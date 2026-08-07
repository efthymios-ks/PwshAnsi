#Requires -Version 7.2
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

# Read-AnsiPause.Tests.ps1
# Pester 5 tests for Read-AnsiPause.
#
# The console seams (Test-AnsiInteractive, Test-AnsiKeyAvailable, Read-AnsiKeyInfo,
# Start-AnsiWait) are replaced inside the module scope, so a scripted key list drives
# the pause: no keyboard, no waiting.

BeforeAll {
    $script:src = Join-Path (Split-Path -Parent $PSScriptRoot) 'src'
    Import-Module (Join-Path $script:src 'Read-AnsiPause.psm1') -Force -DisableNameChecking

    & (Get-Module Read-AnsiPause) {
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

    function New-Key {
        param([Parameter(Mandatory)][System.ConsoleKey]$Key)
        return [System.ConsoleKeyInfo]::new("`0", $Key, $false, $false, $false)
    }

    function New-Char {
        param([Parameter(Mandatory)][char]$Char)
        return [System.ConsoleKeyInfo]::new($Char, [System.ConsoleKey]::A, $false, $false, $false)
    }

    function Set-AnsiTestKeys {
        param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Keys)
        & (Get-Module Read-AnsiPause) { param($k) $script:AnsiKeys = $k; $script:AnsiKeyIndex = 0 } $Keys
    }

    function Set-AnsiTestNoColor {
        param([Parameter(Mandatory)][bool]$Value)
        & (Get-Module Read-AnsiPause) { param($v) $script:AnsiTestNoColor = $v } $Value
    }

    function Set-AnsiTestInteractive {
        param([Parameter(Mandatory)][bool]$Value)
        & (Get-Module Read-AnsiPause) { param($v) $script:AnsiInteractive = $v } $Value
    }

    # Returns the value, the painted rows (cursor-control-only records dropped), and
    # the raw stream for assertions about the erase.
    function Invoke-Pause {
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

    function Get-PaintedText {
        param([Parameter(Mandatory)][object]$Result)
        return (Remove-Ansi (($Result.Rows -join '')))
    }
}

Describe 'Read-AnsiPause — waiting for a key' {
    It 'returns $true when any key is pressed' {
        Set-AnsiTestKeys -Keys @((New-Char -Char 'x'))
        (Invoke-Pause { Read-AnsiPause }).Value | Should -BeTrue
    }

    It 'accepts Enter as any key' {
        Set-AnsiTestKeys -Keys @((New-Key -Key Enter))
        (Invoke-Pause { Read-AnsiPause }).Value | Should -BeTrue
    }

    It 'accepts an arrow key as any key' {
        Set-AnsiTestKeys -Keys @((New-Key -Key DownArrow))
        (Invoke-Pause { Read-AnsiPause }).Value | Should -BeTrue
    }

    It 'returns $false on Escape' {
        Set-AnsiTestKeys -Keys @((New-Key -Key Escape))
        (Invoke-Pause { Read-AnsiPause }).Value | Should -BeFalse
    }

    It 'writes the default message' {
        Set-AnsiTestKeys -Keys @((New-Char -Char 'x'))
        $result = Invoke-Pause { Read-AnsiPause }
        (Get-PaintedText -Result $result) | Should -BeExactly 'Press any key to continue'
    }
}

Describe 'Read-AnsiPause — -Enter' {
    It 'waits for Enter, ignoring other keys' {
        Set-AnsiTestKeys -Keys @((New-Char -Char 'x'), (New-Char -Char 'y'), (New-Key -Key Enter))
        (Invoke-Pause { Read-AnsiPause -Enter }).Value | Should -BeTrue
    }

    It 'still honours Escape' {
        Set-AnsiTestKeys -Keys @((New-Char -Char 'x'), (New-Key -Key Escape))
        (Invoke-Pause { Read-AnsiPause -Enter }).Value | Should -BeFalse
    }

    It 'says which key it wants' {
        Set-AnsiTestKeys -Keys @((New-Key -Key Enter))
        $result = Invoke-Pause { Read-AnsiPause -Enter }
        (Get-PaintedText -Result $result) | Should -BeExactly 'Press enter to continue'
    }
}

Describe 'Read-AnsiPause — the message' {
    It 'takes a custom message positionally' {
        Set-AnsiTestKeys -Keys @((New-Char -Char 'x'))
        $result = Invoke-Pause { Read-AnsiPause 'Review, then continue' }
        (Get-PaintedText -Result $result) | Should -BeExactly 'Review, then continue'
    }

    It 'accepts -Prompt as an alias' {
        Set-AnsiTestKeys -Keys @((New-Char -Char 'x'))
        $result = Invoke-Pause { Read-AnsiPause -Prompt 'hold on' }
        (Get-PaintedText -Result $result) | Should -BeExactly 'hold on'
    }

    It 'parses markup' {
        Set-AnsiTestKeys -Keys @((New-Char -Char 'x'))
        $result = Invoke-Pause { Read-AnsiPause '[bold]hold on[/]' }
        ($result.Rows -join '') | Should -Match ([regex]::Escape($PSStyle.Bold))
        (Get-PaintedText -Result $result) | Should -BeExactly 'hold on'
    }

    It 'renders markdown sugar with -Markdown' {
        Set-AnsiTestKeys -Keys @((New-Char -Char 'x'))
        $result = Invoke-Pause { Read-AnsiPause ':warn: **stop**' -Markdown }
        (Get-PaintedText -Result $result) | Should -BeExactly ([string][char]0x26A0 + ' stop')
    }

    It 'stays literal with -Escape' {
        Set-AnsiTestKeys -Keys @((New-Char -Char 'x'))
        $result = Invoke-Pause { Read-AnsiPause '[bold]x[/]' -Escape }
        (Get-PaintedText -Result $result) | Should -BeExactly '[bold]x[/]'
    }

    It 'colours the message with -MessageColor' {
        Set-AnsiTestKeys -Keys @((New-Char -Char 'x'))
        $result = Invoke-Pause { Read-AnsiPause -MessageColor BrightRed }
        ($result.Rows -join '') | Should -Match ([regex]::Escape($PSStyle.Foreground.BrightRed))
    }

    It 'accepts -Color as an alias' {
        Set-AnsiTestKeys -Keys @((New-Char -Char 'x'))
        $result = Invoke-Pause { Read-AnsiPause -Color BrightRed }
        ($result.Rows -join '') | Should -Match ([regex]::Escape($PSStyle.Foreground.BrightRed))
    }

    It 'throws on an unknown colour' {
        Set-AnsiTestKeys -Keys @((New-Char -Char 'x'))
        { Read-AnsiPause -MessageColor Nope } | Should -Throw
    }

    It 'accepts an empty message' {
        Set-AnsiTestKeys -Keys @((New-Char -Char 'x'))
        $result = Invoke-Pause { Read-AnsiPause '' }
        (Get-PaintedText -Result $result) | Should -BeExactly ''
        $result.Value | Should -BeTrue
    }
}

Describe 'Read-AnsiPause — erasing and -KeepMessage' {
    It 'erases the message once the key arrives' {
        Set-AnsiTestKeys -Keys @((New-Char -Char 'x'))
        $result = Invoke-Pause { Read-AnsiPause }
        # Clear-line is emitted after the message, so the pause leaves no trace.
        $result.Raw | Should -Match ([regex]::Escape("$([char]27)[2K"))
    }

    It 'keeps the message with -KeepMessage' {
        Set-AnsiTestKeys -Keys @((New-Char -Char 'x'))
        $result = Invoke-Pause { Read-AnsiPause 'done' -KeepMessage }
        (Get-PaintedText -Result $result) | Should -Match 'done'
        $result.Value | Should -BeTrue
    }
}

Describe 'Read-AnsiPause — timeout and countdown' {
    It 'returns $null when the timeout expires' {
        Set-AnsiTestKeys -Keys @()
        (Invoke-Pause { Read-AnsiPause -TimeoutSeconds 1 }).Value | Should -BeNullOrEmpty
    }

    It 'returns $true when a key beats the timeout' {
        Set-AnsiTestKeys -Keys @((New-Char -Char 'x'))
        (Invoke-Pause { Read-AnsiPause -TimeoutSeconds 5 }).Value | Should -BeTrue
    }

    It 'shows the seconds left with -ShowCountdown' {
        Set-AnsiTestKeys -Keys @()
        $result = Invoke-Pause { Read-AnsiPause -TimeoutSeconds 1 -ShowCountdown }
        (Get-PaintedText -Result $result) | Should -Match '\(\d+s\)'
    }

    It 'does not show a countdown without a timeout' {
        Set-AnsiTestKeys -Keys @((New-Char -Char 'x'))
        $result = Invoke-Pause { Read-AnsiPause -ShowCountdown }
        (Get-PaintedText -Result $result) | Should -Not -Match '\(\d+s\)'
    }

    It 'rejects a negative timeout' {
        { Read-AnsiPause -TimeoutSeconds -1 } | Should -Throw
    }
}

Describe 'Read-AnsiPause — non-interactive and NO_COLOR' {
    It 'throws when input is redirected' {
        Set-AnsiTestInteractive -Value $false
        try {
            { Read-AnsiPause } | Should -Throw '*interactive console*'
        } finally {
            Set-AnsiTestInteractive -Value $true
        }
    }

    It 'strips styles but keeps the wording' {
        Set-AnsiTestNoColor -Value $true
        try {
            Set-AnsiTestKeys -Keys @((New-Char -Char 'x'))
            $result = Invoke-Pause { Read-AnsiPause '[bold]hold on[/]' -MessageColor BrightRed }
            ($result.Rows -join '') | Should -Not -Match ([regex]::Escape([char]27))
            (Get-PaintedText -Result $result) | Should -BeExactly 'hold on'
        } finally {
            Set-AnsiTestNoColor -Value $false
        }
    }
}

Describe 'Read-AnsiPause — module surface' {
    It 'exports only Read-AnsiPause' {
        (Get-Module Read-AnsiPause).ExportedFunctions.Keys | Should -Be 'Read-AnsiPause'
    }
}
