#Requires -Version 7.2

# Demo-ReadAnsiPause.ps1
# Exercises Read-AnsiPause. Interactive: it waits for your keys.
# Run: pwsh -File .\demo\Demo-ReadAnsiPause.ps1
#
# Any key continues · Esc returns $false · a -TimeoutSeconds pause returns $null
# when it expires.

$ErrorActionPreference = 'Stop'
$srcRoot = Join-Path (Split-Path -Parent $PSScriptRoot) 'src'

Import-Module (Join-Path $srcRoot 'Read-AnsiPause.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $srcRoot 'Format-AnsiGrid.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $srcRoot 'Format-AnsiPanel.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $srcRoot 'Format-AnsiRule.psm1') -Force -DisableNameChecking
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
    $shown = if ($null -eq $Value) { '[BrightBlack]<Null — timed out>[/]' }
    elseif ($Value) { '[BrightGreen]Continued[/]' }
    else { '[BrightRed]Cancelled (esc)[/]' }
    Format-AnsiGrid @(, @("[DarkGray]$Label[/]", $shown)) -Padding 2 | Out-AnsiHost
}

# 1. The default: any key continues, and the message erases itself
Show-DemoHeader '1. Any key continues (the message erases itself)'
$any = Read-AnsiPause
Show-Answer 'Pause' $any

# 2. -Enter waits for Enter specifically
Show-DemoHeader '2. -Enter (other keys are ignored)'
$entered = Read-AnsiPause -Enter
Show-Answer 'Pause' $entered

# 3. A custom message, with markup
Show-DemoHeader '3. A custom message with markup'
$custom = Read-AnsiPause '[bold]Review the plan above[/], then press a key'
Show-Answer 'Pause' $custom

# 4. -Markdown sugar and emoji
Show-DemoHeader '4. -Markdown in the message'
$md = Read-AnsiPause ':warn: **Stop and read this**, then continue' -Markdown -MessageColor BrightYellow
Show-Answer 'Pause' $md

# 5. -KeepMessage leaves the row on screen
Show-DemoHeader '5. -KeepMessage (the row stays)'
$kept = Read-AnsiPause 'This line stays after the key' -KeepMessage
Show-Answer 'Pause' $kept

# 6. A timeout — wait it out to see $null
Show-DemoHeader '6. -TimeoutSeconds 5'
$timed = Read-AnsiPause 'Waiting for you' -TimeoutSeconds 5
Show-Answer 'Pause' $timed

# 7. A countdown that ticks in place
Show-DemoHeader '7. -TimeoutSeconds 5 -ShowCountdown'
$counted = Read-AnsiPause 'Continuing shortly' -TimeoutSeconds 5 -ShowCountdown
Show-Answer 'Pause' $counted

# 8. Esc means "do not carry on"
Show-DemoHeader '8. Press Esc to cancel'
$cancelled = Read-AnsiPause 'Press esc to stop here'
Show-Answer 'Pause' $cancelled

# 9. Usage pattern — page through renderings
Show-DemoHeader '9. Usage pattern — page through output'
foreach ($page in 1..2) {
    Format-AnsiRule "page $page of 2" -Color BrightWhite -LineColor DarkGray | Out-AnsiHost
    Format-AnsiPanel "content of page $page" -Border Square -BorderColor DarkGray | Out-AnsiHost
    if ($page -lt 2) {
        if (-not (Read-AnsiPause 'Next page' -Enter)) { break }
    }
}

# 10. Usage pattern — a last look before something destructive
Show-DemoHeader '10. Usage pattern — a last look before acting'
Format-AnsiPanel @('About to delete 42 files', 'from C:\temp\build') `
    -Title '[bold BrightRed]Review[/]' -Border Heavy -BorderColor BrightRed | Out-AnsiHost
if (Read-AnsiPause 'Press a key to proceed, esc to abort' -MessageColor BrightRed) {
    Format-AnsiPanel 'Proceeding' -Border Square -BorderColor BrightGreen | Out-AnsiHost
} else {
    Format-AnsiPanel 'Aborted' -Border Square -BorderColor DarkGray | Out-AnsiHost
}

Show-DemoHeader 'Done'
Write-Host ''
