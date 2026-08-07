#Requires -Version 7.2

# Ansi.Core.psm1
# Internal helpers shared across PwshAnsi component modules.
# Nothing here is intended for public consumption; each Format-Ansi* module
# imports this and only re-exports its own public function.

Import-Module (Join-Path $PSScriptRoot 'Ansi.Emoji.psm1') -Force -DisableNameChecking

$script:AnsiColorMap = @{
    'black'         = 'Black'
    'red'           = 'Red'
    'green'         = 'Green'
    'yellow'        = 'Yellow'
    'blue'          = 'Blue'
    'magenta'       = 'Magenta'
    'cyan'          = 'Cyan'
    'white'         = 'White'
    'brightblack'   = 'BrightBlack'
    'brightred'     = 'BrightRed'
    'brightgreen'   = 'BrightGreen'
    'brightyellow'  = 'BrightYellow'
    'brightblue'    = 'BrightBlue'
    'brightmagenta' = 'BrightMagenta'
    'brightcyan'    = 'BrightCyan'
    'brightwhite'   = 'BrightWhite'
    # ConsoleColor aliases
    'darkred'       = 'Red'
    'darkgreen'     = 'Green'
    'darkyellow'    = 'Yellow'
    'darkblue'      = 'Blue'
    'darkmagenta'   = 'Magenta'
    'darkcyan'      = 'Cyan'
    'gray'          = 'White'
    'darkgray'      = 'BrightBlack'
}

$script:AnsiStyleMap = @{
    'bold'          = 'Bold'
    'italic'        = 'Italic'
    'underline'     = 'Underline'
    'strikethrough' = 'Strikethrough'
    'reverse'       = 'Reverse'
}

# PwshAnsi's own short names, checked before the full table in Ansi.Emoji.psm1 so the
# tokens the library shipped with keep the glyph they always had — :star: stays the
# text star, where the table has the emoji one. Everything else comes from the table.
$script:AnsiEmojiAlias = @{
    'check'    = [char]0x2713   # ✓
    'cross'    = [char]0x2717   # ✗
    'warn'     = [char]0x26A0   # ⚠
    'info'     = [char]0x2139   # ℹ
    'star'     = [char]0x2605   # ★
    'heart'    = [char]0x2665   # ♥
    'arrow'    = [char]0x2192   # →
    'bullet'   = [char]0x2022   # •
    'fire'     = [string]::new([char[]](0xD83D, 0xDD25))  # 🔥
    'rocket'   = [string]::new([char[]](0xD83D, 0xDE80))  # 🚀
    'bug'      = [string]::new([char[]](0xD83D, 0xDC1B))  # 🐛
    'sparkles' = [string]::new([char[]](0x2728))          # ✨
    'tada'     = [string]::new([char[]](0xD83C, 0xDF89))  # 🎉
}

# Filled and empty cells for the bar drawn by the charts. Kept here because both
# Format-AnsiBarChart and Format-AnsiBreakdownChart draw with them.
$script:AnsiChartCharMap = @{
    'blocks' = @([string][char]0x2588, [string][char]0x2591)   # █ ░
    'line'   = @([string][char]0x2501, [string][char]0x2500)   # ━ ─
    'dots'   = @([string][char]0x25CF, [string][char]0x00B7)   # ● ·
    'ascii'  = @('#', '-')
}

# Colours handed out to chart items that do not name one, in order, cycling.
$script:AnsiChartPalette = @(
    'BrightCyan', 'BrightGreen', 'BrightYellow', 'BrightMagenta', 'BrightBlue',
    'BrightRed', 'Cyan', 'Green', 'Yellow', 'Magenta', 'Blue', 'Red'
)

function Test-AnsiNoColor {
    if ($env:NO_COLOR) { return $true }
    try { if ([Console]::IsOutputRedirected) { return $true } } catch { }
    return $false
}

function Get-AnsiColorName {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Name)
    $key = $Name.ToLowerInvariant()
    if (-not $script:AnsiColorMap.ContainsKey($key)) {
        throw "Unknown color '$Name'. Use one of: $((($script:AnsiColorMap.Keys | Sort-Object) -join ', '))."
    }
    return $script:AnsiColorMap[$key]
}

function Get-AnsiAnchor {
    [CmdletBinding()]
    param([int]$MaxWidth = 0)
    $col = 0
    try { $col = $Host.UI.RawUI.CursorPosition.X } catch { $col = 0 }
    $bufWidth = 120
    try { $bufWidth = $Host.UI.RawUI.BufferSize.Width } catch { $bufWidth = 120 }
    if ($bufWidth -lt 1) { $bufWidth = 120 }
    $width = if ($MaxWidth -gt 0) { $MaxWidth } else { [Math]::Max(1, $bufWidth - $col) }
    [PSCustomObject]@{
        Column      = $col
        BufferWidth = $bufWidth
        Width       = $width
    }
}

function ConvertFrom-AnsiTag {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Body,
        [Parameter(Mandatory)][hashtable]$Base
    )
    $frame = @{
        Fg     = $Base.Fg
        Bg     = $Base.Bg
        Styles = @($Base.Styles)
        Link   = $Base.Link
    }
    if ($Body -match '^link=(.+)$') {
        $frame.Link = $Matches[1]
        return $frame
    }
    $words = $Body -split '\s+' | Where-Object { $_ }
    $onNext = $false
    foreach ($w in $words) {
        $wl = $w.ToLowerInvariant()
        if ($wl -eq 'on') { $onNext = $true; continue }
        if ($script:AnsiStyleMap.ContainsKey($wl)) {
            $frame.Styles = @($frame.Styles + $script:AnsiStyleMap[$wl])
            continue
        }
        if ($script:AnsiColorMap.ContainsKey($wl)) {
            if ($onNext) {
                $frame.Bg = $script:AnsiColorMap[$wl]
                $onNext = $false
            }
            else {
                $frame.Fg = $script:AnsiColorMap[$wl]
            }
            continue
        }
        throw "Unknown markup token '$w' in tag [$Body]."
    }
    if ($onNext) { throw "Markup tag [$Body] has 'on' with no background color." }
    return $frame
}

function ConvertFrom-AnsiMarkdown {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)

    # Preserve backslash-escaped markup chars via private-use placeholders,
    # transform markdown, then restore.
    $m = [char]0xE000
    $Text = $Text -replace '\\\[', "${m}0"
    $Text = $Text -replace '\\\]', "${m}1"
    $Text = $Text -replace '\\\*', "${m}2"
    $Text = $Text -replace '\\_', "${m}3"
    $Text = $Text -replace '\\`', "${m}4"
    $Text = $Text -replace '\\\{', "${m}5"
    $Text = $Text -replace '\\\}', "${m}6"
    $Text = $Text -replace '\\~', "${m}7"

    # :emoji: — replaced early so the tokens don't collide with URL colons later.
    # Digits and underscores are in, because the shortcodes use them
    # (:1st_place_medal:, :keycap_10:); an unknown name is left as written.
    $Text = [regex]::Replace($Text, ':(\w+):', {
        param($m)
        $key = $m.Groups[1].Value.ToLowerInvariant()
        if ($script:AnsiEmojiAlias.ContainsKey($key)) { return $script:AnsiEmojiAlias[$key] }
        $glyph = Get-AnsiEmoji -Name $key
        if ($null -ne $glyph) { $glyph } else { $m.Value }
    })

    # Long form {style}...{/}
    $Text = [regex]::Replace($Text, '\{([^}]+)\}([\s\S]*?)\{/\}', '[$1]$2[/]')
    # Links [text](url)
    $Text = [regex]::Replace($Text, '\[([^\]]+)\]\(([^)]+)\)', '[link=$2]$1[/]')
    # Bold / strike / underline / italic / code
    $Text = [regex]::Replace($Text, '\*\*(.+?)\*\*', '[bold]$1[/]')
    $Text = [regex]::Replace($Text, '~~(.+?)~~', '[strikethrough]$1[/]')
    $Text = [regex]::Replace($Text, '__(.+?)__', '[underline]$1[/]')
    $Text = [regex]::Replace($Text, '\*(.+?)\*', '[italic]$1[/]')
    $Text = [regex]::Replace($Text, '`([^`]+?)`', '[BrightYellow]$1[/]')

    # Restore escapes. Markup metachars round-trip via markup escape syntax.
    $Text = $Text -replace "${m}0", '[['
    $Text = $Text -replace "${m}1", ']]'
    $Text = $Text -replace "${m}2", '*'
    $Text = $Text -replace "${m}3", '_'
    $Text = $Text -replace "${m}4", '`'
    $Text = $Text -replace "${m}5", '{'
    $Text = $Text -replace "${m}6", '}'
    $Text = $Text -replace "${m}7", '~'
    return $Text
}

function ConvertFrom-AnsiMarkup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text,
        [switch]$AsMarkdown,
        [switch]$AsLiteral
    )
    if ($AsLiteral) {
        return , @([PSCustomObject]@{
                Text = $Text; Fg = $null; Bg = $null; Styles = @(); Link = $null
            })
    }
    if ($AsMarkdown) {
        $Text = ConvertFrom-AnsiMarkdown -Text $Text
    }

    $runs = [System.Collections.Generic.List[object]]::new()
    $stack = [System.Collections.Generic.List[hashtable]]::new()
    $null = $stack.Add(@{ Fg = $null; Bg = $null; Styles = @(); Link = $null })

    $sb = [System.Text.StringBuilder]::new()
    $i = 0
    $len = $Text.Length

    while ($i -lt $len) {
        $c = $Text[$i]
        if ($c -eq '[') {
            if ($i + 1 -lt $len -and $Text[$i + 1] -eq '[') {
                [void]$sb.Append('[')
                $i += 2; continue
            }
            $close = $Text.IndexOf(']', $i + 1)
            if ($close -lt 0) { throw "Unclosed markup tag at position $i in: $Text" }
            $tagBody = $Text.Substring($i + 1, $close - $i - 1)
            if ($sb.Length -gt 0) {
                $top = $stack[$stack.Count - 1]
                $null = $runs.Add([PSCustomObject]@{
                        Text   = $sb.ToString()
                        Fg     = $top.Fg
                        Bg     = $top.Bg
                        Styles = @($top.Styles)
                        Link   = $top.Link
                    })
                $null = $sb.Clear()
            }
            if ($tagBody -eq '/') {
                if ($stack.Count -le 1) { throw "Unbalanced closing tag [/] in: $Text" }
                $stack.RemoveAt($stack.Count - 1)
            }
            else {
                $newFrame = ConvertFrom-AnsiTag -Body $tagBody -Base $stack[$stack.Count - 1]
                $null = $stack.Add($newFrame)
            }
            $i = $close + 1
        }
        elseif ($c -eq ']' -and $i + 1 -lt $len -and $Text[$i + 1] -eq ']') {
            [void]$sb.Append(']')
            $i += 2
        }
        else {
            [void]$sb.Append($c)
            $i++
        }
    }
    if ($sb.Length -gt 0) {
        $top = $stack[$stack.Count - 1]
        $null = $runs.Add([PSCustomObject]@{
                Text   = $sb.ToString()
                Fg     = $top.Fg
                Bg     = $top.Bg
                Styles = @($top.Styles)
                Link   = $top.Link
            })
    }
    if ($stack.Count -ne 1) { throw "Unbalanced markup tags in: $Text" }
    return , $runs.ToArray()
}

function Split-AnsiRuns {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Runs,
        [Parameter(Mandatory)][int]$Width,
        [ValidateSet('Fold', 'Crop', 'Ellipsis')]
        [string]$Overflow = 'Fold'
    )
    if ($Width -lt 1) { $Width = 1 }

    $lines = [System.Collections.Generic.List[object]]::new()
    $currentLine = [System.Collections.Generic.List[object]]::new()
    $currentWidth = 0

    function _newRun([string]$text, $r) {
        [PSCustomObject]@{
            Text   = $text
            Fg     = $r.Fg
            Bg     = $r.Bg
            Styles = $r.Styles
            Link   = $r.Link
        }
    }

    foreach ($run in $Runs) {
        $segments = $run.Text.Split([char]10)
        for ($si = 0; $si -lt $segments.Count; $si++) {
            if ($si -gt 0) {
                $null = $lines.Add($currentLine.ToArray())
                $currentLine = [System.Collections.Generic.List[object]]::new()
                $currentWidth = 0
            }
            $seg = $segments[$si]

            if ($Overflow -ne 'Fold') {
                $remaining = $Width - $currentWidth
                if ($remaining -le 0) { continue }
                if ($seg.Length -le $remaining) {
                    if ($seg.Length -gt 0) {
                        $null = $currentLine.Add((_newRun $seg $run))
                        $currentWidth += $seg.Length
                    }
                }
                else {
                    $keep = $remaining
                    $piece = $seg.Substring(0, $keep)
                    if ($Overflow -eq 'Ellipsis' -and $keep -ge 1) {
                        $piece = $piece.Substring(0, [Math]::Max(0, $keep - 1)) + [char]0x2026
                    }
                    $null = $currentLine.Add((_newRun $piece $run))
                    $currentWidth = $Width
                }
                continue
            }

            # Fold
            while ($seg.Length -gt 0) {
                $remaining = $Width - $currentWidth
                if ($remaining -le 0) {
                    $null = $lines.Add($currentLine.ToArray())
                    $currentLine = [System.Collections.Generic.List[object]]::new()
                    $currentWidth = 0
                    $remaining = $Width
                }
                if ($seg.Length -le $remaining) {
                    if ($seg.Length -gt 0) {
                        $null = $currentLine.Add((_newRun $seg $run))
                        $currentWidth += $seg.Length
                    }
                    $seg = ''
                }
                else {
                    $slice = $seg.Substring(0, $remaining)
                    $lastSpace = $slice.LastIndexOf(' ')
                    if ($lastSpace -gt 0 -and $currentWidth -gt 0) {
                        $null = $currentLine.Add((_newRun $seg.Substring(0, $lastSpace) $run))
                        $seg = $seg.Substring($lastSpace + 1)
                    }
                    elseif ($lastSpace -gt 0) {
                        $null = $currentLine.Add((_newRun $seg.Substring(0, $lastSpace) $run))
                        $seg = $seg.Substring($lastSpace + 1)
                    }
                    else {
                        $null = $currentLine.Add((_newRun $slice $run))
                        $seg = $seg.Substring($remaining)
                    }
                    $null = $lines.Add($currentLine.ToArray())
                    $currentLine = [System.Collections.Generic.List[object]]::new()
                    $currentWidth = 0
                }
            }
        }
    }
    $null = $lines.Add($currentLine.ToArray())
    return , $lines.ToArray()
}

function Format-AnsiLine {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Runs,
        [Parameter(Mandatory)][int]$Width,
        [ValidateSet('Left', 'Center', 'Right')]
        [string]$Justify = 'Left',
        [switch]$NoColor
    )
    $visible = 0
    foreach ($r in $Runs) { $visible += $r.Text.Length }
    $pad = [Math]::Max(0, $Width - $visible)
    $leftPad = 0
    switch ($Justify) {
        'Right' { $leftPad = $pad }
        'Center' { $leftPad = [int][Math]::Floor($pad / 2) }
        default { $leftPad = 0 }
    }
    $out = if ($leftPad -gt 0) { ' ' * $leftPad } else { '' }
    foreach ($run in $Runs) {
        if ($NoColor) {
            $out += $run.Text
            continue
        }
        $prefix = ''
        if ($run.Fg) { $prefix += $PSStyle.Foreground.($run.Fg) }
        if ($run.Bg) { $prefix += $PSStyle.Background.($run.Bg) }
        foreach ($s in $run.Styles) { $prefix += $PSStyle.$s }
        $body = $run.Text
        if ($run.Link) {
            $esc = [char]27
            $body = "$esc]8;;$($run.Link)$esc\$body$esc]8;;$esc\"
        }
        if ($prefix) { $out += $prefix + $body + $PSStyle.Reset }
        else { $out += $body }
    }
    return $out
}

# Bake alignment into a row so a rendering's rows are self-contained: the writers
# always paint Left, whatever the component's -Justify / -Alignment said.
function Add-AnsiJustify {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Runs,
        [Parameter(Mandatory)][int]$Width,
        [ValidateSet('Left', 'Center', 'Right')]
        [string]$Justify = 'Left'
    )
    if ($Justify -eq 'Left') { return , $Runs }

    $visible = 0
    foreach ($r in $Runs) { $visible += $r.Text.Length }
    $pad = [Math]::Max(0, $Width - $visible)
    $leftPad = if ($Justify -eq 'Right') { $pad } else { [int][Math]::Floor($pad / 2) }
    if ($leftPad -le 0) { return , $Runs }

    $padded = [System.Collections.Generic.List[object]]::new()
    $null = $padded.Add([PSCustomObject]@{
            Text = ' ' * $leftPad; Fg = $null; Bg = $null; Styles = @(); Link = $null
        })
    foreach ($r in $Runs) { $null = $padded.Add($r) }
    return , $padded.ToArray()
}

# The renderable every Format-Ansi* returns: rows of runs plus what the writers
# need to paint them. Rows are object[][] — one array of runs per row.
function New-AnsiRendering {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Kind,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Rows,
        [Parameter(Mandatory)][int]$Width,
        [int]$Column = 0,
        [AllowNull()][System.Nullable[bool]]$NoColor = $null
    )
    $rendering = [PSCustomObject]@{
        PSTypeName = 'Ansi.Rendering'
        Kind       = $Kind
        Rows       = $Rows
        Width      = $Width
        Column     = $Column
        NoColor    = $NoColor
        RowCount   = $Rows.Count
    }
    return , $rendering
}

function Test-AnsiRendering {
    [CmdletBinding()]
    param([AllowNull()][object]$Value)
    if ($null -eq $Value) { return $false }
    return ($Value.PSObject.TypeNames -contains 'Ansi.Rendering')
}

# --- Console input seams -----------------------------------------------------
# Wrapped so prompts can be driven from tests: replace these in the module scope
# and no real keyboard is involved.

function Test-AnsiInteractive {
    try { return (-not [Console]::IsInputRedirected) } catch { return $false }
}

function Test-AnsiKeyAvailable {
    try { return [Console]::KeyAvailable } catch { return $false }
}

function Read-AnsiKeyInfo {
    # $true: do not echo — prompts echo themselves, coloured and/or masked.
    return [Console]::ReadKey($true)
}

function Start-AnsiWait {
    param([int]$Milliseconds = 25)
    Start-Sleep -Milliseconds $Milliseconds
}

# --- Frames ------------------------------------------------------------------
# A positioned repaint is built as one string and written once. Several writes let
# the terminal present a half-drawn frame, and that is what flicker is.

function Test-AnsiTerminal {
    try { return (-not [Console]::IsOutputRedirected) } catch { return $false }
}

# The single write. A seam, like the input ones, so a suite can capture a frame
# without a console.
function Write-AnsiFrame {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return }
    [Console]::Out.Write($Text)
    [Console]::Out.Flush()
}

# Rows as one frame painted from (Row, Column), both 0-based.
#
# Each row is positioned absolutely and then erased to the end of the line, so a
# shorter row leaves nothing of the last frame behind and nothing is ever cleared
# first — a clear is the flash. The caller's cursor is saved and put back, the
# cursor is hidden while the frame lands, and the whole thing is wrapped in
# synchronized output (DEC 2026) so a terminal that understands it presents the
# frame atomically and one that does not ignores the pair.
#
# -Plain drops every cursor sequence, for output that is not a terminal: the rows
# are still the rows, just written in order.
function Format-AnsiFrame {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Rows,
        [Parameter(Mandatory)][int]$Width,
        [Parameter(Mandatory)][ValidateRange(0, [int]::MaxValue)][int]$Row,
        [Parameter(Mandatory)][ValidateRange(0, [int]::MaxValue)][int]$Column,
        [switch]$NoColor,
        [switch]$Plain
    )
    $esc = [char]27
    $frame = [System.Text.StringBuilder]::new()

    if (-not $Plain) {
        [void]$frame.Append("${esc}7")        # save cursor
        [void]$frame.Append("$esc[?25l")      # hide it while the frame lands
        [void]$frame.Append("$esc[?2026h")    # begin synchronized update
    }

    for ($i = 0; $i -lt $Rows.Count; $i++) {
        $text = Format-AnsiLine -Runs @($Rows[$i]) -Width $Width -Justify Left -NoColor:$NoColor
        if ($Plain) {
            if ($Column -gt 0) { [void]$frame.Append(' ' * $Column) }
            [void]$frame.Append($text).Append([System.Environment]::NewLine)
            continue
        }
        # CUP is 1-based; -Row and -Column are not.
        [void]$frame.Append("$esc[$($Row + $i + 1);$($Column + 1)H").Append($text).Append("$esc[K")
    }

    if (-not $Plain) {
        [void]$frame.Append("$esc[?2026l")
        [void]$frame.Append("$esc[?25h")
        [void]$frame.Append("${esc}8")        # restore cursor
    }
    return $frame.ToString()
}

# --- Cursor visibility -------------------------------------------------------
# A prompt that only takes keys has no use for a blinking cursor, and a list that
# repaints under one looks like it is flickering even when it is not. Written
# straight to the console rather than through Write-Host: cursor state is not
# output, and nothing that captures a prompt's rows should see it. Redirected
# output gets nothing at all.

function Test-AnsiCursorVisible {
    # $null when the platform will not say — the getter is Windows-only.
    try { return [bool][Console]::CursorVisible } catch { return $null }
}

function Hide-AnsiCursor {
    [CmdletBinding()]
    [OutputType([System.Nullable[bool]])]
    param()
    $was = Test-AnsiCursorVisible
    if (Test-AnsiTerminal) { [Console]::Out.Write("$([char]27)[?25l") }
    return $was
}

function Show-AnsiCursor {
    [CmdletBinding()]
    [OutputType([System.Nullable[bool]])]
    param()
    $was = Test-AnsiCursorVisible
    if (Test-AnsiTerminal) { [Console]::Out.Write("$([char]27)[?25h") }
    return $was
}

# Puts back what Hide-AnsiCursor or Show-AnsiCursor reported. An unknown previous
# state means show: a script that never hid its cursor must not be left without one.
function Restore-AnsiCursor {
    [CmdletBinding()]
    param([AllowNull()][System.Nullable[bool]]$State)
    if ($false -eq $State) { $null = Hide-AnsiCursor } else { $null = Show-AnsiCursor }
}

# Cursor control for prompts that repaint a list in place. Not colour, so it is
# emitted even under NO_COLOR — a redrawn list is unreadable otherwise.
function Move-AnsiCursorUp {
    [CmdletBinding()]
    param([Parameter(Mandatory)][int]$Lines)
    if ($Lines -le 0) { return }
    Write-Host ("$([char]27)[${Lines}A") -NoNewline
}

function Clear-AnsiLine {
    Write-Host ("$([char]27)[2K$([char]27)[G") -NoNewline
}

# Choices as {Item; Runs}: the label is parsed once, the original object is kept
# so a prompt can return what the caller passed in.
function ConvertTo-AnsiChoices {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Items,
        [AllowNull()][string]$LabelProperty,
        [AllowNull()][string]$Fg,
        [switch]$Markdown,
        [switch]$Escape
    )
    $choices = [System.Collections.Generic.List[object]]::new()
    foreach ($item in $Items) {
        $label = ''
        if ($LabelProperty -and $null -ne $item) {
            $member = $item.PSObject.Properties[$LabelProperty]
            $label = if ($null -ne $member) { [string]$member.Value } else { [string]$item }
        } else {
            $label = [string]$item
        }

        $runs = $null
        if ($Escape) {
            $runs = @([PSCustomObject]@{ Text = $label; Fg = $Fg; Bg = $null; Styles = @(); Link = $null })
        } else {
            $runs = ConvertFrom-AnsiMarkup -Text $label -AsMarkdown:$Markdown
            foreach ($r in $runs) { if (-not $r.Fg) { $r.Fg = $Fg } }
        }
        $null = $choices.Add([PSCustomObject]@{ Item = $item; Label = $label; Runs = @($runs) })
    }
    return , $choices.ToArray()
}

# The slice of choices to show, keeping the cursor inside it.
function Get-AnsiChoiceWindow {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][int]$Index,
        [Parameter(Mandatory)][int]$Count,
        [Parameter(Mandatory)][int]$PageSize,
        [int]$Start = 0
    )
    $size = [Math]::Min([Math]::Max(1, $PageSize), [Math]::Max(1, $Count))
    if ($Index -lt $Start) { $Start = $Index }
    if ($Index -ge $Start + $size) { $Start = $Index - $size + 1 }
    if ($Start -gt $Count - $size) { $Start = $Count - $size }
    if ($Start -lt 0) { $Start = 0 }
    return [PSCustomObject]@{ Start = $Start; Size = $size; End = $Start + $size - 1 }
}

# Visible width of one row of runs.
function Measure-AnsiRow {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Runs)
    $visible = 0
    foreach ($run in $Runs) { $visible += $run.Text.Length }
    return $visible
}

# A nested rendering reduced to what a host component needs: its rows and the
# widest of them. Returns $null for anything that is not a rendering, so callers
# can fall through to their own string handling.
function Get-AnsiRenderingBlock {
    [CmdletBinding()]
    param([AllowNull()][object]$Value)

    if (-not (Test-AnsiRendering -Value $Value)) { return $null }

    $rows = @($Value.Rows)
    $width = 0
    foreach ($row in $rows) {
        $rowWidth = Measure-AnsiRow -Runs @($row)
        if ($rowWidth -gt $width) { $width = $rowWidth }
    }
    return [PSCustomObject]@{ Rows = $rows; Width = $width }
}

# One run of text in one style. Components with richer runs build their own.
function New-AnsiRun {
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

# --- Numbers and charts ------------------------------------------------------

$script:AnsiNumericType = @(
    [byte], [sbyte], [int16], [uint16], [int], [uint32], [long], [uint64],
    [single], [double], [decimal]
)

function Test-AnsiNumber {
    [CmdletBinding()]
    param([AllowNull()][object]$Value)
    if ($null -eq $Value) { return $false }
    return ($script:AnsiNumericType -contains $Value.GetType())
}

# Whole numbers stay whole, anything else keeps one decimal, and a -Format wins
# over both. Invariant throughout, so a chart reads the same on a comma locale.
function Format-AnsiNumber {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][double]$Number,
        [AllowNull()][string]$Format
    )
    if (-not [string]::IsNullOrEmpty($Format)) {
        return [string]::Format([cultureinfo]::InvariantCulture, "{0:$Format}", $Number)
    }
    if ([Math]::Abs($Number - [Math]::Round($Number)) -lt 0.0001) {
        return [string][long][Math]::Round($Number)
    }
    return [string]::Format([cultureinfo]::InvariantCulture, '{0:0.0}', $Number)
}

# Filled and empty cell for a chart's bar.
function Get-AnsiChartChar {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Style)
    $key = $Style.ToLowerInvariant()
    if (-not $script:AnsiChartCharMap.ContainsKey($key)) {
        throw "Unknown chart style '$Style'. Use one of: $((($script:AnsiChartCharMap.Keys | Sort-Object) -join ', '))."
    }
    return , $script:AnsiChartCharMap[$key]
}

# A named field off a hashtable, a dictionary, or an object's properties. Both
# lookups are case-insensitive, so -ValueProperty ws finds WS.
function Get-AnsiItemField {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Item,
        [Parameter(Mandatory)][string]$Name
    )
    if ($Item -is [System.Collections.IDictionary]) {
        foreach ($key in $Item.Keys) {
            if ([string]$key -eq $Name) { return $Item[$key] }
        }
        return $null
    }
    $member = $Item.PSObject.Properties[$Name]
    if ($null -ne $member) { return $member.Value }
    return $null
}

# Whatever the caller passed reduced to {Label; Value; Color} per item: objects
# read through the -*Property names, hashtables, or bare numbers — no wrapper type,
# the same way Format-AnsiTable takes rows. Colours resolve here, so an unknown one
# throws before anything is drawn; an item that names none takes the next palette
# colour.
function ConvertTo-AnsiChartItem {
    [CmdletBinding()]
    param(
        # AllowNull, because a null element is a gap in the data, not a failure.
        [Parameter(Mandatory)][AllowNull()][AllowEmptyCollection()][object[]]$Items,
        [string]$LabelProperty = 'Label',
        [string]$ValueProperty = 'Value',
        [string]$ColorProperty = 'Color',
        [AllowNull()][string[]]$Palette,
        [AllowNull()][string]$DefaultColor
    )
    $colors = if ($Palette -and $Palette.Count -gt 0) { $Palette } else { $script:AnsiChartPalette }

    $result = [System.Collections.Generic.List[object]]::new()
    foreach ($item in $Items) {
        if ($null -eq $item) { continue }

        $label = ''
        $raw = $null
        $color = $null
        if (Test-AnsiNumber -Value $item) {
            # A bare number is a value with no label of its own.
            $raw = $item
        } else {
            $label = [string](Get-AnsiItemField -Item $item -Name $LabelProperty)
            $raw = Get-AnsiItemField -Item $item -Name $ValueProperty
            $color = Get-AnsiItemField -Item $item -Name $ColorProperty
            if ($null -eq $raw) {
                throw "Chart item '$label' has no $ValueProperty. Give every item a value, or name the property with -ValueProperty."
            }
        }

        $value = Convert-AnsiChartValue -Value $raw -Label $label
        $fg = if ($color) { Get-AnsiColorName -Name ([string]$color) }
        elseif ($DefaultColor) { Get-AnsiColorName -Name $DefaultColor }
        else { Get-AnsiColorName -Name $colors[$result.Count % $colors.Count] }

        $null = $result.Add([PSCustomObject]@{ Label = $label; Value = $value; Color = $fg })
    }
    return , $result.ToArray()
}

# A chart label or title as runs: markup by default, markdown with -Markdown,
# literal with -Escape. A chart row is one line, so hard breaks collapse to spaces.
function ConvertTo-AnsiChartLabel {
    [CmdletBinding()]
    param(
        [AllowNull()][AllowEmptyString()][string]$Text,
        [AllowNull()][string]$Fg,
        [Parameter(Mandatory)][hashtable]$Parse
    )
    if ([string]::IsNullOrEmpty($Text)) { return , @() }

    $flat = $Text -replace "`r?`n", ' '
    if ($Parse.Escape) { return , @(New-AnsiRun -Text $flat -Fg $Fg) }

    # Plain assignment, not @(): ConvertFrom-AnsiMarkup returns the run array
    # comma-wrapped, so @() would nest it one level deeper.
    $runs = ConvertFrom-AnsiMarkup -Text $flat -AsMarkdown:$Parse.Markdown
    foreach ($r in $runs) { if (-not $r.Fg) { $r.Fg = $Fg } }
    return , @($runs)
}

# A chart value as a double. Numbers pass straight through; text is parsed
# invariantly first, then in the current culture, so '2.5' is two and a half
# wherever it is read and '2,5' still lands on a comma locale.
function Convert-AnsiChartValue {
    [CmdletBinding()]
    [OutputType([double])]
    param(
        [Parameter(Mandatory)][AllowNull()][object]$Value,
        [AllowEmptyString()][string]$Label
    )
    if (Test-AnsiNumber -Value $Value) { return [double]$Value }

    $number = 0.0
    $text = [string]$Value
    if ([double]::TryParse($text, [System.Globalization.NumberStyles]::Float,
            [cultureinfo]::InvariantCulture, [ref]$number)) {
        return $number
    }
    if ([double]::TryParse($text, [ref]$number)) { return $number }
    $which = if ([string]::IsNullOrEmpty($Label)) { 'a chart item' } else { "chart item '$Label'" }
    throw "The value of $which is not a number: '$text'."
}

Export-ModuleMember -Function `
    Test-AnsiNoColor,
Get-AnsiColorName,
Get-AnsiAnchor,
ConvertFrom-AnsiTag,
ConvertFrom-AnsiMarkdown,
ConvertFrom-AnsiMarkup,
Split-AnsiRuns,
Format-AnsiLine,
Add-AnsiJustify,
New-AnsiRendering,
Test-AnsiRendering,
Measure-AnsiRow,
Get-AnsiRenderingBlock,
New-AnsiRun,
Test-AnsiNumber,
Format-AnsiNumber,
Get-AnsiChartChar,
Get-AnsiItemField,
ConvertTo-AnsiChartItem,
ConvertTo-AnsiChartLabel,
Convert-AnsiChartValue,
Test-AnsiTerminal,
Write-AnsiFrame,
Format-AnsiFrame,
Test-AnsiCursorVisible,
Hide-AnsiCursor,
Show-AnsiCursor,
Restore-AnsiCursor,
Test-AnsiInteractive,
Test-AnsiKeyAvailable,
Read-AnsiKeyInfo,
Start-AnsiWait,
Move-AnsiCursorUp,
Clear-AnsiLine,
ConvertTo-AnsiChoices,
Get-AnsiChoiceWindow
