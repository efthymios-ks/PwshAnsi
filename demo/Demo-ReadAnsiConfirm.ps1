#Requires -Version 7.2

# Demo-ReadAnsiConfirm.ps1
# Exercises Read-AnsiConfirm. Interactive: it waits for your keys.
# Run: pwsh -File .\demo\Demo-ReadAnsiConfirm.ps1
#
# Esc cancels any prompt and returns $null; a -TimeoutSeconds prompt returns $null
# when it expires.

$ErrorActionPreference = 'Stop'
$srcRoot = Join-Path (Split-Path -Parent $PSScriptRoot) 'src'

Import-Module (Join-Path $srcRoot 'Read-AnsiConfirm.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $srcRoot 'Format-AnsiGrid.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $srcRoot 'Format-AnsiPanel.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $srcRoot 'Out-AnsiHost.psm1') -Force -DisableNameChecking

function Show-DemoHeader {
    param([string]$Title)
    Write-Host ''
    Write-Host ('─' * 78) -ForegroundColor DarkGray
    Write-Host " $Title" -ForegroundColor Cyan
    Write-Host ('─' * 78) -ForegroundColor DarkGray
}

function Show-Answer {
    param([string]$Label, [AllowNull()][object]$Value)
    $shown = if ($null -eq $Value) { '[BrightBlack]<Null — cancelled or timed out>[/]' }
    elseif ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
        $joined = (@($Value) -join ', ')
        if ([string]::IsNullOrEmpty($joined)) { '[BrightBlack]<Nothing selected>[/]' } else { "[BrightWhite]$joined[/]" }
    } else { "[BrightWhite]$Value[/]" }
    Format-AnsiGrid @(, @("[DarkGray]$Label[/]", $shown)) -Padding 2 | Out-AnsiHost
}

# 1. Confirm, defaulting to yes
Show-DemoHeader '1. Read-AnsiConfirm — default yes ([Y/n], Enter accepts)'
$deploy = Read-AnsiConfirm 'Deploy now?'
Show-Answer 'Deploy' $deploy

# 2. Confirm, defaulting to no, with messages
Show-DemoHeader '2. -Default $false with -SuccessMessage / -FailureMessage'
$wipe = Read-AnsiConfirm '[bold BrightRed]Delete everything?[/]' -Default $false `
    -SuccessMessage ':warn: Deleting' -FailureMessage ':check: Nothing deleted' -Markdown
Show-Answer 'Wipe' $wipe

# 3. Confirm with no default — only y or n will do
Show-DemoHeader '3. -Default $null (Enter is ignored, [y/n])'
$sure = Read-AnsiConfirm 'Are you sure?' -Default $null
Show-Answer 'Sure' $sure

# 4. Confirm with a timeout
Show-DemoHeader '4. -TimeoutSeconds 5 on a confirm'
$timed = Read-AnsiConfirm 'Continue?' -TimeoutSeconds 5
Show-Answer 'Continue' $timed


# 5. Usage pattern — guard a destructive step
Show-DemoHeader '5. Usage pattern — guard a destructive step'
if (Read-AnsiConfirm '[bold BrightRed]Drop the database?[/]' -Default $false) {
    Format-AnsiPanel 'Dropping…' -Border Heavy -BorderColor BrightRed | Out-AnsiHost
} else {
    Format-AnsiPanel 'Nothing dropped' -Border Square -BorderColor BrightGreen | Out-AnsiHost
}

Show-DemoHeader 'Done'
Write-Host ''
