#Requires -Version 7.2

# Demo-AnsiTree.ps1
# Exercises every parameter and feature of Format-AnsiTree, painted with Out-AnsiHost.
# Run: pwsh -File .\demo\Demo-AnsiTree.ps1

$ErrorActionPreference = 'Stop'
$srcRoot = Join-Path (Split-Path -Parent $PSScriptRoot) 'src'

Import-Module (Join-Path $srcRoot 'Format-AnsiTree.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $srcRoot 'Format-AnsiGrid.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $srcRoot 'Format-AnsiPanel.psm1') -Force -DisableNameChecking

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

$repo = @{
    Value    = 'PwshAnsi'
    Children = @(
        @{ Value = 'src'; Children = @(
                @{ Value = 'Ansi.Core.psm1' }
                @{ Value = 'Format-AnsiText.psm1' }
                @{ Value = 'Format-AnsiRule.psm1' }
                @{ Value = 'Format-AnsiTree.psm1' }
            )
        }
        @{ Value = 'tests'; Children = @(
                @{ Value = 'Format-AnsiText.Tests.ps1' }
                @{ Value = 'Format-AnsiTree.Tests.ps1' }
            )
        }
        @{ Value = 'docs'; Children = @(@{ Value = 'Overview.md' }) }
        @{ Value = 'README.md' }
    )
}

# 1. Default rendering
Show-DemoHeader '1. Nested hashtable, default Line guides'
Format-AnsiTree $repo | Out-AnsiHost

# 2. Guide styles
Show-DemoHeader '2. -Guide Line / DoubleLine / BoldLine / Ascii'
$small = @{ Value = 'Root'; Children = @(@{ Value = 'First'; Children = @(@{ Value = 'Nested' }) }, @{ Value = 'Last' }) }
foreach ($guide in 'Line', 'DoubleLine', 'BoldLine', 'Ascii') {
    Write-Host "  $guide" -ForegroundColor DarkGray
    Format-AnsiTree $small -Guide $guide | Out-AnsiHost
    Write-Host ''
}

# 3. Colours — guides and labels are independent
Show-DemoHeader '3. -Color (guides) and -LabelColor'
Format-AnsiTree $repo -Color DarkGray -LabelColor BrightWhite | Out-AnsiHost

# 4. Markup and markdown in labels
Show-DemoHeader '4. Markup / -Markdown labels'
Format-AnsiTree @{
    Value    = '[bold]Build[/]'
    Children = @(
        @{ Value = '[BrightGreen]Restore[/] :check:' }
        @{ Value = '**Compile** in `Release`' }
        @{ Value = '[BrightRed]Pack[/] :cross: failed' }
    )
} -Markdown -Color DarkGray | Out-AnsiHost

# 5. -Escape keeps labels literal
Show-DemoHeader '5. -Escape (labels stay literal)'
Format-AnsiTree @{ Value = '[bold]Not parsed[/]'; Children = @(@{ Value = '**Either**' }) } -Escape | Out-AnsiHost

# 6. -MaxDepth collapses deeper branches
Show-DemoHeader '6. -MaxDepth collapses deeper branches to …'
Format-AnsiTree $repo -MaxDepth 1 -Color DarkGray | Out-AnsiHost
Write-Host ''
Format-AnsiTree $repo -MaxDepth 2 -Color DarkGray | Out-AnsiHost

# 7. Long labels wrap under the label column
Show-DemoHeader '7. Label wrapping (aligns under the label, not the guide)'
Format-AnsiTree @{
    Value    = 'Notes'
    Children = @(
        @{ Value = 'A deliberately long label that has to wrap across several rows to fit' }
        @{ Value = 'Short one' }
    )
} -MaxWidth 40 -Color DarkGray | Out-AnsiHost

# 8. Alternative shapes — Name/Items, PSCustomObject, custom properties
Show-DemoHeader '8. Alternative input shapes'
Format-AnsiTree @{ Name = 'Name/Items'; Items = @(@{ Name = 'Child' }) } | Out-AnsiHost
Format-AnsiTree ([PSCustomObject]@{ Value = 'PSCustomObject'; Children = @([PSCustomObject]@{ Value = 'Child' }) }) | Out-AnsiHost
Format-AnsiTree @{ label = '-Property / -ChildProperty'; kids = @(@{ label = 'Child' }) } -Property label -ChildProperty kids | Out-AnsiHost

# 9. Bare values and forests
Show-DemoHeader '9. Bare values and forests'
Format-AnsiTree 'A single leaf' | Out-AnsiHost
Format-AnsiTree @(
    @{ Value = 'First tree'; Children = @(@{ Value = 'Child' }) }
    @{ Value = 'Second tree' }
) | Out-AnsiHost

# 10. Pipeline input — one tree per item
Show-DemoHeader '10. Pipeline input'
@{ Value = 'Piped-1' }, @{ Value = 'Piped-2'; Children = @(@{ Value = 'Child' }) } | Format-AnsiTree -Color DarkGray | Out-AnsiHost

# 11. Anchoring — later rows resume at the anchor column
Show-DemoHeader '11. Anchoring'
Write-Host 'Tree: ' -NoNewline -ForegroundColor DarkGray
Format-AnsiTree $small -Color DarkGray | Out-AnsiHost

# 12. -NoNewline leaves the cursor on the last row
Show-DemoHeader '12. -NoNewline'
Format-AnsiTree $small -Color DarkGray | Out-AnsiHost -NoNewline
Write-Host ' ← Cursor stayed here' -ForegroundColor DarkGray

# 13. Usage pattern — a real directory tree
Show-DemoHeader '13. Usage pattern — a real directory tree'
function ConvertTo-DemoTree {
    param([System.IO.DirectoryInfo]$Directory, [int]$Depth = 2)
    $children = @()
    if ($Depth -gt 0) {
        foreach ($dir in Get-ChildItem -LiteralPath $Directory.FullName -Directory) {
            $children += ConvertTo-DemoTree -Directory $dir -Depth ($Depth - 1)
        }
        foreach ($file in Get-ChildItem -LiteralPath $Directory.FullName -File) {
            $children += @{ Value = $file.Name }
        }
    }
    return @{ Value = '[bold]' + $Directory.Name + '[/]'; Children = $children }
}
$root = Get-Item -LiteralPath (Split-Path -Parent $PSScriptRoot)
Format-AnsiTree (ConvertTo-DemoTree -Directory $root -Depth 2) -Color DarkGray -MaxWidth 60 | Out-AnsiHost

# 14. Two panes — one tree left, one right
# Components write whole rows, so a side-by-side layout means capturing each
# pane's rows off the Information stream and zipping them together. Padding is
# measured on visible width, with the ANSI stripped, so colours stay intact.
Show-DemoHeader '14. Two panes — one tree left, one right'

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

$leftTree = @{
    Value    = '[bold]Src[/]'
    Children = @(
        @{ Value = 'Ansi.Core.psm1' }
        @{ Value = 'Format-AnsiText.psm1' }
        @{ Value = 'Format-AnsiRule.psm1' }
        @{ Value = 'Format-AnsiPath.psm1' }
        @{ Value = 'Format-AnsiJson.psm1' }
        @{ Value = 'Format-AnsiTree.psm1' }
    )
}
$rightTree = @{
    Value    = '[bold]Docs[/]'
    Children = @(
        @{ Value = 'Overview.md' }
        @{ Value = 'Colours.md' }
        @{ Value = 'Markup.md' }
        @{ Value = 'Components'; Children = @(
                @{ Value = 'Format-AnsiText.md' }
                @{ Value = 'Format-AnsiTree.md' }
            )
        }
    )
}

$paneWidth = 30
$gutter = '  ' + [string][char]0x2502 + '  '   # │
$leftRows = Get-DemoRows { Format-AnsiTree $leftTree -MaxWidth $paneWidth -Color DarkGray -LabelColor BrightWhite | Out-AnsiHost }
$rightRows = Get-DemoRows { Format-AnsiTree $rightTree -MaxWidth $paneWidth -Color DarkGray -LabelColor BrightCyan | Out-AnsiHost }

$rowCount = [Math]::Max($leftRows.Count, $rightRows.Count)
for ($i = 0; $i -lt $rowCount; $i++) {
    $left = ''
    if ($i -lt $leftRows.Count) { $left = $leftRows[$i] }
    $right = ''
    if ($i -lt $rightRows.Count) { $right = $rightRows[$i] }
    $pad = ' ' * [Math]::Max(0, $paneWidth - (Measure-DemoVisibleLength $left))
    Write-Host ($left + $pad + $gutter + $right)
}

# 15. Nested renderings — a rendering as a node label
Show-DemoHeader '15. Nested renderings as tree labels'
# A TABLE hanging off a branch, and a PANEL off another
$countTable = Format-AnsiTable @(
    [PSCustomObject]@{ Suite = 'Text'; Passed = 147 }
    [PSCustomObject]@{ Suite = 'Tree'; Passed = 69 }
) -Border Heavy -MaxWidth 30 -BorderColor BrightMagenta -HeaderColor BrightWhite -Align Left, Right
$summary = Format-AnsiPanel 'All suites green' -Border Square -BorderColor BrightGreen -TextColor BrightWhite

Format-AnsiTree @{
    Value    = '[bold]Test run[/]'
    Children = @(
        @{ Value = $countTable }
        @{ Value = 'Duration 13s' }
        @{ Value = $summary }
    )
} -Color BrightBlue -LabelColor BrightWhite | Out-AnsiHost

# 16. NO_COLOR strips styles, keeps layout
Show-DemoHeader '16. NO_COLOR strips styles, keeps layout'
$prev = $env:NO_COLOR
try {
    $env:NO_COLOR = '1'
    Format-AnsiTree $small -Color BrightBlue -LabelColor BrightWhite | Out-AnsiHost
} finally {
    if ($null -eq $prev) { Remove-Item Env:NO_COLOR -ErrorAction SilentlyContinue }
    else { $env:NO_COLOR = $prev }
}

Show-DemoHeader 'Done'
Write-Host ''
