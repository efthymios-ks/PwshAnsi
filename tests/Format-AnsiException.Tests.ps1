#Requires -Version 7.2
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

# Format-AnsiException.Tests.ps1
# Pester 5 tests for Format-AnsiException. Rendered output is captured off the
# Information stream (Write-Host redirect 6>&1) and inspected as strings.
#
# Get-AnsiAnchor and Test-AnsiNoColor are replaced inside the module scope
# (70-column buffer, colour forced on) so the suite is host-independent.
# Injection is used rather than Mock: Pester cannot mock a command a module
# merely imported from another module.

BeforeAll {
    $script:src = Join-Path (Split-Path -Parent $PSScriptRoot) 'src'
    Import-Module (Join-Path $script:src 'Format-AnsiException.psm1') -Force -DisableNameChecking
    Import-Module (Join-Path $script:src 'Out-AnsiHost.psm1') -Force -DisableNameChecking
    Import-Module (Join-Path $script:src 'Out-AnsiString.psm1') -Force -DisableNameChecking
    $script:AnsiModule = Get-Module Format-AnsiException

    $script:Ell = [string][char]0x2026
    $script:Branch = [string][char]0x2514 + [string][char]0x2500 + ' '   # └─
    $script:Buffer = 70

    & $script:AnsiModule {
        $script:AnsiTestColumn = 0
        $script:AnsiTestNoColor = $false

        Set-Item function:script:Get-AnsiAnchor -Value {
            param([int]$MaxWidth = 0)
            [PSCustomObject]@{
                Column      = $script:AnsiTestColumn
                BufferWidth = 70
                Width       = $(if ($MaxWidth -gt 0) { $MaxWidth } else { 70 - $script:AnsiTestColumn })
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

    # A real ErrorRecord, so ScriptStackTrace and InvocationInfo are populated.
    function Invoke-AnsiFailingHelper { throw 'something broke' }
    $script:Record = $null
    try { Invoke-AnsiFailingHelper } catch { $script:Record = $_ }

    # Nested exceptions for -Detail Full.
    $script:Inner = [System.InvalidOperationException]::new('inner cause')
    $script:Outer = [System.Exception]::new('outer failure', $script:Inner)
}

Describe 'Format-AnsiException — ErrorRecord' {
    It 'reports the exception type and message' {
        $rows = Invoke-AnsiPlain { Format-AnsiException $script:Record }
        $rows[0] | Should -BeExactly 'System.Management.Automation.RuntimeException: something broke'
    }

    It 'reports the failing position' {
        # De-wrapped: a long path folds across rows with a hanging indent.
        $rows = Invoke-AnsiPlain { Format-AnsiException $script:Record }
        $flat = ($rows | ForEach-Object { $_.TrimStart() }) -join ''
        $flat | Should -Match 'at .*Format-AnsiException\.Tests\.ps1:\s*line\s*\d+'
    }

    It 'indents the position under the message' {
        $rows = Invoke-AnsiPlain { Format-AnsiException $script:Record }
        $rows[1] | Should -Match '^ {4}at '
    }

    It 'produces no output for $null' {
        $rows = Invoke-AnsiPlain { Format-AnsiException $null }
        $rows.Count | Should -Be 0
    }

    It 'renders one block per pipeline item' {
        $rows = Invoke-AnsiPlain { $script:Record, $script:Outer | Format-AnsiException -Detail Short }
        $rows | Should -Be @('something broke', 'outer failure')
    }
}

Describe 'Format-AnsiException — -Detail' {
    It 'Short prints the message only' {
        $rows = Invoke-AnsiPlain { Format-AnsiException $script:Record -Detail Short }
        $rows | Should -Be @('something broke')
    }

    It 'Default adds the type and position but no frames' {
        $rows = Invoke-AnsiPlain { Format-AnsiException $script:Record -Detail Default }
        ($rows -join "`n") | Should -Match 'RuntimeException'
        ($rows -join "`n") | Should -Not -Match 'at Invoke-AnsiFailingHelper'
    }

    It 'Full adds the stack frames' {
        $rows = Invoke-AnsiPlain { Format-AnsiException $script:Record -Detail Full }
        ($rows -join "`n") | Should -Match 'at Invoke-AnsiFailingHelper'
    }

    It 'Full adds inner exceptions' {
        $rows = Invoke-AnsiPlain { Format-AnsiException $script:Outer -Detail Full }
        $rows[0] | Should -BeExactly 'System.Exception: outer failure'
        $rows[1] | Should -BeExactly ('    ' + $script:Branch + 'System.InvalidOperationException: inner cause')
    }

    It 'Default omits inner exceptions' {
        $rows = Invoke-AnsiPlain { Format-AnsiException $script:Outer -Detail Default }
        $rows.Count | Should -Be 1
    }

    It 'Short omits the type' {
        $rows = Invoke-AnsiPlain { Format-AnsiException $script:Outer -Detail Short }
        $rows | Should -Be @('outer failure')
    }

    It 'rejects an unknown detail level' {
        { Format-AnsiException $script:Record -Detail Loud } | Should -Throw
    }
}

Describe 'Format-AnsiException — stack frames' {
    It 'prints frames with -ShowStackTrace' {
        $rows = Invoke-AnsiPlain { Format-AnsiException $script:Record -ShowStackTrace }
        ($rows -join "`n") | Should -Match 'at Invoke-AnsiFailingHelper'
    }

    It 'indents frames under the message' {
        $rows = Invoke-AnsiPlain { Format-AnsiException $script:Record -ShowStackTrace }
        for ($i = 1; $i -lt $rows.Count; $i++) { $rows[$i] | Should -Match '^ {4}' }
    }

    It 'caps frames with -MaxFrames and says how many were dropped' {
        $rows = Invoke-AnsiPlain { Format-AnsiException $script:Record -ShowStackTrace -MaxFrames 1 }
        $joined = $rows -join "`n"
        $joined | Should -Match ([regex]::Escape($script:Ell) + ' \d+ more frame')
        $joined | Should -Not -Match 'at <ScriptBlock>'
    }

    It 'uses the singular for a single dropped frame' {
        # Keep all but one frame, whatever the depth of the Pester call stack.
        $total = @($script:Record.ScriptStackTrace -split "`r?`n" | Where-Object { $_.Trim() }).Count
        $keep = $total - 1
        $rows = Invoke-AnsiPlain { Format-AnsiException $script:Record -ShowStackTrace -MaxFrames $keep }
        $flat = ($rows | ForEach-Object { $_.TrimStart() }) -join ''
        $flat | Should -Match '1 more frame$'
    }

    It 'does not cap at -MaxFrames 0' {
        $capped = Invoke-AnsiPlain { Format-AnsiException $script:Record -ShowStackTrace -MaxFrames 0 }
        ($capped -join "`n") | Should -Not -Match 'more frame'
    }

    It 'rejects a negative -MaxFrames' {
        { Format-AnsiException $script:Record -MaxFrames -1 } | Should -Throw
    }

    It 'suppresses frames at -Detail Short' {
        $rows = Invoke-AnsiPlain { Format-AnsiException $script:Record -Detail Short -ShowStackTrace }
        $rows | Should -Be @('something broke')
    }
}

Describe 'Format-AnsiException — Exception input' {
    It 'reports type and message' {
        $rows = Invoke-AnsiPlain { Format-AnsiException $script:Outer }
        $rows | Should -Be @('System.Exception: outer failure')
    }

    It 'nests inner exceptions one level per depth' {
        $deep = [System.Exception]::new('level 1',
            [System.InvalidOperationException]::new('level 2',
                [System.ArgumentException]::new('level 3')))
        $rows = Invoke-AnsiPlain { Format-AnsiException $deep -Detail Full }
        $rows[1] | Should -Match ('^ {4}' + [regex]::Escape($script:Branch))
        $rows[2] | Should -Match ('^ {8}' + [regex]::Escape($script:Branch))
    }

    It 'honours -Indent for nesting' {
        $rows = Invoke-AnsiPlain { Format-AnsiException $script:Outer -Detail Full -Indent 2 }
        $rows[1] | Should -Match ('^ {2}' + [regex]::Escape($script:Branch))
    }

    It 'treats a bare string as a message with no type' {
        $rows = Invoke-AnsiPlain { Format-AnsiException 'just a message' }
        $rows | Should -Be @('just a message')
    }
}

Describe 'Format-AnsiException — colours' {
    It 'colours the message BrightRed by default' {
        $out = Invoke-Ansi { Format-AnsiException $script:Outer }
        $out | Should -Match ([regex]::Escape($PSStyle.Foreground.BrightRed + 'outer failure'))
    }

    It 'colours the type BrightWhite by default' {
        $out = Invoke-Ansi { Format-AnsiException $script:Outer }
        $out | Should -Match ([regex]::Escape($PSStyle.Foreground.BrightWhite + 'System.Exception'))
    }

    It 'colours the path and line number in a frame' {
        $out = Invoke-Ansi { Format-AnsiException $script:Record -ShowStackTrace }
        $out | Should -Match ([regex]::Escape($PSStyle.Foreground.BrightCyan))
        $out | Should -Match ([regex]::Escape($PSStyle.Foreground.BrightYellow))
    }

    It 'honours a custom <Parameter>' -ForEach @(
        @{ Parameter = 'MessageColor'; Token = 'outer failure' }
        @{ Parameter = 'TypeColor'; Token = 'System.Exception' }
    ) {
        $splat = @{ $Parameter = 'BrightMagenta' }
        $out = Invoke-Ansi { Format-AnsiException $script:Outer @splat }
        $out | Should -Match ([regex]::Escape($PSStyle.Foreground.BrightMagenta + $Token))
    }

    It 'honours -FrameColor for the frame scaffolding' {
        $out = Invoke-Ansi { Format-AnsiException $script:Record -ShowStackTrace -FrameColor BrightGreen }
        $out | Should -Match ([regex]::Escape($PSStyle.Foreground.BrightGreen))
    }

    It 'throws on an unknown <Parameter>' -ForEach @(
        @{ Parameter = 'MessageColor' }
        @{ Parameter = 'TypeColor' }
        @{ Parameter = 'PathColor' }
        @{ Parameter = 'LineNumberColor' }
        @{ Parameter = 'FrameColor' }
    ) {
        $splat = @{ $Parameter = 'Nope' }
        { Format-AnsiException $script:Outer @splat } | Should -Throw
    }
}

Describe 'Format-AnsiException — width' {
    It 'wraps a long message and hangs the continuation rows' {
        $long = [System.Exception]::new('a very long failure message that will certainly not fit inside a narrow width at all')
        $rows = Invoke-AnsiPlain { Format-AnsiException $long -MaxWidth 40 }
        $rows.Count | Should -BeGreaterThan 1
        $rows[1] | Should -Match '^ {4}\S'
    }

    It 'keeps every row within the width' {
        $rows = Invoke-AnsiPlain { Format-AnsiException $script:Record -ShowStackTrace -MaxWidth 40 }
        foreach ($r in $rows) { $r.Length | Should -BeLessOrEqual 40 }
    }

    It 'accepts -Width as an alias of -MaxWidth' {
        $a = Invoke-AnsiPlain { Format-AnsiException $script:Record -MaxWidth 40 }
        $b = Invoke-AnsiPlain { Format-AnsiException $script:Record -Width 40 }
        $a | Should -Be $b
    }
}

Describe 'Format-AnsiException — anchoring' {
    BeforeAll { Set-AnsiTestColumn 4 }
    AfterAll { Set-AnsiTestColumn 0 }

    It 'leaves the first row where the cursor already is' {
        $rows = Invoke-AnsiPlain { Format-AnsiException $script:Outer -Detail Full }
        $rows[0] | Should -BeExactly 'System.Exception: outer failure'
    }

    It 'resumes later rows at the anchor column' {
        $rows = Invoke-AnsiPlain { Format-AnsiException $script:Outer -Detail Full }
        $rows[1] | Should -Match ('^ {8}' + [regex]::Escape($script:Branch))
    }
}

Describe 'Format-AnsiException — | Out-AnsiHost -NoNewline' {
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

    It 'applies to the only row of a short report' {
        Format-AnsiException $script:Outer -Detail Short | Out-AnsiHost -NoNewline
        $script:hostCalls.Count | Should -Be 1
        $script:hostCalls[0].NoNewline | Should -BeTrue
    }

    It 'applies only to the final row of a full report' {
        Format-AnsiException $script:Record -Detail Full | Out-AnsiHost -NoNewline
        $script:hostCalls.Count | Should -BeGreaterThan 1
        $script:hostCalls[-1].NoNewline | Should -BeTrue
        for ($i = 0; $i -lt $script:hostCalls.Count - 1; $i++) {
            $script:hostCalls[$i].NoNewline | Should -BeFalse
        }
    }

    It 'never sets NoNewline when the switch is absent' {
        Format-AnsiException $script:Record -Detail Full
        foreach ($c in $script:hostCalls) { $c.NoNewline | Should -BeFalse }
    }
}

Describe 'Format-AnsiException — no-colour output' {
    BeforeAll { Set-AnsiTestNoColor $true }
    AfterAll { Set-AnsiTestNoColor $false }

    It 'strips ANSI escape sequences' {
        $out = Invoke-Ansi { Format-AnsiException $script:Record -ShowStackTrace }
        $out | Should -Not -Match ([regex]::Escape([char]27))
    }

    It 'preserves the layout' {
        $rows = Invoke-AnsiLines { Format-AnsiException $script:Outer -Detail Full }
        $rows[0] | Should -BeExactly 'System.Exception: outer failure'
        $rows[1] | Should -BeExactly ('    ' + $script:Branch + 'System.InvalidOperationException: inner cause')
    }
}

Describe 'Format-AnsiException — module surface' {
    It 'exports only the formatter' {
        (Get-Module Format-AnsiException).ExportedFunctions.Keys | Should -Be 'Format-AnsiException'
    }
}
