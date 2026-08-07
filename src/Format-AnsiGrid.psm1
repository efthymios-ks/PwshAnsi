#Requires -Version 7.2

# Format-AnsiGrid.psm1
# Public: Format-AnsiGrid — builds an [Ansi.Rendering].
# Paint it with Out-AnsiHost, or turn it into strings with Out-AnsiString.

Import-Module (Join-Path $PSScriptRoot 'Ansi.Core.psm1') -Force -DisableNameChecking

function Format-AnsiGrid {
    [CmdletBinding(DefaultParameterSetName = 'Rows')]
    [OutputType('Ansi.Rendering')]
    param(
        [Parameter(ParameterSetName = 'Rows', Position = 0, Mandatory, ValueFromPipeline)]
        [AllowNull()]
        [object[]]$Rows,

        [Parameter(ParameterSetName = 'Items', Mandatory, ValueFromPipeline)]
        [AllowNull()]
        [object[]]$Items,

        [Parameter(ParameterSetName = 'Items')]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$ColumnCount = 0,

        [int[]]$ColumnWidth,

        [ValidateSet('Left', 'Center', 'Right')]
        [string[]]$Align,

        [ValidateRange(0, [int]::MaxValue)]
        [int]$Padding = 2,

        [Alias('Color')]
        [string]$TextColor,

        [switch]$Wrap,

        [switch]$Expand,

        [Alias('Width')]
        [int]$MaxWidth = 0,

        [switch]$Markdown,

        [switch]$Escape
    )
    begin {
        $collected = [System.Collections.Generic.List[object]]::new()
    }
    process {
        # Plain assignments, and never $input (an automatic variable): an `if`
        # expression would emit through the pipeline and flatten a row of cells
        # into separate rows.
        if ($PSCmdlet.ParameterSetName -eq 'Items') {
            if ($null -eq $Items) { return }
            foreach ($item in $Items) { $null = $collected.Add($item) }
            return
        }

        if ($null -eq $Rows) { return }
        if ($PSCmdlet.MyInvocation.ExpectingInput) {
            # Piped: the pipeline already unrolled the outer array, so this
            # invocation's $Rows *is* one row of cells.
            $null = $collected.Add($Rows)
        } else {
            foreach ($row in $Rows) { $null = $collected.Add($row) }
        }
    }
    end {
        if ($collected.Count -eq 0) { return }

        $anchor = Get-AnsiAnchor -MaxWidth $MaxWidth
        $noColor = Test-AnsiNoColor
        $available = [Math]::Max(1, $anchor.Width)

        $textFg = if ($TextColor) { Get-AnsiColorName -Name $TextColor } else { $null }
        $parse = @{ Markdown = [bool]$Markdown; Escape = [bool]$Escape }
        $gap = [Math]::Max(0, $Padding)

        # Each cell becomes runs up front so widths are measured on visible text.
        if ($PSCmdlet.ParameterSetName -eq 'Items') {
            $cellRows = Split-AnsiGridItems -Items $collected -ColumnCount $ColumnCount `
                -Available $available -Padding $gap -Fg $textFg -Parse $parse
        } else {
            $cellRows = [System.Collections.Generic.List[object]]::new()
            foreach ($row in $collected) {
                $cells = @()
                foreach ($cell in (ConvertTo-AnsiGridRow -Row $row)) {
                    $cells += (ConvertTo-AnsiGridCell -Value $cell -Fg $textFg -Parse $parse)
                }
                $null = $cellRows.Add($cells)
            }
        }
        if ($cellRows.Count -eq 0) { return }

        $columnCountActual = 0
        foreach ($row in $cellRows) { if ($row.Count -gt $columnCountActual) { $columnCountActual = $row.Count } }

        $widths = Get-AnsiGridWidths -CellRows $cellRows -ColumnCount $columnCountActual `
            -ColumnWidth $ColumnWidth -Available $available -Padding $gap -Expand:$Expand

        $alignments = @()
        for ($c = 0; $c -lt $columnCountActual; $c++) {
            $alignments += $(if ($Align -and $c -lt $Align.Count) { $Align[$c] } elseif ($Align) { $Align[-1] } else { 'Left' })
        }

        $lines = [System.Collections.Generic.List[object]]::new()
        foreach ($row in $cellRows) {
            foreach ($line in (Get-AnsiGridRowLines -Cells $row -Widths $widths -Alignments $alignments `
                        -Padding $gap -Wrap:$Wrap)) {
                $null = $lines.Add($line)
            }
        }

        $totalWidth = 0
        foreach ($w in $widths) { $totalWidth += $w }
        $totalWidth += $gap * [Math]::Max(0, $columnCountActual - 1)

        return (New-AnsiRendering -Kind 'Grid' -Rows $lines.ToArray() -Width $totalWidth `
                -Column $anchor.Column -NoColor $noColor)
    }
}

function New-AnsiGridRun {
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

# A cell is either parsed runs (a string, to be wrapped) or a fixed block of rows
# (a nested [Ansi.Rendering], used as-is).
function ConvertTo-AnsiGridCell {
    [CmdletBinding()]
    param(
        [AllowNull()][object]$Value,
        [AllowNull()][string]$Fg,
        [Parameter(Mandatory)][hashtable]$Parse
    )
    $block = Get-AnsiRenderingBlock -Value $Value
    if ($null -ne $block) {
        return [PSCustomObject]@{ Rows = $block.Rows; Runs = $null; Width = $block.Width }
    }

    $text = if ($null -eq $Value) { '' } else { [string]$Value }
    $runs = $null
    if ([string]::IsNullOrEmpty($text)) {
        $runs = @(New-AnsiGridRun -Text '' -Fg $Fg)
    } elseif ($Parse.Escape) {
        $runs = @(New-AnsiGridRun -Text $text -Fg $Fg)
    } else {
        $runs = ConvertFrom-AnsiMarkup -Text $text -AsMarkdown:$Parse.Markdown
        foreach ($r in $runs) { if (-not $r.Fg) { $r.Fg = $Fg } }
    }
    return [PSCustomObject]@{ Rows = $null; Runs = @($runs); Width = (Measure-AnsiGridRuns -Runs @($runs)) }
}

# A row may be an array of cells, or a single value meaning a one-cell row.
function ConvertTo-AnsiGridRow {
    [CmdletBinding()]
    param([AllowNull()][object]$Row)

    if ($null -eq $Row) { return , @('') }
    # A rendering is one cell, never a collection of cells.
    if (Test-AnsiRendering -Value $Row) { return , @($Row) }
    if ($Row -is [string] -or $Row -is [System.Collections.IDictionary] -or
        -not ($Row -is [System.Collections.IEnumerable])) {
        return , @($Row)
    }
    $cells = @()
    foreach ($cell in $Row) { $cells += $cell }
    if ($cells.Count -eq 0) { $cells = @('') }
    return , $cells
}

# Chunk a flat list into grid rows: -ColumnCount if given, otherwise as many
# columns of the widest item as the available width allows.
function Split-AnsiGridItems {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][System.Collections.Generic.List[object]]$Items,
        [Parameter(Mandatory)][int]$ColumnCount,
        [Parameter(Mandatory)][int]$Available,
        [Parameter(Mandatory)][int]$Padding,
        [AllowNull()][string]$Fg,
        [Parameter(Mandatory)][hashtable]$Parse
    )
    $cells = @()
    $widest = 1
    foreach ($item in $Items) {
        $cell = ConvertTo-AnsiGridCell -Value $item -Fg $Fg -Parse $Parse
        $cells += $cell
        if ($cell.Width -gt $widest) { $widest = [int]$cell.Width }
    }

    $columns = $ColumnCount
    if ($columns -le 0) {
        $columns = [int][Math]::Floor(($Available + $Padding) / ($widest + $Padding))
        if ($columns -lt 1) { $columns = 1 }
        if ($columns -gt $cells.Count) { $columns = $cells.Count }
    }

    $rows = [System.Collections.Generic.List[object]]::new()
    for ($i = 0; $i -lt $cells.Count; $i += $columns) {
        $row = @()
        for ($c = 0; $c -lt $columns -and ($i + $c) -lt $cells.Count; $c++) {
            $row += , $cells[$i + $c]
        }
        $null = $rows.Add($row)
    }
    # Comma-wrapped: returning the list bare would let the pipeline enumerate it
    # and hand the caller a single row instead of the list of rows.
    return , $rows
}

function Measure-AnsiGridRuns {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Runs)
    # Hard breaks split a cell, so the natural width is the widest segment.
    $widest = 0
    $current = 0
    foreach ($run in $Runs) {
        $segments = $run.Text.Split([char]10)
        for ($s = 0; $s -lt $segments.Count; $s++) {
            $current += $segments[$s].Length
            if ($current -gt $widest) { $widest = $current }
            if ($s -lt $segments.Count - 1) { $current = 0 }
        }
    }
    return $widest
}

function Get-AnsiGridWidths {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][System.Collections.Generic.List[object]]$CellRows,
        [Parameter(Mandatory)][int]$ColumnCount,
        [AllowNull()][int[]]$ColumnWidth,
        [Parameter(Mandatory)][int]$Available,
        [Parameter(Mandatory)][int]$Padding,
        [switch]$Expand
    )
    $widths = New-Object int[] $ColumnCount

    for ($c = 0; $c -lt $ColumnCount; $c++) {
        # A given width of 0 (or none) means size to content.
        $fixed = 0
        if ($ColumnWidth -and $c -lt $ColumnWidth.Count) { $fixed = $ColumnWidth[$c] }
        if ($fixed -gt 0) { $widths[$c] = $fixed; continue }

        $natural = 1
        foreach ($row in $CellRows) {
            if ($c -ge $row.Count) { continue }
            $width = [int]$row[$c].Width
            if ($width -gt $natural) { $natural = $width }
        }
        $widths[$c] = $natural
    }

    $overhead = $Padding * [Math]::Max(0, $ColumnCount - 1)
    $target = [Math]::Max($ColumnCount, $Available - $overhead)

    $total = 0
    foreach ($w in $widths) { $total += $w }

    while ($total -gt $target) {
        # Trim the widest column; ties go to the leftmost.
        $widestIndex = 0
        for ($c = 1; $c -lt $ColumnCount; $c++) {
            if ($widths[$c] -gt $widths[$widestIndex]) { $widestIndex = $c }
        }
        if ($widths[$widestIndex] -le 1) { break }
        $widths[$widestIndex]--
        $total--
    }

    if ($Expand -and $total -lt $target) {
        $slack = $target - $total
        $per = [int][Math]::Floor($slack / $ColumnCount)
        for ($c = 0; $c -lt $ColumnCount; $c++) { $widths[$c] += $per }
        $remainder = $slack - ($per * $ColumnCount)
        for ($c = 0; $c -lt $remainder; $c++) { $widths[$c]++ }
    }

    return , $widths
}

function Get-AnsiGridRowLines {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Cells,
        [Parameter(Mandatory)][int[]]$Widths,
        [Parameter(Mandatory)][string[]]$Alignments,
        [Parameter(Mandatory)][int]$Padding,
        [switch]$Wrap
    )
    $overflow = if ($Wrap) { 'Fold' } else { 'Ellipsis' }

    $columnLines = @()
    $height = 1
    for ($c = 0; $c -lt $Widths.Count; $c++) {
        if ($c -lt $Cells.Count) {
            $cell = $Cells[$c]
            if ($null -ne $cell.Rows) {
                # A nested rendering keeps its rows, cropped if the column shrank.
                $rows = [System.Collections.Generic.List[object]]::new()
                foreach ($row in $cell.Rows) {
                    $rowRuns = @($row)
                    if ((Measure-AnsiRow -Runs $rowRuns) -gt $Widths[$c]) {
                        $cropped = Split-AnsiRuns -Runs $rowRuns -Width $Widths[$c] -Overflow Ellipsis
                        $rowRuns = @($cropped[0])
                    }
                    $null = $rows.Add($rowRuns)
                }
                $cellLines = $rows.ToArray()
            } else {
                $cellLines = Split-AnsiRuns -Runs @($cell.Runs) -Width $Widths[$c] -Overflow $overflow
            }
        } else {
            $cellLines = @(, @(New-AnsiGridRun -Text '' -Fg $null))
        }
        $columnLines += , $cellLines
        if ($cellLines.Count -gt $height) { $height = $cellLines.Count }
    }

    $rows = [System.Collections.Generic.List[object]]::new()
    for ($line = 0; $line -lt $height; $line++) {
        $row = [System.Collections.Generic.List[object]]::new()

        for ($c = 0; $c -lt $Widths.Count; $c++) {
            $cellRuns = @()
            if ($line -lt $columnLines[$c].Count) { $cellRuns = @($columnLines[$c][$line]) }

            $visible = 0
            foreach ($r in $cellRuns) { $visible += $r.Text.Length }
            $pad = [Math]::Max(0, $Widths[$c] - $visible)
            $leftPad = switch ($Alignments[$c]) {
                'Right' { $pad }
                'Center' { [int][Math]::Floor($pad / 2) }
                default { 0 }
            }
            $rightPad = $pad - $leftPad

            if ($c -gt 0 -and $Padding -gt 0) {
                $null = $row.Add((New-AnsiGridRun -Text (' ' * $Padding) -Fg $null))
            }
            if ($leftPad -gt 0) { $null = $row.Add((New-AnsiGridRun -Text (' ' * $leftPad) -Fg $null)) }
            foreach ($r in $cellRuns) { $null = $row.Add($r) }
            # The last column keeps no trailing padding: a grid has no right edge.
            if ($rightPad -gt 0 -and $c -lt $Widths.Count - 1) {
                $null = $row.Add((New-AnsiGridRun -Text (' ' * $rightPad) -Fg $null))
            }
        }
        # Drop trailing whitespace runs so short or ragged rows leave no tail.
        while ($row.Count -gt 0 -and [string]::IsNullOrWhiteSpace($row[$row.Count - 1].Text)) {
            $row.RemoveAt($row.Count - 1)
        }
        if ($row.Count -eq 0) { $null = $row.Add((New-AnsiGridRun -Text '' -Fg $null)) }
        $null = $rows.Add($row.ToArray())
    }
    return , $rows.ToArray()
}

Export-ModuleMember -Function Format-AnsiGrid
