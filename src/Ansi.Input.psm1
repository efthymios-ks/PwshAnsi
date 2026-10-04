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

# A resize is reported as a one-element burst alongside the real key stream so prompts
# can rerender from the wait loop they already sit in. [ConsoleKeyInfo].Key is an enum,
# so a sentinel can only ride on a PSCustomObject - prompts switch on [string]$key.Key
# and the name 'AnsiResize' never collides with a ConsoleKey.
function New-AnsiResizeSignal {
    [CmdletBinding()]
    param()
    return [PSCustomObject]@{
        Key       = 'AnsiResize'
        KeyChar   = [char]0
        Modifiers = [System.ConsoleModifiers]0
    }
}

function Test-AnsiResizeSignal {
    [CmdletBinding()]
    [OutputType([bool])]
    param([AllowNull()][object]$Key)
    if ($null -eq $Key) { return $false }
    return ([string]$Key.Key -eq 'AnsiResize')
}

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
    # -GetWindowSize is optional: pass it to turn a resize into a one-element burst carrying
    # the resize sentinel, so the caller's loop rerenders at the new size without a keystroke.
    # The sentinel fires once the size has been stable for the settle window, so a drag
    # produces one repaint at the end instead of flicker all the way through.
    [CmdletBinding()]
    param(
        [AllowNull()][object]$Deadline,
        [Parameter(Mandatory)][scriptblock]$ReadKey,
        [Parameter(Mandatory)][scriptblock]$KeyAvailable,
        [Parameter(Mandatory)][scriptblock]$Wait,
        [AllowNull()][scriptblock]$StopOn,
        [AllowNull()][scriptblock]$GetWindowSize,
        [int]$Limit = 0,
        [int]$ResizeSettleMilliseconds = 150
    )
    $baseline = $null
    $lastSeen = $null
    $lastChangeAt = $null
    if ($GetWindowSize) {
        try { $baseline = & $GetWindowSize; $lastSeen = $baseline } catch { $baseline = $null }
    }

    # Poll for a key with a Wait tick in between so a resize can be noticed without a
    # keystroke. No deadline is the same loop with no clock to run out.
    while (-not (& $KeyAvailable)) {
        if ($null -ne $Deadline -and [datetime]::UtcNow -ge $Deadline) { return $null }
        if ($GetWindowSize -and $null -ne $baseline) {
            $current = $null
            try { $current = & $GetWindowSize } catch { $current = $null }
            if ($null -ne $current) {
                if ($current.Width -ne $lastSeen.Width -or $current.Height -ne $lastSeen.Height) {
                    # Still dragging: restart the settle clock on every change.
                    $lastSeen = $current
                    $lastChangeAt = [datetime]::UtcNow
                } elseif ($null -ne $lastChangeAt -and
                          ([datetime]::UtcNow - $lastChangeAt).TotalMilliseconds -ge $ResizeSettleMilliseconds) {
                    if ($lastSeen.Width -ne $baseline.Width -or $lastSeen.Height -ne $baseline.Height) {
                        return , @((New-AnsiResizeSignal))
                    }
                    # Drag that ended back on the baseline: no sentinel, keep waiting.
                    $lastChangeAt = $null
                }
            }
        }
        & $Wait
    }
    return , (Read-AnsiKeyBurst -ReadKey $ReadKey -KeyAvailable $KeyAvailable -StopOn $StopOn -Limit $Limit)
}

# Custom hotkeys sit next to the built-in bindings on the same prompt. The rule the callers
# rely on is that a built-in never budges: a caller who tries to rebind Enter or Space gets
# a throw at the door, not a surprising no-op mid-prompt.
function Assert-AnsiHotkeys {
    [CmdletBinding()]
    param(
        [AllowNull()][hashtable[]]$Hotkeys,
        [AllowEmptyCollection()][string[]]$ReservedKeys = @(),
        [AllowEmptyCollection()][char[]]$ReservedChars = @(),
        [Parameter(Mandatory)][string]$Caller
    )
    if ($null -eq $Hotkeys -or $Hotkeys.Count -eq 0) { return }

    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($entry in $Hotkeys) {
        if ($null -eq $entry) { throw "$Caller -Hotkeys: entry is null." }
        $key = [string]$entry['Key']
        if ([string]::IsNullOrEmpty($key)) { throw "$Caller -Hotkeys: entry is missing 'Key'." }
        if (-not $entry.ContainsKey('Description') -or $null -eq $entry['Description']) {
            throw "$Caller -Hotkeys: entry '$key' is missing 'Description'."
        }
        if (-not ($entry['Action'] -is [scriptblock])) {
            throw "$Caller -Hotkeys: entry '$key' needs an 'Action' scriptblock."
        }

        if ($key.Length -eq 1) {
            $ch = [char]::ToLowerInvariant([char]$key)
            if ($ReservedChars -contains $ch) {
                throw "$Caller -Hotkeys: '$key' is a reserved default key."
            }
            $token = "char:$ch"
        } else {
            foreach ($reserved in $ReservedKeys) {
                if ([string]::Equals($reserved, $key, [System.StringComparison]::OrdinalIgnoreCase)) {
                    throw "$Caller -Hotkeys: '$key' is a reserved default key."
                }
            }
            $token = "name:$($key.ToLowerInvariant())"
        }
        if (-not $seen.Add($token)) {
            throw "$Caller -Hotkeys: '$key' is listed twice."
        }
    }
}

function Invoke-AnsiHotkey {
    # Returns $true if a hotkey ran, so the caller's default arm can skip its own fallback.
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][System.ConsoleKeyInfo]$Key,
        [AllowNull()][hashtable[]]$Hotkeys,
        [Parameter(Mandatory)][object]$State
    )
    if ($null -eq $Hotkeys -or $Hotkeys.Count -eq 0) { return $false }

    $char = [char]::ToLowerInvariant([char]$Key.KeyChar)
    $name = [string]$Key.Key

    foreach ($entry in $Hotkeys) {
        $k = [string]$entry['Key']
        $match = $false
        if ($k.Length -eq 1) {
            $match = ([char]::ToLowerInvariant([char]$k) -eq $char) -and ([int]$char -ne 0)
        } else {
            $match = [string]::Equals($k, $name, [System.StringComparison]::OrdinalIgnoreCase)
        }
        if ($match) {
            $State.Key = $Key
            & $entry['Action'] $State
            return $true
        }
    }
    return $false
}

function Get-AnsiHotkeyHintFragment {
    # ' · L1 D1 · L2 D2' when there is anything to add; empty otherwise. The leading separator
    # is part of the fragment so the caller can splice it in without worrying about spacing.
    [CmdletBinding()]
    [OutputType([string])]
    param([AllowNull()][hashtable[]]$Hotkeys)
    if ($null -eq $Hotkeys -or $Hotkeys.Count -eq 0) { return '' }

    $sb = [System.Text.StringBuilder]::new()
    foreach ($entry in $Hotkeys) {
        $k = [string]$entry['Key']
        $label = if ($k.Length -eq 1) { $k.ToUpperInvariant() } else { $k }
        $null = $sb.Append(' · ').Append($label).Append(' ').Append([string]$entry['Description'])
    }
    return $sb.ToString()
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

function Reset-AnsiPromptRegion {
    # Clear from the top of a frame down to the end of the screen. On resize an
    # anchored prompt would otherwise append a fresh frame under the stale one
    # whose rows may have wrapped at the old width - a repaint cannot walk the
    # cursor up over the right physical height any more. Move to the known top
    # row and let the terminal clear from there.
    [CmdletBinding()]
    param([Parameter(Mandatory)][int]$TopRow)

    if (-not (Test-AnsiTerminal)) { return }
    try {
        $row = [Math]::Max(0, $TopRow)
        [Console]::SetCursorPosition(0, $row)
        # ED 0: erase from the cursor to the end of the display.
        [Console]::Out.Write("$([char]27)[0J")
        [Console]::Out.Flush()
    } catch { }
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
    New-AnsiResizeSignal, `
    Test-AnsiResizeSignal, `
    Test-AnsiPositioned, `
    Write-AnsiPromptFrame, `
    Reset-AnsiPromptRegion, `
    Set-AnsiPromptCursor, `
    Assert-AnsiHotkeys, `
    Invoke-AnsiHotkey, `
    Get-AnsiHotkeyHintFragment
