#Requires -Version 7.2

# Read-AnsiPause.psm1
# Public: Read-AnsiPause — wait for a key (or Enter) before carrying on.
# Returns $true when a key was pressed, $false on Esc, $null on timeout.
# Depends on Ansi.Core.psm1 for markup, colour, cursor control, and input seams.

Import-Module (Join-Path $PSScriptRoot 'Ansi.Core.psm1') -Force -DisableNameChecking

function Read-AnsiPause {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Position = 0)]
        [AllowEmptyString()]
        [Alias('Prompt')]
        [string]$Message,

        # Default: any key continues. -Enter waits for Enter specifically.
        [switch]$Enter,

        [Alias('Color')]
        [string]$MessageColor = 'BrightBlack',

        [ValidateRange(0, [int]::MaxValue)]
        [int]$TimeoutSeconds = 0,

        # Count the remaining seconds down in place while waiting.
        [switch]$ShowCountdown,

        # Leave the message on screen instead of erasing it once the key arrives.
        [switch]$KeepMessage,

        [switch]$Markdown,

        [switch]$Escape
    )

    if (-not (Test-AnsiInteractive)) {
        throw 'Read-AnsiPause needs an interactive console: input is redirected.'
    }

    $noColor = Test-AnsiNoColor
    $messageFg = Get-AnsiColorName -Name $MessageColor

    if (-not $PSBoundParameters.ContainsKey('Message')) {
        $Message = if ($Enter) { 'Press enter to continue' } else { 'Press any key to continue' }
    }

    $deadline = if ($TimeoutSeconds -gt 0) { [datetime]::UtcNow.AddSeconds($TimeoutSeconds) } else { $null }
    $result = $null

    # Nothing is typed at a pause, so the cursor has no business blinking.
    $cursor = Hide-AnsiCursor
    	try {
        while ($true) {
            Write-AnsiPauseMessage -Message $Message -Fg $messageFg -Deadline $deadline `
                -ShowCountdown:$ShowCountdown -NoColor:$noColor -Markdown:$Markdown -Escape:$Escape

            if ($null -ne $deadline) {
                $timedOut = $false
                while (-not (Test-AnsiKeyAvailable)) {
                    if ([datetime]::UtcNow -ge $deadline) { $timedOut = $true; break }
                    # Redraw once a second so a countdown ticks; otherwise just wait.
                    if ($ShowCountdown) { break }
                    Start-AnsiWait
                }
                if ($timedOut) { break }
                if ($ShowCountdown -and -not (Test-AnsiKeyAvailable)) {
                    Start-AnsiWait -Milliseconds 250
                    continue
                }
            }

            $key = Read-AnsiKeyInfo
            if ($null -eq $key) { break }

            if ($Enter -and $key.Key -ne 'Enter' -and $key.Key -ne 'Escape') { continue }
            $result = ($key.Key -ne 'Escape')
            break
        }
    } finally {
        Restore-AnsiCursor -State $cursor
    }

    # The message row is transient by default: erase it so the pause leaves no trace.
    if ($KeepMessage) {
        Write-Host ''
    } else {
        Clear-AnsiLine
    }
    return $result
}

function Write-AnsiPauseMessage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Message,
        [AllowNull()][string]$Fg,
        [AllowNull()][object]$Deadline,
        [switch]$ShowCountdown,
        [switch]$NoColor,
        [switch]$Markdown,
        [switch]$Escape
    )
    $runs = [System.Collections.Generic.List[object]]::new()

    if ($Escape) {
        $null = $runs.Add((New-AnsiPauseRun -Text $Message -Fg $Fg))
    } else {
        $parsed = ConvertFrom-AnsiMarkup -Text $Message -AsMarkdown:$Markdown
        foreach ($r in $parsed) {
            if (-not $r.Fg) { $r.Fg = $Fg }
            $null = $runs.Add($r)
        }
    }

    if ($ShowCountdown -and $null -ne $Deadline) {
        $left = [Math]::Max(0, [int][Math]::Ceiling(([datetime]$Deadline - [datetime]::UtcNow).TotalSeconds))
        $null = $runs.Add((New-AnsiPauseRun -Text (' (' + $left + 's)') -Fg $Fg))
    }

    Clear-AnsiLine
    Write-Host (Format-AnsiLine -Runs $runs.ToArray() -Width 0 -Justify Left -NoColor:$NoColor) -NoNewline
}

function New-AnsiPauseRun {
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

Export-ModuleMember -Function Read-AnsiPause
