#Requires -Version 7.2

# Demo-AnsiBarChart.ps1
# Exercises every Format-AnsiBarChart parameter, section by section.
# Run: pwsh -File .\demo\Demo-AnsiBarChart.ps1
#
# Piping this strips the colour by design — run it in a terminal.

$ErrorActionPreference = 'Stop'
$srcRoot = Join-Path (Split-Path -Parent $PSScriptRoot) 'src'

Import-Module (Join-Path $srcRoot 'Format-AnsiBarChart.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $srcRoot 'Format-AnsiText.psm1') -Force -DisableNameChecking
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

# 1. A chart is a label, a bar, and a value
Show-DemoHeader '1. Objects with Label, Value and Color'
Format-AnsiBarChart $fruit -Width 60 | Out-AnsiHost

# 2. -Label titles it
Show-DemoHeader '2. -Label (or -Title) above the chart'
Format-AnsiBarChart $fruit 'Fruit sales' -Width 60 -TitleColor BrightWhite | Out-AnsiHost

# 3. -TitleAlignment
Show-DemoHeader '3. -TitleAlignment Left / Center / Right'
foreach ($alignment in 'Left', 'Center', 'Right') {
    Format-AnsiBarChart $fruit -Title $alignment -Width 60 -TitleAlignment $alignment `
        -TitleColor BrightCyan -HideValues | Out-AnsiHost
    Write-Host ''
}

# 4. Colour comes from the item, a default, or the palette
Show-DemoHeader '4. Item colour, -BarColor, -Palette'
$plain = @(
    [PSCustomObject]@{ Label = 'North'; Value = 40 }
    [PSCustomObject]@{ Label = 'South'; Value = 28 }
    [PSCustomObject]@{ Label = 'East'; Value = 16 }
    [PSCustomObject]@{ Label = 'West'; Value = 9 }
)
Format-AnsiText '[DarkGray]The palette, in turn[/]' | Out-AnsiHost
Format-AnsiBarChart $plain -Width 60 | Out-AnsiHost
Write-Host ''
Format-AnsiText '[DarkGray]-BarColor, one colour for all of them[/]' | Out-AnsiHost
Format-AnsiBarChart $plain -Width 60 -BarColor BrightBlue | Out-AnsiHost
Write-Host ''
Format-AnsiText '[DarkGray]-Palette, your own cycle[/]' | Out-AnsiHost
Format-AnsiBarChart $plain -Width 60 -Palette BrightMagenta, Magenta | Out-AnsiHost

# 5. The value column
Show-DemoHeader '5. -HideValues, -ShowPercentage, -ValueFormat'
Format-AnsiBarChart $fruit -Width 60 -HideValues | Out-AnsiHost
Write-Host ''
Format-AnsiBarChart $fruit -Width 60 -ShowPercentage -ValueColor BrightWhite | Out-AnsiHost
Write-Host ''
Format-AnsiBarChart $fruit -Width 60 -ValueFormat 'N2' -ValueColor DarkGray | Out-AnsiHost

# 6. The label column
Show-DemoHeader '6. -LabelWidth, -LabelAlignment, -LabelColor'
Format-AnsiBarChart $plain -Width 60 -LabelWidth 12 -LabelColor BrightWhite | Out-AnsiHost
Write-Host ''
Format-AnsiBarChart $plain -Width 60 -LabelWidth 12 -LabelAlignment Left -LabelColor BrightWhite | Out-AnsiHost

# 7. Scale and bar width
Show-DemoHeader '7. -MaxValue and -BarWidth'
Format-AnsiText '[DarkGray]Scaled to the largest value — apples fill the row[/]' | Out-AnsiHost
Format-AnsiBarChart $fruit -Width 60 | Out-AnsiHost
Write-Host ''
Format-AnsiText '[DarkGray]-MaxValue 20 — the same data against a fixed ceiling[/]' | Out-AnsiHost
Format-AnsiBarChart $fruit -Width 60 -MaxValue 20 | Out-AnsiHost
Write-Host ''
Format-AnsiText '[DarkGray]-BarWidth 20 — the bar column, whatever the labels cost[/]' | Out-AnsiHost
Format-AnsiBarChart $fruit -BarWidth 20 -LabelWidth 12 | Out-AnsiHost

# 8. The four styles
Show-DemoHeader '8. -Style Blocks / Line / Dots / Ascii'
foreach ($style in 'Blocks', 'Line', 'Dots', 'Ascii') {
    Format-AnsiBarChart $plain -Title $style -Width 60 -Style $style -TitleAlignment Left `
        -TitleColor BrightCyan | Out-AnsiHost
    Write-Host ''
}

# 9. Any objects, read through the -*Property names
Show-DemoHeader '9. -LabelProperty / -ValueProperty / -ColorProperty'
$suites = @(
    [PSCustomObject]@{ Suite = 'Text'; Passed = 96; Hue = 'BrightGreen' }
    [PSCustomObject]@{ Suite = 'Table'; Passed = 71; Hue = 'BrightYellow' }
    [PSCustomObject]@{ Suite = 'Tree'; Passed = 38; Hue = 'BrightRed' }
)
Format-AnsiBarChart $suites 'Tests passed' -Width 60 `
    -LabelProperty Suite -ValueProperty Passed -ColorProperty Hue | Out-AnsiHost

Write-Host ''
Format-AnsiText '[DarkGray]Bare numbers work too, and hashtables[/]' | Out-AnsiHost
Format-AnsiBarChart @(12, 5, 2.2) -Width 40 | Out-AnsiHost
Format-AnsiBarChart @(
    @{ Label = 'Hit'; Value = 88; Color = 'BrightGreen' }
    @{ Label = 'Miss'; Value = 12; Color = 'BrightRed' }
) -Width 40 | Out-AnsiHost

# 10. Real objects off the pipeline
Show-DemoHeader '10. Straight off the pipeline'
Get-Process | Sort-Object -Property WorkingSet64 -Descending | Select-Object -First 6 |
    Format-AnsiBarChart -Title 'Top processes by working set (MB)' -Width 70 -LabelWidth 20 `
        -LabelProperty ProcessName -ValueProperty WorkingSet64 -ValueFormat 'N0' `
        -BarColor BrightCyan -TitleColor BrightWhite | Out-AnsiHost

# 11. Markup in the labels
Show-DemoHeader '11. Markup and markdown in the labels'
Format-AnsiBarChart @(
    [PSCustomObject]@{ Label = '[bold]Bold label[/]'; Value = 30 }
    [PSCustomObject]@{ Label = '**Markdown** :rocket:'; Value = 20 }
    [PSCustomObject]@{ Label = '[BrightRed]Coloured[/]'; Value = 10 }
) -Width 60 -Markdown | Out-AnsiHost

# 12. It is a rendering, so it nests
Show-DemoHeader '12. Nested — a chart inside a panel, a grid, and a table'
Format-AnsiPanel (Format-AnsiBarChart $fruit -Width 40) -Title 'Fruit' -Border Rounded `
    -BorderColor BrightCyan | Out-AnsiHost

Write-Host ''
$grid = @(
    , @('[BrightWhite]Q1[/]', (Format-AnsiBarChart @(30, 20, 10) -Width 24 -HideValues))
    , @('[BrightWhite]Q2[/]', (Format-AnsiBarChart @(10, 25, 30) -Width 24 -HideValues))
)
Format-AnsiGrid $grid -Padding 2 | Out-AnsiHost

Write-Host ''
$rows = @(
    [PSCustomObject]@{
        Region = 'North'
        Split  = (Format-AnsiBarChart @(9, 5, 2) -Width 24 -HideValues -Palette BrightGreen, Green, DarkGreen)
    }
    [PSCustomObject]@{
        Region = 'South'
        Split  = (Format-AnsiBarChart @(3, 8, 6) -Width 24 -HideValues -Palette BrightGreen, Green, DarkGreen)
    }
)
Format-AnsiTable $rows -Border Rounded -BorderColor DarkGray -HeaderColor BrightCyan | Out-AnsiHost

# 13. The ends never lie
Show-DemoHeader '13. A value past zero always keeps a cell'
Format-AnsiBarChart @(
    [PSCustomObject]@{ Label = 'Huge'; Value = 1000 }
    [PSCustomObject]@{ Label = 'Tiny'; Value = 1 }
    [PSCustomObject]@{ Label = 'None'; Value = 0 }
) -Width 60 -BarColor BrightGreen | Out-AnsiHost
Format-AnsiText '[DarkGray]Tiny is one cell, not none; none is nothing at all[/]' | Out-AnsiHost

# 14. Anchoring — later rows resume at the anchor column
Show-DemoHeader '14. Anchoring, and -NoNewline'
Write-Host 'Sales: ' -NoNewline -ForegroundColor DarkGray
Format-AnsiBarChart $fruit -Width 50 -BarColor BrightCyan | Out-AnsiHost

Write-Host ''
Format-AnsiBarChart @(30, 20, 10) -Width 30 -HideValues | Out-AnsiHost -NoNewline
Write-Host ' ← Cursor stayed here' -ForegroundColor DarkGray

# 15. Two panes — left and right
Show-DemoHeader '15. Two panes — left and right'
# Two renderings in one grid row: a nested rendering keeps its own runs, so both
# charts stay in their own colours. Zipping the strings would flatten them.
$left = Format-AnsiBarChart $plain 'This quarter' -Width 34 -LabelWidth 6 `
    -BarColor BrightGreen -TitleColor BrightWhite
$right = Format-AnsiBarChart @(
    [PSCustomObject]@{ Label = 'North'; Value = 31 }
    [PSCustomObject]@{ Label = 'South'; Value = 34 }
    [PSCustomObject]@{ Label = 'East'; Value = 12 }
    [PSCustomObject]@{ Label = 'West'; Value = 14 }
) 'Last quarter' -Width 34 -LabelWidth 6 -BarColor BrightMagenta -TitleColor BrightWhite

Format-AnsiGrid @(, @($left, $right)) -Padding 4 | Out-AnsiHost

Show-DemoHeader 'Done'
Write-Host ''
