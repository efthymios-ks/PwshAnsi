#Requires -Version 7.2

# Format-AnsiPanel.psm1
# Public: Format-AnsiPanel — builds an [Ansi.Rendering].
# Paint it with Out-AnsiHost, or turn it into strings with Out-AnsiString.

Import-Module (Join-Path $PSScriptRoot 'Ansi.Core.psm1') -Force -DisableNameChecking

$script:AnsiPanelBorderMap = @{
    'none'    = @{
        TL = ' '; TR = ' '; BL = ' '; BR = ' '
        H  = ' '; V = ' '
        Draw = $false
    }
    'ascii'   = @{
        TL = '+'; TR = '+'; BL = '+'; BR = '+'
        H  = '-'; V = '|'
        Draw = $true
    }
    'square'  = @{
        TL = [string][char]0x250C; TR = [string][char]0x2510
        BL = [string][char]0x2514; BR = [string][char]0x2518
        H  = [string][char]0x2500; V = [string][char]0x2502
        Draw = $true
    }
    'rounded' = @{
        TL = [string][char]0x256D; TR = [string][char]0x256E
        BL = [string][char]0x2570; BR = [string][char]0x256F
        H  = [string][char]0x2500; V = [string][char]0x2502
        Draw = $true
    }
    'heavy'   = @{
        TL = [string][char]0x250F; TR = [string][char]0x2513
        BL = [string][char]0x2517; BR = [string][char]0x251B
        H  = [string][char]0x2501; V = [string][char]0x2503
        Draw = $true
    }
    'double'  = @{
        TL = [string][char]0x2554; TR = [string][char]0x2557
        BL = [string][char]0x255A; BR = [string][char]0x255D
        H  = [string][char]0x2550; V = [string][char]0x2551
        Draw = $true
    }
}

function Format-AnsiPanel {
    [CmdletBinding()]
    [OutputType('Ansi.Rendering')]
    param(
        [Parameter(Position = 0, ValueFromPipeline)]
        [AllowNull()]
        [AllowEmptyString()]
        [AllowEmptyCollection()]
        [Alias('Content')]
        [object[]]$Data,

        [string]$Title,

        [ValidateSet('Left', 'Center', 'Right')]
        [string]$TitleAlignment = 'Left',

        [ValidateSet('None', 'Ascii', 'Square', 'Rounded', 'Heavy', 'Double')]
        [string]$Border = 'Rounded',

        [string]$BorderColor,

        [string]$TextColor,

        [string]$TitleColor,

        [ValidateSet('Left', 'Center', 'Right')]
        [string]$Justify = 'Left',

        [ValidateRange(0, [int]::MaxValue)]
        [int]$Padding = 1,

        [Alias('MaxWidth')]
        [int]$Width = 0,

        [ValidateRange(0, [int]::MaxValue)]
        [int]$Height = 0,

        [switch]$Expand,

        [switch]$Rendered,

        [switch]$Markdown,

        [switch]$Escape
    )
    begin {
        $accumulated = [System.Collections.Generic.List[object]]::new()
    }
    process {
        if ($null -eq $Data) { return }
        # Renderings stay objects; everything else becomes a text line.
        foreach ($item in $Data) {
            if (Test-AnsiRendering -Value $item) { $null = $accumulated.Add($item) }
            else { $null = $accumulated.Add([string]$item) }
        }
    }
    end {
        if ($accumulated.Count -eq 0) { return }

        $anchor = Get-AnsiAnchor -MaxWidth $Width
        $noColor = Test-AnsiNoColor

        # Not $Border: assigning to it would re-validate the ValidateSet.
        $borderChars = $script:AnsiPanelBorderMap[$Border.ToLowerInvariant()]
        $edge = if ($borderChars.Draw -or $Border -eq 'None') { 1 } else { 1 }

        $borderFg = if ($BorderColor) { Get-AnsiColorName -Name $BorderColor } else { $null }
        $textFg = if ($TextColor) { Get-AnsiColorName -Name $TextColor } else { $null }
        $titleFg = if ($TitleColor) { Get-AnsiColorName -Name $TitleColor } else { $borderFg }

        $overhead = (2 * $edge) + (2 * $Padding)

        # Content lines first, so a panel that is not expanded can shrink to fit.
        $contentLines = [System.Collections.Generic.List[object]]::new()
        $maxInner = [Math]::Max(1, $anchor.Width - $overhead)

        if ($Rendered) {
            # Already-rendered rows: pass the text through, measure visible width.
            foreach ($line in $accumulated) {
                $text = [string]$line
                # Pre-rendered text is opaque to Format-AnsiLine, so strip it here
                # when the host cannot show styles.
                if ($noColor) { $text = Remove-AnsiPanelAnsi -Text $text }
                $visible = Measure-AnsiPanelVisible -Text $text
                if ($visible -gt $maxInner) {
                    $text = Limit-AnsiPanelRendered -Text $text -Width $maxInner
                    $visible = Measure-AnsiPanelVisible -Text $text
                }
                $null = $contentLines.Add([PSCustomObject]@{ Text = $text; Visible = $visible })
            }
        } else {
            # Text lines wrap as a block; a nested rendering keeps its own rows.
            # Consecutive strings are gathered so wrapping still sees them as one
            # block, exactly as before.
            $pending = [System.Collections.Generic.List[string]]::new()

            $flushPending = {
                if ($pending.Count -eq 0) { return }
                $runs = Get-AnsiPanelRuns -Lines $pending -Fg $textFg -Markdown:$Markdown -Escape:$Escape
                $wrapped = Split-AnsiRuns -Runs $runs -Width $maxInner -Overflow Fold
                foreach ($lineRuns in $wrapped) {
                    $rowRuns = @($lineRuns)
                    $null = $contentLines.Add([PSCustomObject]@{
                            Runs = $rowRuns; Visible = (Measure-AnsiRow -Runs $rowRuns)
                        })
                }
                $pending.Clear()
            }

            foreach ($item in $accumulated) {
                $block = Get-AnsiRenderingBlock -Value $item
                if ($null -eq $block) {
                    $null = $pending.Add([string]$item)
                    continue
                }
                & $flushPending
                foreach ($row in $block.Rows) {
                    $rowRuns = @($row)
                    $visible = Measure-AnsiRow -Runs $rowRuns
                    if ($visible -gt $maxInner) {
                        $cropped = Split-AnsiRuns -Runs $rowRuns -Width $maxInner -Overflow Ellipsis
                        $rowRuns = @($cropped[0])
                        $visible = Measure-AnsiRow -Runs $rowRuns
                    }
                    $null = $contentLines.Add([PSCustomObject]@{ Runs = $rowRuns; Visible = $visible })
                }
            }
            & $flushPending
        }

        $titleRuns = @()
        $titleVisible = 0
        if ($Title) {
            $flat = $Title -replace "`r?`n", ' '
            $titleRuns = Get-AnsiPanelRuns -Lines @($flat) -Fg $titleFg -Markdown:$Markdown -Escape:$Escape
            foreach ($r in $titleRuns) { $titleVisible += $r.Text.Length }
        }

        $inner = 0
        foreach ($line in $contentLines) { if ($line.Visible -gt $inner) { $inner = $line.Visible } }
        if ($Title) {
            # ' Title ' has to fit between the corners.
            $needed = $titleVisible + 2
            if ($needed -gt $inner) { $inner = $needed }
        }
        if ($Expand) { $inner = $maxInner }
        $inner = [Math]::Min([Math]::Max(1, $inner), $maxInner)

        # -Height pads with blank rows or drops the overflow.
        if ($Height -gt 0) {
            $contentRows = [Math]::Max(0, $Height - 2)
            while ($contentLines.Count -gt $contentRows) { $contentLines.RemoveAt($contentLines.Count - 1) }
            while ($contentLines.Count -lt $contentRows) {
                $null = $contentLines.Add([PSCustomObject]@{ Runs = @(); Text = ''; Visible = 0 })
            }
        }

        $lines = [System.Collections.Generic.List[object]]::new()
        $panelWidth = $inner + $overhead

        $null = $lines.Add((New-AnsiPanelTop -Border $borderChars -Inner ($inner + (2 * $Padding)) `
                    -TitleRuns $titleRuns -TitleVisible $titleVisible -Alignment $TitleAlignment -Fg $borderFg))

        foreach ($line in $contentLines) {
            $null = $lines.Add((New-AnsiPanelRow -Border $borderChars -Inner $inner -Padding $Padding `
                        -Line $line -Justify $Justify -Fg $borderFg -Rendered:$Rendered))
        }

        $null = $lines.Add((New-AnsiPanelBottom -Border $borderChars -Inner ($inner + (2 * $Padding)) -Fg $borderFg))

        return (New-AnsiRendering -Kind 'Panel' -Rows $lines.ToArray() -Width $panelWidth `
                -Column $anchor.Column -NoColor $noColor)
    }
}

function New-AnsiPanelRun {
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

function Get-AnsiPanelRuns {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object]$Lines,
        [AllowNull()][string]$Fg,
        [switch]$Markdown,
        [switch]$Escape
    )
    $text = @($Lines) -join "`n"

    if ($Escape) { return , @(New-AnsiPanelRun -Text $text -Fg $Fg) }

    $runs = ConvertFrom-AnsiMarkup -Text $text -AsMarkdown:$Markdown
    foreach ($r in $runs) { if (-not $r.Fg) { $r.Fg = $Fg } }
    return , $runs
}

function Remove-AnsiPanelAnsi {
    [CmdletBinding()]
    param([AllowEmptyString()][string]$Text)
    $plain = $Text -replace "`e\[[\d;]*m", ''
    return ($plain -replace "`e\]8;;[^`e]*`e\\", '')
}

# Visible width of an already-rendered row: styles and hyperlink wrappers do not
# occupy columns.
function Measure-AnsiPanelVisible {
    [CmdletBinding()]
    param([AllowEmptyString()][string]$Text)
    return (Remove-AnsiPanelAnsi -Text $Text).Length
}

# Trim a rendered row to a visible width, keeping escape sequences intact and
# marking the cut with `…`.
function Limit-AnsiPanelRendered {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text,
        [Parameter(Mandatory)][int]$Width
    )
    if ($Width -le 0) { return '' }

    $keep = [Math]::Max(0, $Width - 1)
    $sb = [System.Text.StringBuilder]::new()
    $visible = 0
    $i = 0

    while ($i -lt $Text.Length) {
        if ($Text[$i] -eq [char]27) {
            # Copy the whole escape sequence: CSI ... letter, or OSC ... ESC \.
            $start = $i
            $i++
            if ($i -lt $Text.Length -and $Text[$i] -eq '[') {
                $i++
                while ($i -lt $Text.Length -and $Text[$i] -notmatch '[A-Za-z]') { $i++ }
                if ($i -lt $Text.Length) { $i++ }
            } elseif ($i -lt $Text.Length -and $Text[$i] -eq ']') {
                while ($i -lt $Text.Length -and -not ($Text[$i] -eq [char]27)) { $i++ }
                if ($i + 1 -lt $Text.Length) { $i += 2 }
            }
            $null = $sb.Append($Text.Substring($start, $i - $start))
            continue
        }
        if ($visible -ge $keep) { break }
        $null = $sb.Append($Text[$i])
        $visible++
        $i++
    }

    $null = $sb.Append([char]0x2026)
    $null = $sb.Append($PSStyle.Reset)
    return $sb.ToString()
}

function New-AnsiPanelTop {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Border,
        [Parameter(Mandatory)][int]$Inner,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$TitleRuns,
        [Parameter(Mandatory)][int]$TitleVisible,
        [Parameter(Mandatory)][string]$Alignment,
        [AllowNull()][string]$Fg
    )
    $row = [System.Collections.Generic.List[object]]::new()
    $null = $row.Add((New-AnsiPanelRun -Text $Border.TL -Fg $Fg))

    if ($TitleRuns.Count -eq 0 -or $TitleVisible -eq 0) {
        $null = $row.Add((New-AnsiPanelRun -Text ($Border.H * $Inner) -Fg $Fg))
        $null = $row.Add((New-AnsiPanelRun -Text $Border.TR -Fg $Fg))
        return , $row.ToArray()
    }

    # ─ Title ─ : one space either side of the title, rule filling the rest.
    $slack = [Math]::Max(0, $Inner - $TitleVisible - 2)
    $left = switch ($Alignment) {
        'Left' { 1 }
        'Right' { $slack + 1 }
        default { [int][Math]::Floor($slack / 2) + 1 }
    }
    $right = $Inner - $TitleVisible - 2 - ($left - 1) + 1
    if ($right -lt 1) { $right = 1 }

    $null = $row.Add((New-AnsiPanelRun -Text ($Border.H * ($left - 1)) -Fg $Fg))
    $null = $row.Add((New-AnsiPanelRun -Text ' ' -Fg $null))
    foreach ($r in $TitleRuns) { $null = $row.Add($r) }
    $null = $row.Add((New-AnsiPanelRun -Text ' ' -Fg $null))
    $null = $row.Add((New-AnsiPanelRun -Text ($Border.H * ($right - 1)) -Fg $Fg))
    $null = $row.Add((New-AnsiPanelRun -Text $Border.TR -Fg $Fg))
    return , $row.ToArray()
}

function New-AnsiPanelBottom {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Border,
        [Parameter(Mandatory)][int]$Inner,
        [AllowNull()][string]$Fg
    )
    return , @(
        (New-AnsiPanelRun -Text $Border.BL -Fg $Fg)
        (New-AnsiPanelRun -Text ($Border.H * $Inner) -Fg $Fg)
        (New-AnsiPanelRun -Text $Border.BR -Fg $Fg)
    )
}

function New-AnsiPanelRow {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Border,
        [Parameter(Mandatory)][int]$Inner,
        [Parameter(Mandatory)][int]$Padding,
        [Parameter(Mandatory)][object]$Line,
        [Parameter(Mandatory)][string]$Justify,
        [AllowNull()][string]$Fg,
        [switch]$Rendered
    )
    $visible = [int]$Line.Visible
    $slack = [Math]::Max(0, $Inner - $visible)
    $leftPad = switch ($Justify) {
        'Right' { $slack }
        'Center' { [int][Math]::Floor($slack / 2) }
        default { 0 }
    }
    $rightPad = $slack - $leftPad
    $pad = ' ' * $Padding

    $row = [System.Collections.Generic.List[object]]::new()
    $null = $row.Add((New-AnsiPanelRun -Text $Border.V -Fg $Fg))
    if ($Padding -gt 0) { $null = $row.Add((New-AnsiPanelRun -Text $pad -Fg $null)) }
    if ($leftPad -gt 0) { $null = $row.Add((New-AnsiPanelRun -Text (' ' * $leftPad) -Fg $null)) }

    if ($Rendered) {
        # Pre-rendered text is emitted verbatim, wrapped in its own run so
        # Format-AnsiLine does not restyle it.
        $null = $row.Add((New-AnsiPanelRun -Text ([string]$Line.Text) -Fg $null))
    } else {
        foreach ($r in @($Line.Runs)) { $null = $row.Add($r) }
    }

    if ($rightPad -gt 0) { $null = $row.Add((New-AnsiPanelRun -Text (' ' * $rightPad) -Fg $null)) }
    if ($Padding -gt 0) { $null = $row.Add((New-AnsiPanelRun -Text $pad -Fg $null)) }
    $null = $row.Add((New-AnsiPanelRun -Text $Border.V -Fg $Fg))
    return , $row.ToArray()
}

Export-ModuleMember -Function Format-AnsiPanel
