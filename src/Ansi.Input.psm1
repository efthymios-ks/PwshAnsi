#Requires -Version 7.2

# Ansi.Input.psm1
# Internal: the input and painting loop the Read-Ansi* prompts share.
#
# Two things live here that every prompt was doing on its own, badly or not at all.
#
# Keys arrive one at a time, but a paste arrives as a burst of them. Repainting per
# character turns a pasted path into a stutter, so Read-AnsiKeyBurst blocks for the
# first key and then takes whatever else is already queued. The prompt applies them
# in order and paints once.
#
# A frame is written either where the cursor is - the original behaviour, one host
# write per row with the cursor walked back up - or at a cell the caller names, as a
# single synchronized write. The positioned path is what lets a prompt sit anywhere
# on the screen without flicker; it also means the prompt must place the cursor
# itself afterwards, because a synchronized frame restores the caller's.

Import-Module (Join-Path $PSScriptRoot 'Ansi.Core.psm1') -Force -DisableNameChecking

# How many keys one burst will take before it paints regardless. A paste longer than
# this simply becomes two bursts.
$script:AnsiBurstLimit = 512

# The console seams arrive as scriptblocks rather than being called here, so they resolve in
# the prompt's own module scope - which is the scope the test suite replaces them in.
function Read-AnsiKeyBurst {
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)][scriptblock]$ReadKey,
        [Parameter(Mandatory)][scriptblock]$KeyAvailable,
        [AllowNull()][scriptblock]$StopOn,
        [int]$Limit = 0
    )
    if ($Limit -lt 1) { $Limit = $script:AnsiBurstLimit }

    $first = & $ReadKey
    if ($null -eq $first) { return , @() }

    $keys = [System.Collections.Generic.List[object]]::new()
    $null = $keys.Add($first)

    # A key that ends the interaction ends the burst with it: whatever follows belongs to
    # whoever reads next, not to this prompt.
    if ($StopOn -and (& $StopOn $first)) { return , $keys.ToArray() }

    while ($keys.Count -lt $Limit -and (& $KeyAvailable)) {
        $next = & $ReadKey
        if ($null -eq $next) { break }
        $null = $keys.Add($next)
        if ($StopOn -and (& $StopOn $next)) { break }
    }

    return , $keys.ToArray()
}

function Wait-AnsiKeyBurst {
    # $null means the deadline passed with nothing typed; the caller treats that as a timeout.
    [CmdletBinding()]
    param(
        [AllowNull()][object]$Deadline,
        [Parameter(Mandatory)][scriptblock]$ReadKey,
        [Parameter(Mandatory)][scriptblock]$KeyAvailable,
        [Parameter(Mandatory)][scriptblock]$Wait,
        [AllowNull()][scriptblock]$StopOn,
        [int]$Limit = 0
    )
    if ($null -ne $Deadline) {
        while (-not (& $KeyAvailable)) {
            if ([datetime]::UtcNow -ge $Deadline) { return $null }
            & $Wait
        }
    }
    return , (Read-AnsiKeyBurst -ReadKey $ReadKey -KeyAvailable $KeyAvailable -StopOn $StopOn -Limit $Limit)
}

function Test-AnsiPositioned {
    [CmdletBinding()]
    [OutputType([bool])]
    param([int]$Row = -1, [int]$Column = -1)
    return ($Row -ge 0 -and $Column -ge 0)
}

function Write-AnsiPromptFrame {
    # Rows are already formatted strings. Positioned: one synchronized write, and the previous
    # frame's surplus rows are blanked so a shrinking list leaves nothing behind. Anchored: the
    # original walk-up-and-rewrite, which is what every caller had before a position was possible.
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Rows,
        [int]$Row = -1,
        [int]$Column = -1,
        [int]$Drawn = 0,
        [switch]$NoColor
    )
    if (-not (Test-AnsiPositioned -Row $Row -Column $Column)) {
        if ($Drawn -gt 0) { Move-AnsiCursorUp -Lines $Drawn }
        foreach ($line in $Rows) {
            Clear-AnsiLine
            Write-Host $line
        }
        return $Rows.Count
    }

    $painted = @($Rows)
    for ($i = $Rows.Count; $i -lt $Drawn; $i++) { $painted += '' }

    $runs = foreach ($line in $painted) { , @([PSCustomObject]@{ Text = $line; Fg = $null; Bg = $null; Styles = @(); Link = $null }) }

    # The rows carry their own escapes already, so the frame must not re-style them.
    $frame = Format-AnsiFrame -Rows @($runs) -Width 0 -Row $Row -Column $Column `
        -NoColor:$NoColor -Plain:(-not (Test-AnsiTerminal))
    Write-AnsiFrame -Text $frame
    return $Rows.Count
}

function Set-AnsiPromptCursor {
    # A synchronized frame puts the caller's cursor back, so a prompt that shows one has to
    # place it again after every paint.
    [CmdletBinding()]
    param([int]$Row = -1, [int]$Column = -1)

    if (-not (Test-AnsiPositioned -Row $Row -Column $Column)) { return }
    if (-not (Test-AnsiTerminal)) { return }

    try { [Console]::SetCursorPosition($Column, $Row) } catch { }
}

function New-AnsiFieldState {
    [CmdletBinding()]
    param([string]$Text = '', [int]$Caret = -1)
    if ($Caret -lt 0) { $Caret = $Text.Length }
    return [PSCustomObject]@{ Text = $Text; Caret = [Math]::Min($Caret, $Text.Length); Window = 0 }
}

function Update-AnsiFieldState {
    # One key against the field: insert or delete at the caret, or move it. Pure - the painting
    # is the caller's business - so a burst is just this applied in order.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$State,
        [Parameter(Mandatory)][object]$Key
    )
    $text = [string]$State.Text
    $caret = [int]$State.Caret

    switch ([string]$Key.Key) {
        # A line break inside a paste is content, not an answer - the caller decides which this
        # is - and the field keeps the real character, drawn as an escape rather than a row.
        'Enter' {
            $text = $text.Insert($caret, "`n")
            $caret++
        }
        'LeftArrow' { if ($caret -gt 0) { $caret-- } }
        'RightArrow' { if ($caret -lt $text.Length) { $caret++ } }
        'Backspace' {
            if ($caret -gt 0) {
                $text = $text.Remove($caret - 1, 1)
                $caret--
            }
        }
        default {
            $char = [char]$Key.KeyChar
            if (-not [char]::IsControl($char) -and [int]$char -ne 0) {
                $text = $text.Insert($caret, [string]$char)
                $caret++
            }
        }
    }

    return [PSCustomObject]@{ Text = $text; Caret = $caret; Window = [int]$State.Window }
}

function Get-AnsiFieldDisplay {
    # One row cannot hold a line break, so the field draws it as a backslash-n escape where the
    # text holds one character - and the caret column is counted in what is drawn, not in what
    # is stored.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text,
        [int]$Caret = 0
    )
    $shown = [System.Text.StringBuilder]::new()
    $caretColumn = 0

    for ($i = 0; $i -lt $Text.Length; $i++) {
        if ($i -eq $Caret) { $caretColumn = $shown.Length }
        $char = $Text[$i]
        if ($char -eq "`n") { $null = $shown.Append([char]92).Append('n') }
        elseif ($char -eq "`r") { }
        else { $null = $shown.Append($char) }
    }
    if ($Caret -ge $Text.Length) { $caretColumn = $shown.Length }

    return [PSCustomObject]@{ Text = $shown.ToString(); CaretColumn = $caretColumn }
}

function Get-AnsiFieldView {
    # The slice that fits, scrolled so the caret is always on screen, plus the column the
    # caret sits at within that slice. A field narrower than its text scrolls sideways.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$State,
        [Parameter(Mandatory)][ValidateRange(1, [int]::MaxValue)][int]$Width
    )
    $display = Get-AnsiFieldDisplay -Text ([string]$State.Text) -Caret ([int]$State.Caret)
    $text = $display.Text
    $caret = $display.CaretColumn
    $window = [Math]::Max(0, [int]$State.Window)

    if ($caret -lt $window) { $window = $caret }
    if ($caret -ge $window + $Width) { $window = $caret - $Width + 1 }
    # Never scroll past the end: a field with room to spare shows the text from where it can.
    $window = [Math]::Max(0, [Math]::Min($window, [Math]::Max(0, $text.Length - $Width + 1)))
    if ($caret -lt $window) { $window = $caret }

    $length = [Math]::Min($Width, [Math]::Max(0, $text.Length - $window))
    $visible = ($length -gt 0) ? $text.Substring($window, $length) : ''

    return [PSCustomObject]@{
        Window      = $window
        Visible     = $visible
        CaretColumn = $caret - $window
        Scrolled    = ($window -gt 0 -or $text.Length -gt $window + $Width)
    }
}

Export-ModuleMember -Function `
    New-AnsiFieldState, `
    Get-AnsiFieldDisplay, `
    Update-AnsiFieldState, `
    Get-AnsiFieldView, `
    Read-AnsiKeyBurst, `
    Wait-AnsiKeyBurst, `
    Test-AnsiPositioned, `
    Write-AnsiPromptFrame, `
    Set-AnsiPromptCursor
