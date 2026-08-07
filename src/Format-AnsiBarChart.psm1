#Requires -Version 7.2

# Format-AnsiBarChart.psm1
# Public: Format-AnsiBarChart — builds an [Ansi.Rendering].
# Paint it with Out-AnsiHost, or turn it into strings with Out-AnsiString.
#
# One row per item: a label, a bar as long as the value deserves, and the value.
#
#              fruit sales
#     apples  ████████████████████ 12
#    oranges  ████████ 5
#    bananas  ███ 2.2
#
# Bars are scaled against the largest value — or -MaxValue — in whole cells, so the
# same data always draws the same chart and a plain terminal shows the same shape a
# fancy one does. Values are formatted invariantly.

Import-Module (Join-Path $PSScriptRoot 'Ansi.Core.psm1') -Force -DisableNameChecking

function Format-AnsiBarChart {
    [CmdletBinding()]
    [OutputType('Ansi.Rendering')]
    param(
        # What to chart, the way Format-AnsiTable takes its rows: any objects with
        # Label/Value/Color — rename with the -*Property parameters — hashtables,
        # or bare numbers.
        [Parameter(Position = 0, Mandatory, ValueFromPipeline)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]]$Data,

        # A title above the chart.
        [Parameter(Position = 1)]
        [Alias('Title')]
        [AllowEmptyString()]
        [string]$Label,

        # The whole chart: labels, bars, and values together. Default: from the
        # cursor to the right edge, like every other component.
        [Alias('MaxWidth')]
        [int]$Width = 0,

        # The bar column itself. Default: whatever the labels and values leave.
        [ValidateRange(0, [int]::MaxValue)]
        [int]$BarWidth = 0,

        # Pad the label column to this width instead of the widest label.
        [ValidateRange(0, [int]::MaxValue)]
        [int]$LabelWidth = 0,

        # What a full bar means. Default: the largest value in the data.
        [ValidateRange(0, [double]::MaxValue)]
        [double]$MaxValue = 0,

        [switch]$HideValues,

        # Show each value as its share of the total instead of the value itself.
        [switch]$ShowPercentage,

        [ValidateSet('Blocks', 'Line', 'Dots', 'Ascii')]
        [string]$Style = 'Blocks',

        # A .NET numeric format for the values, e.g. N0 or 0.00. Default: whole
        # numbers whole, anything else to one decimal.
        [string]$ValueFormat,

        # Colours handed to items that name none, in order, cycling.
        [string[]]$Palette,

        # The colour for items that name none, instead of the palette.
        [Alias('Color')]
        [string]$BarColor,

        [string]$LabelColor,

        [string]$ValueColor,

        [string]$TitleColor,

        [ValidateSet('Left', 'Center', 'Right')]
        [string]$TitleAlignment = 'Center',

        [ValidateSet('Left', 'Right')]
        [string]$LabelAlignment = 'Right',

        [string]$LabelProperty = 'Label',

        [string]$ValueProperty = 'Value',

        [string]$ColorProperty = 'Color',

        [switch]$Markdown,

        [switch]$Escape
    )
    begin {
        $collected = [System.Collections.Generic.List[object]]::new()
    }
    process {
        if ($null -eq $Data) { return }
        foreach ($item in $Data) { $null = $collected.Add($item) }
    }
    end {
        if ($collected.Count -eq 0) { return }

        $anchor = Get-AnsiAnchor -MaxWidth $Width
        $noColor = Test-AnsiNoColor
        $chartWidth = [Math]::Max(1, $anchor.Width)

        $items = ConvertTo-AnsiChartItem -Items $collected.ToArray() `
            -LabelProperty $LabelProperty -ValueProperty $ValueProperty `
            -ColorProperty $ColorProperty -Palette $Palette -DefaultColor $BarColor
        if ($items.Count -eq 0) { return }

        $labelFg = if ($LabelColor) { Get-AnsiColorName -Name $LabelColor } else { $null }
        $valueFg = if ($ValueColor) { Get-AnsiColorName -Name $ValueColor } else { $null }
        $parse = @{ Markdown = [bool]$Markdown; Escape = [bool]$Escape }

        $total = 0
        foreach ($item in $items) { $total += [Math]::Max(0, $item.Value) }

        # Label runs up front, so the column is sized on visible text, not markup.
        $rowsData = [System.Collections.Generic.List[object]]::new()
        foreach ($item in $items) {
            $labelRuns = ConvertTo-AnsiChartLabel -Text $item.Label -Fg $labelFg -Parse $parse
            $text = if ($ShowPercentage) {
                $share = if ($total -gt 0) { ([Math]::Max(0, $item.Value) / $total) * 100 } else { 0 }
                (Format-AnsiNumber -Number $share -Format $ValueFormat) + '%'
            } else {
                Format-AnsiNumber -Number $item.Value -Format $ValueFormat
            }
            $null = $rowsData.Add([PSCustomObject]@{
                    Item      = $item
                    LabelRuns = $labelRuns
                    ValueText = $text
                })
        }

        $labelCells = $LabelWidth
        if ($labelCells -le 0) {
            foreach ($row in $rowsData) {
                $measured = Measure-AnsiRow -Runs @($row.LabelRuns)
                if ($measured -gt $labelCells) { $labelCells = $measured }
            }
        }
        $valueCells = 0
        if (-not $HideValues) {
            foreach ($row in $rowsData) {
                if ($row.ValueText.Length -gt $valueCells) { $valueCells = $row.ValueText.Length }
            }
        }

        # One space either side of the bar column, only where there is something to
        # separate it from.
        $spent = $labelCells + $(if ($labelCells -gt 0) { 1 } else { 0 }) +
            $valueCells + $(if ($valueCells -gt 0) { 1 } else { 0 })
        # Named $barCells, not $barWidth: variable names are case-insensitive, so
        # that would assign to the -BarWidth parameter and re-run its ValidateRange.
        $barCells = if ($BarWidth -gt 0) { $BarWidth } else { $chartWidth - $spent }
        $barCells = [Math]::Max(1, $barCells)

        $ceiling = $MaxValue
        if ($ceiling -le 0) {
            foreach ($item in $items) { if ($item.Value -gt $ceiling) { $ceiling = $item.Value } }
        }
        $chars = Get-AnsiChartChar -Style $Style

        $rows = [System.Collections.Generic.List[object]]::new()

        if (-not [string]::IsNullOrEmpty($Label)) {
            $titleFg = if ($TitleColor) { Get-AnsiColorName -Name $TitleColor } else { $null }
            $titleRuns = ConvertTo-AnsiChartLabel -Text $Label -Fg $titleFg -Parse $parse
            $null = $rows.Add((Add-AnsiJustify -Runs @($titleRuns) -Width ($spent + $barCells) `
                        -Justify $TitleAlignment))
        }

        foreach ($row in $rowsData) {
            $runs = [System.Collections.Generic.List[object]]::new()

            $labelText = Measure-AnsiRow -Runs @($row.LabelRuns)
            $pad = [Math]::Max(0, $labelCells - $labelText)
            if ($LabelAlignment -eq 'Right' -and $pad -gt 0) {
                $null = $runs.Add((New-AnsiRun -Text (' ' * $pad) -Fg $null))
            }
            foreach ($r in $row.LabelRuns) { $null = $runs.Add($r) }
            if ($LabelAlignment -eq 'Left' -and $pad -gt 0) {
                $null = $runs.Add((New-AnsiRun -Text (' ' * $pad) -Fg $null))
            }
            if ($labelCells -gt 0) { $null = $runs.Add((New-AnsiRun -Text ' ' -Fg $null)) }

            $filled = Get-AnsiBarCell -Value $row.Item.Value -Ceiling $ceiling -Cells $barCells
            if ($filled -gt 0) {
                $null = $runs.Add((New-AnsiRun -Text ($chars[0] * $filled) -Fg $row.Item.Color))
            }

            if ($valueCells -gt 0) {
                # The value sits at the same column on every row, so the numbers
                # read as a column rather than trailing each bar.
                $gap = ($barCells - $filled) + 1
                $null = $runs.Add((New-AnsiRun -Text (' ' * $gap) -Fg $null))
                $null = $runs.Add((New-AnsiRun -Text $row.ValueText -Fg $valueFg))
            }

            $null = $rows.Add($runs.ToArray())
        }

        $chartCells = 0
        foreach ($row in $rows) {
            $measured = Measure-AnsiRow -Runs @($row)
            if ($measured -gt $chartCells) { $chartCells = $measured }
        }

        return (New-AnsiRendering -Kind 'BarChart' -Rows $rows.ToArray() -Width $chartCells `
                -Column $anchor.Column -NoColor $noColor)
    }
}

# How many cells a value fills. Whole cells only; a value past zero always keeps
# one, so a small share never reads as nothing at all.
function Get-AnsiBarCell {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][double]$Value,
        [Parameter(Mandatory)][double]$Ceiling,
        [Parameter(Mandatory)][int]$Cells
    )
    if ($Value -le 0 -or $Ceiling -le 0) { return 0 }
    $share = $Value / $Ceiling
    if ($share -gt 1) { $share = 1 }
    $filled = [int][Math]::Round($share * $Cells, [MidpointRounding]::AwayFromZero)
    if ($filled -lt 1) { $filled = 1 }
    if ($filled -gt $Cells) { $filled = $Cells }
    return $filled
}

Export-ModuleMember -Function Format-AnsiBarChart
