#Requires -Version 7.2

# Demo-AnsiPanel.ps1
# Exercises every parameter and feature of Format-AnsiPanel, painted with Out-AnsiHost.
# Run: pwsh -File .\demo\Demo-AnsiPanel.ps1

$ErrorActionPreference = 'Stop'
$srcRoot = Join-Path (Split-Path -Parent $PSScriptRoot) 'src'

Import-Module (Join-Path $srcRoot 'Format-AnsiPanel.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $srcRoot 'Format-AnsiTree.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $srcRoot 'Format-AnsiGrid.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $srcRoot 'Format-AnsiJson.psm1') -Force -DisableNameChecking
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

# Capture a component's rows so a panel can frame them.
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

$para = 'Every rendering respects the row and column it started at: wrapped or multi-row output resumes at the original column, never column zero.'

# 1. A framed line
Show-DemoHeader '1. Framed text'
Format-AnsiPanel 'Hello from Format-AnsiPanel' | Out-AnsiHost

# 2. Several lines, sized to the widest
Show-DemoHeader '2. Multiple lines'
Format-AnsiPanel @('First', 'Second line', 'Third') | Out-AnsiHost

# 3. Title in the top rule
Show-DemoHeader '3. -Title and -TitleAlignment Left / Center / Right'
foreach ($alignment in 'Left', 'Center', 'Right') {
    Format-AnsiPanel 'Body text goes here' -Title $alignment -TitleAlignment $alignment -BorderColor DarkGray | Out-AnsiHost
}

# 4. Borders
Show-DemoHeader '4. -Border Ascii / Square / Rounded / Heavy / Double / None'
foreach ($border in 'Ascii', 'Square', 'Rounded', 'Heavy', 'Double', 'None') {
    Format-AnsiPanel 'Content' -Title $border -Border $border -BorderColor DarkGray | Out-AnsiHost
}

# 5. Colours
Show-DemoHeader '5. -BorderColor / -TextColor / -TitleColor'
Format-AnsiPanel 'Bright and legible' -Title 'Colours' `
    -BorderColor BrightMagenta -TitleColor BrightYellow -TextColor BrightGreen | Out-AnsiHost
Format-AnsiPanel 'Title inherits the border colour' -Title 'Inherited' -BorderColor BrightCyan | Out-AnsiHost

# 6. Padding
Show-DemoHeader '6. -Padding 0 / 1 (default) / 3'
foreach ($padding in 0, 1, 3) {
    Format-AnsiPanel "padding $padding" -Padding $padding -BorderColor DarkGray | Out-AnsiHost
}

# 7. Wrapping to the inner width
Show-DemoHeader '7. Content wraps to the inner width'
Format-AnsiPanel $para -Width 46 -BorderColor DarkGray -TextColor BrightWhite | Out-AnsiHost

# 8. Justify inside the panel
Show-DemoHeader '8. -Justify Left / Center / Right'
foreach ($justify in 'Left', 'Center', 'Right') {
    Format-AnsiPanel @('Short', 'A longer line here') -Justify $justify -Title $justify -BorderColor DarkGray | Out-AnsiHost
}

# 9. -Width, -Expand, -Height
Show-DemoHeader '9. -Width / -Expand / -Height'
Format-AnsiPanel 'Fixed width' -Width 30 -BorderColor DarkGray | Out-AnsiHost
Format-AnsiPanel 'Expanded to the buffer' -Expand -BorderColor DarkGray | Out-AnsiHost
Format-AnsiPanel @('Padded', 'To six rows') -Height 6 -BorderColor DarkGray | Out-AnsiHost

# 10. Markup and markdown
Show-DemoHeader '10. Markup / -Markdown'
Format-AnsiPanel @(
    '[bold BrightWhite]Build finished[/]'
    ':check: Restore, compile, pack'
    ':cross: [BrightRed]Smoke tests failed[/]'
) -Title '**Summary**' -Markdown -BorderColor DarkGray | Out-AnsiHost

# 11. -Escape keeps content literal
Show-DemoHeader '11. -Escape (content stays literal)'
Format-AnsiPanel '[bold]X[/] and **y**' -Escape -Title 'Literal' -BorderColor DarkGray | Out-AnsiHost

# 12. -Rendered frames another component's output
Show-DemoHeader '12. -Rendered frames captured PwshAnsi output'
$treeRows = Get-DemoRows {
    Format-AnsiTree @{
        Value    = '[bold]Src[/]'
        Children = @(
            @{ Value = 'Ansi.Core.psm1' }
            @{ Value = 'Format-AnsiPanel.psm1' }
            @{ Value = 'Format-AnsiGrid.psm1' }
        )
    } -MaxWidth 30 -Color DarkGray -LabelColor BrightWhite | Out-AnsiHost
}
Format-AnsiPanel $treeRows -Rendered -Title 'Tree' -BorderColor BrightBlue | Out-AnsiHost

$jsonRows = Get-DemoRows {
    Format-AnsiJson '{"components":8,"tests":625,"failed":0}' -MaxWidth 30 -PunctuationColor DarkGray | Out-AnsiHost
}
Format-AnsiPanel $jsonRows -Rendered -Title 'JSON' -BorderColor BrightGreen | Out-AnsiHost

# 13. Anchoring — the whole box hangs at the anchor column
Show-DemoHeader '13. Anchoring'
Write-Host 'Panel: ' -NoNewline -ForegroundColor DarkGray
Format-AnsiPanel @('Anchored', 'at the cursor') -Title 'Here' -BorderColor DarkGray | Out-AnsiHost

# 14. -NoNewline leaves the cursor on the bottom rule
Show-DemoHeader '14. -NoNewline'
Format-AnsiPanel 'Done' -BorderColor DarkGray | Out-AnsiHost -NoNewline
Write-Host ' ← Cursor stayed here' -ForegroundColor DarkGray

# 15. Usage pattern — an error callout
Show-DemoHeader '15. Usage pattern — error callout'
Format-AnsiPanel @(
    '[bold]Cannot bind argument to parameter ''Runs''[/]'
    ''
    'at Split-AnsiRuns, Ansi.Core.psm1: line 261'
    'at Format-AnsiText<End>, Format-AnsiText.psm1: line 71'
) -Title '[bold]:cross: Error[/]' -Markdown -Border Heavy -BorderColor BrightRed -TextColor BrightWhite | Out-AnsiHost

# 16. Two panes — panels left and right
Show-DemoHeader '16. Two panes — panels left and right'

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

Write-DemoPanes -PaneWidth 32 -Left {
    Format-AnsiPanel @('Restore  ok', 'Compile  ok', 'Pack     ok') `
        -Title 'Build' -Width 32 -Expand -BorderColor BrightGreen -TextColor BrightWhite | Out-AnsiHost
} -Right {
    Format-AnsiPanel @('Unit      625', 'Integration   0', 'Flaky         0') `
        -Title 'tests' -Width 32 -Expand -BorderColor BrightBlue -TextColor BrightWhite | Out-AnsiHost
}

# 17. Nested renderings — pass one Format-Ansi* result into another
Show-DemoHeader '17. Nested renderings inside a panel'
$innerTree = Format-AnsiTree @{
    Value    = '[bold]Src[/]'
    Children = @(
        @{ Value = 'Ansi.Core.psm1' }
        @{ Value = 'Out-AnsiHost.psm1' }
        @{ Value = 'Components'; Children = @(
                @{ Value = 'Format-AnsiPanel.psm1' }
                @{ Value = 'Format-AnsiTree.psm1' }
            )
        }
    )
} -MaxWidth 30 -Color BrightBlue -LabelColor BrightWhite
Format-AnsiPanel $innerTree -Title 'A TREE inside a PANEL' -BorderColor BrightMagenta | Out-AnsiHost

Format-AnsiPanel @('Text line above', $innerTree, 'Text line below') `
    -Title 'Tree between two text lines' -BorderColor BrightGreen | Out-AnsiHost

# 18. NO_COLOR strips styles, keeps layout
Show-DemoHeader '18. NO_COLOR strips styles, keeps layout'
$prev = $env:NO_COLOR
try {
    $env:NO_COLOR = '1'
    Format-AnsiPanel $para -Width 46 -Title 'Plain' -BorderColor BrightBlue -TextColor BrightWhite | Out-AnsiHost
} finally {
    if ($null -eq $prev) { Remove-Item Env:NO_COLOR -ErrorAction SilentlyContinue }
    else { $env:NO_COLOR = $prev }
}

Show-DemoHeader 'Done'
Write-Host ''
