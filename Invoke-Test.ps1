#Requires -Version 7.2

<#
.SYNOPSIS
    Runs every Pester test in the tests folder and fails if any test fails.

.DESCRIPTION
    Discovers *.Tests.ps1 under -Path (default: ./tests), runs them with
    Pester 5, and exits non-zero when anything fails, errors, or when no test
    is discovered at all. Intended for both local use and CI.

    Exit codes:
      0  all tests passed
      1  one or more tests failed
      2  no tests were discovered
      3  Pester 5 is unavailable and could not be installed

.PARAMETER Path
    Folder or file to run. Defaults to the tests folder beside this script.

.PARAMETER Output
    Pester output verbosity: None, Normal, Detailed, Diagnostic. Default Detailed.

.PARAMETER TestName
    Only run tests whose full name matches this wildcard pattern.

.PARAMETER Tag
    Only run tests carrying one of these tags.

.PARAMETER ResultPath
    Write NUnit XML test results to this path.

.PARAMETER SkipInstall
    Do not attempt to install Pester when it is missing; fail instead.

.INPUTS
    None.

.OUTPUTS
    None. Progress and the summary go to the host; the verdict is the exit code.

.EXAMPLE
    ./Invoke-Test.ps1

.EXAMPLE
    ./Invoke-Test.ps1 -Output Normal -ResultPath ./testResults.xml

.EXAMPLE
    ./Invoke-Test.ps1 -TestName '*-Overflow*'
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateNotNullOrEmpty()]
    [string]$Path = (Join-Path -Path $PSScriptRoot -ChildPath 'tests'),

    [ValidateSet('None', 'Normal', 'Detailed', 'Diagnostic')]
    [string]$Output = 'Detailed',

    [ValidateNotNullOrEmpty()]
    [string]$TestName,

    [ValidateNotNullOrEmpty()]
    [string[]]$Tag,

    [ValidateNotNullOrEmpty()]
    [string]$ResultPath,

    [switch]$SkipInstall
)

begin {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    $script:MinimumPesterVersion = [version]'5.0.0'
    $script:NextMajorPesterVersion = [version]'6.0.0'
    $script:InstallPesterVersion = '5.5.0'

    function Get-PesterModule {
        <#
        .SYNOPSIS
            Returns the newest installed Pester 5.x module, or nothing.
        #>
        [CmdletBinding()]
        [OutputType([System.Management.Automation.PSModuleInfo])]
        param()

        Get-Module -ListAvailable -Name Pester |
            Where-Object {
                $_.Version -ge $script:MinimumPesterVersion -and
                $_.Version -lt $script:NextMajorPesterVersion
            } |
            Sort-Object -Property Version -Descending |
            Select-Object -First 1
    }

    function Write-Failure {
        <#
        .SYNOPSIS
            Reports a failure to the host and ends the run with an exit code.
        .DESCRIPTION
            Write-Error is avoided on purpose: under ErrorActionPreference =
            Stop it terminates the script before `exit`, and the exit code
            would no longer say why the run stopped.
        #>
        [CmdletBinding()]
        [OutputType([void])]
        param(
            [Parameter(Mandatory, Position = 0)]
            [ValidateNotNullOrEmpty()]
            [string]$Message,

            [Parameter(Mandatory, Position = 1)]
            [ValidateRange(1, 255)]
            [int]$ExitCode
        )

        Write-Host "ERROR: $Message" -ForegroundColor Red
        exit $ExitCode
    }
}

process {
    $pesterModule = Get-PesterModule

    if (-not $pesterModule) {
        if ($SkipInstall) {
            Write-Failure "Pester 5.x is not installed. Run: Install-Module Pester -Scope CurrentUser -MinimumVersion $script:InstallPesterVersion -Force -SkipPublisherCheck" 3
        }

        Write-Host 'Pester 5.x not found — installing for the current user...' -ForegroundColor Yellow
        try {
            Install-Module -Name Pester -Scope CurrentUser `
                -MinimumVersion $script:InstallPesterVersion -MaximumVersion '5.99.99' `
                -Force -SkipPublisherCheck -AllowClobber -ErrorAction Stop
        } catch {
            Write-Failure "Failed to install Pester 5.x: $($_.Exception.Message)" 3
        }

        $pesterModule = Get-PesterModule
        if (-not $pesterModule) {
            Write-Failure 'Pester 5.x is still unavailable after installation.' 3
        }
    }

    # Drop the Windows-bundled Pester 3 if it got loaded first, then pin to 5.x.
    Get-Module -Name Pester |
        Where-Object { $_.Version -lt $script:MinimumPesterVersion } |
        Remove-Module -Force

    Import-Module -Name $pesterModule.Path -Force

    if (-not (Test-Path -LiteralPath $Path)) {
        Write-Failure "Test path not found: $Path" 2
    }

    $configuration = New-PesterConfiguration
    $configuration.Run.Path = $Path
    $configuration.Run.PassThru = $true
    $configuration.Run.Exit = $false
    $configuration.Output.Verbosity = $Output

    if ($PSBoundParameters.ContainsKey('TestName')) { $configuration.Filter.FullName = $TestName }
    if ($PSBoundParameters.ContainsKey('Tag')) { $configuration.Filter.Tag = $Tag }

    if ($PSBoundParameters.ContainsKey('ResultPath')) {
        $configuration.TestResult.Enabled = $true
        $configuration.TestResult.OutputPath = $ResultPath
        $configuration.TestResult.OutputFormat = 'NUnitXml'
    }

    Write-Host "Pester $($pesterModule.Version) — running tests in $Path" -ForegroundColor Cyan

    try {
        $result = Invoke-Pester -Configuration $configuration
    } catch {
        Write-Failure "Pester run failed: $($_.Exception.Message)" 1
    }

    if (-not $result) {
        Write-Failure "No tests were discovered under $Path." 2
    }

    $total = $result.PassedCount + $result.FailedCount + $result.SkippedCount + $result.NotRunCount

    Write-Host ''
    Write-Host ('Passed: {0}  Failed: {1}  Skipped: {2}  Duration: {3:n2}s' -f
        $result.PassedCount, $result.FailedCount, $result.SkippedCount, $result.Duration.TotalSeconds) `
        -ForegroundColor $(if ($result.FailedCount -gt 0) { 'Red' } else { 'Green' })

    if ($total -eq 0) {
        Write-Failure "No tests were discovered under $Path." 2
    }

    if ($result.FailedCount -gt 0 -or $result.FailedBlocksCount -gt 0 -or $result.FailedContainersCount -gt 0) {
        Write-Host 'TESTS FAILED' -ForegroundColor Red
        exit 1
    }

    Write-Host 'ALL TESTS PASSED' -ForegroundColor Green
    exit 0
}
