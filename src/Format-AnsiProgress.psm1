#Requires -Version 7.2

# Format-AnsiProgress.psm1
# Public: Format-AnsiProgress — builds an [Ansi.Rendering].
# Paint it with Out-AnsiHost, or turn it into strings with Out-AnsiString.
#
# One row: an optional label, a bar, and an optional suffix.
#
#     restore  ████████████░░░░░░░░░░░░░░░░░░   40%
#
# The bar is filled and empty cells in whole characters — no partial blocks, so the
# same value always draws the same bar and a plain terminal shows the same shape a
# fancy one does. Invoke-AnsiTask paints these live; on its own it is a bar you can
# nest in a panel, a grid cell, or a table.

Import-Module (Join-Path $PSScriptRoot 'Ansi.Core.psm1') -Force -DisableNameChecking

$script:AnsiProgressCharMap = @{
    # Filled, empty.
    'blocks' = @([string][char]0x2588, [string][char]0x2591)   # █ ░
    'line'   = @([string][char]0x2501, [string][char]0x2500)   # ━ ─
    'dots'   = @([string][char]0x25CF, [string][char]0x00B7)   # ● ·
    'ascii'  = @('#', '-')
}

function Format-AnsiProgress {
    [CmdletBinding()]
    [OutputType('Ansi.Rendering')]
    param(
        # How far along, in the same units as -Total.
        [Parameter(Position = 0, Mandatory, ValueFromPipeline)]
        [double]$Value,

        [ValidateRange(0.000001, [double]::MaxValue)]
        [double]$Total = 100,

        # Text before the bar. Markup is honoured unless -Escape is passed.
        [Parameter(Position = 1)]
        [AllowEmptyString()]
        [string]$Label,

        # Total width of the row: label, bar, and suffix together. Default: from the
        # cursor to the right edge, like every other component.
        [int]$Width = 0,

        # Width of the bar itself. Default: whatever is left after label and suffix.
        [ValidateRange(0, [int]::MaxValue)]
        [int]$BarWidth = 0,

        # Pad the label to this width so a column of bars lines up.
        [ValidateRange(0, [int]::MaxValue)]
        [int]$LabelWidth = 0,

        # What follows the bar.
        [ValidateSet('Percent', 'Count', 'Both', 'None')]
        [string]$Show = 'Percent',

        [ValidateSet('Blocks', 'Line', 'Dots', 'Ascii')]
        [string]$Style = 'Blocks',

        [Alias('Color')]
        [string]$BarColor,

        [string]$EmptyColor,

        [string]$LabelColor,

        [string]$SuffixColor,

        # Colour the bar with this instead once it reaches -Total.
        [string]$CompleteColor,

        [switch]$Markdown,

        [switch]$Escape
    )
    process {
        $anchor = Get-AnsiAnchor -MaxWidth $Width
        $noColor = Test-AnsiNoColor

        $rowWidth = [Math]::Max(1, $anchor.Width)
        $percent = Get-AnsiProgressPercent -Value $Value -Total $Total
        $done = ($percent -ge 100)

        $labelRuns = @()
        if (-not [string]::IsNullOrEmpty($Label)) {
            $labelFg = if ($LabelColor) { Get-AnsiColorName -Name $LabelColor } else { $null }
            # A bar is one row: hard breaks in the label collapse to spaces.
            $flat = $Label -replace "`r?`n", ' '
            if ($Escape) {
                $labelRuns = @(New-AnsiProgressRun -Text $flat -Fg $labelFg)
            } else {
                # Plain assignment, not @(): ConvertFrom-AnsiMarkup returns the run
                # array comma-wrapped, so @() would nest it one level deeper.
                $labelRuns = ConvertFrom-AnsiMarkup -Text $flat -AsMarkdown:$Markdown
                foreach ($r in $labelRuns) { if (-not $r.Fg) { $r.Fg = $labelFg } }
            }
        }

        $labelText = Get-AnsiProgressLabelWidth -Runs $labelRuns -LabelWidth $LabelWidth
        $suffix = Get-AnsiProgressSuffix -Show $Show -Percent $percent -Value $Value -Total $Total

        # The bar gets what the label and suffix leave, unless told a width. Named
        # $barCells, not $barWidth: variable names are case-insensitive, so that
        # would assign to the -BarWidth parameter and re-run its ValidateRange.
        $spent = $labelText + $suffix.Length
        $barCells = if ($BarWidth -gt 0) { $BarWidth } else { $rowWidth - $spent }
        $barCells = [Math]::Max(1, $barCells)

        $chars = $script:AnsiProgressCharMap[$Style.ToLowerInvariant()]
        $filled = [int][Math]::Round(($percent / 100) * $barCells, [MidpointRounding]::AwayFromZero)
        $filled = [Math]::Min($barCells, [Math]::Max(0, $filled))
        # Never show an empty bar past zero, nor a full one short of the total: the
        # shape is what gets read, and rounding must not lie about either end. The
        # full guard goes last, so on a one cell bar "full means done" still holds.
        if ($filled -eq 0 -and $percent -gt 0) { $filled = 1 }
        if ($filled -eq $barCells -and -not $done) { $filled = $barCells - 1 }

        $barFg = if ($done -and $CompleteColor) { Get-AnsiColorName -Name $CompleteColor }
        elseif ($BarColor) { Get-AnsiColorName -Name $BarColor }
        else { $null }
        $emptyFg = if ($EmptyColor) { Get-AnsiColorName -Name $EmptyColor } else { $null }
        $suffixFg = if ($SuffixColor) { Get-AnsiColorName -Name $SuffixColor } else { $null }

        $runs = [System.Collections.Generic.List[object]]::new()
        foreach ($r in $labelRuns) { $null = $runs.Add($r) }
        if ($labelText -gt (Measure-AnsiRow -Runs @($labelRuns))) {
            $pad = $labelText - (Measure-AnsiRow -Runs @($labelRuns))
            $null = $runs.Add((New-AnsiProgressRun -Text (' ' * $pad) -Fg $null))
        }
        if ($filled -gt 0) {
            $null = $runs.Add((New-AnsiProgressRun -Text ($chars[0] * $filled) -Fg $barFg))
        }
        if ($barCells - $filled -gt 0) {
            $null = $runs.Add((New-AnsiProgressRun -Text ($chars[1] * ($barCells - $filled)) -Fg $emptyFg))
        }
        if ($suffix) {
            $null = $runs.Add((New-AnsiProgressRun -Text $suffix -Fg $suffixFg))
        }

        $width = Measure-AnsiRow -Runs @($runs.ToArray())
        return (New-AnsiRendering -Kind 'Progress' -Rows @(, @($runs.ToArray())) -Width $width `
                -Column $anchor.Column -NoColor $noColor)
    }
}

# 0..100, clamped: a caller counting past its own total still gets a full bar.
function Get-AnsiProgressPercent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][double]$Value,
        [Parameter(Mandatory)][double]$Total
    )
    if ($Total -le 0) { return 100 }
    $percent = ($Value / $Total) * 100
    if ($percent -lt 0) { return 0 }
    if ($percent -gt 100) { return 100 }
    return $percent
}

# What trails the bar, with the leading spaces that separate it.
function Get-AnsiProgressSuffix {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Show,
        [Parameter(Mandatory)][double]$Percent,
        [Parameter(Mandatory)][double]$Value,
        [Parameter(Mandatory)][double]$Total
    )
    $shown = $Show.ToLowerInvariant()
    if ($shown -eq 'none') { return '' }

    # Right-aligned to a fixed width so a bar does not shift as the numbers grow.
    $percentText = [string]::Format([cultureinfo]::InvariantCulture, '{0,4:0}%', $Percent)
    if ($shown -eq 'percent') { return "  $percentText" }

    # Value padded to the width of Total, so the bar does not shift as it counts up.
    $countWidth = ([string](Format-AnsiProgressNumber -Number $Total)).Length
    $countText = ('{0,' + $countWidth + '}/{1}') -f
        (Format-AnsiProgressNumber -Number $Value), (Format-AnsiProgressNumber -Number $Total)
    if ($shown -eq 'count') { return "  $countText" }
    return "  $countText  $percentText"
}

# Whole numbers stay whole; anything else keeps one decimal. Invariant culture, so
# a bar reads the same on a comma locale as it does on a dot one.
function Format-AnsiProgressNumber {
    [CmdletBinding()]
    param([Parameter(Mandatory)][double]$Number)
    if ([Math]::Abs($Number - [Math]::Round($Number)) -lt 0.0001) {
        return [string][long][Math]::Round($Number)
    }
    return [string]::Format([cultureinfo]::InvariantCulture, '{0:0.0}', $Number)
}

# The width the label occupies, padding included.
function Get-AnsiProgressLabelWidth {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Runs,
        [Parameter(Mandatory)][int]$LabelWidth
    )
    $visible = Measure-AnsiRow -Runs @($Runs)
    if ($visible -eq 0 -and $LabelWidth -eq 0) { return 0 }
    # One space between the label and the bar.
    $width = [Math]::Max($visible, $LabelWidth)
    return $width + 1
}

function New-AnsiProgressRun {
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

Export-ModuleMember -Function Format-AnsiProgress
