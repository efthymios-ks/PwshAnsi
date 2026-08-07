#Requires -Version 7.2

# Format-AnsiTable.psm1
# Public: Format-AnsiTable — builds an [Ansi.Rendering].
# Paint it with Out-AnsiHost, or turn it into strings with Out-AnsiString.

Import-Module (Join-Path $PSScriptRoot 'Ansi.Core.psm1') -Force -DisableNameChecking

# Glyphs per border style. Verticals empty => columns are space-separated.
$script:AnsiTableBorderMap = @{
    'none'       = @{
        TL = ''; TM = ''; TR = ''
        ML = ''; MX = ''; MR = ''
        BL = ''; BM = ''; BR = ''
        H  = ''; V = ''
        Rules = $false
    }
    'horizontal' = @{
        TL = ''; TM = ''; TR = ''
        ML = ''; MX = ''; MR = ''
        BL = ''; BM = ''; BR = ''
        H  = [string][char]0x2500; V = ''
        Rules = $true
    }
    'ascii'      = @{
        TL = '+'; TM = '+'; TR = '+'
        ML = '+'; MX = '+'; MR = '+'
        BL = '+'; BM = '+'; BR = '+'
        H  = '-'; V = '|'
        Rules = $true
    }
    'square'     = @{
        TL = [string][char]0x250C; TM = [string][char]0x252C; TR = [string][char]0x2510
        ML = [string][char]0x251C; MX = [string][char]0x253C; MR = [string][char]0x2524
        BL = [string][char]0x2514; BM = [string][char]0x2534; BR = [string][char]0x2518
        H  = [string][char]0x2500; V = [string][char]0x2502
        Rules = $true
    }
    'rounded'    = @{
        TL = [string][char]0x256D; TM = [string][char]0x252C; TR = [string][char]0x256E
        ML = [string][char]0x251C; MX = [string][char]0x253C; MR = [string][char]0x2524
        BL = [string][char]0x2570; BM = [string][char]0x2534; BR = [string][char]0x256F
        H  = [string][char]0x2500; V = [string][char]0x2502
        Rules = $true
    }
    'heavy'      = @{
        TL = [string][char]0x250F; TM = [string][char]0x2533; TR = [string][char]0x2513
        ML = [string][char]0x2523; MX = [string][char]0x254B; MR = [string][char]0x252B
        BL = [string][char]0x2517; BM = [string][char]0x253B; BR = [string][char]0x251B
        H  = [string][char]0x2501; V = [string][char]0x2503
        Rules = $true
    }
    'double'     = @{
        TL = [string][char]0x2554; TM = [string][char]0x2566; TR = [string][char]0x2557
        ML = [string][char]0x2560; MX = [string][char]0x256C; MR = [string][char]0x2563
        BL = [string][char]0x255A; BM = [string][char]0x2569; BR = [string][char]0x255D
        H  = [string][char]0x2550; V = [string][char]0x2551
        Rules = $true
    }
}

function Format-AnsiTable {
    [CmdletBinding()]
    [OutputType('Ansi.Rendering')]
    param(
        [Parameter(Position = 0, ValueFromPipeline)]
        [AllowNull()]
        [object]$Data,

        [Parameter(Position = 1)]
        [object[]]$Property,

        [ValidateSet('None', 'Ascii', 'Square', 'Rounded', 'Heavy', 'Double', 'Horizontal')]
        [string]$Border = 'Rounded',

        [string]$BorderColor,

        [string]$HeaderColor,

        [string]$TextColor,

        [ValidateSet('Left', 'Center', 'Right')]
        [string[]]$Align,

        [Alias('MaxWidth')]
        [int]$Width = 0,

        [string]$Title,

        [string]$TitleColor,

        [switch]$HideHeaders,

        [switch]$ShowRowSeparators,

        [switch]$Wrap,

        [switch]$Expand,

        [switch]$Markdown,

        [switch]$Escape
    )
    begin {
        $items = [System.Collections.Generic.List[object]]::new()
    }
    process {
        if ($null -eq $Data) { return }
        if ($Data -is [string] -or $Data -is [System.Collections.IDictionary] -or
            -not ($Data -is [System.Collections.IEnumerable])) {
            $null = $items.Add($Data)
        } else {
            foreach ($item in $Data) { $null = $items.Add($item) }
        }
    }
    end {
        if ($items.Count -eq 0) { return }

        $anchor = Get-AnsiAnchor -MaxWidth $Width
        $noColor = Test-AnsiNoColor
        $available = [Math]::Max(1, $anchor.Width)

        # Not $Border: assigning to it would re-validate the ValidateSet.
        $borderChars = $script:AnsiTableBorderMap[$Border.ToLowerInvariant()]

        $borderFg = if ($BorderColor) { Get-AnsiColorName -Name $BorderColor } else { $null }
        $headerFg = if ($HeaderColor) { Get-AnsiColorName -Name $HeaderColor } else { $null }
        $textFg = if ($TextColor) { Get-AnsiColorName -Name $TextColor } else { $null }
        $titleFg = if ($TitleColor) { Get-AnsiColorName -Name $TitleColor } else { $null }

        $columns = Resolve-AnsiTableColumns -Items $items -Property $Property
        if ($columns.Count -eq 0) { return }

        $parse = @{ Markdown = [bool]$Markdown; Escape = [bool]$Escape }

        # Header and body cells become run arrays up front so widths can be
        # measured on visible text rather than on markup.
        $headerCells = @()
        foreach ($column in $columns) {
            $headerCells += (ConvertTo-AnsiTableCell -Value $column.Name -Fg $headerFg -Parse $parse)
        }

        $bodyCells = [System.Collections.Generic.List[object]]::new()
        foreach ($item in $items) {
            $row = @()
            foreach ($column in $columns) {
                $value = Get-AnsiTableValue -Item $item -Column $column
                $row += (ConvertTo-AnsiTableCell -Value $value -Fg $textFg -Parse $parse)
            }
            $null = $bodyCells.Add($row)
        }

        $widths = Get-AnsiTableWidths -Columns $columns -HeaderCells $headerCells -BodyCells $bodyCells `
            -Available $available -Border $borderChars -HideHeaders:$HideHeaders -Expand:$Expand

        $alignments = @()
        for ($c = 0; $c -lt $columns.Count; $c++) {
            $alignments += $(if ($Align -and $c -lt $Align.Count) { $Align[$c] } elseif ($Align) { $Align[-1] } else { 'Left' })
        }

        $lines = [System.Collections.Generic.List[object]]::new()
        $tableWidth = Get-AnsiTableTotalWidth -Widths $widths -Border $borderChars

        if ($Title) {
            $titleCell = ConvertTo-AnsiTableCell -Value $Title -Fg $titleFg -Parse $parse
            $titleRuns = @($titleCell.Runs)
            $titleLines = Split-AnsiRuns -Runs $titleRuns -Width $tableWidth -Overflow Ellipsis
            foreach ($titleLine in $titleLines) {
                # Parentheses, not @(): New-AnsiTableCentered returns the run array
                # comma-wrapped, so @() would nest it and Format-AnsiLine would then
                # read Text/Link off an array.
                $null = $lines.Add((New-AnsiTableCentered -Runs @($titleLine) -Width $tableWidth))
            }
        }

        if ($borderChars.Rules -and $borderChars.V) {
            $null = $lines.Add((New-AnsiTableRule -Widths $widths -Border $borderChars -Position Top -Fg $borderFg))
        } elseif ($borderChars.Rules) {
            $null = $lines.Add((New-AnsiTableFlatRule -Width $tableWidth -Border $borderChars -Fg $borderFg))
        }

        if (-not $HideHeaders) {
            foreach ($row in (Get-AnsiTableRowLines -Cells $headerCells -Widths $widths -Alignments $alignments `
                        -Border $borderChars -BorderFg $borderFg -Wrap:$Wrap)) {
                $null = $lines.Add($row)
            }
            if ($borderChars.Rules -and $borderChars.V) {
                $null = $lines.Add((New-AnsiTableRule -Widths $widths -Border $borderChars -Position Middle -Fg $borderFg))
            } elseif ($borderChars.Rules) {
                $null = $lines.Add((New-AnsiTableFlatRule -Width $tableWidth -Border $borderChars -Fg $borderFg))
            }
        }

        for ($r = 0; $r -lt $bodyCells.Count; $r++) {
            foreach ($row in (Get-AnsiTableRowLines -Cells $bodyCells[$r] -Widths $widths -Alignments $alignments `
                        -Border $borderChars -BorderFg $borderFg -Wrap:$Wrap)) {
                $null = $lines.Add($row)
            }
            if ($ShowRowSeparators -and $r -lt $bodyCells.Count - 1) {
                if ($borderChars.Rules -and $borderChars.V) {
                    $null = $lines.Add((New-AnsiTableRule -Widths $widths -Border $borderChars -Position Middle -Fg $borderFg))
                } elseif ($borderChars.Rules) {
                    $null = $lines.Add((New-AnsiTableFlatRule -Width $tableWidth -Border $borderChars -Fg $borderFg))
                }
            }
        }

        if ($borderChars.Rules -and $borderChars.V) {
            $null = $lines.Add((New-AnsiTableRule -Widths $widths -Border $borderChars -Position Bottom -Fg $borderFg))
        } elseif ($borderChars.Rules) {
            $null = $lines.Add((New-AnsiTableFlatRule -Width $tableWidth -Border $borderChars -Fg $borderFg))
        }

        return (New-AnsiRendering -Kind 'Table' -Rows $lines.ToArray() -Width $tableWidth `
                -Column $anchor.Column -NoColor $noColor)
    }
}

function New-AnsiTableRun {
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
function ConvertTo-AnsiTableCell {
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
        $runs = @(New-AnsiTableRun -Text '' -Fg $Fg)
    } elseif ($Parse.Escape) {
        $runs = @(New-AnsiTableRun -Text $text -Fg $Fg)
    } else {
        $runs = ConvertFrom-AnsiMarkup -Text $text -AsMarkdown:$Parse.Markdown
        foreach ($r in $runs) { if (-not $r.Fg) { $r.Fg = $Fg } }
    }
    return [PSCustomObject]@{ Rows = $null; Runs = @($runs); Width = (Measure-AnsiTableRuns -Runs @($runs)) }
}

# Column definitions from -Property, or every property of the first item.
function Resolve-AnsiTableColumns {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][System.Collections.Generic.List[object]]$Items,
        [AllowNull()][object[]]$Property
    )
    $columns = [System.Collections.Generic.List[object]]::new()

    if ($Property) {
        foreach ($p in $Property) {
            if ($p -is [System.Collections.IDictionary]) {
                $name = $null
                foreach ($key in @('Name', 'Label', 'N', 'L')) {
                    if ($p.Contains($key)) { $name = [string]$p[$key]; break }
                }
                $expression = $null
                foreach ($key in @('Expression', 'E')) {
                    if ($p.Contains($key)) { $expression = $p[$key]; break }
                }
                if (-not $name -and $expression -isnot [scriptblock]) { $name = [string]$expression }
                $null = $columns.Add([PSCustomObject]@{ Name = $name; Expression = $expression })
            } else {
                $null = $columns.Add([PSCustomObject]@{ Name = [string]$p; Expression = [string]$p })
            }
        }
        return , $columns.ToArray()
    }

    $first = $Items[0]
    if ($first -is [System.Collections.IDictionary]) {
        foreach ($key in $first.Keys) {
            $null = $columns.Add([PSCustomObject]@{ Name = [string]$key; Expression = [string]$key })
        }
    } elseif ($first -is [string] -or $first -is [System.ValueType]) {
        $null = $columns.Add([PSCustomObject]@{ Name = 'Value'; Expression = $null })
    } else {
        foreach ($prop in $first.PSObject.Properties) {
            $null = $columns.Add([PSCustomObject]@{ Name = $prop.Name; Expression = $prop.Name })
        }
    }
    return , $columns.ToArray()
}

# The raw value, not a string: a calculated column may return an [Ansi.Rendering].
function Get-AnsiTableValue {
    [CmdletBinding()]
    param(
        [AllowNull()][object]$Item,
        [Parameter(Mandatory)][object]$Column
    )
    if ($null -eq $Item) { return '' }

    $expression = $Column.Expression
    if ($null -eq $expression) { return $Item }

    if ($expression -is [scriptblock]) {
        return ($Item | ForEach-Object $expression)
    }
    if ($Item -is [System.Collections.IDictionary]) {
        if ($Item.Contains($expression)) { return $Item[$expression] }
        return ''
    }
    $member = $Item.PSObject.Properties[[string]$expression]
    if ($null -eq $member) { return '' }
    return $member.Value
}

function Measure-AnsiTableRuns {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Runs)
    # Hard breaks split a cell, so the natural width is the widest segment.
    $widest = 0
    $current = 0
    foreach ($run in $Runs) {
        foreach ($segment in $run.Text.Split([char]10)) {
            $current += $segment.Length
            if ($current -gt $widest) { $widest = $current }
            $current = 0
        }
    }
    return $widest
}

function Get-AnsiTableOverhead {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][int]$ColumnCount,
        [Parameter(Mandatory)][hashtable]$Border
    )
    if ($Border.V) {
        # │ cell │ cell │  => one vertical per column plus a closing one, and a
        # space of padding on each side of every cell.
        return ($ColumnCount + 1) + (2 * $ColumnCount)
    }
    # Borderless columns are separated by two spaces.
    return 2 * [Math]::Max(0, $ColumnCount - 1)
}

function Get-AnsiTableTotalWidth {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][int[]]$Widths,
        [Parameter(Mandatory)][hashtable]$Border
    )
    $sum = 0
    foreach ($w in $Widths) { $sum += $w }
    return $sum + (Get-AnsiTableOverhead -ColumnCount $Widths.Count -Border $Border)
}

# Natural widths, shrunk widest-first until the table fits, or grown to fill it
# when -Expand is set.
function Get-AnsiTableWidths {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object[]]$Columns,
        [Parameter(Mandatory)][object[]]$HeaderCells,
        [Parameter(Mandatory)][AllowEmptyCollection()][System.Collections.Generic.List[object]]$BodyCells,
        [Parameter(Mandatory)][int]$Available,
        [Parameter(Mandatory)][hashtable]$Border,
        [switch]$HideHeaders,
        [switch]$Expand
    )
    $count = $Columns.Count
    $widths = New-Object int[] $count

    for ($c = 0; $c -lt $count; $c++) {
        $natural = 0
        if (-not $HideHeaders) { $natural = [int]$HeaderCells[$c].Width }
        foreach ($row in $BodyCells) {
            $cellWidth = [int]$row[$c].Width
            if ($cellWidth -gt $natural) { $natural = $cellWidth }
        }
        $widths[$c] = [Math]::Max(1, $natural)
    }

    $overhead = Get-AnsiTableOverhead -ColumnCount $count -Border $Border
    $target = [Math]::Max($count, $Available - $overhead)

    $total = 0
    foreach ($w in $widths) { $total += $w }

    while ($total -gt $target) {
        # Trim the widest column; ties go to the leftmost.
        $widestIndex = 0
        for ($c = 1; $c -lt $count; $c++) {
            if ($widths[$c] -gt $widths[$widestIndex]) { $widestIndex = $c }
        }
        if ($widths[$widestIndex] -le 1) { break }
        $widths[$widestIndex]--
        $total--
    }

    if ($Expand -and $total -lt $target) {
        $slack = $target - $total
        $per = [int][Math]::Floor($slack / $count)
        for ($c = 0; $c -lt $count; $c++) { $widths[$c] += $per }
        $remainder = $slack - ($per * $count)
        for ($c = 0; $c -lt $remainder; $c++) { $widths[$c]++ }
    }

    return , $widths
}

# One cell becomes one or more lines of runs: a string folds or ellipsises to the
# width, a nested rendering keeps its rows (each cropped if the column shrank).
function Get-AnsiTableCellLines {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Cell,
        [Parameter(Mandatory)][int]$Width,
        [switch]$Wrap
    )
    if ($null -ne $Cell.Rows) {
        $lines = [System.Collections.Generic.List[object]]::new()
        foreach ($row in $Cell.Rows) {
            $rowRuns = @($row)
            if ((Measure-AnsiRow -Runs $rowRuns) -gt $Width) {
                $cropped = Split-AnsiRuns -Runs $rowRuns -Width $Width -Overflow Ellipsis
                $rowRuns = @($cropped[0])
            }
            $null = $lines.Add($rowRuns)
        }
        return , $lines.ToArray()
    }

    $overflow = if ($Wrap) { 'Fold' } else { 'Ellipsis' }
    $lines = Split-AnsiRuns -Runs @($Cell.Runs) -Width $Width -Overflow $overflow
    return , $lines
}

function Get-AnsiTableRowLines {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object[]]$Cells,
        [Parameter(Mandatory)][int[]]$Widths,
        [Parameter(Mandatory)][string[]]$Alignments,
        [Parameter(Mandatory)][hashtable]$Border,
        [AllowNull()][string]$BorderFg,
        [switch]$Wrap
    )
    $columnLines = @()
    $height = 1
    for ($c = 0; $c -lt $Cells.Count; $c++) {
        $cellLines = Get-AnsiTableCellLines -Cell $Cells[$c] -Width $Widths[$c] -Wrap:$Wrap
        $columnLines += , $cellLines
        if ($cellLines.Count -gt $height) { $height = $cellLines.Count }
    }

    $rows = [System.Collections.Generic.List[object]]::new()
    for ($line = 0; $line -lt $height; $line++) {
        $row = [System.Collections.Generic.List[object]]::new()
        if ($Border.V) { $null = $row.Add((New-AnsiTableRun -Text $Border.V -Fg $BorderFg)) }

        for ($c = 0; $c -lt $Cells.Count; $c++) {
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

            if ($Border.V) { $null = $row.Add((New-AnsiTableRun -Text ' ' -Fg $null)) }
            elseif ($c -gt 0) { $null = $row.Add((New-AnsiTableRun -Text '  ' -Fg $null)) }

            if ($leftPad -gt 0) { $null = $row.Add((New-AnsiTableRun -Text (' ' * $leftPad) -Fg $null)) }
            foreach ($r in $cellRuns) { $null = $row.Add($r) }
            if ($rightPad -gt 0) { $null = $row.Add((New-AnsiTableRun -Text (' ' * $rightPad) -Fg $null)) }

            if ($Border.V) {
                $null = $row.Add((New-AnsiTableRun -Text ' ' -Fg $null))
                $null = $row.Add((New-AnsiTableRun -Text $Border.V -Fg $BorderFg))
            }
        }
        $null = $rows.Add($row.ToArray())
    }
    return , $rows.ToArray()
}

function New-AnsiTableRule {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][int[]]$Widths,
        [Parameter(Mandatory)][hashtable]$Border,
        [Parameter(Mandatory)][ValidateSet('Top', 'Middle', 'Bottom')][string]$Position,
        [AllowNull()][string]$BorderFg,
        [AllowNull()][string]$Fg
    )
    $colour = if ($Fg) { $Fg } else { $BorderFg }
    $left, $mid, $right = switch ($Position) {
        'Top' { $Border.TL, $Border.TM, $Border.TR }
        'Bottom' { $Border.BL, $Border.BM, $Border.BR }
        default { $Border.ML, $Border.MX, $Border.MR }
    }

    $text = $left
    for ($c = 0; $c -lt $Widths.Count; $c++) {
        $text += $Border.H * ($Widths[$c] + 2)
        $text += $(if ($c -lt $Widths.Count - 1) { $mid } else { $right })
    }
    return , @(New-AnsiTableRun -Text $text -Fg $colour)
}

function New-AnsiTableFlatRule {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][int]$Width,
        [Parameter(Mandatory)][hashtable]$Border,
        [AllowNull()][string]$Fg
    )
    return , @(New-AnsiTableRun -Text ($Border.H * $Width) -Fg $Fg)
}

function New-AnsiTableCentered {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Runs,
        [Parameter(Mandatory)][int]$Width
    )
    $visible = 0
    foreach ($r in $Runs) { $visible += $r.Text.Length }
    $leftPad = [int][Math]::Floor([Math]::Max(0, $Width - $visible) / 2)

    $row = [System.Collections.Generic.List[object]]::new()
    if ($leftPad -gt 0) { $null = $row.Add((New-AnsiTableRun -Text (' ' * $leftPad) -Fg $null)) }
    foreach ($r in $Runs) { $null = $row.Add($r) }
    return , $row.ToArray()
}

Export-ModuleMember -Function Format-AnsiTable
