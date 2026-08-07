#Requires -Version 7.2
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

# Format-AnsiPanel.Tests.ps1
# Pester 5 tests for Format-AnsiPanel. Rendered output is captured off the
# Information stream (Write-Host redirect 6>&1) and inspected as strings.
#
# Get-AnsiAnchor and Test-AnsiNoColor are replaced inside the Format-AnsiPanel module
# scope (44-column buffer, colour forced on) so the suite is host-independent.
# Injection is used rather than Mock: Pester cannot mock a command a module
# merely imported from another module.

BeforeAll {
    $script:src = Join-Path (Split-Path -Parent $PSScriptRoot) 'src'
    Import-Module (Join-Path $script:src 'Format-AnsiPanel.psm1') -Force -DisableNameChecking
    Import-Module (Join-Path $script:src 'Out-AnsiHost.psm1') -Force -DisableNameChecking
    Import-Module (Join-Path $script:src 'Out-AnsiString.psm1') -Force -DisableNameChecking
    $script:AnsiModule = Get-Module Format-AnsiPanel

    $script:Ell = [string][char]0x2026
    $script:Buffer = 44

    # Rounded (default) glyphs.
    $script:TL = [string][char]0x256D; $script:TR = [string][char]0x256E
    $script:BL = [string][char]0x2570; $script:BR = [string][char]0x256F
    $script:H = [string][char]0x2500; $script:V = [string][char]0x2502

    & $script:AnsiModule {
        $script:AnsiTestColumn = 0
        $script:AnsiTestNoColor = $false

        Set-Item function:script:Get-AnsiAnchor -Value {
            param([int]$MaxWidth = 0)
            [PSCustomObject]@{
                Column      = $script:AnsiTestColumn
                BufferWidth = 44
                Width       = $(if ($MaxWidth -gt 0) { $MaxWidth } else { 44 - $script:AnsiTestColumn })
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
        $plain = $Text -replace "`e\[[\d;]*m", ''
        return ($plain -replace "`e\]8;;[^`e]*`e\\", '')
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
}

Describe 'Format-AnsiPanel — framing' {
    It 'boxes a single line with one space of padding' {
        $rows = Invoke-AnsiPlain { Format-AnsiPanel 'hello' }
        $rows | Should -Be @(
            ($script:TL + ($script:H * 7) + $script:TR)
            ($script:V + ' hello ' + $script:V)
            ($script:BL + ($script:H * 7) + $script:BR)
        )
    }

    It 'sizes the box to the widest line' {
        $rows = Invoke-AnsiPlain { Format-AnsiPanel @('first', 'second line', 'third') }
        $rows.Count | Should -Be 5
        foreach ($r in $rows) { $r.Length | Should -Be 15 }
        $rows[1] | Should -BeExactly ($script:V + ' first       ' + $script:V)
    }

    It 'pads shorter lines to the inner width' {
        $rows = Invoke-AnsiPlain { Format-AnsiPanel @('a', 'bbb') }
        $rows[1] | Should -BeExactly ($script:V + ' a   ' + $script:V)
        $rows[2] | Should -BeExactly ($script:V + ' bbb ' + $script:V)
    }

    It 'splits a hard `n into rows' {
        $rows = Invoke-AnsiPlain { Format-AnsiPanel "one`ntwo" }
        $rows.Count | Should -Be 4
        $rows[1] | Should -BeExactly ($script:V + ' one ' + $script:V)
        $rows[2] | Should -BeExactly ($script:V + ' two ' + $script:V)
    }

    It 'boxes an empty string as one blank row' {
        $rows = Invoke-AnsiPlain { Format-AnsiPanel '' }
        $rows.Count | Should -Be 3
        $rows[1] | Should -BeExactly ($script:V + '   ' + $script:V)
    }

    It 'produces no output for $null' {
        $rows = Invoke-AnsiPlain { Format-AnsiPanel $null }
        $rows.Count | Should -Be 0
    }

    It 'produces no output for an empty collection' {
        $rows = Invoke-AnsiPlain { Format-AnsiPanel @() }
        $rows.Count | Should -Be 0
    }

    It 'accepts lines from the pipeline' {
        $rows = Invoke-AnsiPlain { @('a', 'b') | Format-AnsiPanel }
        $rows.Count | Should -Be 4
    }
}

Describe 'Format-AnsiPanel — -Title' {
    It 'sets the title into the top rule, left by default' {
        $rows = Invoke-AnsiPlain { Format-AnsiPanel 'body text here' -Title 'Build' }
        $rows[0] | Should -BeExactly ($script:TL + ' Build ' + ($script:H * 9) + $script:TR)
    }

    It 'centers the title' {
        $rows = Invoke-AnsiPlain { Format-AnsiPanel 'body text here' -Title 'Build' -TitleAlignment Center }
        $rows[0] | Should -BeExactly ($script:TL + ($script:H * 4) + ' Build ' + ($script:H * 5) + $script:TR)
    }

    It 'right-aligns the title' {
        $rows = Invoke-AnsiPlain { Format-AnsiPanel 'body text here' -Title 'Build' -TitleAlignment Right }
        $rows[0] | Should -BeExactly ($script:TL + ($script:H * 9) + ' Build ' + $script:TR)
    }

    It 'widens the panel when the title is wider than the body' {
        $rows = Invoke-AnsiPlain { Format-AnsiPanel 'x' -Title 'a longer title' }
        # title 14 + 2 spaces => inner 16, plus padding and borders => 20
        $rows[0].Length | Should -Be 20
        $rows[1] | Should -BeExactly ($script:V + ' x' + (' ' * 16) + $script:V)
    }

    It 'leaves the top rule plain without a title' {
        $rows = Invoke-AnsiPlain { Format-AnsiPanel 'x' }
        $rows[0] | Should -BeExactly ($script:TL + ($script:H * 3) + $script:TR)
    }

    It 'parses markup in the title' {
        $out = Invoke-Ansi { Format-AnsiPanel 'x' -Title '[bold]T[/]' }
        $out | Should -Match ([regex]::Escape($PSStyle.Bold))
    }

    It 'collapses a hard `n in the title' {
        $rows = Invoke-AnsiPlain { Format-AnsiPanel 'body text here' -Title "a`nb" }
        $rows[0] | Should -BeExactly ($script:TL + ' a b ' + ($script:H * 11) + $script:TR)
    }

    It 'rejects an unknown -TitleAlignment' {
        { Format-AnsiPanel 'x' -Title 't' -TitleAlignment Middle } | Should -Throw
    }
}

Describe 'Format-AnsiPanel — -Border' {
    It '<Border> draws with <Corner>' -ForEach @(
        @{ Border = 'Rounded'; Corner = [string][char]0x256D; Side = [string][char]0x2502 }
        @{ Border = 'Square'; Corner = [string][char]0x250C; Side = [string][char]0x2502 }
        @{ Border = 'Heavy'; Corner = [string][char]0x250F; Side = [string][char]0x2503 }
        @{ Border = 'Double'; Corner = [string][char]0x2554; Side = [string][char]0x2551 }
        @{ Border = 'Ascii'; Corner = '+'; Side = '|' }
    ) {
        $b = $Border
        $rows = Invoke-AnsiPlain { Format-AnsiPanel 'x' -Border $b }
        $rows[0].StartsWith($Corner) | Should -BeTrue
        $rows[1].StartsWith($Side) | Should -BeTrue
    }

    It 'None keeps the layout but draws no glyphs' {
        $rows = Invoke-AnsiPlain { Format-AnsiPanel 'x' -Border None }
        $rows.Count | Should -Be 3
        $rows[1] | Should -BeExactly '  x  '
        $rows[0].Trim() | Should -BeExactly ''
    }

    It 'is case-insensitive' {
        { Invoke-Ansi { Format-AnsiPanel 'x' -Border 'double' } } | Should -Not -Throw
    }

    It 'rejects an unknown border' {
        { Format-AnsiPanel 'x' -Border Wiggly } | Should -Throw
    }
}

Describe 'Format-AnsiPanel — -Padding, -Justify, -Width, -Height, -Expand' {
    It 'removes the inner gap at -Padding 0' {
        $rows = Invoke-AnsiPlain { Format-AnsiPanel 'tight' -Padding 0 }
        $rows[1] | Should -BeExactly ($script:V + 'tight' + $script:V)
        $rows[0] | Should -BeExactly ($script:TL + ($script:H * 5) + $script:TR)
    }

    It 'widens the inner gap' {
        $rows = Invoke-AnsiPlain { Format-AnsiPanel 'roomy' -Padding 3 }
        $rows[1] | Should -BeExactly ($script:V + '   roomy   ' + $script:V)
    }

    It 'rejects a negative padding' {
        { Format-AnsiPanel 'x' -Padding -1 } | Should -Throw
    }

    It 'centers content with -Justify Center' {
        $rows = Invoke-AnsiPlain { Format-AnsiPanel @('a', 'ccc') -Justify Center }
        $rows[1] | Should -BeExactly ($script:V + '  a  ' + $script:V)
    }

    It 'right-aligns content with -Justify Right' {
        $rows = Invoke-AnsiPlain { Format-AnsiPanel @('a', 'ccc') -Justify Right }
        $rows[1] | Should -BeExactly ($script:V + '   a ' + $script:V)
    }

    It 'wraps content to the inner width of -Width' {
        $rows = Invoke-AnsiPlain {
            Format-AnsiPanel 'a long paragraph that certainly does not fit inside' -Width 30
        }
        $rows.Count | Should -BeGreaterThan 3
        foreach ($r in $rows) { $r.Length | Should -BeLessOrEqual 30 }
    }

    It 'accepts -MaxWidth as an alias of -Width' {
        $a = Invoke-AnsiPlain { Format-AnsiPanel 'a long paragraph that will wrap here' -Width 24 }
        $b = Invoke-AnsiPlain { Format-AnsiPanel 'a long paragraph that will wrap here' -MaxWidth 24 }
        $a | Should -Be $b
    }

    It 'fills the available width with -Expand' {
        $rows = Invoke-AnsiPlain { Format-AnsiPanel 'x' -Expand }
        foreach ($r in $rows) { $r.Length | Should -Be $script:Buffer }
    }

    It 'fills a given -Width with -Expand' {
        $rows = Invoke-AnsiPlain { Format-AnsiPanel 'x' -Expand -Width 20 }
        $rows[0].Length | Should -Be 20
    }

    It 'pads to -Height with blank rows' {
        $rows = Invoke-AnsiPlain { Format-AnsiPanel @('a', 'b') -Height 6 }
        $rows.Count | Should -Be 6
        $rows[4] | Should -BeExactly ($script:V + '   ' + $script:V)
    }

    It 'drops content that exceeds -Height' {
        $rows = Invoke-AnsiPlain { Format-AnsiPanel @('a', 'b', 'c', 'd') -Height 3 }
        $rows.Count | Should -Be 3
        $rows[1] | Should -BeExactly ($script:V + ' a ' + $script:V)
    }

    It 'rejects a negative height' {
        { Format-AnsiPanel 'x' -Height -1 } | Should -Throw
    }
}

Describe 'Format-AnsiPanel — colours' {
    It 'colours the border with -BorderColor' {
        $out = Invoke-Ansi { Format-AnsiPanel 'x' -BorderColor DarkGray }
        $out | Should -Match ([regex]::Escape($PSStyle.Foreground.BrightBlack + $script:TL))
    }

    It 'colours content with -TextColor' {
        $out = Invoke-Ansi { Format-AnsiPanel 'x' -TextColor BrightCyan }
        $out | Should -Match ([regex]::Escape($PSStyle.Foreground.BrightCyan + 'x'))
    }

    It 'colours the title with -TitleColor' {
        $out = Invoke-Ansi { Format-AnsiPanel 'x' -Title 'T' -TitleColor BrightMagenta }
        $out | Should -Match ([regex]::Escape($PSStyle.Foreground.BrightMagenta + 'T'))
    }

    It 'falls back to the border colour for the title' {
        $out = Invoke-Ansi { Format-AnsiPanel 'x' -Title 'T' -BorderColor BrightBlue }
        $out | Should -Match ([regex]::Escape($PSStyle.Foreground.BrightBlue + 'T'))
    }

    It 'renders unstyled by default' {
        $out = Invoke-Ansi { Format-AnsiPanel 'x' }
        $out | Should -Not -Match ([regex]::Escape([char]27))
    }

    It 'lets content set its own colour via markup' {
        $out = Invoke-Ansi { Format-AnsiPanel '[BrightGreen]ok[/]' -TextColor DarkGray }
        $out | Should -Match ([regex]::Escape($PSStyle.Foreground.BrightGreen + 'ok'))
    }

    It 'throws on an unknown <Parameter>' -ForEach @(
        @{ Parameter = 'BorderColor' }
        @{ Parameter = 'TextColor' }
        @{ Parameter = 'TitleColor' }
    ) {
        $splat = @{ $Parameter = 'Nope' }
        { Format-AnsiPanel 'x' -Title 't' @splat } | Should -Throw
    }
}

Describe 'Format-AnsiPanel — markup in content' {
    It 'parses markup by default' {
        $out = Invoke-Ansi { Format-AnsiPanel '[bold]x[/]' }
        $out | Should -Match ([regex]::Escape($PSStyle.Bold))
        (Remove-Ansi $out) -split "`n" | Should -Contain ($script:V + ' x ' + $script:V)
    }

    It 'sizes the panel on visible width, not markup length' {
        $rows = Invoke-AnsiPlain { Format-AnsiPanel '[bold]x[/]' }
        $rows[0].Length | Should -Be 5
    }

    It 'renders markdown sugar with -Markdown' {
        $out = Invoke-Ansi { Format-AnsiPanel '**x**' -Markdown }
        $out | Should -Match ([regex]::Escape($PSStyle.Bold))
    }

    It 'replaces emoji with -Markdown' {
        $rows = Invoke-AnsiPlain { Format-AnsiPanel ':check:' -Markdown }
        $rows[1] | Should -BeExactly ($script:V + ' ' + [string][char]0x2713 + ' ' + $script:V)
    }

    It 'treats content as literal with -Escape' {
        $rows = Invoke-AnsiPlain { Format-AnsiPanel '[bold]x[/]' -Escape }
        $rows[1] | Should -BeExactly ($script:V + ' [bold]x[/] ' + $script:V)
    }

    It 'throws on invalid markup' {
        { Format-AnsiPanel '[nosuch]x[/]' } | Should -Throw
    }

    It 'does not throw on invalid markup under -Escape' {
        { Invoke-Ansi { Format-AnsiPanel '[nosuch]x' -Escape } } | Should -Not -Throw
    }
}

Describe 'Format-AnsiPanel — -Rendered (frame captured output)' {
    BeforeAll {
        # A pre-rendered block: styled text whose escape bytes must not count
        # towards the width.
        $script:StyledRows = @(
            ($PSStyle.Foreground.BrightGreen + 'first' + $PSStyle.Reset)
            ($PSStyle.Bold + 'second row' + $PSStyle.Reset)
        )
    }

    It 'measures visible width, ignoring ANSI' {
        $rows = Invoke-AnsiPlain { Format-AnsiPanel $script:StyledRows -Rendered }
        foreach ($r in $rows) { $r.Length | Should -Be 14 }
        $rows[1] | Should -BeExactly ($script:V + ' first      ' + $script:V)
    }

    It 'keeps the original styling' {
        $out = Invoke-Ansi { Format-AnsiPanel $script:StyledRows -Rendered }
        $out | Should -Match ([regex]::Escape($PSStyle.Foreground.BrightGreen))
        $out | Should -Match ([regex]::Escape($PSStyle.Bold))
    }

    It 'does not parse markup in rendered content' {
        $rows = Invoke-AnsiPlain { Format-AnsiPanel '[bold]x[/]' -Rendered }
        $rows[1] | Should -BeExactly ($script:V + ' [bold]x[/] ' + $script:V)
    }

    It 'never re-wraps rendered rows, it truncates them' {
        $long = @(('x' * 60))
        $rows = Invoke-AnsiPlain { Format-AnsiPanel $long -Rendered -Width 20 }
        $rows.Count | Should -Be 3
        $rows[1] | Should -Match ([regex]::Escape($script:Ell))
        $rows[1].Length | Should -Be 20
    }

    It 'frames rows captured from another component' {
        Import-Module (Join-Path $script:src 'Format-AnsiGrid.psm1') -Force -DisableNameChecking
        & (Get-Module Format-AnsiGrid) {
            Set-Item function:script:Get-AnsiAnchor -Value {
                param([int]$MaxWidth = 0)
                [PSCustomObject]@{ Column = 0; BufferWidth = 30; Width = $(if ($MaxWidth -gt 0) { $MaxWidth } else { 30 }) }
            }
            Set-Item function:script:Test-AnsiNoColor -Value { $false }
        }
        $captured = Format-AnsiGrid @(, @('k', 'v'), @('kk', 'vv')) -Color BrightCyan | Out-AnsiString
        $rows = Invoke-AnsiPlain { Format-AnsiPanel $captured -Rendered -Title 'grid' }

        $rows.Count | Should -Be 4
        $rows[1] | Should -BeExactly ($script:V + ' k   v  ' + $script:V)
        $rows[2] | Should -BeExactly ($script:V + ' kk  vv ' + $script:V)
    }
}

Describe 'Format-AnsiPanel — nested renderings' {
    It 'frames another rendering row for row' {
        Import-Module (Join-Path $script:src 'Format-AnsiGrid.psm1') -Force -DisableNameChecking
        & (Get-Module Format-AnsiGrid) {
            Set-Item function:script:Get-AnsiAnchor -Value {
                param([int]$MaxWidth = 0)
                [PSCustomObject]@{ Column = 0; BufferWidth = 44; Width = $(if ($MaxWidth -gt 0) { $MaxWidth } else { 44 }) }
            }
            Set-Item function:script:Test-AnsiNoColor -Value { $false }
        }

        $grid = Format-AnsiGrid @(, @('k', 'v'), @('kk', 'vv')) -MaxWidth 20
        $rows = Invoke-AnsiPlain { Format-AnsiPanel $grid -Title 'grid' }

        $rows.Count | Should -Be 4
        $rows[1] | Should -BeExactly ($script:V + ' k   v  ' + $script:V)
        $rows[2] | Should -BeExactly ($script:V + ' kk  vv ' + $script:V)
    }

    It 'mixes text lines and a nested rendering in order' {
        $inner = Format-AnsiPanel 'inner' -Border Square
        $rows = Invoke-AnsiPlain { Format-AnsiPanel @('above', $inner, 'below') }
        $plain = $rows -join "`n"
        $plain | Should -Match 'above'
        $plain | Should -Match ([regex]::Escape([string][char]0x250C))   # the inner box
        $plain | Should -Match 'below'
    }
}

Describe 'Format-AnsiPanel — anchoring' {
    BeforeAll { Set-AnsiTestColumn 4 }
    AfterAll { Set-AnsiTestColumn 0 }

    It 'leaves the first row where the cursor already is' {
        $rows = Invoke-AnsiPlain { Format-AnsiPanel @('a', 'b') }
        $rows[0] | Should -BeExactly ($script:TL + ($script:H * 3) + $script:TR)
    }

    It 'resumes later rows at the anchor column' {
        $rows = Invoke-AnsiPlain { Format-AnsiPanel @('a', 'b') }
        $rows[1] | Should -BeExactly ((' ' * 4) + $script:V + ' a ' + $script:V)
        $rows[-1] | Should -BeExactly ((' ' * 4) + $script:BL + ($script:H * 3) + $script:BR)
    }

    It 'sizes the panel to the remaining buffer with -Expand' {
        $rows = Invoke-AnsiPlain { Format-AnsiPanel 'x' -Expand }
        $rows[0].Length | Should -Be ($script:Buffer - 4)
    }
}

Describe 'Format-AnsiPanel — | Out-AnsiHost -NoNewline' {
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

    It 'applies only to the bottom rule' {
        Format-AnsiPanel @('a', 'b') | Out-AnsiHost -NoNewline
        $script:hostCalls.Count | Should -Be 4
        $script:hostCalls[-1].NoNewline | Should -BeTrue
        for ($i = 0; $i -lt $script:hostCalls.Count - 1; $i++) {
            $script:hostCalls[$i].NoNewline | Should -BeFalse
        }
    }

    It 'never sets NoNewline when the switch is absent' {
        Format-AnsiPanel @('a', 'b')
        foreach ($c in $script:hostCalls) { $c.NoNewline | Should -BeFalse }
    }
}

Describe 'Format-AnsiPanel — no-colour output' {
    BeforeAll { Set-AnsiTestNoColor $true }
    AfterAll { Set-AnsiTestNoColor $false }

    It 'strips ANSI escape sequences' {
        $out = Invoke-Ansi { Format-AnsiPanel '[bold]x[/]' -Title 'T' -BorderColor DarkGray -TextColor BrightCyan }
        $out | Should -Not -Match ([regex]::Escape([char]27))
    }

    It 'strips ANSI from rendered content too' {
        $out = Invoke-Ansi {
            Format-AnsiPanel @(($PSStyle.Foreground.BrightGreen + 'ok' + $PSStyle.Reset)) -Rendered
        }
        $out | Should -Not -Match ([regex]::Escape([char]27))
        ($out -split "`n")[1] | Should -BeExactly ($script:V + ' ok ' + $script:V)
    }

    It 'preserves the frame, title, and padding' {
        $rows = Invoke-AnsiLines { Format-AnsiPanel 'body text here' -Title 'Build' -Padding 2 }
        $rows[0] | Should -BeExactly ($script:TL + ' Build ' + ($script:H * 11) + $script:TR)
        $rows[1] | Should -BeExactly ($script:V + '  body text here  ' + $script:V)
    }
}

Describe 'Format-AnsiPanel — module surface' {
    It 'exports only the formatter' {
        (Get-Module Format-AnsiPanel).ExportedFunctions.Keys | Should -Be 'Format-AnsiPanel'
    }
}
