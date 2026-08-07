#Requires -Version 7.2
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

# Format-AnsiJson.Tests.ps1
# Pester 5 tests for Format-AnsiJson. Rendered output is captured off the
# Information stream (Write-Host redirect 6>&1) and inspected as strings.
#
# Get-AnsiAnchor and Test-AnsiNoColor are replaced inside the Format-AnsiJson module
# scope (60-column buffer, colour forced on) so the suite is host-independent.
# Injection is used rather than Mock: Pester cannot mock a command a module
# merely imported from another module.

BeforeAll {
    $script:src = Join-Path (Split-Path -Parent $PSScriptRoot) 'src'
    Import-Module (Join-Path $script:src 'Format-AnsiJson.psm1') -Force -DisableNameChecking
    Import-Module (Join-Path $script:src 'Out-AnsiHost.psm1') -Force -DisableNameChecking
    Import-Module (Join-Path $script:src 'Out-AnsiString.psm1') -Force -DisableNameChecking
    $script:AnsiModule = Get-Module Format-AnsiJson

    $script:Ell = [string][char]0x2026     # …
    $script:Buffer = 60

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

    # Plain rows with ANSI stripped, for comparing layout. Assignment rather than
    # a pipe: piping the comma-wrapped result would flatten it into one string.
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

Describe 'Format-AnsiJson — JSON string input' {
    It 'pretty-prints an object' {
        $rows = Invoke-AnsiPlain { Format-AnsiJson '{"name":"ansi","count":3,"ok":true,"none":null}' }
        $rows | Should -Be @(
            '{'
            '  "name": "ansi",'
            '  "count": 3,'
            '  "ok": true,'
            '  "none": null'
            '}'
        )
    }

    It 'pretty-prints an array' {
        $rows = Invoke-AnsiPlain { Format-AnsiJson '[1,2,3]' }
        $rows | Should -Be @('[', '  1,', '  2,', '  3', ']')
    }

    It 'pretty-prints objects nested in an array' {
        $rows = Invoke-AnsiPlain { Format-AnsiJson '[{"id":1},{"id":2}]' }
        $rows | Should -Be @('[', '  {', '    "id": 1', '  },', '  {', '    "id": 2', '  }', ']')
    }

    It 'nests objects inside objects' {
        $rows = Invoke-AnsiPlain { Format-AnsiJson '{"a":{"b":{"c":1}}}' }
        $rows | Should -Be @('{', '  "a": {', '    "b": {', '      "c": 1', '    }', '  }', '}')
    }

    It 'renders an empty object' {
        $rows = Invoke-AnsiPlain { Format-AnsiJson '{}' }
        $rows | Should -Be @('{}')
    }

    It 'renders an empty array' {
        $rows = Invoke-AnsiPlain { Format-AnsiJson '[]' }
        $rows | Should -Be @('[]')
    }

    It 'renders an empty array nested in an array' {
        $rows = Invoke-AnsiPlain { Format-AnsiJson '[[]]' }
        $rows | Should -Be @('[', '  []', ']')
    }

    It 'renders empty members inline' {
        $rows = Invoke-AnsiPlain { Format-AnsiJson '{"list":[],"map":{}}' }
        $rows | Should -Be @('{', '  "list": [],', '  "map": {}', '}')
    }

    It 'renders a JSON scalar' -ForEach @(
        @{ Json = '42'; Expected = '42' }
        @{ Json = '-3.5'; Expected = '-3.5' }
        @{ Json = 'true'; Expected = 'true' }
        @{ Json = 'false'; Expected = 'false' }
        @{ Json = 'null'; Expected = 'null' }
        @{ Json = '"text"'; Expected = '"text"' }
    ) {
        $json = $Json
        $out = Invoke-Ansi { Format-AnsiJson $json }
        Remove-Ansi $out | Should -BeExactly $Expected
    }

    It 'treats a non-JSON string as a JSON string value' {
        $out = Invoke-Ansi { Format-AnsiJson 'not json at all' }
        Remove-Ansi $out | Should -BeExactly '"not json at all"'
    }
}

Describe 'Format-AnsiJson — object input' {
    It 'serialises a PSCustomObject in property order' {
        $data = [PSCustomObject]@{ name = 'ansi'; count = 3 }
        $rows = Invoke-AnsiPlain { Format-AnsiJson $data }
        $rows | Should -Be @('{', '  "name": "ansi",', '  "count": 3', '}')
    }

    It 'serialises an ordered dictionary in key order' {
        $data = [ordered]@{ z = 1; a = 2 }
        $rows = Invoke-AnsiPlain { Format-AnsiJson $data }
        $rows | Should -Be @('{', '  "z": 1,', '  "a": 2', '}')
    }

    It 'serialises a hashtable' {
        $rows = Invoke-AnsiPlain { Format-AnsiJson @{ only = 'one' } }
        $rows | Should -Be @('{', '  "only": "one"', '}')
    }

    It 'serialises nested collections' {
        $data = [PSCustomObject]@{ tags = @('a', 'b'); nested = [PSCustomObject]@{ x = 1 } }
        $rows = Invoke-AnsiPlain { Format-AnsiJson $data }
        $rows | Should -Be @(
            '{'
            '  "tags": ['
            '    "a",'
            '    "b"'
            '  ],'
            '  "nested": {'
            '    "x": 1'
            '  }'
            '}'
        )
    }

    It 'renders an empty collection' {
        $rows = Invoke-AnsiPlain { Format-AnsiJson @() }
        $rows | Should -Be @('[]')
    }

    It 'renders an empty hashtable' {
        $rows = Invoke-AnsiPlain { Format-AnsiJson @{} }
        $rows | Should -Be @('{}')
    }

    It 'renders $null as null' {
        $out = Invoke-Ansi { Format-AnsiJson $null }
        Remove-Ansi $out | Should -BeExactly 'null'
    }

    It 'renders numbers without quotes' {
        $data = [PSCustomObject]@{ int = 7; float = 3.5; neg = -2 }
        $rows = Invoke-AnsiPlain { Format-AnsiJson $data }
        $rows | Should -Be @('{', '  "int": 7,', '  "float": 3.5,', '  "neg": -2', '}')
    }

    It 'renders booleans without quotes' {
        $rows = Invoke-AnsiPlain { Format-AnsiJson ([PSCustomObject]@{ ok = $true; bad = $false }) }
        $rows | Should -Be @('{', '  "ok": true,', '  "bad": false', '}')
    }

    It 'escapes quotes, backslashes, and newlines in strings' {
        $data = [ordered]@{ q = 'he said "hi"'; bs = 'c\d'; nl = "a`nb" }
        $rows = Invoke-AnsiPlain { Format-AnsiJson $data }
        $rows | Should -Be @('{', '  "q": "he said \"hi\"",', '  "bs": "c\\d",', '  "nl": "a\nb"', '}')
    }

    It 'accepts real objects off the pipeline' {
        $data = Get-Item -LiteralPath $script:src | Select-Object Name
        $rows = Invoke-AnsiPlain { $data | Format-AnsiJson }
        $rows | Should -Be @('{', '  "Name": "src"', '}')
    }

    It 'wraps several pipeline items into one array' {
        $rows = Invoke-AnsiPlain { 1, 2 | Format-AnsiJson }
        $rows | Should -Be @('[', '  1,', '  2', ']')
    }
}

Describe 'Format-AnsiJson — -IndentSize' {
    It 'defaults to two spaces' {
        $rows = Invoke-AnsiPlain { Format-AnsiJson '{"a":{"b":1}}' }
        $rows[1] | Should -BeExactly '  "a": {'
        $rows[2] | Should -BeExactly '    "b": 1'
    }

    It 'honours a wider indent' {
        $rows = Invoke-AnsiPlain { Format-AnsiJson '{"a":{"b":1}}' -IndentSize 4 }
        $rows[1] | Should -BeExactly '    "a": {'
        $rows[2] | Should -BeExactly '        "b": 1'
    }

    It 'flattens to no indent at 0' {
        $rows = Invoke-AnsiPlain { Format-AnsiJson '{"a":{"b":1}}' -IndentSize 0 }
        $rows | Should -Be @('{', '"a": {', '"b": 1', '}', '}')
    }

    It 'rejects a negative indent' {
        { Format-AnsiJson '{}' -IndentSize -1 } | Should -Throw
    }
}

Describe 'Format-AnsiJson — -MaxDepth' {
    It 'collapses deeper objects to {…}' {
        $rows = Invoke-AnsiPlain { Format-AnsiJson '{"a":{"b":{"c":1}}}' -MaxDepth 1 }
        # Parentheses matter: `,` binds tighter than `+`, so an unparenthesised
        # concatenation would splice into extra array elements.
        $rows | Should -Be @('{', ('  "a": {' + $script:Ell + '}'), '}')
    }

    It 'collapses deeper arrays to […]' {
        $rows = Invoke-AnsiPlain { Format-AnsiJson '{"d":[1,2]}' -MaxDepth 1 }
        $rows | Should -Be @('{', ('  "d": [' + $script:Ell + ']'), '}')
    }

    It 'expands one more level at 2' {
        $rows = Invoke-AnsiPlain { Format-AnsiJson '{"a":{"b":{"c":1}}}' -MaxDepth 2 }
        $rows | Should -Be @('{', '  "a": {', ('    "b": {' + $script:Ell + '}'), '  }', '}')
    }

    It 'leaves empty containers alone rather than collapsing them' {
        $rows = Invoke-AnsiPlain { Format-AnsiJson '{"a":{},"b":[]}' -MaxDepth 1 }
        $rows | Should -Be @('{', '  "a": {},', '  "b": []', '}')
    }

    It 'renders everything at 0 (the default)' {
        $rows = Invoke-AnsiPlain { Format-AnsiJson '{"a":{"b":{"c":1}}}' }
        $rows.Count | Should -Be 7
    }
}

Describe 'Format-AnsiJson — -Depth' {
    It 'bounds serialisation of deep objects' {
        $deep = @{ a = @{ b = @{ c = @{ d = 1 } } } }
        $rows = Invoke-AnsiPlain { Format-AnsiJson $deep -Depth 2 -WarningAction SilentlyContinue }
        ($rows -join "`n") | Should -Match 'Hashtable'
    }

    It 'renders the whole tree at the default depth' {
        $deep = @{ a = @{ b = @{ c = @{ d = 1 } } } }
        $rows = Invoke-AnsiPlain { Format-AnsiJson $deep }
        ($rows -join "`n") | Should -Match '"d": 1'
    }

    It 'parses input deeper than -Depth without throwing' {
        $json = '{"a":{"b":{"c":{"d":{"e":1}}}}}'
        { Invoke-Ansi { Format-AnsiJson $json -Depth 2 } } | Should -Not -Throw
    }

    It 'rejects a depth below 1' {
        { Format-AnsiJson '{}' -Depth 0 } | Should -Throw
    }
}

Describe 'Format-AnsiJson — colours' {
    It 'colours keys' {
        $out = Invoke-Ansi { Format-AnsiJson '{"a":1}' }
        $out | Should -Match ([regex]::Escape($PSStyle.Foreground.BrightBlue + '"a"'))
    }

    It 'colours string values' {
        $out = Invoke-Ansi { Format-AnsiJson '{"a":"x"}' }
        $out | Should -Match ([regex]::Escape($PSStyle.Foreground.BrightGreen + '"x"'))
    }

    It 'colours numbers' {
        $out = Invoke-Ansi { Format-AnsiJson '{"a":1}' }
        $out | Should -Match ([regex]::Escape($PSStyle.Foreground.BrightCyan + '1'))
    }

    It 'colours booleans' {
        $out = Invoke-Ansi { Format-AnsiJson '{"a":true}' }
        $out | Should -Match ([regex]::Escape($PSStyle.Foreground.BrightMagenta + 'true'))
    }

    It 'colours null' {
        $out = Invoke-Ansi { Format-AnsiJson '{"a":null}' }
        $out | Should -Match ([regex]::Escape($PSStyle.Foreground.BrightBlack + 'null'))
    }

    It 'honours a custom <Parameter>' -ForEach @(
        @{ Parameter = 'KeyColor'; Json = '{"a":1}'; Token = '"a"' }
        @{ Parameter = 'StringColor'; Json = '{"a":"x"}'; Token = '"x"' }
        @{ Parameter = 'NumberColor'; Json = '{"a":1}'; Token = '1' }
        @{ Parameter = 'BooleanColor'; Json = '{"a":true}'; Token = 'true' }
        @{ Parameter = 'NullColor'; Json = '{"a":null}'; Token = 'null' }
    ) {
        $json = $Json
        $splat = @{ $Parameter = 'BrightRed' }
        $out = Invoke-Ansi { Format-AnsiJson $json @splat }
        $out | Should -Match ([regex]::Escape($PSStyle.Foreground.BrightRed + $Token))
    }

    It 'leaves punctuation unstyled by default' {
        $out = Invoke-Ansi { Format-AnsiJson '{}' }
        $out | Should -BeExactly '{}'
    }

    It 'colours punctuation with -PunctuationColor' {
        $out = Invoke-Ansi { Format-AnsiJson '{"a":1}' -PunctuationColor DarkGray }
        $out | Should -Match ([regex]::Escape($PSStyle.Foreground.BrightBlack + '{'))
        $out | Should -Match ([regex]::Escape($PSStyle.Foreground.BrightBlack + ': '))
    }

    It 'colours the trailing comma with the punctuation colour' {
        $out = Invoke-Ansi { Format-AnsiJson '{"a":1,"b":2}' -PunctuationColor DarkGray }
        Measure-Occurrence $out ($PSStyle.Foreground.BrightBlack + ',') | Should -Be 1
    }

    It 'throws on an unknown colour' {
        { Format-AnsiJson '{}' -KeyColor Nope } | Should -Throw
    }
}

Describe 'Format-AnsiJson — width handling' {
    It 'ellipsises a row wider than the width instead of wrapping' {
        $json = '{"k":"' + ('x' * 80) + '"}'
        $rows = Invoke-AnsiPlain { Format-AnsiJson $json -MaxWidth 30 }
        $rows.Count | Should -Be 3
        $rows[1].Length | Should -Be 30
        $rows[1] | Should -Match ([regex]::Escape($script:Ell))
    }

    It 'leaves rows that fit untouched' {
        $rows = Invoke-AnsiPlain { Format-AnsiJson '{"a":1}' -MaxWidth 30 }
        $rows | Should -Be @('{', '  "a": 1', '}')
    }

    It 'keeps every row within the width' {
        $json = '{"a":{"b":"' + ('y' * 50) + '"}}'
        $rows = Invoke-AnsiPlain { Format-AnsiJson $json -MaxWidth 20 }
        foreach ($r in $rows) { $r.Length | Should -BeLessOrEqual 20 }
    }
}

Describe 'Format-AnsiJson — anchoring' {
    BeforeAll { Set-AnsiTestColumn 4 }
    AfterAll { Set-AnsiTestColumn 0 }

    It 'leaves the first row where the cursor already is' {
        $rows = Invoke-AnsiPlain { Format-AnsiJson '{"a":1}' }
        $rows[0] | Should -BeExactly '{'
    }

    It 'resumes later rows at the anchor column' {
        $rows = Invoke-AnsiPlain { Format-AnsiJson '{"a":1}' }
        $rows[1] | Should -BeExactly ((' ' * 4) + '  "a": 1')
        $rows[2] | Should -BeExactly ((' ' * 4) + '}')
    }

    It 'sizes rows to the remaining buffer' {
        $json = '{"k":"' + ('x' * 200) + '"}'
        $rows = Invoke-AnsiPlain { Format-AnsiJson $json }
        $rows[1].Length | Should -BeLessOrEqual ($script:Buffer - 4 + 4)
    }
}

Describe 'Format-AnsiJson — | Out-AnsiHost -NoNewline' {
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
        Format-AnsiJson '{"a":1}' | Out-AnsiHost -NoNewline
        $script:hostCalls.Count | Should -Be 3
        $script:hostCalls[-1].NoNewline | Should -BeTrue
        for ($i = 0; $i -lt $script:hostCalls.Count - 1; $i++) {
            $script:hostCalls[$i].NoNewline | Should -BeFalse
        }
    }

    It 'applies to the only row of a scalar' {
        Format-AnsiJson '42' | Out-AnsiHost -NoNewline
        $script:hostCalls.Count | Should -Be 1
        $script:hostCalls[0].NoNewline | Should -BeTrue
    }

    It 'never sets NoNewline when the switch is absent' {
        Format-AnsiJson '{"a":1}'
        foreach ($c in $script:hostCalls) { $c.NoNewline | Should -BeFalse }
    }
}

Describe 'Format-AnsiJson — no-colour output' {
    BeforeAll { Set-AnsiTestNoColor $true }
    AfterAll { Set-AnsiTestNoColor $false }

    It 'strips ANSI escape sequences' {
        $out = Invoke-Ansi { Format-AnsiJson '{"a":"x","b":1,"c":true,"d":null}' -PunctuationColor DarkGray }
        $out | Should -Not -Match ([regex]::Escape([char]27))
    }

    It 'preserves indentation and structure' {
        $rows = Invoke-AnsiLines { Format-AnsiJson '{"a":{"b":1}}' }
        $rows | Should -Be @('{', '  "a": {', '    "b": 1', '  }', '}')
    }

    It 'preserves row truncation' {
        $json = '{"k":"' + ('x' * 80) + '"}'
        $rows = Invoke-AnsiLines { Format-AnsiJson $json -MaxWidth 24 }
        $rows[1].Length | Should -Be 24
        $rows[1] | Should -Match ([regex]::Escape($script:Ell))
    }
}

Describe 'Format-AnsiJson — module surface' {
    It 'exports only the formatter' {
        (Get-Module Format-AnsiJson).ExportedFunctions.Keys | Should -Be 'Format-AnsiJson'
    }
}
