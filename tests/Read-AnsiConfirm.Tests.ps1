#Requires -Version 7.2
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

# Read-AnsiConfirm.Tests.ps1
# Pester 5 tests for Read-AnsiConfirm.
#
# The console seams (Test-AnsiInteractive, Test-AnsiKeyAvailable, Read-AnsiKeyInfo,
# Start-AnsiWait) are replaced inside each module scope, so a scripted key list
# drives the prompt and no real keyboard or timing is involved. Test-AnsiNoColor is
# driven by Set-AnsiTestNoColor, as in the component suites.

BeforeAll {
    $script:src = Join-Path (Split-Path -Parent $PSScriptRoot) 'src'
    Import-Module (Join-Path $script:src 'Read-AnsiConfirm.psm1') -Force -DisableNameChecking

    foreach ($name in 'Read-AnsiConfirm') {
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

    function New-TestKey {
        param(
            [char]$Char = "`0",
            [System.ConsoleKey]$Key = [System.ConsoleKey]::A
        )
        return [System.ConsoleKeyInfo]::new($Char, $Key, $false, $false, $false)
    }

    # Build a key list: the characters of -Text, then Enter (or Escape).
    function New-TestKeys {
        param(
            [AllowEmptyString()][string]$Text = '',
            [ValidateSet('Enter', 'Escape', 'None')][string]$Finish = 'Enter',
            [int]$Backspaces = 0
        )
        $keys = [System.Collections.Generic.List[object]]::new()
        foreach ($c in $Text.ToCharArray()) { $null = $keys.Add((New-TestKey -Char $c)) }
        for ($i = 0; $i -lt $Backspaces; $i++) {
            $null = $keys.Add((New-TestKey -Char "`b" -Key ([System.ConsoleKey]::Backspace)))
        }
        switch ($Finish) {
            'Enter' { $null = $keys.Add((New-TestKey -Char "`r" -Key ([System.ConsoleKey]::Enter))) }
            'Escape' { $null = $keys.Add((New-TestKey -Char ([char]27) -Key ([System.ConsoleKey]::Escape))) }
        }
        return , $keys.ToArray()
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

    # A prompt writes to the host and returns a value: capture both.
    function Invoke-Prompt {
        param([Parameter(Mandatory)][scriptblock]$Sb)
        $painted = [System.Collections.Generic.List[string]]::new()
        $value = $null
        $records = & $Sb 6>&1
        foreach ($record in @($records)) {
            if ($record -is [System.Management.Automation.InformationRecord]) {
                $null = $painted.Add([string]$record.ToString())
            } else {
                $value = $record
            }
        }
        return [PSCustomObject]@{ Value = $value; Painted = ($painted -join '') }
    }

    function Remove-Ansi {
        param([AllowEmptyString()][string]$Text)
        return ($Text -replace "`e\[[\d;]*m", '')
    }
}

Describe 'Read-AnsiConfirm — answers' {
    It 'returns $true for y' {
        Set-AnsiTestKeys -Module Read-AnsiConfirm -Keys @((New-TestKey -Char 'y'))
        $result = Invoke-Prompt { Read-AnsiConfirm 'Deploy?' }
        $result.Value | Should -BeTrue
    }

    It 'returns $false for n' {
        Set-AnsiTestKeys -Module Read-AnsiConfirm -Keys @((New-TestKey -Char 'n'))
        $result = Invoke-Prompt { Read-AnsiConfirm 'Deploy?' }
        $result.Value | Should -BeFalse
    }

    It 'accepts upper case' {
        Set-AnsiTestKeys -Module Read-AnsiConfirm -Keys @((New-TestKey -Char 'Y'))
        $result = Invoke-Prompt { Read-AnsiConfirm 'Deploy?' }
        $result.Value | Should -BeTrue
    }

    It 'ignores keys that are not y, n, Enter, or Escape' {
        Set-AnsiTestKeys -Module Read-AnsiConfirm -Keys @((New-TestKey -Char 'q'), (New-TestKey -Char 'n'))
        $result = Invoke-Prompt { Read-AnsiConfirm 'Deploy?' }
        $result.Value | Should -BeFalse
    }

    It 'echoes the answer as a word' {
        Set-AnsiTestKeys -Module Read-AnsiConfirm -Keys @((New-TestKey -Char 'y'))
        $result = Invoke-Prompt { Read-AnsiConfirm 'Deploy?' }
        (Remove-Ansi $result.Painted) | Should -BeExactly 'Deploy? [Y/n]: yes'
    }

    It 'colours the echoed answer' {
        Set-AnsiTestKeys -Module Read-AnsiConfirm -Keys @((New-TestKey -Char 'y'))
        $result = Invoke-Prompt { Read-AnsiConfirm 'Deploy?' -AnswerColor BrightGreen }
        $result.Painted | Should -Match ([regex]::Escape($PSStyle.Foreground.BrightGreen + 'yes'))
    }
}

Describe 'Read-AnsiConfirm — defaults' {
    It 'capitalises the default choice' {
        Set-AnsiTestKeys -Module Read-AnsiConfirm -Keys @((New-TestKey -Char 'y'))
        $yes = Invoke-Prompt { Read-AnsiConfirm 'Deploy?' -Default $true }
        (Remove-Ansi $yes.Painted) | Should -BeLike '*`[Y/n`]*'

        Set-AnsiTestKeys -Module Read-AnsiConfirm -Keys @((New-TestKey -Char 'y'))
        $no = Invoke-Prompt { Read-AnsiConfirm 'Deploy?' -Default $false }
        (Remove-Ansi $no.Painted) | Should -BeLike '*`[y/N`]*'
    }

    It 'returns the default on Enter' {
        Set-AnsiTestKeys -Module Read-AnsiConfirm -Keys @((New-TestKey -Char "`r" -Key ([System.ConsoleKey]::Enter)))
        $result = Invoke-Prompt { Read-AnsiConfirm 'Deploy?' -Default $false }
        $result.Value | Should -BeFalse
    }

    It 'ignores Enter when there is no default' {
        $keys = @(
            (New-TestKey -Char "`r" -Key ([System.ConsoleKey]::Enter))
            (New-TestKey -Char 'y')
        )
        Set-AnsiTestKeys -Module Read-AnsiConfirm -Keys $keys
        $result = Invoke-Prompt { Read-AnsiConfirm 'Deploy?' -Default $null }
        $result.Value | Should -BeTrue
        (Remove-Ansi $result.Painted) | Should -BeLike '*`[y/n`]*'
    }
}

Describe 'Read-AnsiConfirm — messages, cancel, timeout' {
    It 'writes -SuccessMessage after yes' {
        Set-AnsiTestKeys -Module Read-AnsiConfirm -Keys @((New-TestKey -Char 'y'))
        $result = Invoke-Prompt { Read-AnsiConfirm 'Deploy?' -SuccessMessage 'deploying' -FailureMessage 'skipped' }
        (Remove-Ansi $result.Painted) | Should -Match 'deploying'
        (Remove-Ansi $result.Painted) | Should -Not -Match 'skipped'
    }

    It 'writes -FailureMessage after no' {
        Set-AnsiTestKeys -Module Read-AnsiConfirm -Keys @((New-TestKey -Char 'n'))
        $result = Invoke-Prompt { Read-AnsiConfirm 'Deploy?' -SuccessMessage 'deploying' -FailureMessage 'skipped' }
        (Remove-Ansi $result.Painted) | Should -Match 'skipped'
    }

    It 'parses markup in the messages' {
        Set-AnsiTestKeys -Module Read-AnsiConfirm -Keys @((New-TestKey -Char 'y'))
        $result = Invoke-Prompt { Read-AnsiConfirm 'Deploy?' -SuccessMessage ':check: go' -Markdown }
        (Remove-Ansi $result.Painted) | Should -Match ([regex]::Escape([string][char]0x2713))
    }

    It 'returns $null when Escape is pressed' {
        Set-AnsiTestKeys -Module Read-AnsiConfirm -Keys @((New-TestKey -Char ([char]27) -Key ([System.ConsoleKey]::Escape)))
        $result = Invoke-Prompt { Read-AnsiConfirm 'Deploy?' }
        $result.Value | Should -BeNullOrEmpty
    }

    It 'returns $null when the timeout expires' {
        Set-AnsiTestKeys -Module Read-AnsiConfirm -Keys @()
        $result = Invoke-Prompt { Read-AnsiConfirm 'Deploy?' -TimeoutSeconds 1 }
        $result.Value | Should -BeNullOrEmpty
    }

    It 'throws when input is redirected' {
        Set-AnsiTestInteractive -Module Read-AnsiConfirm -Value $false
        try {
            { Read-AnsiConfirm 'Deploy?' } | Should -Throw '*interactive console*'
        } finally {
            Set-AnsiTestInteractive -Module Read-AnsiConfirm -Value $true
        }
    }

    It 'strips styles when the host cannot show them' {
        Set-AnsiTestNoColor -Module Read-AnsiConfirm -Value $true
        try {
            Set-AnsiTestKeys -Module Read-AnsiConfirm -Keys @((New-TestKey -Char 'y'))
            $result = Invoke-Prompt { Read-AnsiConfirm '[bold]Deploy?[/]' -SuccessMessage 'go' }
            $result.Painted | Should -Not -Match ([regex]::Escape([char]27))
        } finally {
            Set-AnsiTestNoColor -Module Read-AnsiConfirm -Value $false
        }
    }
}

Describe 'Read-AnsiConfirm — module surface' {
    It 'exports only Read-AnsiConfirm' {
        (Get-Module Read-AnsiConfirm).ExportedFunctions.Keys | Should -Be 'Read-AnsiConfirm'
    }
}
