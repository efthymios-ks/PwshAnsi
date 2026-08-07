#Requires -Version 7.2
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

# Format-AnsiTree.Tests.ps1
# Pester 5 tests for Format-AnsiTree. Rendered output is captured off the
# Information stream (Write-Host redirect 6>&1) and inspected as strings.
#
# Get-AnsiAnchor and Test-AnsiNoColor are replaced inside the Format-AnsiTree module
# scope (50-column buffer, colour forced on) so the suite is host-independent.
# Injection is used rather than Mock: Pester cannot mock a command a module
# merely imported from another module.

BeforeAll {
    $script:src = Join-Path (Split-Path -Parent $PSScriptRoot) 'src'
    Import-Module (Join-Path $script:src 'Format-AnsiTree.psm1') -Force -DisableNameChecking
    Import-Module (Join-Path $script:src 'Out-AnsiHost.psm1') -Force -DisableNameChecking
    Import-Module (Join-Path $script:src 'Out-AnsiString.psm1') -Force -DisableNameChecking
    $script:AnsiModule = Get-Module Format-AnsiTree

    $script:Ell = [string][char]0x2026
    $script:Buffer = 50

    # Line guide pieces, spelled out so expectations stay readable.
    $script:Tee = [string][char]0x251C + [string][char]0x2500 + [string][char]0x2500 + ' '   # ├──
    $script:Last = [string][char]0x2514 + [string][char]0x2500 + [string][char]0x2500 + ' '  # └──
    $script:Bar = [string][char]0x2502 + '   '                                               # │
    $script:Gap = '    '

    & $script:AnsiModule {
        $script:AnsiTestColumn = 0
        $script:AnsiTestNoColor = $false

        Set-Item function:script:Get-AnsiAnchor -Value {
            param([int]$MaxWidth = 0)
            [PSCustomObject]@{
                Column      = $script:AnsiTestColumn
                BufferWidth = 50
                Width       = $(if ($MaxWidth -gt 0) { $MaxWidth } else { 50 - $script:AnsiTestColumn })
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

    $script:Tree = @{
        Value    = 'root'
        Children = @(
            @{ Value = 'branch-a'; Children = @(
                    @{ Value = 'leaf-a1' }
                    @{ Value = 'leaf-a2'; Children = @(@{ Value = 'deep-a2x' }) }
                )
            }
            @{ Value = 'branch-b' }
            @{ Value = 'branch-c'; Children = @(@{ Value = 'leaf-c1' }) }
        )
    }
}

Describe 'Format-AnsiTree — structure' {
    It 'renders the root without a guide and children beneath it' {
        $rows = Invoke-AnsiPlain { Format-AnsiTree $script:Tree }
        $rows | Should -Be @(
            'root'
            ($script:Tee + 'branch-a')
            ($script:Bar + $script:Tee + 'leaf-a1')
            ($script:Bar + $script:Last + 'leaf-a2')
            ($script:Bar + $script:Gap + $script:Last + 'deep-a2x')
            ($script:Tee + 'branch-b')
            ($script:Last + 'branch-c')
            ($script:Gap + $script:Last + 'leaf-c1')
        )
    }

    It 'marks the last child with the corner connector' {
        $rows = Invoke-AnsiPlain { Format-AnsiTree $script:Tree }
        $rows[-2] | Should -BeExactly ($script:Last + 'branch-c')
    }

    It 'continues the bar past a node that still has siblings' {
        $rows = Invoke-AnsiPlain { Format-AnsiTree $script:Tree }
        $rows[2] | Should -BeExactly ($script:Bar + $script:Tee + 'leaf-a1')
    }

    It 'drops the bar under the last child' {
        $rows = Invoke-AnsiPlain { Format-AnsiTree $script:Tree }
        $rows[-1] | Should -BeExactly ($script:Gap + $script:Last + 'leaf-c1')
    }

    It 'renders a childless node as a single row' {
        $rows = Invoke-AnsiPlain { Format-AnsiTree @{ Value = 'solo' } }
        $rows | Should -Be @('solo')
    }

    It 'ignores an empty Children collection' {
        $rows = Invoke-AnsiPlain { Format-AnsiTree @{ Value = 'root'; Children = @() } }
        $rows | Should -Be @('root')
    }

    It 'emits one row per node' {
        $rows = Invoke-AnsiPlain { Format-AnsiTree $script:Tree }
        $rows.Count | Should -Be 8
    }
}

Describe 'Format-AnsiTree — -Guide' {
    It 'draws <Guide> guides' -ForEach @(
        @{ Guide = 'Line'; Tee = [string][char]0x251C; Bar = [string][char]0x2502; Corner = [string][char]0x2514 }
        @{ Guide = 'DoubleLine'; Tee = [string][char]0x2560; Bar = [string][char]0x2551; Corner = [string][char]0x255A }
        @{ Guide = 'BoldLine'; Tee = [string][char]0x2523; Bar = [string][char]0x2503; Corner = [string][char]0x2517 }
        @{ Guide = 'Ascii'; Tee = '|'; Bar = '|'; Corner = '`' }
    ) {
        $g = $Guide
        $rows = Invoke-AnsiPlain { Format-AnsiTree $script:Tree -Guide $g }
        # StartsWith, not -BeLike: the Ascii corner is a backtick, which -BeLike
        # would read as an escape character.
        $rows[1].StartsWith($Tee) | Should -BeTrue
        $rows[2].StartsWith($Bar) | Should -BeTrue
        $rows[-2].StartsWith($Corner) | Should -BeTrue
    }

    It 'keeps every guide four columns wide' -ForEach @(
        @{ Guide = 'Line' }, @{ Guide = 'DoubleLine' }, @{ Guide = 'BoldLine' }, @{ Guide = 'Ascii' }
    ) {
        $g = $Guide
        $rows = Invoke-AnsiPlain { Format-AnsiTree $script:Tree -Guide $g }
        $rows[1].Length | Should -Be (4 + 'branch-a'.Length)
        $rows[4].Length | Should -Be (12 + 'deep-a2x'.Length)
    }

    It 'defaults to Line' {
        $rows = Invoke-AnsiPlain { Format-AnsiTree $script:Tree }
        $rows[1] | Should -BeExactly ($script:Tee + 'branch-a')
    }

    It 'is case-insensitive' {
        { Invoke-Ansi { Format-AnsiTree $script:Tree -Guide 'ascii' } } | Should -Not -Throw
    }

    It 'rejects an unknown guide' {
        { Format-AnsiTree $script:Tree -Guide Wiggly } | Should -Throw
    }
}

Describe 'Format-AnsiTree — input shapes' {
    It 'accepts a nested hashtable' {
        $rows = Invoke-AnsiPlain { Format-AnsiTree @{ Value = 'h'; Children = @(@{ Value = 'k' }) } }
        $rows | Should -Be @('h', ($script:Last + 'k'))
    }

    It 'accepts nested PSCustomObjects' {
        $data = [PSCustomObject]@{ Value = 'obj'; Children = @([PSCustomObject]@{ Value = 'kid' }) }
        $rows = Invoke-AnsiPlain { Format-AnsiTree $data }
        $rows | Should -Be @('obj', ($script:Last + 'kid'))
    }

    It 'accepts an ordered dictionary' {
        $data = [ordered]@{ Value = 'ord'; Children = @([ordered]@{ Value = 'kid' }) }
        $rows = Invoke-AnsiPlain { Format-AnsiTree $data }
        $rows | Should -Be @('ord', ($script:Last + 'kid'))
    }

    It 'accepts Name/Items as label and children' {
        $rows = Invoke-AnsiPlain { Format-AnsiTree @{ Name = 'named'; Items = @(@{ Name = 'sub' }) } }
        $rows | Should -Be @('named', ($script:Last + 'sub'))
    }

    It 'accepts Label/Nodes as label and children' {
        $rows = Invoke-AnsiPlain { Format-AnsiTree @{ Label = 'lab'; Nodes = @(@{ Label = 'n' }) } }
        $rows | Should -Be @('lab', ($script:Last + 'n'))
    }

    It 'honours -Property and -ChildProperty' {
        $data = @{ label = 'L'; kids = @(@{ label = 'K'; kids = @(@{ label = 'M' }) }) }
        $rows = Invoke-AnsiPlain { Format-AnsiTree $data -Property label -ChildProperty kids }
        $rows | Should -Be @('L', ($script:Last + 'K'), ($script:Gap + $script:Last + 'M'))
    }

    It 'renders a bare string as a single leaf' {
        $rows = Invoke-AnsiPlain { Format-AnsiTree 'just-a-string' }
        $rows | Should -Be @('just-a-string')
    }

    It 'renders a scalar as a single leaf' {
        $rows = Invoke-AnsiPlain { Format-AnsiTree 42 }
        $rows | Should -Be @('42')
    }

    It 'treats a single non-collection child as one node' {
        $rows = Invoke-AnsiPlain { Format-AnsiTree @{ Value = 'root'; Children = 'only' } }
        $rows | Should -Be @('root', ($script:Last + 'only'))
    }

    It 'renders a collection of roots as a forest' {
        $data = @(@{ Value = 'r1'; Children = @(@{ Value = 'c1' }) }, @{ Value = 'r2' })
        $rows = Invoke-AnsiPlain { Format-AnsiTree $data }
        $rows | Should -Be @('r1', ($script:Last + 'c1'), 'r2')
    }

    It 'renders one tree per pipeline item' {
        $rows = Invoke-AnsiPlain { @{ Value = 'p1' }, @{ Value = 'p2' } | Format-AnsiTree }
        $rows | Should -Be @('p1', 'p2')
    }

    It 'produces no output for $null' {
        $rows = Invoke-AnsiPlain { Format-AnsiTree $null }
        $rows.Count | Should -Be 0
    }

    It 'handles deep nesting' {
        $data = @{ Value = '1'; Children = @(@{ Value = '2'; Children = @(@{ Value = '3'; Children = @(@{ Value = '4' }) }) }) }
        $rows = Invoke-AnsiPlain { Format-AnsiTree $data }
        $rows.Count | Should -Be 4
        $rows[3] | Should -BeExactly ($script:Gap + $script:Gap + $script:Last + '4')
    }
}

Describe 'Format-AnsiTree — -MaxDepth' {
    It 'collapses everything below the first level' {
        $rows = Invoke-AnsiPlain { Format-AnsiTree $script:Tree -MaxDepth 1 }
        $rows | Should -Be @(
            'root'
            ($script:Tee + 'branch-a')
            ($script:Bar + $script:Last + $script:Ell)
            ($script:Tee + 'branch-b')
            ($script:Last + 'branch-c')
            ($script:Gap + $script:Last + $script:Ell)
        )
    }

    It 'expands one more level at 2' {
        $rows = Invoke-AnsiPlain { Format-AnsiTree $script:Tree -MaxDepth 2 }
        $rows[2] | Should -BeExactly ($script:Bar + $script:Tee + 'leaf-a1')
        $rows[4] | Should -BeExactly ($script:Bar + $script:Gap + $script:Last + $script:Ell)
    }

    It 'renders the whole tree at 0 (the default)' {
        $rows = Invoke-AnsiPlain { Format-AnsiTree $script:Tree -MaxDepth 0 }
        $rows.Count | Should -Be 8
    }

    It 'leaves childless nodes alone' {
        $rows = Invoke-AnsiPlain { Format-AnsiTree @{ Value = 'root'; Children = @(@{ Value = 'leaf' }) } -MaxDepth 1 }
        $rows | Should -Be @('root', ($script:Last + 'leaf'))
    }

    It 'rejects a negative depth' {
        { Format-AnsiTree $script:Tree -MaxDepth -1 } | Should -Throw
    }
}

Describe 'Format-AnsiTree — colours' {
    It 'colours guides with -Color' {
        $out = Invoke-Ansi { Format-AnsiTree $script:Tree -Color DarkGray }
        $out | Should -Match ([regex]::Escape($PSStyle.Foreground.BrightBlack + $script:Tee))
    }

    It 'colours labels with -LabelColor' {
        $out = Invoke-Ansi { Format-AnsiTree $script:Tree -LabelColor BrightWhite }
        $out | Should -Match ([regex]::Escape($PSStyle.Foreground.BrightWhite + 'root'))
    }

    It 'colours guides and labels independently' {
        $out = Invoke-Ansi { Format-AnsiTree $script:Tree -Color DarkGray -LabelColor BrightWhite }
        $out | Should -Match ([regex]::Escape($PSStyle.Foreground.BrightBlack))
        $out | Should -Match ([regex]::Escape($PSStyle.Foreground.BrightWhite))
    }

    It 'aliases -GuideColor as -Color' {
        $out = Invoke-Ansi { Format-AnsiTree $script:Tree -GuideColor BrightBlue }
        $out | Should -Match ([regex]::Escape($PSStyle.Foreground.BrightBlue))
    }

    It 'renders unstyled when no colour is given' {
        $out = Invoke-Ansi { Format-AnsiTree @{ Value = 'root' } }
        $out | Should -BeExactly 'root'
    }

    It 'lets a label set its own colour via markup' {
        $data = @{ Value = 'root'; Children = @(@{ Value = '[BrightGreen]green[/]' }) }
        $out = Invoke-Ansi { Format-AnsiTree $data -LabelColor DarkGray }
        $out | Should -Match ([regex]::Escape($PSStyle.Foreground.BrightGreen + 'green'))
    }

    It 'colours the collapsed … with the label colour' {
        $out = Invoke-Ansi { Format-AnsiTree $script:Tree -MaxDepth 1 -LabelColor BrightWhite }
        $out | Should -Match ([regex]::Escape($PSStyle.Foreground.BrightWhite + $script:Ell))
    }

    It 'throws on an unknown guide colour' {
        { Format-AnsiTree $script:Tree -Color Nope } | Should -Throw
    }

    It 'throws on an unknown label colour' {
        { Format-AnsiTree $script:Tree -LabelColor Nope } | Should -Throw
    }
}

Describe 'Format-AnsiTree — labels' {
    It 'parses markup in labels' {
        $out = Invoke-Ansi { Format-AnsiTree @{ Value = '[bold]root[/]' } }
        $out | Should -Match ([regex]::Escape($PSStyle.Bold))
        Remove-Ansi $out | Should -BeExactly 'root'
    }

    It 'renders markdown sugar with -Markdown' {
        $out = Invoke-Ansi { Format-AnsiTree @{ Value = '**root**' } -Markdown }
        $out | Should -Match ([regex]::Escape($PSStyle.Bold))
        Remove-Ansi $out | Should -BeExactly 'root'
    }

    It 'replaces emoji tokens with -Markdown' {
        $out = Invoke-Ansi { Format-AnsiTree @{ Value = ':check: ok' } -Markdown }
        Remove-Ansi $out | Should -BeExactly ([string][char]0x2713 + ' ok')
    }

    It 'treats labels as literal with -Escape' {
        $out = Invoke-Ansi { Format-AnsiTree @{ Value = '[bold]literal[/]' } -Escape }
        Remove-Ansi $out | Should -BeExactly '[bold]literal[/]'
    }

    It '-Escape wins over -Markdown' {
        $out = Invoke-Ansi { Format-AnsiTree @{ Value = '**x**' } -Escape -Markdown }
        Remove-Ansi $out | Should -BeExactly '**x**'
    }

    It 'throws on invalid markup in a label' {
        { Format-AnsiTree @{ Value = '[nosuch]x[/]' } } | Should -Throw
    }

    It 'does not throw on invalid markup under -Escape' {
        { Invoke-Ansi { Format-AnsiTree @{ Value = '[nosuch]x' } -Escape } } | Should -Not -Throw
    }

    It 'renders a hyperlink in a label' {
        $out = Invoke-Ansi { Format-AnsiTree @{ Value = '[link=https://example.com]y[/]' } }
        $out | Should -Match ([regex]::Escape('https://example.com'))
    }
}

Describe 'Format-AnsiTree — label wrapping' {
    It 'wraps a long label under the label column, not the guide' {
        $data = @{ Value = 'root'; Children = @(@{ Value = 'a label that is definitely longer than the width allows here' }) }
        $rows = Invoke-AnsiPlain { Format-AnsiTree $data -MaxWidth 30 }
        $rows[1] | Should -BeExactly ($script:Last + 'a label that is')
        for ($i = 2; $i -lt $rows.Count; $i++) {
            $rows[$i] | Should -Match '^ {4}\S'
        }
    }

    It 'keeps ancestor guides on wrapped rows' {
        $data = @{ Value = 'root'; Children = @(
                @{ Value = 'mid'; Children = @(@{ Value = 'deep label that needs to wrap across rows' }) }
                @{ Value = 'after' }
            )
        }
        $rows = Invoke-AnsiPlain { Format-AnsiTree $data -MaxWidth 28 }
        $rows[2] | Should -BeExactly ($script:Bar + $script:Last + 'deep label that')
        $rows[3] | Should -BeExactly ($script:Bar + $script:Gap + 'needs to wrap')
        $rows[-1] | Should -BeExactly ($script:Last + 'after')
    }

    It 'keeps every row within the width' {
        $data = @{ Value = 'root'; Children = @(@{ Value = ('x' * 80) }) }
        $rows = Invoke-AnsiPlain { Format-AnsiTree $data -MaxWidth 20 }
        foreach ($r in $rows) { $r.Length | Should -BeLessOrEqual 20 }
    }

    It 'does not wrap labels that fit' {
        $rows = Invoke-AnsiPlain { Format-AnsiTree $script:Tree -MaxWidth 40 }
        $rows.Count | Should -Be 8
    }

    It 'preserves label styling across a wrap' {
        $data = @{ Value = 'root'; Children = @(@{ Value = '[bold]' + ('word ' * 12) + '[/]' }) }
        $out = Invoke-Ansi { Format-AnsiTree $data -MaxWidth 24 }
        Measure-Occurrence $out $PSStyle.Bold | Should -BeGreaterOrEqual 2
    }
}

Describe 'Format-AnsiTree — nested renderings' {
    It 'uses a rendering as a node label, row for row' {
        Import-Module (Join-Path $script:src 'Format-AnsiGrid.psm1') -Force -DisableNameChecking
        & (Get-Module Format-AnsiGrid) {
            Set-Item function:script:Get-AnsiAnchor -Value {
                param([int]$MaxWidth = 0)
                [PSCustomObject]@{ Column = 0; BufferWidth = 50; Width = $(if ($MaxWidth -gt 0) { $MaxWidth } else { 50 }) }
            }
            Set-Item function:script:Test-AnsiNoColor -Value { $false }
        }

        $grid = Format-AnsiGrid @(, @('k', 'v'), @('kk', 'vv')) -MaxWidth 20
        $rows = Invoke-AnsiPlain { Format-AnsiTree @{ Value = 'root'; Children = @(@{ Value = $grid }) } }

        $rows.Count | Should -Be 3
        $rows[1] | Should -BeExactly ($script:Last + 'k   v')
        $rows[2] | Should -BeExactly ($script:Gap + 'kk  vv')
    }
}

Describe 'Format-AnsiTree — anchoring' {
    BeforeAll { Set-AnsiTestColumn 4 }
    AfterAll { Set-AnsiTestColumn 0 }

    It 'leaves the first row where the cursor already is' {
        $rows = Invoke-AnsiPlain { Format-AnsiTree $script:Tree }
        $rows[0] | Should -BeExactly 'root'
    }

    It 'resumes later rows at the anchor column' {
        $rows = Invoke-AnsiPlain { Format-AnsiTree $script:Tree }
        $rows[1] | Should -BeExactly ((' ' * 4) + $script:Tee + 'branch-a')
    }

    It 'sizes rows to the remaining buffer' {
        $data = @{ Value = 'root'; Children = @(@{ Value = ('y' * 200) }) }
        $rows = Invoke-AnsiPlain { Format-AnsiTree $data }
        $rows[1].Length | Should -BeLessOrEqual $script:Buffer
    }
}

Describe 'Format-AnsiTree — | Out-AnsiHost -NoNewline' {
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
        Format-AnsiTree $script:Tree | Out-AnsiHost -NoNewline
        $script:hostCalls.Count | Should -Be 8
        $script:hostCalls[-1].NoNewline | Should -BeTrue
        for ($i = 0; $i -lt $script:hostCalls.Count - 1; $i++) {
            $script:hostCalls[$i].NoNewline | Should -BeFalse
        }
    }

    It 'applies to the only row of a single leaf' {
        Format-AnsiTree 'solo' | Out-AnsiHost -NoNewline
        $script:hostCalls.Count | Should -Be 1
        $script:hostCalls[0].NoNewline | Should -BeTrue
    }

    It 'never sets NoNewline when the switch is absent' {
        Format-AnsiTree $script:Tree
        foreach ($c in $script:hostCalls) { $c.NoNewline | Should -BeFalse }
    }
}

Describe 'Format-AnsiTree — no-colour output' {
    BeforeAll { Set-AnsiTestNoColor $true }
    AfterAll { Set-AnsiTestNoColor $false }

    It 'strips ANSI escape sequences' {
        $out = Invoke-Ansi { Format-AnsiTree $script:Tree -Color DarkGray -LabelColor BrightWhite }
        $out | Should -Not -Match ([regex]::Escape([char]27))
    }

    It 'preserves the guide layout' {
        $rows = Invoke-AnsiLines { Format-AnsiTree $script:Tree }
        $rows[1] | Should -BeExactly ($script:Tee + 'branch-a')
        $rows[4] | Should -BeExactly ($script:Bar + $script:Gap + $script:Last + 'deep-a2x')
    }

    It 'preserves collapsing and wrapping' {
        $rows = Invoke-AnsiLines { Format-AnsiTree $script:Tree -MaxDepth 1 }
        $rows[2] | Should -BeExactly ($script:Bar + $script:Last + $script:Ell)

        $data = @{ Value = 'root'; Children = @(@{ Value = 'a label that is definitely longer than the width' }) }
        $wrapped = Invoke-AnsiLines { Format-AnsiTree $data -MaxWidth 30 }
        $wrapped.Count | Should -BeGreaterThan 2
    }
}

Describe 'Format-AnsiTree — module surface' {
    It 'exports only the formatter' {
        (Get-Module Format-AnsiTree).ExportedFunctions.Keys | Should -Be 'Format-AnsiTree'
    }
}
