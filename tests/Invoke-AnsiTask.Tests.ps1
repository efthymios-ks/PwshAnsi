#Requires -Version 7.2
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

# Invoke-AnsiTask.Tests.ps1
# Pester 5 tests for Invoke-AnsiTask. Everything it draws goes through Write-Host,
# so the whole run is captured off the Information stream (6>&1) and inspected.
#
# One seam is replaced inside the Invoke-AnsiTask module scope:
#   Test-AnsiTaskLive — whether the terminal can be redrawn in place. Driven by
#                      Set-AnsiTestLive, so both the live and the redirected paths
#                      are testable from a redirected test run.
# Injection is used rather than Mock: Pester cannot mock a command a module
# merely imported from another module.

BeforeAll {
    $script:src = Join-Path (Split-Path -Parent $PSScriptRoot) 'src'
    Import-Module (Join-Path $script:src 'Invoke-AnsiTask.psm1') -Force -DisableNameChecking
    $script:AnsiModule = Get-Module Invoke-AnsiTask

    $script:Done = [string][char]0x2714     # ✔
    $script:Failed = [string][char]0x2718   # ✘
    $script:Running = [string][char]0x2192  # →
    $script:Full = [string][char]0x2588     # █
    $script:Esc = [string][char]27

    & $script:AnsiModule {
        $script:AnsiTestLive = $false
        Set-Item function:script:Test-AnsiTaskLive -Value { $script:AnsiTestLive }
    }

    function Set-AnsiTestLive {
        param([Parameter(Mandatory)][bool]$Value)
        & $script:AnsiModule { param($v) $script:AnsiTestLive = $v } $Value
    }

    # Every Write-Host call as one string.
    function Invoke-AnsiLines {
        param([Parameter(Mandatory)][scriptblock]$Sb)
        $records = & $Sb 6>&1
        if ($null -eq $records) { return , @() }
        $rows = @($records | ForEach-Object { [string]$_.ToString() })
        return , $rows
    }

    function Invoke-Ansi {
        param([Parameter(Mandatory)][scriptblock]$Sb)
        return ((Invoke-AnsiLines $Sb) -join "`n")
    }

    # The same, with the styling removed. A mark and the name beside it are
    # separate runs, so with colour on there are escape sequences between them —
    # and whether colour is on depends on which suites ran first, since the
    # Format-AnsiText module is shared. Assertions about text use this.
    function Invoke-AnsiText {
        param([Parameter(Mandatory)][scriptblock]$Sb)
        $out = Invoke-Ansi $Sb
        return ($out -replace "$([char]27)\[[0-9;]*[A-Za-z]", '')
    }

    function Reset-AnsiTest {
        Set-AnsiTestLive -Value $false
    }
}

Describe 'Invoke-AnsiTask — one step' {
    BeforeEach { Reset-AnsiTest }

    It 'marks a finished step done' {
        $out = Invoke-AnsiText { Invoke-AnsiTask 'build' { } }
        $out | Should -Match ([regex]::Escape("$script:Done build"))
    }

    It 'times the step' {
        $out = Invoke-Ansi { Invoke-AnsiTask 'build' { Start-Sleep -Milliseconds 30 } }
        $out | Should -Match '0\.\d+s'
    }

    It 'runs the scriptblock once' {
        $script:ran = 0
        $null = Invoke-AnsiLines { Invoke-AnsiTask 'build' { $script:ran++ } }
        $script:ran | Should -Be 1
    }

    It 'lets the scriptblock output through' {
        $result = & { Invoke-AnsiTask 'build' { 'from the step' } } 6>$null
        $result | Should -BeExactly 'from the step'
    }

    It 'takes the name and script positionally' {
        $out = Invoke-AnsiText { Invoke-AnsiTask 'positional' { } }
        $out | Should -Match 'positional'
    }

    It 'takes a step name literally, brackets and all' {
        $out = Invoke-AnsiText { Invoke-AnsiTask 'build [x86]' { } }
        $out | Should -Match ([regex]::Escape('build [x86]'))
    }
}

Describe 'Invoke-AnsiTask — several steps' {
    BeforeEach { Reset-AnsiTest }

    It 'runs every step in order' {
        $script:order = [System.Collections.Generic.List[string]]::new()
        $null = Invoke-AnsiLines {
            Invoke-AnsiTask -Task @(
                @{ Name = 'first'; Script = { $script:order.Add('first') } }
                @{ Name = 'second'; Script = { $script:order.Add('second') } }
                @{ Name = 'third'; Script = { $script:order.Add('third') } }
            )
        }
        ($script:order -join ',') | Should -BeExactly 'first,second,third'
    }

    It 'marks each one done' {
        $out = Invoke-AnsiText {
            Invoke-AnsiTask -Task @(
                @{ Name = 'restore'; Script = { } }
                @{ Name = 'build'; Script = { } }
            )
        }
        $out | Should -Match ([regex]::Escape("$script:Done restore"))
        $out | Should -Match ([regex]::Escape("$script:Done build"))
    }

    It 'accepts objects as well as hashtables' {
        $steps = @(
            [PSCustomObject]@{ Name = 'one'; Script = { } }
            [PSCustomObject]@{ Name = 'two'; Script = { } }
        )
        $out = Invoke-Ansi { Invoke-AnsiTask -Task $steps }
        $out | Should -Match 'one'
        $out | Should -Match 'two'
    }

    It 'accepts ScriptBlock as the key too' {
        $out = Invoke-AnsiText { Invoke-AnsiTask -Task @(@{ Name = 'alt'; ScriptBlock = { } }) }
        $out | Should -Match ([regex]::Escape("$script:Done alt"))
    }

    It 'does nothing with an empty task list' {
        $lines = Invoke-AnsiLines { Invoke-AnsiTask -Task @() }
        $lines.Count | Should -Be 0
    }

    It 'refuses a step with no name' {
        { Invoke-AnsiTask -Task @(@{ Script = { } }) } | Should -Throw '*needs a Name*'
    }

    It 'refuses a step with no script' {
        { Invoke-AnsiTask -Task @(@{ Name = 'x' }) } | Should -Throw '*needs a Script*'
    }
}

Describe 'Invoke-AnsiTask — failure' {
    BeforeEach { Reset-AnsiTest }

    It 'marks the failed step and rethrows' {
        $out = ''
        { $out = Invoke-Ansi { Invoke-AnsiTask 'build' { throw 'boom' } } } | Should -Throw 'boom'
    }

    It 'stops at the first failure' {
        $script:reached = $false
        {
            $null = Invoke-AnsiLines {
                Invoke-AnsiTask -Task @(
                    @{ Name = 'bad'; Script = { throw 'boom' } }
                    @{ Name = 'after'; Script = { $script:reached = $true } }
                )
            }
        } | Should -Throw 'boom'
        $script:reached | Should -BeFalse
    }

    It 'keeps going with -ContinueOnError' {
        $script:reached = $false
        $null = Invoke-AnsiLines {
            Invoke-AnsiTask -ContinueOnError -Task @(
                @{ Name = 'bad'; Script = { throw 'boom' } }
                @{ Name = 'after'; Script = { $script:reached = $true } }
            )
        }
        $script:reached | Should -BeTrue
    }

    It 'draws the failed mark' {
        $out = Invoke-AnsiText { Invoke-AnsiTask -ContinueOnError -Task @(@{ Name = 'bad'; Script = { throw 'boom' } }) }
        $out | Should -Match ([regex]::Escape("$script:Failed bad"))
    }
}

Describe 'Invoke-AnsiTask — results' {
    BeforeEach { Reset-AnsiTest }

    It 'emits nothing extra without -PassThru' {
        $result = & { Invoke-AnsiTask 'build' { } } 6>$null
        $result | Should -BeNullOrEmpty
    }

    It 'emits one result per step with -PassThru' {
        $result = & {
            Invoke-AnsiTask -PassThru -Task @(
                @{ Name = 'a'; Script = { } }
                @{ Name = 'b'; Script = { } }
            )
        } 6>$null
        $result.Count | Should -Be 2
        $result[0].Name | Should -BeExactly 'a'
        $result[0].Ok | Should -BeTrue
        $result[0].Duration | Should -BeOfType [TimeSpan]
    }

    It 'reports a failed step and the ones it never reached' {
        $result = & {
            Invoke-AnsiTask -ContinueOnError -PassThru -Task @(
                @{ Name = 'bad'; Script = { throw 'boom' } }
                @{ Name = 'good'; Script = { } }
            )
        } 6>$null
        $result[0].Ok | Should -BeFalse
        $result[0].Error.Exception.Message | Should -BeExactly 'boom'
        $result[1].Ok | Should -BeTrue
    }

    It 'is tagged PwshAnsi.TaskResult' {
        $result = & { Invoke-AnsiTask 'x' { } -PassThru } 6>$null
        $result.PSObject.TypeNames | Should -Contain 'PwshAnsi.TaskResult'
    }
}

Describe 'Invoke-AnsiTask — what it shows' {
    BeforeEach { Reset-AnsiTest }

    It 'prints text and no bar when output is redirected' {
        # Every bar state would be its own line in a log, so a redirected run only
        # gets the finished lines.
        $out = Invoke-AnsiText { Invoke-AnsiTask 'build' { } }
        $out | Should -Match ([regex]::Escape($script:Done))
        $out | Should -Not -Match ([regex]::Escape($script:Full))
        $out | Should -Not -Match ([regex]::Escape($script:Running))
    }

    It 'draws a bar on a live terminal' {
        Set-AnsiTestLive -Value $true
        $out = Invoke-Ansi { Invoke-AnsiTask 'build' { } }
        $out | Should -Match ([regex]::Escape($script:Full))
    }

    It 'shows the running step while it runs on a live terminal' {
        Set-AnsiTestLive -Value $true
        $out = Invoke-AnsiText { Invoke-AnsiTask 'build' { } }
        $out | Should -Match ([regex]::Escape("$script:Running build"))
    }

    It 'redraws in place rather than appending' {
        Set-AnsiTestLive -Value $true
        $out = Invoke-Ansi { Invoke-AnsiTask 'build' { } }
        $out | Should -Match ([regex]::Escape("$script:Esc[1A"))    # cursor up
        $out | Should -Match ([regex]::Escape("$script:Esc[2K"))    # clear line
    }

    It 'shows only text with -Show Text' {
        Set-AnsiTestLive -Value $true
        $out = Invoke-AnsiText { Invoke-AnsiTask 'build' { } -Show Text }
        $out | Should -Match ([regex]::Escape($script:Done))
        $out | Should -Not -Match ([regex]::Escape($script:Full))
    }

    It 'shows only the bar with -Show Bar' {
        Set-AnsiTestLive -Value $true
        $out = Invoke-AnsiText { Invoke-AnsiTask 'build' { } -Show Bar -KeepBar }
        $out | Should -Match ([regex]::Escape($script:Full))
        $out | Should -Not -Match ([regex]::Escape($script:Done))
    }

    It 'counts the steps in the bar' {
        Set-AnsiTestLive -Value $true
        $out = Invoke-Ansi {
            Invoke-AnsiTask -Show Bar -KeepBar -Task @(
                @{ Name = 'a'; Script = { } }
                @{ Name = 'b'; Script = { } }
                @{ Name = 'c'; Script = { } }
            )
        }
        $out | Should -Match '3/3'
    }

    It 'drops the count with -ProgressShow Percent' {
        Set-AnsiTestLive -Value $true
        $out = Invoke-Ansi {
            Invoke-AnsiTask -Show Bar -KeepBar -ProgressShow Percent -Task @(
                @{ Name = 'a'; Script = { } }
                @{ Name = 'b'; Script = { } }
            )
        }
        $out | Should -Match '100%'
        $out | Should -Not -Match '2/2'
    }

    It 'keeps the count alone with -ProgressShow Count' {
        Set-AnsiTestLive -Value $true
        $out = Invoke-Ansi {
            Invoke-AnsiTask -Show Bar -KeepBar -ProgressShow Count -Task @(
                @{ Name = 'a'; Script = { } }
                @{ Name = 'b'; Script = { } }
            )
        }
        $out | Should -Match '2/2'
        $out | Should -Not -Match '%'
    }

    It 'leaves the bar bare with -ProgressShow None' {
        Set-AnsiTestLive -Value $true
        $out = Invoke-Ansi { Invoke-AnsiTask 'build' { } -Show Bar -KeepBar -ProgressShow None }
        $out | Should -Match ([regex]::Escape($script:Full))
        $out | Should -Not -Match '%'
        $out | Should -Not -Match '1/1'
    }

    It 'hides the fraction a step reports when -ProgressShow is Percent' {
        Set-AnsiTestLive -Value $true
        $out = Invoke-Ansi {
            Invoke-AnsiTask 'download' { param($task) $task.Update(1, 2) } -Show Bar -KeepBar -ProgressShow Percent
        }
        $out | Should -Not -Match '0\.5/1'
    }

    It 'draws the bar in the style it was given' {
        Set-AnsiTestLive -Value $true
        $out = Invoke-Ansi { Invoke-AnsiTask 'build' { } -Show Bar -Style Ascii -KeepBar }
        $out | Should -Match '#'
    }

    It 'sizes the bar with -Width' {
        Set-AnsiTestLive -Value $true
        $lines = Invoke-AnsiLines { Invoke-AnsiTask 'build' { } -Show Bar -Width 24 -KeepBar }
        $bar = @($lines | Where-Object { $_ -match [regex]::Escape($script:Full) })[-1]
        ($bar -replace "$([char]27)\[[0-9;]*[A-Za-z]", '').Length | Should -Be 24
    }

    It 'clears the bar when it finishes' {
        Set-AnsiTestLive -Value $true
        $lines = Invoke-AnsiLines { Invoke-AnsiTask 'build' { } -Show Bar }
        # The last thing written is the clear, not a bar.
        $lines[-1] | Should -Match ([regex]::Escape("$script:Esc[2K"))
    }

    It 'leaves the bar behind with -KeepBar' {
        Set-AnsiTestLive -Value $true
        $lines = Invoke-AnsiLines { Invoke-AnsiTask 'build' { } -Show Bar -KeepBar }
        $lines[-1] | Should -Match ([regex]::Escape($script:Full))
    }
}

Describe 'Invoke-AnsiTask — the task control object' {
    BeforeEach { Reset-AnsiTest }

    It 'hands the step its own name and position' {
        $script:seen = $null
        $null = Invoke-AnsiLines {
            Invoke-AnsiTask -Task @(
                @{ Name = 'first'; Script = { } }
                @{ Name = 'second'; Script = { param($task) $script:seen = $task } }
            )
        }
        $script:seen.Name | Should -BeExactly 'second'
        $script:seen.Index | Should -Be 1
        $script:seen.Count | Should -Be 2
    }

    It 'moves the bar with Update' {
        Set-AnsiTestLive -Value $true
        $lines = Invoke-AnsiLines {
            Invoke-AnsiTask 'copy' { param($task) $task.Update(1, 2) } -Show Bar -Width 20 -KeepBar
        }
        # Half of one step of one: a bar drawn at 50% between the empty and full ones.
        $bars = @($lines | Where-Object { $_ -match [regex]::Escape($script:Full) })
        $bars.Count | Should -BeGreaterThan 1
    }

    It 'clamps what Update is given' {
        Set-AnsiTestLive -Value $true
        {
            $null = Invoke-AnsiLines {
                Invoke-AnsiTask 'copy' { param($task) $task.Update(-5, 2); $task.Update(99, 2) } -Show Bar
            }
        } | Should -Not -Throw
    }

    It 'prints a message with Write' {
        $out = Invoke-Ansi { Invoke-AnsiTask 'copy' { param($task) $task.Write('halfway') } }
        $out | Should -Match 'halfway'
    }

    It 'is reachable as $args[0] without a param block' {
        $out = Invoke-Ansi { Invoke-AnsiTask 'copy' { $args[0].Write('from args') } }
        $out | Should -Match 'from args'
    }
}

Describe 'Invoke-AnsiTask — module surface' {
    BeforeEach { Reset-AnsiTest }

    It 'refuses to nest' {
        {
            $null = Invoke-AnsiLines {
                Invoke-AnsiTask 'outer' { Invoke-AnsiTask 'inner' { } }
            }
        } | Should -Throw '*does not nest*'
    }

    It 'runs again after a failure' {
        { $null = Invoke-AnsiLines { Invoke-AnsiTask 'bad' { throw 'boom' } } } | Should -Throw 'boom'
        $out = Invoke-AnsiText { Invoke-AnsiTask 'after' { } }
        $out | Should -Match ([regex]::Escape("$script:Done after"))
    }

    It 'rejects an unknown -Show' {
        { Invoke-AnsiTask 'x' { } -Show Fireworks } | Should -Throw
    }

    It 'exports one function' {
        (Get-Module Invoke-AnsiTask).ExportedFunctions.Keys | Should -Be @('Invoke-AnsiTask')
    }
}
