#Requires -Version 7.2

# Demo-AnsiTable.ps1
# Exercises every parameter and feature of Format-AnsiTable, painted with Out-AnsiHost.
# Run: pwsh -File .\demo\Demo-AnsiTable.ps1

$ErrorActionPreference = 'Stop'
$srcRoot = Join-Path (Split-Path -Parent $PSScriptRoot) 'src'

Import-Module (Join-Path $srcRoot 'Format-AnsiTable.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $srcRoot 'Format-AnsiGrid.psm1') -Force -DisableNameChecking
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

$components = @(
    [PSCustomObject]@{ Component = 'Format-AnsiText'; Tests = 147; Status = 'Built' }
    [PSCustomObject]@{ Component = 'Format-AnsiRule'; Tests = 78; Status = 'Built' }
    [PSCustomObject]@{ Component = 'Format-AnsiPath'; Tests = 64; Status = 'Built' }
    [PSCustomObject]@{ Component = 'Format-AnsiJson'; Tests = 67; Status = 'Built' }
    [PSCustomObject]@{ Component = 'Format-AnsiTree'; Tests = 68; Status = 'Built' }
    [PSCustomObject]@{ Component = 'Format-AnsiTable'; Tests = 78; Status = 'Built' }
)

# 1. Default rendering — rounded border, headers, sized to content
Show-DemoHeader '1. Default rendering'
Format-AnsiTable $components | Out-AnsiHost

# 2. Border styles
Show-DemoHeader '2. -Border None / Ascii / Square / Rounded / Heavy / Double / Horizontal'
$small = $components | Select-Object -First 2
foreach ($border in 'None', 'Ascii', 'Square', 'Rounded', 'Heavy', 'Double', 'Horizontal') {
    Write-Host "  $border" -ForegroundColor DarkGray
    Format-AnsiTable $small -Border $border | Out-AnsiHost
    Write-Host ''
}

# 3. Colours
Show-DemoHeader '3. -BorderColor / -HeaderColor / -TextColor'
Format-AnsiTable $components -BorderColor BrightMagenta -HeaderColor BrightYellow -TextColor BrightGreen | Out-AnsiHost
Format-AnsiTable ($components | Select-Object -First 3) `
    -Border Double -BorderColor BrightCyan -HeaderColor BrightRed -TextColor BrightWhite | Out-AnsiHost
Format-AnsiTable ($components | Select-Object -First 3) `
    -Border Heavy -BorderColor BrightGreen -HeaderColor BrightBlue -TextColor BrightYellow | Out-AnsiHost

# 3b. Per-cell colours via markup — the value decides its own colour
Show-DemoHeader '3b. Per-cell colours via markup'
$runs = @(
    [PSCustomObject]@{ Suite = 'Text'; Passed = 147; Failed = 0; State = 'Green' }
    [PSCustomObject]@{ Suite = 'Rule'; Passed = 76; Failed = 2; State = 'Red' }
    [PSCustomObject]@{ Suite = 'Path'; Passed = 64; Failed = 0; State = 'Green' }
    [PSCustomObject]@{ Suite = 'Json'; Passed = 60; Failed = 7; State = 'Red' }
    [PSCustomObject]@{ Suite = 'Tree'; Passed = 68; Failed = 0; State = 'Green' }
)
Format-AnsiTable $runs -Property `
    Suite,
@{ Name = 'Passed'; Expression = { '[BrightGreen]{0}[/]' -f $_.Passed } },
@{ Name = 'Failed'; Expression = {
        if ($_.Failed -gt 0) { '[bold BrightRed]{0}[/]' -f $_.Failed } else { '[DarkGray]0[/]' }
    }
},
@{ Name = 'Result'; Expression = {
        if ($_.Failed -gt 0) { '[BrightRed]:cross: Failing[/]' } else { '[BrightGreen]:check: Passing[/]' }
    }
} -Markdown -Align Left, Right, Right, Left -BorderColor DarkGray -HeaderColor BrightWhite | Out-AnsiHost

# 3c. Backgrounds, and one row highlighted
Show-DemoHeader '3c. Backgrounds and a highlighted row'
Format-AnsiTable @(
    [PSCustomObject]@{ Level = '[BrightBlack on White] INFO  [/]'; Message = 'Render started' }
    [PSCustomObject]@{ Level = '[Black on BrightYellow] WARN  [/]'; Message = 'Buffer narrower than -Width' }
    [PSCustomObject]@{ Level = '[BrightWhite on Red] ERROR [/]'; Message = '[bold BrightRed]Column count mismatch[/]' }
    [PSCustomObject]@{ Level = '[BrightWhite on BrightBlue] DEBUG [/]'; Message = 'Anchor column = 8' }
) -Border Heavy -BorderColor DarkGray -HeaderColor BrightWhite -TextColor Gray | Out-AnsiHost

# 3d. Colour every part at once, including the rules
Show-DemoHeader '3d. Border, header, text, and title colours together'
Format-AnsiTable $components -Title '[bold]Coverage[/]' -TitleColor BrightYellow `
    -BorderColor BrightBlue -HeaderColor BrightMagenta -TextColor BrightWhite `
    -Align Left, Right, Center -ShowRowSeparators | Out-AnsiHost

# 4. Title
Show-DemoHeader '4. -Title (centered above the table) and -TitleColor'
Format-AnsiTable $components -Title 'PwshAnsi components' -TitleColor BrightWhite -BorderColor DarkGray | Out-AnsiHost

# 5. Alignment per column
Show-DemoHeader '5. -Align per column (numbers read better right-aligned)'
Format-AnsiTable $components -Align Left, Right, Center -BorderColor DarkGray | Out-AnsiHost

# 6. Headers and row separators
Show-DemoHeader '6. -HideHeaders and -ShowRowSeparators'
Format-AnsiTable $small -HideHeaders -BorderColor DarkGray | Out-AnsiHost
Format-AnsiTable $small -ShowRowSeparators -BorderColor DarkGray | Out-AnsiHost

# 7. Column selection and calculated columns
Show-DemoHeader '7. -Property (names and calculated columns)'
Format-AnsiTable $components -Property Component, Status | Out-AnsiHost
Format-AnsiTable $components -Property `
    @{ Name = 'Name'; Expression = { $_.Component -replace '^Format-Ansi', '' } },
@{ Name = 'Tests'; Expression = { $_.Tests } },
@{ Name = 'Share'; Expression = { '{0:p0}' -f ($_.Tests / 707) } } -Align Left, Right, Right | Out-AnsiHost

# 8. Width control and -Expand
Show-DemoHeader '8. -Width and -Expand'
Format-AnsiTable $small -Width 36 -BorderColor DarkGray | Out-AnsiHost
Format-AnsiTable $small -Expand -BorderColor DarkGray | Out-AnsiHost

# 9. Cell overflow — ellipsis by default, folding with -Wrap
Show-DemoHeader '9. Cell overflow: default vs -Wrap'
$notes = @(
    [PSCustomObject]@{ Key = 'Anchor'; Note = 'Every rendering resumes at the column the cursor started on, never column zero.' }
    [PSCustomObject]@{ Key = 'Colour'; Note = 'All colours come from $PSStyle; NO_COLOR strips styles but keeps the layout.' }
)
Format-AnsiTable $notes -Width 56 -BorderColor DarkGray | Out-AnsiHost
Write-Host ''
Format-AnsiTable $notes -Width 56 -Wrap -BorderColor DarkGray | Out-AnsiHost

# 10. Markup and markdown in cells
Show-DemoHeader '10. Markup / -Markdown in cells'
Format-AnsiTable @(
    [PSCustomObject]@{ Step = '[bold]Restore[/]'; Result = '[BrightGreen]:check: Ok[/]' }
    [PSCustomObject]@{ Step = '[bold]Compile[/]'; Result = '[BrightGreen]:check: Ok[/]' }
    [PSCustomObject]@{ Step = '[bold]Smoke[/]'; Result = '[BrightRed]:cross: Failed[/]' }
) -Markdown -BorderColor DarkGray | Out-AnsiHost

# 11. -Escape keeps cells literal
Show-DemoHeader '11. -Escape (cells stay literal)'
Format-AnsiTable @([PSCustomObject]@{ Pattern = '[bold]X[/]'; Meaning = '**Not** parsed' }) -Escape | Out-AnsiHost

# 12. Input shapes — hashtables, scalars, single object, pipeline
Show-DemoHeader '12. Input shapes'
Format-AnsiTable @(@{ key = 'Retries'; value = 3 }, @{ key = 'Timeout'; value = '30s' }) -Property key, value | Out-AnsiHost
Format-AnsiTable @('Alpha', 'Bravo', 'Charlie') | Out-AnsiHost
Format-AnsiTable ([PSCustomObject]@{ Single = 'Object'; Rows = 1 }) | Out-AnsiHost
Get-ChildItem -LiteralPath $srcRoot -File |
    Select-Object Name, Length |
    Format-AnsiTable -Align Left, Right -Border Horizontal | Out-AnsiHost

# 13. Anchoring — later rows resume at the anchor column
Show-DemoHeader '13. Anchoring'
Write-Host 'Table: ' -NoNewline -ForegroundColor DarkGray
Format-AnsiTable $small -Width 40 -BorderColor DarkGray | Out-AnsiHost

# 14. -NoNewline leaves the cursor on the last row
Show-DemoHeader '14. -NoNewline'
Format-AnsiTable ($components | Select-Object -First 1) -Border Square -BorderColor DarkGray | Out-AnsiHost -NoNewline
Write-Host ' ← Cursor stayed here' -ForegroundColor DarkGray

# 15. Usage pattern — a summary table with a total row
Show-DemoHeader '15. Usage pattern — summary with a total row'
$total = ($components | Measure-Object -Property Tests -Sum).Sum
$summary = @($components | Select-Object Component, Tests) +
@([PSCustomObject]@{ Component = '[bold]Total[/]'; Tests = $total })
Format-AnsiTable $summary -Align Left, Right -ShowRowSeparators:$false -BorderColor DarkGray -HeaderColor BrightWhite | Out-AnsiHost

# 16. Two panes — tables left and right
# Components write whole rows, so a side-by-side layout means capturing each
# pane's rows off the Information stream and zipping them. Padding is measured on
# visible width, with the ANSI stripped, so colours survive.
Show-DemoHeader '16. Two panes — tables left and right'

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
    Format-AnsiTable ($components | Select-Object -First 3 -Property `
        @{ Name = 'Name'; Expression = { $_.Component -replace '^Format-Ansi', '' } }, Tests) `
        -Width 34 -Align Left, Right -BorderColor DarkGray -HeaderColor BrightWhite | Out-AnsiHost
} -Right {
    Format-AnsiTable @(
        [PSCustomObject]@{ Border = 'Rounded'; Rules = 'Yes' }
        [PSCustomObject]@{ Border = 'Horizontal'; Rules = 'Rules only' }
        [PSCustomObject]@{ Border = 'None'; Rules = 'No' }
    ) -Width 34 -Border Square -BorderColor DarkGray -HeaderColor BrightCyan | Out-AnsiHost
}

# 17. Nested renderings — a rendering as a cell
Show-DemoHeader '17. Nested renderings inside table cells'
Format-AnsiTable @(
    [PSCustomObject]@{ Suite = 'Text'; Passed = 147; Failed = 0 }
    [PSCustomObject]@{ Suite = 'JSON'; Passed = 60; Failed = 7 }
) -Property `
    Suite,
@{ Name = 'A TREE in a CELL'; Expression = {
        Format-AnsiTree @{
            Value    = '[bold]Results[/]'
            Children = @(
                @{ Value = "passed $($_.Passed)" }
                @{ Value = "failed $($_.Failed)" }
            )
        } -MaxWidth 22 -Color BrightBlue -LabelColor BrightWhite
    }
},
@{ Name = 'Verdict'; Expression = {
        Format-AnsiText $(if ($_.Failed -gt 0) { '[BrightRed]:cross: Failing[/]' } else { '[BrightGreen]:check: Passing[/]' }) -Markdown -MaxWidth 16
    }
} -Border Heavy -BorderColor BrightMagenta -HeaderColor BrightWhite -ShowRowSeparators | Out-AnsiHost

# 18. NO_COLOR strips styles, keeps layout
Show-DemoHeader '18. NO_COLOR strips styles, keeps layout'
$prev = $env:NO_COLOR
try {
    $env:NO_COLOR = '1'
    Format-AnsiTable $small -Title 'Plain' -BorderColor BrightBlue -HeaderColor BrightWhite -Align Left, Right, Center | Out-AnsiHost
} finally {
    if ($null -eq $prev) { Remove-Item Env:NO_COLOR -ErrorAction SilentlyContinue }
    else { $env:NO_COLOR = $prev }
}

Show-DemoHeader 'Done'
Write-Host ''
