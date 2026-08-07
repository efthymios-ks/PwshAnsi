#Requires -Version 7.2

# Demo-AnsiJson.ps1
# Exercises every parameter and feature of Format-AnsiJson, painted with Out-AnsiHost.
# Run: pwsh -File .\demo\Demo-AnsiJson.ps1

$ErrorActionPreference = 'Stop'
$srcRoot = Join-Path (Split-Path -Parent $PSScriptRoot) 'src'

Import-Module (Join-Path $srcRoot 'Format-AnsiJson.psm1') -Force -DisableNameChecking

Import-Module (Join-Path $srcRoot 'Out-AnsiHost.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $srcRoot 'Out-AnsiString.psm1') -Force -DisableNameChecking

function Show-DemoHeader {
    param([string]$Title)
    Write-Host ''
    Write-Host ('─' * 78) -ForegroundColor DarkGray
    Write-Host " $Title" -ForegroundColor Cyan
    Write-Host ('─' * 78) -ForegroundColor DarkGray
}

$json = '{"name":"PwshAnsi","version":"0.2.0","built":["Text","Rule","Path","Json"],"tests":{"total":356,"failed":0},"dependencies":[],"stable":true,"license":null}'

# 1. A JSON string is parsed and pretty-printed
Show-DemoHeader '1. JSON string input'
Format-AnsiJson $json | Out-AnsiHost

# 2. Objects are serialised first
Show-DemoHeader '2. PSCustomObject / hashtable / ordered dictionary'
Format-AnsiJson ([PSCustomObject]@{ name = 'PwshAnsi'; tags = @('CLI', 'ANSI'); nested = [PSCustomObject]@{ depth = 2 } }) | Out-AnsiHost
Format-AnsiJson ([ordered]@{ z = 'First'; a = 'Second' }) | Out-AnsiHost

# 3. Scalars and empty containers
Show-DemoHeader '3. Scalars and empty containers'
Format-AnsiJson 42 | Out-AnsiHost
Format-AnsiJson $true | Out-AnsiHost
Format-AnsiJson $null | Out-AnsiHost
Format-AnsiJson 'Just a string' | Out-AnsiHost
Format-AnsiJson '{}' | Out-AnsiHost
Format-AnsiJson '[]' | Out-AnsiHost
Format-AnsiJson '{"list":[],"map":{}}' | Out-AnsiHost

# 4. -IndentSize
Show-DemoHeader '4. -IndentSize 2 (default) / 4 / 0'
Format-AnsiJson '{"a":{"b":1}}' | Out-AnsiHost
Format-AnsiJson '{"a":{"b":1}}' -IndentSize 4 | Out-AnsiHost
Format-AnsiJson '{"a":{"b":1}}' -IndentSize 0 | Out-AnsiHost

# 5. -MaxDepth collapses deeper nodes
Show-DemoHeader '5. -MaxDepth collapses deeper nodes to {…} / […]'
$deep = '{"a":{"b":{"c":{"d":1}}},"list":[1,2,3]}'
Format-AnsiJson $deep -MaxDepth 1 | Out-AnsiHost
Write-Host ''
Format-AnsiJson $deep -MaxDepth 2 | Out-AnsiHost

# 6. Value colours
Show-DemoHeader '6. Value colours'
Format-AnsiJson '{"key":"string","num":3.5,"flag":false,"empty":null}' | Out-AnsiHost
Format-AnsiJson '{"key":"string","num":3.5,"flag":false,"empty":null}' `
    -KeyColor BrightWhite -StringColor BrightYellow -NumberColor BrightRed `
    -BooleanColor BrightGreen -NullColor DarkGray | Out-AnsiHost

# 7. -PunctuationColor de-emphasises braces, commas, and colons
Show-DemoHeader '7. -PunctuationColor'
Format-AnsiJson $json -PunctuationColor DarkGray | Out-AnsiHost

# 8. Long rows are ellipsised, never wrapped
Show-DemoHeader '8. -MaxWidth ellipsises long rows'
$long = '{"note":"' + ('x' * 120) + '","short":1}'
Format-AnsiJson $long -MaxWidth 50 -PunctuationColor DarkGray | Out-AnsiHost

# 9. Pipeline input — several items become one array
Show-DemoHeader '9. Pipeline input'
[PSCustomObject]@{ id = 1; ok = $true } | Format-AnsiJson | Out-AnsiHost
1, 2, 3 | Format-AnsiJson | Out-AnsiHost

# 10. Real objects straight off a cmdlet
Show-DemoHeader '10. Cmdlet output'
Get-Process -Id $PID | Select-Object Id, ProcessName, StartTime | Format-AnsiJson -MaxWidth 60 | Out-AnsiHost

# 11. -Depth bounds serialisation of deep objects
Show-DemoHeader '11. -Depth bounds serialisation (deeper nodes stringify)'
Format-AnsiJson (@{ a = @{ b = @{ c = @{ d = 1 } } } }) -Depth 2 -WarningAction SilentlyContinue | Out-AnsiHost

# 12. Anchoring — later rows resume at the anchor column
Show-DemoHeader '12. Anchoring'
Write-Host 'Config: ' -NoNewline -ForegroundColor DarkGray
Format-AnsiJson '{"retries":3,"timeout":"30s"}' -PunctuationColor DarkGray | Out-AnsiHost

# 13. -NoNewline leaves the cursor on the last row
Show-DemoHeader '13. -NoNewline'
Format-AnsiJson '{"done":true}' -PunctuationColor DarkGray | Out-AnsiHost -NoNewline
Write-Host ' ← Cursor stayed here' -ForegroundColor DarkGray

# 14. Usage pattern — dump a settings file
Show-DemoHeader '14. Usage pattern — inspect a JSON file'
$tempFile = Join-Path ([System.IO.Path]::GetTempPath()) 'ansi-demo-settings.json'
'{"theme":"dark","fontSize":13,"plugins":["ansi","pester"],"telemetry":false}' |
    Set-Content -LiteralPath $tempFile -Encoding utf8
try {
    Get-Content -LiteralPath $tempFile -Raw | Format-AnsiJson -PunctuationColor DarkGray | Out-AnsiHost
} finally {
    Remove-Item -LiteralPath $tempFile -ErrorAction SilentlyContinue
}

# 15. Two panes — JSON left and right
# Components write whole rows, so a side-by-side layout means capturing each
# pane's rows off the Information stream and zipping them. Padding is measured on
# visible width, with the ANSI stripped, so colours survive.
Show-DemoHeader '15. Two panes — request left, response right'

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
    Format-AnsiJson '{"method":"POST","path":"/v1/render","body":{"component":"table","rows":6}}' `
        -MaxWidth 34 -PunctuationColor DarkGray | Out-AnsiHost
} -Right {
    Format-AnsiJson '{"status":200,"elapsedMs":8.4,"warnings":[],"cached":false}' `
        -MaxWidth 34 -PunctuationColor DarkGray | Out-AnsiHost
}

# 16. NO_COLOR strips styles, keeps layout
Show-DemoHeader '16. NO_COLOR strips styles, keeps layout'
$prev = $env:NO_COLOR
try {
    $env:NO_COLOR = '1'
    Format-AnsiJson '{"a":{"b":[1,"two",null]}}' -PunctuationColor DarkGray | Out-AnsiHost
} finally {
    if ($null -eq $prev) { Remove-Item Env:NO_COLOR -ErrorAction SilentlyContinue }
    else { $env:NO_COLOR = $prev }
}

Show-DemoHeader 'Done'
Write-Host ''
