#Requires -Version 5.1
# Assert-PwshAnsi.psm1
# Must stay Windows PowerShell 5.1 syntax throughout.
# Exports only Assert-PwshAnsi; all other functions are internal helpers.

$script:AnsiMinPwsh  = [version]'7.2'
$script:AnsiRerunVar = 'PWSHANSI_RERUN'

function ConvertTo-AnsiEncodedCommand {
    param([Parameter(Mandatory)][string]$Command)
    return [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($Command))
}

function ConvertTo-AnsiVersion {
    param($Value)
    if (-not $Value) { return $null }
    $match = [regex]::Match([string]$Value, '^v?(\d+)\.(\d+)\.(\d+)')
    if (-not $match.Success) { return $null }
    return [version]('{0}.{1}.{2}' -f $match.Groups[1].Value, $match.Groups[2].Value, $match.Groups[3].Value)
}

# Yellow: an action that changes the system. DarkYellow (orange): its outcome or a skip.
function Write-AnsiLog {
    param([Parameter(Mandatory)][string]$Message, [switch]$Outcome)
    $color = 'Yellow'
    if ($Outcome) { $color = 'DarkYellow' }
    Write-Host "[PwshAnsi] $Message" -ForegroundColor $color
}

function Enable-AnsiTls12 {
    [Net.ServicePointManager]::SecurityProtocol =
        [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
}

# Version of a pwsh executable: file version first (no process start), then a probe.
function Get-AnsiPwshVersion {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try { $version = ConvertTo-AnsiVersion (Get-Item -LiteralPath $Path).VersionInfo.FileVersion } catch { $version = $null }
    if ($version) { return $version }
    $probe = ConvertTo-AnsiEncodedCommand '[string]$PSVersionTable.PSVersion'
    try { return ConvertTo-AnsiVersion (& $Path -NoProfile -NonInteractive -EncodedCommand $probe 2>$null | Select-Object -Last 1) }
    catch { return $null }
}

# Newest pwsh on this machine at or above the minimum, as @{ Path; Version }, or $null.
function Find-AnsiPwsh {
    $candidates = @(Get-Command pwsh -CommandType Application -All -ErrorAction SilentlyContinue |
        Select-Object -ExpandProperty Source)
    if ($env:ProgramFiles) { $candidates += Join-Path $env:ProgramFiles 'PowerShell\7\pwsh.exe' }
    if ($env:LOCALAPPDATA) { $candidates += Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\pwsh.exe' }

    $best = $null
    foreach ($path in ($candidates | Select-Object -Unique)) {
        $version = Get-AnsiPwshVersion -Path $path
        if (-not $version) { continue }
        if ($version -lt $script:AnsiMinPwsh) { continue }
        if ($best -and $version -le $best.Version) { continue }
        $best = [pscustomobject]@{ Path = $path; Version = $version }
    }
    return $best
}

# Latest stable pwsh release. Throws when it cannot be checked.
function Get-AnsiLatestPwshVersion {
    Enable-AnsiTls12
    $info = Invoke-RestMethod -Uri 'https://aka.ms/pwsh-buildinfo-stable' -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
    return [version]([string]$info.ReleaseTag).TrimStart('v')
}

function Test-AnsiElevated {
    $identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal $identity
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Installs pwsh from the official MSI: Program Files, PATH, Start menu, and Microsoft Update.
# Only msiexec is elevated (one UAC prompt), never the script itself.
# Restart Manager stays on: other open pwsh windows are closed gracefully, never the PC rebooted.
function Install-AnsiPwsh {
    param([Parameter(Mandatory)][version]$Version)
    $arch = $env:PROCESSOR_ARCHITEW6432
    if (-not $arch) { $arch = $env:PROCESSOR_ARCHITECTURE }
    $arch = switch ($arch) { 'ARM64' { 'arm64' } 'x86' { 'x86' } default { 'x64' } }

    $name = "PowerShell-$Version-win-$arch.msi"
    $url  = "https://github.com/PowerShell/PowerShell/releases/download/v$Version/$name"
    $msi  = Join-Path ([IO.Path]::GetTempPath()) $name
    $arguments = @('/i', "`"$msi`"", '/quiet', '/norestart', 'ADD_PATH=1', 'USE_MU=1', 'ENABLE_MU=1')

    Enable-AnsiTls12
    try {
        Write-AnsiLog "Downloading $name..."
        Invoke-WebRequest -Uri $url -OutFile $msi -UseBasicParsing -ErrorAction Stop

        $start = @{ FilePath = 'msiexec.exe'; ArgumentList = $arguments; Wait = $true; PassThru = $true }
        if (Test-AnsiElevated) { Write-AnsiLog "Running the PowerShell $Version installer..." }
        else {
            Write-AnsiLog "Requesting administrator rights to install PowerShell $Version (UAC)..."
            $start.Verb = 'RunAs'
        }
        $process = Start-Process @start -ErrorAction Stop
        if ($process.ExitCode -notin 0, 3010) { throw "msiexec exited with $($process.ExitCode)." }
        if ($process.ExitCode -eq 3010) { Write-AnsiLog "PowerShell $Version installed; a reboot is needed to finish." -Outcome }
        else { Write-AnsiLog "PowerShell $Version installed." -Outcome }
    }
    finally { Remove-Item -LiteralPath $msi -Force -ErrorAction SilentlyContinue }
}

function Test-AnsiRerunStage {
    param([Parameter(Mandatory)][string]$Stage)
    $done = (Get-Item -Path "env:$($script:AnsiRerunVar)" -ErrorAction SilentlyContinue).Value
    if (-not $done) { return $false }
    return ($done -split ',') -contains $Stage
}

function ConvertTo-AnsiPortableArgument {
    param([hashtable]$Arguments = @{})
    $bound = @{}
    foreach ($key in $Arguments.Keys) {
        $value = $Arguments[$key]
        if ($value -is [System.Management.Automation.SwitchParameter]) { $value = $value.IsPresent }
        $bound[$key] = $value
    }
    return $bound
}

function Invoke-AnsiRerun {
    param(
        [Parameter(Mandatory)][string]$Pwsh,
        [Parameter(Mandatory)][string]$ScriptPath,
        [Parameter(Mandatory)][string]$Stage,
        [hashtable]$Arguments = @{},
        [switch]$PauseOnExit
    )
    $bound  = ConvertTo-AnsiPortableArgument $Arguments
    $clixml = Join-Path ([IO.Path]::GetTempPath()) ('PwshAnsi-{0}.clixml' -f [guid]::NewGuid())
    $bound | Export-Clixml -LiteralPath $clixml

    $quote   = { param($s) "'" + ($s -replace "'", "''") + "'" }
    $command = @(
        "`$p = Import-Clixml -LiteralPath $(& $quote $clixml)"
        "Remove-Item -LiteralPath $(& $quote $clixml) -Force"
        "& $(& $quote $ScriptPath) @p"
        'exit $LASTEXITCODE'
    ) -join "`n"

    $reason = 'to load the new PwshAnsi'
    if ($Stage -eq 'pwsh') { $reason = "in $Pwsh" }
    Write-AnsiLog "Restarting the script $reason..." -Outcome

    $done = (Get-Item -Path "env:$($script:AnsiRerunVar)" -ErrorAction SilentlyContinue).Value
    Set-Item -Path "env:$($script:AnsiRerunVar)" -Value ((@($done, $Stage) | Where-Object { $_ }) -join ',')
    & $Pwsh -NoProfile -ExecutionPolicy Bypass -EncodedCommand (ConvertTo-AnsiEncodedCommand $command)
    $code = $LASTEXITCODE
    if ($PauseOnExit) { $null = Read-Host 'Press Enter to close' }
    exit $code
}

# Returns the path to a pwsh 7.2+ to rerun under, or $null when the current host already qualifies.
# Only installs when no pwsh 7.2+ is found at all; never updates an existing installation.
function Update-AnsiPwsh {
    if ($PSVersionTable.PSVersion -ge $script:AnsiMinPwsh) { return $null }

    $current = Find-AnsiPwsh
    if ($current) { return $current.Path }

    try {
        $latest = Get-AnsiLatestPwshVersion
        Write-AnsiLog "PowerShell $($script:AnsiMinPwsh)+ not found. Installing PowerShell $latest..."
        Install-AnsiPwsh -Version $latest
        $installed = Find-AnsiPwsh
        if (-not $installed) { throw "PowerShell $latest was installed but cannot be found." }
        return $installed.Path
    }
    catch {
        throw "PowerShell $($script:AnsiMinPwsh)+ is missing and could not be installed: $($_.Exception.Message)"
    }
}

# $true when a newer PwshAnsi was installed and the script must rerun to load it.
# Update failures log a yellow warning and return $false; they never throw.
function Update-PwshAnsiModule {
    param([Parameter(Mandatory)][version]$Current)
    if (Test-AnsiRerunStage 'module') { return $false }

    $latest = $null
    try {
        $latest = [version](Find-Module PwshAnsi -ErrorAction Stop).Version
        if ($latest -le $Current) { return $false }

        Write-AnsiLog "Updating PwshAnsi $Current -> $latest..."
        Install-Module PwshAnsi -RequiredVersion $latest -Scope CurrentUser -Force -ErrorAction Stop
        Write-AnsiLog "PwshAnsi $latest installed." -Outcome
        return $true
    }
    catch {
        if ($latest -and $latest -gt $Current) {
            Write-AnsiLog "Failed to update PwshAnsi: $($_.Exception.Message) Continuing on $Current."
        }
        return $false
    }
}

function Assert-PwshAnsi {
    <#
    .SYNOPSIS
        Ensures the calling script runs on pwsh 7.2+ with the latest PwshAnsi.
    .DESCRIPTION
        1. If no pwsh 7.2+ is present, installs it and reruns the script there.
        2. Unless -SkipUpdate is set, checks the gallery for a newer PwshAnsi and
           reruns the script to load it when one is found.
        Already on pwsh 7.2+ with the latest PwshAnsi (or -SkipUpdate): returns immediately.
        PwshAnsi gallery check or update fails: logs a warning and continues.
    .EXAMPLE
        Assert-PwshAnsi
    .EXAMPLE
        Assert-PwshAnsi -SkipUpdate
    #>
    [CmdletBinding()]
    param(
        [hashtable]$Arguments,
        [string]$ScriptPath = $MyInvocation.PSCommandPath,
        [switch]$SkipUpdate
    )
    if (-not $ScriptPath) { throw 'Assert-PwshAnsi: call it from a script file, or pass -ScriptPath.' }

    if ($null -eq $Arguments) {
        $Arguments = @{}
        $caller = Get-PSCallStack | Select-Object -Skip 1 -First 1
        if ($caller) {
            $bound = $caller.InvocationInfo.BoundParameters
            foreach ($key in $bound.Keys) { $Arguments[$key] = $bound[$key] }
        }
    }

    $pwsh = Update-AnsiPwsh
    if ($pwsh) { Invoke-AnsiRerun -Pwsh $pwsh -ScriptPath $ScriptPath -Stage 'pwsh' -Arguments $Arguments }

    if ($SkipUpdate) { return }

    $current = $MyInvocation.MyCommand.Module.Version
    if (-not (Update-PwshAnsiModule -Current $current)) { return }
    Invoke-AnsiRerun -Pwsh (Get-Process -Id $PID).Path -ScriptPath $ScriptPath -Stage 'module' -Arguments $Arguments
}

Export-ModuleMember -Function Assert-PwshAnsi
