#Requires -Version 7.2
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

# Read-AnsiMultiSelection.Tests.ps1
# Pester 5 tests for Read-AnsiMultiSelection.
#
# The console seams are replaced inside each module scope, so a scripted key list
# drives the prompt: no keyboard, no waiting. Cursor-control sequences are stripped
# from the captured output, leaving the rows each redraw painted.

BeforeAll {
    $script:src = Join-Path (Split-Path -Parent $PSScriptRoot) 'src'
    Import-Module (Join-Path $script:src 'Read-AnsiMultiSelection.psm1') -Force -DisableNameChecking

    foreach ($name in 'Read-AnsiMultiSelection') {
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

Describe 'Read-AnsiMultiSelection — ticking' {
    It 'returns an empty result when nothing is ticked' {
        Set-AnsiTestKeys -Module Read-AnsiMultiSelection -Keys @((New-Key -Key Enter))
        $result = Invoke-Prompt { Read-AnsiMultiSelection 'Pick' $script:Fruit }
        @($result.Value).Count | Should -Be 0
    }

    It 'ticks with the space bar' {
        Set-AnsiTestKeys -Module Read-AnsiMultiSelection -Keys @((New-Key -Key Spacebar), (New-Key -Key Enter))
        $result = Invoke-Prompt { Read-AnsiMultiSelection 'Pick' $script:Fruit }
        @($result.Value) | Should -Be @('apple')
    }

    It 'ticks several, in list order' {
        Set-AnsiTestKeys -Module Read-AnsiMultiSelection -Keys @(
            (New-Key -Key DownArrow), (New-Key -Key DownArrow), (New-Key -Key Spacebar)
            (New-Key -Key Home), (New-Key -Key Spacebar), (New-Key -Key Enter)
        )
        $result = Invoke-Prompt { Read-AnsiMultiSelection 'Pick' $script:Fruit }
        @($result.Value) | Should -Be @('apple', 'cherry')
    }

    It 'unticks on a second space' {
        Set-AnsiTestKeys -Module Read-AnsiMultiSelection -Keys @(
            (New-Key -Key Spacebar), (New-Key -Key Spacebar), (New-Key -Key Enter)
        )
        $result = Invoke-Prompt { Read-AnsiMultiSelection 'Pick' $script:Fruit }
        @($result.Value).Count | Should -Be 0
    }

    It 'toggles everything with a' {
        Set-AnsiTestKeys -Module Read-AnsiMultiSelection -Keys @((New-Char -Char 'a'), (New-Key -Key Enter))
        $result = Invoke-Prompt { Read-AnsiMultiSelection 'Pick' $script:Fruit }
        @($result.Value).Count | Should -Be 5
    }

    It 'clears everything with a second a' {
        Set-AnsiTestKeys -Module Read-AnsiMultiSelection -Keys @((New-Char -Char 'a'), (New-Char -Char 'a'), (New-Key -Key Enter))
        $result = Invoke-Prompt { Read-AnsiMultiSelection 'Pick' $script:Fruit }
        @($result.Value).Count | Should -Be 0
    }

    It 'starts from -Selected' {
        Set-AnsiTestKeys -Module Read-AnsiMultiSelection -Keys @((New-Key -Key Enter))
        $result = Invoke-Prompt { Read-AnsiMultiSelection 'Pick' $script:Fruit -Selected 'banana', 'date' }
        @($result.Value) | Should -Be @('banana', 'date')
    }

    It 'returns the original objects' {
        $items = @(
            [PSCustomObject]@{ Name = 'alpha'; Id = 1 }
            [PSCustomObject]@{ Name = 'beta'; Id = 2 }
        )
        Set-AnsiTestKeys -Module Read-AnsiMultiSelection -Keys @(
            (New-Key -Key DownArrow), (New-Key -Key Spacebar), (New-Key -Key Enter)
        )
        $result = Invoke-Prompt { Read-AnsiMultiSelection 'Pick' $items -LabelProperty Name }
        @($result.Value)[0].Id | Should -Be 2
    }
}

Describe 'Read-AnsiMultiSelection — drawing and -Required' {
    It 'draws a checkbox per choice and a count' {
        Set-AnsiTestKeys -Module Read-AnsiMultiSelection -Keys @((New-Key -Key Spacebar), (New-Key -Key Enter))
        $result = Invoke-Prompt { Read-AnsiMultiSelection 'Pick' $script:Fruit }
        $frame = Get-FinalFrame -Result $result -Title 'Pick'

        $frame.Count | Should -Be 8                     # title + 5 choices + hint + note
        $frame[1] | Should -BeExactly ($script:Cursor + ' [' + $script:Check + '] apple')
        $frame[2] | Should -BeExactly '  [ ] banana'
        $frame[6] | Should -Match '^1 selected'
    }

    It 'refuses an empty selection with -Required and reports it' {
        Set-AnsiTestKeys -Module Read-AnsiMultiSelection -Keys @(
            (New-Key -Key Enter), (New-Key -Key Spacebar), (New-Key -Key Enter)
        )
        $result = Invoke-Prompt { Read-AnsiMultiSelection 'Pick' $script:Fruit -Required }
        @($result.Value) | Should -Be @('apple')
        ($result.Rows -join '') | Should -Match 'Select at least one item\.'
    }

    It 'honours -RequiredMessage' {
        Set-AnsiTestKeys -Module Read-AnsiMultiSelection -Keys @(
            (New-Key -Key Enter), (New-Key -Key Spacebar), (New-Key -Key Enter)
        )
        $result = Invoke-Prompt { Read-AnsiMultiSelection 'Pick' $script:Fruit -Required -RequiredMessage 'pick one!' }
        ($result.Rows -join '') | Should -Match 'pick one!'
    }

    It 'accepts an empty selection without -Required' {
        Set-AnsiTestKeys -Module Read-AnsiMultiSelection -Keys @((New-Key -Key Enter))
        $result = Invoke-Prompt { Read-AnsiMultiSelection 'Pick' $script:Fruit }
        $result.HasValue | Should -BeTrue
        @($result.Value).Count | Should -Be 0
    }

    It 'pages like the single selection' {
        Set-AnsiTestKeys -Module Read-AnsiMultiSelection -Keys @((New-Key -Key End), (New-Key -Key Enter))
        $result = Invoke-Prompt { Read-AnsiMultiSelection 'Pick' $script:Fruit -PageSize 2 }
        $frame = Get-FinalFrame -Result $result -Title 'Pick'
        $frame.Count | Should -Be 5                     # title + 2 choices + hint + note
        $frame[2] | Should -BeExactly ($script:Cursor + ' [ ] elderberry')
    }

    It 'colours the tick with -MarkColor' {
        Set-AnsiTestKeys -Module Read-AnsiMultiSelection -Keys @((New-Key -Key Spacebar), (New-Key -Key Enter))
        $result = Invoke-Prompt { Read-AnsiMultiSelection 'Pick' $script:Fruit -MarkColor BrightMagenta }
        ($result.Rows -join '') | Should -Match ([regex]::Escape($PSStyle.Foreground.BrightMagenta))
    }
}

Describe 'Read-AnsiMultiSelection — cancel, timeout, non-interactive' {
    It 'returns $null on Escape' {
        Set-AnsiTestKeys -Module Read-AnsiMultiSelection -Keys @((New-Key -Key Spacebar), (New-Key -Key Escape))
        (Invoke-Prompt { Read-AnsiMultiSelection 'Pick' $script:Fruit }).Value | Should -BeNullOrEmpty
    }

    It 'returns $null when the timeout expires' {
        Set-AnsiTestKeys -Module Read-AnsiMultiSelection -Keys @()
        (Invoke-Prompt { Read-AnsiMultiSelection 'Pick' $script:Fruit -TimeoutSeconds 1 }).Value | Should -BeNullOrEmpty
    }

    It 'throws when input is redirected' {
        Set-AnsiTestInteractive -Module Read-AnsiMultiSelection -Value $false
        try {
            { Read-AnsiMultiSelection 'Pick' $script:Fruit } | Should -Throw '*interactive console*'
        } finally {
            Set-AnsiTestInteractive -Module Read-AnsiMultiSelection -Value $true
        }
    }

    It 'throws when there are no choices' {
        { Read-AnsiMultiSelection 'Pick' @() } | Should -Throw '*at least one choice*'
    }
}

Describe 'Read-AnsiMultiSelection — groups, view only' {
    It 'draws headers without a box and members with one' {
        Set-AnsiTestKeys -Module Read-AnsiMultiSelection -Keys @((New-Key -Key Spacebar), (New-Key -Key Enter))
        $result = Invoke-Prompt { Read-AnsiMultiSelection 'Pick' $script:Groups -Grouped }
        $frame = Get-FinalFrame -Result $result -Title 'Pick'

        $frame.Count | Should -Be 9                     # title + 2 headers + 4 members + hint + note
        $frame[1] | Should -BeExactly '  Berries'
        $frame[2] | Should -BeExactly ($script:Cursor + '   [' + $script:Check + '] strawberry')
        $frame[3] | Should -BeExactly '    [ ] raspberry'
        $frame[4] | Should -BeExactly '  Citrus'
        $frame[7] | Should -Match '^1 selected'
    }

    It 'moves straight past a header' {
        Set-AnsiTestKeys -Module Read-AnsiMultiSelection -Keys @(
            (New-Key -Key DownArrow), (New-Key -Key DownArrow), (New-Key -Key Spacebar), (New-Key -Key Enter)
        )
        $result = Invoke-Prompt { Read-AnsiMultiSelection 'Pick' $script:Groups -Grouped }
        @($result.Value) | Should -Be @('lemon')
    }

    It 'returns members in list order, never a header' {
        Set-AnsiTestKeys -Module Read-AnsiMultiSelection -Keys @((New-Char -Char 'a'), (New-Key -Key Enter))
        $result = Invoke-Prompt { Read-AnsiMultiSelection 'Pick' $script:Groups -Grouped }
        @($result.Value) | Should -Be @('strawberry', 'raspberry', 'lemon', 'lime')
    }

    It 'counts members, not headers' {
        Set-AnsiTestKeys -Module Read-AnsiMultiSelection -Keys @((New-Char -Char 'a'), (New-Key -Key Enter))
        $result = Invoke-Prompt { Read-AnsiMultiSelection 'Pick' $script:Groups -Grouped -PageSize 3 }
        (Get-FinalFrame -Result $result -Title 'Pick')[-2] | Should -Match '^1/4  4 selected'
    }

    It 'pre-ticks inside groups with -Selected' {
        Set-AnsiTestKeys -Module Read-AnsiMultiSelection -Keys @((New-Key -Key Enter))
        $result = Invoke-Prompt { Read-AnsiMultiSelection 'Pick' $script:Groups -Grouped -Selected 'raspberry', 'lime' }
        @($result.Value) | Should -Be @('raspberry', 'lime')
    }

    It 'throws -ToggleGroups without -Grouped' {
        { Read-AnsiMultiSelection 'Pick' $script:Fruit -ToggleGroups } | Should -Throw '*needs -Grouped*'
    }
}

Describe 'Read-AnsiMultiSelection — groups, -ToggleGroups' {
    BeforeAll {
        function Get-PlainRows {
            param([Parameter(Mandatory)][object]$Result)
            return (@($Result.Rows | ForEach-Object { Remove-Ansi $_ }) -join "`n")
        }
    }

    It 'starts on the header and boxes it' {
        Set-AnsiTestKeys -Module Read-AnsiMultiSelection -Keys @((New-Key -Key Enter))
        $result = Invoke-Prompt { Read-AnsiMultiSelection 'Pick' $script:Groups -Grouped -ToggleGroups }
        $frame = Get-FinalFrame -Result $result -Title 'Pick'

        $frame[1] | Should -BeExactly ($script:Cursor + ' [ ] Berries')
        $frame[2] | Should -BeExactly '    [ ] strawberry'
        $frame[4] | Should -BeExactly '  [ ] Citrus'
    }

    It 'sets the whole group with one space' {
        Set-AnsiTestKeys -Module Read-AnsiMultiSelection -Keys @((New-Key -Key Spacebar), (New-Key -Key Enter))
        $result = Invoke-Prompt { Read-AnsiMultiSelection 'Pick' $script:Groups -Grouped -ToggleGroups }
        @($result.Value) | Should -Be @('strawberry', 'raspberry')

        $frame = Get-FinalFrame -Result $result -Title 'Pick'
        $frame[1] | Should -BeExactly ($script:Cursor + ' [' + $script:Check + '] Berries')
        $frame[2] | Should -BeExactly ('    [' + $script:Check + '] strawberry')
        $frame[3] | Should -BeExactly ('    [' + $script:Check + '] raspberry')
    }

    It 'clears the whole group on a second space' {
        Set-AnsiTestKeys -Module Read-AnsiMultiSelection -Keys @(
            (New-Key -Key Spacebar), (New-Key -Key Spacebar), (New-Key -Key Enter)
        )
        $result = Invoke-Prompt { Read-AnsiMultiSelection 'Pick' $script:Groups -Grouped -ToggleGroups }
        @($result.Value).Count | Should -Be 0
    }

    It 'leaves the other groups alone' {
        Set-AnsiTestKeys -Module Read-AnsiMultiSelection -Keys @(
            (New-Key -Key End), (New-Key -Key UpArrow), (New-Key -Key UpArrow), (New-Key -Key Spacebar)
            (New-Key -Key Enter)
        )
        $result = Invoke-Prompt { Read-AnsiMultiSelection 'Pick' $script:Groups -Grouped -ToggleGroups }
        @($result.Value) | Should -Be @('lemon', 'lime')
    }

    It 'completes a part-ticked group on space' {
        Set-AnsiTestKeys -Module Read-AnsiMultiSelection -Keys @(
            (New-Key -Key DownArrow), (New-Key -Key Spacebar), (New-Key -Key UpArrow)
            (New-Key -Key Spacebar), (New-Key -Key Enter)
        )
        $result = Invoke-Prompt { Read-AnsiMultiSelection 'Pick' $script:Groups -Grouped -ToggleGroups }
        @($result.Value) | Should -Be @('strawberry', 'raspberry')
    }

    It 'shows a part-ticked group as [-]' {
        # Painted once per key burst, so the partial state is asserted from where it is drawn -
        # a group that starts with one member ticked - rather than from a frame between keys.
        Set-AnsiTestKeys -Module Read-AnsiMultiSelection -Keys @((New-Key -Key Enter))
        $result = Invoke-Prompt {
            Read-AnsiMultiSelection 'Pick' $script:Groups -Grouped -ToggleGroups -Selected 'strawberry'
        }
        (Get-PlainRows -Result $result) | Should -Match ([regex]::Escape('[-] Berries'))
    }

    It 'reports a full group from -Selected' {
        Set-AnsiTestKeys -Module Read-AnsiMultiSelection -Keys @((New-Key -Key Enter))
        $result = Invoke-Prompt {
            Read-AnsiMultiSelection 'Pick' $script:Groups -Grouped -ToggleGroups -Selected 'strawberry', 'raspberry'
        }
        (Get-FinalFrame -Result $result -Title 'Pick')[1] |
            Should -BeExactly ($script:Cursor + ' [' + $script:Check + '] Berries')
    }

    It 'reports a part-ticked group from -Selected' {
        Set-AnsiTestKeys -Module Read-AnsiMultiSelection -Keys @((New-Key -Key Enter))
        $result = Invoke-Prompt {
            Read-AnsiMultiSelection 'Pick' $script:Groups -Grouped -ToggleGroups -Selected 'strawberry'
        }
        (Get-FinalFrame -Result $result -Title 'Pick')[1] | Should -BeExactly ($script:Cursor + ' [-] Berries')
    }

    It 'ticks every member with a, whatever group it is in' {
        Set-AnsiTestKeys -Module Read-AnsiMultiSelection -Keys @((New-Char -Char 'a'), (New-Key -Key Enter))
        $result = Invoke-Prompt { Read-AnsiMultiSelection 'Pick' $script:Groups -Grouped -ToggleGroups }
        @($result.Value) | Should -Be @('strawberry', 'raspberry', 'lemon', 'lime')
        (Get-FinalFrame -Result $result -Title 'Pick')[1] |
            Should -BeExactly ($script:Cursor + ' [' + $script:Check + '] Berries')
    }

    It 'counts headers as rows the cursor can reach' {
        Set-AnsiTestKeys -Module Read-AnsiMultiSelection -Keys @((New-Key -Key Enter))
        $result = Invoke-Prompt { Read-AnsiMultiSelection 'Pick' $script:Groups -Grouped -ToggleGroups -PageSize 3 }
        (Get-FinalFrame -Result $result -Title 'Pick')[-2] | Should -Match '^1/6'
    }

    It 'toggles nothing for an empty group' {
        $groups = @(
            @{ Name = 'Empty'; Choices = @() }
            @{ Name = 'Citrus'; Choices = @('lemon') }
        )
        Set-AnsiTestKeys -Module Read-AnsiMultiSelection -Keys @((New-Key -Key Spacebar), (New-Key -Key Enter))
        $result = Invoke-Prompt { Read-AnsiMultiSelection 'Pick' $groups -Grouped -ToggleGroups }
        @($result.Value).Count | Should -Be 0
        (Get-FinalFrame -Result $result -Title 'Pick')[1] | Should -BeExactly ($script:Cursor + ' [ ] Empty')
    }

    It 'returns $null on Escape after toggling a group' {
        Set-AnsiTestKeys -Module Read-AnsiMultiSelection -Keys @((New-Key -Key Spacebar), (New-Key -Key Escape))
        (Invoke-Prompt { Read-AnsiMultiSelection 'Pick' $script:Groups -Grouped -ToggleGroups }).Value |
            Should -BeNullOrEmpty
    }
}

Describe 'Read-AnsiMultiSelection — module surface' {
    It 'exports only Read-AnsiMultiSelection' {
        (Get-Module Read-AnsiMultiSelection).ExportedFunctions.Keys | Should -Be 'Read-AnsiMultiSelection'
    }
}
