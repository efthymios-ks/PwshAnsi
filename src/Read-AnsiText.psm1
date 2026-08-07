#Requires -Version 7.2

# Read-AnsiText.psm1
# Public: Read-AnsiText — prompt for a line of text and return it.
# Reads keys itself so the answer can be coloured, masked, timed out, and
# validated. Returns $null when the prompt is cancelled (Esc) or times out.
# Depends on Ansi.Core.psm1 for markup, colour, and the console input seams.

Import-Module (Join-Path $PSScriptRoot 'Ansi.Core.psm1') -Force -DisableNameChecking

function Read-AnsiText {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Position = 0, Mandatory)]
        [AllowEmptyString()]
        [string]$Prompt,

        [Alias('DefaultAnswer')]
        [AllowNull()]
        [string]$Default,

        [string]$PromptColor,

        [string]$AnswerColor = 'BrightCyan',

        [string]$DefaultColor = 'BrightBlack',

        [switch]$AllowEmpty,

        [switch]$Secret,

        [scriptblock]$Validate,

        [string]$ValidationMessage = 'That answer is not valid.',

        [string]$ValidationColor = 'BrightRed',

        [ValidateRange(0, [int]::MaxValue)]
        [int]$TimeoutSeconds = 0,

        [switch]$Markdown,

        [switch]$Escape
    )

    if (-not (Test-AnsiInteractive)) {
        throw 'Read-AnsiText needs an interactive console: input is redirected.'
    }

    $noColor = Test-AnsiNoColor
    $answerFg = Get-AnsiColorName -Name $AnswerColor
    $defaultFg = Get-AnsiColorName -Name $DefaultColor
    $validationFg = Get-AnsiColorName -Name $ValidationColor
    $promptFg = if ($PromptColor) { Get-AnsiColorName -Name $PromptColor } else { $null }
    $hasDefault = $PSBoundParameters.ContainsKey('Default') -and $null -ne $Default

    while ($true) {
        Write-AnsiPromptLine -Prompt $Prompt -PromptFg $promptFg -Default $Default -HasDefault:$hasDefault `
            -DefaultFg $defaultFg -NoColor:$noColor -Markdown:$Markdown -Escape:$Escape

        $result = Read-AnsiKeyLine -Mask:$Secret -Fg $answerFg -TimeoutSeconds $TimeoutSeconds -NoColor:$noColor
        if ($result.TimedOut -or $result.Cancelled) { return $null }

        $answer = $result.Value
        if ([string]::IsNullOrEmpty($answer)) {
            if ($hasDefault) { $answer = $Default }
            elseif (-not $AllowEmpty) {
                Write-AnsiPromptNote -Text 'An answer is required.' -Fg $validationFg -NoColor:$noColor
                continue
            }
        }

        if ($Validate) {
            $ok = $false
            try { $ok = [bool](& $Validate $answer) } catch { $ok = $false }
            if (-not $ok) {
                Write-AnsiPromptNote -Text $ValidationMessage -Fg $validationFg -NoColor:$noColor
                continue
            }
        }

        return $answer
    }
}

# The prompt row: markup-parsed prompt, then a dim default hint, cursor left on
# the same line for the answer.
function Write-AnsiPromptLine {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Prompt,
        [AllowNull()][string]$PromptFg,
        [AllowNull()][string]$Default,
        [switch]$HasDefault,
        [AllowNull()][string]$DefaultFg,
        [switch]$NoColor,
        [switch]$Markdown,
        [switch]$Escape
    )
    $runs = [System.Collections.Generic.List[object]]::new()

    if ($Escape) {
        $null = $runs.Add((New-AnsiPromptRun -Text $Prompt -Fg $PromptFg))
    } else {
        $parsed = ConvertFrom-AnsiMarkup -Text $Prompt -AsMarkdown:$Markdown
        foreach ($r in $parsed) {
            if (-not $r.Fg) { $r.Fg = $PromptFg }
            $null = $runs.Add($r)
        }
    }

    if ($HasDefault) {
        $null = $runs.Add((New-AnsiPromptRun -Text (' [' + $Default + ']') -Fg $DefaultFg))
    }
    $null = $runs.Add((New-AnsiPromptRun -Text ': ' -Fg $PromptFg))

    $line = Format-AnsiLine -Runs $runs.ToArray() -Width 0 -Justify Left -NoColor:$NoColor
    Write-Host $line -NoNewline
}

function Write-AnsiPromptNote {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Text,
        [AllowNull()][string]$Fg,
        [switch]$NoColor
    )
    $runs = @(New-AnsiPromptRun -Text $Text -Fg $Fg)
    Write-Host (Format-AnsiLine -Runs $runs -Width 0 -Justify Left -NoColor:$NoColor)
}

# Read one line of keys, echoing as it goes. Returns Value plus why it stopped, so
# callers can tell an empty answer from a cancelled or timed-out one. It lives here
# rather than in Ansi.Core so the console seams resolve in this module's scope —
# which is what tests replace.
function Read-AnsiKeyLine {
    [CmdletBinding()]
    param(
        [switch]$Mask,
        [AllowNull()][string]$Fg,
        [int]$TimeoutSeconds = 0,
        [switch]$NoColor
    )
    $buffer = [System.Text.StringBuilder]::new()
    $deadline = if ($TimeoutSeconds -gt 0) { [datetime]::UtcNow.AddSeconds($TimeoutSeconds) } else { $null }

    $prefix = ''
    $suffix = ''
    if (-not $NoColor -and $Fg) {
        $prefix = $PSStyle.Foreground.$Fg
        $suffix = $PSStyle.Reset
    }

    # This one is typed into: the cursor has to be visible to type against.
    $cursor = Show-AnsiCursor
    	try {
        while ($true) {
            if ($null -ne $deadline) {
                while (-not (Test-AnsiKeyAvailable)) {
                    if ([datetime]::UtcNow -ge $deadline) {
                        return [PSCustomObject]@{ Value = $buffer.ToString(); TimedOut = $true; Cancelled = $false }
                    }
                    Start-AnsiWait
                }
            }

            $key = Read-AnsiKeyInfo
            if ($null -eq $key) {
                return [PSCustomObject]@{ Value = $buffer.ToString(); TimedOut = $true; Cancelled = $false }
            }

            switch ($key.Key) {
                'Enter' {
                    Write-Host ''
                    return [PSCustomObject]@{ Value = $buffer.ToString(); TimedOut = $false; Cancelled = $false }
                }
                'Escape' {
                    Write-Host ''
                    return [PSCustomObject]@{ Value = $buffer.ToString(); TimedOut = $false; Cancelled = $true }
                }
                'Backspace' {
                    if ($buffer.Length -gt 0) {
                        $null = $buffer.Remove($buffer.Length - 1, 1)
                        Write-Host "`b `b" -NoNewline
                    }
                    continue
                }
                default {
                    $char = $key.KeyChar
                    if ([char]::IsControl($char)) { continue }
                    $null = $buffer.Append($char)
                    $echo = if ($Mask) { '*' } else { [string]$char }
                    Write-Host ($prefix + $echo + $suffix) -NoNewline
                    continue
                }
            }
        }
    } finally {
        Restore-AnsiCursor -State $cursor
    }
}

function New-AnsiPromptRun {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text,
        [AllowNull()][string]$Fg
    )
    [PSCustomObject]@{
        Text   = $Text
        Fg     = $(if ($Fg) { $Fg } else { $null })
        Bg     = $null
        Styles = @()
        Link   = $null
    }
}

Export-ModuleMember -Function Read-AnsiText
