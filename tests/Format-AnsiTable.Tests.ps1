#Requires -Version 7.2
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

# Format-AnsiTable.Tests.ps1
# Pester 5 tests for Format-AnsiTable. Rendered output is captured off the
# Information stream (Write-Host redirect 6>&1) and inspected as strings.
#
# Get-AnsiAnchor and Test-AnsiNoColor are replaced inside the Format-AnsiTable module
# scope (60-column buffer, colour forced on) so the suite is host-independent.
# Injection is used rather than Mock: Pester cannot mock a command a module
# merely imported from another module.

BeforeAll {
    $script:src = Join-Path (Split-Path -Parent $PSScriptRoot) 'src'
    Import-Module (Join-Path $script:src 'Format-AnsiTable.psm1') -Force -DisableNameChecking
    Import-Module (Join-Path $script:src 'Out-AnsiHost.psm1') -Force -DisableNameChecking
    Import-Module (Join-Path $script:src 'Out-AnsiString.psm1') -Force -DisableNameChecking
    $script:AnsiModule = Get-Module Format-AnsiTable

    $script:Ell = [string][char]0x2026
    $script:Buffer = 60

    # Rounded (default) glyphs.
    $script:TL = [string][char]0x256D; $script:TM = [string][char]0x252C; $script:TR = [string][char]0x256E
    $script:ML = [string][char]0x251C; $script:MX = [string][char]0x253C; $script:MR = [string][char]0x2524
    $script:BL = [string][char]0x2570; $script:BM = [string][char]0x2534; $script:BR = [string][char]0x256F
    $script:H = [string][char]0x2500; $script:V = [string][char]0x2502

    & $script:AnsiModule {
        $script:AnsiTestColumn = 0
        $script:AnsiTestNoColor = $false

        Set-Item function:script:Get-AnsiAnchor -Value {
            param([int]$MaxWidth = 0)
            [PSCustomObject]@{
                Column      = $script:AnsiTestColumn
                BufferWidth = 60
                Width       = $(if ($MaxWidth -gt 0) { $MaxWidth } else { 60 - $script:AnsiTestColumn })
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

    $script:Data = @(
        [PSCustomObject]@{ Name = 'Text'; Tests = 147; Status = 'built' }
        [PSCustomObject]@{ Name = 'Rule'; Tests = 78; Status = 'built' }
        [PSCustomObject]@{ Name = 'Table'; Tests = 0; Status = 'wip' }
    )
}

Describe 'Format-AnsiTable — default rendering' {
    It 'draws a rounded, headed table sized to its content' {
        $rows = Invoke-AnsiPlain { Format-AnsiTable $script:Data }
        $rows | Should -Be @(
            ($script:TL + ($script:H * 7) + $script:TM + ($script:H * 7) + $script:TM + ($script:H * 8) + $script:TR)
            ($script:V + ' Name  ' + $script:V + ' Tests ' + $script:V + ' Status ' + $script:V)
            ($script:ML + ($script:H * 7) + $script:MX + ($script:H * 7) + $script:MX + ($script:H * 8) + $script:MR)
            ($script:V + ' Text  ' + $script:V + ' 147   ' + $script:V + ' built  ' + $script:V)
            ($script:V + ' Rule  ' + $script:V + ' 78    ' + $script:V + ' built  ' + $script:V)
            ($script:V + ' Table ' + $script:V + ' 0     ' + $script:V + ' wip    ' + $script:V)
            ($script:BL + ($script:H * 7) + $script:BM + ($script:H * 7) + $script:BM + ($script:H * 8) + $script:BR)
        )
    }

    It 'sizes every row to the same width' {
        $rows = Invoke-AnsiPlain { Format-AnsiTable $script:Data }
        $expected = $rows[0].Length
        foreach ($r in $rows) { $r.Length | Should -Be $expected }
    }

    It 'pads each cell with one space on both sides' {
        $rows = Invoke-AnsiPlain { Format-AnsiTable $script:Data }
        $rows[3] | Should -BeLike ($script:V + ' Text*')
    }

    It 'produces header, rule, and one row per item' {
        $rows = Invoke-AnsiPlain { Format-AnsiTable $script:Data }
        $rows.Count | Should -Be 7
    }
}

Describe 'Format-AnsiTable — -Border' {
    It '<Border> draws with <Corner>' -ForEach @(
        @{ Border = 'Rounded'; Corner = [string][char]0x256D }
        @{ Border = 'Square'; Corner = [string][char]0x250C }
        @{ Border = 'Heavy'; Corner = [string][char]0x250F }
        @{ Border = 'Double'; Corner = [string][char]0x2554 }
        @{ Border = 'Ascii'; Corner = '+' }
    ) {
        $b = $Border
        $rows = Invoke-AnsiPlain { Format-AnsiTable $script:Data -Border $b }
        $rows[0].StartsWith($Corner) | Should -BeTrue
    }

    It 'None drops every glyph and separates columns with two spaces' {
        $rows = Invoke-AnsiPlain { Format-AnsiTable $script:Data -Border None }
        $rows | Should -Be @(
            'Name   Tests  Status'
            'Text   147    built '
            'Rule   78     built '
            'Table  0      wip   '
        )
    }

    It 'Horizontal keeps rules but no verticals' {
        $rows = Invoke-AnsiPlain { Format-AnsiTable $script:Data -Border Horizontal }
        $rows.Count | Should -Be 7
        $rows[0] | Should -BeExactly ($script:H * 20)
        $rows[1] | Should -BeExactly 'Name   Tests  Status'
        $rows[2] | Should -BeExactly ($script:H * 20)
        $rows[-1] | Should -BeExactly ($script:H * 20)
    }

    It 'is case-insensitive' {
        { Invoke-Ansi { Format-AnsiTable $script:Data -Border 'double' } } | Should -Not -Throw
    }

    It 'rejects an unknown border' {
        { Format-AnsiTable $script:Data -Border Wiggly } | Should -Throw
    }
}

Describe 'Format-AnsiTable — headers, rules, and title' {
    It 'omits the header and its rule with -HideHeaders' {
        $rows = Invoke-AnsiPlain { Format-AnsiTable $script:Data -HideHeaders }
        $rows.Count | Should -Be 5
        $rows[1] | Should -BeLike ($script:V + ' Text*')
    }

    It 'sizes columns to the body only when headers are hidden' {
        $rows = Invoke-AnsiPlain { Format-AnsiTable $script:Data -HideHeaders }
        $rows[1] | Should -BeExactly ($script:V + ' Text  ' + $script:V + ' 147 ' + $script:V + ' built ' + $script:V)
    }

    It 'adds a rule between rows with -ShowRowSeparators' {
        $rows = Invoke-AnsiPlain { Format-AnsiTable $script:Data -ShowRowSeparators }
        $rows.Count | Should -Be 9
        $rows[4] | Should -BeExactly ($script:ML + ($script:H * 7) + $script:MX + ($script:H * 7) + $script:MX + ($script:H * 8) + $script:MR)
    }

    It 'does not add a separator after the last row' {
        $rows = Invoke-AnsiPlain { Format-AnsiTable $script:Data -ShowRowSeparators }
        $rows[-1].StartsWith($script:BL) | Should -BeTrue
    }

    It 'centers -Title above the table' {
        $rows = Invoke-AnsiPlain { Format-AnsiTable $script:Data -Title 'Components' }
        # table width 26, title 10 => 8 leading spaces
        $rows[0] | Should -BeExactly ((' ' * 8) + 'Components')
        $rows[1].StartsWith($script:TL) | Should -BeTrue
    }

    It 'truncates a title wider than the table' {
        $rows = Invoke-AnsiPlain { Format-AnsiTable $script:Data -Title ('t' * 80) }
        $rows[0].Length | Should -Be 26
        $rows[0] | Should -Match ([regex]::Escape($script:Ell))
    }

    It 'parses markup in the title' {
        $out = Invoke-Ansi { Format-AnsiTable $script:Data -Title '[bold]Components[/]' }
        $out | Should -Match ([regex]::Escape($PSStyle.Bold))
    }
}

Describe 'Format-AnsiTable — -Align' {
    It 'left-aligns by default' {
        $rows = Invoke-AnsiPlain { Format-AnsiTable $script:Data }
        $rows[4] | Should -BeExactly ($script:V + ' Rule  ' + $script:V + ' 78    ' + $script:V + ' built  ' + $script:V)
    }

    It 'aligns per column' {
        $rows = Invoke-AnsiPlain { Format-AnsiTable $script:Data -Align Left, Right, Center }
        $rows[4] | Should -BeExactly ($script:V + ' Rule  ' + $script:V + '    78 ' + $script:V + ' built  ' + $script:V)
        $rows[5] | Should -BeExactly ($script:V + ' Table ' + $script:V + '     0 ' + $script:V + '  wip   ' + $script:V)
    }

    It 'reuses the last value for the remaining columns' {
        $rows = Invoke-AnsiPlain { Format-AnsiTable $script:Data -Align Right }
        $rows[3] | Should -BeExactly ($script:V + '  Text ' + $script:V + '   147 ' + $script:V + '  built ' + $script:V)
    }

    It 'aligns headers the same way as the body' {
        $rows = Invoke-AnsiPlain { Format-AnsiTable $script:Data -Align Right }
        $rows[1] | Should -BeExactly ($script:V + '  Name ' + $script:V + ' Tests ' + $script:V + ' Status ' + $script:V)
    }

    It 'rejects an unknown alignment' {
        { Format-AnsiTable $script:Data -Align Middle } | Should -Throw
    }
}

Describe 'Format-AnsiTable — -Property' {
    It 'selects and orders columns by name' {
        $rows = Invoke-AnsiPlain { Format-AnsiTable $script:Data -Property Status, Name }
        $rows[1] | Should -BeExactly ($script:V + ' Status ' + $script:V + ' Name  ' + $script:V)
    }

    It 'accepts a calculated column with Name/Expression' {
        $rows = Invoke-AnsiPlain {
            Format-AnsiTable $script:Data -Property Name, @{ Name = 'x2'; Expression = { $_.Tests * 2 } }
        }
        $rows[1] | Should -BeExactly ($script:V + ' Name  ' + $script:V + ' x2  ' + $script:V)
        $rows[3] | Should -BeExactly ($script:V + ' Text  ' + $script:V + ' 294 ' + $script:V)
    }

    It 'accepts Label/E as aliases' {
        $rows = Invoke-AnsiPlain {
            Format-AnsiTable $script:Data -Property @{ Label = 'n'; E = { $_.Name } }
        }
        $rows[1] | Should -BeExactly ($script:V + ' n     ' + $script:V)
    }

    It 'renders an empty cell for a missing property' {
        $rows = Invoke-AnsiPlain { Format-AnsiTable $script:Data -Property Name, Missing }
        $rows[3] | Should -BeExactly ($script:V + ' Text  ' + $script:V + '         ' + $script:V)
    }

    It 'takes -Property positionally' {
        $rows = Invoke-AnsiPlain { Format-AnsiTable $script:Data Name }
        $rows[1] | Should -BeExactly ($script:V + ' Name  ' + $script:V)
    }
}

Describe 'Format-AnsiTable — input shapes' {
    It 'uses the properties of the first item as columns' {
        $rows = Invoke-AnsiPlain { Format-AnsiTable $script:Data }
        $rows[1] | Should -Match 'Name'
        $rows[1] | Should -Match 'Status'
    }

    It 'renders hashtable rows' {
        $rows = Invoke-AnsiPlain { Format-AnsiTable @(@{ k = 'a'; v = 1 }, @{ k = 'b'; v = 2 }) -Property k, v }
        $rows[1] | Should -BeExactly ($script:V + ' k ' + $script:V + ' v ' + $script:V)
        $rows[3] | Should -BeExactly ($script:V + ' a ' + $script:V + ' 1 ' + $script:V)
    }

    It 'renders ordered dictionary rows in key order' {
        $rows = Invoke-AnsiPlain { Format-AnsiTable @([ordered]@{ z = 1; a = 2 }) }
        $rows[1] | Should -BeExactly ($script:V + ' z ' + $script:V + ' a ' + $script:V)
    }

    It 'renders scalars under a Value column' {
        $rows = Invoke-AnsiPlain { Format-AnsiTable @('one', 'two') }
        $rows[1] | Should -BeExactly ($script:V + ' Value ' + $script:V)
        $rows[3] | Should -BeExactly ($script:V + ' one   ' + $script:V)
    }

    It 'renders a single object as one row' {
        $rows = Invoke-AnsiPlain { Format-AnsiTable ([PSCustomObject]@{ A = 1; B = 2 }) }
        $rows.Count | Should -Be 5
        $rows[3] | Should -BeExactly ($script:V + ' 1 ' + $script:V + ' 2 ' + $script:V)
    }

    It 'accumulates pipeline items into one table' {
        $rows = Invoke-AnsiPlain { $script:Data | Format-AnsiTable }
        $rows.Count | Should -Be 7
    }

    It 'accepts cmdlet output' {
        $rows = Invoke-AnsiPlain { Get-Item -LiteralPath $script:src | Format-AnsiTable -Property Name }
        $rows[3] | Should -Match 'src'
    }

    It 'renders empty cells for $null and empty values' {
        $rows = Invoke-AnsiPlain { Format-AnsiTable @([PSCustomObject]@{ A = $null; B = '' }) }
        $rows[3] | Should -BeExactly ($script:V + '   ' + $script:V + '   ' + $script:V)
    }

    It 'produces no output for $null' {
        $rows = Invoke-AnsiPlain { Format-AnsiTable $null }
        $rows.Count | Should -Be 0
    }

    It 'produces no output for an empty collection' {
        $rows = Invoke-AnsiPlain { Format-AnsiTable @() }
        $rows.Count | Should -Be 0
    }
}

Describe 'Format-AnsiTable — width and -Expand' {
    It 'honours -Width by shrinking the widest column first' {
        $rows = Invoke-AnsiPlain { Format-AnsiTable $script:Data -Width 24 }
        foreach ($r in $rows) { $r.Length | Should -Be 24 }
        $rows[1] | Should -BeExactly ($script:V + ' Name ' + $script:V + ' Tests ' + $script:V + ' Stat' + $script:Ell + ' ' + $script:V)
    }

    It 'ellipsises cells that no longer fit' {
        $rows = Invoke-AnsiPlain { Format-AnsiTable $script:Data -Width 24 }
        $rows[5] | Should -BeExactly ($script:V + ' Tab' + $script:Ell + ' ' + $script:V + ' 0     ' + $script:V + ' wip   ' + $script:V)
    }

    It 'never renders wider than the anchored width' {
        $wide = @([PSCustomObject]@{ A = ('a' * 80); B = ('b' * 80) })
        $rows = Invoke-AnsiPlain { Format-AnsiTable $wide }
        foreach ($r in $rows) { $r.Length | Should -BeLessOrEqual $script:Buffer }
    }

    It 'accepts -MaxWidth as an alias of -Width' {
        $rows = Invoke-AnsiPlain { Format-AnsiTable $script:Data -MaxWidth 24 }
        $rows[0].Length | Should -Be 24
    }

    It 'fills the width with -Expand' {
        $rows = Invoke-AnsiPlain { Format-AnsiTable $script:Data -Expand }
        foreach ($r in $rows) { $r.Length | Should -Be $script:Buffer }
    }

    It 'fills a given -Width with -Expand' {
        $rows = Invoke-AnsiPlain { Format-AnsiTable $script:Data -Expand -Width 40 }
        foreach ($r in $rows) { $r.Length | Should -Be 40 }
    }

    It 'does not expand without the switch' {
        $rows = Invoke-AnsiPlain { Format-AnsiTable $script:Data -Width 40 }
        $rows[0].Length | Should -Be 26
    }
}

Describe 'Format-AnsiTable — cell overflow' {
    BeforeAll {
        $script:LongRow = @([PSCustomObject]@{
                K = 'note'
                V = 'a very long value that will not fit inside the table width'
            })
    }

    It 'ellipsises long cells by default' {
        $rows = Invoke-AnsiPlain { Format-AnsiTable $script:LongRow -Width 30 }
        $rows.Count | Should -Be 5
        $rows[3] | Should -Match ([regex]::Escape($script:Ell))
    }

    It 'folds long cells with -Wrap' {
        $rows = Invoke-AnsiPlain { Format-AnsiTable $script:LongRow -Width 30 -Wrap }
        $rows.Count | Should -BeGreaterThan 5
        ($rows -join '') | Should -Not -Match ([regex]::Escape($script:Ell))
    }

    It 'pads shorter columns across a wrapped row' {
        $rows = Invoke-AnsiPlain { Format-AnsiTable $script:LongRow -Width 30 -Wrap }
        foreach ($r in $rows) { $r.Length | Should -Be 30 }
        $rows[4] | Should -BeLike ($script:V + '      ' + $script:V + '*')
    }

    It 'splits a cell containing a hard `n across rows' {
        $rows = Invoke-AnsiPlain { Format-AnsiTable @([PSCustomObject]@{ A = "one`ntwo"; B = 'x' }) -Wrap }
        $rows.Count | Should -Be 6
        $rows[3] | Should -BeExactly ($script:V + ' one ' + $script:V + ' x ' + $script:V)
        $rows[4] | Should -BeExactly ($script:V + ' two ' + $script:V + '   ' + $script:V)
    }

    It 'keeps cell styling across a wrap' {
        $styled = @([PSCustomObject]@{ V = '[bold]' + ('word ' * 10) + '[/]' })
        $out = Invoke-Ansi { Format-AnsiTable $styled -Width 20 -Wrap }
        Measure-Occurrence $out $PSStyle.Bold | Should -BeGreaterOrEqual 2
    }
}

Describe 'Format-AnsiTable — colours' {
    It 'colours borders with -BorderColor' {
        $out = Invoke-Ansi { Format-AnsiTable $script:Data -BorderColor DarkGray }
        $out | Should -Match ([regex]::Escape($PSStyle.Foreground.BrightBlack + $script:TL))
    }

    It 'colours headers with -HeaderColor' {
        $out = Invoke-Ansi { Format-AnsiTable $script:Data -HeaderColor BrightWhite }
        $out | Should -Match ([regex]::Escape($PSStyle.Foreground.BrightWhite + 'Name'))
    }

    It 'colours body cells with -TextColor' {
        $out = Invoke-Ansi { Format-AnsiTable $script:Data -TextColor BrightCyan }
        $out | Should -Match ([regex]::Escape($PSStyle.Foreground.BrightCyan + 'Text'))
    }

    It 'colours the title with -TitleColor' {
        $out = Invoke-Ansi { Format-AnsiTable $script:Data -Title 'T' -TitleColor BrightMagenta }
        $out | Should -Match ([regex]::Escape($PSStyle.Foreground.BrightMagenta + 'T'))
    }

    It 'leaves headers and cells unstyled by default' {
        $rows = Invoke-AnsiLines { Format-AnsiTable @([PSCustomObject]@{ A = 1 }) }
        $rows[1] | Should -BeExactly ($script:V + ' A ' + $script:V)
    }

    It 'lets a cell set its own colour via markup' {
        $out = Invoke-Ansi { Format-AnsiTable @([PSCustomObject]@{ A = '[BrightGreen]ok[/]' }) -TextColor DarkGray }
        $out | Should -Match ([regex]::Escape($PSStyle.Foreground.BrightGreen + 'ok'))
    }

    It 'throws on an unknown <Parameter>' -ForEach @(
        @{ Parameter = 'BorderColor' }
        @{ Parameter = 'HeaderColor' }
        @{ Parameter = 'TextColor' }
        @{ Parameter = 'TitleColor' }
    ) {
        $splat = @{ $Parameter = 'Nope' }
        { Format-AnsiTable $script:Data @splat } | Should -Throw
    }
}

Describe 'Format-AnsiTable — markup in cells' {
    It 'parses markup by default' {
        $out = Invoke-Ansi { Format-AnsiTable @([PSCustomObject]@{ A = '[bold]x[/]' }) }
        $out | Should -Match ([regex]::Escape($PSStyle.Bold))
        (Remove-Ansi $out) -split "`n" | Should -Contain ($script:V + ' x ' + $script:V)
    }

    It 'sizes columns on visible width, not markup length' {
        $rows = Invoke-AnsiPlain { Format-AnsiTable @([PSCustomObject]@{ A = '[bold]x[/]' }) }
        $rows[0].Length | Should -Be 5
    }

    It 'renders markdown sugar with -Markdown' {
        $out = Invoke-Ansi { Format-AnsiTable @([PSCustomObject]@{ A = '**x**' }) -Markdown }
        $out | Should -Match ([regex]::Escape($PSStyle.Bold))
    }

    It 'replaces emoji with -Markdown' {
        $rows = Invoke-AnsiPlain { Format-AnsiTable @([PSCustomObject]@{ A = ':check:' }) -Markdown }
        $rows[3] | Should -BeExactly ($script:V + ' ' + [string][char]0x2713 + ' ' + $script:V)
    }

    It 'treats cells as literal with -Escape' {
        $rows = Invoke-AnsiPlain { Format-AnsiTable @([PSCustomObject]@{ A = '[bold]x[/]' }) -Escape }
        $rows[3] | Should -BeExactly ($script:V + ' [bold]x[/] ' + $script:V)
    }

    It 'throws on invalid markup in a cell' {
        { Format-AnsiTable @([PSCustomObject]@{ A = '[nosuch]x[/]' }) } | Should -Throw
    }

    It 'does not throw on invalid markup under -Escape' {
        { Invoke-Ansi { Format-AnsiTable @([PSCustomObject]@{ A = '[nosuch]x' }) -Escape } } | Should -Not -Throw
    }
}

Describe 'Format-AnsiTable — nested renderings' {
    It 'uses a rendering returned by a calculated column as the cell' {
        Import-Module (Join-Path $script:src 'Format-AnsiGrid.psm1') -Force -DisableNameChecking
        & (Get-Module Format-AnsiGrid) {
            Set-Item function:script:Get-AnsiAnchor -Value {
                param([int]$MaxWidth = 0)
                [PSCustomObject]@{ Column = 0; BufferWidth = 60; Width = $(if ($MaxWidth -gt 0) { $MaxWidth } else { 60 }) }
            }
            Set-Item function:script:Test-AnsiNoColor -Value { $false }
        }

        $rows = Invoke-AnsiPlain {
            Format-AnsiTable @([PSCustomObject]@{ Name = 'suite' }) -Property `
                Name,
            @{ Name = 'Detail'; Expression = { Format-AnsiGrid @(, @('pass', '3'), @('fail', '1')) -MaxWidth 20 } }
        }

        # The nested grid is two rows tall, so the table row grows with it.
        $rows.Count | Should -Be 6
        $rows[3] | Should -BeExactly ($script:V + ' suite ' + $script:V + ' pass  3 ' + $script:V)
        $rows[4] | Should -BeExactly ($script:V + '       ' + $script:V + ' fail  1 ' + $script:V)
    }
}

Describe 'Format-AnsiTable — anchoring' {
    BeforeAll { Set-AnsiTestColumn 4 }
    AfterAll { Set-AnsiTestColumn 0 }

    It 'leaves the first row where the cursor already is' {
        $rows = Invoke-AnsiPlain { Format-AnsiTable $script:Data -Width 26 }
        $rows[0].StartsWith($script:TL) | Should -BeTrue
    }

    It 'resumes later rows at the anchor column' {
        $rows = Invoke-AnsiPlain { Format-AnsiTable $script:Data -Width 26 }
        $rows[1] | Should -BeExactly ((' ' * 4) + $script:V + ' Name  ' + $script:V + ' Tests ' + $script:V + ' Status ' + $script:V)
    }

    It 'sizes the table to the remaining buffer with -Expand' {
        $rows = Invoke-AnsiPlain { Format-AnsiTable $script:Data -Expand }
        (Remove-Ansi $rows[0]).Length | Should -Be ($script:Buffer - 4)
    }
}

Describe 'Format-AnsiTable — | Out-AnsiHost -NoNewline' {
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
        Format-AnsiTable $script:Data | Out-AnsiHost -NoNewline
        $script:hostCalls.Count | Should -Be 7
        $script:hostCalls[-1].NoNewline | Should -BeTrue
        for ($i = 0; $i -lt $script:hostCalls.Count - 1; $i++) {
            $script:hostCalls[$i].NoNewline | Should -BeFalse
        }
    }

    It 'never sets NoNewline when the switch is absent' {
        Format-AnsiTable $script:Data
        foreach ($c in $script:hostCalls) { $c.NoNewline | Should -BeFalse }
    }
}

Describe 'Format-AnsiTable — no-colour output' {
    BeforeAll { Set-AnsiTestNoColor $true }
    AfterAll { Set-AnsiTestNoColor $false }

    It 'strips ANSI escape sequences' {
        $out = Invoke-Ansi {
            Format-AnsiTable $script:Data -BorderColor DarkGray -HeaderColor BrightWhite -TextColor BrightCyan
        }
        $out | Should -Not -Match ([regex]::Escape([char]27))
    }

    It 'preserves the border layout' {
        $rows = Invoke-AnsiLines { Format-AnsiTable $script:Data }
        $rows[1] | Should -BeExactly ($script:V + ' Name  ' + $script:V + ' Tests ' + $script:V + ' Status ' + $script:V)
        $rows[-1].StartsWith($script:BL) | Should -BeTrue
    }

    It 'preserves alignment, truncation, and titles' {
        $rows = Invoke-AnsiLines { Format-AnsiTable $script:Data -Width 24 -Align Right -Title 'T' }
        $rows[0] | Should -BeExactly ((' ' * 11) + 'T')
        $rows[2] | Should -Match ([regex]::Escape($script:Ell))
    }
}

Describe 'Format-AnsiTable — module surface' {
    It 'exports only the formatter' {
        (Get-Module Format-AnsiTable).ExportedFunctions.Keys | Should -Be 'Format-AnsiTable'
    }
}
