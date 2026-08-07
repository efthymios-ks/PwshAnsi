#Requires -Version 7.2

# Demo-AnsiPath.ps1
# Exercises every parameter and feature of Format-AnsiPath, painted with Out-AnsiHost.
# Run: pwsh -File .\demo\Demo-AnsiPath.ps1

$ErrorActionPreference = 'Stop'
$srcRoot = Join-Path (Split-Path -Parent $PSScriptRoot) 'src'

Import-Module (Join-Path $srcRoot 'Format-AnsiPath.psm1') -Force -DisableNameChecking

Import-Module (Join-Path $srcRoot 'Out-AnsiHost.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $srcRoot 'Out-AnsiString.psm1') -Force -DisableNameChecking

function Show-DemoHeader {
    param([string]$Title)
    Write-Host ''
    Write-Host ('─' * 78) -ForegroundColor DarkGray
    Write-Host " $Title" -ForegroundColor Cyan
    Write-Host ('─' * 78) -ForegroundColor DarkGray
}

$deep = 'C:\Users\dev\repos\PwshAnsi\src\deeply\nested\file.txt'

# 1. Path shapes — nothing is validated or normalised
Show-DemoHeader '1. Path shapes'
Format-AnsiPath 'C:\Users\dev\repo\file.txt' | Out-AnsiHost
Format-AnsiPath '/usr/local/share/doc/readme.md' | Out-AnsiHost
Format-AnsiPath '\\server\share\team\notes.docx' | Out-AnsiHost
Format-AnsiPath 'src\Format-AnsiPath.psm1' | Out-AnsiHost
Format-AnsiPath '~/projects/ansi/src/core.psm1' | Out-AnsiHost
Format-AnsiPath '..\..\build\output.zip' | Out-AnsiHost
Format-AnsiPath 'file.txt' | Out-AnsiHost
Format-AnsiPath 'Q:\does\not\exist.txt' | Out-AnsiHost

# 2. Part colours
Show-DemoHeader '2. -RootColor / -SeparatorColor / -StemColor / -LeafColor'
Format-AnsiPath $deep -RootColor BrightRed -SeparatorColor DarkGray -StemColor BrightBlue -LeafColor BrightGreen | Out-AnsiHost
Format-AnsiPath $deep -SeparatorColor DarkGray -LeafColor BrightWhite | Out-AnsiHost

# 3. -Color as the base colour, overridden per part
Show-DemoHeader '3. -Color base colour (per-part overrides win)'
Format-AnsiPath 'C:\repos\ansi\src\core.psm1' -Color BrightCyan | Out-AnsiHost
Format-AnsiPath 'C:\repos\ansi\src\core.psm1' -Color DarkGray -LeafColor BrightWhite | Out-AnsiHost

# 4. Truncation — middle segments collapse into …
Show-DemoHeader '4. Truncation drops middle segments'
foreach ($w in 70, 46, 34, 26, 18, 12) {
    Write-Host ("{0,3} : " -f $w) -NoNewline -ForegroundColor DarkGray
    Format-AnsiPath $deep -MaxWidth $w -SeparatorColor DarkGray -LeafColor BrightWhite | Out-AnsiHost
}

# 5. A single over-long leaf is ellipsised
Show-DemoHeader '5. Over-long leaf'
Format-AnsiPath 'C:\averyveryverylongsinglefilename.txt' -MaxWidth 20 -LeafColor BrightWhite | Out-AnsiHost

# 6. Alignment
Show-DemoHeader '6. -Alignment Left / Center / Right'
Format-AnsiPath 'src\core.psm1' -MaxWidth 40 -Alignment Left   -LeafColor BrightWhite | Out-AnsiHost
Format-AnsiPath 'src\core.psm1' -MaxWidth 40 -Alignment Center -LeafColor BrightWhite | Out-AnsiHost
Format-AnsiPath 'src\core.psm1' -MaxWidth 40 -Alignment Right  -LeafColor BrightWhite | Out-AnsiHost

# 7. Separators are preserved (mixed input normalises to the first one used)
Show-DemoHeader '7. Separator handling'
Format-AnsiPath '/usr/local/bin/pwsh' | Out-AnsiHost
Format-AnsiPath 'C:/Users\repo/file.txt' | Out-AnsiHost   # → C:/Users/repo/file.txt

# 8. Array and pipeline input — one row per path
Show-DemoHeader '8. Array and pipeline input'
Format-AnsiPath 'src\a.ps1', 'src\b.ps1', 'src\c.ps1' -LeafColor BrightWhite | Out-AnsiHost
'tests\1.Tests.ps1', 'tests\2.Tests.ps1' | Format-AnsiPath -Color DarkGray -LeafColor BrightCyan | Out-AnsiHost

# 9. Real filesystem items bind by FullName
Show-DemoHeader '9. Get-ChildItem piped straight in'
Get-ChildItem -LiteralPath $srcRoot -File |
    Format-AnsiPath -MaxWidth 60 -SeparatorColor DarkGray -LeafColor BrightGreen | Out-AnsiHost

# 10. Anchoring — later rows resume at the anchor column
Show-DemoHeader '10. Anchoring'
Write-Host 'Loaded: ' -NoNewline -ForegroundColor DarkGray
Format-AnsiPath 'src\core.psm1', 'src\text.psm1', 'src\rule.psm1' -LeafColor BrightWhite | Out-AnsiHost

# 11. -NoNewline leaves the cursor on the row
Show-DemoHeader '11. -NoNewline'
Format-AnsiPath 'src\core.psm1' -LeafColor BrightWhite | Out-AnsiHost -NoNewline
Write-Host ' ← Cursor stayed here' -ForegroundColor DarkGray

# 12. Usage pattern — file list with sizes
Show-DemoHeader '12. Usage pattern — annotated file list'
foreach ($f in Get-ChildItem -LiteralPath $srcRoot -File) {
    Write-Host ('{0,8:n0} B  ' -f $f.Length) -NoNewline -ForegroundColor DarkGray
    Format-AnsiPath $f.FullName -MaxWidth 50 -SeparatorColor DarkGray -LeafColor BrightWhite | Out-AnsiHost
}

# 13. Two panes — paths left and right
# Components write whole rows, so a side-by-side layout means capturing each
# pane's rows off the Information stream and zipping them. Padding is measured on
# visible width, with the ANSI stripped, so colours survive.
Show-DemoHeader '13. Two panes — paths left and right'

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
    Format-AnsiPath 'src\Ansi.Core.psm1', 'src\Format-AnsiText.psm1', 'src\Format-AnsiTable.psm1' `
        -MaxWidth 32 -SeparatorColor DarkGray -LeafColor BrightWhite | Out-AnsiHost
} -Right {
    Format-AnsiPath 'C:\Users\dev\repos\PwshAnsi\docs\Overview.md',
    'C:\Users\dev\repos\PwshAnsi\docs\Markup.md',
    '/usr/local/share/ansi/colours.md' `
        -MaxWidth 32 -SeparatorColor DarkGray -StemColor DarkGray -LeafColor BrightCyan | Out-AnsiHost
}

# 14. NO_COLOR strips styles, keeps layout
Show-DemoHeader '14. NO_COLOR strips styles, keeps layout'
$prev = $env:NO_COLOR
try {
    $env:NO_COLOR = '1'
    Format-AnsiPath $deep -MaxWidth 34 -RootColor BrightRed -LeafColor BrightGreen | Out-AnsiHost
    Format-AnsiPath 'src\core.psm1' -MaxWidth 40 -Alignment Right | Out-AnsiHost
} finally {
    if ($null -eq $prev) { Remove-Item Env:NO_COLOR -ErrorAction SilentlyContinue }
    else { $env:NO_COLOR = $prev }
}

Show-DemoHeader 'Done'
Write-Host ''
