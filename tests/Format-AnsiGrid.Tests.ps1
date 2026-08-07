#Requires -Version 7.2
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

# Format-AnsiGrid.Tests.ps1
# Pester 5 tests for Format-AnsiGrid. Rendered output is captured off the
# Information stream (Write-Host redirect 6>&1) and inspected as strings.
#
# Get-AnsiAnchor and Test-AnsiNoColor are replaced inside the Format-AnsiGrid module
# scope (40-column buffer, colour forced on) so the suite is host-independent.
# Injection is used rather than Mock: Pester cannot mock a command a module
# merely imported from another module.

BeforeAll {
    $script:src = Join-Path (Split-Path -Parent $PSScriptRoot) 'src'
    Import-Module (Join-Path $script:src 'Format-AnsiGrid.psm1') -Force -DisableNameChecking
    Import-Module (Join-Path $script:src 'Out-AnsiHost.psm1') -Force -DisableNameChecking
    Import-Module (Join-Path $script:src 'Out-AnsiString.psm1') -Force -DisableNameChecking
    $script:AnsiModule = Get-Module Format-AnsiGrid

    $script:Ell = [string][char]0x2026
    $script:Buffer = 40

    & $script:AnsiModule {
        $script:AnsiTestColumn = 0
        $script:AnsiTestNoColor = $false

        Set-Item function:script:Get-AnsiAnchor -Value {
            param([int]$MaxWidth = 0)
            [PSCustomObject]@{
                Column      = $script:AnsiTestColumn
                BufferWidth = 40
                Width       = $(if ($MaxWidth -gt 0) { $MaxWidth } else { 40 - $script:AnsiTestColumn })
            }
        }

        Set-Item function:script:Test-AnsiNoColor -Value { $script:AnsiTestNoColor }
    }

    function Set-AnsiTestColumn {
        param([Parameter(Mandatory)][int]$Column)
        & $script:AnsiModule { param($c) $script:AnsiTestColumn = $c } $Column
    }

    function Set-AnsiTestNoColor {
        param([Parameter(Mandatory)][bool]$Value)
        & $script:AnsiModule { param($v) $script:AnsiTestNoColor = $v } $Value
    }

    # The block returns an [Ansi.Rendering]; painting it is this helper's job.
    function Invoke-AnsiLines {
        param([Parameter(Mandatory)][scriptblock]$Sb)
        $records = & { & $Sb | Out-AnsiHost } 6>&1
        if ($null -eq $records) { return , @() }
        $rows = @($records | ForEach-Object { [string]$_.ToString() })
        return , $rows
    }

    function Invoke-Ansi {
        param([Parameter(Mandatory)][scriptblock]$Sb)
        return ((Invoke-AnsiLines $Sb) -join "`n")
    }

    function Remove-Ansi {
        param([AllowEmptyString()][string]$Text)
        return ($Text -replace "`e\[[\d;]*m", '')
    }

    # Rows with ANSI stripped. Assignment rather than a pipe: piping the
    # comma-wrapped result would flatten it into one string.
    function Invoke-AnsiPlain {
        param([Parameter(Mandatory)][scriptblock]$Sb)
        $rows = Invoke-AnsiLines $Sb
        $plain = [System.Collections.Generic.List[string]]::new()
        foreach ($r in $rows) { $null = $plain.Add((Remove-Ansi $r)) }
        return , $plain.ToArray()
    }

    function Measure-Occurrence {
        param([string]$Text, [string]$Needle)
        return ([regex]::Matches($Text, [regex]::Escape($Needle))).Count
    }

    # Leading commas matter: @() collects statement output and unrolls arrays, so
    # newline-separated rows would flatten into one cell per row.
    $script:Grid = @(
        , @('Name', 'Tests', 'Status')
        , @('Text', '147', 'built')
        , @('Table', '78', 'built')
    )
    $script:Items = @('alpha', 'bravo', 'charlie', 'delta', 'echo', 'foxtrot', 'golf', 'hotel')
}

Describe 'Format-AnsiGrid — explicit rows' {
    It 'aligns columns and separates them by two spaces' {
        $rows = Invoke-AnsiPlain { Format-AnsiGrid $script:Grid }
        $rows | Should -Be @(
            'Name   Tests  Status'
            'Text   147    built'
            'Table  78     built'
        )
    }

    It 'draws no borders at all' {
        $out = Invoke-Ansi { Format-AnsiGrid $script:Grid }
        $out | Should -Not -Match '[─-╿+|]'
    }

    It 'leaves no trailing whitespace' {
        $rows = Invoke-AnsiPlain { Format-AnsiGrid $script:Grid }
        foreach ($r in $rows) { $r | Should -Not -Match '\s$' }
    }

    It 'accepts a single multi-cell row when it is comma-wrapped' {
        $rows = Invoke-AnsiPlain { Format-AnsiGrid @(, @('a', 'b', 'c')) }
        $rows | Should -Be @('a  b  c')
    }

    It 'treats a flat list of scalars as one cell per row' {
        $rows = Invoke-AnsiPlain { Format-AnsiGrid @('one', 'two') }
        $rows | Should -Be @('one', 'two')
    }

    It 'pads ragged rows without a tail' {
        $rows = Invoke-AnsiPlain { Format-AnsiGrid @(@('a', 'b', 'c'), @('d'), @('e', 'f')) }
        $rows | Should -Be @('a  b  c', 'd', 'e  f')
    }

    It 'renders one row per pipeline item' {
        $rows = Invoke-AnsiPlain { $script:Grid | Format-AnsiGrid }
        $rows.Count | Should -Be 3
    }

    It 'produces no output for $null' {
        $rows = Invoke-AnsiPlain { Format-AnsiGrid $null }
        $rows.Count | Should -Be 0
    }

    It 'renders empty cells as spaces' {
        $rows = Invoke-AnsiPlain { Format-AnsiGrid @(@('a', '', 'c'), @('x', 'y', 'z')) }
        $rows | Should -Be @('a     c', 'x  y  z')
    }
}

Describe 'Format-AnsiGrid — -Padding' {
    It 'defaults to two spaces between columns' {
        $rows = Invoke-AnsiPlain { Format-AnsiGrid $script:Grid }
        $rows[0] | Should -BeExactly 'Name   Tests  Status'
    }

    It 'widens the gap' {
        $rows = Invoke-AnsiPlain { Format-AnsiGrid $script:Grid -Padding 4 }
        $rows[0] | Should -BeExactly 'Name     Tests    Status'
    }

    It 'removes the gap at 0' {
        $rows = Invoke-AnsiPlain { Format-AnsiGrid $script:Grid -Padding 0 }
        $rows[0] | Should -BeExactly 'Name TestsStatus'
    }

    It 'rejects a negative padding' {
        { Format-AnsiGrid $script:Grid -Padding -1 } | Should -Throw
    }
}

Describe 'Format-AnsiGrid — -Align' {
    It 'left-aligns by default' {
        $rows = Invoke-AnsiPlain { Format-AnsiGrid $script:Grid }
        $rows[1] | Should -BeExactly 'Text   147    built'
    }

    It 'aligns per column' {
        $rows = Invoke-AnsiPlain { Format-AnsiGrid $script:Grid -Align Left, Right, Center }
        $rows[1] | Should -BeExactly 'Text     147  built'
        $rows[2] | Should -BeExactly 'Table     78  built'
    }

    It 'reuses the last value for the remaining columns' {
        $rows = Invoke-AnsiPlain { Format-AnsiGrid $script:Grid -Align Right }
        $rows[0] | Should -BeExactly ' Name  Tests  Status'
        $rows[1] | Should -BeExactly ' Text    147   built'
    }

    It 'rejects an unknown alignment' {
        { Format-AnsiGrid $script:Grid -Align Middle } | Should -Throw
    }
}

Describe 'Format-AnsiGrid — -ColumnWidth and -Expand' {
    It 'honours a fixed width per column' {
        $rows = Invoke-AnsiPlain { Format-AnsiGrid $script:Grid -ColumnWidth 8, 0, 10 }
        $rows[0] | Should -BeExactly 'Name      Tests  Status'
    }

    It 'sizes a column to content when its width is 0' {
        $rows = Invoke-AnsiPlain { Format-AnsiGrid $script:Grid -ColumnWidth 0, 0, 0 }
        $rows[0] | Should -BeExactly 'Name   Tests  Status'
    }

    It 'spreads the available width with -Expand' {
        # 40 columns - 2 gaps of 2 => 12 per column. The right edge carries no
        # trailing padding, so the row itself stops after the last cell.
        $rows = Invoke-AnsiPlain { Format-AnsiGrid $script:Grid -Expand }
        $rows[0] | Should -BeExactly ('Name' + (' ' * 10) + 'Tests' + (' ' * 9) + 'Status')
    }

    It 'spreads a given -MaxWidth with -Expand' {
        $rows = Invoke-AnsiPlain { Format-AnsiGrid $script:Grid -Expand -MaxWidth 30 }
        $rows[0] | Should -BeExactly ('Name' + (' ' * 7) + 'Tests' + (' ' * 5) + 'Status')
    }

    It 'accepts -Width as an alias of -MaxWidth' {
        $expanded = Invoke-AnsiPlain { Format-AnsiGrid $script:Grid -Expand -Width 30 }
        $alias = Invoke-AnsiPlain { Format-AnsiGrid $script:Grid -Expand -MaxWidth 30 }
        $expanded | Should -Be $alias
    }

    It 'never renders wider than the available width' {
        $wide = @(, @(('a' * 60), ('b' * 60)))
        $rows = Invoke-AnsiPlain { Format-AnsiGrid $wide }
        foreach ($r in $rows) { $r.Length | Should -BeLessOrEqual $script:Buffer }
    }
}

Describe 'Format-AnsiGrid — -Items (flow a flat list)' {
    It 'fits as many columns as the width allows' {
        # widest item 'foxtrot' = 7, +2 padding => 4 columns in 40
        $rows = Invoke-AnsiPlain { Format-AnsiGrid -Items $script:Items }
        $rows | Should -Be @(
            'alpha  bravo    charlie  delta'
            'echo   foxtrot  golf     hotel'
        )
    }

    It 'honours an explicit -ColumnCount' {
        $rows = Invoke-AnsiPlain { Format-AnsiGrid -Items $script:Items -ColumnCount 3 }
        $rows.Count | Should -Be 3
        $rows[0] | Should -BeExactly 'alpha  bravo  charlie'
        $rows[2] | Should -BeExactly 'golf   hotel'
    }

    It 'stacks vertically at -ColumnCount 1' {
        $rows = Invoke-AnsiPlain { Format-AnsiGrid -Items $script:Items -ColumnCount 1 }
        $rows.Count | Should -Be 8
        $rows[0] | Should -BeExactly 'alpha'
    }

    It 'uses fewer columns in a narrow width' {
        $rows = Invoke-AnsiPlain { Format-AnsiGrid -Items $script:Items -MaxWidth 20 }
        $rows.Count | Should -Be 4
        $rows[0] | Should -BeExactly 'alpha    bravo'
    }

    It 'never renders more columns than it has items' {
        $rows = Invoke-AnsiPlain { Format-AnsiGrid -Items @('a', 'b') }
        $rows | Should -Be @('a  b')
    }

    It 'aligns flowed columns' {
        # column widths 2 and 3, right-aligned, no trailing pad on the right edge
        $rows = Invoke-AnsiPlain { Format-AnsiGrid -Items @('a', 'bbb', 'cc', 'd') -ColumnCount 2 -Align Right }
        $rows | Should -Be @(' a  bbb', 'cc    d')
    }

    It 'accepts items from the pipeline' {
        $rows = Invoke-AnsiPlain { $script:Items | Format-AnsiGrid -ColumnCount 4 }
        $rows.Count | Should -Be 2
    }

    It 'rejects -ColumnCount 0' {
        { Format-AnsiGrid -Items $script:Items -ColumnCount 0 } | Should -Throw
    }

    It 'cannot combine -Rows and -Items' {
        { Format-AnsiGrid -Rows $script:Grid -Items $script:Items } | Should -Throw
    }
}

Describe 'Format-AnsiGrid — cell overflow' {
    BeforeAll {
        $script:LongRow = @(, @('key', 'a value far too long for this grid width'))
    }

    It 'ellipsises long cells by default' {
        $rows = Invoke-AnsiPlain { Format-AnsiGrid $script:LongRow -MaxWidth 30 }
        $rows.Count | Should -Be 1
        $rows[0] | Should -Match ([regex]::Escape($script:Ell))
        $rows[0].Length | Should -BeLessOrEqual 30
    }

    It 'folds long cells with -Wrap' {
        $rows = Invoke-AnsiPlain { Format-AnsiGrid $script:LongRow -MaxWidth 30 -Wrap }
        $rows.Count | Should -BeGreaterThan 1
        ($rows -join '') | Should -Not -Match ([regex]::Escape($script:Ell))
    }

    It 'keeps the other columns on the first line of a folded row' {
        $rows = Invoke-AnsiPlain { Format-AnsiGrid $script:LongRow -MaxWidth 30 -Wrap }
        $rows[0] | Should -BeLike 'key  *'
        $rows[1] | Should -Match '^ {5}\S'
    }

    It 'splits a cell containing a hard `n across rows' {
        $rows = Invoke-AnsiPlain { Format-AnsiGrid @(, @("line1`nline2", 'right')) }
        $rows | Should -Be @('line1  right', 'line2')
    }

    It 'does not need -Wrap for a hard `n' {
        $wrapped = Invoke-AnsiPlain { Format-AnsiGrid @(, @("line1`nline2", 'right')) -Wrap }
        $plain = Invoke-AnsiPlain { Format-AnsiGrid @(, @("line1`nline2", 'right')) }
        $wrapped | Should -Be $plain
    }
}

Describe 'Format-AnsiGrid — markup and colour' {
    It 'parses markup in cells' {
        $out = Invoke-Ansi { Format-AnsiGrid @(, @('[bold]k[/]', '[BrightGreen]v[/]')) }
        $out | Should -Match ([regex]::Escape($PSStyle.Bold))
        $out | Should -Match ([regex]::Escape($PSStyle.Foreground.BrightGreen))
        Remove-Ansi $out | Should -BeExactly 'k  v'
    }

    It 'sizes columns on visible width, not markup length' {
        $rows = Invoke-AnsiPlain { Format-AnsiGrid @(, @('[bold]k[/]', 'v')) }
        $rows[0] | Should -BeExactly 'k  v'
    }

    It 'renders markdown sugar with -Markdown' {
        $out = Invoke-Ansi { Format-AnsiGrid @(, @('**b**', ':check:')) -Markdown }
        $out | Should -Match ([regex]::Escape($PSStyle.Bold))
        Remove-Ansi $out | Should -BeExactly ('b  ' + [string][char]0x2713)
    }

    It 'treats cells as literal with -Escape' {
        $rows = Invoke-AnsiPlain { Format-AnsiGrid @(, @('[bold]k[/]', 'v')) -Escape }
        $rows[0] | Should -BeExactly '[bold]k[/]  v'
    }

    It 'colours every cell with -TextColor' {
        $out = Invoke-Ansi { Format-AnsiGrid @(, @('a', 'b')) -TextColor BrightCyan }
        Measure-Occurrence $out $PSStyle.Foreground.BrightCyan | Should -Be 2
    }

    It 'aliases -Color as -TextColor' {
        $out = Invoke-Ansi { Format-AnsiGrid @(, @('a')) -Color BrightCyan }
        $out | Should -Match ([regex]::Escape($PSStyle.Foreground.BrightCyan))
    }

    It 'lets a cell set its own colour via markup' {
        $out = Invoke-Ansi { Format-AnsiGrid @(, @('[BrightGreen]ok[/]', 'plain')) -TextColor DarkGray }
        $out | Should -Match ([regex]::Escape($PSStyle.Foreground.BrightGreen + 'ok'))
    }

    It 'throws on an unknown colour' {
        { Format-AnsiGrid $script:Grid -TextColor Nope } | Should -Throw
    }

    It 'throws on invalid markup in a cell' {
        { Format-AnsiGrid @(, @('[nosuch]x[/]')) } | Should -Throw
    }

    It 'does not throw on invalid markup under -Escape' {
        { Invoke-Ansi { Format-AnsiGrid @(, @('[nosuch]x')) -Escape } } | Should -Not -Throw
    }
}

Describe 'Format-AnsiGrid — nested renderings' {
    It 'places a rendering in a cell and grows the row to its height' {
        Import-Module (Join-Path $script:src 'Format-AnsiText.psm1') -Force -DisableNameChecking
        & (Get-Module Format-AnsiText) {
            Set-Item function:script:Get-AnsiAnchor -Value {
                param([int]$MaxWidth = 0)
                [PSCustomObject]@{ Column = 0; BufferWidth = 40; Width = $(if ($MaxWidth -gt 0) { $MaxWidth } else { 40 }) }
            }
            Set-Item function:script:Test-AnsiNoColor -Value { $false }
        }

        $text = Format-AnsiText "one`ntwo" -MaxWidth 5
        $rows = Invoke-AnsiPlain { Format-AnsiGrid @(, @('label', $text)) }

        $rows.Count | Should -Be 2
        $rows[0] | Should -BeExactly 'label  one'
        $rows[1] | Should -BeExactly '       two'
    }
}

Describe 'Format-AnsiGrid — anchoring' {
    BeforeAll { Set-AnsiTestColumn 4 }
    AfterAll { Set-AnsiTestColumn 0 }

    It 'leaves the first row where the cursor already is' {
        $rows = Invoke-AnsiPlain { Format-AnsiGrid $script:Grid }
        $rows[0] | Should -BeExactly 'Name   Tests  Status'
    }

    It 'resumes later rows at the anchor column' {
        $rows = Invoke-AnsiPlain { Format-AnsiGrid $script:Grid }
        $rows[1] | Should -BeExactly ((' ' * 4) + 'Text   147    built')
    }

    It 'sizes the grid to the remaining buffer with -Expand' {
        $rows = Invoke-AnsiPlain { Format-AnsiGrid $script:Grid -Expand }
        $unexpanded = 'Name   Tests  Status'.Length
        $rows[0].Length | Should -BeGreaterThan $unexpanded
        $rows[0].Length | Should -BeLessOrEqual ($script:Buffer - 4)
    }
}

Describe 'Format-AnsiGrid — | Out-AnsiHost -NoNewline' {
    BeforeEach {
        $script:hostCalls = [System.Collections.Generic.List[object]]::new()
        Mock -ModuleName Out-AnsiHost -CommandName Write-Host -MockWith {
            param($Object, [switch]$NoNewline)
            $script:hostCalls.Add([PSCustomObject]@{
                    Message   = [string]$Object
                    NoNewline = $NoNewline.IsPresent
                })
        }
    }

    It 'applies only to the final row' {
        Format-AnsiGrid $script:Grid | Out-AnsiHost -NoNewline
        $script:hostCalls.Count | Should -Be 3
        $script:hostCalls[-1].NoNewline | Should -BeTrue
        for ($i = 0; $i -lt $script:hostCalls.Count - 1; $i++) {
            $script:hostCalls[$i].NoNewline | Should -BeFalse
        }
    }

    It 'applies to the only row of a single-row grid' {
        Format-AnsiGrid @(, @('a', 'b')) | Out-AnsiHost -NoNewline
        $script:hostCalls.Count | Should -Be 1
        $script:hostCalls[0].NoNewline | Should -BeTrue
    }

    It 'never sets NoNewline when the switch is absent' {
        Format-AnsiGrid $script:Grid
        foreach ($c in $script:hostCalls) { $c.NoNewline | Should -BeFalse }
    }
}

Describe 'Format-AnsiGrid — no-colour output' {
    BeforeAll { Set-AnsiTestNoColor $true }
    AfterAll { Set-AnsiTestNoColor $false }

    It 'strips ANSI escape sequences' {
        $out = Invoke-Ansi { Format-AnsiGrid @(, @('[bold]k[/]', 'v')) -TextColor BrightCyan }
        $out | Should -Not -Match ([regex]::Escape([char]27))
        $out | Should -BeExactly 'k  v'
    }

    It 'preserves alignment and padding' {
        $rows = Invoke-AnsiLines { Format-AnsiGrid $script:Grid -Align Right -Padding 3 }
        $rows[1] | Should -BeExactly ' Text     147    built'
    }

    It 'preserves flowed columns and truncation' {
        $flowed = Invoke-AnsiLines { Format-AnsiGrid -Items $script:Items -ColumnCount 4 }
        $flowed.Count | Should -Be 2

        $cropped = Invoke-AnsiLines { Format-AnsiGrid @(, @('key', ('x' * 60))) -MaxWidth 20 }
        $cropped[0] | Should -Match ([regex]::Escape($script:Ell))
    }
}

Describe 'Format-AnsiGrid — module surface' {
    It 'exports only the formatter' {
        (Get-Module Format-AnsiGrid).ExportedFunctions.Keys | Should -Be 'Format-AnsiGrid'
    }
}
