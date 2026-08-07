#Requires -Version 7.2
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

# Out-Ansi.Tests.ps1
# Pester 5 tests for the two writers that consume an [Ansi.Rendering]:
#   Out-AnsiHost   — paints to the host
#   Out-AnsiString — returns strings, ANSI unless -Plain
# Renderings are built by hand here so the writers are tested on their own, and
# with Format-AnsiText/Format-AnsiGrid so the real contract is covered too.

BeforeAll {
    $script:src = Join-Path (Split-Path -Parent $PSScriptRoot) 'src'
    Import-Module (Join-Path $script:src 'Out-AnsiHost.psm1') -Force -DisableNameChecking
    Import-Module (Join-Path $script:src 'Out-AnsiString.psm1') -Force -DisableNameChecking
    Import-Module (Join-Path $script:src 'Format-AnsiText.psm1') -Force -DisableNameChecking
    Import-Module (Join-Path $script:src 'Format-AnsiGrid.psm1') -Force -DisableNameChecking
    Import-Module (Join-Path $script:src 'Ansi.Core.psm1') -Force -DisableNameChecking

    $script:HostModule = Get-Module Out-AnsiHost

    # Pin the anchor and colour decision in every component used here, exactly as
    # the per-component suites do, so the writers are tested against fixed input.
    foreach ($name in 'Format-AnsiText', 'Format-AnsiGrid') {
        & (Get-Module $name) {
            Set-Item function:script:Get-AnsiAnchor -Value {
                param([int]$MaxWidth = 0)
                [PSCustomObject]@{
                    Column      = 0
                    BufferWidth = 40
                    Width       = $(if ($MaxWidth -gt 0) { $MaxWidth } else { 40 })
                }
            }
            Set-Item function:script:Test-AnsiNoColor -Value { $false }
        }
    }

    & $script:HostModule {
        $script:AnsiTestNoColor = $false
        $script:AnsiTestTerminal = $true
        $script:AnsiTestFrame = $null
        Set-Item function:script:Test-AnsiNoColor -Value { $script:AnsiTestNoColor }
        # The positioned path writes straight to the console, so the frame is
        # captured at the seam instead.
        Set-Item function:script:Test-AnsiTerminal -Value { $script:AnsiTestTerminal }
        Set-Item function:script:Write-AnsiFrame -Value {
            param([string]$Text)
            $script:AnsiTestFrame = $Text
        }
    }

    function Set-AnsiTestNoColor {
        param([Parameter(Mandatory)][bool]$Value)
        & $script:HostModule { param($v) $script:AnsiTestNoColor = $v } $Value
    }

    function Set-AnsiTestTerminal {
        param([Parameter(Mandatory)][bool]$Value)
        & $script:HostModule { param($v) $script:AnsiTestTerminal = $v } $Value
    }

    # The frame the last positioned paint wrote.
    function Get-AnsiTestFrame {
        return [string](& $script:HostModule { $script:AnsiTestFrame })
    }

    function New-TestRun {
        param(
            [Parameter(Mandatory)][AllowEmptyString()][string]$Text,
            [string]$Fg
        )
        [PSCustomObject]@{
            Text   = $Text
            Fg     = $(if ($Fg) { $Fg } else { $null })
            Bg     = $null
            Styles = @()
            Link   = $null
        }
    }

    # Two rows: 'red' in BrightRed, then plain 'plain'.
    function New-TestRendering {
        param(
            [int]$Column = 0,
            [AllowNull()][System.Nullable[bool]]$NoColor = $null,
            [int]$Width = 5
        )
        $rows = @(
            , @((New-TestRun -Text 'red' -Fg 'BrightRed'))
            , @((New-TestRun -Text 'plain'))
        )
        return (New-AnsiRendering -Kind 'Test' -Rows $rows -Width $Width -Column $Column -NoColor $NoColor)
    }

    function Invoke-AnsiLines {
        param([Parameter(Mandatory)][scriptblock]$Sb)
        $records = & $Sb 6>&1
        if ($null -eq $records) { return , @() }
        $rows = @($records | ForEach-Object { [string]$_.ToString() })
        return , $rows
    }

    function Remove-Ansi {
        param([AllowEmptyString()][string]$Text)
        return ($Text -replace "`e\[[\d;]*m", '')
    }
}

Describe 'Ansi.Rendering — the object Format-Ansi* returns' {
    It 'carries the kind, rows, width, column, and colour decision' {
        $rendering = Format-AnsiText 'hello' -MaxWidth 20
        $rendering.Kind | Should -BeExactly 'Text'
        $rendering.Width | Should -Be 20
        $rendering.RowCount | Should -Be 1
        $rendering.PSObject.TypeNames | Should -Contain 'Ansi.Rendering'
    }

    It 'writes nothing to the host when only formatting' {
        $rows = Invoke-AnsiLines { $null = Format-AnsiText 'hello' -MaxWidth 20 }
        $rows.Count | Should -Be 0
    }

    It 'keeps rows as runs, not strings' {
        $rendering = Format-AnsiText '[bold]x[/]' -MaxWidth 20
        $row = @($rendering.Rows[0])
        $row[0].Text | Should -BeExactly 'x'
        $row[0].Styles | Should -Contain 'Bold'
    }

    It 'is recognised by Test-AnsiRendering' {
        Test-AnsiRendering -Value (Format-AnsiText 'x') | Should -BeTrue
        Test-AnsiRendering -Value 'not a rendering' | Should -BeFalse
        Test-AnsiRendering -Value $null | Should -BeFalse
    }
}

Describe 'Out-AnsiHost' {
    It 'paints one host row per rendering row' {
        $rendering = New-TestRendering
        $rows = Invoke-AnsiLines { Out-AnsiHost -Rendering $rendering }
        $rows.Count | Should -Be 2
        (Remove-Ansi $rows[0]) | Should -BeExactly 'red'
        (Remove-Ansi $rows[1]) | Should -BeExactly 'plain'
    }

    It 'keeps the styles the runs carry' {
        $rendering = New-TestRendering
        $rows = Invoke-AnsiLines { Out-AnsiHost -Rendering $rendering }
        $rows[0] | Should -Match ([regex]::Escape($PSStyle.Foreground.BrightRed + 'red'))
    }

    It 'accepts a rendering from the pipeline' {
        $rows = Invoke-AnsiLines { Format-AnsiText 'piped' -MaxWidth 20 | Out-AnsiHost }
        (Remove-Ansi $rows[0]) | Should -BeExactly 'piped'
    }

    It 'leaves the first row unprefixed and resumes later rows at the anchor column' {
        $rendering = New-TestRendering -Column 4
        $rows = Invoke-AnsiLines { Out-AnsiHost -Rendering $rendering }
        (Remove-Ansi $rows[0]) | Should -BeExactly 'red'
        (Remove-Ansi $rows[1]) | Should -BeExactly '    plain'
    }

    It 'honours -Column over the rendering' {
        $rendering = New-TestRendering -Column 4
        $rows = Invoke-AnsiLines { Out-AnsiHost -Rendering $rendering -Column 1 }
        (Remove-Ansi $rows[1]) | Should -BeExactly ' plain'
    }

    It 'does not prefix a blank row' {
        $rows = @(, @((New-TestRun -Text 'a')), , @((New-TestRun -Text '')))
        $rendering = New-AnsiRendering -Kind 'Test' -Rows $rows -Width 1 -Column 6 -NoColor $false
        $painted = Invoke-AnsiLines { Out-AnsiHost -Rendering $rendering }
        $painted[1] | Should -BeExactly ''
    }

    It 'strips styles when the rendering says NoColor' {
        $rendering = New-TestRendering -NoColor $true
        $rows = Invoke-AnsiLines { Out-AnsiHost -Rendering $rendering }
        $rows[0] | Should -BeExactly 'red'
        $rows[0] | Should -Not -Match ([regex]::Escape([char]27))
    }

    It 'honours -NoColor over the rendering' {
        $rendering = New-TestRendering -NoColor $false
        $rows = Invoke-AnsiLines { Out-AnsiHost -Rendering $rendering -NoColor $true }
        $rows[0] | Should -BeExactly 'red'
    }

    It 'honours -NoColor $false over a NoColor rendering' {
        $rendering = New-TestRendering -NoColor $true
        $rows = Invoke-AnsiLines { Out-AnsiHost -Rendering $rendering -NoColor $false }
        $rows[0] | Should -Match ([regex]::Escape($PSStyle.Foreground.BrightRed))
    }

    It 'falls back to Test-AnsiNoColor when neither says' {
        Set-AnsiTestNoColor $true
        try {
            $rendering = New-TestRendering -NoColor $null
            $rows = Invoke-AnsiLines { Out-AnsiHost -Rendering $rendering }
            $rows[0] | Should -BeExactly 'red'
        } finally {
            Set-AnsiTestNoColor $false
        }
    }

    It 'writes nothing for $null' {
        $rows = Invoke-AnsiLines { Out-AnsiHost -Rendering $null }
        $rows.Count | Should -Be 0
    }

    It 'writes nothing for a rendering with no rows' {
        $rendering = New-AnsiRendering -Kind 'Test' -Rows @() -Width 1 -Column 0 -NoColor $false
        $rows = Invoke-AnsiLines { Out-AnsiHost -Rendering $rendering }
        $rows.Count | Should -Be 0
    }

    It 'throws when handed something that is not a rendering' {
        # try/catch rather than -Throw with a wildcard: '[Ansi.Rendering]' would be
        # read as a character class.
        $err = $null
        try { Out-AnsiHost -Rendering 'just a string' } catch { $err = $_ }
        $err | Should -Not -BeNullOrEmpty
        $err.Exception.Message | Should -Match ([regex]::Escape('expects an [Ansi.Rendering]'))
    }

    Context '-NoNewline' {
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
            Out-AnsiHost -Rendering (New-TestRendering) -NoNewline
            $script:hostCalls.Count | Should -Be 2
            $script:hostCalls[0].NoNewline | Should -BeFalse
            $script:hostCalls[-1].NoNewline | Should -BeTrue
        }

        It 'never sets NoNewline when the switch is absent' {
            Out-AnsiHost -Rendering (New-TestRendering)
            foreach ($c in $script:hostCalls) { $c.NoNewline | Should -BeFalse }
        }
    }

    Context '-Row and -Column' {
        BeforeEach {
            Set-AnsiTestTerminal -Value $true
            Set-AnsiTestNoColor $false
        }
        AfterAll { Set-AnsiTestTerminal -Value $true }

        It 'paints each row at the cell it was given, 0-based' {
            Out-AnsiHost -Rendering (New-TestRendering) -Row 4 -Column 10
            $frame = Get-AnsiTestFrame
            # CUP is 1-based on the wire: row 4, column 10 is 5;11.
            $frame | Should -Match ([regex]::Escape("`e[5;11H"))
            $frame | Should -Match ([regex]::Escape("`e[6;11H"))
        }

        It 'starts at the very first cell for -Row 0 -Column 0' {
            Out-AnsiHost -Rendering (New-TestRendering) -Row 0 -Column 0
            (Get-AnsiTestFrame) | Should -Match ([regex]::Escape("`e[1;1H"))
        }

        It 'writes the whole frame once' {
            $script:writes = 0
            & $script:HostModule {
                Set-Item function:script:Write-AnsiFrame -Value {
                    param([string]$Text)
                    $script:AnsiTestFrame = $Text
                    $script:AnsiTestWrites = [int]$script:AnsiTestWrites + 1
                }
                $script:AnsiTestWrites = 0
            }
            Out-AnsiHost -Rendering (New-TestRendering) -Row 2 -Column 0
            (& $script:HostModule { $script:AnsiTestWrites }) | Should -Be 1
            # And put the capturing seam back for the tests that follow.
            & $script:HostModule {
                Set-Item function:script:Write-AnsiFrame -Value {
                    param([string]$Text)
                    $script:AnsiTestFrame = $Text
                }
            }
        }

        It 'erases to the end of every line instead of clearing first' {
            Out-AnsiHost -Rendering (New-TestRendering) -Row 0 -Column 0
            $frame = Get-AnsiTestFrame
            ([regex]::Matches($frame, [regex]::Escape("`e[K"))).Count | Should -Be 2
            $frame | Should -Not -Match ([regex]::Escape("`e[2J"))
        }

        It 'saves the cursor, hides it, and puts it back' {
            Out-AnsiHost -Rendering (New-TestRendering) -Row 1 -Column 1
            $frame = Get-AnsiTestFrame
            $frame | Should -Match ([regex]::Escape("`e7"))
            $frame | Should -Match ([regex]::Escape("`e[?25l"))
            $frame | Should -Match ([regex]::Escape("`e[?25h"))
            $frame | Should -Match ([regex]::Escape("`e8"))
        }

        It 'wraps the frame in synchronized output' {
            Out-AnsiHost -Rendering (New-TestRendering) -Row 1 -Column 1
            $frame = Get-AnsiTestFrame
            # Begin before the first row lands, end after the last.
            $frame.IndexOf("`e[?2026h") | Should -BeLessThan $frame.IndexOf("`e[2;2H")
            $frame.IndexOf("`e[?2026l") | Should -BeGreaterThan $frame.IndexOf("`e[3;2H")
        }

        It 'keeps the styles the runs carry' {
            Out-AnsiHost -Rendering (New-TestRendering) -Row 0 -Column 0
            (Get-AnsiTestFrame) | Should -Match ([regex]::Escape($PSStyle.Foreground.BrightRed + 'red'))
        }

        It 'honours -NoColor while still positioning' {
            Out-AnsiHost -Rendering (New-TestRendering) -Row 0 -Column 0 -NoColor $true
            $frame = Get-AnsiTestFrame
            $frame | Should -Not -Match ([regex]::Escape($PSStyle.Foreground.BrightRed))
            $frame | Should -Match ([regex]::Escape("`e[1;1H"))
        }

        It 'writes no host rows at all' {
            $rows = Invoke-AnsiLines { Out-AnsiHost -Rendering (New-TestRendering) -Row 3 -Column 3 }
            $rows.Count | Should -Be 0
        }

        It 'drops every cursor sequence when output is not a terminal' {
            Set-AnsiTestTerminal -Value $false
            Out-AnsiHost -Rendering (New-TestRendering) -Row 4 -Column 2 -NoColor $true
            $frame = Get-AnsiTestFrame
            $frame | Should -Not -Match ([regex]::Escape([char]27))
            $frame | Should -BeExactly ('  red' + [System.Environment]::NewLine +
                '  plain' + [System.Environment]::NewLine)
        }

        It 'takes the rendering from the pipeline' {
            Format-AnsiText 'piped' -MaxWidth 20 | Out-AnsiHost -Row 2 -Column 5
            (Get-AnsiTestFrame) | Should -Match 'piped'
        }

        It 'needs both -Row and -Column' {
            # Read off the metadata, not by calling it: an interactive host prompts
            # for a missing mandatory parameter instead of failing, and a suite must
            # never sit waiting for one.
            $set = (Get-Command Out-AnsiHost).ParameterSets | Where-Object Name -EQ 'Position'
            $set | Should -Not -BeNullOrEmpty
            foreach ($name in 'Row', 'Column') {
                ($set.Parameters | Where-Object Name -EQ $name).IsMandatory | Should -BeTrue
            }
            # And -Row is in no other set, so it cannot be passed on its own.
            $others = (Get-Command Out-AnsiHost).ParameterSets | Where-Object Name -NE 'Position'
            foreach ($other in $others) {
                ($other.Parameters | Where-Object Name -EQ 'Row') | Should -BeNullOrEmpty
            }
        }

        It 'rejects a negative row' {
            { Out-AnsiHost -Rendering (New-TestRendering) -Row -1 -Column 0 } | Should -Throw
        }

        It 'refuses -NoNewline, which a positioned frame has no use for' {
            { Out-AnsiHost -Rendering (New-TestRendering) -Row 1 -Column 1 -NoNewline -ErrorAction Stop } |
                Should -Throw
        }

        It 'writes nothing for a rendering with no rows' {
            & $script:HostModule { $script:AnsiTestFrame = 'untouched' }
            $rendering = New-AnsiRendering -Kind 'Test' -Rows @() -Width 1 -Column 0 -NoColor $false
            Out-AnsiHost -Rendering $rendering -Row 0 -Column 0
            (Get-AnsiTestFrame) | Should -BeExactly 'untouched'
        }
    }
}

Describe 'Out-AnsiString' {
    It 'returns one string per row' {
        $strings = Out-AnsiString -Rendering (New-TestRendering)
        $strings.Count | Should -Be 2
        (Remove-Ansi $strings[0]) | Should -BeExactly 'red'
        (Remove-Ansi $strings[1]) | Should -BeExactly 'plain'
    }

    It 'returns strings, not host output' {
        $rows = Invoke-AnsiLines { $null = Out-AnsiString -Rendering (New-TestRendering) }
        $rows.Count | Should -Be 0
    }

    It 'keeps ANSI by default' {
        $strings = Out-AnsiString -Rendering (New-TestRendering)
        $strings[0] | Should -Match ([regex]::Escape($PSStyle.Foreground.BrightRed + 'red'))
    }

    It 'strips every style with -Plain' {
        $strings = Out-AnsiString -Rendering (New-TestRendering) -Plain
        $strings[0] | Should -BeExactly 'red'
        $strings[0] | Should -Not -Match ([regex]::Escape([char]27))
    }

    It 'strips hyperlinks with -Plain too' {
        $linked = New-TestRun -Text 'link'
        $linked.Link = 'https://example.com'
        $rendering = New-AnsiRendering -Kind 'Test' -Rows @(, @($linked)) -Width 4 -Column 0 -NoColor $false
        (Out-AnsiString -Rendering $rendering) | Should -Match ([regex]::Escape('https://example.com'))
        (Out-AnsiString -Rendering $rendering -Plain) | Should -BeExactly 'link'
    }

    It 'honours a NoColor rendering without -Plain' {
        $strings = Out-AnsiString -Rendering (New-TestRendering -NoColor $true)
        $strings[0] | Should -BeExactly 'red'
    }

    It 'adds no anchor prefix by default' {
        $strings = Out-AnsiString -Rendering (New-TestRendering -Column 4) -Plain
        $strings[1] | Should -BeExactly 'plain'
    }

    It 'prefixes later rows with -WithAnchor' {
        $strings = Out-AnsiString -Rendering (New-TestRendering -Column 4) -Plain -WithAnchor
        $strings[0] | Should -BeExactly 'red'
        $strings[1] | Should -BeExactly '    plain'
    }

    It 'joins rows with -Join' {
        $joined = Out-AnsiString -Rendering (New-TestRendering) -Plain -Join
        $joined | Should -BeOfType ([string])
        $joined | Should -BeExactly ('red' + [System.Environment]::NewLine + 'plain')
    }

    It 'accepts a rendering from the pipeline' {
        $strings = Format-AnsiText 'piped' -MaxWidth 20 | Out-AnsiString -Plain
        $strings | Should -Be @('piped')
    }

    It 'returns nothing for $null' {
        $strings = Out-AnsiString -Rendering $null
        $strings | Should -BeNullOrEmpty
    }

    It 'throws when handed something that is not a rendering' {
        $err = $null
        try { Out-AnsiString -Rendering 42 } catch { $err = $_ }
        $err | Should -Not -BeNullOrEmpty
        $err.Exception.Message | Should -Match ([regex]::Escape('expects an [Ansi.Rendering]'))
    }
}

Describe 'Out-Ansi* — round trip with real components' {
    It 'paints what Out-AnsiString returns' {
        $painted = Invoke-AnsiLines { Format-AnsiText 'aaa bbb ccc' -MaxWidth 5 | Out-AnsiHost }
        $strings = Format-AnsiText 'aaa bbb ccc' -MaxWidth 5 | Out-AnsiString
        $painted | Should -Be $strings
    }

    It 'stringifies a grid without touching the host' {
        $strings = Format-AnsiGrid @(, @('k', 'v'), @('kk', 'vv')) -MaxWidth 30 | Out-AnsiString -Plain
        $strings | Should -Be @('k   v', 'kk  vv')
    }

    It 'feeds captured strings straight into a panel' {
        Import-Module (Join-Path $script:src 'Format-AnsiPanel.psm1') -Force -DisableNameChecking
        & (Get-Module Format-AnsiPanel) {
            Set-Item function:script:Get-AnsiAnchor -Value {
                param([int]$MaxWidth = 0)
                [PSCustomObject]@{
                    Column      = 0
                    BufferWidth = 40
                    Width       = $(if ($MaxWidth -gt 0) { $MaxWidth } else { 40 })
                }
            }
            Set-Item function:script:Test-AnsiNoColor -Value { $false }
        }

        $rows = Format-AnsiGrid @(, @('k', 'v')) -MaxWidth 30 | Out-AnsiString
        $panel = Invoke-AnsiLines { Format-AnsiPanel $rows -Rendered -Title 'grid' | Out-AnsiHost }
        $panel.Count | Should -Be 3
        # The title (4 + 2 spaces) is wider than 'k  v', so the panel widens to 6.
        (Remove-Ansi $panel[1]) | Should -BeExactly ([string][char]0x2502 + ' k  v   ' + [string][char]0x2502)
    }

    It 'renders text to a string with styles intact' {
        $strings = Format-AnsiText '[bold]x[/]' -MaxWidth 10 | Out-AnsiString
        $strings[0] | Should -Match ([regex]::Escape($PSStyle.Bold))
    }
}

Describe 'Cursor visibility' {
    BeforeAll {
        # -PassThru for the reference: every component imports Ansi.Core with -Force,
        # which unloads whatever global import came before it, so Get-Module cannot
        # be relied on to still find it by name.
        $script:CoreModule = Import-Module (Join-Path $script:src 'Ansi.Core.psm1') `
            -Force -DisableNameChecking -PassThru
    }

    It 'writes nothing when output is not a terminal' {
        # Redirected here, so the guards a prompt puts around its key loop are
        # no-ops and nothing lands in anything a suite captures.
        $rows = Invoke-AnsiLines { $null = & $script:CoreModule { Hide-AnsiCursor } }
        $rows.Count | Should -Be 0
        $rows = Invoke-AnsiLines { $null = & $script:CoreModule { Show-AnsiCursor } }
        $rows.Count | Should -Be 0
    }

    It 'reports the state it found, or $null where the platform will not say' {
        $state = & $script:CoreModule { Hide-AnsiCursor }
        ($state -is [bool] -or $null -eq $state) | Should -BeTrue
    }

    It 'restores hidden with hidden and anything else with visible' {
        # The two calls are replaced in Core's scope, so what Restore-AnsiCursor
        # decided is what gets recorded.
        & $script:CoreModule {
            $script:AnsiTestCursorCalls = [System.Collections.Generic.List[string]]::new()
            Set-Item function:script:Hide-AnsiCursor -Value { $script:AnsiTestCursorCalls.Add('hide') }
            Set-Item function:script:Show-AnsiCursor -Value { $script:AnsiTestCursorCalls.Add('show') }

            Restore-AnsiCursor -State $false
            Restore-AnsiCursor -State $true
            Restore-AnsiCursor -State $null
        }
        $calls = & $script:CoreModule { $script:AnsiTestCursorCalls }
        $calls | Should -Be @('hide', 'show', 'show')
    }
}

Describe 'Out-Ansi* — module surface' {
    It 'Out-AnsiHost exports only Out-AnsiHost' {
        (Get-Module Out-AnsiHost).ExportedFunctions.Keys | Should -Be 'Out-AnsiHost'
    }

    It 'Out-AnsiString exports only Out-AnsiString' {
        (Get-Module Out-AnsiString).ExportedFunctions.Keys | Should -Be 'Out-AnsiString'
    }
}
