#Requires -Version 7.2
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

# Format-AnsiProgress.Tests.ps1
# Pester 5 tests for Format-AnsiProgress. Rendered output is captured off the
# Information stream (Write-Host redirect 6>&1) and inspected as strings.
#
# As elsewhere, two Ansi.Core helpers are replaced inside the Format-AnsiProgress
# module scope to make the suite host-independent:
#   Get-AnsiAnchor    — pinned to a known column and a 40-column buffer.
#   Test-AnsiNoColor  — driven by Set-AnsiTestNoColor, not the environment.
# Injection is used rather than Mock: Pester cannot mock a command a module
# merely imported from another module.

BeforeAll {
    $script:src = Join-Path (Split-Path -Parent $PSScriptRoot) 'src'
    Import-Module (Join-Path $script:src 'Format-AnsiProgress.psm1') -Force -DisableNameChecking
    Import-Module (Join-Path $script:src 'Out-AnsiHost.psm1') -Force -DisableNameChecking
    Import-Module (Join-Path $script:src 'Out-AnsiString.psm1') -Force -DisableNameChecking
    Import-Module (Join-Path $script:src 'Format-AnsiPanel.psm1') -DisableNameChecking
    Import-Module (Join-Path $script:src 'Format-AnsiGrid.psm1') -DisableNameChecking
    $script:AnsiModule = Get-Module Format-AnsiProgress

    $script:Full = [string][char]0x2588     # █
    $script:Light = [string][char]0x2591    # ░
    $script:Heavy = [string][char]0x2501    # ━
    $script:Line = [string][char]0x2500     # ─
    $script:Dot = [string][char]0x25CF      # ●
    $script:Middot = [string][char]0x00B7   # ·
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

    # The plain text of a bar, colour and all stripped.
    function Get-AnsiPlain {
        param([Parameter(Mandatory)][scriptblock]$Sb)
        $line = & $Sb | Out-AnsiString -Plain -Join
        return [string]$line
    }

    function Reset-AnsiTest {
        Set-AnsiTestColumn -Column 0
        Set-AnsiTestNoColor -Value $true
    }
}

Describe 'Format-AnsiProgress — the bar' {
    BeforeEach { Reset-AnsiTest }

    It 'draws an empty bar at zero' {
        $plain = Get-AnsiPlain { Format-AnsiProgress 0 -Width 20 -Show None }
        $plain | Should -BeExactly ($script:Light * 20)
    }

    It 'draws a full bar at the total' {
        $plain = Get-AnsiPlain { Format-AnsiProgress 100 -Width 20 -Show None }
        $plain | Should -BeExactly ($script:Full * 20)
    }

    It 'fills half the bar at half the total' {
        $plain = Get-AnsiPlain { Format-AnsiProgress 50 -Width 20 -Show None }
        $plain | Should -BeExactly (($script:Full * 10) + ($script:Light * 10))
    }

    It 'counts in -Total units, not percent' {
        $plain = Get-AnsiPlain { Format-AnsiProgress 3 -Total 4 -Width 20 -Show None }
        $plain | Should -BeExactly (($script:Full * 15) + ($script:Light * 5))
    }

    It 'never shows a full bar short of the total' {
        # round() would fill all 20 cells at 99%, which reads as finished.
        $plain = Get-AnsiPlain { Format-AnsiProgress 99 -Width 20 -Show None }
        $plain | Should -BeExactly (($script:Full * 19) + $script:Light)
    }

    It 'never shows an empty bar past zero' {
        $plain = Get-AnsiPlain { Format-AnsiProgress 1 -Total 1000 -Width 20 -Show None }
        $plain | Should -BeExactly ($script:Full + ($script:Light * 19))
    }

    It 'clamps a value below zero and past the total' {
        (Get-AnsiPlain { Format-AnsiProgress -5 -Width 10 -Show None }) | Should -BeExactly ($script:Light * 10)
        (Get-AnsiPlain { Format-AnsiProgress 250 -Width 10 -Show None }) | Should -BeExactly ($script:Full * 10)
    }

    It 'accepts a fractional value' {
        $plain = Get-AnsiPlain { Format-AnsiProgress 12.5 -Width 8 -Show None }
        $plain | Should -BeExactly (($script:Full * 1) + ($script:Light * 7))
    }

    It 'takes the value from the pipeline' {
        $plain = 50 | Format-AnsiProgress -Width 20 -Show None | Out-AnsiString -Plain -Join
        $plain | Should -BeExactly (($script:Full * 10) + ($script:Light * 10))
    }
}

Describe 'Format-AnsiProgress — styles' {
    BeforeEach { Reset-AnsiTest }

    It 'draws <Style> with its own characters' -ForEach @(
        @{ Style = 'Blocks'; Filled = 0x2588; Empty = 0x2591 }
        @{ Style = 'Line'; Filled = 0x2501; Empty = 0x2500 }
        @{ Style = 'Dots'; Filled = 0x25CF; Empty = 0x00B7 }
    ) {
        $plain = Get-AnsiPlain { Format-AnsiProgress 50 -Width 10 -Show None -Style $Style }
        $plain | Should -BeExactly (([string][char]$Filled * 5) + ([string][char]$Empty * 5))
    }

    It 'draws Ascii with hash and dash' {
        $plain = Get-AnsiPlain { Format-AnsiProgress 50 -Width 10 -Show None -Style Ascii }
        $plain | Should -BeExactly '#####-----'
    }

    It 'rejects an unknown style' {
        { Format-AnsiProgress 50 -Style Sparkles } | Should -Throw
    }
}

Describe 'Format-AnsiProgress — label and suffix' {
    BeforeEach { Reset-AnsiTest }

    It 'puts the label before the bar with one space' {
        $plain = Get-AnsiPlain { Format-AnsiProgress 50 'restore' -Width 20 -Show None }
        $plain | Should -BeExactly ('restore ' + ($script:Full * 6) + ($script:Light * 6))
    }

    It 'pads the label to -LabelWidth so a column lines up' {
        $short = Get-AnsiPlain { Format-AnsiProgress 50 'build' -Width 24 -Show None -LabelWidth 10 }
        $long = Get-AnsiPlain { Format-AnsiProgress 50 'restore' -Width 24 -Show None -LabelWidth 10 }
        # 24 wide less an 11 column label leaves 13 cells: 7 filled at half.
        $short | Should -BeExactly ('build      ' + ($script:Full * 7) + ($script:Light * 6))
        $long | Should -BeExactly ('restore    ' + ($script:Full * 7) + ($script:Light * 6))
    }

    It 'shows the percent by default, right aligned to four columns' {
        (Get-AnsiPlain { Format-AnsiProgress 5 -Width 20 }) | Should -Match '   5%$'
        (Get-AnsiPlain { Format-AnsiProgress 50 -Width 20 }) | Should -Match '  50%$'
        (Get-AnsiPlain { Format-AnsiProgress 100 -Width 20 }) | Should -Match ' 100%$'
    }

    It 'shows the count with -Show Count' {
        (Get-AnsiPlain { Format-AnsiProgress 3 -Total 7 -Width 20 -Show Count }) | Should -Match '3/7$'
    }

    It 'pads the count so the bar does not shift as it counts up' {
        $first = Get-AnsiPlain { Format-AnsiProgress 9 -Total 100 -Width 30 -Show Count }
        $later = Get-AnsiPlain { Format-AnsiProgress 99 -Total 100 -Width 30 -Show Count }
        $first.Length | Should -Be $later.Length
        $first | Should -Match '  9/100$'
    }

    It 'shows both with -Show Both' {
        (Get-AnsiPlain { Format-AnsiProgress 3 -Total 7 -Width 30 -Show Both }) | Should -Match '3/7    43%$'
    }

    It 'shows nothing after the bar with -Show None' {
        $plain = Get-AnsiPlain { Format-AnsiProgress 50 -Width 10 -Show None }
        $plain.Length | Should -Be 10
    }

    It 'keeps whole numbers whole and fractions to one decimal' {
        (Get-AnsiPlain { Format-AnsiProgress 2 -Total 4 -Width 20 -Show Count }) | Should -Match '2/4$'
        (Get-AnsiPlain { Format-AnsiProgress 1.5 -Total 4 -Width 20 -Show Count }) | Should -Match '1.5/4$'
    }

    It 'reads markup in the label' {
        Set-AnsiTestNoColor -Value $false
        $out = Invoke-Ansi { Format-AnsiProgress 50 '[BrightRed]hot[/]' -Width 20 -Show None }
        $out | Should -Match ([regex]::Escape($PSStyle.Foreground.BrightRed))
        $out | Should -Match 'hot'
    }

    It 'takes the label literally with -Escape' {
        $plain = Get-AnsiPlain { Format-AnsiProgress 50 '[BrightRed]hot[/]' -Width 40 -Show None -Escape }
        $plain | Should -Match ([regex]::Escape('[BrightRed]hot[/]'))
    }

    It 'collapses a hard break in the label' {
        $plain = Get-AnsiPlain { Format-AnsiProgress 50 "two`nlines" -Width 30 -Show None }
        $plain | Should -Match '^two lines '
    }
}

Describe 'Format-AnsiProgress — width' {
    BeforeEach { Reset-AnsiTest }

    It 'fills the anchor width by default' {
        $plain = Get-AnsiPlain { Format-AnsiProgress 50 }
        $plain.Length | Should -Be $script:Buffer
    }

    It 'leaves room for the caller column' {
        Set-AnsiTestColumn -Column 10
        $plain = Get-AnsiPlain { Format-AnsiProgress 50 }
        $plain.Length | Should -Be ($script:Buffer - 10)
    }

    It 'reports the column it was anchored at' {
        Set-AnsiTestColumn -Column 7
        (Format-AnsiProgress 50).Column | Should -Be 7
    }

    It 'honours -Width over the buffer' {
        (Get-AnsiPlain { Format-AnsiProgress 50 -Width 12 }).Length | Should -Be 12
    }

    It 'sizes the bar itself with -BarWidth' {
        $plain = Get-AnsiPlain { Format-AnsiProgress 50 -BarWidth 6 -Show None }
        $plain | Should -BeExactly (($script:Full * 3) + ($script:Light * 3))
    }

    It 'keeps -BarWidth even when the label and suffix are wider than -Width' {
        $plain = Get-AnsiPlain { Format-AnsiProgress 50 'a long label here' -Width 10 -BarWidth 4 }
        $plain | Should -Match ([regex]::Escape(($script:Full * 2) + ($script:Light * 2)))
    }

    It 'never draws a bar narrower than one cell' {
        $plain = Get-AnsiPlain { Format-AnsiProgress 50 'label that eats the row' -Width 12 -Show None }
        $plain | Should -Match ([regex]::Escape($script:Light))
    }

    It 'reports its own width' {
        (Format-AnsiProgress 50 -Width 25).Width | Should -Be 25
    }

    It 'is a single row' {
        (Format-AnsiProgress 50).RowCount | Should -Be 1
    }
}

Describe 'Format-AnsiProgress — colour' {
    BeforeEach { Set-AnsiTestNoColor -Value $false }

    It 'colours the filled part with -BarColor' {
        $out = Invoke-Ansi { Format-AnsiProgress 50 -Width 20 -Show None -BarColor BrightGreen }
        $out | Should -Match ([regex]::Escape($PSStyle.Foreground.BrightGreen))
    }

    It 'colours the empty part with -EmptyColor' {
        $out = Invoke-Ansi { Format-AnsiProgress 50 -Width 20 -Show None -EmptyColor DarkGray }
        $out | Should -Match ([regex]::Escape($PSStyle.Foreground.BrightBlack))
    }

    It 'colours the label and the suffix' {
        $out = Invoke-Ansi { Format-AnsiProgress 50 'x' -Width 20 -LabelColor BrightCyan -SuffixColor BrightYellow }
        $out | Should -Match ([regex]::Escape($PSStyle.Foreground.BrightCyan))
        $out | Should -Match ([regex]::Escape($PSStyle.Foreground.BrightYellow))
    }

    It 'accepts -Color as an alias for -BarColor' {
        $out = Invoke-Ansi { Format-AnsiProgress 50 -Width 20 -Show None -Color BrightMagenta }
        $out | Should -Match ([regex]::Escape($PSStyle.Foreground.BrightMagenta))
    }

    It 'switches to -CompleteColor only at the total' {
        $mid = Invoke-Ansi { Format-AnsiProgress 50 -Width 20 -Show None -BarColor BrightYellow -CompleteColor BrightGreen }
        $done = Invoke-Ansi { Format-AnsiProgress 100 -Width 20 -Show None -BarColor BrightYellow -CompleteColor BrightGreen }
        $mid | Should -Match ([regex]::Escape($PSStyle.Foreground.BrightYellow))
        $done | Should -Match ([regex]::Escape($PSStyle.Foreground.BrightGreen))
        $done | Should -Not -Match ([regex]::Escape($PSStyle.Foreground.BrightYellow))
    }

    It 'keeps the layout and drops the colour under NO_COLOR' {
        Set-AnsiTestNoColor -Value $true
        $out = Invoke-Ansi { Format-AnsiProgress 50 -Width 20 -Show None -BarColor BrightGreen }
        $out | Should -BeExactly (($script:Full * 10) + ($script:Light * 10))
    }

    It 'rejects an unknown colour' {
        { Format-AnsiProgress 50 -BarColor Chartreuse } | Should -Throw '*Unknown color*'
    }
}

Describe 'Format-AnsiProgress — the rendering' {
    BeforeEach { Reset-AnsiTest }

    It 'returns an Ansi.Rendering of kind Progress' {
        $rendering = Format-AnsiProgress 50
        $rendering.PSObject.TypeNames | Should -Contain 'Ansi.Rendering'
        $rendering.Kind | Should -BeExactly 'Progress'
    }

    It 'writes nothing on its own' {
        $records = & { $null = Format-AnsiProgress 50 } 6>&1
        $records | Should -BeNullOrEmpty
    }

    It 'nests in a panel' {
        # Assignment first: Out-AnsiString returns the lines comma-wrapped, so
        # @(pipeline) would nest them and the join would print a type name.
        $bar = Format-AnsiProgress 50 -Width 20 -Show None
        $lines = Format-AnsiPanel $bar -Border Square | Out-AnsiString -Plain
        ($lines -join "`n") | Should -Match ([regex]::Escape($script:Full * 10))
    }

    It 'nests in a grid cell' {
        $bar = Format-AnsiProgress 50 -Width 10 -Show None
        $lines = Format-AnsiGrid @(, @('build', $bar)) | Out-AnsiString -Plain
        ($lines -join "`n") | Should -Match ([regex]::Escape($script:Full * 5))
    }

    It 'exports one function' {
        (Get-Module Format-AnsiProgress).ExportedFunctions.Keys | Should -Be @('Format-AnsiProgress')
    }
}
