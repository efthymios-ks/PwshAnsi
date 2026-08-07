#Requires -Version 7.2
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

# Format-AnsiRule.Tests.ps1
# Pester 5 tests for Format-AnsiRule. Rendered output is captured off the
# Information stream (Write-Host redirect 6>&1) and inspected as strings.
#
# As in Format-AnsiText.Tests.ps1, two Ansi.Core helpers are replaced inside the
# Format-AnsiRule module scope to make the suite host-independent:
#   Get-AnsiAnchor    — pinned to a known column and a 40-column buffer.
#   Test-AnsiNoColor  — driven by Set-AnsiTestNoColor, not the environment.
# Injection is used rather than Mock: Pester cannot mock a command a module
# merely imported from another module.

BeforeAll {
    $script:src = Join-Path (Split-Path -Parent $PSScriptRoot) 'src'
    Import-Module (Join-Path $script:src 'Format-AnsiRule.psm1') -Force -DisableNameChecking
    Import-Module (Join-Path $script:src 'Out-AnsiHost.psm1') -Force -DisableNameChecking
    Import-Module (Join-Path $script:src 'Out-AnsiString.psm1') -Force -DisableNameChecking
    $script:AnsiModule = Get-Module Format-AnsiRule

    $script:Line = [string][char]0x2500     # ─
    $script:Double = [string][char]0x2550   # ═
    $script:Heavy = [string][char]0x2501    # ━
    $script:Dashed = [string][char]0x2504   # ┄
    $script:Dotted = [string][char]0x2508   # ┈
    $script:Ell = [string][char]0x2026      # …
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

    # One string per Write-Host call. The leading comma keeps single-row and
    # empty results arrays instead of collapsing to a string.
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

    function Remove-Osc {
        param([AllowEmptyString()][string]$Text)
        return ($Text -replace "`e\]8;;[^`e]*`e\\", '')
    }

    function Get-Plain {
        param([AllowEmptyString()][string]$Text)
        return (Remove-Osc (Remove-Ansi $Text))
    }

    function Measure-Occurrence {
        param([string]$Text, [string]$Needle)
        return ([regex]::Matches($Text, [regex]::Escape($Needle))).Count
    }
}

Describe 'Format-AnsiRule — plain line' {
    It 'fills the requested width with ─ by default' {
        $out = Invoke-Ansi { Format-AnsiRule -Width 20 }
        Remove-Ansi $out | Should -BeExactly ($script:Line * 20)
    }

    It 'emits exactly one row' {
        $lines = Invoke-AnsiLines { Format-AnsiRule -Width 20 }
        $lines.Count | Should -Be 1
    }

    It 'falls back to the anchored width when -Width is absent' {
        $out = Invoke-Ansi { Format-AnsiRule }
        (Remove-Ansi $out).Length | Should -Be $script:Buffer
    }

    It 'renders a plain line for an empty title' {
        $out = Invoke-Ansi { Format-AnsiRule '' -Width 10 }
        Remove-Ansi $out | Should -BeExactly ($script:Line * 10)
    }

    It 'renders a plain line for a $null title' {
        $out = Invoke-Ansi { Format-AnsiRule $null -Width 10 }
        Remove-Ansi $out | Should -BeExactly ($script:Line * 10)
    }

    It 'survives a width of 1' {
        $out = Invoke-Ansi { Format-AnsiRule -Width 1 }
        Remove-Ansi $out | Should -BeExactly $script:Line
    }
}

Describe 'Format-AnsiRule — -Border' {
    It '<Border> repeats <Expected>' -ForEach @(
        @{ Border = 'Line'; Expected = [string][char]0x2500 }
        @{ Border = 'Double'; Expected = [string][char]0x2550 }
        @{ Border = 'Heavy'; Expected = [string][char]0x2501 }
        @{ Border = 'Ascii'; Expected = '-' }
        @{ Border = 'Dashed'; Expected = [string][char]0x2504 }
        @{ Border = 'Dotted'; Expected = [string][char]0x2508 }
    ) {
        $border = $Border
        $out = Invoke-Ansi { Format-AnsiRule -Width 10 -Border $border }
        Remove-Ansi $out | Should -BeExactly ($Expected * 10)
    }

    It 'is case-insensitive' {
        $out = Invoke-Ansi { Format-AnsiRule -Width 6 -Border 'double' }
        Remove-Ansi $out | Should -BeExactly ($script:Double * 6)
    }

    It 'rejects an unknown border name' {
        { Format-AnsiRule -Width 6 -Border Wiggly } | Should -Throw
    }
}

Describe 'Format-AnsiRule — -Char' {
    It 'overrides the border character' {
        $out = Invoke-Ansi { Format-AnsiRule -Width 10 -Char '=' }
        Remove-Ansi $out | Should -BeExactly ('=' * 10)
    }

    It 'tiles a multi-character override and trims to the width' {
        $out = Invoke-Ansi { Format-AnsiRule -Width 7 -Char '<>' }
        Remove-Ansi $out | Should -BeExactly '<><><><'
    }

    It 'wins over -Border' {
        $out = Invoke-Ansi { Format-AnsiRule -Width 5 -Border Double -Char '.' }
        Remove-Ansi $out | Should -BeExactly '.....'
    }

    It 'rejects an empty override' {
        { Format-AnsiRule -Width 5 -Char '' } | Should -Throw
    }
}

Describe 'Format-AnsiRule — title placement' {
    It 'left-aligns by default: title, pad, line' {
        $out = Invoke-Ansi { Format-AnsiRule 'Setup' -Width 20 }
        Remove-Ansi $out | Should -BeExactly ('Setup ' + ($script:Line * 14))
    }

    It 'centers the title between two line segments' {
        # remaining = 20 - 5 - 2 = 13 => left 6, right 7
        $out = Invoke-Ansi { Format-AnsiRule 'Setup' -Width 20 -Alignment Center }
        Remove-Ansi $out | Should -BeExactly (($script:Line * 6) + ' Setup ' + ($script:Line * 7))
    }

    It 'right-aligns: line, pad, title' {
        $out = Invoke-Ansi { Format-AnsiRule 'Setup' -Width 20 -Alignment Right }
        Remove-Ansi $out | Should -BeExactly (($script:Line * 14) + ' Setup')
    }

    It 'always fills the width exactly' -ForEach @(
        @{ Alignment = 'Left' }, @{ Alignment = 'Center' }, @{ Alignment = 'Right' }
    ) {
        $alignment = $Alignment
        $out = Invoke-Ansi { Format-AnsiRule 'Title' -Width 19 -Alignment $alignment }
        (Remove-Ansi $out).Length | Should -Be 19
    }

    It 'collapses a hard `n in the title to a space' {
        $out = Invoke-Ansi { Format-AnsiRule "one`ntwo" -Width 20 }
        Remove-Ansi $out | Should -BeExactly ('one two ' + ($script:Line * 12))
    }

    It 'rejects an unknown -Alignment value' {
        { Format-AnsiRule 'x' -Width 10 -Alignment Middle } | Should -Throw
    }
}

Describe 'Format-AnsiRule — -TitlePadding' {
    It 'defaults to one space between title and line' {
        $out = Invoke-Ansi { Format-AnsiRule 'S' -Width 10 }
        Remove-Ansi $out | Should -BeExactly ('S ' + ($script:Line * 8))
    }

    It 'drops the gap at 0' {
        $out = Invoke-Ansi { Format-AnsiRule 'S' -Width 10 -TitlePadding 0 }
        Remove-Ansi $out | Should -BeExactly ('S' + ($script:Line * 9))
    }

    It 'widens the gap above 1' {
        $out = Invoke-Ansi { Format-AnsiRule 'S' -Width 10 -TitlePadding 3 }
        Remove-Ansi $out | Should -BeExactly ('S   ' + ($script:Line * 6))
    }

    It 'pads both sides when centered' {
        # remaining = 20 - 5 - (3 * 2) = 9 => left 4, right 5
        $out = Invoke-Ansi { Format-AnsiRule 'Setup' -Width 20 -TitlePadding 3 -Alignment Center }
        Remove-Ansi $out | Should -BeExactly (($script:Line * 4) + '   Setup   ' + ($script:Line * 5))
    }

    It 'rejects a negative padding' {
        { Format-AnsiRule 'S' -Width 10 -TitlePadding -1 } | Should -Throw
    }
}

Describe 'Format-AnsiRule — colours' {
    It 'colours the title with -TitleColor' {
        $out = Invoke-Ansi { Format-AnsiRule 'T' -Width 12 -TitleColor BrightRed }
        $out | Should -Match ([regex]::Escape($PSStyle.Foreground.BrightRed))
        Remove-Ansi $out | Should -BeExactly ('T ' + ($script:Line * 10))
    }

    It 'colours the line with -LineColor' {
        $out = Invoke-Ansi { Format-AnsiRule -Width 12 -LineColor BrightBlue }
        $out | Should -Match ([regex]::Escape($PSStyle.Foreground.BrightBlue))
    }

    It 'colours title and line independently' {
        $out = Invoke-Ansi { Format-AnsiRule 'T' -Width 12 -TitleColor BrightRed -LineColor BrightBlue }
        $out | Should -Match ([regex]::Escape($PSStyle.Foreground.BrightRed))
        $out | Should -Match ([regex]::Escape($PSStyle.Foreground.BrightBlue))
    }

    It 'aliases -Color onto -TitleColor' {
        $out = Invoke-Ansi { Format-AnsiRule 'T' -Width 12 -Color BrightRed }
        $out | Should -Match ([regex]::Escape($PSStyle.Foreground.BrightRed))
        $out | Should -Not -Match ([regex]::Escape($PSStyle.Foreground.BrightBlue))
    }

    It 'leaves the line unstyled when only the title is coloured' {
        $out = Invoke-Ansi { Format-AnsiRule 'T' -Width 12 -Color BrightRed }
        Measure-Occurrence $out $PSStyle.Reset | Should -Be 1
    }

    It 'accepts ConsoleColor aliases' {
        $out = Invoke-Ansi { Format-AnsiRule 'T' -Width 12 -LineColor DarkGray }
        $out | Should -Match ([regex]::Escape($PSStyle.Foreground.BrightBlack))
    }

    It 'throws on an unknown title colour' {
        { Format-AnsiRule 'T' -Width 12 -Color Nope } | Should -Throw
    }

    It 'throws on an unknown line colour' {
        { Format-AnsiRule 'T' -Width 12 -LineColor Nope } | Should -Throw
    }

    It 'does not overwrite a colour set via markup in the title' {
        $out = Invoke-Ansi { Format-AnsiRule '[BrightGreen]T[/]' -Width 12 -Color BrightRed }
        $out | Should -Match ([regex]::Escape($PSStyle.Foreground.BrightGreen))
        $out | Should -Not -Match ([regex]::Escape($PSStyle.Foreground.BrightRed))
    }
}

Describe 'Format-AnsiRule — markup and markdown in the title' {
    It 'parses markup tags by default' {
        $out = Invoke-Ansi { Format-AnsiRule '[bold]x[/]' -Width 20 }
        $out | Should -Match ([regex]::Escape($PSStyle.Bold))
        Remove-Ansi $out | Should -BeExactly ('x ' + ($script:Line * 18))
    }

    It 'renders a hyperlink in the title' {
        $out = Invoke-Ansi { Format-AnsiRule '[link=https://example.com]y[/]' -Width 10 }
        $out | Should -Match ([regex]::Escape('https://example.com'))
        Get-Plain $out | Should -BeExactly ('y ' + ($script:Line * 8))
    }

    It 'renders markdown sugar with -Markdown' {
        $out = Invoke-Ansi { Format-AnsiRule '**Done**' -Width 20 -Markdown }
        $out | Should -Match ([regex]::Escape($PSStyle.Bold))
        Remove-Ansi $out | Should -BeExactly ('Done ' + ($script:Line * 15))
    }

    It 'replaces emoji tokens with -Markdown' {
        $out = Invoke-Ansi { Format-AnsiRule ':check: ok' -Width 20 -Markdown }
        Remove-Ansi $out | Should -BeExactly ([string][char]0x2713 + ' ok ' + ($script:Line * 15))
    }

    It 'treats the title as literal with -Escape' {
        $out = Invoke-Ansi { Format-AnsiRule '[bold]x[/]' -Width 20 -Escape }
        Remove-Ansi $out | Should -BeExactly ('[bold]x[/] ' + ($script:Line * 9))
    }

    It '-Escape wins over -Markdown' {
        $out = Invoke-Ansi { Format-AnsiRule '**x**' -Width 20 -Escape -Markdown }
        Remove-Ansi $out | Should -BeExactly ('**x** ' + ($script:Line * 14))
    }

    It '-Escape still applies -Color to the literal title' {
        $out = Invoke-Ansi { Format-AnsiRule '[bold]x[/]' -Width 20 -Escape -Color BrightRed }
        $out | Should -Match ([regex]::Escape($PSStyle.Foreground.BrightRed))
        Remove-Ansi $out | Should -BeExactly ('[bold]x[/] ' + ($script:Line * 9))
    }

    It 'throws on invalid markup in the title' {
        { Format-AnsiRule '[nosuch]x[/]' -Width 20 } | Should -Throw
    }

    It 'does not throw on invalid markup under -Escape' {
        { Invoke-Ansi { Format-AnsiRule '[nosuch]x' -Width 20 -Escape } } | Should -Not -Throw
    }
}

Describe 'Format-AnsiRule — title truncation' {
    It 'ellipsises a title that does not fit' {
        # available = 12 - 1 (pad) - 1 (min line) = 10
        $out = Invoke-Ansi { Format-AnsiRule 'A very long title indeed' -Width 12 }
        Remove-Ansi $out | Should -BeExactly ('A very lo' + $script:Ell + ' ' + $script:Line)
    }

    It 'keeps the row exactly the requested width when truncating' {
        $out = Invoke-Ansi { Format-AnsiRule ('x' * 200) -Width 15 -Alignment Center }
        (Remove-Ansi $out).Length | Should -Be 15
    }

    It 'ellipsises a centered title' {
        # available = 12 - 2 (pads) - 2 (min lines) = 8
        $out = Invoke-Ansi { Format-AnsiRule 'A very long title' -Width 12 -Alignment Center }
        $plain = Remove-Ansi $out
        $plain | Should -Match ([regex]::Escape($script:Ell))
        $plain.Length | Should -Be 12
    }

    It 'keeps title styling on a truncated title' {
        $out = Invoke-Ansi { Format-AnsiRule '[bold]A very long title indeed[/]' -Width 12 }
        $out | Should -Match ([regex]::Escape($PSStyle.Bold))
        (Remove-Ansi $out) | Should -Match ([regex]::Escape($script:Ell))
    }

    It 'drops the title entirely when the width leaves no room for it' {
        $out = Invoke-Ansi { Format-AnsiRule 'Title' -Width 3 }
        Remove-Ansi $out | Should -BeExactly ($script:Line * 3)
    }

    It 'drops the title when padding consumes the width' {
        $out = Invoke-Ansi { Format-AnsiRule 'Title' -Width 6 -TitlePadding 5 }
        Remove-Ansi $out | Should -BeExactly ($script:Line * 6)
    }
}

Describe 'Format-AnsiRule — -Spacing' {
    It 'adds a blank row before and after at 1' {
        $lines = Invoke-AnsiLines { Format-AnsiRule 'S' -Width 10 -Spacing 1 }
        $lines.Count | Should -Be 3
        $lines[0] | Should -BeExactly ''
        (Remove-Ansi $lines[1]) | Should -BeExactly ('S ' + ($script:Line * 8))
        $lines[2] | Should -BeExactly ''
    }

    It 'scales with the value' {
        $lines = Invoke-AnsiLines { Format-AnsiRule -Width 10 -Spacing 2 }
        $lines.Count | Should -Be 5
        (Remove-Ansi $lines[2]) | Should -BeExactly ($script:Line * 10)
    }

    It 'emits a single row at 0' {
        $lines = Invoke-AnsiLines { Format-AnsiRule -Width 10 -Spacing 0 }
        $lines.Count | Should -Be 1
    }

    It 'rejects a negative value' {
        { Format-AnsiRule -Width 10 -Spacing -1 } | Should -Throw
    }
}

Describe 'Format-AnsiRule — anchoring' {
    BeforeAll { Set-AnsiTestColumn 8 }
    AfterAll { Set-AnsiTestColumn 0 }

    It 'sizes the rule to the remaining buffer' {
        $out = Invoke-Ansi { Format-AnsiRule }
        (Remove-Ansi $out).Length | Should -Be ($script:Buffer - 8)
    }

    It 'leaves the single row where the cursor already is' {
        $out = Invoke-Ansi { Format-AnsiRule -Width 10 }
        Remove-Ansi $out | Should -BeExactly ($script:Line * 10)
    }

    It 'resumes at the anchor column after a spacing row' {
        $lines = Invoke-AnsiLines { Format-AnsiRule -Width 10 -Spacing 1 }
        $lines[0] | Should -BeExactly ''
        (Remove-Ansi $lines[1]) | Should -BeExactly ((' ' * 8) + ($script:Line * 10))
    }

    It 'honours -Width over the anchored width' {
        $out = Invoke-Ansi { Format-AnsiRule -Width 12 }
        (Remove-Ansi $out).Length | Should -Be 12
    }
}

Describe 'Format-AnsiRule — -Expand' {
    It 'spans the whole buffer from column 0' {
        $out = Invoke-Ansi { Format-AnsiRule -Expand }
        Remove-Ansi $out | Should -BeExactly ($script:Line * $script:Buffer)
    }

    It 'ignores the anchor column' {
        Set-AnsiTestColumn 8
        try {
            $lines = Invoke-AnsiLines { Format-AnsiRule -Expand -Spacing 1 }
            (Remove-Ansi $lines[1]) | Should -BeExactly ($script:Line * $script:Buffer)
        } finally {
            Set-AnsiTestColumn 0
        }
    }

    It 'still honours -Width' {
        $out = Invoke-Ansi { Format-AnsiRule -Expand -Width 15 }
        (Remove-Ansi $out).Length | Should -Be 15
    }

    It 'keeps the title layout' {
        $out = Invoke-Ansi { Format-AnsiRule 'S' -Expand -Alignment Right }
        Remove-Ansi $out | Should -BeExactly (($script:Line * ($script:Buffer - 2)) + ' S')
    }
}

Describe 'Format-AnsiRule — input handling' {
    It 'renders one rule per pipeline item' {
        $lines = Invoke-AnsiLines { 'one', 'two' | Format-AnsiRule -Width 10 }
        $lines.Count | Should -Be 2
        (Remove-Ansi $lines[0]) | Should -BeExactly ('one ' + ($script:Line * 6))
        (Remove-Ansi $lines[1]) | Should -BeExactly ('two ' + ($script:Line * 6))
    }

    It 'binds -Title by name' {
        $out = Invoke-Ansi { Format-AnsiRule -Title 'S' -Width 10 }
        Remove-Ansi $out | Should -BeExactly ('S ' + ($script:Line * 8))
    }

    It 'takes the title positionally' {
        $out = Invoke-Ansi { Format-AnsiRule 'S' -Width 10 }
        Remove-Ansi $out | Should -BeExactly ('S ' + ($script:Line * 8))
    }
}

Describe 'Format-AnsiRule — | Out-AnsiHost -NoNewline' {
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

    It 'applies to the only row of an unspaced rule' {
        Format-AnsiRule -Width 10 | Out-AnsiHost -NoNewline
        $script:hostCalls.Count | Should -Be 1
        $script:hostCalls[0].NoNewline | Should -BeTrue
    }

    It 'applies only to the final row when spaced' {
        Format-AnsiRule -Width 10 -Spacing 1 | Out-AnsiHost -NoNewline
        $script:hostCalls.Count | Should -Be 3
        $script:hostCalls[-1].NoNewline | Should -BeTrue
        for ($i = 0; $i -lt $script:hostCalls.Count - 1; $i++) {
            $script:hostCalls[$i].NoNewline | Should -BeFalse
        }
    }

    It 'never sets NoNewline when the switch is absent' {
        Format-AnsiRule -Width 10 -Spacing 1
        foreach ($c in $script:hostCalls) { $c.NoNewline | Should -BeFalse }
    }
}

Describe 'Format-AnsiRule — no-colour output' {
    BeforeAll { Set-AnsiTestNoColor $true }
    AfterAll { Set-AnsiTestNoColor $false }

    It 'strips ANSI escape sequences' {
        $out = Invoke-Ansi { Format-AnsiRule '[bold]T[/]' -Width 12 -Color BrightRed -LineColor BrightBlue }
        $out | Should -Not -Match ([regex]::Escape([char]27))
        $out | Should -BeExactly ('T ' + ($script:Line * 10))
    }

    It 'drops hyperlinks but keeps the title text' {
        $out = Invoke-Ansi { Format-AnsiRule '[link=https://example.com]y[/]' -Width 10 }
        $out | Should -BeExactly ('y ' + ($script:Line * 8))
    }

    It 'preserves alignment, padding, and truncation' {
        $out = Invoke-Ansi { Format-AnsiRule 'Setup' -Width 20 -Alignment Center }
        $out | Should -BeExactly (($script:Line * 6) + ' Setup ' + ($script:Line * 7))

        $truncated = Invoke-Ansi { Format-AnsiRule 'A very long title indeed' -Width 12 }
        $truncated | Should -BeExactly ('A very lo' + $script:Ell + ' ' + $script:Line)
    }

    It 'still validates markup' {
        { Format-AnsiRule '[nosuch]x[/]' -Width 12 } | Should -Throw
    }
}

Describe 'Format-AnsiRule — module surface' {
    It 'exports only the formatter' {
        (Get-Module Format-AnsiRule).ExportedFunctions.Keys | Should -Be 'Format-AnsiRule'
    }
}
