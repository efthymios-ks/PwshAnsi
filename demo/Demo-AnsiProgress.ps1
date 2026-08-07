#Requires -Version 7.2

# Demo-AnsiProgress.ps1
# Exercises every Format-AnsiProgress parameter, section by section.
# Run: pwsh -File .\demo\Demo-AnsiProgress.ps1
#
# Piping this strips the colour by design — run it in a terminal.

$ErrorActionPreference = 'Stop'
$srcRoot = Join-Path (Split-Path -Parent $PSScriptRoot) 'src'

Import-Module (Join-Path $srcRoot 'Format-AnsiProgress.psm1') -Force -DisableNameChecking
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

# 1. The bar at a few values
Show-DemoHeader '1. A bar is a value out of a total'
foreach ($value in 0, 25, 50, 75, 100) {
    Format-AnsiProgress $value -Width 60 -BarColor BrightCyan -EmptyColor DarkGray | Out-AnsiHost
}

# 2. -Total counts in your own units
Show-DemoHeader '2. -Total — count files, tests, bytes, anything'
Format-AnsiProgress 3 -Total 7 -Width 60 -Show Count -BarColor BrightGreen | Out-AnsiHost
Format-AnsiProgress 128 -Total 512 -Width 60 -Show Both -BarColor BrightGreen | Out-AnsiHost
Format-AnsiProgress 1.5 -Total 4 -Width 60 -Show Count -BarColor BrightGreen | Out-AnsiHost

# 3. Labels, padded so a column lines up
Show-DemoHeader '3. -Label and -LabelWidth'
foreach ($row in @(
        @{ Name = 'Restore'; Done = 100 }
        @{ Name = 'Build'; Done = 64 }
        @{ Name = 'Test'; Done = 20 }
        @{ Name = 'Publish'; Done = 0 }
    )) {
    Format-AnsiProgress $row.Done $row.Name -Width 60 -LabelWidth 10 `
        -BarColor BrightYellow -EmptyColor DarkGray -LabelColor BrightWhite | Out-AnsiHost
}

# 4. -Show picks the suffix
Show-DemoHeader '4. -Show Percent / Count / Both / None'
foreach ($show in 'Percent', 'Count', 'Both', 'None') {
    Format-AnsiProgress 42 $show -Total 100 -Width 60 -LabelWidth 8 -Show $show `
        -BarColor BrightMagenta | Out-AnsiHost
}

# 5. The four styles
Show-DemoHeader '5. -Style Blocks / Line / Dots / Ascii'
foreach ($style in 'Blocks', 'Line', 'Dots', 'Ascii') {
    Format-AnsiProgress 60 $style -Width 60 -LabelWidth 8 -Style $style `
        -BarColor BrightBlue -EmptyColor DarkGray | Out-AnsiHost
}

# 6. Colours, and one that changes when it is done
Show-DemoHeader '6. -BarColor, -EmptyColor, -CompleteColor'
Format-AnsiProgress 40 'Running' -Width 60 -LabelWidth 10 -BarColor BrightYellow `
    -EmptyColor DarkGray -CompleteColor BrightGreen | Out-AnsiHost
Format-AnsiProgress 100 'Finished' -Width 60 -LabelWidth 10 -BarColor BrightYellow `
    -EmptyColor DarkGray -CompleteColor BrightGreen | Out-AnsiHost
Format-AnsiProgress 100 'Over budget' -Width 60 -LabelWidth 10 -BarColor BrightRed `
    -EmptyColor DarkGray -SuffixColor BrightRed | Out-AnsiHost

# 7. -BarWidth pins the bar itself
Show-DemoHeader '7. -BarWidth — a fixed bar whatever the label says'
Format-AnsiProgress 55 'Short' -BarWidth 20 -LabelWidth 14 -BarColor BrightCyan | Out-AnsiHost
Format-AnsiProgress 55 'A much longer label' -BarWidth 20 -LabelWidth 14 -BarColor BrightCyan | Out-AnsiHost

# 8. The ends never lie
Show-DemoHeader '8. Rounding never claims done, nor claims nothing started'
Format-AnsiProgress 1 -Total 1000 -Width 60 -BarColor BrightGreen | Out-AnsiHost
Format-AnsiProgress 999 -Total 1000 -Width 60 -BarColor BrightGreen | Out-AnsiHost
Format-AnsiProgress 1000 -Total 1000 -Width 60 -BarColor BrightGreen | Out-AnsiHost
Format-AnsiText '[DarkGray]One filled cell, one empty cell, then all of them[/]' | Out-AnsiHost

# 9. It is a rendering, so it nests
Show-DemoHeader '9. Nested — bars inside a panel, a grid, and a table'
$panelRows = @(
    Format-AnsiProgress 100 'Restore' -BarWidth 24 -LabelWidth 9 -BarColor BrightGreen
    Format-AnsiProgress 62 'Build' -BarWidth 24 -LabelWidth 9 -BarColor BrightYellow
    Format-AnsiProgress 0 'Publish' -BarWidth 24 -LabelWidth 9 -EmptyColor DarkGray
)
Format-AnsiPanel $panelRows -Title 'Pipeline' -Border Rounded -BorderColor BrightCyan | Out-AnsiHost

Write-Host ''
$grid = @(
    @('[BrightWhite]Web[/]', (Format-AnsiProgress 90 -BarWidth 18 -BarColor BrightGreen)),
    @('[BrightWhite]API[/]', (Format-AnsiProgress 45 -BarWidth 18 -BarColor BrightYellow)),
    @('[BrightWhite]Jobs[/]', (Format-AnsiProgress 10 -BarWidth 18 -BarColor BrightRed))
)
Format-AnsiGrid $grid -Padding 2 | Out-AnsiHost

Write-Host ''
$rows = @(
    [PSCustomObject]@{ Suite = 'Text'; Coverage = (Format-AnsiProgress 96 -BarWidth 16 -Show Percent -BarColor BrightGreen) }
    [PSCustomObject]@{ Suite = 'Table'; Coverage = (Format-AnsiProgress 71 -BarWidth 16 -Show Percent -BarColor BrightYellow) }
    [PSCustomObject]@{ Suite = 'Tree'; Coverage = (Format-AnsiProgress 38 -BarWidth 16 -Show Percent -BarColor BrightRed) }
)
Format-AnsiTable $rows -Border Rounded -BorderColor DarkGray -HeaderColor BrightCyan | Out-AnsiHost

# 10. Two panes side by side
Show-DemoHeader '10. Two panes — left and right'
$left = @(
    Format-AnsiProgress 100 'CPU' -BarWidth 14 -LabelWidth 5 -Show Percent -BarColor BrightGreen
    Format-AnsiProgress 55 'RAM' -BarWidth 14 -LabelWidth 5 -Show Percent -BarColor BrightYellow
    Format-AnsiProgress 20 'Disk' -BarWidth 14 -LabelWidth 5 -Show Percent -BarColor BrightCyan
) | ForEach-Object { $_ | Out-AnsiString -Plain -Join }
$right = @(
    Format-AnsiProgress 12 'North' -Total 20 -BarWidth 14 -LabelWidth 6 -Show Count -BarColor BrightMagenta
    Format-AnsiProgress 19 'South' -Total 20 -BarWidth 14 -LabelWidth 6 -Show Count -BarColor BrightMagenta
    Format-AnsiProgress 4 'East' -Total 20 -BarWidth 14 -LabelWidth 6 -Show Count -BarColor BrightMagenta
) | ForEach-Object { $_ | Out-AnsiString -Plain -Join }

$paneWidth = 34
for ($i = 0; $i -lt [Math]::Max($left.Count, $right.Count); $i++) {
    $l = if ($i -lt $left.Count) { $left[$i] } else { '' }
    $r = if ($i -lt $right.Count) { $right[$i] } else { '' }
    Format-AnsiText ($l.PadRight($paneWidth)) -Escape -Color BrightWhite | Out-AnsiHost -NoNewline
    Format-AnsiText $r -Escape -Color BrightWhite | Out-AnsiHost
}

Show-DemoHeader 'Done'
Write-Host ''
