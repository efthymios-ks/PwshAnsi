#Requires -Version 7.2

# Read-AnsiConfirm.psm1
# Public: Read-AnsiConfirm — ask a yes/no question and return a [bool].
# Returns $null when the prompt is cancelled (Esc) or times out.
# Depends on Ansi.Core.psm1 for markup, colour, and the console input seams.

Import-Module (Join-Path $PSScriptRoot 'Ansi.Core.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'Ansi.Input.psm1') -Force -DisableNameChecking

function Read-AnsiConfirm {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Position = 0, Mandatory)]
        [AllowEmptyString()]
        [string]$Prompt,

        [Alias('DefaultAnswer')]
        [AllowNull()]
        [System.Nullable[bool]]$Default = $true,

        [string]$PromptColor,

        [string]$AnswerColor = 'BrightCyan',

        [string]$ChoiceColor = 'BrightBlack',

        [string]$SuccessMessage,

        [string]$FailureMessage,

        [string]$SuccessColor = 'BrightGreen',

        [string]$FailureColor = 'BrightRed',

        [ValidateRange(0, [int]::MaxValue)]
        [int]$TimeoutSeconds = 0,

        [switch]$Markdown,

        [int]$Row = -1,

        [int]$Column = -1,

        [switch]$Escape
    )

    if (-not (Test-AnsiInteractive)) {
        throw 'Read-AnsiConfirm needs an interactive console: input is redirected.'
    }

    $noColor = Test-AnsiNoColor
    $answerFg = Get-AnsiColorName -Name $AnswerColor
    $choiceFg = Get-AnsiColorName -Name $ChoiceColor
    $successFg = Get-AnsiColorName -Name $SuccessColor
    $failureFg = Get-AnsiColorName -Name $FailureColor
    $promptFg = if ($PromptColor) { Get-AnsiColorName -Name $PromptColor } else { $null }

    # The default is the capitalised choice, as every CLI spells it.
    $choices = '[y/n]'
    if ($null -ne $Default) { $choices = if ($Default) { '[Y/n]' } else { '[y/N]' } }

    Write-AnsiConfirmPrompt -Prompt $Prompt -PromptFg $promptFg -Choices $choices -ChoiceFg $choiceFg `
        -NoColor:$noColor -Markdown:$Markdown -Escape:$Escape -Row $Row -Column $Column

    $answer = $null
    $deadline = if ($TimeoutSeconds -gt 0) { [datetime]::UtcNow.AddSeconds($TimeoutSeconds) } else { $null }

    # One key answers this, so the cursor stays out of the way.
    $cursor = Hide-AnsiCursor
    	try {
        while ($null -eq $answer) {
            if ($null -ne $deadline) {
                while (-not (Test-AnsiKeyAvailable)) {
                    if ([datetime]::UtcNow -ge $deadline) {
                        Write-Host ''
                        return $null
                    }
                    Start-AnsiWait
                }
            }

            $key = Read-AnsiKeyInfo
            if ($null -eq $key) {
                Write-Host ''
                return $null
            }

            switch ($key.Key) {
                'Escape' {
                    Write-Host ''
                    return $null
                }
                'Enter' {
                    if ($null -eq $Default) { continue }
                    $answer = [bool]$Default
                    continue
                }
                default {
                    switch ([char]::ToLowerInvariant($key.KeyChar)) {
                        'y' { $answer = $true }
                        'n' { $answer = $false }
                        default { continue }
                    }
                }
            }
        }
    } finally {
        Restore-AnsiCursor -State $cursor
    }

    # Echo the answer the caller did not type, so the row reads back correctly.
    $word = if ($answer) { 'yes' } else { 'no' }
    Write-Host (Format-AnsiLine -Runs @((New-AnsiConfirmRun -Text $word -Fg $answerFg)) `
            -Width 0 -Justify Left -NoColor:$noColor)

    if ($answer -and $SuccessMessage) {
        Write-AnsiConfirmNote -Text $SuccessMessage -Fg $successFg -NoColor:$noColor -Markdown:$Markdown -Escape:$Escape
    } elseif (-not $answer -and $FailureMessage) {
        Write-AnsiConfirmNote -Text $FailureMessage -Fg $failureFg -NoColor:$noColor -Markdown:$Markdown -Escape:$Escape
    }

    return $answer
}

function Write-AnsiConfirmPrompt {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Prompt,
        [AllowNull()][string]$PromptFg,
        [Parameter(Mandatory)][string]$Choices,
        [AllowNull()][string]$ChoiceFg,
        [switch]$NoColor,
        [switch]$Markdown,
        [switch]$Escape,
        [int]$Row = -1,
        [int]$Column = -1
    )
    $runs = [System.Collections.Generic.List[object]]::new()

    if ($Escape) {
        $null = $runs.Add((New-AnsiConfirmRun -Text $Prompt -Fg $PromptFg))
    } else {
        $parsed = ConvertFrom-AnsiMarkup -Text $Prompt -AsMarkdown:$Markdown
        foreach ($r in $parsed) {
            if (-not $r.Fg) { $r.Fg = $PromptFg }
            $null = $runs.Add($r)
        }
    }

    $null = $runs.Add((New-AnsiConfirmRun -Text (' ' + $Choices) -Fg $ChoiceFg))
    $null = $runs.Add((New-AnsiConfirmRun -Text ': ' -Fg $PromptFg))

    $line = Format-AnsiLine -Runs $runs.ToArray() -Width 0 -Justify Left -NoColor:$NoColor
    if (Test-AnsiPositioned -Row $Row -Column $Column) {
        # Placed: one synchronized write, and the answer is echoed after it by the caller.
        $null = Write-AnsiPromptFrame -Rows @($line) -Row $Row -Column $Column
        Set-AnsiPromptCursor -Row $Row -Column ($Column + (Measure-AnsiRow -Runs $runs.ToArray()))
    } else {
        Write-Host $line -NoNewline
    }
}

function Write-AnsiConfirmNote {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Text,
        [AllowNull()][string]$Fg,
        [switch]$NoColor,
        [switch]$Markdown,
        [switch]$Escape
    )
    $runs = $null
    if ($Escape) {
        $runs = @(New-AnsiConfirmRun -Text $Text -Fg $Fg)
    } else {
        $runs = ConvertFrom-AnsiMarkup -Text $Text -AsMarkdown:$Markdown
        foreach ($r in $runs) { if (-not $r.Fg) { $r.Fg = $Fg } }
    }
    Write-Host (Format-AnsiLine -Runs @($runs) -Width 0 -Justify Left -NoColor:$NoColor)
}

function New-AnsiConfirmRun {
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

Export-ModuleMember -Function Read-AnsiConfirm
