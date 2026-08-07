#Requires -Version 7.2
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

# Start-AnsiTitleAnimation.Tests.ps1
# Pester 5 tests for Start-AnsiTitleAnimation, Stop-AnsiTitleAnimation, and
# Invoke-AnsiTitleAnimation.
#
# The terminal seams (Test-AnsiTitleSupported, Get-AnsiTitleCurrent, Set-AnsiTitle)
# and the worker (Start-AnsiTitleWorker, Stop-AnsiTitleWorker) are replaced inside the
# module scope, so the frames and the lifecycle are asserted without a second
# runspace, a real title bar, or any sleeping.

BeforeAll {
    $script:src = Join-Path (Split-Path -Parent $PSScriptRoot) 'src'
    Import-Module (Join-Path $script:src 'Start-AnsiTitleAnimation.psm1') -Force -DisableNameChecking
    $script:AnsiModule = Get-Module Start-AnsiTitleAnimation

    & $script:AnsiModule {
        $script:AnsiTestSupported = $true
        $script:AnsiTestCurrent = 'original title'
        $script:AnsiTestSet = [System.Collections.Generic.List[string]]::new()
        $script:AnsiTestWorkers = [System.Collections.Generic.List[object]]::new()

        Set-Item function:script:Test-AnsiTitleSupported -Value { $script:AnsiTestSupported }
        Set-Item function:script:Get-AnsiTitleCurrent -Value { $script:AnsiTestCurrent }
        Set-Item function:script:Set-AnsiTitle -Value {
            param([Parameter(Mandatory)][AllowEmptyString()][string]$Title)
            $null = $script:AnsiTestSet.Add($Title)
        }
        Set-Item function:script:Start-AnsiTitleWorker -Value {
            param(
                [Parameter(Mandatory)][string[]]$Titles,
                [Parameter(Mandatory)][int]$Interval,
                [AllowEmptyString()][string]$Original
            )
            $state = [PSCustomObject]@{
                Titles   = $Titles
                Interval = $Interval
                Original = $Original
                Stopped  = $false
            }
            $null = $script:AnsiTestWorkers.Add($state)
            return $state
        }
        Set-Item function:script:Stop-AnsiTitleWorker -Value {
            param([Parameter(Mandatory)][object]$State)
            $State.Stopped = $true
        }
    }

    function Reset-AnsiTest {
        param([bool]$Supported = $true, [string]$Current = 'original title')
        & $script:AnsiModule {
            param($supported, $current)
            $script:AnsiTestSupported = $supported
            $script:AnsiTestCurrent = $current
            $script:AnsiTestSet.Clear()
            $script:AnsiTestWorkers.Clear()
            $script:AnsiTitleState = $null
        } $Supported $Current
    }

    # Values come back inside a carrier object: `& $module { , @(...) }` would be
    # unrolled by the pipeline, turning a one-item list into the item and a string
    # into its characters.
    function Get-AnsiTestWorker {
        $carrier = & $script:AnsiModule { [PSCustomObject]@{ Value = @($script:AnsiTestWorkers.ToArray()) } }
        return , @($carrier.Value)
    }

    function Get-AnsiTestSetTitle {
        $carrier = & $script:AnsiModule { [PSCustomObject]@{ Value = @($script:AnsiTestSet.ToArray()) } }
        return , @($carrier.Value)
    }

    function Get-AnsiTestFrame {
        $carrier = & $script:AnsiModule {
            # Assignment first: Get-AnsiTitleFrame returns the array comma-wrapped, so
            # @(call) would nest it one level deeper.
            $built = Get-AnsiTitleFrame
            [PSCustomObject]@{ Value = @($built) }
        }
        return , @($carrier.Value)
    }

    # ⠋, the first of the ten braille frames.
    $script:FirstFrame = [string][char]0x280B
}

Describe 'Start-AnsiTitleAnimation — frames' {
    BeforeEach { Reset-AnsiTest }

    It 'turns the ten braille dot frames' {
        $frames = Get-AnsiTestFrame
        $frames.Count | Should -Be 10
        ($frames -join '') | Should -BeExactly (
            [string]::new([char[]](0x280B, 0x2819, 0x2839, 0x2838, 0x283C, 0x2834, 0x2826, 0x2827, 0x2807, 0x280F)))
    }

    It 'keeps every frame to one character the console can set' {
        # Nothing above U+FFFF: astral characters (emoji) do not survive a console
        # title, they arrive as a question mark. One char per frame also keeps the
        # text beside it from shifting.
        foreach ($frame in (Get-AnsiTestFrame)) {
            $frame.Length | Should -Be 1
            [char]::IsSurrogate($frame[0]) | Should -BeFalse
        }
    }

    It 'is one animation with nothing to choose' {
        # No -Style, no -Frames, no -Width, no millisecond dial: the dots are the
        # animation and -Speed names the pace.
        foreach ($name in 'Style', 'Frames', 'Width', 'Interval') {
            (Get-Command Start-AnsiTitleAnimation).Parameters.Keys | Should -Not -Contain $name
            (Get-Command Invoke-AnsiTitleAnimation).Parameters.Keys | Should -Not -Contain $name
        }
    }

    It 'turns at a calm quarter second by default' {
        $null = Start-AnsiTitleAnimation 'x' -Force
        (Get-AnsiTestWorker)[0].Interval | Should -Be 250
    }

    It 'turns <Speed> at <Milliseconds>ms a frame' -ForEach @(
        @{ Speed = 'Slow'; Milliseconds = 500 }
        @{ Speed = 'Normal'; Milliseconds = 250 }
        @{ Speed = 'Fast'; Milliseconds = 100 }
    ) {
        $null = Start-AnsiTitleAnimation 'x' -Speed $Speed -Force
        (Get-AnsiTestWorker)[0].Interval | Should -Be $Milliseconds
    }

    It 'rejects a speed that is not one of the three' {
        { Start-AnsiTitleAnimation 'x' -Speed Turbo -Force } | Should -Throw
        { Start-AnsiTitleAnimation 'x' -Speed 250 -Force } | Should -Throw
    }
}

Describe 'Start-AnsiTitleAnimation — the titles it animates' {
    BeforeEach { Reset-AnsiTest }

    It 'puts the dots before the text by default' {
        $null = Start-AnsiTitleAnimation 'building' -Force
        $worker = (Get-AnsiTestWorker)[0]
        $worker.Titles[0] | Should -BeExactly ($script:FirstFrame + ' building')
    }

    It 'puts the dots after the text with -FrameLast' {
        $null = Start-AnsiTitleAnimation 'building' -FrameLast -Force
        $worker = (Get-AnsiTestWorker)[0]
        $worker.Titles[0] | Should -BeExactly ('building ' + $script:FirstFrame)
    }

    It 'animates the dots alone when there is no text' {
        $null = Start-AnsiTitleAnimation -Force
        $worker = (Get-AnsiTestWorker)[0]
        $worker.Titles[0] | Should -BeExactly $script:FirstFrame
    }

    It 'keeps the text in place as the dots turn' {
        $null = Start-AnsiTitleAnimation 'building' -Force
        foreach ($title in (Get-AnsiTestWorker)[0].Titles) {
            $title.Substring(1) | Should -BeExactly ' building'
        }
    }

    It 'builds one title per frame' {
        $null = Start-AnsiTitleAnimation 'x' -Force
        (Get-AnsiTestWorker)[0].Titles.Count | Should -Be 10
    }

    It 'passes the speed to the worker' {
        $null = Start-AnsiTitleAnimation 'x' -Speed Fast -Force
        (Get-AnsiTestWorker)[0].Interval | Should -Be 100
    }

    It 'remembers the title it found' {
        Reset-AnsiTest -Current 'my shell'
        $null = Start-AnsiTitleAnimation 'x' -Force
        (Get-AnsiTestWorker)[0].Original | Should -BeExactly 'my shell'
    }
}

Describe 'Start-AnsiTitleAnimation — lifecycle' {
    BeforeEach { Reset-AnsiTest }

    It 'returns $true and starts one worker' {
        Start-AnsiTitleAnimation 'x' -Force | Should -BeTrue
        (Get-AnsiTestWorker).Count | Should -Be 1
    }

    It 'refuses a second animation while one is running' {
        $null = Start-AnsiTitleAnimation 'first' -Force
        { Start-AnsiTitleAnimation 'second' -Force } | Should -Throw '*already running*'
    }

    It 'can start again after stopping' {
        $null = Start-AnsiTitleAnimation 'first' -Force
        Stop-AnsiTitleAnimation
        Start-AnsiTitleAnimation 'second' -Force | Should -BeTrue
        (Get-AnsiTestWorker).Count | Should -Be 2
    }

    It 'does nothing when there is no interactive terminal' {
        Reset-AnsiTest -Supported $false
        Start-AnsiTitleAnimation 'x' | Should -BeFalse
        (Get-AnsiTestWorker).Count | Should -Be 0
    }

    It 'animates anyway with -Force' {
        Reset-AnsiTest -Supported $false
        Start-AnsiTitleAnimation 'x' -Force | Should -BeTrue
        (Get-AnsiTestWorker).Count | Should -Be 1
    }
}

Describe 'Stop-AnsiTitleAnimation' {
    BeforeEach { Reset-AnsiTest }

    It 'stops the worker' {
        $null = Start-AnsiTitleAnimation 'x' -Force
        Stop-AnsiTitleAnimation
        (Get-AnsiTestWorker)[0].Stopped | Should -BeTrue
    }

    It 'puts the original title back' {
        Reset-AnsiTest -Current 'my shell'
        $null = Start-AnsiTitleAnimation 'x' -Force
        Stop-AnsiTitleAnimation
        (Get-AnsiTestSetTitle)[-1] | Should -BeExactly 'my shell'
    }

    It 'leaves a given -Title behind instead' {
        $null = Start-AnsiTitleAnimation 'x' -Force
        Stop-AnsiTitleAnimation -Title 'done'
        (Get-AnsiTestSetTitle)[-1] | Should -BeExactly 'done'
    }

    It 'accepts an empty -Title' {
        $null = Start-AnsiTitleAnimation 'x' -Force
        Stop-AnsiTitleAnimation -Title ''
        (Get-AnsiTestSetTitle)[-1] | Should -BeExactly ''
    }

    It 'does nothing when no animation is running' {
        Stop-AnsiTitleAnimation
        (Get-AnsiTestSetTitle).Count | Should -Be 0
    }

    It 'is safe to call twice' {
        $null = Start-AnsiTitleAnimation 'x' -Force
        Stop-AnsiTitleAnimation
        Stop-AnsiTitleAnimation
        (Get-AnsiTestSetTitle).Count | Should -Be 1
    }
}

Describe 'Invoke-AnsiTitleAnimation' {
    BeforeEach { Reset-AnsiTest }

    It 'returns what the scriptblock returned' {
        Invoke-AnsiTitleAnimation { 21 * 2 } 'working' -Force | Should -Be 42
    }

    It 'passes the whole output through' {
        Invoke-AnsiTitleAnimation { 1; 2; 3 } 'working' -Force | Should -Be @(1, 2, 3)
    }

    It 'animates while it runs and stops afterwards' {
        $null = Invoke-AnsiTitleAnimation { 'x' } 'working' -Force
        $worker = (Get-AnsiTestWorker)[0]
        $worker.Titles[0] | Should -BeExactly ($script:FirstFrame + ' working')
        $worker.Stopped | Should -BeTrue
    }

    It 'restores the title even when the scriptblock throws' {
        Reset-AnsiTest -Current 'my shell'
        { Invoke-AnsiTitleAnimation { throw 'boom' } 'working' -Force } | Should -Throw 'boom'
        (Get-AnsiTestWorker)[0].Stopped | Should -BeTrue
        (Get-AnsiTestSetTitle)[-1] | Should -BeExactly 'my shell'
    }

    It 'leaves -FinalTitle behind' {
        $null = Invoke-AnsiTitleAnimation { 'x' } 'working' -Force -FinalTitle 'built'
        (Get-AnsiTestSetTitle)[-1] | Should -BeExactly 'built'
    }

    It 'forwards -Speed and -FrameLast' {
        $null = Invoke-AnsiTitleAnimation { 'x' } 'working' -Speed Slow -FrameLast -Force
        $worker = (Get-AnsiTestWorker)[0]
        $worker.Titles[0] | Should -BeExactly ('working ' + $script:FirstFrame)
        $worker.Interval | Should -Be 500
    }

    It 'runs the scriptblock even without a terminal' {
        Reset-AnsiTest -Supported $false
        Invoke-AnsiTitleAnimation { 'ran' } 'working' | Should -BeExactly 'ran'
        (Get-AnsiTestWorker).Count | Should -Be 0
    }
}

Describe 'Start-AnsiTitleAnimation — module surface' {
    It 'exports the three title functions' {
        (Get-Module Start-AnsiTitleAnimation).ExportedFunctions.Keys | Sort-Object |
            Should -Be @('Invoke-AnsiTitleAnimation', 'Start-AnsiTitleAnimation', 'Stop-AnsiTitleAnimation')
    }
}
