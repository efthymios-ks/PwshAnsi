#Requires -Version 7.2
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

# Format-AnsiBreakdownChart.Tests.ps1
# Pester 5 tests for Format-AnsiBreakdownChart. Rendered output is captured off the
# Information stream (Write-Host redirect 6>&1) or read back with Out-AnsiString.
#
# As elsewhere, two Ansi.Core helpers are replaced inside the module scope to make
# the suite host-independent:
#   Get-AnsiAnchor    — pinned to a known column and a 40-column buffer.
#   Test-AnsiNoColor  — driven by Set-AnsiTestNoColor, not the environment.
# Injection is used rather than Mock: Pester cannot mock a command a module
# merely imported from another module.

BeforeAll {
    $script:src = Join-Path (Split-Path -Parent $PSScriptRoot) 'src'
    Import-Module (Join-Path $script:src 'Format-AnsiBreakdownChart.psm1') -Force -DisableNameChecking
    Import-Module (Join-Path $script:src 'Out-AnsiHost.psm1') -Force -DisableNameChecking
    Import-Module (Join-Path $script:src 'Out-AnsiString.psm1') -Force -DisableNameChecking
    Import-Module (Join-Path $script:src 'Format-AnsiPanel.psm1') -DisableNameChecking
    $script:AnsiModule = Get-Module Format-AnsiBreakdownChart

    $script:Full = [string][char]0x2588     # █
    $script:Light = [string][char]0x2591    # ░
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

    # The rows of a chart, colour and all stripped.
    function Get-AnsiPlain {
        param([Parameter(Mandatory)][scriptblock]$Sb)
        $rows = & $Sb | Out-AnsiString -Plain
        if ($null -eq $rows) { return , @() }
        return , @($rows)
    }

    function Reset-AnsiTest {
        Set-AnsiTestColumn -Column 0
        Set-AnsiTestNoColor -Value $true
    }

    # 10 / 5 / 5 out of 20: halves and quarters, so the cells divide exactly.
    function New-AnsiTestData {
        return , @(
            [PSCustomObject]@{ Label = 'apples'; Value = 10 }
            [PSCustomObject]@{ Label = 'oranges'; Value = 5 }
            [PSCustomObject]@{ Label = 'bananas'; Value = 5 }
        )
    }
}

Describe 'Format-AnsiBreakdownChart — the bar' {
    BeforeEach { Reset-AnsiTest }

    It 'splits one full-width bar between the parts' {
        $rows = Get-AnsiPlain { Format-AnsiBreakdownChart (New-AnsiTestData) -Width 20 -HideTags }
        $rows.Count | Should -Be 1
        $rows[0] | Should -BeExactly ($script:Full * 20)
    }

    It 'sizes each part by its share' {
        $rendering = Format-AnsiBreakdownChart (New-AnsiTestData) -Width 20 -HideTags
        $runs = @($rendering.Rows[0])
        $runs.Count | Should -Be 3
        $runs[0].Text.Length | Should -Be 10
        $runs[1].Text.Length | Should -Be 5
        $runs[2].Text.Length | Should -Be 5
    }

    It 'hands the cells the floors left over to the largest remainders' {
        # 1/1/1 across 37 cells is 12.33 each: three floors of 12, one cell over.
        $rendering = Format-AnsiBreakdownChart @(1, 1, 1) -Width 37 -HideTags
        $runs = @($rendering.Rows[0])
        ($runs | Measure-Object -Property { $_.Text.Length } -Sum).Sum | Should -Be 37
        $runs[0].Text.Length | Should -Be 13
        $runs[1].Text.Length | Should -Be 12
        $runs[2].Text.Length | Should -Be 12
    }

    It 'never loses a part that has a value' {
        # 1 in 1001 rounds to nothing across 10 cells; it still gets a cell.
        $rendering = Format-AnsiBreakdownChart @(1000, 1) -Width 10 -HideTags
        $runs = @($rendering.Rows[0])
        $runs.Count | Should -Be 2
        $runs[0].Text.Length | Should -Be 9
        $runs[1].Text.Length | Should -Be 1
    }

    It 'draws an empty bar when nothing has a value' {
        $rows = Get-AnsiPlain { Format-AnsiBreakdownChart @(0, 0) -Width 20 -HideTags }
        $rows[0] | Should -BeExactly ($script:Light * 20)
    }

    It 'ignores a negative value' {
        $rendering = Format-AnsiBreakdownChart @(10, -5) -Width 10 -HideTags
        $runs = @($rendering.Rows[0])
        $runs[0].Text.Length | Should -Be 10
        $runs.Count | Should -Be 1
    }

    It 'draws <Style> with its own characters' -ForEach @(
        @{ Style = 'Blocks'; Filled = 0x2588; Empty = 0x2591 }
        @{ Style = 'Line'; Filled = 0x2501; Empty = 0x2500 }
        @{ Style = 'Dots'; Filled = 0x25CF; Empty = 0x00B7 }
    ) {
        # Not $filled / $empty: variable names are case-insensitive, and those
        # would overwrite the -ForEach data.
        $withValue = Get-AnsiPlain { Format-AnsiBreakdownChart @(1) -Width 10 -HideTags -Style $Style }
        $without = Get-AnsiPlain { Format-AnsiBreakdownChart @(0) -Width 10 -HideTags -Style $Style }
        $withValue[0] | Should -BeExactly ([string][char]$Filled * 10)
        $without[0] | Should -BeExactly ([string][char]$Empty * 10)
    }

    It 'draws Ascii with hashes and dashes' {
        $withValue = Get-AnsiPlain { Format-AnsiBreakdownChart @(1) -Width 10 -HideTags -Style Ascii }
        $without = Get-AnsiPlain { Format-AnsiBreakdownChart @(0) -Width 10 -HideTags -Style Ascii }
        $withValue[0] | Should -BeExactly ('#' * 10)
        $without[0] | Should -BeExactly ('-' * 10)
    }

    It 'rejects an unknown style' {
        { Format-AnsiBreakdownChart @(1) -Style Sparkles } | Should -Throw
    }
}

Describe 'Format-AnsiBreakdownChart — the legend' {
    BeforeEach { Reset-AnsiTest }

    It 'names every part under the bar' {
        $rows = Get-AnsiPlain { Format-AnsiBreakdownChart (New-AnsiTestData) -Width 40 }
        $rows.Count | Should -Be 2
        $rows[1] | Should -BeExactly (
            "$script:Full apples 10   $script:Full oranges 5   $script:Full bananas 5")
    }

    It 'drops the legend with -HideTags' {
        (Format-AnsiBreakdownChart (New-AnsiTestData) -Width 40 -HideTags).RowCount | Should -Be 1
    }

    It 'drops the numbers with -HideTagValues' {
        $rows = Get-AnsiPlain { Format-AnsiBreakdownChart (New-AnsiTestData) -Width 40 -HideTagValues }
        $rows[1] | Should -BeExactly (
            "$script:Full apples   $script:Full oranges   $script:Full bananas")
    }

    It 'shows each share with -ShowPercentage' {
        # 44 cells, because the percentages make the legend wider than the values.
        $rows = Get-AnsiPlain { Format-AnsiBreakdownChart (New-AnsiTestData) -Width 44 -ShowPercentage }
        $rows[1] | Should -BeExactly (
            "$script:Full apples 50%   $script:Full oranges 25%   $script:Full bananas 25%")
    }

    It 'formats the numbers with -ValueFormat' {
        $rows = Get-AnsiPlain { Format-AnsiBreakdownChart (New-AnsiTestData) -Width 40 -ValueFormat 'N1' }
        $rows[1] | Should -Match ([regex]::Escape('apples 10.0'))
    }

    It 'flows as many tags onto a row as fit' {
        # Each tag is 11 cells; two need 25, so a 20-cell chart takes one per row.
        $rows = Get-AnsiPlain { Format-AnsiBreakdownChart (New-AnsiTestData) -Width 20 }
        $rows.Count | Should -Be 4
        $rows[1] | Should -BeExactly "$script:Full apples 10"
        $rows[3] | Should -BeExactly "$script:Full bananas 5"
    }

    It 'puts one tag per row with -FullSize' {
        $rows = Get-AnsiPlain { Format-AnsiBreakdownChart (New-AnsiTestData) -Width 40 -FullSize }
        $rows.Count | Should -Be 4
        $rows[2] | Should -BeExactly "$script:Full oranges 5"
    }

    It 'keeps whole numbers whole and fractions to one decimal' {
        $rows = Get-AnsiPlain { Format-AnsiBreakdownChart @(4, 1.5) -Width 40 }
        $rows[1] | Should -Match '4\s'
        $rows[1] | Should -Match '1\.5$'
    }

    It 'reads markup in a tag' {
        Set-AnsiTestNoColor -Value $false
        $out = Invoke-Ansi {
            Format-AnsiBreakdownChart @([PSCustomObject]@{ Label = '[BrightRed]hot[/]'; Value = 1 }) -Width 20
        }
        $out | Should -Match ([regex]::Escape($PSStyle.Foreground.BrightRed))
        $out | Should -Match 'hot'
    }

    It 'takes a tag literally with -Escape' {
        $rows = Get-AnsiPlain {
            Format-AnsiBreakdownChart @([PSCustomObject]@{ Label = '[BrightRed]hot[/]'; Value = 1 }) -Width 40 -Escape
        }
        $rows[1] | Should -Match ([regex]::Escape('[BrightRed]hot[/]'))
    }
}

Describe 'Format-AnsiBreakdownChart — the data' {
    BeforeEach { Reset-AnsiTest }

    It 'takes the items from the pipeline' {
        $rows = New-AnsiTestData | Format-AnsiBreakdownChart -Width 20 -HideTags | Out-AnsiString -Plain
        @($rows)[0] | Should -BeExactly ($script:Full * 20)
    }

    It 'takes hashtables' {
        $rows = Get-AnsiPlain {
            Format-AnsiBreakdownChart @(
                @{ Label = 'apples'; Value = 10 }
                @{ Label = 'oranges'; Value = 10 }
            ) -Width 40 -HideTagValues
        }
        $rows[1] | Should -BeExactly "$script:Full apples   $script:Full oranges"
    }

    It 'takes bare numbers' {
        $rows = Get-AnsiPlain { Format-AnsiBreakdownChart @(10, 10) -Width 20 -HideTags }
        $rows[0] | Should -BeExactly ($script:Full * 20)
    }

    It 'reads any object through the -*Property names' {
        $rows = Get-AnsiPlain {
            Format-AnsiBreakdownChart @(
                [PSCustomObject]@{ Name = 'web'; Hits = 20; Hue = 'BrightGreen' }
                [PSCustomObject]@{ Name = 'api'; Hits = 20; Hue = 'BrightRed' }
            ) -Width 40 -LabelProperty Name -ValueProperty Hits -ColorProperty Hue -HideTagValues
        }
        $rows[1] | Should -BeExactly "$script:Full web   $script:Full api"
    }

    It 'skips a null item' {
        $rendering = Format-AnsiBreakdownChart @(10, $null, 10) -Width 20 -HideTags
        @($rendering.Rows[0]).Count | Should -Be 2
    }

    It 'writes nothing at all for no items' {
        Format-AnsiBreakdownChart @() | Should -BeNullOrEmpty
    }

    It 'rejects an item with no value' {
        { Format-AnsiBreakdownChart @([PSCustomObject]@{ Label = 'a' }) } | Should -Throw '*has no Value*'
    }

    It 'rejects a value that is not a number' {
        { Format-AnsiBreakdownChart @([PSCustomObject]@{ Label = 'a'; Value = 'lots' }) } |
            Should -Throw '*not a number*'
    }
}

Describe 'Format-AnsiBreakdownChart — width' {
    BeforeEach { Reset-AnsiTest }

    It 'fills the anchor width by default' {
        $rows = Get-AnsiPlain { Format-AnsiBreakdownChart @(1) -HideTags }
        $rows[0].Length | Should -Be $script:Buffer
    }

    It 'leaves room for the caller column' {
        Set-AnsiTestColumn -Column 10
        $rows = Get-AnsiPlain { Format-AnsiBreakdownChart @(1) -HideTags }
        $rows[0].Length | Should -Be ($script:Buffer - 10)
    }

    It 'reports the column it was anchored at' {
        Set-AnsiTestColumn -Column 7
        (Format-AnsiBreakdownChart @(1)).Column | Should -Be 7
    }

    It 'takes -MaxWidth as an alias for -Width' {
        $rows = Get-AnsiPlain { Format-AnsiBreakdownChart @(1) -MaxWidth 12 -HideTags }
        $rows[0].Length | Should -Be 12
    }

    It 'reports the width of its widest row' {
        (Format-AnsiBreakdownChart @(1) -Width 25 -HideTags).Width | Should -Be 25
    }
}

Describe 'Format-AnsiBreakdownChart — colour' {
    BeforeEach { Set-AnsiTestNoColor -Value $false }

    It 'hands out the palette in turn' {
        $out = Invoke-Ansi { Format-AnsiBreakdownChart @(10, 10) -Width 20 -HideTags }
        $out | Should -Match ([regex]::Escape($PSStyle.Foreground.BrightCyan))
        $out | Should -Match ([regex]::Escape($PSStyle.Foreground.BrightGreen))
    }

    It 'takes the palette from -Palette' {
        $out = Invoke-Ansi { Format-AnsiBreakdownChart @(10, 10) -Width 20 -HideTags -Palette BrightRed, BrightBlue }
        $out | Should -Match ([regex]::Escape($PSStyle.Foreground.BrightRed))
        $out | Should -Match ([regex]::Escape($PSStyle.Foreground.BrightBlue))
        $out | Should -Not -Match ([regex]::Escape($PSStyle.Foreground.BrightCyan))
    }

    It "lets an item's own colour win" {
        $out = Invoke-Ansi {
            Format-AnsiBreakdownChart @([PSCustomObject]@{ Label = 'a'; Value = 1; Color = 'BrightYellow' }) `
                -Width 20 -HideTags
        }
        $out | Should -Match ([regex]::Escape($PSStyle.Foreground.BrightYellow))
        $out | Should -Not -Match ([regex]::Escape($PSStyle.Foreground.BrightCyan))
    }

    It 'colours a tag like the part it names' {
        $out = Invoke-Ansi {
            Format-AnsiBreakdownChart @([PSCustomObject]@{ Label = 'a'; Value = 1; Color = 'BrightMagenta' }) -Width 20
        }
        ([regex]::Matches($out, [regex]::Escape($PSStyle.Foreground.BrightMagenta))).Count |
            Should -BeGreaterThan 1
    }

    It 'overrides the tag text with -TagColor and the numbers with -ValueColor' {
        $out = Invoke-Ansi {
            Format-AnsiBreakdownChart (New-AnsiTestData) -Width 40 -TagColor BrightWhite -ValueColor BrightYellow
        }
        $out | Should -Match ([regex]::Escape($PSStyle.Foreground.BrightWhite))
        $out | Should -Match ([regex]::Escape($PSStyle.Foreground.BrightYellow))
    }

    It 'keeps the layout and drops the colour under NO_COLOR' {
        Set-AnsiTestNoColor -Value $true
        $out = Invoke-Ansi { Format-AnsiBreakdownChart @(10, 10) -Width 20 -HideTags }
        $out | Should -BeExactly ($script:Full * 20)
    }

    It 'rejects an unknown colour' {
        { Format-AnsiBreakdownChart @(1) -Palette Chartreuse } | Should -Throw '*Unknown color*'
        { Format-AnsiBreakdownChart @(1) -TagColor Chartreuse } | Should -Throw '*Unknown color*'
        { Format-AnsiBreakdownChart @([PSCustomObject]@{ Label = 'a'; Value = 1; Color = '#FFFF00' }) } |
            Should -Throw '*Unknown color*'
    }
}

Describe 'Format-AnsiBreakdownChart — the rendering' {
    BeforeEach { Reset-AnsiTest }

    It 'returns an Ansi.Rendering of kind BreakdownChart' {
        $rendering = Format-AnsiBreakdownChart (New-AnsiTestData) -Width 40
        $rendering.PSObject.TypeNames | Should -Contain 'Ansi.Rendering'
        $rendering.Kind | Should -BeExactly 'BreakdownChart'
    }

    It 'is the bar plus however many rows the legend needs' {
        (Format-AnsiBreakdownChart (New-AnsiTestData) -Width 40).RowCount | Should -Be 2
        (Format-AnsiBreakdownChart (New-AnsiTestData) -Width 40 -FullSize).RowCount | Should -Be 4
    }

    It 'writes nothing on its own' {
        $records = & { $null = Format-AnsiBreakdownChart (New-AnsiTestData) } 6>&1
        $records | Should -BeNullOrEmpty
    }

    It 'nests in a panel' {
        # Assignment first: Out-AnsiString returns the lines comma-wrapped, so
        # @(pipeline) would nest them and the join would print a type name.
        $chart = Format-AnsiBreakdownChart (New-AnsiTestData) -Width 20 -HideTags
        $lines = Format-AnsiPanel $chart -Border Square | Out-AnsiString -Plain
        ($lines -join "`n") | Should -Match ([regex]::Escape($script:Full * 20))
    }

    It 'exports one function' {
        (Get-Module Format-AnsiBreakdownChart).ExportedFunctions.Keys |
            Should -Be @('Format-AnsiBreakdownChart')
    }
}
