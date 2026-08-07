#Requires -Version 7.2
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

# Format-AnsiPath.Tests.ps1
# Pester 5 tests for Format-AnsiPath. Rendered output is captured off the
# Information stream (Write-Host redirect 6>&1) and inspected as strings.
#
# Get-AnsiAnchor and Test-AnsiNoColor are replaced inside the Format-AnsiPath module
# scope (40-column buffer, colour forced on) so the suite is host-independent.
# Injection is used rather than Mock: Pester cannot mock a command a module
# merely imported from another module.

BeforeAll {
    $script:src = Join-Path (Split-Path -Parent $PSScriptRoot) 'src'
    Import-Module (Join-Path $script:src 'Format-AnsiPath.psm1') -Force -DisableNameChecking
    Import-Module (Join-Path $script:src 'Out-AnsiHost.psm1') -Force -DisableNameChecking
    Import-Module (Join-Path $script:src 'Out-AnsiString.psm1') -Force -DisableNameChecking
    $script:AnsiModule = Get-Module Format-AnsiPath

    $script:Ell = [string][char]0x2026     # …
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

    function Measure-Occurrence {
        param([string]$Text, [string]$Needle)
        return ([regex]::Matches($Text, [regex]::Escape($Needle))).Count
    }
}

Describe 'Format-AnsiPath — path shapes' {
    It 'renders <Case> unchanged' -ForEach @(
        @{ Case = 'a Windows absolute path'; PathText = 'C:\Users\dev\repo\file.txt' }
        @{ Case = 'a Unix absolute path'; PathText = '/usr/local/share/doc/readme.md' }
        @{ Case = 'a UNC path'; PathText = '\\server\share\team\notes.docx' }
        @{ Case = 'a relative path'; PathText = 'src\Format-AnsiPath.psm1' }
        @{ Case = 'a home-relative path'; PathText = '~/projects/ansi/src/core.psm1' }
        @{ Case = 'a bare leaf'; PathText = 'file.txt' }
        @{ Case = 'a trailing separator'; PathText = 'C:\Users\repo\' }
        @{ Case = 'a drive root'; PathText = 'C:\' }
        @{ Case = 'a filesystem root'; PathText = '/' }
        @{ Case = 'a dotted relative path'; PathText = '..\..\src\file.ps1' }
    ) {
        $target = $PathText
        $out = Invoke-Ansi { Format-AnsiPath $target -MaxWidth 60 }
        Remove-Ansi $out | Should -BeExactly $target
    }

    It 'does not validate that the path exists' {
        $out = Invoke-Ansi { Format-AnsiPath 'Q:\nope\missing\ghost.txt' -MaxWidth 60 }
        Remove-Ansi $out | Should -BeExactly 'Q:\nope\missing\ghost.txt'
    }

    It 'normalises mixed separators onto the first one used' {
        $out = Invoke-Ansi { Format-AnsiPath 'C:/Users\repo/file.txt' -MaxWidth 60 }
        Remove-Ansi $out | Should -BeExactly 'C:/Users/repo/file.txt'
    }

    It 'collapses repeated separators' {
        $out = Invoke-Ansi { Format-AnsiPath 'C:\Users\\repo\file.txt' -MaxWidth 60 }
        Remove-Ansi $out | Should -BeExactly 'C:\Users\repo\file.txt'
    }

    It 'emits one row per path' {
        $lines = Invoke-AnsiLines { Format-AnsiPath 'a\1.txt' -MaxWidth 20 }
        $lines.Count | Should -Be 1
    }
}

Describe 'Format-AnsiPath — colours' {
    It 'colours the root with -RootColor' {
        $out = Invoke-Ansi { Format-AnsiPath 'C:\a\leaf.txt' -MaxWidth 30 -RootColor BrightRed }
        $out | Should -Match ([regex]::Escape($PSStyle.Foreground.BrightRed + 'C:\'))
    }

    It 'colours separators with -SeparatorColor' {
        $out = Invoke-Ansi { Format-AnsiPath 'a\b\leaf.txt' -MaxWidth 30 -SeparatorColor DarkGray }
        Measure-Occurrence $out ($PSStyle.Foreground.BrightBlack + '\') | Should -Be 2
    }

    It 'colours stem segments with -StemColor' {
        $out = Invoke-Ansi { Format-AnsiPath 'a\b\leaf.txt' -MaxWidth 30 -StemColor BrightBlue }
        Measure-Occurrence $out $PSStyle.Foreground.BrightBlue | Should -Be 2
    }

    It 'colours the leaf with -LeafColor' {
        $out = Invoke-Ansi { Format-AnsiPath 'a\b\leaf.txt' -MaxWidth 30 -LeafColor BrightGreen }
        $out | Should -Match ([regex]::Escape($PSStyle.Foreground.BrightGreen + 'leaf.txt'))
    }

    It 'applies -Color to every part' {
        $out = Invoke-Ansi { Format-AnsiPath 'C:\a\leaf.txt' -MaxWidth 30 -Color BrightCyan }
        # root, stem, separator, leaf
        Measure-Occurrence $out $PSStyle.Foreground.BrightCyan | Should -Be 4
        Remove-Ansi $out | Should -BeExactly 'C:\a\leaf.txt'
    }

    It 'lets a specific part override -Color' {
        $out = Invoke-Ansi { Format-AnsiPath 'C:\a\leaf.txt' -MaxWidth 30 -Color DarkGray -LeafColor BrightWhite }
        $out | Should -Match ([regex]::Escape($PSStyle.Foreground.BrightWhite + 'leaf.txt'))
        Measure-Occurrence $out $PSStyle.Foreground.BrightBlack | Should -Be 3
    }

    It 'aliases -PathColor as -Color' {
        $out = Invoke-Ansi { Format-AnsiPath 'a\b.txt' -MaxWidth 30 -PathColor BrightCyan }
        $out | Should -Match ([regex]::Escape($PSStyle.Foreground.BrightCyan))
    }

    It 'renders unstyled when no colour is given' {
        $out = Invoke-Ansi { Format-AnsiPath 'a\b.txt' -MaxWidth 30 }
        $out | Should -BeExactly 'a\b.txt'
    }

    It 'throws on an unknown <Parameter>' -ForEach @(
        @{ Parameter = 'Color' }
        @{ Parameter = 'RootColor' }
        @{ Parameter = 'SeparatorColor' }
        @{ Parameter = 'StemColor' }
        @{ Parameter = 'LeafColor' }
    ) {
        $splat = @{ $Parameter = 'Nope' }
        { Format-AnsiPath 'a\b.txt' -MaxWidth 30 @splat } | Should -Throw
    }
}

Describe 'Format-AnsiPath — truncation' {
    BeforeAll {
        $script:deep = 'C:\Users\dev\repos\ansi\src\deeply\nested\file.txt'
    }

    It 'drops middle segments and marks them with …' {
        $out = Invoke-Ansi { Format-AnsiPath $script:deep -MaxWidth 30 }
        Remove-Ansi $out | Should -BeExactly ('C:\' + $script:Ell + '\deeply\nested\file.txt')
    }

    It 'drops more segments as the width shrinks' {
        $out = Invoke-Ansi { Format-AnsiPath $script:deep -MaxWidth 20 }
        Remove-Ansi $out | Should -BeExactly ('C:\' + $script:Ell + '\nested\file.txt')
    }

    It 'keeps the row within the width at every size' -ForEach @(
        @{ Width = 40 }, @{ Width = 30 }, @{ Width = 24 }, @{ Width = 18 }, @{ Width = 12 }, @{ Width = 8 }
    ) {
        $w = $Width
        $out = Invoke-Ansi { Format-AnsiPath $script:deep -MaxWidth $w }
        (Remove-Ansi $out).Length | Should -BeLessOrEqual $w
    }

    It 'always keeps the root and the leaf visible when either fits' {
        $out = Invoke-Ansi { Format-AnsiPath $script:deep -MaxWidth 18 }
        $plain = Remove-Ansi $out
        $plain | Should -BeLike 'C:\*'
        $plain | Should -BeLike '*file.txt'
    }

    It 'ellipsises the leaf when even root + leaf will not fit' {
        $out = Invoke-Ansi { Format-AnsiPath $script:deep -MaxWidth 10 }
        $plain = Remove-Ansi $out
        $plain.Length | Should -Be 10
        $plain | Should -BeExactly ('C:\' + $script:Ell + '\file' + $script:Ell)
    }

    It 'ellipsises a single long leaf' {
        $out = Invoke-Ansi { Format-AnsiPath 'C:\averyveryverylongleafname.txt' -MaxWidth 12 }
        Remove-Ansi $out | Should -BeExactly ('C:\averyver' + $script:Ell)
    }

    It 'truncates a rootless path' {
        $out = Invoke-Ansi { Format-AnsiPath 'a\b\c\d\leaf.txt' -MaxWidth 12 }
        Remove-Ansi $out | Should -BeExactly ($script:Ell + '\d\leaf.txt')
    }

    It 'truncates a Unix path with its own separator' {
        $out = Invoke-Ansi { Format-AnsiPath '/usr/local/share/doc/readme.md' -MaxWidth 20 }
        Remove-Ansi $out | Should -BeExactly ('/' + $script:Ell + '/doc/readme.md')
    }

    It 'does not truncate a path that fits' {
        $out = Invoke-Ansi { Format-AnsiPath 'C:\a\b.txt' -MaxWidth 30 }
        Remove-Ansi $out | Should -Not -Match ([regex]::Escape($script:Ell))
    }

    It 'keeps the leaf colour on a truncated path' {
        $out = Invoke-Ansi { Format-AnsiPath $script:deep -MaxWidth 20 -LeafColor BrightGreen }
        $out | Should -Match ([regex]::Escape($PSStyle.Foreground.BrightGreen + 'file.txt'))
    }

    It 'colours the … stand-in with the stem colour' {
        $out = Invoke-Ansi { Format-AnsiPath $script:deep -MaxWidth 20 -StemColor BrightBlue }
        $out | Should -Match ([regex]::Escape($PSStyle.Foreground.BrightBlue + $script:Ell))
    }
}

Describe 'Format-AnsiPath — -Alignment' {
    It 'left-aligns by default' {
        $out = Invoke-Ansi { Format-AnsiPath 'a\b.txt' -MaxWidth 20 }
        Remove-Ansi $out | Should -BeExactly 'a\b.txt'
    }

    It 'centers within the width' {
        # pad = 20 - 7 = 13 => leftPad = 6
        $out = Invoke-Ansi { Format-AnsiPath 'a\b.txt' -MaxWidth 20 -Alignment Center }
        Remove-Ansi $out | Should -BeExactly ((' ' * 6) + 'a\b.txt')
    }

    It 'right-aligns within the width' {
        $out = Invoke-Ansi { Format-AnsiPath 'a\b.txt' -MaxWidth 20 -Alignment Right }
        Remove-Ansi $out | Should -BeExactly ((' ' * 13) + 'a\b.txt')
    }

    It 'aligns each row independently' {
        $lines = Invoke-AnsiLines { Format-AnsiPath 'a.txt', 'bb.txt' -MaxWidth 10 -Alignment Right }
        (Remove-Ansi $lines[0]) | Should -BeExactly ((' ' * 5) + 'a.txt')
        (Remove-Ansi $lines[1]) | Should -BeExactly ((' ' * 4) + 'bb.txt')
    }

    It 'rejects an unknown -Alignment value' {
        { Format-AnsiPath 'a' -Alignment Middle } | Should -Throw
    }
}

Describe 'Format-AnsiPath — input handling' {
    It 'renders one row per array item' {
        $lines = Invoke-AnsiLines { Format-AnsiPath 'a\1.txt', 'b\2.txt' -MaxWidth 20 }
        $lines.Count | Should -Be 2
        (Remove-Ansi $lines[1]) | Should -BeExactly 'b\2.txt'
    }

    It 'renders one row per pipeline item' {
        $lines = Invoke-AnsiLines { 'a\1.txt', 'b\2.txt', 'c\3.txt' | Format-AnsiPath -MaxWidth 20 }
        $lines.Count | Should -Be 3
    }

    It 'binds FullName from the pipeline by property name' {
        $item = [PSCustomObject]@{ FullName = 'C:\a\b.txt' }
        $out = Invoke-Ansi { $item | Format-AnsiPath -MaxWidth 20 }
        Remove-Ansi $out | Should -BeExactly 'C:\a\b.txt'
    }

    It 'accepts real filesystem items' {
        $file = Get-ChildItem -LiteralPath $script:src -File | Select-Object -First 1
        $out = Invoke-Ansi { $file | Format-AnsiPath -MaxWidth 60 }
        Remove-Ansi $out | Should -BeExactly $file.FullName
    }

    It 'produces no output for an empty collection' {
        $lines = Invoke-AnsiLines { Format-AnsiPath @() }
        $lines.Count | Should -Be 0
    }

    It 'produces no output for $null' {
        $lines = Invoke-AnsiLines { Format-AnsiPath $null }
        $lines.Count | Should -Be 0
    }

    It 'renders one blank row for an empty string' {
        $lines = Invoke-AnsiLines { Format-AnsiPath '' -MaxWidth 20 }
        $lines.Count | Should -Be 1
        Remove-Ansi $lines[0] | Should -BeExactly ''
    }
}

Describe 'Format-AnsiPath — anchoring' {
    BeforeAll { Set-AnsiTestColumn 6 }
    AfterAll { Set-AnsiTestColumn 0 }

    It 'sizes the row to the remaining buffer' {
        $long = 'C:\' + ('seg\' * 20) + 'leaf.txt'
        $out = Invoke-Ansi { Format-AnsiPath $long }
        (Remove-Ansi $out).Length | Should -BeLessOrEqual ($script:Buffer - 6)
    }

    It 'leaves the first row where the cursor already is' {
        $lines = Invoke-AnsiLines { Format-AnsiPath 'a\1.txt', 'b\2.txt' }
        (Remove-Ansi $lines[0]) | Should -BeExactly 'a\1.txt'
    }

    It 'resumes later rows at the anchor column' {
        $lines = Invoke-AnsiLines { Format-AnsiPath 'a\1.txt', 'b\2.txt' }
        (Remove-Ansi $lines[1]) | Should -BeExactly ((' ' * 6) + 'b\2.txt')
    }
}

Describe 'Format-AnsiPath — | Out-AnsiHost -NoNewline' {
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

    It 'applies to the only row of a single path' {
        Format-AnsiPath 'a\b.txt' -MaxWidth 20 | Out-AnsiHost -NoNewline
        $script:hostCalls.Count | Should -Be 1
        $script:hostCalls[0].NoNewline | Should -BeTrue
    }

    It 'applies only to the final row of several paths' {
        Format-AnsiPath 'a.txt', 'b.txt', 'c.txt' -MaxWidth 20 | Out-AnsiHost -NoNewline
        $script:hostCalls.Count | Should -Be 3
        $script:hostCalls[-1].NoNewline | Should -BeTrue
        for ($i = 0; $i -lt $script:hostCalls.Count - 1; $i++) {
            $script:hostCalls[$i].NoNewline | Should -BeFalse
        }
    }

    It 'never sets NoNewline when the switch is absent' {
        Format-AnsiPath 'a.txt', 'b.txt' -MaxWidth 20
        foreach ($c in $script:hostCalls) { $c.NoNewline | Should -BeFalse }
    }
}

Describe 'Format-AnsiPath — no-colour output' {
    BeforeAll { Set-AnsiTestNoColor $true }
    AfterAll { Set-AnsiTestNoColor $false }

    It 'strips ANSI escape sequences' {
        $out = Invoke-Ansi {
            Format-AnsiPath 'C:\a\leaf.txt' -MaxWidth 30 -RootColor BrightRed -LeafColor BrightGreen
        }
        $out | Should -Not -Match ([regex]::Escape([char]27))
        $out | Should -BeExactly 'C:\a\leaf.txt'
    }

    It 'preserves truncation and alignment' {
        $out = Invoke-Ansi { Format-AnsiPath 'C:\Users\dev\repos\ansi\src\file.txt' -MaxWidth 20 }
        $out | Should -Match ([regex]::Escape($script:Ell))
        $out.Length | Should -BeLessOrEqual 20

        $right = Invoke-Ansi { Format-AnsiPath 'a\b.txt' -MaxWidth 20 -Alignment Right }
        $right | Should -BeExactly ((' ' * 13) + 'a\b.txt')
    }
}

Describe 'Format-AnsiPath — module surface' {
    It 'exports only the formatter' {
        (Get-Module Format-AnsiPath).ExportedFunctions.Keys | Should -Be 'Format-AnsiPath'
    }
}
