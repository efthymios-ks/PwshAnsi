#Requires -Version 7.2

# Format-AnsiTree.psm1
# Public: Format-AnsiTree — builds an [Ansi.Rendering].
# Paint it with Out-AnsiHost, or turn it into strings with Out-AnsiString.

Import-Module (Join-Path $PSScriptRoot 'Ansi.Core.psm1') -Force -DisableNameChecking

# Tee / Last connect a node to its parent; Bar / Gap continue past it.
$script:AnsiTreeGuideMap = @{
    'line'       = @{
        Tee  = [string][char]0x251C + [string][char]0x2500 + [string][char]0x2500 + ' '   # ├──
        Last = [string][char]0x2514 + [string][char]0x2500 + [string][char]0x2500 + ' '   # └──
        Bar  = [string][char]0x2502 + '   '                                               # │
        Gap  = '    '
    }
    'doubleline' = @{
        Tee  = [string][char]0x2560 + [string][char]0x2550 + [string][char]0x2550 + ' '   # ╠══
        Last = [string][char]0x255A + [string][char]0x2550 + [string][char]0x2550 + ' '   # ╚══
        Bar  = [string][char]0x2551 + '   '                                               # ║
        Gap  = '    '
    }
    'boldline'   = @{
        Tee  = [string][char]0x2523 + [string][char]0x2501 + [string][char]0x2501 + ' '   # ┣━━
        Last = [string][char]0x2517 + [string][char]0x2501 + [string][char]0x2501 + ' '   # ┗━━
        Bar  = [string][char]0x2503 + '   '                                               # ┃
        Gap  = '    '
    }
    'ascii'      = @{
        Tee  = '|-- '
        Last = '`-- '
        Bar  = '|   '
        Gap  = '    '
    }
}

function Format-AnsiTree {
    [CmdletBinding()]
    [OutputType('Ansi.Rendering')]
    param(
        [Parameter(Position = 0, ValueFromPipeline)]
        [AllowNull()]
        [object]$Data,

        [ValidateSet('Line', 'DoubleLine', 'BoldLine', 'Ascii')]
        [string]$Guide = 'Line',

        [Alias('GuideColor')]
        [string]$Color,

        [string]$LabelColor,

        [ValidateRange(0, [int]::MaxValue)]
        [int]$MaxDepth = 0,

        [string]$Property,

        [string]$ChildProperty,

        [int]$MaxWidth = 0,

        [switch]$Markdown,

        [switch]$Escape
    )
    begin {
        $roots = [System.Collections.Generic.List[object]]::new()
    }
    process {
        if ($null -ne $Data) { $null = $roots.Add($Data) }
    }
    end {
        if ($roots.Count -eq 0) { return }

        $anchor = Get-AnsiAnchor -MaxWidth $MaxWidth
        $noColor = Test-AnsiNoColor
        $width = [Math]::Max(1, $anchor.Width)

        # Not $guide: PowerShell variable names are case-insensitive, so assigning
        # to it would re-validate the -Guide ValidateSet against a hashtable.
        $guideChars = $script:AnsiTreeGuideMap[$Guide.ToLowerInvariant()]
        $guideFg = if ($Color) { Get-AnsiColorName -Name $Color } else { $null }
        $labelFg = if ($LabelColor) { Get-AnsiColorName -Name $LabelColor } else { $null }

        $options = @{
            Guide         = $guideChars
            GuideFg       = $guideFg
            LabelFg       = $labelFg
            Width         = $width
            MaxDepth      = $MaxDepth
            Markdown      = [bool]$Markdown
            Escape        = [bool]$Escape
            Property      = $Property
            ChildProperty = $ChildProperty
        }

        # A single enumerable root renders as a forest, one tree per item.
        $items = [System.Collections.Generic.List[object]]::new()
        if ($roots.Count -eq 1 -and (Test-AnsiTreeForest -Value $roots[0] -Options $options)) {
            foreach ($item in $roots[0]) { $null = $items.Add($item) }
        } else {
            foreach ($item in $roots) { $null = $items.Add($item) }
        }

        $lines = [System.Collections.Generic.List[object]]::new()
        foreach ($item in $items) {
            $node = ConvertTo-AnsiTreeNode -Value $item -Options $options
            Add-AnsiTreeRows -Node $node -Prefix '' -Connector '' -Level 0 -Options $options -Lines $lines
        }

        return (New-AnsiRendering -Kind 'Tree' -Rows $lines.ToArray() -Width $width `
                -Column $anchor.Column -NoColor $noColor)
    }
}

function New-AnsiTreeRun {
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

# True when the value is a bare collection of nodes rather than a single node.
function Test-AnsiTreeForest {
    [CmdletBinding()]
    param([AllowNull()][object]$Value, [Parameter(Mandatory)][hashtable]$Options)

    if ($null -eq $Value -or $Value -is [string]) { return $false }
    if ($Value -is [System.Collections.IDictionary]) { return $false }
    if ($Value -is [System.Collections.IEnumerable]) { return $true }
    return $false
}

# Normalise anything into @{ Label; Children }. Hashtables and objects may name
# the label Value/Label/Name and the children Children/Items/Nodes, or the caller
# can point at their own properties with -Property / -ChildProperty.
function ConvertTo-AnsiTreeNode {
    [CmdletBinding()]
    param(
        [AllowNull()][object]$Value,
        [Parameter(Mandatory)][hashtable]$Options
    )
    $label = ''
    $rawChildren = $null

    if ($null -eq $Value) {
        return [PSCustomObject]@{ Label = ''; Children = @() }
    }

    # A rendering is a label in its own right: a whole block under one node.
    if (Test-AnsiRendering -Value $Value) {
        return [PSCustomObject]@{ Label = $Value; Children = @() }
    }

    if ($Value -is [System.Collections.IDictionary]) {
        $labelKey = Get-AnsiTreeKey -Keys $Value.Keys -Candidates @($Options.Property, 'Value', 'Label', 'Name', 'Text')
        $childKey = Get-AnsiTreeKey -Keys $Value.Keys -Candidates @($Options.ChildProperty, 'Children', 'Items', 'Nodes')
        if ($labelKey) {
            $raw = $Value[$labelKey]
            $label = if (Test-AnsiRendering -Value $raw) { $raw } else { [string]$raw }
        }
        if ($childKey) { $rawChildren = $Value[$childKey] }
    } elseif ($Value -is [string] -or $Value -is [System.ValueType]) {
        $label = [string]$Value
    } else {
        $names = @($Value.PSObject.Properties.Name)
        $labelKey = Get-AnsiTreeKey -Keys $names -Candidates @($Options.Property, 'Value', 'Label', 'Name', 'Text')
        $childKey = Get-AnsiTreeKey -Keys $names -Candidates @($Options.ChildProperty, 'Children', 'Items', 'Nodes')
        if ($labelKey) {
            $raw = $Value.$labelKey
            $label = if (Test-AnsiRendering -Value $raw) { $raw } else { [string]$raw }
        } else {
            $label = [string]$Value
        }
        if ($childKey) { $rawChildren = $Value.$childKey }
    }

    $children = [System.Collections.Generic.List[object]]::new()
    if ($null -ne $rawChildren) {
        if ((Test-AnsiRendering -Value $rawChildren) -or
            $rawChildren -is [string] -or $rawChildren -is [System.Collections.IDictionary] -or
            -not ($rawChildren -is [System.Collections.IEnumerable])) {
            $null = $children.Add((ConvertTo-AnsiTreeNode -Value $rawChildren -Options $Options))
        } else {
            foreach ($child in $rawChildren) {
                $null = $children.Add((ConvertTo-AnsiTreeNode -Value $child -Options $Options))
            }
        }
    }

    [PSCustomObject]@{ Label = $label; Children = $children.ToArray() }
}

function Get-AnsiTreeKey {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object]$Keys,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Candidates
    )
    $available = @($Keys | ForEach-Object { [string]$_ })
    foreach ($candidate in $Candidates) {
        if ([string]::IsNullOrEmpty($candidate)) { continue }
        $match = $available | Where-Object { $_ -eq $candidate } | Select-Object -First 1
        if ($match) { return $match }
    }
    return $null
}

# Emit one row per node, wrapping long labels under the label column.
function Add-AnsiTreeRows {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Node,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Prefix,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Connector,
        [Parameter(Mandatory)][int]$Level,
        [Parameter(Mandatory)][hashtable]$Options,
        [Parameter(Mandatory)][AllowEmptyCollection()][System.Collections.Generic.List[object]]$Lines
    )
    $guide = $Options.Guide
    $guideText = $Prefix + $Connector

    $available = [Math]::Max(1, $Options.Width - $guideText.Length)

    # A nested rendering is used row-for-row; a string label is parsed and wrapped.
    $block = Get-AnsiRenderingBlock -Value $Node.Label
    if ($null -ne $block) {
        $rows = [System.Collections.Generic.List[object]]::new()
        foreach ($row in $block.Rows) {
            $rowRuns = @($row)
            if ((Measure-AnsiRow -Runs $rowRuns) -gt $available) {
                $cropped = Split-AnsiRuns -Runs $rowRuns -Width $available -Overflow Ellipsis
                $rowRuns = @($cropped[0])
            }
            $null = $rows.Add($rowRuns)
        }
        $wrapped = $rows.ToArray()
    } else {
        # Labels are parsed as markup unless -Escape says otherwise.
        if ($Options.Escape) {
            $labelRuns = @(New-AnsiTreeRun -Text ([string]$Node.Label) -Fg $Options.LabelFg)
        } else {
            $labelRuns = ConvertFrom-AnsiMarkup -Text ([string]$Node.Label) -AsMarkdown:$Options.Markdown
            foreach ($r in $labelRuns) { if (-not $r.Fg) { $r.Fg = $Options.LabelFg } }
        }
        $wrapped = Split-AnsiRuns -Runs @($labelRuns) -Width $available -Overflow Fold
    }

    # Continuation rows keep the ancestors' guides and carry this node's own bar
    # while siblings remain, so a multi-row label does not break the branch. Either
    # way the text lines up under the label, not under the guide.
    $hang = $Prefix
    if ($Connector) {
        $hang += $(if ($Connector -eq $guide.Last) { $guide.Gap } else { $guide.Bar })
    }

    for ($i = 0; $i -lt $wrapped.Count; $i++) {
        $row = [System.Collections.Generic.List[object]]::new()
        if ($i -eq 0) {
            if ($guideText) { $null = $row.Add((New-AnsiTreeRun -Text $guideText -Fg $Options.GuideFg)) }
        } else {
            if ($hang) { $null = $row.Add((New-AnsiTreeRun -Text $hang -Fg $Options.GuideFg)) }
        }
        foreach ($r in @($wrapped[$i])) { $null = $row.Add($r) }
        $null = $Lines.Add($row.ToArray())
    }

    if ($Node.Children.Count -eq 0) { return }

    $childPrefix = if ($Connector) {
        $Prefix + $(if ($Connector -eq $guide.Last) { $guide.Gap } else { $guide.Bar })
    } else {
        $Prefix
    }

    # -MaxDepth counts levels below the root: deeper branches collapse to one `…`.
    if ($Options.MaxDepth -gt 0 -and ($Level + 1) -gt $Options.MaxDepth) {
        $row = @(
            (New-AnsiTreeRun -Text ($childPrefix + $guide.Last) -Fg $Options.GuideFg)
            (New-AnsiTreeRun -Text ([string][char]0x2026) -Fg $Options.LabelFg)
        )
        $null = $Lines.Add($row)
        return
    }

    for ($i = 0; $i -lt $Node.Children.Count; $i++) {
        $isLastChild = ($i -eq $Node.Children.Count - 1)
        $childConnector = if ($isLastChild) { $guide.Last } else { $guide.Tee }
        Add-AnsiTreeRows -Node $Node.Children[$i] -Prefix $childPrefix -Connector $childConnector `
            -Level ($Level + 1) -Options $Options -Lines $Lines
    }
}

Export-ModuleMember -Function Format-AnsiTree
