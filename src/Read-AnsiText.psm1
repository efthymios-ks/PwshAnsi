#Requires -Version 7.2

# Read-AnsiText.psm1
# Public: Read-AnsiText — prompt for a line of text and return it.
# Reads keys itself so the answer can be coloured, masked, timed out, and
# validated. Returns $null when the prompt is cancelled (Esc) or times out.
# Depends on Ansi.Core.psm1 for markup, colour, and the console input seams.

Import-Module (Join-Path $PSScriptRoot 'Ansi.Core.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'Ansi.Input.psm1') -Force -DisableNameChecking

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

# One line of keys against a field model: the caret moves, text is inserted and deleted
# where it sits, and a field too narrow for its text scrolls sideways. Returns Value plus
# why it stopped, so callers can tell an empty answer from a cancelled or timed-out one.
# It lives here rather than in Ansi.Core so the console seams resolve in this module's
# scope - which is what tests replace.
function Read-AnsiKeyLine {
    [CmdletBinding()]
    param(
        [switch]$Mask,
        [AllowNull()][string]$Fg,
        [int]$TimeoutSeconds = 0,
        [switch]$NoColor
    )
    $state = New-AnsiFieldState
    $deadline = if ($TimeoutSeconds -gt 0) { [datetime]::UtcNow.AddSeconds($TimeoutSeconds) } else { $null }

    # Defined here so they bind to this module's seams, which is what the tests replace.
    $readKey = { Read-AnsiKeyInfo }
    $keyAvailable = { Test-AnsiKeyAvailable }
    $wait = { Start-AnsiWait }
    $stopOn = { param($k) [string]$k.Key -eq 'Escape' }

    $prefix = ''
    $suffix = ''
    if (-not $NoColor -and $Fg) {
        $prefix = $PSStyle.Foreground.$Fg
        $suffix = $PSStyle.Reset
    }

    # A real terminal gets the field repainted in place, which is what makes the caret and the
    # sideways scroll possible. Anywhere else - a captured or redirected host - there is nothing
    # to position against, so the answer is echoed as it grows, exactly as it always was.
    $row = -1
    $column = -1
    $width = 0
    $positioned = Test-AnsiTerminal
    if ($positioned) {
        try {
            $row = [Console]::CursorTop
            $column = [Console]::CursorLeft
            $width = [Math]::Max(1, [Console]::BufferWidth - $column - 1)
        } catch { $positioned = $false }
    }

    $paint = {
        $view = Get-AnsiFieldView -State $state -Width $width
        $state.Window = $view.Window
        $shown = $Mask ? ('*' * $view.Visible.Length) : $view.Visible
        try {
            [Console]::SetCursorPosition($column, $row)
            Write-Host ($prefix + $shown + $suffix + (' ' * [Math]::Max(0, $width - $shown.Length))) -NoNewline
            [Console]::SetCursorPosition($column + $view.CaretColumn, $row)
        } catch { }
    }

    # This one is typed into: the cursor has to be visible to type against.
    $cursor = Show-AnsiCursor
    try {
        while ($true) {
            $burst = Wait-AnsiKeyBurst -Deadline $deadline -ReadKey $readKey -KeyAvailable $keyAvailable -Wait $wait -StopOn $stopOn
            # Nothing at all means the input ended: a timeout, or a host with no more keys.
            if ($null -eq $burst -or @($burst).Count -eq 0) {
                return [PSCustomObject]@{ Value = $state.Text; TimedOut = $true; Cancelled = $false }
            }

            $keys = @($burst)
            for ($i = 0; $i -lt $keys.Count; $i++) {
                $key = $keys[$i]
                if ($null -eq $key) {
                    return [PSCustomObject]@{ Value = $state.Text; TimedOut = $true; Cancelled = $false }
                }

                # A newline in the middle of a burst came from a paste, not from a finger: it is
                # kept in the answer and drawn as an escape. Only a newline the burst ends on is
                # someone answering, and that one submits.
                $submits = ([string]$key.Key -eq 'Enter' -and $i -eq $keys.Count - 1)

                if ($submits -or [string]$key.Key -eq 'Escape') {
                    if ($positioned) { & $paint }
                    Write-Host ''
                    return [PSCustomObject]@{
                        Value     = $state.Text
                        TimedOut  = $false
                        Cancelled = ([string]$key.Key -eq 'Escape')
                    }
                }

                $before = $state
                $state = Update-AnsiFieldState -State $state -Key $key

                if (-not $positioned) {
                    # No cursor to move: echo the one character that grew, or rub out the one
                    # that went. Caret moves and mid-text edits simply have nothing to show.
                    if ($state.Text.Length -gt $before.Text.Length) {
                        $echo = $Mask ? '*' : [string]$key.KeyChar
                        Write-Host ($prefix + $echo + $suffix) -NoNewline
                    } elseif ($state.Text.Length -lt $before.Text.Length) {
                        Write-Host "`b `b" -NoNewline
                    }
                }
            }

            if ($positioned) { & $paint }
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
