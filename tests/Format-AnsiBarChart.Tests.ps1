#Requires -Version 7.2
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

# Format-AnsiBarChart.Tests.ps1
# Pester 5 tests for Format-AnsiBarChart. Rendered output is captured off the
# Information stream (Write-Host redirect 6>&1) or read back with Out-AnsiString.
#
# As elsewhere, two Ansi.Core helpers are replaced inside the Format-AnsiBarChart
# module scope to make the suite host-independent:
#   Get-AnsiAnchor    — pinned to a known column and a 40-column buffer.
#   Test-AnsiNoColor  — driven by Set-AnsiTestNoColor, not the environment.
# Injection is used rather than Mock: Pester cannot mock a command a module
# merely imported from another module.

BeforeAll {
    $script:src = Join-Path (Split-Path -Parent $PSScriptRoot) 'src'
    Import-Module (Join-Path $script:src 'Format-AnsiBarChart.psm1') -Force -DisableNameChecking
    Import-Module (Join-Path $script:src 'Out-AnsiHost.psm1') -Force -DisableNameChecking
    Import-Module (Join-Path $script:src 'Out-AnsiString.psm1') -Force -DisableNameChecking
    Import-Module (Join-Path $script:src 'Format-AnsiPanel.psm1') -DisableNameChecking
    $script:AnsiModule = Get-Module Format-AnsiBarChart

    $script:Full = [string][char]0x2588     # █
    $script:Heavy = [string][char]0x2501    # ━
    $script:Dot = [string][char]0x25CF      # ●
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

    # apples 10, oranges 5: a 7-cell label column and a 2-cell value column.
    function New-AnsiTestData {
        return , @(
            [PSCustomObject]@{ Label = 'apples'; Value = 10 }
            [PSCustomObject]@{ Label = 'oranges'; Value = 5 }
        )
    }
}

Describe 'Format-AnsiBarChart — the bars' {
    BeforeEach { Reset-AnsiTest }

    It 'draws one row per item, scaled to the largest value' {
        # 30 wide less a 8-cell label column and a 3-cell value column: 19 bar cells.
        $rows = Get-AnsiPlain { Format-AnsiBarChart (New-AnsiTestData) -Width 30 }
        $rows.Count | Should -Be 2
        $rows[0] | Should -BeExactly (' apples ' + ($script:Full * 19) + ' 10')
        $rows[1] | Should -BeExactly ('oranges ' + ($script:Full * 10) + (' ' * 10) + '5')
    }

    It 'gives the bar what the values leave with -HideValues' {
        $rows = Get-AnsiPlain { Format-AnsiBarChart (New-AnsiTestData) -Width 30 -HideValues }
        $rows[0] | Should -BeExactly (' apples ' + ($script:Full * 22))
        $rows[1] | Should -BeExactly ('oranges ' + ($script:Full * 11))
    }

    It 'scales against -MaxValue instead of the data' {
        $rows = Get-AnsiPlain { Format-AnsiBarChart (New-AnsiTestData) -Width 30 -MaxValue 20 }
        $rows[0] | Should -BeExactly (' apples ' + ($script:Full * 10) + (' ' * 10) + '10')
        $rows[1] | Should -BeExactly ('oranges ' + ($script:Full * 5) + (' ' * 15) + '5')
    }

    It 'never draws an empty bar for a value past zero' {
        $rows = Get-AnsiPlain { Format-AnsiBarChart @(1000, 1) -Width 20 -HideValues }
        $rows[0] | Should -BeExactly ($script:Full * 20)
        $rows[1] | Should -BeExactly $script:Full
    }

    It 'draws nothing at all for zero' {
        $rows = Get-AnsiPlain { Format-AnsiBarChart @(10, 0) -Width 20 -HideValues }
        $rows[1] | Should -BeExactly ''
    }

    It 'draws nothing for a negative value, and still prints it' {
        $rows = Get-AnsiPlain { Format-AnsiBarChart @(10, -5) -Width 20 }
        $rows[1] | Should -Match '^\s+-5$'
    }

    It 'draws every bar empty when nothing has a value' {
        $rows = Get-AnsiPlain { Format-AnsiBarChart @(0, 0) -Width 20 -HideValues }
        $rows[0] | Should -BeExactly ''
        $rows[1] | Should -BeExactly ''
    }

    It 'draws <Style> with its own character' -ForEach @(
        @{ Style = 'Blocks'; Filled = 0x2588 }
        @{ Style = 'Line'; Filled = 0x2501 }
        @{ Style = 'Dots'; Filled = 0x25CF }
    ) {
        $rows = Get-AnsiPlain { Format-AnsiBarChart @(10) -Width 12 -HideValues -Style $Style }
        $rows[0] | Should -BeExactly ([string][char]$Filled * 12)
    }

    It 'draws Ascii with hashes' {
        $rows = Get-AnsiPlain { Format-AnsiBarChart @(10) -Width 12 -HideValues -Style Ascii }
        $rows[0] | Should -BeExactly ('#' * 12)
    }

    It 'rejects an unknown style' {
        { Format-AnsiBarChart @(1) -Style Sparkles } | Should -Throw
    }
}

Describe 'Format-AnsiBarChart — labels and values' {
    BeforeEach { Reset-AnsiTest }

    It 'right-aligns the label column by default' {
        $rows = Get-AnsiPlain { Format-AnsiBarChart (New-AnsiTestData) -Width 30 -HideValues }
        $rows[0] | Should -Match '^ apples '
    }

    It 'left-aligns the labels with -LabelAlignment Left' {
        $rows = Get-AnsiPlain { Format-AnsiBarChart (New-AnsiTestData) -Width 30 -HideValues -LabelAlignment Left }
        $rows[0] | Should -Match '^apples  '
    }

    It 'pads the label column to -LabelWidth' {
        $rows = Get-AnsiPlain { Format-AnsiBarChart (New-AnsiTestData) -Width 30 -LabelWidth 10 }
        $rows[0] | Should -BeExactly ('    apples ' + ($script:Full * 16) + ' 10')
    }

    It 'drops the label column when nothing is labelled' {
        $rows = Get-AnsiPlain { Format-AnsiBarChart @(10, 5) -Width 20 }
        $rows[0] | Should -BeExactly (($script:Full * 17) + ' 10')
        $rows[1] | Should -BeExactly (($script:Full * 9) + (' ' * 9) + '5')
    }

    It 'puts the values in a column of their own' {
        $rows = Get-AnsiPlain { Format-AnsiBarChart (New-AnsiTestData) -Width 30 }
        $rows[0].IndexOf('10') | Should -Be $rows[1].IndexOf('5')
    }

    It 'keeps whole numbers whole and fractions to one decimal' {
        $rows = Get-AnsiPlain { Format-AnsiBarChart @(4, 1.5) -Width 20 }
        $rows[0] | Should -Match '4$'
        $rows[1] | Should -Match '1\.5$'
    }

    It 'formats the values with -ValueFormat' {
        $rows = Get-AnsiPlain { Format-AnsiBarChart @(4, 1.5) -Width 20 -ValueFormat 'N2' }
        $rows[0] | Should -Match '4\.00$'
        $rows[1] | Should -Match '1\.50$'
    }

    It 'shows each share with -ShowPercentage' {
        $rows = Get-AnsiPlain { Format-AnsiBarChart (New-AnsiTestData) -Width 30 -ShowPercentage }
        $rows[0] | Should -Match '66\.7%$'
        $rows[1] | Should -Match '33\.3%$'
    }

    It 'shows the shares to no decimals with -ValueFormat' {
        $rows = Get-AnsiPlain { Format-AnsiBarChart (New-AnsiTestData) -Width 30 -ShowPercentage -ValueFormat 'N0' }
        $rows[0] | Should -Match '67%$'
    }

    It 'reads markup in a label' {
        Set-AnsiTestNoColor -Value $false
        $out = Invoke-Ansi { Format-AnsiBarChart @([PSCustomObject]@{ Label = '[BrightRed]hot[/]'; Value = 1 }) -Width 20 }
        $out | Should -Match ([regex]::Escape($PSStyle.Foreground.BrightRed))
        $out | Should -Match 'hot'
    }

    It 'takes a label literally with -Escape' {
        $rows = Get-AnsiPlain {
            Format-AnsiBarChart @([PSCustomObject]@{ Label = '[BrightRed]hot[/]'; Value = 1 }) -Width 40 -Escape
        }
        $rows[0] | Should -Match ([regex]::Escape('[BrightRed]hot[/]'))
    }

    It 'collapses a hard break in a label' {
        $rows = Get-AnsiPlain {
            Format-AnsiBarChart @([PSCustomObject]@{ Label = "two`nlines"; Value = 1 }) -Width 30 -HideValues
        }
        $rows[0] | Should -Match '^two lines '
    }
}

Describe 'Format-AnsiBarChart — the title' {
    BeforeEach { Reset-AnsiTest }

    It 'centers the title over the chart' {
        $rows = Get-AnsiPlain { Format-AnsiBarChart (New-AnsiTestData) 'sales' -Width 30 }
        $rows.Count | Should -Be 3
        $rows[0] | Should -BeExactly ((' ' * 12) + 'sales')
    }

    It 'aligns the title <Alignment>' -ForEach @(
        @{ Alignment = 'Left'; Pad = 0 }
        @{ Alignment = 'Center'; Pad = 12 }
        @{ Alignment = 'Right'; Pad = 25 }
    ) {
        $rows = Get-AnsiPlain { Format-AnsiBarChart (New-AnsiTestData) 'sales' -Width 30 -TitleAlignment $Alignment }
        $rows[0] | Should -BeExactly ((' ' * $Pad) + 'sales')
    }

    It 'takes -Title as an alias for -Label' {
        $rows = Get-AnsiPlain { Format-AnsiBarChart (New-AnsiTestData) -Title 'sales' -Width 30 -TitleAlignment Left }
        $rows[0] | Should -BeExactly 'sales'
    }

    It 'colours the title with -TitleColor' {
        Set-AnsiTestNoColor -Value $false
        $out = Invoke-Ansi { Format-AnsiBarChart (New-AnsiTestData) 'sales' -Width 30 -TitleColor BrightCyan }
        $out | Should -Match ([regex]::Escape($PSStyle.Foreground.BrightCyan))
    }
}

Describe 'Format-AnsiBarChart — the data' {
    BeforeEach { Reset-AnsiTest }

    It 'takes the items from the pipeline' {
        $rows = New-AnsiTestData | Format-AnsiBarChart -Width 30 -HideValues | Out-AnsiString -Plain
        @($rows).Count | Should -Be 2
        @($rows)[0] | Should -BeExactly (' apples ' + ($script:Full * 22))
    }

    It 'takes hashtables' {
        $rows = Get-AnsiPlain {
            Format-AnsiBarChart @(
                @{ Label = 'apples'; Value = 10 }
                @{ Label = 'oranges'; Value = 5 }
            ) -Width 30 -HideValues
        }
        $rows[0] | Should -BeExactly (' apples ' + ($script:Full * 22))
    }

    It 'takes bare numbers' {
        $rows = Get-AnsiPlain { Format-AnsiBarChart @(10, 5) -Width 20 -HideValues }
        $rows[0] | Should -BeExactly ($script:Full * 20)
    }

    It 'reads any object through the -*Property names' {
        $rows = Get-AnsiPlain {
            Format-AnsiBarChart @(
                [PSCustomObject]@{ Name = 'web'; Hits = 20; Hue = 'BrightGreen' }
                [PSCustomObject]@{ Name = 'api'; Hits = 10; Hue = 'BrightRed' }
            ) -Width 30 -HideValues -LabelProperty Name -ValueProperty Hits -ColorProperty Hue
        }
        $rows[0] | Should -Match '^web '
        $rows[1] | Should -Match '^api '
    }

    It 'parses a value written as text' {
        $rows = Get-AnsiPlain { Format-AnsiBarChart @([PSCustomObject]@{ Label = 'a'; Value = '2.5' }) -Width 20 }
        $rows[0] | Should -Match '2\.5$'
    }

    It 'skips a null item' {
        $rows = Get-AnsiPlain { Format-AnsiBarChart @(10, $null, 5) -Width 20 -HideValues }
        $rows.Count | Should -Be 2
    }

    It 'writes nothing at all for no items' {
        $rendering = Format-AnsiBarChart @()
        $rendering | Should -BeNullOrEmpty
    }

    It 'rejects an item with no value' {
        { Format-AnsiBarChart @([PSCustomObject]@{ Label = 'a' }) } | Should -Throw '*has no Value*'
    }

    It 'rejects a value that is not a number' {
        { Format-AnsiBarChart @([PSCustomObject]@{ Label = 'a'; Value = 'lots' }) } |
            Should -Throw '*not a number*'
    }
}

Describe 'Format-AnsiBarChart — width' {
    BeforeEach { Reset-AnsiTest }

    It 'fills the anchor width by default' {
        $rows = Get-AnsiPlain { Format-AnsiBarChart @(10) -Width 0 -HideValues }
        $rows[0].Length | Should -Be $script:Buffer
    }

    It 'leaves room for the caller column' {
        Set-AnsiTestColumn -Column 10
        $rows = Get-AnsiPlain { Format-AnsiBarChart @(10) -HideValues }
        $rows[0].Length | Should -Be ($script:Buffer - 10)
    }

    It 'reports the column it was anchored at' {
        Set-AnsiTestColumn -Column 7
        (Format-AnsiBarChart @(10)).Column | Should -Be 7
    }

    It 'takes -MaxWidth as an alias for -Width' {
        $rows = Get-AnsiPlain { Format-AnsiBarChart @(10) -MaxWidth 12 -HideValues }
        $rows[0].Length | Should -Be 12
    }

    It 'sizes the bar column itself with -BarWidth' {
        $rows = Get-AnsiPlain { Format-AnsiBarChart (New-AnsiTestData) -Width 30 -BarWidth 10 }
        $rows[0] | Should -BeExactly (' apples ' + ($script:Full * 10) + ' 10')
        $rows[1] | Should -BeExactly ('oranges ' + ($script:Full * 5) + (' ' * 6) + '5')
    }

    It 'never draws a bar narrower than one cell' {
        $rows = Get-AnsiPlain {
            Format-AnsiBarChart @([PSCustomObject]@{ Label = 'a label that eats the row'; Value = 1 }) -Width 12
        }
        $rows[0] | Should -Match ([regex]::Escape($script:Full))
    }

    It 'reports the width of its widest row' {
        (Format-AnsiBarChart (New-AnsiTestData) -Width 30).Width | Should -Be 30
    }
}

Describe 'Format-AnsiBarChart — colour' {
    BeforeEach { Set-AnsiTestNoColor -Value $false }

    It 'hands out the palette in turn' {
        $out = Invoke-Ansi { Format-AnsiBarChart @(10, 8) -Width 20 -HideValues }
        $out | Should -Match ([regex]::Escape($PSStyle.Foreground.BrightCyan))
        $out | Should -Match ([regex]::Escape($PSStyle.Foreground.BrightGreen))
    }

    It 'takes the palette from -Palette' {
        $out = Invoke-Ansi { Format-AnsiBarChart @(10, 8) -Width 20 -HideValues -Palette BrightRed, BrightBlue }
        $out | Should -Match ([regex]::Escape($PSStyle.Foreground.BrightRed))
        $out | Should -Match ([regex]::Escape($PSStyle.Foreground.BrightBlue))
        $out | Should -Not -Match ([regex]::Escape($PSStyle.Foreground.BrightCyan))
    }

    It 'colours every unnamed bar with -BarColor' {
        $out = Invoke-Ansi { Format-AnsiBarChart @(10, 8) -Width 20 -HideValues -BarColor BrightMagenta }
        $out | Should -Match ([regex]::Escape($PSStyle.Foreground.BrightMagenta))
        $out | Should -Not -Match ([regex]::Escape($PSStyle.Foreground.BrightCyan))
    }

    It 'accepts -Color as an alias for -BarColor' {
        $out = Invoke-Ansi { Format-AnsiBarChart @(10) -Width 20 -HideValues -Color BrightBlue }
        $out | Should -Match ([regex]::Escape($PSStyle.Foreground.BrightBlue))
    }

    It "lets an item's own colour win" {
        $out = Invoke-Ansi {
            Format-AnsiBarChart @([PSCustomObject]@{ Label = 'a'; Value = 1; Color = 'BrightYellow' }) `
                -Width 20 -HideValues -BarColor BrightMagenta
        }
        $out | Should -Match ([regex]::Escape($PSStyle.Foreground.BrightYellow))
        $out | Should -Not -Match ([regex]::Escape($PSStyle.Foreground.BrightMagenta))
    }

    It 'colours the labels and the values' {
        $out = Invoke-Ansi {
            Format-AnsiBarChart (New-AnsiTestData) -Width 30 -LabelColor BrightWhite -ValueColor BrightYellow
        }
        $out | Should -Match ([regex]::Escape($PSStyle.Foreground.BrightWhite))
        $out | Should -Match ([regex]::Escape($PSStyle.Foreground.BrightYellow))
    }

    It 'keeps the layout and drops the colour under NO_COLOR' {
        Set-AnsiTestNoColor -Value $true
        $out = Invoke-Ansi { Format-AnsiBarChart @(10) -Width 20 -HideValues -BarColor BrightGreen }
        $out | Should -BeExactly ($script:Full * 20)
    }

    It 'rejects an unknown colour' {
        { Format-AnsiBarChart @(1) -BarColor Chartreuse } | Should -Throw '*Unknown color*'
        { Format-AnsiBarChart @(1) -Palette Chartreuse } | Should -Throw '*Unknown color*'
        { Format-AnsiBarChart @([PSCustomObject]@{ Label = 'a'; Value = 1; Color = '#FFFF00' }) } |
            Should -Throw '*Unknown color*'
    }
}

Describe 'Format-AnsiBarChart — the rendering' {
    BeforeEach { Reset-AnsiTest }

    It 'returns an Ansi.Rendering of kind BarChart' {
        $rendering = Format-AnsiBarChart (New-AnsiTestData) -Width 30
        $rendering.PSObject.TypeNames | Should -Contain 'Ansi.Rendering'
        $rendering.Kind | Should -BeExactly 'BarChart'
    }

    It 'is one row per item, plus one for a title' {
        (Format-AnsiBarChart (New-AnsiTestData) -Width 30).RowCount | Should -Be 2
        (Format-AnsiBarChart (New-AnsiTestData) 'sales' -Width 30).RowCount | Should -Be 3
    }

    It 'writes nothing on its own' {
        $records = & { $null = Format-AnsiBarChart (New-AnsiTestData) } 6>&1
        $records | Should -BeNullOrEmpty
    }

    It 'nests in a panel' {
        # Assignment first: Out-AnsiString returns the lines comma-wrapped, so
        # @(pipeline) would nest them and the join would print a type name.
        $chart = Format-AnsiBarChart (New-AnsiTestData) -Width 24 -HideValues
        $lines = Format-AnsiPanel $chart -Border Square | Out-AnsiString -Plain
        ($lines -join "`n") | Should -Match ([regex]::Escape($script:Full * 16))
    }

    It 'exports one function' {
        (Get-Module Format-AnsiBarChart).ExportedFunctions.Keys | Should -Be @('Format-AnsiBarChart')
    }
}
