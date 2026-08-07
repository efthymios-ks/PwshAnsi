#Requires -Version 7.2

# Format-AnsiBreakdownChart.psm1
# Public: Format-AnsiBreakdownChart — builds an [Ansi.Rendering].
# Paint it with Out-AnsiHost, or turn it into strings with Out-AnsiString.
#
# One bar split by share, then a legend naming each part.
#
#     ████████████████████████░░░░░░░░░░░░░░░░████████
#     █ apples 12   █ oranges 5   █ bananas 2.2
#
# Cells are whole: the parts are handed out by largest remainder so they add up to
# the bar's width exactly, and any part with a value keeps at least one cell.

Import-Module (Join-Path $PSScriptRoot 'Ansi.Core.psm1') -Force -DisableNameChecking

function Format-AnsiBreakdownChart {
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

        # The bar and the legend. Default: from the cursor to the right edge, like
        # every other component.
        [Parameter(Position = 1)]
        [Alias('MaxWidth')]
        [int]$Width = 0,

        # Drop the legend and keep the bar.
        [switch]$HideTags,

        # Keep the legend, drop the numbers in it.
        [switch]$HideTagValues,

        # Show each part's share instead of its value.
        [switch]$ShowPercentage,

        # One legend entry per row, instead of as many as fit on a row.
        [switch]$FullSize,

        [ValidateSet('Blocks', 'Line', 'Dots', 'Ascii')]
        [string]$Style = 'Blocks',

        # A .NET numeric format for the legend, e.g. N0 or 0.00. Default: whole
        # numbers whole, anything else to one decimal.
        [string]$ValueFormat,

        # Colours handed to items that name none, in order, cycling.
        [string[]]$Palette,

        # The tag text. Default: the colour of the part it names.
        [string]$TagColor,

        [string]$ValueColor,

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
            -ColorProperty $ColorProperty -Palette $Palette
        if ($items.Count -eq 0) { return }

        $chars = Get-AnsiChartChar -Style $Style
        $tagFg = if ($TagColor) { Get-AnsiColorName -Name $TagColor } else { $null }
        $valueFg = if ($ValueColor) { Get-AnsiColorName -Name $ValueColor } else { $null }
        $parse = @{ Markdown = [bool]$Markdown; Escape = [bool]$Escape }

        $shares = Split-AnsiBreakdownCell -Items $items -Cells $chartWidth

        $rows = [System.Collections.Generic.List[object]]::new()

        # The bar: one run per part, then the remainder if the values do not fill it.
        $barRuns = [System.Collections.Generic.List[object]]::new()
        $drawn = 0
        for ($i = 0; $i -lt $items.Count; $i++) {
            if ($shares[$i] -le 0) { continue }
            $null = $barRuns.Add((New-AnsiRun -Text ($chars[0] * $shares[$i]) -Fg $items[$i].Color))
            $drawn += $shares[$i]
        }
        if ($drawn -lt $chartWidth) {
            $null = $barRuns.Add((New-AnsiRun -Text ($chars[1] * ($chartWidth - $drawn)) -Fg $null))
        }
        $null = $rows.Add($barRuns.ToArray())

        if (-not $HideTags) {
            $total = 0
            foreach ($item in $items) { $total += [Math]::Max(0, $item.Value) }

            $tags = [System.Collections.Generic.List[object]]::new()
            foreach ($item in $items) {
                $runs = [System.Collections.Generic.List[object]]::new()
                $null = $runs.Add((New-AnsiRun -Text $chars[0] -Fg $item.Color))
                $null = $runs.Add((New-AnsiRun -Text ' ' -Fg $null))

                $labelRuns = ConvertTo-AnsiChartLabel -Text $item.Label `
                    -Fg $(if ($tagFg) { $tagFg } else { $item.Color }) -Parse $parse
                foreach ($r in $labelRuns) { $null = $runs.Add($r) }

                if (-not $HideTagValues) {
                    $text = if ($ShowPercentage) {
                        $share = if ($total -gt 0) { ([Math]::Max(0, $item.Value) / $total) * 100 } else { 0 }
                        (Format-AnsiNumber -Number $share -Format $ValueFormat) + '%'
                    } else {
                        Format-AnsiNumber -Number $item.Value -Format $ValueFormat
                    }
                    if ($labelRuns.Count -gt 0) { $null = $runs.Add((New-AnsiRun -Text ' ' -Fg $null)) }
                    $null = $runs.Add((New-AnsiRun -Text $text -Fg $valueFg))
                }
                $null = $tags.Add($runs.ToArray())
            }

            foreach ($row in (Join-AnsiBreakdownTag -Tags $tags.ToArray() -Cells $chartWidth -FullSize:$FullSize)) {
                $null = $rows.Add($row)
            }
        }

        $measured = 0
        foreach ($row in $rows) {
            $rowWidth = Measure-AnsiRow -Runs @($row)
            if ($rowWidth -gt $measured) { $measured = $rowWidth }
        }

        return (New-AnsiRendering -Kind 'BreakdownChart' -Rows $rows.ToArray() -Width $measured `
                -Column $anchor.Column -NoColor $noColor)
    }
}

# Cells per part. Largest remainder, so the parts add up to the bar exactly rather
# than drifting a cell or two out; every part with a value keeps at least one cell,
# taken from the largest part that can spare it.
function Split-AnsiBreakdownCell {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Items,
        [Parameter(Mandatory)][int]$Cells
    )
    $count = $Items.Count
    $shares = New-Object int[] $count
    if ($count -eq 0 -or $Cells -le 0) { return , $shares }

    $total = 0
    foreach ($item in $Items) { $total += [Math]::Max(0, $item.Value) }
    if ($total -le 0) { return , $shares }

    $exact = New-Object double[] $count
    $assigned = 0
    for ($i = 0; $i -lt $count; $i++) {
        $exact[$i] = ([Math]::Max(0, $Items[$i].Value) / $total) * $Cells
        $shares[$i] = [int][Math]::Floor($exact[$i])
        $assigned += $shares[$i]
    }

    # The cells the floors left over go to the largest fractions first.
    $order = 0..($count - 1) | Sort-Object -Property @{ Expression = { $exact[$_] - [Math]::Floor($exact[$_]) } } -Descending
    $index = 0
    while ($assigned -lt $Cells -and $index -lt $count) {
        $shares[$order[$index]]++
        $assigned++
        $index++
    }

    # A part with a value is never invisible: borrow a cell from the widest part.
    for ($i = 0; $i -lt $count; $i++) {
        if ($shares[$i] -gt 0 -or $Items[$i].Value -le 0) { continue }
        $widest = -1
        for ($c = 0; $c -lt $count; $c++) {
            if ($shares[$c] -lt 2) { continue }
            if ($widest -lt 0 -or $shares[$c] -gt $shares[$widest]) { $widest = $c }
        }
        if ($widest -lt 0) { break }
        $shares[$widest]--
        $shares[$i]++
    }

    return , $shares
}

# The legend: one tag per row with -FullSize, otherwise as many as fit on a row,
# three spaces apart. A tag wider than the row gets a row of its own.
function Join-AnsiBreakdownTag {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Tags,
        [Parameter(Mandatory)][int]$Cells,
        [switch]$FullSize
    )
    $rows = [System.Collections.Generic.List[object]]::new()
    if ($Tags.Count -eq 0) { return , $rows.ToArray() }

    if ($FullSize) {
        foreach ($tag in $Tags) { $null = $rows.Add(@($tag)) }
        return , $rows.ToArray()
    }

    $gap = 3
    $current = [System.Collections.Generic.List[object]]::new()
    $used = 0
    foreach ($tag in $Tags) {
        $tagWidth = Measure-AnsiRow -Runs @($tag)
        $needed = $(if ($used -gt 0) { $gap } else { 0 }) + $tagWidth
        if ($used -gt 0 -and ($used + $needed) -gt $Cells) {
            $null = $rows.Add($current.ToArray())
            $current = [System.Collections.Generic.List[object]]::new()
            $used = 0
            $needed = $tagWidth
        }
        if ($used -gt 0) {
            $null = $current.Add((New-AnsiRun -Text (' ' * $gap) -Fg $null))
        }
        foreach ($run in @($tag)) { $null = $current.Add($run) }
        $used += $needed
    }
    if ($current.Count -gt 0) { $null = $rows.Add($current.ToArray()) }
    return , $rows.ToArray()
}

Export-ModuleMember -Function Format-AnsiBreakdownChart
