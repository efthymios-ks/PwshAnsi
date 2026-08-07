#Requires -Version 7.2

# Start-AnsiTitleAnimation.psm1
# Public: Start-AnsiTitleAnimation, Stop-AnsiTitleAnimation, Invoke-AnsiTitleAnimation.
#
# Turns the braille dots in the terminal's window title while your code runs, so a
# long job stays visible on the taskbar even when the window is not in front.
#
# One animation, no styles: a spinner is what a title bar can show. Emoji cannot go
# there (a console title carries no surrogate pairs, so they arrive as ?), and a
# bullet sliding along a track needs padding that a title bar renders in a
# proportional font. The braille frames are single characters that always land.
#
# The three functions share one piece of state (the worker and the title to put
# back), so they live in one module rather than one file each.
#
# The title is set with [Console]::Title, which is SetConsoleTitleW on Windows and
# an escape sequence written by .NET elsewhere. Writing OSC 2 ourselves would go
# through [Console]::OutputEncoding — code page 437 in a default console, where the
# frames turn into question marks. Console::Title takes UTF-16 straight to the API.
#
# The frames tick from a second runspace, so they keep moving while the main thread
# is busy inside a long synchronous command — which is exactly when a title
# animation earns its keep.

Import-Module (Join-Path $PSScriptRoot 'Ansi.Core.psm1') -Force -DisableNameChecking

# The braille dots turning: ⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏. Written as code points so the file's own
# encoding can never be what breaks the animation.
$script:AnsiTitleFrames = @(
    [string][char]0x280B, [string][char]0x2819, [string][char]0x2839, [string][char]0x2838
    [string][char]0x283C, [string][char]0x2834, [string][char]0x2826, [string][char]0x2827
    [string][char]0x2807, [string][char]0x280F
)

# -Speed in milliseconds a frame. Three names instead of a number: a title bar has
# one job, and picking 137ms is not a decision anyone needs to make.
$script:AnsiTitleSpeed = @{
    'slow'   = 500
    'normal' = 250
    'fast'   = 100
}

$script:AnsiTitleState = $null

function Start-AnsiTitleAnimation {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Position = 0)]
        [AllowEmptyString()]
        [string]$Text = '',

        # How fast the dots turn. Normal is a calm quarter second a frame — a title
        # bar is glanced at, not watched.
        [ValidateSet('Slow', 'Normal', 'Fast')]
        [string]$Speed = 'Normal',

        # Put the dots after the text instead of before it.
        [switch]$FrameLast,

        # Animate even when output is redirected (a title is not output, but a
        # non-interactive host has no title bar to animate either).
        [switch]$Force
    )

    if ($null -ne $script:AnsiTitleState) {
        throw 'A title animation is already running; call Stop-AnsiTitleAnimation first.'
    }

    if (-not ($Force -or (Test-AnsiTitleSupported))) {
        Write-Verbose 'No interactive terminal: title animation skipped.'
        return $false
    }

    $titles = [System.Collections.Generic.List[string]]::new()
    foreach ($frame in (Get-AnsiTitleFrame)) {
        $null = $titles.Add((Join-AnsiTitle -Frame $frame -Text $Text -FrameLast:$FrameLast))
    }

    $script:AnsiTitleState = Start-AnsiTitleWorker -Titles $titles.ToArray() `
        -Interval (Get-AnsiTitleInterval -Speed $Speed) -Original (Get-AnsiTitleCurrent)
    return $true
}

function Stop-AnsiTitleAnimation {
    [CmdletBinding()]
    param(
        # Title to leave behind. Default: whatever the title was before starting.
        [AllowEmptyString()]
        [string]$Title
    )

    if ($null -eq $script:AnsiTitleState) { return }

    $state = $script:AnsiTitleState
    $script:AnsiTitleState = $null

    Stop-AnsiTitleWorker -State $state

    $restore = if ($PSBoundParameters.ContainsKey('Title')) { $Title } else { [string]$state.Original }
    Set-AnsiTitle -Title $restore
}

function Invoke-AnsiTitleAnimation {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0, Mandatory)]
        [scriptblock]$ScriptBlock,

        [Parameter(Position = 1)]
        [AllowEmptyString()]
        [string]$Text = '',

        [ValidateSet('Slow', 'Normal', 'Fast')]
        [string]$Speed = 'Normal',

        [switch]$FrameLast,

        [switch]$Force,

        # Title to leave behind when the scriptblock finishes.
        [AllowEmptyString()]
        [string]$FinalTitle
    )

    $splat = @{ Text = $Text; Speed = $Speed }
    if ($FrameLast) { $splat['FrameLast'] = $true }
    if ($Force) { $splat['Force'] = $true }

    $null = Start-AnsiTitleAnimation @splat
    try {
        # The scriptblock's own output passes straight through.
        & $ScriptBlock
    } finally {
        if ($PSBoundParameters.ContainsKey('FinalTitle')) {
            Stop-AnsiTitleAnimation -Title $FinalTitle
        } else {
            Stop-AnsiTitleAnimation
        }
    }
}

# --- frames ---------------------------------------------------------------------

function Get-AnsiTitleFrame {
    [CmdletBinding()]
    param()
    return , @($script:AnsiTitleFrames)
}

# Milliseconds a frame for a speed name.
function Get-AnsiTitleInterval {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Speed)
    $key = $Speed.ToLowerInvariant()
    if (-not $script:AnsiTitleSpeed.ContainsKey($key)) { throw "Unknown title speed '$Speed'." }
    return $script:AnsiTitleSpeed[$key]
}

# Frame and text into one title.
function Join-AnsiTitle {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Frame,
        [AllowEmptyString()][string]$Text = '',
        [switch]$FrameLast
    )
    if ([string]::IsNullOrEmpty($Text)) { return $Frame }
    if ($FrameLast) { return "$Text $Frame" }
    return "$Frame $Text"
}

# --- the terminal ---------------------------------------------------------------

function Test-AnsiTitleSupported {
    try { if ([Console]::IsOutputRedirected) { return $false } } catch { return $false }
    return $true
}

function Get-AnsiTitleCurrent {
    # Console::Title cannot be read on Unix; the host knows what it last set.
    try { return [string]$Host.UI.RawUI.WindowTitle } catch { return '' }
}

# Set the window title. Console::Title is UTF-16 all the way to SetConsoleTitleW on
# Windows, so a braille frame arrives intact whatever the console code page is. The
# OSC 2 fallback is written as raw UTF-8 bytes for the same reason: [Console]::Write
# would run it through a code page and hand back question marks.
function Set-AnsiTitle {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Title)
    try {
        [Console]::Title = $Title
        return
    } catch { }
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes("$([char]27)]2;$Title$([char]7)")
        $stdout = [Console]::OpenStandardOutput()
        $stdout.Write($bytes, 0, $bytes.Length)
        $stdout.Flush()
    } catch {
        try { $Host.UI.RawUI.WindowTitle = $Title } catch { }
    }
}

# --- the worker -----------------------------------------------------------------

# A second runspace running plain .NET: set a frame, sleep, repeat until the shared
# stop flag flips. No PowerShell host calls, so nothing here depends on the main
# thread being free.
function Start-AnsiTitleWorker {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string[]]$Titles,
        [Parameter(Mandatory)][int]$Interval,
        [AllowEmptyString()][string]$Original
    )
    $shared = [hashtable]::Synchronized(@{ Stop = $false; Titles = $Titles; Interval = $Interval })

    $runspace = [runspacefactory]::CreateRunspace()
    $runspace.ApartmentState = 'MTA'
    $runspace.ThreadOptions = 'ReuseThread'
    $runspace.Open()
    $runspace.SessionStateProxy.SetVariable('Shared', $shared)

    $worker = [powershell]::Create()
    $worker.Runspace = $runspace
    $null = $worker.AddScript({
            $index = 0
            while (-not $Shared.Stop) {
                $title = $Shared.Titles[$index % $Shared.Titles.Count]
                try {
                    [Console]::Title = $title
                } catch {
                    try {
                        $bytes = [System.Text.Encoding]::UTF8.GetBytes("$([char]27)]2;$title$([char]7)")
                        $stdout = [Console]::OpenStandardOutput()
                        $stdout.Write($bytes, 0, $bytes.Length)
                        $stdout.Flush()
                    } catch { }
                }
                $index++
                [System.Threading.Thread]::Sleep($Shared.Interval)
            }
        })

    $handle = $worker.BeginInvoke()

    return [PSCustomObject]@{
        Shared   = $shared
        Worker   = $worker
        Runspace = $runspace
        Handle   = $handle
        Original = $Original
    }
}

function Stop-AnsiTitleWorker {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$State)

    try { $State.Shared.Stop = $true } catch { }

    try {
        # Give the loop one interval to notice, then take the runspace down.
        $null = $State.Worker.EndInvoke($State.Handle)
    } catch {
        try { $State.Worker.Stop() } catch { }
    } finally {
        try { $State.Worker.Dispose() } catch { }
        try { $State.Runspace.Close() } catch { }
        try { $State.Runspace.Dispose() } catch { }
    }
}

Export-ModuleMember -Function Start-AnsiTitleAnimation, Stop-AnsiTitleAnimation, Invoke-AnsiTitleAnimation
