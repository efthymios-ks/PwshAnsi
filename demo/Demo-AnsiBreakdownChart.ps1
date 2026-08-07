#Requires -Version 7.2

# Demo-AnsiBreakdownChart.ps1
# Exercises every Format-AnsiBreakdownChart parameter, section by section.
# Run: pwsh -File .\demo\Demo-AnsiBreakdownChart.ps1
#
# Piping this strips the colour by design — run it in a terminal.

$ErrorActionPreference = 'Stop'
$srcRoot = Join-Path (Split-Path -Parent $PSScriptRoot) 'src'

Import-Module (Join-Path $srcRoot 'Format-AnsiBreakdownChart.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $srcRoot 'Format-AnsiText.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $srcRoot 'Format-AnsiRule.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $srcRoot 'Format-AnsiPanel.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $srcRoot 'Format-AnsiGrid.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $srcRoot 'Format-AnsiTable.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $srcRoot 'Out-AnsiHost.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $srcRoot 'Out-AnsiString.psm1') -Force -DisableNameChecking

function Show-DemoHeader {
    param([string]$Title)
    Write-Host ''
    Write-Host ('─' * 78) -ForegroundColor DarkGray
    Write-Host " $Title" -ForegroundColor Cyan
    Write-Host ('─' * 78) -ForegroundColor DarkGray
}

# The data is plain objects — no wrapper type, the same as Format-AnsiTable rows.
$fruit = @(
    [PSCustomObject]@{ Label = 'Apples'; Value = 12; Color = 'BrightGreen' }
    [PSCustomObject]@{ Label = 'Oranges'; Value = 5; Color = 'Yellow' }
    [PSCustomObject]@{ Label = 'Bananas'; Value = 2.2; Color = 'BrightYellow' }
)

# 1. One bar, split by share, then a legend
Show-DemoHeader '1. Objects with Label, Value and Color'
Format-AnsiBreakdownChart $fruit -Width 60 | Out-AnsiHost

# 2. The legend
Show-DemoHeader '2. -HideTags, -HideTagValues, -ShowPercentage'
Format-AnsiText '[DarkGray]The bar on its own[/]' | Out-AnsiHost
Format-AnsiBreakdownChart $fruit -Width 60 -HideTags | Out-AnsiHost
Write-Host ''
Format-AnsiText '[DarkGray]Tags without the numbers[/]' | Out-AnsiHost
Format-AnsiBreakdownChart $fruit -Width 60 -HideTagValues | Out-AnsiHost
Write-Host ''
Format-AnsiText '[DarkGray]Shares instead of values[/]' | Out-AnsiHost
Format-AnsiBreakdownChart $fruit -Width 60 -ShowPercentage | Out-AnsiHost
Write-Host ''
Format-AnsiText '[DarkGray]Shares, to no decimals[/]' | Out-AnsiHost
Format-AnsiBreakdownChart $fruit -Width 60 -ShowPercentage -ValueFormat 'N0' | Out-AnsiHost

# 3. -FullSize gives every tag a row
Show-DemoHeader '3. -FullSize — one tag per row'
Format-AnsiBreakdownChart $fruit -Width 60 -FullSize -ShowPercentage | Out-AnsiHost

# 4. Tags flow onto as many rows as they need
Show-DemoHeader '4. A legend wider than the chart wraps'
$languages = @(
    [PSCustomObject]@{ Label = 'PowerShell'; Value = 42 }
    [PSCustomObject]@{ Label = 'C#'; Value = 31 }
    [PSCustomObject]@{ Label = 'TypeScript'; Value = 18 }
    [PSCustomObject]@{ Label = 'SQL'; Value = 12 }
    [PSCustomObject]@{ Label = 'Bicep'; Value = 6 }
    [PSCustomObject]@{ Label = 'YAML'; Value = 4 }
)
Format-AnsiBreakdownChart $languages -Width 60 | Out-AnsiHost

# 5. Colour comes from the item or the palette
Show-DemoHeader '5. -Palette, -TagColor, -ValueColor'
Format-AnsiText '[DarkGray]The palette, in turn[/]' | Out-AnsiHost
Format-AnsiBreakdownChart $languages -Width 60 | Out-AnsiHost
Write-Host ''
Format-AnsiText '[DarkGray]-Palette — your own cycle[/]' | Out-AnsiHost
Format-AnsiBreakdownChart $languages -Width 60 -Palette BrightBlue, Blue, BrightCyan, Cyan | Out-AnsiHost
Write-Host ''
Format-AnsiText '[DarkGray]-TagColor and -ValueColor override the tag text[/]' | Out-AnsiHost
Format-AnsiBreakdownChart $languages -Width 60 -TagColor BrightWhite -ValueColor DarkGray | Out-AnsiHost

# 6. The four styles
Show-DemoHeader '6. -Style Blocks / Line / Dots / Ascii'
foreach ($style in 'Blocks', 'Line', 'Dots', 'Ascii') {
    Format-AnsiText "[DarkGray]$style[/]" | Out-AnsiHost
    Format-AnsiBreakdownChart $fruit -Width 60 -Style $style -HideTagValues | Out-AnsiHost
    Write-Host ''
}

# 7. Whole cells, and nothing lost
Show-DemoHeader '7. Cells add up, and a small part still shows'
Format-AnsiText '[DarkGray]1000 / 1 across 40 cells — the one keeps a cell of its own[/]' | Out-AnsiHost
Format-AnsiBreakdownChart @(
    [PSCustomObject]@{ Label = 'Huge'; Value = 1000; Color = 'BrightGreen' }
    [PSCustomObject]@{ Label = 'Tiny'; Value = 1; Color = 'BrightRed' }
) -Width 40 | Out-AnsiHost
Write-Host ''
Format-AnsiText '[DarkGray]Three equal thirds of 40 cells — 14, 13, 13[/]' | Out-AnsiHost
Format-AnsiBreakdownChart @(1, 1, 1) -Width 40 -HideTags | Out-AnsiHost
Write-Host ''
Format-AnsiText '[DarkGray]Nothing with a value — an empty bar[/]' | Out-AnsiHost
Format-AnsiBreakdownChart @(0, 0) -Width 40 -HideTags | Out-AnsiHost

# 8. Any objects, read through the -*Property names
Show-DemoHeader '8. -LabelProperty / -ValueProperty / -ColorProperty'
$disks = @(
    [PSCustomObject]@{ Name = 'Used'; Bytes = 412; Hue = 'BrightRed' }
    [PSCustomObject]@{ Name = 'Cache'; Bytes = 96; Hue = 'BrightYellow' }
    [PSCustomObject]@{ Name = 'Free'; Bytes = 468; Hue = 'BrightGreen' }
)
Format-AnsiBreakdownChart $disks -Width 60 `
    -LabelProperty Name -ValueProperty Bytes -ColorProperty Hue | Out-AnsiHost

Write-Host ''
Format-AnsiText '[DarkGray]Bare numbers work too, and hashtables[/]' | Out-AnsiHost
Format-AnsiBreakdownChart @(50, 30, 20) -Width 50 -ShowPercentage | Out-AnsiHost
Format-AnsiBreakdownChart @(
    @{ Label = 'Pass'; Value = 219; Color = 'BrightGreen' }
    @{ Label = 'Fail'; Value = 6; Color = 'BrightRed' }
) -Width 50 | Out-AnsiHost

# 9. Real objects off the pipeline
Show-DemoHeader '9. Straight off the pipeline'
Get-Process | Group-Object -Property { $_.Company } -NoElement |
    Sort-Object -Property Count -Descending | Select-Object -First 5 |
    Format-AnsiBreakdownChart -Width 70 -LabelProperty Name -ValueProperty Count -ShowPercentage |
    Out-AnsiHost

# 10. Markup in the tags
Show-DemoHeader '10. Markup and markdown in the tags'
Format-AnsiBreakdownChart @(
    [PSCustomObject]@{ Label = '[bold]Bold tag[/]'; Value = 30 }
    [PSCustomObject]@{ Label = '**Markdown** :check:'; Value = 20 }
) -Width 60 -Markdown | Out-AnsiHost

# 11. It is a rendering, so it nests
Show-DemoHeader '11. Nested — a chart inside a panel, a grid, and a table'
Format-AnsiPanel (Format-AnsiBreakdownChart $fruit -Width 40) -Title 'Fruit' -Border Rounded `
    -BorderColor BrightCyan | Out-AnsiHost

Write-Host ''
$grid = @(
    , @('[BrightWhite]Q1[/]', (Format-AnsiBreakdownChart @(30, 20, 10) -Width 24 -HideTags))
    , @('[BrightWhite]Q2[/]', (Format-AnsiBreakdownChart @(10, 25, 30) -Width 24 -HideTags))
)
Format-AnsiGrid $grid -Padding 2 | Out-AnsiHost

Write-Host ''
$rows = @(
    [PSCustomObject]@{
        Suite = 'Text'
        Split = (Format-AnsiBreakdownChart @(96, 4) -Width 24 -HideTags -Palette BrightGreen, BrightRed)
    }
    [PSCustomObject]@{
        Suite = 'Table'
        Split = (Format-AnsiBreakdownChart @(71, 29) -Width 24 -HideTags -Palette BrightGreen, BrightRed)
    }
)
Format-AnsiTable $rows -Border Rounded -BorderColor DarkGray -HeaderColor BrightCyan | Out-AnsiHost

# 12. A one-line summary bar
Show-DemoHeader '12. A rule, a bar, a legend'
Format-AnsiRule 'Coverage' -Width 60 -Alignment Left -LineColor DarkGray | Out-AnsiHost
Format-AnsiBreakdownChart @(
    [PSCustomObject]@{ Label = 'Covered'; Value = 812; Color = 'BrightGreen' }
    [PSCustomObject]@{ Label = 'Partial'; Value = 96; Color = 'BrightYellow' }
    [PSCustomObject]@{ Label = 'Missed'; Value = 144; Color = 'BrightRed' }
) -Width 60 -ShowPercentage -ValueFormat 'N0' | Out-AnsiHost

# 13. Anchoring — later rows resume at the anchor column
Show-DemoHeader '13. Anchoring, and -NoNewline'
Write-Host 'Fruit: ' -NoNewline -ForegroundColor DarkGray
Format-AnsiBreakdownChart $fruit -Width 50 | Out-AnsiHost

Write-Host ''
Format-AnsiBreakdownChart @(30, 20, 10) -Width 30 -HideTags | Out-AnsiHost -NoNewline
Write-Host ' ← Cursor stayed here' -ForegroundColor DarkGray

# 14. Two panes — left and right
Show-DemoHeader '14. Two panes — left and right'
# Two renderings in one grid row: a nested rendering keeps its own runs, so both
# charts stay in their own colours. Zipping the strings would flatten them.
$left = Format-AnsiBreakdownChart @(
    [PSCustomObject]@{ Label = 'Pass'; Value = 219; Color = 'BrightGreen' }
    [PSCustomObject]@{ Label = 'Fail'; Value = 6; Color = 'BrightRed' }
) -Width 34 -FullSize
$right = Format-AnsiBreakdownChart @(
    [PSCustomObject]@{ Label = 'Used'; Value = 412; Color = 'BrightYellow' }
    [PSCustomObject]@{ Label = 'Free'; Value = 468; Color = 'BrightCyan' }
) -Width 34 -FullSize -ShowPercentage

Format-AnsiGrid @(, @($left, $right)) -Padding 4 | Out-AnsiHost

Show-DemoHeader 'Done'
Write-Host ''
