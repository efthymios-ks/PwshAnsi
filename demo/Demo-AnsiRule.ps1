#Requires -Version 7.2

# Demo-AnsiRule.ps1
# Exercises every parameter and feature of Format-AnsiRule, painted with Out-AnsiHost.
# Run: pwsh -File .\demo\Demo-AnsiRule.ps1

$ErrorActionPreference = 'Stop'
$srcRoot = Join-Path (Split-Path -Parent $PSScriptRoot) 'src'

Import-Module (Join-Path $srcRoot 'Format-AnsiRule.psm1') -Force -DisableNameChecking

Import-Module (Join-Path $srcRoot 'Out-AnsiHost.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $srcRoot 'Out-AnsiString.psm1') -Force -DisableNameChecking

function Show-DemoHeader {
    param([string]$Title)
    Write-Host ''
    Write-Host ('─' * 78) -ForegroundColor DarkGray
    Write-Host " $Title" -ForegroundColor Cyan
    Write-Host ('─' * 78) -ForegroundColor DarkGray
}

# 1. Plain rule
Show-DemoHeader '1. Plain rule (no title)'
Format-AnsiRule -Width 60 | Out-AnsiHost

# 2. Title placement
Show-DemoHeader '2. -Alignment Left / Center / Right'
Format-AnsiRule 'Left (default)' -Width 60 | Out-AnsiHost
Format-AnsiRule 'Center'         -Width 60 -Alignment Center | Out-AnsiHost
Format-AnsiRule 'Right'          -Width 60 -Alignment Right | Out-AnsiHost

# 3. Border characters
Show-DemoHeader '3. -Border Line / Double / Heavy / Ascii / Dashed / Dotted'
foreach ($border in 'Line', 'Double', 'Heavy', 'Ascii', 'Dashed', 'Dotted') {
    Format-AnsiRule $border -Width 60 -Border $border | Out-AnsiHost
}

# 4. -Char override (tiles multi-character strings)
Show-DemoHeader '4. -Char override'
Format-AnsiRule -Width 60 -Char '=' | Out-AnsiHost
Format-AnsiRule -Width 60 -Char '·' | Out-AnsiHost
Format-AnsiRule 'Tiled' -Width 60 -Char '<>' | Out-AnsiHost

# 5. -TitlePadding
Show-DemoHeader '5. -TitlePadding 0 / 1 (default) / 4'
Format-AnsiRule 'Padding 0' -Width 60 -TitlePadding 0 | Out-AnsiHost
Format-AnsiRule 'Padding 1' -Width 60 | Out-AnsiHost
Format-AnsiRule 'Padding 4' -Width 60 -TitlePadding 4 -Alignment Center | Out-AnsiHost

# 6. Colours — title and line are independent
Show-DemoHeader '6. -TitleColor / -Color and -LineColor'
Format-AnsiRule 'BrightWhite title, DarkGray line' -Width 60 -TitleColor BrightWhite -LineColor DarkGray | Out-AnsiHost
Format-AnsiRule '-Color aliases -TitleColor'       -Width 60 -Color BrightMagenta | Out-AnsiHost
Format-AnsiRule 'Line only'                        -Width 60 -LineColor BrightBlue | Out-AnsiHost

# 7. Markup in the title
Show-DemoHeader '7. Markup in the title'
Format-AnsiRule '[bold BrightYellow]Bold yellow[/] title' -Width 60 -LineColor DarkGray | Out-AnsiHost
Format-AnsiRule '[BrightGreen]Passed[/]' -Width 60 -Alignment Right -LineColor BrightGreen | Out-AnsiHost

# 8. Markdown sugar and emoji
Show-DemoHeader '8. -Markdown (sugar + emoji)'
Format-AnsiRule '**Done** :check:' -Width 60 -Markdown -LineColor DarkGray | Out-AnsiHost
Format-AnsiRule ':rocket: Deploy `v1.2.0`' -Width 60 -Markdown -Alignment Center | Out-AnsiHost

# 9. -Escape (literal title)
Show-DemoHeader '9. -Escape (title stays literal)'
Format-AnsiRule '[bold]Not parsed[/] **either**' -Width 60 -Escape -Color BrightGreen | Out-AnsiHost

# 10. Truncation
Show-DemoHeader '10. Title truncation (… when it will not fit)'
Format-AnsiRule 'A very long title that cannot possibly fit inside this width' -Width 30 | Out-AnsiHost
Format-AnsiRule 'A very long title that cannot possibly fit inside this width' -Width 30 -Alignment Center | Out-AnsiHost
Format-AnsiRule 'No room at all' -Width 3   # title dropped, plain line instead | Out-AnsiHost

# 11. -Spacing
Show-DemoHeader '11. -Spacing 1 (blank row above and below)'
Write-Host 'Before'
Format-AnsiRule 'Spaced' -Width 60 -Spacing 1 -LineColor DarkGray | Out-AnsiHost
Write-Host 'After'

# 12. Anchoring — the rule starts at the cursor column
Show-DemoHeader '12. Anchoring vs -Expand'
Write-Host '        ' -NoNewline
Format-AnsiRule 'Anchored at column 8' -LineColor DarkGray | Out-AnsiHost
Write-Host '        ' -NoNewline
Format-AnsiRule 'Expanded to full buffer' -Expand -LineColor BrightBlue | Out-AnsiHost

# 13. Pipeline input — one rule per item
Show-DemoHeader '13. Pipeline input'
'First', 'Second', 'Third' | Format-AnsiRule -Width 60 -LineColor DarkGray | Out-AnsiHost

# 14. -NoNewline leaves the cursor on the rule row
Show-DemoHeader '14. -NoNewline'
Format-AnsiRule -Width 30 -LineColor DarkGray | Out-AnsiHost -NoNewline
Write-Host ' ← Cursor stayed here' -ForegroundColor DarkGray

# 15. Section-heading pattern
Show-DemoHeader '15. Usage pattern — section headings'
Format-AnsiRule 'Build' -Width 60 -Color BrightWhite -LineColor DarkGray | Out-AnsiHost
Write-Host '  Restore, compile, pack'
Format-AnsiRule 'Test' -Width 60 -Color BrightWhite -LineColor DarkGray | Out-AnsiHost
Write-Host '  225 tests'
Format-AnsiRule ':check: All green' -Width 60 -Markdown -Alignment Right -LineColor BrightGreen | Out-AnsiHost

# 16. Two panes — rules left and right
# Components write whole rows, so a side-by-side layout means capturing each
# pane's rows off the Information stream and zipping them. Padding is measured on
# visible width, with the ANSI stripped, so colours survive.
Show-DemoHeader '16. Two panes — rules left and right'

function Get-DemoRows {
    param([Parameter(Mandatory)][scriptblock]$Render)
    $records = & $Render 6>&1
    if ($null -eq $records) { return , @() }
    $rows = @($records | ForEach-Object { [string]$_.ToString() })
    return , $rows
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

Write-DemoPanes -PaneWidth 32 -Left {
    Format-AnsiRule 'Build' -Width 32 -Color BrightWhite -LineColor DarkGray | Out-AnsiHost
    Format-AnsiRule ':check: Restore' -Width 32 -Markdown -LineColor BrightGreen | Out-AnsiHost
    Format-AnsiRule ':check: Compile' -Width 32 -Markdown -LineColor BrightGreen | Out-AnsiHost
} -Right {
    Format-AnsiRule 'Test' -Width 32 -Alignment Center -Color BrightWhite -LineColor DarkGray | Out-AnsiHost
    Format-AnsiRule '502 passed' -Width 32 -Alignment Right -LineColor BrightGreen | Out-AnsiHost
    Format-AnsiRule '0 failed' -Width 32 -Alignment Right -Border Dashed -LineColor DarkGray | Out-AnsiHost
}

# 17. NO_COLOR handling
Show-DemoHeader '17. NO_COLOR strips styles, keeps layout'
$prev = $env:NO_COLOR
try {
    $env:NO_COLOR = '1'
    Format-AnsiRule '[bold BrightRed]Plain title[/]' -Width 60 -LineColor BrightBlue | Out-AnsiHost
    Format-AnsiRule 'Centered plain' -Width 60 -Alignment Center | Out-AnsiHost
} finally {
    if ($null -eq $prev) { Remove-Item Env:NO_COLOR -ErrorAction SilentlyContinue }
    else { $env:NO_COLOR = $prev }
}

Show-DemoHeader 'Done'
Write-Host ''
