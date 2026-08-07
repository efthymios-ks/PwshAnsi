#Requires -Version 7.2

# Demo-AnsiText.ps1
# Exercises every parameter and feature of Format-AnsiText, painted with Out-AnsiHost.
# Run: pwsh -File .\demo\Demo-AnsiText.ps1

param(
    [switch]$NoColorTest
)

$ErrorActionPreference = 'Stop'
$srcRoot = Join-Path (Split-Path -Parent $PSScriptRoot) 'src'

Import-Module (Join-Path $srcRoot 'Format-AnsiText.psm1') -Force -DisableNameChecking

Import-Module (Join-Path $srcRoot 'Out-AnsiHost.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $srcRoot 'Out-AnsiString.psm1') -Force -DisableNameChecking

function Show-DemoHeader {
    param([string]$Title)
    Write-Host ''
    Write-Host ('─' * 78) -ForegroundColor DarkGray
    Write-Host " $Title" -ForegroundColor Cyan
    Write-Host ('─' * 78) -ForegroundColor DarkGray
}

# 1. Plain text
Show-DemoHeader '1. Plain text'
Format-AnsiText 'Hello from Format-AnsiText.' | Out-AnsiHost

# 2. -Color parameter
Show-DemoHeader '2. -Color parameter'
Format-AnsiText 'This whole line is BrightBlue.' -Color BrightBlue | Out-AnsiHost
Format-AnsiText 'ConsoleColor alias: DarkYellow → dark yellow.' -Color DarkYellow | Out-AnsiHost
Format-AnsiText 'Gray alias maps to $PSStyle White.' -Color Gray | Out-AnsiHost

# 3. Markup syntax
Show-DemoHeader '3. Markup syntax [style ...]text[/]'
Format-AnsiText '[bold]Bold[/] · [italic]italic[/] · [underline]underline[/] · [strikethrough]strike[/] · [reverse]reverse[/]' | Out-AnsiHost
Format-AnsiText '[BrightRed]Red[/] on [BrightGreen]green[/] on [BrightBlue]blue[/]' | Out-AnsiHost
Format-AnsiText '[bold BrightYellow on Blue]Bold yellow on blue[/]' | Out-AnsiHost
Format-AnsiText 'Nested: [BrightRed]red [bold]red+bold[/] red again[/].' | Out-AnsiHost

# 4. Escape literal brackets
Show-DemoHeader '4. Literal brackets via [[ and ]]'
Format-AnsiText 'Show literal [[brackets]] without parsing.' | Out-AnsiHost

# 5. Markdown sugar
Show-DemoHeader '5. Markdown sugar (-Markdown)'
Format-AnsiText '**Bold**, *italic*, __underline__, ~~strike~~, `code`' -Markdown | Out-AnsiHost
Format-AnsiText 'Link: [Anthropic](https://www.anthropic.com)' -Markdown | Out-AnsiHost
Format-AnsiText 'Long form: {BrightMagenta on Black}styled span{/} inline.' -Markdown | Out-AnsiHost
Format-AnsiText 'Escaped: \*not italic\* and \[not a link\].' -Markdown | Out-AnsiHost
Format-AnsiText 'Emojis: :check: ok · :cross: fail · :warn: careful · :info: note · :fire: hot · :rocket: launch · :tada: done' -Markdown | Out-AnsiHost

# 5b. Direct [link=url] markup tag (OSC 8 hyperlink)
Show-DemoHeader '5b. Direct [link=url] markup tag'
Format-AnsiText 'Docs live at [link=https://www.anthropic.com][BrightBlue underline]anthropic.com[/][/].' | Out-AnsiHost

# 6. -Escape switch (literal, no parsing)
Show-DemoHeader '6. -Escape (treat input as literal)'
Format-AnsiText '[bold]This stays literal[/] and **markdown too**' -Escape | Out-AnsiHost
Format-AnsiText '[bold]Literal but colored[/] via -Color' -Escape -Color BrightGreen | Out-AnsiHost

# 7. Justify
Show-DemoHeader '7. -Justify Left / Center / Right (within anchored width)'
Format-AnsiText 'Left aligned (default).'   -MaxWidth 60 -Justify Left   -Color Cyan | Out-AnsiHost
Format-AnsiText 'Center aligned.'           -MaxWidth 60 -Justify Center -Color Cyan | Out-AnsiHost
Format-AnsiText 'Right aligned.'            -MaxWidth 60 -Justify Right  -Color Cyan | Out-AnsiHost

# 8. Wrapping
Show-DemoHeader '8. Wrapping (Fold, default)'
$para = 'PowerShell rendering library with no external dependencies. Every rendering respects the row and column it started at: wrapped or multi-row output resumes at the original column, never column zero.'
Format-AnsiText $para -MaxWidth 50 -Color BrightWhite | Out-AnsiHost

# 9. Wrapping preserves styles across breaks
Show-DemoHeader '9. Wrapping preserves nested styles'
Format-AnsiText '[BrightYellow]The [bold]quick brown fox[/] jumps over the [underline]lazy dog[/] again and again and again.[/]' -MaxWidth 40 | Out-AnsiHost

# 10. -Indent (hanging continuation)
Show-DemoHeader '10. -Indent (continuation rows hang)'
Format-AnsiText $para -MaxWidth 60 -Indent 4 -Color BrightGreen | Out-AnsiHost

# 11. -MaxRows (row cap with ellipsis)
Show-DemoHeader '11. -MaxRows (row cap adds …)'
Format-AnsiText $para -MaxWidth 40 -MaxRows 2 -Color BrightMagenta | Out-AnsiHost

# 12. -Overflow Fold vs Crop vs Ellipsis
Show-DemoHeader '12. -Overflow modes'
$long = 'This single line is definitely much longer than the given width and demonstrates the overflow behaviour.'
Format-AnsiText ('Fold     : ' + $long) -MaxWidth 40 -Overflow Fold | Out-AnsiHost
Write-Host ''
Format-AnsiText ('Crop     : ' + $long) -MaxWidth 40 -Overflow Crop | Out-AnsiHost
Format-AnsiText ('Ellipsis : ' + $long) -MaxWidth 40 -Overflow Ellipsis | Out-AnsiHost

# 13. Anchoring — caller positions the cursor first
Show-DemoHeader '13. Anchoring — continuation resumes at anchor column'
Write-Host 'Prefix › ' -NoNewline -ForegroundColor DarkGray
Format-AnsiText $para -MaxWidth 60 | Out-AnsiHost

# 14. -NoNewline chains writes on one line
Show-DemoHeader '14. -NoNewline chaining'
Format-AnsiText 'Part-one ' -Color BrightRed | Out-AnsiHost -NoNewline
Format-AnsiText 'Part-two ' -Color BrightGreen | Out-AnsiHost -NoNewline
Format-AnsiText 'Part-three'          -Color BrightBlue | Out-AnsiHost

# 15. Pipeline input — one line per item
Show-DemoHeader '15. Pipeline input'
'Alpha', 'Bravo', 'Charlie', 'Delta' | Format-AnsiText -Color BrightCyan | Out-AnsiHost

# 15b. Array positional form — same shape without a pipe
Show-DemoHeader '15b. Array positional form'
Format-AnsiText 'Alpha', 'Bravo', 'Charlie', 'Delta' -Color BrightMagenta | Out-AnsiHost

# 15c. Embedded `\n` inside a single string — hard breaks
Show-DemoHeader '15c. `\n` hard breaks inside one string'
Format-AnsiText "line one`nline two`nline three" -Color BrightGreen | Out-AnsiHost

# 15d. -MaxRows forces Fold wrap and puts … only on the last kept row
Show-DemoHeader '15d. -MaxRows caps rows, only the last row gets …'
$multi = "first paragraph is short.`nsecond paragraph is definitely too long to fit on a single line so it wraps.`nthird paragraph.`nfourth paragraph.`nfifth paragraph."
Format-AnsiText $multi -MaxWidth 40 -MaxRows 4 -Color BrightYellow | Out-AnsiHost

# 16. Combined: markdown + color + justify + indent + wrap
Show-DemoHeader '16. Combined features'
Format-AnsiText @(
    '**PwshAnsi** is a *zero-dependency* PowerShell rendering library.'
    'It uses `$PSStyle` for colours and emits its own ANSI. Visit [the plan](https://example.com/plan) for details.'
) -Markdown -Color White -Indent 2 -MaxWidth 60 | Out-AnsiHost

# 17. Two panes — one block left, one right
# Components write whole rows, so a side-by-side layout means capturing each
# pane's rows off the Information stream and zipping them. Padding is measured on
# visible width, with the ANSI stripped, so colours survive.
Show-DemoHeader '17. Two panes — one text block left, one right'

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

Write-DemoPanes -PaneWidth 34 -Left {
    Format-AnsiText '[bold BrightWhite]Anchoring[/]' -MaxWidth 34 | Out-AnsiHost
    Format-AnsiText 'Every rendering respects the row and column it started at, so wrapped output resumes at the anchor.' -MaxWidth 34 -Color BrightCyan | Out-AnsiHost
} -Right {
    Format-AnsiText '[bold BrightWhite]Overflow[/]' -MaxWidth 34 | Out-AnsiHost
    Format-AnsiText '`Fold` wraps, `Crop` truncates, `Ellipsis` marks the cut with a single glyph.' -MaxWidth 34 -Markdown | Out-AnsiHost
    Format-AnsiText 'Row caps use -MaxRows and only ellipsise the last kept row.' -MaxWidth 34 -MaxRows 2 | Out-AnsiHost
}

# 18. NO_COLOR handling
Show-DemoHeader '18. NO_COLOR strips styles, keeps layout'
$prev = $env:NO_COLOR
try {
    $env:NO_COLOR = '1'
    Format-AnsiText '[bold BrightRed]This should render as plain text.[/]' -MaxWidth 60 | Out-AnsiHost
    Format-AnsiText $para -MaxWidth 50 -Indent 4 | Out-AnsiHost
} finally {
    if ($null -eq $prev) { Remove-Item Env:NO_COLOR -ErrorAction SilentlyContinue }
    else                 { $env:NO_COLOR = $prev }
}

Show-DemoHeader 'Done'
Write-Host ''
