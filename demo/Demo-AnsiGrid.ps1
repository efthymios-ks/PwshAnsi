#Requires -Version 7.2

# Demo-AnsiGrid.ps1
# Exercises every parameter and feature of Format-AnsiGrid, painted with Out-AnsiHost.
# Run: pwsh -File .\demo\Demo-AnsiGrid.ps1

$ErrorActionPreference = 'Stop'
$srcRoot = Join-Path (Split-Path -Parent $PSScriptRoot) 'src'

Import-Module (Join-Path $srcRoot 'Format-AnsiGrid.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $srcRoot 'Format-AnsiPanel.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $srcRoot 'Format-AnsiText.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $srcRoot 'Format-AnsiTree.psm1') -Force -DisableNameChecking

Import-Module (Join-Path $srcRoot 'Out-AnsiHost.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $srcRoot 'Out-AnsiString.psm1') -Force -DisableNameChecking

function Show-DemoHeader {
    param([string]$Title)
    Write-Host ''
    Write-Host ('─' * 78) -ForegroundColor DarkGray
    Write-Host " $Title" -ForegroundColor Cyan
    Write-Host ('─' * 78) -ForegroundColor DarkGray
}

# Leading commas matter: @() collects statement output and unrolls arrays, so
# newline-separated rows without them would flatten into one cell per row.
$rows = @(
    , @('[bold]Component[/]', '[bold]Tests[/]', '[bold]Status[/]')
    , @('Format-AnsiText', '147', '[BrightGreen]Built[/]')
    , @('Format-AnsiRule', '78', '[BrightGreen]Built[/]')
    , @('Format-AnsiGrid', '57', '[BrightYellow]New[/]')
)
$items = @(
    'Ansi.Core.psm1', 'Format-AnsiText.psm1', 'Format-AnsiRule.psm1', 'Format-AnsiPath.psm1'
    'Format-AnsiJson.psm1', 'Format-AnsiTree.psm1', 'Format-AnsiTable.psm1', 'Format-AnsiGrid.psm1'
)

# 1. Explicit rows — a borderless, aligned block
Show-DemoHeader '1. Explicit rows (-Rows)'
Format-AnsiGrid $rows | Out-AnsiHost

# 2. Alignment per column
Show-DemoHeader '2. -Align per column'
Format-AnsiGrid $rows -Align Left, Right, Center | Out-AnsiHost

# 3. Padding between columns
Show-DemoHeader '3. -Padding 0 / 2 (default) / 6'
foreach ($padding in 0, 2, 6) {
    Write-Host "  padding $padding" -ForegroundColor DarkGray
    Format-AnsiGrid $rows -Padding $padding | Out-AnsiHost
    Write-Host ''
}

# 4. Fixed and content-sized columns
Show-DemoHeader '4. -ColumnWidth (0 = size to content)'
Format-AnsiGrid $rows -ColumnWidth 20, 0, 10 -Align Left, Right, Left | Out-AnsiHost

# 5. -Expand spreads the slack across columns
Show-DemoHeader '5. -Expand'
Format-AnsiGrid $rows -Expand -MaxWidth 70 | Out-AnsiHost

# 6. A flat list flowed into columns (-Items) — no chunking on your side
Show-DemoHeader '6. -Items flows a flat list into as many columns as fit'
Format-AnsiGrid -Items $items -Color BrightCyan | Out-AnsiHost

# 7. -ColumnCount forces the shape
Show-DemoHeader '7. -Items -ColumnCount 2 / 3 / 1'
foreach ($count in 2, 3, 1) {
    Write-Host "  $count column(s)" -ForegroundColor DarkGray
    Format-AnsiGrid -Items $items[0..3] -ColumnCount $count -Color BrightCyan | Out-AnsiHost
    Write-Host ''
}

# 8. Narrow width flows fewer columns
Show-DemoHeader '8. -Items in a narrow width'
Format-AnsiGrid -Items $items -MaxWidth 44 -Color BrightCyan | Out-AnsiHost

# 9. Markup, markdown, and per-cell colour
Show-DemoHeader '9. Markup / -Markdown per cell'
Format-AnsiGrid @(
    , @('[bold]Step[/]', '[bold]Result[/]')
    , @('Restore', '[BrightGreen]:check: Ok[/]')
    , @('Compile', '[BrightGreen]:check: Ok[/]')
    , @('Smoke', '[bold BrightRed]:cross: Failed[/]')
) -Markdown -Align Left, Right | Out-AnsiHost

# 10. -Escape keeps cells literal
Show-DemoHeader '10. -Escape (cells stay literal)'
Format-AnsiGrid @(, @('[bold]X[/]', '**Not parsed**')) -Escape | Out-AnsiHost

# 11. Cell overflow — ellipsis by default, folding with -Wrap
Show-DemoHeader '11. Cell overflow: default vs -Wrap'
$long = @(, @('Anchor', 'Every rendering resumes at the column the cursor started on, never column zero.'))
Format-AnsiGrid $long -MaxWidth 60 -Color BrightWhite | Out-AnsiHost
Write-Host ''
Format-AnsiGrid $long -MaxWidth 60 -Wrap -Color BrightWhite | Out-AnsiHost

# 12. Hard newlines inside a cell add rows to that cell only
Show-DemoHeader '12. Hard `n inside a cell'
Format-AnsiGrid @(, @("first line`nsecond line", 'Right column')) -Color BrightWhite | Out-AnsiHost

# 13. Ragged rows and a one-column grid (what Rows/Columns would have been)
Show-DemoHeader '13. Ragged rows, and a vertical stack'
Format-AnsiGrid @(, @('a', 'b', 'c'), @('d'), @('e', 'f')) | Out-AnsiHost
Write-Host ''
Format-AnsiGrid @('One', 'Two', 'Three') | Out-AnsiHost

# 14. Pipeline input
Show-DemoHeader '14. Pipeline input (rows and items)'
$rows | Format-AnsiGrid -Markdown | Out-AnsiHost
Write-Host ''
$items[0..4] | Format-AnsiGrid -ColumnCount 3 -Color BrightCyan | Out-AnsiHost

# 15. Anchoring — later rows resume at the anchor column
Show-DemoHeader '15. Anchoring'
Write-Host 'Grid: ' -NoNewline -ForegroundColor DarkGray
Format-AnsiGrid $rows -Markdown | Out-AnsiHost

# 16. -NoNewline leaves the cursor on the last row
Show-DemoHeader '16. -NoNewline'
Format-AnsiGrid @(, @('Done', 'Yes')) -Color BrightWhite | Out-AnsiHost -NoNewline
Write-Host ' ← Cursor stayed here' -ForegroundColor DarkGray

# 17. Usage pattern — a key/value block
Show-DemoHeader '17. Usage pattern — key/value block'
$settings = [ordered]@{
    Runtime      = 'PowerShell 7.2+'
    Dependencies = 'None'
    Components   = '7 built'
    Tests        = '559 passing'
}
$kv = @()
foreach ($entry in $settings.GetEnumerator()) {
    # Each cell parenthesised: `,` binds tighter than `+`, so unparenthesised
    # concatenation would splice extra cells into the row.
    $kv += , @(('[DarkGray]{0}[/]' -f $entry.Key), ('[BrightWhite]{0}[/]' -f $entry.Value))
}
Format-AnsiGrid $kv -Padding 3 | Out-AnsiHost

# 18. Two panes — grids left and right
# Components write whole rows, so a side-by-side layout means capturing each
# pane's rows off the Information stream and zipping them. Padding is measured on
# visible width, with the ANSI stripped, so colours survive.
Show-DemoHeader '18. Two panes — grids left and right'

function Get-DemoRows {
    param([Parameter(Mandatory)][scriptblock]$Render)
    $records = & $Render 6>&1
    if ($null -eq $records) { return , @() }
    $captured = @($records | ForEach-Object { [string]$_.ToString() })
    return , $captured
}

function Measure-DemoVisibleLength {
    param([AllowEmptyString()][string]$Text)
    $plain = $Text -replace "`e\[[\d;]*m", ''
    $plain = $plain -replace "`e\]8;;[^`e]*`e\\", ''
    return $plain.Length
}

function Write-DemoPanes {
    param(
        [Parameter(Mandatory)][int]$PaneWidth,
        [Parameter(Mandatory)][scriptblock]$Left,
        [Parameter(Mandatory)][scriptblock]$Right
    )
    $gutter = '  ' + [string][char]0x2502 + '  '
    $leftRows = Get-DemoRows $Left
    $rightRows = Get-DemoRows $Right
    for ($i = 0; $i -lt [Math]::Max($leftRows.Count, $rightRows.Count); $i++) {
        $l = ''
        if ($i -lt $leftRows.Count) { $l = $leftRows[$i] }
        $r = ''
        if ($i -lt $rightRows.Count) { $r = $rightRows[$i] }
        $pad = ' ' * [Math]::Max(0, $PaneWidth - (Measure-DemoVisibleLength $l))
        Write-Host ($l + $pad + $gutter + $r)
    }
}

Write-DemoPanes -PaneWidth 30 -Left {
    Format-AnsiGrid $kv -Padding 2 -MaxWidth 30 | Out-AnsiHost
} -Right {
    Format-AnsiGrid -Items $items -ColumnCount 1 -MaxWidth 30 -Color BrightCyan | Out-AnsiHost
}

# 19. Nested renderings — a rendering per cell
Show-DemoHeader '19. Nested renderings inside grid cells'
$ciTree = Format-AnsiTree @{
    Value    = '[bold]CI[/]'
    Children = @(@{ Value = ':check: Build' }, @{ Value = ':check: Test' })
} -Markdown -MaxWidth 22 -Color BrightGreen -LabelColor BrightWhite
$countTree = Format-AnsiTree @{
    Value    = '[bold]Counts[/]'
    Children = @(@{ Value = 'Unit 712' }, @{ Value = 'Demo   9' })
} -MaxWidth 22 -Color BrightBlue -LabelColor BrightWhite

# TWO TREES, one per grid cell — side by side with no capture/zip
Format-AnsiGrid @(, @($ciTree, $countTree)) -Padding 4 | Out-AnsiHost
Write-Host ''
# a tree next to a framed panel, still one grid row
$panel = Format-AnsiPanel 'All green' -Border Square -BorderColor BrightMagenta -TextColor BrightWhite
Format-AnsiGrid @(, @($ciTree, $panel)) -Padding 4 | Out-AnsiHost

# 20. NO_COLOR strips styles, keeps layout
Show-DemoHeader '20. NO_COLOR strips styles, keeps layout'
$prev = $env:NO_COLOR
try {
    $env:NO_COLOR = '1'
    Format-AnsiGrid $rows -Align Left, Right, Center | Out-AnsiHost
    Format-AnsiGrid -Items $items[0..3] -ColumnCount 2 | Out-AnsiHost
} finally {
    if ($null -eq $prev) { Remove-Item Env:NO_COLOR -ErrorAction SilentlyContinue }
    else { $env:NO_COLOR = $prev }
}

Show-DemoHeader 'Done'
Write-Host ''
