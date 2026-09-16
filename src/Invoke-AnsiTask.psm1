#Requires -Version 7.2

# Invoke-AnsiTask.psm1
# Public: Invoke-AnsiTask — runs work and reports on it while it runs.
#
# Unlike Format-Ansi*, this writes as it goes: a task that has not finished has
# nothing to hand a writer. The same reason the Read-Ansi* prompts write directly.
#
#     ✔ restore   0.4s
#     ✔ build     2.1s
#     → test
#     ████████████████████░░░░░░░░░░   2/3   67%
#
# -Show picks what you get: Text (a line per step), Bar (one bar, redrawn), or Both.
# -ProgressShow picks what the bar carries at its end, as Format-AnsiProgress -Show.
# Inside a step, $task.Update(value, total) moves the bar for work the runner cannot
# count on its own — which puts a fraction in the count ("0.5/1"), so -ProgressShow
# Percent is usually the one to reach for there.
#
# When output is redirected the bar is not redrawn in place — every state would be
# a separate line in the log. Text still prints, so a CI transcript stays readable.

Import-Module (Join-Path $PSScriptRoot 'Ansi.Core.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'Format-AnsiText.psm1') -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'Format-AnsiProgress.psm1') -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'Out-AnsiHost.psm1') -DisableNameChecking

$script:AnsiTaskMark = @{
    'running' = [string][char]0x2192   # →
    'done'    = [string][char]0x2714   # ✔
    'failed'  = [string][char]0x2718   # ✘
    'skipped' = [string][char]0x00B7   # ·
}

function Invoke-AnsiTask {
    [CmdletBinding(DefaultParameterSetName = 'Single')]
    param(
        # One step: its name.
        [Parameter(ParameterSetName = 'Single', Position = 0, Mandatory)]
        [string]$Name,

        # One step: what to run. It receives the task control object, so a long step
        # can call $task.Update(value, total) or $task.Write('message').
        [Parameter(ParameterSetName = 'Single', Position = 1, Mandatory)]
        [scriptblock]$ScriptBlock,

        # Several steps: @{ Name = 'build'; Script = { ... } } each, or objects with
        # Name and Script properties.
        [Parameter(ParameterSetName = 'Many', Position = 0, Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Task,

        # What to report: a line per step, a bar, or both.
        [ValidateSet('Both', 'Text', 'Bar')]
        [string]$Show = 'Both',

        # What the bar carries at its end, as Format-AnsiProgress -Show. A step that
        # reports a fraction makes the count a decimal ("0.5/1"), which reads worse
        # than the percentage it is derived from, so Percent is often the better one.
        [ValidateSet('Percent', 'Count', 'Both', 'None')]
        [string]$ProgressShow = 'Both',

        [ValidateSet('Blocks', 'Line', 'Dots', 'Ascii')]
        [string]$Style = 'Blocks',

        [int]$Width = 0,

        [string]$BarColor = 'BrightCyan',

        [string]$EmptyColor = 'DarkGray',

        # Keep going when a step throws, instead of rethrowing at once.
        [switch]$ContinueOnError,

        # Leave the finished steps on screen. Off: the bar is cleared at the end.
        [switch]$KeepBar,

        # Emit a result object per step: Name, Ok, Duration, Error.
        [switch]$PassThru
    )

    $steps = if ($PSCmdlet.ParameterSetName -eq 'Single') {
        @([PSCustomObject]@{ Name = $Name; Script = $ScriptBlock })
    } else {
        ConvertTo-AnsiTaskStep -Task $Task
    }

    if ($steps.Count -eq 0) { return }

    $state = [PSCustomObject]@{
        Steps        = $steps
        Index        = 0
        Show         = $Show
        ProgressShow = $ProgressShow
        Style        = $Style
        Width        = $Width
        BarColor     = $BarColor
        EmptyColor   = $EmptyColor
        BarLines     = 0        # bar rows currently on screen, to redraw over
        Live         = (Test-AnsiTaskLive)
        Fraction     = 0.0      # progress inside the running step, 0..1
    }

    $results = [System.Collections.Generic.List[object]]::new()
    $failure = $null

    if ($null -ne $script:AnsiTaskCurrent) {
        throw 'A task is already running; Invoke-AnsiTask does not nest.'
    }
    $script:AnsiTaskCurrent = $state
    try {
    foreach ($step in $steps) {
        $state.Fraction = 0.0
        Write-AnsiTaskLine -State $state -Step $step -Status 'running'
        Write-AnsiTaskBar -State $state

        $started = [System.Diagnostics.Stopwatch]::StartNew()
        $ok = $true
        $errorRecord = $null

        try {
            # The control object lets a step move the bar and print beside it.
            $control = New-AnsiTaskControl -State $state -Step $step
            & $step.Script $control
        } catch {
            $ok = $false
            $errorRecord = $_
            if (-not $ContinueOnError) { $failure = $_ }
        }
        $started.Stop()

        $state.Index++
        $state.Fraction = 0.0
        Write-AnsiTaskLine -State $state -Step $step -Status $(if ($ok) { 'done' } else { 'failed' }) `
            -Duration $started.Elapsed -Replace
        Write-AnsiTaskBar -State $state

        $null = $results.Add([PSCustomObject]@{
                PSTypeName = 'PwshAnsi.TaskResult'
                Name       = $step.Name
                Ok         = $ok
                Duration   = $started.Elapsed
                Error      = $errorRecord
            })

        if ($null -ne $failure) { break }
    }
    } finally {
        $script:AnsiTaskCurrent = $null
    }

    # Steps never reached, so a -PassThru caller sees the whole list either way.
    if ($null -ne $failure) {
        for ($i = $state.Index; $i -lt $steps.Count; $i++) {
            $null = $results.Add([PSCustomObject]@{
                    PSTypeName = 'PwshAnsi.TaskResult'
                    Name       = $steps[$i].Name
                    Ok         = $false
                    Duration   = [TimeSpan]::Zero
                    Error      = $null
                })
        }
    }

    Clear-AnsiTaskBar -State $state -Keep:$KeepBar

    if ($PassThru) { $results.ToArray() }
    if ($null -ne $failure) { throw $failure }
}

# --- steps ----------------------------------------------------------------------

# Hashtables and objects both reduce to { Name; Script }.
function ConvertTo-AnsiTaskStep {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Task)

    $steps = [System.Collections.Generic.List[object]]::new()
    foreach ($item in $Task) {
        if ($null -eq $item) { continue }

        $name = $null
        $script = $null
        if ($item -is [hashtable]) {
            $name = $item['Name']
            $script = $item['Script']
            if ($null -eq $script) { $script = $item['ScriptBlock'] }
        } else {
            $name = $item.PSObject.Properties['Name'].Value
            $prop = $item.PSObject.Properties['Script']
            if ($null -eq $prop) { $prop = $item.PSObject.Properties['ScriptBlock'] }
            if ($null -ne $prop) { $script = $prop.Value }
        }

        if ([string]::IsNullOrWhiteSpace([string]$name)) { throw 'Every task needs a Name.' }
        if ($script -isnot [scriptblock]) { throw "Task '$name' needs a Script scriptblock." }

        $null = $steps.Add([PSCustomObject]@{ Name = [string]$name; Script = $script })
    }
    return , $steps.ToArray()
}

# What a step is handed: move the bar, or print a line above it.
function New-AnsiTaskControl {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$State,
        [Parameter(Mandatory)][object]$Step
    )
    $control = [PSCustomObject]@{
        PSTypeName = 'PwshAnsi.Task'
        Name       = $Step.Name
        Index      = $State.Index
        Count      = $State.Steps.Count
    }
    $control | Add-Member -MemberType ScriptMethod -Name Update -Value {
        param([double]$Value, [double]$Total = 100)
        $fraction = if ($Total -gt 0) { $Value / $Total } else { 0 }
        Set-AnsiTaskFraction -Fraction $fraction
    }
    $control | Add-Member -MemberType ScriptMethod -Name Write -Value {
        param([string]$Message)
        Write-AnsiTaskMessage -Message $Message
    }
    return $control
}

# The control object's methods run in the module scope, so both reach the state
# the current call is using. One task runs at a time by construction.
$script:AnsiTaskCurrent = $null

function Set-AnsiTaskFraction {
    [CmdletBinding()]
    param([Parameter(Mandatory)][double]$Fraction)
    if ($null -eq $script:AnsiTaskCurrent) { return }
    $state = $script:AnsiTaskCurrent
    $state.Fraction = [Math]::Min(1.0, [Math]::Max(0.0, $Fraction))
    Write-AnsiTaskBar -State $state -Replace
}

function Write-AnsiTaskMessage {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Message)
    if ($null -eq $script:AnsiTaskCurrent) { return }
    $state = $script:AnsiTaskCurrent
    Remove-AnsiTaskBar -State $state
    Format-AnsiText "  $Message" -Color DarkGray | Out-AnsiHost
    Write-AnsiTaskBar -State $state
}

# --- painting ---------------------------------------------------------------------

# In place redraw needs a terminal. Redirected output gets plain appended lines,
# because every intermediate bar would otherwise be its own line in the log.
function Test-AnsiTaskLive {
    try { return (-not [Console]::IsOutputRedirected) } catch { return $false }
}

function Write-AnsiTaskLine {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$State,
        [Parameter(Mandatory)][object]$Step,
        [Parameter(Mandatory)][string]$Status,
        [TimeSpan]$Duration = [TimeSpan]::Zero,
        # Rewrite the running line rather than adding one.
        [switch]$Replace
    )
    if ($State.Show -eq 'Bar') { return }

    # A finished step replaces its own running line, but only on a live terminal:
    # in a log both lines are worth keeping, so the redirected path only prints
    # the finished one.
    if ($Replace) {
        if ($State.Live) {
            Remove-AnsiTaskBar -State $State
            Move-AnsiCursorUp -Lines 1
            Clear-AnsiLine
        }
    } elseif ($Status -eq 'running' -and -not $State.Live) {
        return
    } else {
        Remove-AnsiTaskBar -State $State
    }

    $mark = $script:AnsiTaskMark[$Status]
    $color = switch ($Status) {
        'done' { 'BrightGreen' }
        'failed' { 'BrightRed' }
        'skipped' { 'DarkGray' }
        default { 'BrightCyan' }
    }
    $name = ($Step.Name -replace '\[', '[[') -replace '\]', ']]'
    $line = "[$color]$mark[/] $name"
    if ($Duration -ne [TimeSpan]::Zero) {
        $line += "  [DarkGray]$(Format-AnsiTaskDuration -Duration $Duration)[/]"
    }
    Format-AnsiText $line | Out-AnsiHost
}

function Write-AnsiTaskBar {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$State,
        # Redraw over the bar already on screen instead of adding one.
        [switch]$Replace
    )
    if ($State.Show -eq 'Text') { return }
    # A bar is a live thing: in a log it would be one line per update.
    if (-not $State.Live) { return }

    if ($Replace) { Remove-AnsiTaskBar -State $State }

    $value = $State.Index + $State.Fraction
    $splat = @{
        Total      = $State.Steps.Count
        Show       = $State.ProgressShow
        Style      = $State.Style
        BarColor   = $State.BarColor
        EmptyColor = $State.EmptyColor
    }
    if ($State.Width -gt 0) { $splat['Width'] = $State.Width }

    Format-AnsiProgress $value @splat | Out-AnsiHost
    $State.BarLines = 1
}

# Take the bar off the screen so something else can be written under the steps.
function Remove-AnsiTaskBar {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$State)
    if ($State.BarLines -le 0) { return }
    if (-not $State.Live) { $State.BarLines = 0; return }
    Move-AnsiCursorUp -Lines $State.BarLines
    for ($i = 0; $i -lt $State.BarLines; $i++) {
        Clear-AnsiLine
        if ($i -lt $State.BarLines - 1) { Write-Host '' }
    }
    $State.BarLines = 0
}

function Clear-AnsiTaskBar {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$State,
        [switch]$Keep
    )
    if ($Keep) { return }
    Remove-AnsiTaskBar -State $State
}

# 0.4s, 2.1s, 1m 05s — a step's own scale, never more precision than is useful.
# Invariant culture: -f would write "0,4s" on a comma locale, and a rendering
# should read the same on every machine that runs it.
function Format-AnsiTaskDuration {
    [CmdletBinding()]
    param([Parameter(Mandatory)][TimeSpan]$Duration)
    $culture = [cultureinfo]::InvariantCulture
    if ($Duration.TotalSeconds -lt 60) {
        return [string]::Format($culture, '{0:0.0}s', $Duration.TotalSeconds)
    }
    if ($Duration.TotalMinutes -lt 60) {
        return [string]::Format($culture, '{0}m {1:00}s', [int]$Duration.TotalMinutes, $Duration.Seconds)
    }
    return [string]::Format($culture, '{0}h {1:00}m', [int]$Duration.TotalHours, $Duration.Minutes)
}

Export-ModuleMember -Function Invoke-AnsiTask
