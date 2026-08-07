#Requires -Version 7.2
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

# Read-AnsiText.Tests.ps1
# Pester 5 tests for Read-AnsiText.
#
# The console seams (Test-AnsiInteractive, Test-AnsiKeyAvailable, Read-AnsiKeyInfo,
# Start-AnsiWait) are replaced inside each module scope, so a scripted key list
# drives the prompt and no real keyboard or timing is involved. Test-AnsiNoColor is
# driven by Set-AnsiTestNoColor, as in the component suites.

BeforeAll {
    $script:src = Join-Path (Split-Path -Parent $PSScriptRoot) 'src'
    Import-Module (Join-Path $script:src 'Read-AnsiText.psm1') -Force -DisableNameChecking

    foreach ($name in 'Read-AnsiText') {
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

Describe 'Read-AnsiText — answers' {
    It 'returns what was typed' {
        Set-AnsiTestKeys -Module Read-AnsiText -Keys (New-TestKeys -Text 'ansi')
        $result = Invoke-Prompt { Read-AnsiText 'Name' }
        $result.Value | Should -BeExactly 'ansi'
    }

    It 'writes the prompt with a colon and no trailing newline' {
        Set-AnsiTestKeys -Module Read-AnsiText -Keys (New-TestKeys -Text 'x')
        $result = Invoke-Prompt { Read-AnsiText 'Name' }
        (Remove-Ansi $result.Painted) | Should -BeLike 'Name: *'
    }

    It 'echoes every typed character' {
        Set-AnsiTestKeys -Module Read-AnsiText -Keys (New-TestKeys -Text 'abc')
        $result = Invoke-Prompt { Read-AnsiText 'Name' }
        (Remove-Ansi $result.Painted) | Should -BeExactly 'Name: abc'
    }

    It 'masks the answer with -Secret' {
        Set-AnsiTestKeys -Module Read-AnsiText -Keys (New-TestKeys -Text 'hunter2')
        $result = Invoke-Prompt { Read-AnsiText 'Password' -Secret }
        $result.Value | Should -BeExactly 'hunter2'
        (Remove-Ansi $result.Painted) | Should -BeExactly 'Password: *******'
    }

    It 'honours backspace' {
        Set-AnsiTestKeys -Module Read-AnsiText -Keys (New-TestKeys -Text 'ansii' -Backspaces 1)
        $result = Invoke-Prompt { Read-AnsiText 'Name' }
        $result.Value | Should -BeExactly 'ansi'
    }

    It 'ignores control characters' {
        $keys = @(
            (New-TestKey -Char 'a')
            (New-TestKey -Char "`t" -Key ([System.ConsoleKey]::Tab))
            (New-TestKey -Char 'b')
            (New-TestKey -Char "`r" -Key ([System.ConsoleKey]::Enter))
        )
        Set-AnsiTestKeys -Module Read-AnsiText -Keys $keys
        $result = Invoke-Prompt { Read-AnsiText 'Name' }
        $result.Value | Should -BeExactly 'ab'
    }

    It 'colours the answer with -AnswerColor' {
        Set-AnsiTestKeys -Module Read-AnsiText -Keys (New-TestKeys -Text 'x')
        $result = Invoke-Prompt { Read-AnsiText 'Name' -AnswerColor BrightRed }
        $result.Painted | Should -Match ([regex]::Escape($PSStyle.Foreground.BrightRed + 'x'))
    }

    It 'throws on an unknown colour' {
        Set-AnsiTestKeys -Module Read-AnsiText -Keys (New-TestKeys -Text 'x')
        { Read-AnsiText 'Name' -AnswerColor Nope } | Should -Throw
    }
}

Describe 'Read-AnsiText — defaults and empty answers' {
    It 'shows the default in the prompt' {
        Set-AnsiTestKeys -Module Read-AnsiText -Keys (New-TestKeys)
        $result = Invoke-Prompt { Read-AnsiText 'Name' -Default 'ansi' }
        (Remove-Ansi $result.Painted) | Should -BeExactly 'Name [ansi]: '
    }

    It 'returns the default for an empty answer' {
        Set-AnsiTestKeys -Module Read-AnsiText -Keys (New-TestKeys)
        $result = Invoke-Prompt { Read-AnsiText 'Name' -Default 'ansi' }
        $result.Value | Should -BeExactly 'ansi'
    }

    It 'prefers a typed answer over the default' {
        Set-AnsiTestKeys -Module Read-AnsiText -Keys (New-TestKeys -Text 'typed')
        $result = Invoke-Prompt { Read-AnsiText 'Name' -Default 'ansi' }
        $result.Value | Should -BeExactly 'typed'
    }

    It 'accepts an empty answer with -AllowEmpty' {
        Set-AnsiTestKeys -Module Read-AnsiText -Keys (New-TestKeys)
        $result = Invoke-Prompt { Read-AnsiText 'Name' -AllowEmpty }
        $result.Value | Should -BeExactly ''
    }

    It 're-prompts when an answer is required' {
        # Enter on its own, then a real answer.
        $keys = @((New-TestKeys), (New-TestKeys -Text 'ansi')) | ForEach-Object { $_ }
        Set-AnsiTestKeys -Module Read-AnsiText -Keys @($keys | ForEach-Object { $_ })
        $result = Invoke-Prompt { Read-AnsiText 'Name' }
        $result.Value | Should -BeExactly 'ansi'
        (Remove-Ansi $result.Painted) | Should -Match 'An answer is required\.'
    }
}

Describe 'Read-AnsiText — -Validate' {
    It 'returns the answer when validation passes' {
        Set-AnsiTestKeys -Module Read-AnsiText -Keys (New-TestKeys -Text '42')
        $result = Invoke-Prompt { Read-AnsiText 'Port' -Validate { param($v) $v -match '^\d+$' } }
        $result.Value | Should -BeExactly '42'
    }

    It 're-prompts and reports when validation fails' {
        $keys = @()
        $keys += (New-TestKeys -Text 'abc')
        $keys += (New-TestKeys -Text '42')
        Set-AnsiTestKeys -Module Read-AnsiText -Keys $keys
        $result = Invoke-Prompt {
            Read-AnsiText 'Port' -Validate { param($v) $v -match '^\d+$' } -ValidationMessage 'digits only'
        }
        $result.Value | Should -BeExactly '42'
        (Remove-Ansi $result.Painted) | Should -Match 'digits only'
    }

    It 'treats a throwing validator as a failure' {
        $keys = @()
        $keys += (New-TestKeys -Text 'boom')
        $keys += (New-TestKeys -Text 'ok')
        Set-AnsiTestKeys -Module Read-AnsiText -Keys $keys
        $result = Invoke-Prompt {
            Read-AnsiText 'Value' -Validate { param($v) if ($v -eq 'boom') { throw 'no' } ; $true }
        }
        $result.Value | Should -BeExactly 'ok'
    }

    It 'validates the default too' {
        $keys = @()
        $keys += (New-TestKeys)
        $keys += (New-TestKeys -Text '9')
        Set-AnsiTestKeys -Module Read-AnsiText -Keys $keys
        $result = Invoke-Prompt {
            Read-AnsiText 'Port' -Default 'nope' -Validate { param($v) $v -match '^\d+$' }
        }
        $result.Value | Should -BeExactly '9'
    }
}

Describe 'Read-AnsiText — cancel, timeout, and non-interactive' {
    It 'returns $null when Escape is pressed' {
        Set-AnsiTestKeys -Module Read-AnsiText -Keys (New-TestKeys -Text 'abc' -Finish Escape)
        $result = Invoke-Prompt { Read-AnsiText 'Name' }
        $result.Value | Should -BeNullOrEmpty
    }

    It 'returns $null when the timeout expires' {
        Set-AnsiTestKeys -Module Read-AnsiText -Keys @()
        $result = Invoke-Prompt { Read-AnsiText 'Name' -TimeoutSeconds 1 }
        $result.Value | Should -BeNullOrEmpty
    }

    It 'throws when input is redirected' {
        Set-AnsiTestInteractive -Module Read-AnsiText -Value $false
        try {
            { Read-AnsiText 'Name' } | Should -Throw '*interactive console*'
        } finally {
            Set-AnsiTestInteractive -Module Read-AnsiText -Value $true
        }
    }
}

Describe 'Read-AnsiText — markup and no-colour' {
    It 'parses markup in the prompt' {
        Set-AnsiTestKeys -Module Read-AnsiText -Keys (New-TestKeys -Text 'x')
        $result = Invoke-Prompt { Read-AnsiText '[bold]Name[/]' }
        $result.Painted | Should -Match ([regex]::Escape($PSStyle.Bold))
        (Remove-Ansi $result.Painted) | Should -BeLike 'Name: *'
    }

    It 'renders markdown sugar with -Markdown' {
        Set-AnsiTestKeys -Module Read-AnsiText -Keys (New-TestKeys -Text 'x')
        $result = Invoke-Prompt { Read-AnsiText '**Name**' -Markdown }
        $result.Painted | Should -Match ([regex]::Escape($PSStyle.Bold))
    }

    It 'keeps the prompt literal with -Escape' {
        Set-AnsiTestKeys -Module Read-AnsiText -Keys (New-TestKeys -Text 'x')
        $result = Invoke-Prompt { Read-AnsiText '[bold]Name[/]' -Escape }
        (Remove-Ansi $result.Painted) | Should -BeLike '`[bold`]Name`[/`]: *'
    }

    It 'strips styles when the host cannot show them' {
        Set-AnsiTestNoColor -Module Read-AnsiText -Value $true
        try {
            Set-AnsiTestKeys -Module Read-AnsiText -Keys (New-TestKeys -Text 'x')
            $result = Invoke-Prompt { Read-AnsiText '[bold]Name[/]' -AnswerColor BrightRed }
            $result.Painted | Should -Not -Match ([regex]::Escape([char]27))
            $result.Painted | Should -BeExactly 'Name: x'
        } finally {
            Set-AnsiTestNoColor -Module Read-AnsiText -Value $false
        }
    }
}

Describe 'Read-AnsiText — module surface' {
    It 'exports only Read-AnsiText' {
        (Get-Module Read-AnsiText).ExportedFunctions.Keys | Should -Be 'Read-AnsiText'
    }
}
