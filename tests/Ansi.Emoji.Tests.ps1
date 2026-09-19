#Requires -Version 7.2
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

# Ansi.Emoji.Tests.ps1 — Pester 5 tests for Get-AnsiEmojiTable and Get-AnsiEmoji.

BeforeAll {
    $script:src    = Join-Path (Split-Path -Parent $PSScriptRoot) 'src'
    $script:Module = Import-Module (Join-Path $script:src 'Ansi.Emoji.psm1') -Force -DisableNameChecking -PassThru
}

Describe 'Get-AnsiEmojiTable' {
    It 'returns a dictionary' {
        $table = & $script:Module { Get-AnsiEmojiTable }
        ($table -is [System.Collections.Generic.Dictionary[string, string]]) | Should -BeTrue
    }

    It 'contains more than 1400 entries' {
        $table = & $script:Module { Get-AnsiEmojiTable }
        $table.Count | Should -BeGreaterThan 1400
    }

    It 'returns the same object on repeated calls (cached)' {
        $a = & $script:Module { Get-AnsiEmojiTable }
        $b = & $script:Module { Get-AnsiEmojiTable }
        [object]::ReferenceEquals($a, $b) | Should -BeTrue
    }

    It 'uses a case-insensitive comparer' {
        $table = & $script:Module { Get-AnsiEmojiTable }
        $table.ContainsKey('ROCKET')   | Should -BeTrue
        $table.ContainsKey('rocket')   | Should -BeTrue
        $table.ContainsKey('Rocket')   | Should -BeTrue
    }

    It 'maps a single-codepoint name to the correct glyph' {
        $table    = & $script:Module { Get-AnsiEmojiTable }
        $expected = [char]::ConvertFromUtf32(0x1F600)
        $table['grinning_face'] | Should -BeExactly $expected
    }

    It 'maps a multi-codepoint name (with variation selector) correctly' {
        # warning is U+26A0 U+FE0F
        $table    = & $script:Module { Get-AnsiEmojiTable }
        $expected = [string][char]0x26A0 + [char]0xFE0F
        $table['warning'] | Should -BeExactly $expected
    }
}

Describe 'Get-AnsiEmoji' {
    It 'returns the glyph for a known name' {
        $glyph    = & $script:Module { Get-AnsiEmoji 'rocket' }
        $expected = [char]::ConvertFromUtf32(0x1F680)
        $glyph | Should -BeExactly $expected
    }

    It 'is case-insensitive' {
        $lower = & $script:Module { Get-AnsiEmoji 'rocket' }
        $upper = & $script:Module { Get-AnsiEmoji 'ROCKET' }
        $mixed = & $script:Module { Get-AnsiEmoji 'Rocket' }
        $lower | Should -BeExactly $upper
        $lower | Should -BeExactly $mixed
    }

    It 'returns $null for an unknown name' {
        $result = & $script:Module { Get-AnsiEmoji 'not_a_real_emoji_xyz' }
        $result | Should -BeNullOrEmpty
    }

    It 'returns $null for an empty string' {
        $result = & $script:Module { Get-AnsiEmoji '' }
        $result | Should -BeNullOrEmpty
    }

    It 'handles a name with digits' {
        $glyph    = & $script:Module { Get-AnsiEmoji '1st_place_medal' }
        $expected = [char]::ConvertFromUtf32(0x1F947)
        $glyph | Should -BeExactly $expected
    }

    It 'exports only Get-AnsiEmojiTable and Get-AnsiEmoji' {
        $exported = $script:Module.ExportedFunctions.Keys | Sort-Object
        $exported | Should -Be @('Get-AnsiEmoji', 'Get-AnsiEmojiTable')
    }
}
