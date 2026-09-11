#Requires -Version 7.2
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

# Ansi.Input.Tests.ps1
# The input layer the Read-Ansi* prompts share: key bursts, and the field model a
# text prompt edits against. Both are pure enough to test without a console - the
# console seams arrive as scriptblocks.

BeforeAll {
    $script:Input = Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'src' 'Ansi.Input.psm1') `
        -Force -DisableNameChecking -PassThru

    function New-TestKey {
        param([char]$Char = "`0", [System.ConsoleKey]$Key = [System.ConsoleKey]::A)
        return [System.ConsoleKeyInfo]::new($Char, $Key, $false, $false, $false)
    }

    function New-CharKeys {
        param([string]$Text)
        return @($Text.ToCharArray() | ForEach-Object { New-TestKey -Char $_ -Key ([System.ConsoleKey]::A) })
    }

    function Invoke-Burst {
        param([object[]]$Keys, [scriptblock]$StopOn = $null)
        return & $script:Input {
            param($keys, $stopOn)
            # The seams are invoked from inside the module, so they carry the queue and its
            # position with them; a closure captures locals, not $script: variables.
            $queue = [PSCustomObject]@{ Keys = @($keys); Index = 0 }
            $read = { if ($queue.Index -ge $queue.Keys.Count) { return $null }; $k = $queue.Keys[$queue.Index]; $queue.Index++; return $k }.GetNewClosure()
            $available = { $queue.Index -lt $queue.Keys.Count }.GetNewClosure()
            Read-AnsiKeyBurst -ReadKey $read -KeyAvailable $available -StopOn $stopOn
        } $Keys $StopOn
    }

    function Invoke-Field {
        param([string]$Start, [object[]]$Keys)
        return & $script:Input {
            param($start, $keys)
            $state = New-AnsiFieldState -Text $start
            foreach ($key in $keys) { $state = Update-AnsiFieldState -State $state -Key $key }
            return $state
        } $Start $Keys
    }

    function Get-View {
        param([string]$Text, [int]$Caret, [int]$Window, [int]$Width)
        return & $script:Input {
            param($t, $c, $w, $width)
            Get-AnsiFieldView -State ([PSCustomObject]@{ Text = $t; Caret = $c; Window = $w }) -Width $width
        } $Text $Caret $Window $Width
    }
}

Describe 'Read-AnsiKeyBurst' {
    It 'takes everything already queued in one go' {
        $burst = Invoke-Burst -Keys (New-CharKeys 'paste')
        @($burst).Count | Should -Be 5
    }

    It 'returns nothing when the first read is empty' {
        $burst = Invoke-Burst -Keys @()
        @($burst).Count | Should -Be 0
    }

    It 'stops at the key that ends the interaction' {
        $keys = @((New-CharKeys 'ab') + @(New-TestKey -Key ([System.ConsoleKey]::Enter)) + (New-CharKeys 'cd'))
        $burst = Invoke-Burst -Keys $keys -StopOn { param($k) [string]$k.Key -eq 'Enter' }

        @($burst).Count | Should -Be 3
        [string]$burst[-1].Key | Should -BeExactly 'Enter'
    }

    It 'stops even when the terminating key comes first' {
        $keys = @(@(New-TestKey -Key ([System.ConsoleKey]::Escape)) + (New-CharKeys 'xy'))
        $burst = Invoke-Burst -Keys $keys -StopOn { param($k) [string]$k.Key -eq 'Escape' }
        @($burst).Count | Should -Be 1
    }
}

Describe 'Update-AnsiFieldState' {
    It 'types at the caret' {
        $state = Invoke-Field -Start '' -Keys (New-CharKeys 'abc')
        $state.Text | Should -BeExactly 'abc'
        $state.Caret | Should -Be 3
    }

    It 'inserts where the caret sits, not at the end' {
        $keys = @(@(New-TestKey -Key ([System.ConsoleKey]::LeftArrow)) + (New-CharKeys 'X'))
        $state = Invoke-Field -Start 'ab' -Keys $keys
        $state.Text | Should -BeExactly 'aXb'
        $state.Caret | Should -Be 2
    }

    It 'backspaces the character before the caret' {
        $keys = @(
            (New-TestKey -Key ([System.ConsoleKey]::LeftArrow))
            (New-TestKey -Key ([System.ConsoleKey]::Backspace))
        )
        $state = Invoke-Field -Start 'abc' -Keys $keys
        $state.Text | Should -BeExactly 'ac'
        $state.Caret | Should -Be 1
    }

    It 'stops the caret at both ends' {
        $left = Invoke-Field -Start 'ab' -Keys @(
            (New-TestKey -Key ([System.ConsoleKey]::LeftArrow))
            (New-TestKey -Key ([System.ConsoleKey]::LeftArrow))
            (New-TestKey -Key ([System.ConsoleKey]::LeftArrow))
        )
        $left.Caret | Should -Be 0

        $right = Invoke-Field -Start 'ab' -Keys @((New-TestKey -Key ([System.ConsoleKey]::RightArrow)))
        $right.Caret | Should -Be 2
    }

    It 'ignores control characters' {
        $state = Invoke-Field -Start 'ab' -Keys @((New-TestKey -Char "`t" -Key ([System.ConsoleKey]::Tab)))
        $state.Text | Should -BeExactly 'ab'
    }
}

Describe 'Get-AnsiFieldDisplay' {
    It 'draws a stored newline as a two-column escape' {
        $display = & $script:Input { param($t, $c) Get-AnsiFieldDisplay -Text $t -Caret $c } "ab`ncd" 5
        $display.Text | Should -BeExactly ('ab' + ([char]92 + 'n') + 'cd')
        $display.CaretColumn | Should -Be 6
    }

    It 'drops a carriage return so CRLF draws once' {
        $display = & $script:Input { param($t, $c) Get-AnsiFieldDisplay -Text $t -Caret $c } "a`r`nb" 4
        $display.Text | Should -BeExactly ('a' + ([char]92 + 'n') + 'b')
    }
}

Describe 'Get-AnsiFieldView' {
    It 'shows the whole text when it fits' {
        $view = Get-View -Text 'abc' -Caret 3 -Window 0 -Width 10
        $view.Visible | Should -BeExactly 'abc'
        $view.CaretColumn | Should -Be 3
        $view.Window | Should -Be 0
    }

    It 'scrolls right to keep the caret on screen' {
        $view = Get-View -Text 'abcdefghij' -Caret 10 -Window 0 -Width 4
        $view.Window | Should -Be 7
        $view.Visible | Should -BeExactly 'hij'
        $view.CaretColumn | Should -Be 3
    }

    It 'scrolls back left when the caret moves out of the window' {
        $view = Get-View -Text 'abcdefghij' -Caret 1 -Window 6 -Width 4
        $view.Window | Should -Be 1
        $view.CaretColumn | Should -Be 0
        $view.Visible | Should -BeExactly 'bcde'
    }

    It 'reports that the text is longer than the field' {
        (Get-View -Text 'abcdefghij' -Caret 0 -Window 0 -Width 4).Scrolled | Should -BeTrue
        (Get-View -Text 'abc' -Caret 0 -Window 0 -Width 10).Scrolled | Should -BeFalse
    }

    It 'counts a newline as the two columns it is drawn in' {
        $view = Get-View -Text "ab`ncd" -Caret 5 -Window 0 -Width 10
        $view.Visible | Should -BeExactly ('ab' + ([char]92 + 'n') + 'cd')
        $view.CaretColumn | Should -Be 6
    }

    It 'handles an empty field' {
        $view = Get-View -Text '' -Caret 0 -Window 0 -Width 5
        $view.Visible | Should -BeExactly ''
        $view.CaretColumn | Should -Be 0
    }
}
