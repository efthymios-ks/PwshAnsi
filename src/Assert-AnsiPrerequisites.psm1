#Requires -Version 5.1
<#
    Assert-Pwsh7 — guarantee the calling script runs under PowerShell 7.

    Works from Windows PowerShell 5.1. Import this module before any PwshAnsi calls,
    then call Assert-Pwsh7 as the first line of your script:

        Import-Module "$PSScriptRoot\<path-to>\Assert-AnsiPrerequisites.psm1" -Force
        Assert-Pwsh7 -Arguments $PSBoundParameters
#>

function Assert-Pwsh7 {
    <#
    .SYNOPSIS
        Guarantees the calling script runs under PowerShell 7.

    .DESCRIPTION
        Returns immediately when already on pwsh 7+. Otherwise locates pwsh.exe, installs it
        when missing (winget, else the official https://aka.ms/install-powershell.ps1 MSI),
        then re-executes the calling script under pwsh with the same arguments and exits the
        current (5.1) process with the child's exit code - so nothing after the call runs twice.

        Nothing is prompted: a missing PowerShell 7 is installed silently.

    .PARAMETER Arguments
        The caller's $PSBoundParameters, forwarded to the relaunched script.

    .PARAMETER ScriptPath
        Script to relaunch. Defaults to the script that called this function.

    .EXAMPLE
        Assert-Pwsh7 -Arguments $PSBoundParameters
    #>
    [CmdletBinding()]
    param(
        [hashtable]$Arguments = @{},
        [string]$ScriptPath
    )

    if ($PSVersionTable.PSVersion.Major -ge 7) { return }

    # $PSCommandPath inside a module points at the module, so walk out to the caller's script.
    if (-not $ScriptPath) {
        $ScriptPath = Get-PSCallStack |
            Select-Object -Skip 1 -ExpandProperty ScriptName -ErrorAction SilentlyContinue |
            Where-Object { $_ -and $_ -ne $PSCommandPath } |
            Select-Object -First 1
    }
    if (-not $ScriptPath -or -not (Test-Path $ScriptPath)) {
        throw 'Assert-Pwsh7: cannot determine the script to relaunch. Pass -ScriptPath.'
    }

    # PATH first, then the standard install locations - a fresh install is not on the PATH
    # of an already-running session.
    $findPwsh = {
        $cmd = Get-Command pwsh.exe -ErrorAction SilentlyContinue
        if ($cmd) { return $cmd.Source }
        foreach ($c in @(
                (Join-Path $env:ProgramFiles 'PowerShell\7\pwsh.exe')
                (Join-Path ${env:ProgramFiles(x86)} 'PowerShell\7\pwsh.exe')
                (Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\pwsh.exe')
            )) {
            if ($c -and (Test-Path $c)) { return $c }
        }
        return $null
    }

    $pwshPath = & $findPwsh
    if (-not $pwshPath) {
        Write-Host ''
        Write-Host "PowerShell 7 is required - this session is $($PSVersionTable.PSVersion). Installing it..." -ForegroundColor Yellow

        $installed = $false
        if (Get-Command winget -ErrorAction SilentlyContinue) {
            Write-Host 'Installing PowerShell 7 via winget...' -ForegroundColor White
            winget install --id Microsoft.PowerShell --source winget --exact `
                --accept-package-agreements --accept-source-agreements --silent
            if ($LASTEXITCODE -eq 0 -and (& $findPwsh)) { $installed = $true }
            else { Write-Warning "winget install returned $LASTEXITCODE - falling back to the MSI installer." }
        }

        if (-not $installed) {
            Write-Host 'Installing PowerShell 7 from https://aka.ms/install-powershell.ps1 ...' -ForegroundColor White
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            $bootstrap = Join-Path $env:TEMP 'install-powershell.ps1'
            Invoke-WebRequest -Uri 'https://aka.ms/install-powershell.ps1' -OutFile $bootstrap -UseBasicParsing
            & $bootstrap -UseMSI -Quiet
            Remove-Item $bootstrap -Force -ErrorAction SilentlyContinue
        }

        $pwshPath = & $findPwsh
        if (-not $pwshPath) { throw 'PowerShell 7 still not found after installing. Install it manually and re-run.' }
        Write-Host "PowerShell 7 installed: $pwshPath" -ForegroundColor Green
    }

    $forward = @()
    foreach ($entry in $Arguments.GetEnumerator()) {
        if ($entry.Value -is [switch]) {
            if ($entry.Value.IsPresent) { $forward += "-$($entry.Key)" }
        } elseif ($entry.Value -is [array]) {
            $forward += "-$($entry.Key)"
            $forward += ($entry.Value | ForEach-Object { [string]$_ })
        } else {
            $forward += "-$($entry.Key)"
            $forward += [string]$entry.Value
        }
    }

    Write-Host "Relaunching under PowerShell 7: $pwshPath" -ForegroundColor DarkGray
    & $pwshPath -NoProfile -ExecutionPolicy Bypass -File $ScriptPath @forward
    exit $LASTEXITCODE
}

Export-ModuleMember -Function Assert-Pwsh7
