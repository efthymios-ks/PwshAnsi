#Requires -Version 7.2
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

# Format-AnsiText.Tests.ps1
# Pester 5 tests for Format-AnsiText. Rendered output is captured off the
# Information stream (Write-Host redirect 6>&1) and inspected as strings.
#
# Two Ansi.Core helpers are replaced inside the Format-AnsiText module scope so the
# suite is deterministic regardless of the host it runs on:
#   Get-AnsiAnchor    — pinned to a known column and a 120-column buffer, so
#                      anchoring never depends on the real cursor position.
#                      Set-AnsiTestColumn moves it for the anchoring block.
#   Test-AnsiNoColor  — driven by Set-AnsiTestNoColor instead of the environment,
#                      so ANSI is emitted even when the run's stdout is
#                      redirected (Pester sets NO_COLOR itself under CI), while
#                      the no-colour block still exercises the stripped path.
# They are swapped by injecting into the module's session state rather than with
# Mock: Pester cannot mock a command a module merely imported from another one.
# The real Test-AnsiNoColor is still exercised against a separate Ansi.Core import.

BeforeAll {
    $script:src = Join-Path (Split-Path -Parent $PSScriptRoot) 'src'
    Import-Module (Join-Path $script:src 'Format-AnsiText.psm1') -Force -DisableNameChecking
    Import-Module (Join-Path $script:src 'Out-AnsiHost.psm1') -Force -DisableNameChecking
    Import-Module (Join-Path $script:src 'Out-AnsiString.psm1') -Force -DisableNameChecking
    $script:AnsiModule = Get-Module Format-AnsiText
    $script:AnsiCore = Import-Module (Join-Path $script:src 'Ansi.Core.psm1') -Force -DisableNameChecking -PassThru

    $script:Esc = [char]27
    $script:St = [string][char]27 + '\'       # OSC string terminator: ESC \
    $script:Ell = [char]0x2026                # …

    & $script:AnsiModule {
        $script:AnsiTestColumn = 0
        $script:AnsiTestNoColor = $false

        Set-Item function:script:Get-AnsiAnchor -Value {
            param([int]$MaxWidth = 0)
            [PSCustomObject]@{
                Column      = $script:AnsiTestColumn
                BufferWidth = 120
                Width       = $(if ($MaxWidth -gt 0) { $MaxWidth } else { 120 - $script:AnsiTestColumn })
            }
        }

        Set-Item function:script:Test-AnsiNoColor -Value { $script:AnsiTestNoColor }
    }

    # Move the pretend cursor column the rendering anchors to.
    function Set-AnsiTestColumn {
        param([Parameter(Mandatory)][int]$Column)
        & $script:AnsiModule { param($c) $script:AnsiTestColumn = $c } $Column
    }

    # Force the styled / stripped rendering path.
    function Set-AnsiTestNoColor {
        param([Parameter(Mandatory)][bool]$Value)
        & $script:AnsiModule { param($v) $script:AnsiTestNoColor = $v } $Value
    }

    # Capture helper — merges the Information stream into the pipeline and
    # returns one string per Write-Host call (i.e. one per rendered row).
    # The leading comma keeps single-row and empty results arrays.
    # The block returns an [Ansi.Rendering]; painting it is this helper's job.
    function Invoke-AnsiLines {
        param([Parameter(Mandatory)][scriptblock]$Sb)
        $records = & { & $Sb | Out-AnsiHost } 6>&1
        if ($null -eq $records) { return , @() }
        $rows = @($records | ForEach-Object { [string]$_.ToString() })
        return , $rows
    }

    # Same, joined into a single block of text.
    function Invoke-Ansi {
        param([Parameter(Mandatory)][scriptblock]$Sb)
        return ((Invoke-AnsiLines $Sb) -join "`n")
    }

    # Strip all CSI ANSI sequences (m-terminated) so we can compare plain layout.
    function Remove-Ansi {
        param([AllowEmptyString()][string]$Text)
        return ($Text -replace "`e\[[\d;]*m", '')
    }

    # Strip OSC 8 hyperlink wrappers, keeping the link text.
    function Remove-Osc {
        param([AllowEmptyString()][string]$Text)
        return ($Text -replace "`e\]8;;[^`e]*`e\\", '')
    }

    # Fully plain text: no styles, no hyperlinks.
    function Get-Plain {
        param([AllowEmptyString()][string]$Text)
        return (Remove-Osc (Remove-Ansi $Text))
    }

    # Occurrence count of a literal substring.
    function Measure-Occurrence {
        param([string]$Text, [string]$Needle)
        return ([regex]::Matches($Text, [regex]::Escape($Needle))).Count
    }
}

Describe 'Format-AnsiText — input handling' {
    It 'writes a single line for a single string' {
        $out = Invoke-Ansi { Format-AnsiText 'hello' }
        Remove-Ansi $out | Should -BeExactly 'hello'
    }

    It 'binds -Message by name' {
        $out = Invoke-Ansi { Format-AnsiText -Message 'hello' }
        Remove-Ansi $out | Should -BeExactly 'hello'
    }

    It 'produces no output for an empty collection' {
        $lines = Invoke-AnsiLines { Format-AnsiText @() }
        $lines.Count | Should -Be 0
    }

    It 'produces no output when nothing is piped in' {
        $lines = Invoke-AnsiLines { @() | Format-AnsiText }
        $lines.Count | Should -Be 0
    }

    It 'produces no output for $null' {
        $lines = Invoke-AnsiLines { Format-AnsiText $null }
        $lines.Count | Should -Be 0
    }

    It 'writes one blank row for an empty string' {
        $lines = Invoke-AnsiLines { Format-AnsiText '' }
        $lines.Count | Should -Be 1
        Remove-Ansi $lines[0] | Should -BeExactly ''
    }

    It 'preserves a whitespace-only message' {
        $out = Invoke-Ansi { Format-AnsiText '   ' }
        Remove-Ansi $out | Should -BeExactly '   '
    }

    It 'coerces non-string input to string' {
        $out = Invoke-Ansi { Format-AnsiText 42 }
        Remove-Ansi $out | Should -BeExactly '42'
    }

    It 'writes one line per array item (positional)' {
        $lines = Invoke-AnsiLines { Format-AnsiText 'a', 'b', 'c' }
        $lines.Count | Should -Be 3
        (Remove-Ansi $lines[0]) | Should -BeExactly 'a'
        (Remove-Ansi $lines[2]) | Should -BeExactly 'c'
    }

    It 'writes one line per pipeline item' {
        $lines = Invoke-AnsiLines { 'x', 'y' | Format-AnsiText }
        $lines.Count | Should -Be 2
    }

    It 'renders all pipeline items in one block (rendered in end)' {
        $lines = Invoke-AnsiLines { 'alpha', 'bravo', 'charlie' | Format-AnsiText }
        (Remove-Ansi ($lines -join '|')) | Should -BeExactly 'alpha|bravo|charlie'
    }

    It 'splits an embedded `n into multiple lines' {
        $lines = Invoke-AnsiLines { Format-AnsiText "one`ntwo`nthree" }
        $lines.Count | Should -Be 3
        (Remove-Ansi $lines[0]) | Should -BeExactly 'one'
        (Remove-Ansi $lines[2]) | Should -BeExactly 'three'
    }
}

Describe 'Format-AnsiText — -Color' {
    It 'wraps content in the requested foreground ANSI code' {
        $out = Invoke-Ansi { Format-AnsiText 'x' -Color BrightRed }
        $out | Should -Match ([regex]::Escape($PSStyle.Foreground.BrightRed))
        $out | Should -Match ([regex]::Escape($PSStyle.Reset))
        Remove-Ansi $out | Should -BeExactly 'x'
    }

    It 'accepts $PSStyle colour name <_>' -ForEach @(
        'Black', 'Red', 'Green', 'Yellow', 'Blue', 'Magenta', 'Cyan', 'White'
        'BrightBlack', 'BrightRed', 'BrightGreen', 'BrightYellow'
        'BrightBlue', 'BrightMagenta', 'BrightCyan', 'BrightWhite'
    ) {
        $name = $_
        $out = Invoke-Ansi { Format-AnsiText 'x' -Color $name }
        $out | Should -Match ([regex]::Escape($PSStyle.Foreground.$name))
    }

    It 'maps ConsoleColor alias <Alias> onto <Target>' -ForEach @(
        @{ Alias = 'DarkRed'; Target = 'Red' }
        @{ Alias = 'DarkGreen'; Target = 'Green' }
        @{ Alias = 'DarkYellow'; Target = 'Yellow' }
        @{ Alias = 'DarkBlue'; Target = 'Blue' }
        @{ Alias = 'DarkMagenta'; Target = 'Magenta' }
        @{ Alias = 'DarkCyan'; Target = 'Cyan' }
        @{ Alias = 'Gray'; Target = 'White' }
        @{ Alias = 'DarkGray'; Target = 'BrightBlack' }
    ) {
        $out = Invoke-Ansi { Format-AnsiText 'x' -Color $Alias }
        $out | Should -Match ([regex]::Escape($PSStyle.Foreground.$Target))
    }

    It 'is case-insensitive' {
        $out = Invoke-Ansi { Format-AnsiText 'x' -Color 'brightcyan' }
        $out | Should -Match ([regex]::Escape($PSStyle.Foreground.BrightCyan))
    }

    It 'throws on unknown colour names' {
        { Format-AnsiText 'x' -Color NotAColour } | Should -Throw
    }

    It 'does not overwrite a colour set via markup' {
        $out = Invoke-Ansi { Format-AnsiText '[BrightGreen]x[/]' -Color BrightRed }
        $out | Should -Match ([regex]::Escape($PSStyle.Foreground.BrightGreen))
        $out | Should -Not -Match ([regex]::Escape($PSStyle.Foreground.BrightRed))
    }

    It 'colours runs that only carry a style' {
        # 'a' is unstyled, 'b' is bold — both pick up the -Color foreground.
        $out = Invoke-Ansi { Format-AnsiText 'a[bold]b[/]' -Color BrightRed }
        Measure-Occurrence $out $PSStyle.Foreground.BrightRed | Should -Be 2
        $out | Should -Match ([regex]::Escape($PSStyle.Bold))
    }

    It 'does not set a background' {
        $out = Invoke-Ansi { Format-AnsiText 'x' -Color BrightRed }
        $out | Should -Not -Match ([regex]::Escape($PSStyle.Background.BrightRed))
    }
}

Describe 'Format-AnsiText — markup' {
    It 'applies [<Tag>]' -ForEach @(
        @{ Tag = 'bold'; Style = 'Bold' }
        @{ Tag = 'italic'; Style = 'Italic' }
        @{ Tag = 'underline'; Style = 'Underline' }
        @{ Tag = 'strikethrough'; Style = 'Strikethrough' }
        @{ Tag = 'reverse'; Style = 'Reverse' }
    ) {
        $text = "[$Tag]x[/]"
        $out = Invoke-Ansi { Format-AnsiText $text }
        $out | Should -Match ([regex]::Escape($PSStyle.$Style))
        Remove-Ansi $out | Should -BeExactly 'x'
    }

    It 'combines foreground, background, and style in one tag' {
        $out = Invoke-Ansi { Format-AnsiText '[bold BrightRed on Blue]x[/]' }
        $out | Should -Match ([regex]::Escape($PSStyle.Bold))
        $out | Should -Match ([regex]::Escape($PSStyle.Foreground.BrightRed))
        $out | Should -Match ([regex]::Escape($PSStyle.Background.Blue))
    }

    It 'inherits the enclosing frame in a nested tag' {
        # Inner run is bold AND still BrightRed; all three runs keep the colour.
        $out = Invoke-Ansi { Format-AnsiText '[BrightRed]a[bold]b[/]c[/]' }
        Measure-Occurrence $out $PSStyle.Foreground.BrightRed | Should -Be 3
        Measure-Occurrence $out $PSStyle.Bold | Should -Be 1
    }

    It 'restores the outer frame after [/]' {
        $out = Invoke-Ansi { Format-AnsiText '[BrightRed]a[bold]b[/]c[/]' }
        Remove-Ansi $out | Should -BeExactly 'abc'
    }

    It 'leaves untagged text unstyled' {
        $out = Invoke-Ansi { Format-AnsiText 'plain' }
        $out | Should -BeExactly 'plain'
    }

    It 'unescapes [[ and ]] as literal brackets' {
        $out = Invoke-Ansi { Format-AnsiText 'a [[b]] c' }
        Remove-Ansi $out | Should -BeExactly 'a [b] c'
    }

    It 'renders [link=url] as an OSC 8 hyperlink' {
        $out = Invoke-Ansi { Format-AnsiText '[link=https://example.com]y[/]' }
        $expected = "$($script:Esc)]8;;https://example.com$($script:St)y$($script:Esc)]8;;$($script:St)"
        $out | Should -BeExactly $expected
        Get-Plain $out | Should -BeExactly 'y'
    }

    It 'combines a link with styling' {
        $out = Invoke-Ansi { Format-AnsiText '[link=https://example.com][underline]y[/][/]' }
        $out | Should -Match ([regex]::Escape($PSStyle.Underline))
        $out | Should -Match ([regex]::Escape('https://example.com'))
        Get-Plain $out | Should -BeExactly 'y'
    }

    It 'throws on an unknown colour token' {
        { Format-AnsiText '[nosuch]x[/]' } | Should -Throw
    }

    It 'throws on unbalanced opening tag' {
        { Format-AnsiText '[bold]x' } | Should -Throw
    }

    It 'throws on an unbalanced closing tag' {
        { Format-AnsiText 'x[/]' } | Should -Throw
    }

    It 'throws on a tag that is never closed with ]' {
        { Format-AnsiText 'a [bold x' } | Should -Throw
    }

    It "throws when 'on' has no background colour" {
        { Format-AnsiText '[bold on]x[/]' } | Should -Throw
    }
}

Describe 'Format-AnsiText — markdown' {
    It 'renders **bold**' {
        $out = Invoke-Ansi { Format-AnsiText '**x**' -Markdown }
        $out | Should -Match ([regex]::Escape($PSStyle.Bold))
        Remove-Ansi $out | Should -BeExactly 'x'
    }

    It 'renders *italic*' {
        $out = Invoke-Ansi { Format-AnsiText '*x*' -Markdown }
        $out | Should -Match ([regex]::Escape($PSStyle.Italic))
    }

    It 'renders __underline__' {
        $out = Invoke-Ansi { Format-AnsiText '__x__' -Markdown }
        $out | Should -Match ([regex]::Escape($PSStyle.Underline))
    }

    It 'renders ~~strikethrough~~' {
        $out = Invoke-Ansi { Format-AnsiText '~~x~~' -Markdown }
        $out | Should -Match ([regex]::Escape($PSStyle.Strikethrough))
    }

    It 'renders `code` as BrightYellow' {
        $out = Invoke-Ansi { Format-AnsiText '`x`' -Markdown }
        $out | Should -Match ([regex]::Escape($PSStyle.Foreground.BrightYellow))
    }

    It 'renders [text](url) as OSC 8' {
        $out = Invoke-Ansi { Format-AnsiText '[label](https://x.com)' -Markdown }
        $expected = "$($script:Esc)]8;;https://x.com$($script:St)label$($script:Esc)]8;;$($script:St)"
        $out | Should -BeExactly $expected
    }

    It 'renders {style}...{/} long form' {
        $out = Invoke-Ansi { Format-AnsiText '{BrightMagenta}x{/}' -Markdown }
        $out | Should -Match ([regex]::Escape($PSStyle.Foreground.BrightMagenta))
    }

    It 'renders a {style on style}...{/} long form with a background' {
        $out = Invoke-Ansi { Format-AnsiText '{bold BrightMagenta on Black}x{/}' -Markdown }
        $out | Should -Match ([regex]::Escape($PSStyle.Bold))
        $out | Should -Match ([regex]::Escape($PSStyle.Background.Black))
    }

    It 'nests sugar inside sugar' {
        $out = Invoke-Ansi { Format-AnsiText '**bold with *italic* inside**' -Markdown }
        $out | Should -Match ([regex]::Escape($PSStyle.Bold))
        $out | Should -Match ([regex]::Escape($PSStyle.Italic))
        Remove-Ansi $out | Should -BeExactly 'bold with italic inside'
    }

    It 'composes with raw markup tags' {
        $out = Invoke-Ansi { Format-AnsiText '[BrightCyan]**x**[/]' -Markdown }
        $out | Should -Match ([regex]::Escape($PSStyle.Bold))
        $out | Should -Match ([regex]::Escape($PSStyle.Foreground.BrightCyan))
    }

    It 'honours backslash escapes for markup metachars' {
        $out = Invoke-Ansi { Format-AnsiText '\*not italic\* and \[not link\]' -Markdown }
        Remove-Ansi $out | Should -BeExactly '*not italic* and [not link]'
    }

    It 'honours backslash escapes for backtick, brace, tilde, and underscore' {
        $out = Invoke-Ansi { Format-AnsiText '\`a\` \{b\} \~c\~ \_d\_' -Markdown }
        Remove-Ansi $out | Should -BeExactly '`a` {b} ~c~ _d_'
    }

    It 'leaves markdown sugar literal when -Markdown is absent' {
        $out = Invoke-Ansi { Format-AnsiText '**x** and `y` and ~~z~~' }
        Remove-Ansi $out | Should -BeExactly '**x** and `y` and ~~z~~'
    }

    It 'replaces :<Token>:' -ForEach @(
        @{ Token = 'check'; Glyph = [string][char]0x2713 }
        @{ Token = 'cross'; Glyph = [string][char]0x2717 }
        @{ Token = 'warn'; Glyph = [string][char]0x26A0 }
        @{ Token = 'info'; Glyph = [string][char]0x2139 }
        @{ Token = 'star'; Glyph = [string][char]0x2605 }
        @{ Token = 'heart'; Glyph = [string][char]0x2665 }
        @{ Token = 'arrow'; Glyph = [string][char]0x2192 }
        @{ Token = 'bullet'; Glyph = [string][char]0x2022 }
        @{ Token = 'fire'; Glyph = [string]::new([char[]](0xD83D, 0xDD25)) }
        @{ Token = 'rocket'; Glyph = [string]::new([char[]](0xD83D, 0xDE80)) }
        @{ Token = 'bug'; Glyph = [string]::new([char[]](0xD83D, 0xDC1B)) }
        @{ Token = 'sparkles'; Glyph = [string]::new([char[]](0x2728)) }
        @{ Token = 'tada'; Glyph = [string]::new([char[]](0xD83C, 0xDF89)) }
    ) {
        $text = ":${Token}:"
        $out = Invoke-Ansi { Format-AnsiText $text -Markdown }
        (Remove-Ansi $out) | Should -BeExactly $Glyph
    }

    It 'leaves unknown :xyz: tokens alone' {
        $out = Invoke-Ansi { Format-AnsiText ':not_a_real_emoji:' -Markdown }
        Remove-Ansi $out | Should -BeExactly ':not_a_real_emoji:'
    }

    It 'leaves :emoji: tokens alone without -Markdown' {
        $out = Invoke-Ansi { Format-AnsiText ':check:' }
        Remove-Ansi $out | Should -BeExactly ':check:'
    }

    It 'replaces the full-table name :<Token>:' -ForEach @(
        @{ Token = 'grinning_face'; Code = 0x1F600 }
        @{ Token = 'party_popper'; Code = 0x1F389 }
        @{ Token = 'check_mark'; Code = 0x2714 }
        @{ Token = 'cross_mark'; Code = 0x274C }
        @{ Token = 'red_heart'; Code = 0x2764 }
        @{ Token = 'thumbs_up'; Code = 0x1F44D }
    ) {
        $text = ":${Token}:"
        $out = Invoke-Ansi { Format-AnsiText $text -Markdown }
        (Remove-Ansi $out) | Should -BeExactly ([char]::ConvertFromUtf32($Code))
    }

    It 'replaces a name with digits in it' {
        # :1st_place_medal: and :keycap_10: — the token grammar is \w+, not letters.
        $out = Invoke-Ansi { Format-AnsiText ':1st_place_medal: :keycap_10:' -Markdown }
        (Remove-Ansi $out) | Should -BeExactly (
            [char]::ConvertFromUtf32(0x1F947) + ' ' + [char]::ConvertFromUtf32(0x1F51F))
    }

    It 'keeps the variation selector a name carries' {
        # :warning: is U+26A0 U+FE0F — the selector is what makes it render in colour.
        $out = Invoke-Ansi { Format-AnsiText ':warning:' -Markdown }
        (Remove-Ansi $out) | Should -BeExactly ([string][char]0x26A0 + [char]0xFE0F)
    }

    It 'matches a name whatever its case' {
        $out = Invoke-Ansi { Format-AnsiText ':ROCKET: :Grinning_Face:' -Markdown }
        (Remove-Ansi $out) | Should -BeExactly (
            [char]::ConvertFromUtf32(0x1F680) + ' ' + [char]::ConvertFromUtf32(0x1F600))
    }

    It 'gives PwshAnsi its own short name over the table one' {
        # :star: is the text star it has always been, not the table's U+2B50.
        $out = Invoke-Ansi { Format-AnsiText ':star:' -Markdown }
        (Remove-Ansi $out) | Should -BeExactly ([string][char]0x2605)
    }

    It 'knows the whole shortcode set' {
        $table = & $script:AnsiCore { Get-AnsiEmojiTable }
        $table.Count | Should -BeGreaterThan 1400
    }
}

Describe 'Format-AnsiText — -Justify' {
    It 'left-aligns by default (no padding)' {
        $out = Invoke-Ansi { Format-AnsiText 'x' -MaxWidth 10 }
        Remove-Ansi $out | Should -BeExactly 'x'
    }

    It 'centers within the effective width' {
        # pad = 9, leftPad = floor(9/2) = 4
        $out = Invoke-Ansi { Format-AnsiText 'x' -MaxWidth 10 -Justify Center }
        Remove-Ansi $out | Should -BeExactly ((' ' * 4) + 'x')
    }

    It 'right-aligns within the effective width' {
        # leftPad = pad = 9
        $out = Invoke-Ansi { Format-AnsiText 'x' -MaxWidth 10 -Justify Right }
        Remove-Ansi $out | Should -BeExactly ((' ' * 9) + 'x')
    }

    It 'justifies each row independently' {
        $lines = Invoke-AnsiLines { Format-AnsiText "x`nyy" -MaxWidth 6 -Justify Right }
        $lines.Count | Should -Be 2
        (Remove-Ansi $lines[0]) | Should -BeExactly ((' ' * 5) + 'x')
        (Remove-Ansi $lines[1]) | Should -BeExactly ((' ' * 4) + 'yy')
    }

    It 'measures visible width only — padding ignores ANSI' {
        $out = Invoke-Ansi { Format-AnsiText '[bold]x[/]' -MaxWidth 10 -Justify Right }
        (Remove-Ansi $out) | Should -BeExactly ((' ' * 9) + 'x')
    }

    It 'does not pad when the row already fills the width' {
        $out = Invoke-Ansi { Format-AnsiText 'abcde' -MaxWidth 5 -Justify Center }
        Remove-Ansi $out | Should -BeExactly 'abcde'
    }
}

Describe 'Format-AnsiText — wrapping' {
    It 'wraps at word boundaries (Fold, default)' {
        $lines = Invoke-AnsiLines { Format-AnsiText 'aaa bbb ccc' -MaxWidth 5 }
        $lines.Count | Should -Be 3
        foreach ($l in $lines) { (Remove-Ansi $l).Length | Should -BeLessOrEqual 5 }
    }

    It 'breaks a word that is longer than the effective width' {
        $lines = Invoke-AnsiLines { Format-AnsiText 'aaaaaaaaaa' -MaxWidth 4 }
        $lines.Count | Should -Be 3
        (Remove-Ansi $lines[0]) | Should -BeExactly 'aaaa'
        (Remove-Ansi $lines[2]) | Should -BeExactly 'aa'
    }

    It 'does not wrap content that fits' {
        $lines = Invoke-AnsiLines { Format-AnsiText 'short' -MaxWidth 40 }
        $lines.Count | Should -Be 1
    }

    It 'wraps at the effective width minus -Indent' {
        # MaxWidth 12 - Indent 4 => content wraps at 8
        $lines = Invoke-AnsiLines { Format-AnsiText 'alpha bravo charlie' -MaxWidth 12 -Indent 4 }
        foreach ($l in $lines) { (Remove-Ansi $l).TrimStart().Length | Should -BeLessOrEqual 8 }
    }

    It 'survives a width of 1' {
        $lines = Invoke-AnsiLines { Format-AnsiText 'ab' -MaxWidth 1 }
        $lines.Count | Should -Be 2
    }

    It 'preserves nested styles across a wrap' {
        # Both rows must re-emit bold and the enclosing foreground.
        $out = Invoke-Ansi { Format-AnsiText '[BrightYellow][bold]aaa bbb[/][/]' -MaxWidth 3 }
        Measure-Occurrence $out $PSStyle.Bold | Should -BeGreaterOrEqual 2
        Measure-Occurrence $out $PSStyle.Foreground.BrightYellow | Should -BeGreaterOrEqual 2
    }

    It 'keeps hard `n breaks independent of wrapping' {
        $lines = Invoke-AnsiLines { Format-AnsiText "aaa bbb`nccc" -MaxWidth 5 }
        $lines.Count | Should -Be 3
        (Remove-Ansi $lines[2]) | Should -BeExactly 'ccc'
    }
}

Describe 'Format-AnsiText — -Indent' {
    It 'does not indent the first row' {
        $lines = Invoke-AnsiLines { Format-AnsiText 'alpha bravo charlie' -MaxWidth 12 -Indent 4 }
        (Remove-Ansi $lines[0]) | Should -BeExactly 'alpha'
    }

    It 'indents continuation rows by -Indent columns' {
        $lines = Invoke-AnsiLines { Format-AnsiText 'alpha bravo charlie' -MaxWidth 12 -Indent 4 }
        $lines.Count | Should -BeGreaterThan 1
        for ($i = 1; $i -lt $lines.Count; $i++) {
            (Remove-Ansi $lines[$i]) | Should -Match '^ {4}\S'
        }
    }

    It 'adds no prefix when -Indent is 0' {
        $lines = Invoke-AnsiLines { Format-AnsiText 'alpha bravo charlie' -MaxWidth 12 }
        for ($i = 1; $i -lt $lines.Count; $i++) {
            (Remove-Ansi $lines[$i]) | Should -Match '^\S'
        }
    }

    It 'indents rows produced by a hard `n too' {
        $lines = Invoke-AnsiLines { Format-AnsiText "one`ntwo" -MaxWidth 20 -Indent 3 }
        (Remove-Ansi $lines[0]) | Should -BeExactly 'one'
        (Remove-Ansi $lines[1]) | Should -BeExactly '   two'
    }
}

Describe 'Format-AnsiText — anchoring' {
    BeforeAll { Set-AnsiTestColumn 8 }   # pretend the caller left the cursor at column 8
    AfterAll { Set-AnsiTestColumn 0 }

    It 'leaves the first row where the cursor already is' {
        $lines = Invoke-AnsiLines { Format-AnsiText 'alpha bravo charlie' -MaxWidth 12 }
        (Remove-Ansi $lines[0]) | Should -BeExactly 'alpha bravo'
    }

    It 'resumes continuation rows at the anchor column' {
        $lines = Invoke-AnsiLines { Format-AnsiText 'alpha bravo charlie' -MaxWidth 12 }
        $lines.Count | Should -BeGreaterThan 1
        (Remove-Ansi $lines[1]) | Should -BeExactly ((' ' * 8) + 'charlie')
    }

    It 'adds -Indent on top of the anchor column' {
        $lines = Invoke-AnsiLines { Format-AnsiText "one`ntwo" -MaxWidth 20 -Indent 3 }
        (Remove-Ansi $lines[1]) | Should -BeExactly ((' ' * 11) + 'two')
    }

    It 'derives the default width from the remaining buffer' {
        # Buffer 120, anchor 8 => 112 columns before the first wrap.
        $lines = Invoke-AnsiLines { Format-AnsiText (('a' * 60) + ' ' + ('b' * 60)) }
        $lines.Count | Should -Be 2
        (Remove-Ansi $lines[0]) | Should -BeExactly ('a' * 60)
    }
}

Describe 'Format-AnsiText — -MaxRows' {
    It 'caps at N rows and appends … to the last kept row' {
        $lines = Invoke-AnsiLines { Format-AnsiText 'aaa bbb ccc ddd eee' -MaxWidth 6 -MaxRows 2 }
        $lines.Count | Should -Be 2
        (Remove-Ansi $lines[-1]) | Should -Match ([regex]::Escape($script:Ell))
    }

    It 'caps at a single row' {
        $lines = Invoke-AnsiLines { Format-AnsiText 'aaa bbb ccc' -MaxWidth 5 -MaxRows 1 }
        $lines.Count | Should -Be 1
        (Remove-Ansi $lines[0]) | Should -Match ([regex]::Escape($script:Ell))
    }

    It 'does not append … when content already fits' {
        $out = Invoke-Ansi { Format-AnsiText 'short' -MaxWidth 40 -MaxRows 5 }
        Remove-Ansi $out | Should -Not -Match ([regex]::Escape($script:Ell))
    }

    It 'does not append … when the row count matches the cap exactly' {
        $lines = Invoke-AnsiLines { Format-AnsiText 'aaa bbb ccc ddd eee fff' -MaxWidth 10 -MaxRows 3 }
        $lines.Count | Should -Be 3
        (Remove-Ansi ($lines -join '')) | Should -Not -Match ([regex]::Escape($script:Ell))
    }

    It 'leaves output untouched when the cap exceeds the row count' {
        $lines = Invoke-AnsiLines { Format-AnsiText "one`ntwo" -MaxWidth 20 -MaxRows 9 }
        $lines.Count | Should -Be 2
        (Remove-Ansi $lines[1]) | Should -BeExactly 'two'
    }

    It 'forces Fold wrap so only the last kept row is ellipsised (even with -Overflow Ellipsis)' {
        $lines = Invoke-AnsiLines {
            Format-AnsiText 'aaa bbb ccc ddd eee fff ggg hhh' -MaxWidth 10 -Overflow Ellipsis -MaxRows 3
        }
        $lines.Count | Should -Be 3
        (Remove-Ansi $lines[0]) | Should -BeExactly 'aaa bbb'
        (Remove-Ansi $lines[1]) | Should -BeExactly 'ccc ddd'
        (Remove-Ansi $lines[2]) | Should -Match ([regex]::Escape($script:Ell))
    }

    It 'keeps the ellipsised row within the effective width' {
        $lines = Invoke-AnsiLines { Format-AnsiText 'aaaaaaaaaa bbbbbbbbbb cccccccccc' -MaxWidth 8 -MaxRows 2 }
        foreach ($l in $lines) { (Remove-Ansi $l).Length | Should -BeLessOrEqual 8 }
    }

    It 'preserves styling on the ellipsised row' {
        $out = Invoke-Ansi { Format-AnsiText '[bold]aaa bbb ccc ddd[/]' -MaxWidth 6 -MaxRows 2 }
        $out | Should -Match ([regex]::Escape($PSStyle.Bold))
        (Remove-Ansi $out) | Should -Match ([regex]::Escape($script:Ell))
    }
}

Describe 'Format-AnsiText — -Overflow' {
    It 'Fold produces multiple rows for content that does not fit' {
        $lines = Invoke-AnsiLines { Format-AnsiText 'aaa bbb ccc' -MaxWidth 5 -Overflow Fold }
        $lines.Count | Should -Be 3
    }

    It 'Crop keeps one row of exactly the effective width and does not add …' {
        $lines = Invoke-AnsiLines { Format-AnsiText 'aaaaaaaaaaaa' -MaxWidth 5 -Overflow Crop }
        $lines.Count | Should -Be 1
        (Remove-Ansi $lines[0]) | Should -BeExactly 'aaaaa'
    }

    It 'Ellipsis keeps one row and marks it with …' {
        $lines = Invoke-AnsiLines { Format-AnsiText 'aaaaaaaaaaaa' -MaxWidth 5 -Overflow Ellipsis }
        $lines.Count | Should -Be 1
        (Remove-Ansi $lines[0]) | Should -BeExactly ('aaaa' + $script:Ell)
    }

    It 'honours `n hard breaks in Crop mode' {
        $lines = Invoke-AnsiLines { Format-AnsiText "aaaaaaaaaa`nbbb" -MaxWidth 5 -Overflow Crop }
        $lines.Count | Should -Be 2
        (Remove-Ansi $lines[0]) | Should -BeExactly 'aaaaa'
        (Remove-Ansi $lines[1]) | Should -BeExactly 'bbb'
    }

    It 'honours `n hard breaks in Ellipsis mode' {
        $lines = Invoke-AnsiLines { Format-AnsiText "aaaaaaaaaa`nbbb" -MaxWidth 5 -Overflow Ellipsis }
        $lines.Count | Should -Be 2
        (Remove-Ansi $lines[0]) | Should -BeExactly ('aaaa' + $script:Ell)
    }

    It '<Mode> leaves content that fits untouched' -ForEach @(
        @{ Mode = 'Fold' }, @{ Mode = 'Crop' }, @{ Mode = 'Ellipsis' }
    ) {
        $mode = $Mode
        $out = Invoke-Ansi { Format-AnsiText 'abc' -MaxWidth 10 -Overflow $mode }
        Remove-Ansi $out | Should -BeExactly 'abc'
    }

    It 'keeps styling on a cropped row' {
        $out = Invoke-Ansi { Format-AnsiText '[bold]aaaaaaaaaaaa[/]' -MaxWidth 5 -Overflow Crop }
        $out | Should -Match ([regex]::Escape($PSStyle.Bold))
        Remove-Ansi $out | Should -BeExactly 'aaaaa'
    }
}

Describe 'Format-AnsiText — -Escape' {
    It 'treats markup as literal' {
        $out = Invoke-Ansi { Format-AnsiText '[bold]x[/]' -Escape }
        Remove-Ansi $out | Should -BeExactly '[bold]x[/]'
    }

    It 'treats markdown as literal' {
        $out = Invoke-Ansi { Format-AnsiText '**x** and `y`' -Escape }
        Remove-Ansi $out | Should -BeExactly '**x** and `y`'
    }

    It 'wins over -Markdown when both are supplied' {
        $out = Invoke-Ansi { Format-AnsiText '**x**' -Escape -Markdown }
        Remove-Ansi $out | Should -BeExactly '**x**'
    }

    It 'does not throw on markup that would otherwise be invalid' {
        { Invoke-Ansi { Format-AnsiText '[nosuch]x' -Escape } } | Should -Not -Throw
    }

    It 'keeps [[ and ]] literal' {
        $out = Invoke-Ansi { Format-AnsiText 'a [[b]] c' -Escape }
        Remove-Ansi $out | Should -BeExactly 'a [[b]] c'
    }

    It '-Color still applies over literal text' {
        $out = Invoke-Ansi { Format-AnsiText '[bold]x[/]' -Escape -Color BrightRed }
        $out | Should -Match ([regex]::Escape($PSStyle.Foreground.BrightRed))
        Remove-Ansi $out | Should -BeExactly '[bold]x[/]'
    }

    It 'still wraps and justifies' {
        $lines = Invoke-AnsiLines { Format-AnsiText '[bold]aaa bbb[/]' -Escape -MaxWidth 6 }
        $lines.Count | Should -BeGreaterThan 1
    }
}

Describe 'Format-AnsiText — | Out-AnsiHost -NoNewline' {
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

    It 'forwards -NoNewline to Write-Host only on the final row' {
        Format-AnsiText 'aaa bbb ccc' -MaxWidth 5 | Out-AnsiHost -NoNewline

        $script:hostCalls.Count | Should -BeGreaterThan 1
        $script:hostCalls[-1].NoNewline | Should -BeTrue
        for ($i = 0; $i -lt $script:hostCalls.Count - 1; $i++) {
            $script:hostCalls[$i].NoNewline | Should -BeFalse
        }
    }

    It 'applies to the only row of single-row output' {
        Format-AnsiText 'x' | Out-AnsiHost -NoNewline
        $script:hostCalls.Count | Should -Be 1
        $script:hostCalls[0].NoNewline | Should -BeTrue
    }

    It 'never sets NoNewline when the switch is absent' {
        Format-AnsiText 'aaa bbb ccc' -MaxWidth 5 | Out-AnsiHost
        $script:hostCalls.Count | Should -BeGreaterThan 1
        foreach ($c in $script:hostCalls) { $c.NoNewline | Should -BeFalse }
    }
}

Describe 'Format-AnsiText — no-colour output' {
    BeforeAll { Set-AnsiTestNoColor $true }
    AfterAll { Set-AnsiTestNoColor $false }

    It 'detects NO_COLOR in the environment' {
        $prev = $env:NO_COLOR
        try {
            $env:NO_COLOR = '1'
            (& $script:AnsiCore { Test-AnsiNoColor }) | Should -BeTrue
        } finally {
            if ($null -eq $prev) { Remove-Item Env:NO_COLOR -ErrorAction SilentlyContinue }
            else { $env:NO_COLOR = $prev }
        }
    }

    It 'strips ANSI escape sequences' {
        $out = Invoke-Ansi { Format-AnsiText '[bold BrightRed on Blue]x[/]' }
        $out | Should -Not -Match ([regex]::Escape([char]27))
        $out | Should -BeExactly 'x'
    }

    It 'strips -Color styling too' {
        $out = Invoke-Ansi { Format-AnsiText 'x' -Color BrightRed }
        $out | Should -BeExactly 'x'
    }

    It 'drops OSC 8 hyperlinks but keeps the link text' {
        $out = Invoke-Ansi { Format-AnsiText '[link=https://example.com]y[/]' }
        $out | Should -BeExactly 'y'
    }

    It 'renders markdown as plain text' {
        $out = Invoke-Ansi { Format-AnsiText '**x** :check:' -Markdown }
        $out | Should -BeExactly ('x ' + [char]0x2713)
    }

    It 'still validates markup' {
        { Format-AnsiText '[nosuch]x[/]' } | Should -Throw
    }

    It 'preserves justification' {
        $out = Invoke-Ansi { Format-AnsiText 'x' -MaxWidth 10 -Justify Center }
        $out | Should -BeExactly ((' ' * 4) + 'x')
    }

    It 'preserves wrapping and the row cap' {
        $lines = Invoke-AnsiLines { Format-AnsiText 'aaa bbb ccc ddd' -MaxWidth 6 -MaxRows 2 }
        $lines.Count | Should -Be 2
        $lines[-1] | Should -Match ([regex]::Escape($script:Ell))
    }

    It 'preserves indent' {
        $lines = Invoke-AnsiLines { Format-AnsiText "one`ntwo" -MaxWidth 20 -Indent 3 }
        $lines[1] | Should -BeExactly '   two'
    }
}

Describe 'Format-AnsiText — parameter validation' {
    It 'rejects an unknown -Justify value' {
        { Format-AnsiText 'x' -Justify Middle } | Should -Throw
    }

    It 'rejects an unknown -Overflow value' {
        { Format-AnsiText 'x' -Overflow Wrap } | Should -Throw
    }

    It 'exports only the formatter' {
        (Get-Module Format-AnsiText).ExportedFunctions.Keys | Should -Be 'Format-AnsiText'
    }
}
