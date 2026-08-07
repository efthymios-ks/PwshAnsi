#Requires -Version 5.1

<#
.SYNOPSIS
    Checks this machine for what PwshAnsi needs and installs what is missing.

.DESCRIPTION
    PwshAnsi needs PowerShell 7.2+ (for $PSStyle) and, to run its tests,
    Pester 5.x. This script reports what is present, installs what is not, and
    verifies the result. It is deliberately runnable from Windows PowerShell 5.1 —
    that is the shell you are in when PowerShell 7 is the thing missing — so it
    avoids 7.x-only syntax and $PSStyle throughout.

    Nothing is installed without confirmation: it supports -WhatIf and -Confirm,
    and -Force answers yes.

    Installing PowerShell 7 tries winget first, then the MSI from the official
    GitHub release. On Linux and macOS it prints the command for the platform
    rather than guessing at a package manager.

    Exit codes:
      0  everything PwshAnsi needs is present
      1  something failed
      2  a prerequisite is still missing (declined, -WhatIf, or manual step needed)

.PARAMETER SkipPowerShell
    Do not install PowerShell 7, only report on it.

.PARAMETER SkipPester
    Do not install Pester 5.x, only report on it.

.PARAMETER SkipSmokeTest
    Do not render a line with PwshAnsi at the end.

.PARAMETER MinimumPowerShellVersion
    The lowest acceptable PowerShell version. Default 7.2.0.

.PARAMETER Force
    Install without asking.

.EXAMPLE
    .\Install-AnsiPrerequisite.ps1

.EXAMPLE
    .\Install-AnsiPrerequisite.ps1 -WhatIf

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Install-AnsiPrerequisite.ps1 -Force
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [switch]$SkipPowerShell,

    [switch]$SkipPester,

    [switch]$SkipSmokeTest,

    [version]$MinimumPowerShellVersion = [version]'7.2.0',

    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:MinimumPesterVersion = [version]'5.0.0'
$script:InstallPesterVersion = '5.5.0'
$script:Outstanding = New-Object System.Collections.Generic.List[string]

# --- reporting -----------------------------------------------------------------
# No $PSStyle here: this script has to read correctly under Windows PowerShell 5.1.

function Write-Step {
    param([Parameter(Mandatory)][string]$Message)
    Write-Host ''
    Write-Host "== $Message" -ForegroundColor Cyan
}

function Write-Good {
    param([Parameter(Mandatory)][string]$Message)
    Write-Host "   [ok]   $Message" -ForegroundColor Green
}

function Write-Miss {
    param([Parameter(Mandatory)][string]$Message)
    Write-Host "   [need] $Message" -ForegroundColor Yellow
}

function Write-Bad {
    param([Parameter(Mandatory)][string]$Message)
    Write-Host "   [fail] $Message" -ForegroundColor Red
}

function Write-Note {
    param([Parameter(Mandatory)][string]$Message)
    Write-Host "          $Message" -ForegroundColor DarkGray
}

# --- discovery -----------------------------------------------------------------

function Test-Windows {
    if ($PSVersionTable.PSVersion.Major -lt 6) { return $true }
    return [bool]$IsWindows
}

function Get-CommandPath {
    param([Parameter(Mandatory)][string]$Name)
    $found = Get-Command -Name $Name -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($found) { return $found.Source }
    return $null
}

# pwsh may be installed but not on PATH yet in this session, so look where the
# installers put it as well.
function Get-PwshCandidate {
    $candidates = New-Object System.Collections.Generic.List[string]

    $onPath = Get-CommandPath -Name 'pwsh'
    if ($onPath) { $null = $candidates.Add($onPath) }

    if (Test-Windows) {
        foreach ($root in @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:LOCALAPPDATA)) {
            if (-not $root) { continue }
            $pattern = Join-Path $root 'PowerShell\*\pwsh.exe'
            foreach ($item in (Get-ChildItem -Path $pattern -ErrorAction SilentlyContinue)) {
                $null = $candidates.Add($item.FullName)
            }
        }
    } else {
        foreach ($path in @('/usr/bin/pwsh', '/usr/local/bin/pwsh', '/opt/microsoft/powershell/7/pwsh')) {
            if (Test-Path -LiteralPath $path) { $null = $candidates.Add($path) }
        }
    }

    $best = $null
    $bestVersion = [version]'0.0'
    foreach ($candidate in $candidates) {
        $version = Get-PwshVersion -Path $candidate
        if ($null -ne $version -and $version -gt $bestVersion) {
            $best = $candidate
            $bestVersion = $version
        }
    }
    if (-not $best) { return $null }
    return [PSCustomObject]@{ Path = $best; Version = $bestVersion }
}

function Get-PwshVersion {
    param([Parameter(Mandatory)][string]$Path)
    try {
        $raw = & $Path -NoProfile -NoLogo -Command '$PSVersionTable.PSVersion.ToString()' 2>$null
        if ($LASTEXITCODE -ne 0 -or -not $raw) { return $null }
        return [version]([string]$raw).Trim()
    } catch {
        return $null
    }
}

# --- PowerShell 7 --------------------------------------------------------------

function Install-PowerShellWithWinget {
    $winget = Get-CommandPath -Name 'winget'
    if (-not $winget) {
        Write-Note 'winget is not available'
        return $false
    }

    Write-Note "installing with winget: $winget"
    & $winget install --id Microsoft.PowerShell --source winget --accept-source-agreements --accept-package-agreements
    if ($LASTEXITCODE -ne 0) {
        Write-Note "winget exited with $LASTEXITCODE"
        return $false
    }
    return $true
}

function Install-PowerShellWithMsi {
    $release = $null
    try {
        # The official release feed; -UseBasicParsing keeps this working on 5.1.
        $release = Invoke-RestMethod -Uri 'https://api.github.com/repos/PowerShell/PowerShell/releases/latest' `
            -Headers @{ 'User-Agent' = 'PwshAnsi-setup' } -UseBasicParsing
    } catch {
        Write-Note "could not reach the PowerShell release feed: $($_.Exception.Message)"
        return $false
    }

    $architecture = if ([Environment]::Is64BitOperatingSystem) { 'x64' } else { 'x86' }
    $asset = $release.assets |
        Where-Object { $_.name -like "*win-$architecture.msi" } |
        Select-Object -First 1
    if (-not $asset) {
        Write-Note "no win-$architecture MSI in $($release.tag_name)"
        return $false
    }

    $msi = Join-Path ([System.IO.Path]::GetTempPath()) $asset.name
    Write-Note "downloading $($asset.name)"
    try {
        Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $msi -UseBasicParsing
    } catch {
        Write-Note "download failed: $($_.Exception.Message)"
        return $false
    }

    Write-Note 'running msiexec (a UAC prompt may appear)'
    $process = Start-Process -FilePath 'msiexec.exe' `
        -ArgumentList @('/i', "`"$msi`"", '/qb', 'ADD_PATH=1') -Wait -PassThru
    Remove-Item -LiteralPath $msi -ErrorAction SilentlyContinue

    if ($process.ExitCode -ne 0) {
        Write-Note "msiexec exited with $($process.ExitCode)"
        return $false
    }
    return $true
}

function Install-PowerShellCore {
    if (-not (Test-Windows)) {
        Write-Note 'on Linux and macOS install it with your package manager, for example:'
        Write-Note '  sudo apt-get install -y powershell        # Debian/Ubuntu, after adding the MS repo'
        Write-Note '  brew install --cask powershell            # macOS'
        Write-Note '  https://aka.ms/powershell-release?tag=stable'
        return $false
    }

    if (Install-PowerShellWithWinget) { return $true }
    Write-Note 'falling back to the MSI'
    return (Install-PowerShellWithMsi)
}

function Resolve-PowerShell {
    Write-Step "PowerShell $MinimumPowerShellVersion or newer"

    $current = $PSVersionTable.PSVersion
    Write-Note "this shell: $($PSVersionTable.PSEdition) $current"

    if ($current -ge $MinimumPowerShellVersion) {
        Write-Good "already running PowerShell $current"
        return $true
    }

    $existing = Get-PwshCandidate
    if ($null -ne $existing -and $existing.Version -ge $MinimumPowerShellVersion) {
        Write-Good "PowerShell $($existing.Version) is installed at $($existing.Path)"
        Write-Note 'run PwshAnsi with that pwsh, not this shell'
        return $true
    }

    if ($SkipPowerShell) {
        Write-Miss 'PowerShell 7 is missing (-SkipPowerShell, not installing)'
        $null = $script:Outstanding.Add('PowerShell 7.2+')
        return $false
    }

    Write-Miss 'PowerShell 7 is missing'
    if (-not ($Force -or $PSCmdlet.ShouldProcess('this machine', 'Install PowerShell 7'))) {
        Write-Note 'declined — nothing was installed'
        $null = $script:Outstanding.Add('PowerShell 7.2+')
        return $false
    }

    if (-not (Install-PowerShellCore)) {
        Write-Bad 'could not install PowerShell 7'
        $null = $script:Outstanding.Add('PowerShell 7.2+')
        return $false
    }

    $installed = Get-PwshCandidate
    if ($null -eq $installed -or $installed.Version -lt $MinimumPowerShellVersion) {
        Write-Miss 'installed, but pwsh is not visible from this session yet'
        Write-Note 'open a new terminal so PATH is refreshed, then run this script again'
        $null = $script:Outstanding.Add('PowerShell 7.2+ (restart the terminal)')
        return $false
    }

    Write-Good "installed PowerShell $($installed.Version) at $($installed.Path)"
    return $true
}

# --- Pester --------------------------------------------------------------------

function Get-PesterModule {
    param([Parameter(Mandatory)][string]$PwshPath)

    # Ask the target pwsh, not this shell: module paths differ between editions.
    $raw = & $PwshPath -NoProfile -NoLogo -Command @'
$m = Get-Module -ListAvailable -Name Pester |
    Where-Object { $_.Version -ge [version]'5.0.0' -and $_.Version -lt [version]'6.0.0' } |
    Sort-Object Version -Descending |
    Select-Object -First 1
if ($m) { $m.Version.ToString() }
'@ 2>$null
    if (-not $raw) { return $null }
    return [version]([string]$raw).Trim()
}

function Resolve-Pester {
    param([Parameter(Mandatory)][string]$PwshPath)

    Write-Step 'Pester 5.x (only needed to run the tests)'

    $existing = Get-PesterModule -PwshPath $PwshPath
    if ($null -ne $existing) {
        Write-Good "Pester $existing is available to $PwshPath"
        return $true
    }

    if ($SkipPester) {
        Write-Miss 'Pester 5.x is missing (-SkipPester, not installing)'
        $null = $script:Outstanding.Add('Pester 5.x')
        return $false
    }

    Write-Miss 'Pester 5.x is missing'
    if (-not ($Force -or $PSCmdlet.ShouldProcess('the current user', 'Install Pester 5.x'))) {
        Write-Note 'declined — nothing was installed'
        $null = $script:Outstanding.Add('Pester 5.x')
        return $false
    }

    $install = @"
Install-Module -Name Pester -Scope CurrentUser -MinimumVersion $script:InstallPesterVersion ``
    -MaximumVersion '5.99.99' -Force -SkipPublisherCheck -AllowClobber -ErrorAction Stop
"@
    & $PwshPath -NoProfile -NoLogo -Command $install
    if ($LASTEXITCODE -ne 0) {
        Write-Bad 'Install-Module failed'
        $null = $script:Outstanding.Add('Pester 5.x')
        return $false
    }

    $installed = Get-PesterModule -PwshPath $PwshPath
    if ($null -eq $installed) {
        Write-Bad 'Pester still not visible after installing'
        $null = $script:Outstanding.Add('Pester 5.x')
        return $false
    }

    Write-Good "installed Pester $installed"
    return $true
}

# --- smoke test ----------------------------------------------------------------

function Test-AnsiRenders {
    param([Parameter(Mandatory)][string]$PwshPath)

    Write-Step 'rendering a line with PwshAnsi'

    $srcRoot = Join-Path $PSScriptRoot 'src'
    if (-not (Test-Path -LiteralPath $srcRoot)) {
        Write-Miss "no src folder next to this script ($srcRoot)"
        return $false
    }

    $smoke = @"
Import-Module (Join-Path '$srcRoot' 'Format-AnsiText.psm1') -Force -DisableNameChecking
Import-Module (Join-Path '$srcRoot' 'Out-AnsiHost.psm1') -Force -DisableNameChecking
Format-AnsiText '[bold BrightGreen]PwshAnsi is ready.[/]' | Out-AnsiHost
"@
    & $PwshPath -NoProfile -NoLogo -Command $smoke
    if ($LASTEXITCODE -ne 0) {
        Write-Bad 'PwshAnsi could not render'
        return $false
    }

    Write-Good 'PwshAnsi rendered without errors'
    return $true
}

# --- run -----------------------------------------------------------------------

Write-Host ''
Write-Host 'PwshAnsi setup' -ForegroundColor White
Write-Note "repo: $PSScriptRoot"

$powerShellOk = Resolve-PowerShell

$pwshPath = $null
if ($powerShellOk) {
    if ($PSVersionTable.PSVersion -ge $MinimumPowerShellVersion) {
        $pwshPath = (Get-Process -Id $PID).Path
        if (-not $pwshPath) { $pwshPath = 'pwsh' }
    } else {
        $candidate = Get-PwshCandidate
        if ($null -ne $candidate) { $pwshPath = $candidate.Path }
    }
}

if ($pwshPath) {
    $null = Resolve-Pester -PwshPath $pwshPath
    if (-not $SkipSmokeTest) { $null = Test-AnsiRenders -PwshPath $pwshPath }
} else {
    Write-Step 'Pester 5.x (only needed to run the tests)'
    Write-Note 'skipped: PowerShell 7 has to be in place first'
}

Write-Host ''
if ($script:Outstanding.Count -eq 0) {
    Write-Host 'Everything PwshAnsi needs is in place.' -ForegroundColor Green
    Write-Note 'run the tests: pwsh -File .\Invoke-Test.ps1'
    Write-Note 'try a demo:    pwsh -File .\demo\Demo-AnsiTable.ps1'
    Write-Host ''
    exit 0
}

Write-Host 'Still missing:' -ForegroundColor Yellow
foreach ($item in $script:Outstanding) { Write-Host "  - $item" -ForegroundColor Yellow }
Write-Host ''
exit 2
