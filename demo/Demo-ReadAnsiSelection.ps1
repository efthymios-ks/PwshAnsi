#Requires -Version 7.2

# Demo-ReadAnsiSelection.ps1
# Exercises Read-AnsiSelection. Interactive: it waits for your keys.
# Run: pwsh -File .\demo\Demo-ReadAnsiSelection.ps1
#
# ↑↓ (or k/j) move · Home/End jump · PageUp/PageDown page · enter selects ·
# esc cancels and returns $null.

$ErrorActionPreference = 'Stop'
$srcRoot = Join-Path (Split-Path -Parent $PSScriptRoot) 'src'

Import-Module (Join-Path $srcRoot 'Read-AnsiSelection.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $srcRoot 'Format-AnsiGrid.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $srcRoot 'Format-AnsiPanel.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $srcRoot 'Format-AnsiTable.psm1') -Force -DisableNameChecking
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
    $shown = if ($null -eq $Value) { '[BrightBlack]<Null — cancelled or timed out>[/]' } else { "[BrightWhite]$Value[/]" }
    Format-AnsiGrid @(, @("[DarkGray]$Label[/]", $shown)) -Padding 2 | Out-AnsiHost
}

$fruit = @('Apple', 'Banana', 'Cherry', 'Date', 'Elderberry')
$components = @(
    [PSCustomObject]@{ Name = 'Format-AnsiText'; Tests = 147 }
    [PSCustomObject]@{ Name = 'Format-AnsiTable'; Tests = 79 }
    [PSCustomObject]@{ Name = 'Format-AnsiTree'; Tests = 69 }
    [PSCustomObject]@{ Name = 'Format-AnsiPanel'; Tests = 68 }
)

# 1. A short list — arrows move, enter selects
Show-DemoHeader '1. A short list (↑↓ then enter)'
$pick = Read-AnsiSelection 'Pick a fruit' $fruit
Show-Answer 'Fruit' $pick

# 2. Paging — only -PageSize rows are shown, the window scrolls
Show-DemoHeader '2. -PageSize 3 (try End, PageDown)'
$paged = Read-AnsiSelection 'Pick a fruit' $fruit -PageSize 3
Show-Answer 'Fruit' $paged

# 3. Objects — labelled by a property, the object comes back
Show-DemoHeader '3. -LabelProperty (returns the object, not the label)'
$component = Read-AnsiSelection 'Pick a component' $components -LabelProperty Name
if ($null -ne $component) {
    Format-AnsiTable @($component) -Border Square -BorderColor DarkGray -HeaderColor BrightWhite | Out-AnsiHost
} else {
    Show-Answer 'Component' $null
}

# 4. Markup in the title and the labels
Show-DemoHeader '4. Markup / -Markdown in the title and labels'
$env = Read-AnsiSelection '[bold]Environment[/] :rocket:' @(
    '[BrightGreen]Dev[/]'
    '[BrightYellow]Staging[/]'
    '[BrightRed]Production[/]'
) -Markdown
Show-Answer 'Environment' $env

# 5. Colours — the cursor row, the title, the rest of the list
Show-DemoHeader '5. -CursorColor / -TitleColor / -ChoiceColor'
$coloured = Read-AnsiSelection 'Pick a fruit' $fruit `
    -CursorColor BrightMagenta -TitleColor BrightWhite -ChoiceColor DarkGray
Show-Answer 'Fruit' $coloured

# 6. A timeout — wait it out to see $null
Show-DemoHeader '6. -TimeoutSeconds 5'
$timed = Read-AnsiSelection 'Quick, pick one' $fruit -TimeoutSeconds 5
Show-Answer 'Fruit' $timed

# 7. Usage pattern — pick, then show the choice in a panel
Show-DemoHeader '7. Usage pattern — choose a target, then act on it'
$target = Read-AnsiSelection 'Deploy to' @('Dev', 'Staging', 'Production')
if ($null -eq $target) {
    Format-AnsiPanel 'Cancelled' -Border Square -BorderColor DarkGray | Out-AnsiHost
} else {
    Format-AnsiPanel "deploying to [BrightWhite]$target[/]" -Title 'Next step' `
        -Border Heavy -BorderColor BrightGreen | Out-AnsiHost
}

Show-DemoHeader 'Done'
Write-Host ''
