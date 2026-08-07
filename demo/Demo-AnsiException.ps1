#Requires -Version 7.2

# Demo-AnsiException.ps1
# Exercises every parameter and feature of Format-AnsiException, painted with Out-AnsiHost.
# Run: pwsh -File .\demo\Demo-AnsiException.ps1

$ErrorActionPreference = 'Stop'
$srcRoot = Join-Path (Split-Path -Parent $PSScriptRoot) 'src'

Import-Module (Join-Path $srcRoot 'Format-AnsiException.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $srcRoot 'Format-AnsiPanel.psm1') -Force -DisableNameChecking

Import-Module (Join-Path $srcRoot 'Out-AnsiHost.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $srcRoot 'Out-AnsiString.psm1') -Force -DisableNameChecking

function Show-DemoHeader {
    param([string]$Title)
    Write-Host ''
    Write-Host ('─' * 78) -ForegroundColor DarkGray
    Write-Host " $Title" -ForegroundColor Cyan
    Write-Host ('─' * 78) -ForegroundColor DarkGray
}

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

# A real ErrorRecord, so the position and script stack are populated.
function Invoke-DemoInnerStep { throw 'The widget could not be flushed' }
function Invoke-DemoOuterStep { Invoke-DemoInnerStep }
$record = $null
try { Invoke-DemoOuterStep } catch { $record = $_ }

# A nested exception chain.
$nested = [System.Exception]::new('Deploy failed',
    [System.InvalidOperationException]::new('Database migration aborted',
        [System.TimeoutException]::new('Connection timed out after 30s')))

# 1. Default: type, message, and where it happened
Show-DemoHeader '1. Default detail'
Format-AnsiException $record | Out-AnsiHost

# 2. -Detail Short / Default / Full
Show-DemoHeader '2. -Detail Short / Default / Full'
foreach ($detail in 'Short', 'Default', 'Full') {
    Write-Host "  $detail" -ForegroundColor DarkGray
    Format-AnsiException $record -Detail $detail | Out-AnsiHost
    Write-Host ''
}

# 3. -ShowStackTrace on its own
Show-DemoHeader '3. -ShowStackTrace'
Format-AnsiException $record -ShowStackTrace | Out-AnsiHost

# 4. -MaxFrames caps the trace and says what was dropped
Show-DemoHeader '4. -MaxFrames 2'
Format-AnsiException $record -ShowStackTrace -MaxFrames 2 | Out-AnsiHost

# 5. Inner exceptions, nested one level each
Show-DemoHeader '5. Inner exceptions (-Detail Full)'
Format-AnsiException $nested -Detail Full | Out-AnsiHost

# 6. -Indent controls the nesting step
Show-DemoHeader '6. -Indent 2 / 4 (default) / 8'
foreach ($indent in 2, 4, 8) {
    Write-Host "  indent $indent" -ForegroundColor DarkGray
    Format-AnsiException $nested -Detail Full -Indent $indent | Out-AnsiHost
    Write-Host ''
}

# 7. Colours
Show-DemoHeader '7. Colours: message / type / path / line number / frame'
Format-AnsiException $record -ShowStackTrace `
    -MessageColor BrightRed -TypeColor BrightWhite `
    -PathColor BrightCyan -LineNumberColor BrightYellow -FrameColor DarkGray | Out-AnsiHost
Write-Host ''
Format-AnsiException $record -ShowStackTrace `
    -MessageColor BrightYellow -TypeColor BrightMagenta `
    -PathColor BrightGreen -LineNumberColor BrightRed -FrameColor BrightBlack | Out-AnsiHost

# 8. A plain string is just a message
Show-DemoHeader '8. A bare string'
Format-AnsiException 'No exception object, just a message' | Out-AnsiHost

# 9. An Exception (not an ErrorRecord)
Show-DemoHeader '9. Exception input'
Format-AnsiException ([System.IO.FileNotFoundException]::new('settings.json is missing')) | Out-AnsiHost

# 10. Wrapping — long messages fold with a hanging indent
Show-DemoHeader '10. Narrow width wraps and hangs'
Format-AnsiException $record -ShowStackTrace -MaxWidth 46 | Out-AnsiHost

# 11. Anchoring — the block hangs at the anchor column
Show-DemoHeader '11. Anchoring'
Write-Host 'Error: ' -NoNewline -ForegroundColor DarkGray
Format-AnsiException $nested -Detail Full | Out-AnsiHost

# 12. -NoNewline leaves the cursor on the last row
Show-DemoHeader '12. -NoNewline'
Format-AnsiException $nested -Detail Short | Out-AnsiHost -NoNewline
Write-Host ' ← Cursor stayed here' -ForegroundColor DarkGray

# 13. Pipeline input — one block per error
Show-DemoHeader '13. Pipeline input'
$record, $nested | Format-AnsiException -Detail Short | Out-AnsiHost

# 14. Usage pattern — framed error report
Show-DemoHeader '14. Usage pattern — framed in a panel'
$reportRows = Get-DemoRows {
    Format-AnsiException $record -ShowStackTrace -MaxFrames 3 -MaxWidth 60 -FrameColor DarkGray | Out-AnsiHost
}
Format-AnsiPanel $reportRows -Rendered -Title '[bold]:cross: Failed[/]' -Markdown `
    -Border Heavy -BorderColor BrightRed | Out-AnsiHost

# 15. Usage pattern — a trap that reports and rethrows
Show-DemoHeader '15. Usage pattern — report then rethrow'
try {
    try { Invoke-DemoOuterStep } catch {
        Format-AnsiException $_ -Detail Default -FrameColor DarkGray | Out-AnsiHost
        throw
    }
} catch {
    Write-Host '  Rethrown to the caller' -ForegroundColor DarkGray
}

# 16. Two panes — two reports side by side
Show-DemoHeader '16. Two panes — reports left and right'

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
    Format-AnsiException $nested -Detail Full -MaxWidth 34 -Indent 2 -FrameColor DarkGray | Out-AnsiHost
} -Right {
    Format-AnsiException $record -ShowStackTrace -MaxFrames 2 -MaxWidth 34 -FrameColor DarkGray | Out-AnsiHost
}

# 17. NO_COLOR strips styles, keeps layout
Show-DemoHeader '17. NO_COLOR strips styles, keeps layout'
$prev = $env:NO_COLOR
try {
    $env:NO_COLOR = '1'
    Format-AnsiException $nested -Detail Full | Out-AnsiHost
} finally {
    if ($null -eq $prev) { Remove-Item Env:NO_COLOR -ErrorAction SilentlyContinue }
    else { $env:NO_COLOR = $prev }
}

Show-DemoHeader 'Done'
Write-Host ''
