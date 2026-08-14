#Requires -Version 7.2
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

# Read-AnsiSelection.Tests.ps1
# Pester 5 tests for Read-AnsiSelection.
#
# The console seams are replaced inside each module scope, so a scripted key list
# drives the prompt: no keyboard, no waiting. Cursor-control sequences are stripped
# from the captured output, leaving the rows each redraw painted.

BeforeAll {
    $script:src = Join-Path (Split-Path -Parent $PSScriptRoot) 'src'
    Import-Module (Join-Path $script:src 'Read-AnsiSelection.psm1') -Force -DisableNameChecking

    foreach ($name in 'Read-AnsiSelection') {
        & (Get-Module $name) {
            $script:AnsiKeys = @()
            $script:AnsiKeyIndex = 0
            $script:AnsiTestNoColor = $false
            $script:AnsiInteractive = $true

            Set-Item function:script:Test-AnsiInteractive -Value { $script:AnsiInteractive }
            Set-Item function:script:Test-AnsiNoColor -Value { $script:AnsiTestNoColor }
            Set-Item function:script:Test-AnsiKeyAvailable -Value { $script:AnsiKeyIndex -lt $script:AnsiKeys.Count }
            Set-Item function:script:Read-AnsiKeyInfo -Value {
                if ($script:AnsiKeyIndex -ge $script:AnsiKeys.Count) { return $null }
                $key = $script:AnsiKeys[$script:AnsiKeyIndex]
                $script:AnsiKeyIndex++
                return $key
            }
            Set-Item function:script:Start-AnsiWait -Value { param([int]$Milliseconds = 25) }
        }
    }

    function New-Key {
        param([Parameter(Mandatory)][System.ConsoleKey]$Key)
        return [System.ConsoleKeyInfo]::new("`0", $Key, $false, $false, $false)
    }

    function New-Char {
        param([Parameter(Mandatory)][char]$Char)
        return [System.ConsoleKeyInfo]::new($Char, [System.ConsoleKey]::A, $false, $false, $false)
    }

    function Set-AnsiTestKeys {
        param(
            [Parameter(Mandatory)][string]$Module,
            [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Keys
        )
        & (Get-Module $Module) { param($k) $script:AnsiKeys = $k; $script:AnsiKeyIndex = 0 } $Keys
    }

    function Set-AnsiTestNoColor {
        param([Parameter(Mandatory)][string]$Module, [Parameter(Mandatory)][bool]$Value)
        & (Get-Module $Module) { param($v) $script:AnsiTestNoColor = $v } $Value
    }

    function Set-AnsiTestInteractive {
        param([Parameter(Mandatory)][string]$Module, [Parameter(Mandatory)][bool]$Value)
        & (Get-Module $Module) { param($v) $script:AnsiInteractive = $v } $Value
    }

    # Returns the chosen value, the painted rows, and the raw stream. Records that
    # are nothing but cursor control (the in-place redraw) are kept out of Rows so
    # row indexes match what the user sees, but stay in Raw for assertions about it.
    function Invoke-Prompt {
        param([Parameter(Mandatory)][scriptblock]$Sb)
        $rows = [System.Collections.Generic.List[string]]::new()
        $raw = [System.Text.StringBuilder]::new()
        $value = $null
        $sawValue = $false

        foreach ($record in @(& $Sb 6>&1)) {
            if ($record -is [System.Management.Automation.InformationRecord]) {
                $text = [string]$record.ToString()
                $null = $raw.Append($text)
                if ($text -match "^(?:`e\[\d*[AG]|`e\[2K)+$") { continue }
                $null = $rows.Add($text)
            } else {
                $value = $record
                $sawValue = $true
            }
        }
        return [PSCustomObject]@{
            Value = $value; HasValue = $sawValue; Rows = $rows.ToArray(); Raw = $raw.ToString()
        }
    }

    function Remove-Ansi {
        param([AllowEmptyString()][string]$Text)
        return ($Text -replace "`e\[[\d;]*m", '')
    }

    # The rows of the last redraw: everything after the final title row.
    function Get-FinalFrame {
        param([Parameter(Mandatory)][object]$Result, [Parameter(Mandatory)][string]$Title)
        $plain = @($Result.Rows | ForEach-Object { Remove-Ansi $_ })
        $last = -1
        for ($i = 0; $i -lt $plain.Count; $i++) { if ($plain[$i] -eq $Title) { $last = $i } }
        if ($last -lt 0) { return , @() }
        return , @($plain[$last..($plain.Count - 1)])
    }

    $script:Fruit = @('apple', 'banana', 'cherry', 'date', 'elderberry')
    $script:Cursor = [string][char]0x203A   # ›
    $script:Check = [string][char]0x2713    # ✓

    # Rows: 0 Berries, 1 strawberry, 2 raspberry, 3 Citrus, 4 lemon, 5 lime.
    $script:Groups = @(
        @{ Name = 'Berries'; Choices = @('strawberry', 'raspberry') }
        @{ Name = 'Citrus'; Choices = @('lemon', 'lime') }
    )
}

Describe 'Read-AnsiSelection — moving and choosing' {
    It 'starts on the first choice' {
        Set-AnsiTestKeys -Module Read-AnsiSelection -Keys @((New-Key -Key Enter))
        $result = Invoke-Prompt { Read-AnsiSelection 'Pick' $script:Fruit }
        $result.Value | Should -BeExactly 'apple'
    }

    It 'moves down with the arrow keys' {
        Set-AnsiTestKeys -Module Read-AnsiSelection -Keys @(
            (New-Key -Key DownArrow), (New-Key -Key DownArrow), (New-Key -Key Enter)
        )
        $result = Invoke-Prompt { Read-AnsiSelection 'Pick' $script:Fruit }
        $result.Value | Should -BeExactly 'cherry'
    }

    It 'moves back up' {
        Set-AnsiTestKeys -Module Read-AnsiSelection -Keys @(
            (New-Key -Key DownArrow), (New-Key -Key DownArrow), (New-Key -Key UpArrow), (New-Key -Key Enter)
        )
        $result = Invoke-Prompt { Read-AnsiSelection 'Pick' $script:Fruit }
        $result.Value | Should -BeExactly 'banana'
    }

    It 'stops at the top' {
        Set-AnsiTestKeys -Module Read-AnsiSelection -Keys @(
            (New-Key -Key UpArrow), (New-Key -Key UpArrow), (New-Key -Key Enter)
        )
        $result = Invoke-Prompt { Read-AnsiSelection 'Pick' $script:Fruit }
        $result.Value | Should -BeExactly 'apple'
    }

    It 'stops at the bottom' {
        $keys = @()
        for ($i = 0; $i -lt 9; $i++) { $keys += (New-Key -Key DownArrow) }
        $keys += (New-Key -Key Enter)
        Set-AnsiTestKeys -Module Read-AnsiSelection -Keys $keys
        $result = Invoke-Prompt { Read-AnsiSelection 'Pick' $script:Fruit }
        $result.Value | Should -BeExactly 'elderberry'
    }

    It 'jumps with Home and End' {
        Set-AnsiTestKeys -Module Read-AnsiSelection -Keys @((New-Key -Key End), (New-Key -Key Enter))
        (Invoke-Prompt { Read-AnsiSelection 'Pick' $script:Fruit }).Value | Should -BeExactly 'elderberry'

        Set-AnsiTestKeys -Module Read-AnsiSelection -Keys @(
            (New-Key -Key End), (New-Key -Key Home), (New-Key -Key Enter)
        )
        (Invoke-Prompt { Read-AnsiSelection 'Pick' $script:Fruit }).Value | Should -BeExactly 'apple'
    }

    It 'pages with PageDown and PageUp' {
        Set-AnsiTestKeys -Module Read-AnsiSelection -Keys @((New-Key -Key PageDown), (New-Key -Key Enter))
        (Invoke-Prompt { Read-AnsiSelection 'Pick' $script:Fruit -PageSize 2 }).Value | Should -BeExactly 'cherry'

        Set-AnsiTestKeys -Module Read-AnsiSelection -Keys @(
            (New-Key -Key PageDown), (New-Key -Key PageUp), (New-Key -Key Enter)
        )
        (Invoke-Prompt { Read-AnsiSelection 'Pick' $script:Fruit -PageSize 2 }).Value | Should -BeExactly 'apple'
    }

    It 'moves with j and k as well' {
        Set-AnsiTestKeys -Module Read-AnsiSelection -Keys @((New-Char -Char 'j'), (New-Char -Char 'j'), (New-Char -Char 'k'), (New-Key -Key Enter))
        (Invoke-Prompt { Read-AnsiSelection 'Pick' $script:Fruit }).Value | Should -BeExactly 'banana'
    }

    It 'ignores keys it does not use' {
        Set-AnsiTestKeys -Module Read-AnsiSelection -Keys @((New-Char -Char 'q'), (New-Key -Key Enter))
        (Invoke-Prompt { Read-AnsiSelection 'Pick' $script:Fruit }).Value | Should -BeExactly 'apple'
    }
}

Describe 'Read-AnsiSelection — drawing' {
    It 'draws the title, every choice, and a hint' {
        Set-AnsiTestKeys -Module Read-AnsiSelection -Keys @((New-Key -Key Enter))
        $result = Invoke-Prompt { Read-AnsiSelection 'Pick' $script:Fruit }
        $frame = Get-FinalFrame -Result $result -Title 'Pick'

        $frame.Count | Should -Be 7                     # title + 5 choices + hint
        $frame[0] | Should -BeExactly 'Pick'
        $frame[1] | Should -BeExactly ($script:Cursor + ' apple')
        $frame[2] | Should -BeExactly '  banana'
        $frame[-1] | Should -Match 'enter select'
    }

    It 'marks the row the cursor is on' {
        Set-AnsiTestKeys -Module Read-AnsiSelection -Keys @((New-Key -Key DownArrow), (New-Key -Key Enter))
        $result = Invoke-Prompt { Read-AnsiSelection 'Pick' $script:Fruit }
        $frame = Get-FinalFrame -Result $result -Title 'Pick'
        $frame[1] | Should -BeExactly '  apple'
        $frame[2] | Should -BeExactly ($script:Cursor + ' banana')
    }

    It 'shows only -PageSize rows and scrolls the window' {
        Set-AnsiTestKeys -Module Read-AnsiSelection -Keys @((New-Key -Key End), (New-Key -Key Enter))
        $result = Invoke-Prompt { Read-AnsiSelection 'Pick' $script:Fruit -PageSize 3 }
        $frame = Get-FinalFrame -Result $result -Title 'Pick'

        $frame.Count | Should -Be 5                     # title + 3 choices + hint
        $frame[1] | Should -BeExactly '  cherry'
        $frame[3] | Should -BeExactly ($script:Cursor + ' elderberry')
    }

    It 'shows a position counter when the list is paged' {
        Set-AnsiTestKeys -Module Read-AnsiSelection -Keys @((New-Key -Key Enter))
        $result = Invoke-Prompt { Read-AnsiSelection 'Pick' $script:Fruit -PageSize 2 }
        $frame = Get-FinalFrame -Result $result -Title 'Pick'
        $frame[-1] | Should -Match '^1/5'
    }

    It 'colours the cursor row' {
        Set-AnsiTestKeys -Module Read-AnsiSelection -Keys @((New-Key -Key Enter))
        $result = Invoke-Prompt { Read-AnsiSelection 'Pick' $script:Fruit -CursorColor BrightRed }
        ($result.Rows -join '') | Should -Match ([regex]::Escape($PSStyle.Foreground.BrightRed))
    }

    It 'repaints in place rather than appending frames' {
        Set-AnsiTestKeys -Module Read-AnsiSelection -Keys @((New-Key -Key DownArrow), (New-Key -Key Enter))
        $result = Invoke-Prompt { Read-AnsiSelection 'Pick' $script:Fruit }
        # Two frames were drawn, so the cursor was moved back up over the first.
        $result.Raw | Should -Match ([regex]::Escape("$([char]27)[7A"))
    }
}

Describe 'Read-AnsiSelection — input shapes and options' {
    It 'returns the original object, not its label' {
        $items = @(
            [PSCustomObject]@{ Name = 'alpha'; Id = 1 }
            [PSCustomObject]@{ Name = 'beta'; Id = 2 }
        )
        Set-AnsiTestKeys -Module Read-AnsiSelection -Keys @((New-Key -Key DownArrow), (New-Key -Key Enter))
        $result = Invoke-Prompt { Read-AnsiSelection 'Pick' $items -LabelProperty Name }
        $result.Value.Id | Should -Be 2
    }

    It 'labels objects with -LabelProperty' {
        $items = @([PSCustomObject]@{ Name = 'alpha' })
        Set-AnsiTestKeys -Module Read-AnsiSelection -Keys @((New-Key -Key Enter))
        $result = Invoke-Prompt { Read-AnsiSelection 'Pick' $items -LabelProperty Name }
        (Get-FinalFrame -Result $result -Title 'Pick')[1] | Should -BeExactly ($script:Cursor + ' alpha')
    }

    It 'accepts choices from the pipeline' {
        Set-AnsiTestKeys -Module Read-AnsiSelection -Keys @((New-Key -Key DownArrow), (New-Key -Key Enter))
        $result = Invoke-Prompt { $script:Fruit | Read-AnsiSelection 'Pick' }
        $result.Value | Should -BeExactly 'banana'
    }

    It 'parses markup in the title and the choices' {
        Set-AnsiTestKeys -Module Read-AnsiSelection -Keys @((New-Key -Key Enter))
        $result = Invoke-Prompt { Read-AnsiSelection '[bold]Pick[/]' @('[BrightGreen]go[/]') }
        ($result.Rows -join '') | Should -Match ([regex]::Escape($PSStyle.Bold))
        ($result.Rows -join '') | Should -Match ([regex]::Escape($PSStyle.Foreground.BrightGreen))
    }

    It 'keeps labels literal with -Escape' {
        Set-AnsiTestKeys -Module Read-AnsiSelection -Keys @((New-Key -Key Enter))
        $result = Invoke-Prompt { Read-AnsiSelection 'Pick' @('[bold]x[/]') -Escape }
        (Get-FinalFrame -Result $result -Title 'Pick')[1] | Should -BeExactly ($script:Cursor + ' [bold]x[/]')
    }

    It 'throws when there are no choices' {
        { Read-AnsiSelection 'Pick' @() } | Should -Throw '*at least one choice*'
    }

    It 'throws an unknown colour' {
        { Read-AnsiSelection 'Pick' $script:Fruit -CursorColor Nope } | Should -Throw
    }
}

Describe 'Read-AnsiSelection — cancel, timeout, non-interactive, NO_COLOR' {
    It 'returns $null on Escape' {
        Set-AnsiTestKeys -Module Read-AnsiSelection -Keys @((New-Key -Key Escape))
        (Invoke-Prompt { Read-AnsiSelection 'Pick' $script:Fruit }).Value | Should -BeNullOrEmpty
    }

    It 'returns $null when the timeout expires' {
        Set-AnsiTestKeys -Module Read-AnsiSelection -Keys @()
        (Invoke-Prompt { Read-AnsiSelection 'Pick' $script:Fruit -TimeoutSeconds 1 }).Value | Should -BeNullOrEmpty
    }

    It 'throws when input is redirected' {
        Set-AnsiTestInteractive -Module Read-AnsiSelection -Value $false
        try {
            { Read-AnsiSelection 'Pick' $script:Fruit } | Should -Throw '*interactive console*'
        } finally {
            Set-AnsiTestInteractive -Module Read-AnsiSelection -Value $true
        }
    }

    It 'strips styles but keeps the layout under NO_COLOR' {
        Set-AnsiTestNoColor -Module Read-AnsiSelection -Value $true
        try {
            Set-AnsiTestKeys -Module Read-AnsiSelection -Keys @((New-Key -Key Enter))
            $result = Invoke-Prompt { Read-AnsiSelection 'Pick' $script:Fruit -CursorColor BrightRed }
            ($result.Rows -join '') | Should -Not -Match ([regex]::Escape($PSStyle.Foreground.BrightRed))
            (Get-FinalFrame -Result $result -Title 'Pick')[1] | Should -BeExactly ($script:Cursor + ' apple')
        } finally {
            Set-AnsiTestNoColor -Module Read-AnsiSelection -Value $false
        }
    }
}

Describe 'Read-AnsiSelection — groups' {
    It 'draws a header per group with its members indented' {
        Set-AnsiTestKeys -Module Read-AnsiSelection -Keys @((New-Key -Key Enter))
        $result = Invoke-Prompt { Read-AnsiSelection 'Pick' $script:Groups -Grouped }
        $frame = Get-FinalFrame -Result $result -Title 'Pick'

        $frame.Count | Should -Be 8                     # title + 2 headers + 4 members + hint
        $frame[1] | Should -BeExactly '  Berries'
        $frame[2] | Should -BeExactly ($script:Cursor + '   strawberry')
        $frame[3] | Should -BeExactly '    raspberry'
        $frame[4] | Should -BeExactly '  Citrus'
        $frame[6] | Should -BeExactly '    lime'
    }

    It 'draws headers in bold' {
        Set-AnsiTestKeys -Module Read-AnsiSelection -Keys @((New-Key -Key Enter))
        $result = Invoke-Prompt { Read-AnsiSelection 'Pick' $script:Groups -Grouped }
        ($result.Rows -join '') | Should -Match ([regex]::Escape($PSStyle.Bold))
    }

    It 'starts on the first member, not the header' {
        Set-AnsiTestKeys -Module Read-AnsiSelection -Keys @((New-Key -Key Enter))
        $result = Invoke-Prompt { Read-AnsiSelection 'Pick' $script:Groups -Grouped }
        $result.Value | Should -BeExactly 'strawberry'
    }

    It 'moves straight past a header' {
        Set-AnsiTestKeys -Module Read-AnsiSelection -Keys @(
            (New-Key -Key DownArrow), (New-Key -Key DownArrow), (New-Key -Key Enter)
        )
        $result = Invoke-Prompt { Read-AnsiSelection 'Pick' $script:Groups -Grouped }
        $result.Value | Should -BeExactly 'lemon'
    }

    It 'moves back up past a header' {
        Set-AnsiTestKeys -Module Read-AnsiSelection -Keys @(
            (New-Key -Key End), (New-Key -Key UpArrow), (New-Key -Key UpArrow), (New-Key -Key Enter)
        )
        $result = Invoke-Prompt { Read-AnsiSelection 'Pick' $script:Groups -Grouped }
        $result.Value | Should -BeExactly 'raspberry'
    }

    It 'lands Home and End on members' {
        Set-AnsiTestKeys -Module Read-AnsiSelection -Keys @((New-Key -Key End), (New-Key -Key Enter))
        (Invoke-Prompt { Read-AnsiSelection 'Pick' $script:Groups -Grouped }).Value | Should -BeExactly 'lime'

        Set-AnsiTestKeys -Module Read-AnsiSelection -Keys @(
            (New-Key -Key End), (New-Key -Key Home), (New-Key -Key Enter)
        )
        (Invoke-Prompt { Read-AnsiSelection 'Pick' $script:Groups -Grouped }).Value | Should -BeExactly 'strawberry'
    }

    It 'snaps a page move onto a member' {
        Set-AnsiTestKeys -Module Read-AnsiSelection -Keys @((New-Key -Key PageDown), (New-Key -Key Enter))
        (Invoke-Prompt { Read-AnsiSelection 'Pick' $script:Groups -Grouped -PageSize 3 }).Value |
            Should -BeExactly 'lemon'

        Set-AnsiTestKeys -Module Read-AnsiSelection -Keys @(
            (New-Key -Key End), (New-Key -Key PageUp), (New-Key -Key Enter)
        )
        (Invoke-Prompt { Read-AnsiSelection 'Pick' $script:Groups -Grouped -PageSize 3 }).Value |
            Should -BeExactly 'raspberry'
    }

    It 'counts members, not headers, in the position counter' {
        Set-AnsiTestKeys -Module Read-AnsiSelection -Keys @((New-Key -Key End), (New-Key -Key Enter))
        $result = Invoke-Prompt { Read-AnsiSelection 'Pick' $script:Groups -Grouped -PageSize 3 }
        (Get-FinalFrame -Result $result -Title 'Pick')[-1] | Should -Match '^4/4'
    }

    It 'reads Group-Object output with the property names named' {
        $shape = @(
            [PSCustomObject]@{ Name = 'Berries'; Group = @('strawberry') }
            [PSCustomObject]@{ Name = 'Citrus'; Group = @('lemon') }
        )
        Set-AnsiTestKeys -Module Read-AnsiSelection -Keys @((New-Key -Key End), (New-Key -Key Enter))
        $result = Invoke-Prompt {
            Read-AnsiSelection 'Pick' $shape -Grouped -GroupChoicesProperty Group
        }
        $result.Value | Should -BeExactly 'lemon'
        (Get-FinalFrame -Result $result -Title 'Pick')[1] | Should -BeExactly '  Berries'
    }

    It 'labels members with -LabelProperty and returns the objects' {
        $groups = @(
            @{ Name = 'Formatters'; Choices = @([PSCustomObject]@{ Name = 'alpha'; Id = 1 }) }
            @{ Name = 'Prompts'; Choices = @([PSCustomObject]@{ Name = 'beta'; Id = 2 }) }
        )
        Set-AnsiTestKeys -Module Read-AnsiSelection -Keys @((New-Key -Key End), (New-Key -Key Enter))
        $result = Invoke-Prompt { Read-AnsiSelection 'Pick' $groups -Grouped -LabelProperty Name }
        $result.Value.Id | Should -Be 2
        (Get-FinalFrame -Result $result -Title 'Pick')[2] | Should -BeExactly '    alpha'
    }

    It 'colours headers with -GroupColor' {
        Set-AnsiTestKeys -Module Read-AnsiSelection -Keys @((New-Key -Key Enter))
        $result = Invoke-Prompt { Read-AnsiSelection 'Pick' $script:Groups -Grouped -GroupColor BrightYellow }
        ($result.Rows -join '') | Should -Match ([regex]::Escape($PSStyle.Foreground.BrightYellow))
    }

    It 'keeps an empty group as a header with nothing under it' {
        $groups = @(
            @{ Name = 'Empty'; Choices = @() }
            @{ Name = 'Citrus'; Choices = @('lemon') }
        )
        Set-AnsiTestKeys -Module Read-AnsiSelection -Keys @((New-Key -Key Enter))
        $result = Invoke-Prompt { Read-AnsiSelection 'Pick' $groups -Grouped }
        $frame = Get-FinalFrame -Result $result -Title 'Pick'
        $frame[1] | Should -BeExactly '  Empty'
        $frame[2] | Should -BeExactly '  Citrus'
        $result.Value | Should -BeExactly 'lemon'
    }

    It 'throws when a group carries no choices' {
        { Read-AnsiSelection 'Pick' @(@{ Name = 'Berries' }) -Grouped } | Should -Throw '*has no Choices*'
    }

    It 'throws when a group has no name' {
        { Read-AnsiSelection 'Pick' @(@{ Choices = @('lemon') }) -Grouped } | Should -Throw '*has no Name*'
    }

    It 'throws when every group is empty' {
        { Read-AnsiSelection 'Pick' @(@{ Name = 'Empty'; Choices = @() }) -Grouped } |
            Should -Throw '*at least one choice*'
    }
}

Describe 'Read-AnsiSelection — module surface' {
    It 'exports only Read-AnsiSelection' {
        (Get-Module Read-AnsiSelection).ExportedFunctions.Keys | Should -Be 'Read-AnsiSelection'
    }
}
