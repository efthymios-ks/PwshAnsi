#Requires -Version 7.2

# Format-AnsiJson.psm1
# Public: Format-AnsiJson — builds an [Ansi.Rendering].
# Paint it with Out-AnsiHost, or turn it into strings with Out-AnsiString.

Import-Module (Join-Path $PSScriptRoot 'Ansi.Core.psm1') -Force -DisableNameChecking

function Format-AnsiJson {
    [CmdletBinding()]
    [OutputType('Ansi.Rendering')]
    param(
        [Parameter(Position = 0, ValueFromPipeline)]
        [AllowNull()]
        [AllowEmptyString()]
        [AllowEmptyCollection()]
        [object]$Data,

        [ValidateRange(1, 100)]
        [int]$Depth = 10,

        [ValidateRange(0, 16)]
        [int]$IndentSize = 2,

        [ValidateRange(0, [int]::MaxValue)]
        [int]$MaxDepth = 0,

        [string]$KeyColor = 'BrightBlue',

        [string]$StringColor = 'BrightGreen',

        [string]$NumberColor = 'BrightCyan',

        [string]$BooleanColor = 'BrightMagenta',

        [string]$NullColor = 'BrightBlack',

        [string]$PunctuationColor,

        [int]$MaxWidth = 0
    )
    begin {
        $accumulated = [System.Collections.Generic.List[object]]::new()
    }
    process {
        $null = $accumulated.Add($Data)
    }
    end {
        if ($accumulated.Count -eq 0) { return }

        $anchor = Get-AnsiAnchor -MaxWidth $MaxWidth
        $noColor = Test-AnsiNoColor
        $width = [Math]::Max(1, $anchor.Width)

        $colors = @{
            Key         = Get-AnsiColorName -Name $KeyColor
            String      = Get-AnsiColorName -Name $StringColor
            Number      = Get-AnsiColorName -Name $NumberColor
            Boolean     = Get-AnsiColorName -Name $BooleanColor
            Null        = Get-AnsiColorName -Name $NullColor
            Punctuation = $(if ($PunctuationColor) { Get-AnsiColorName -Name $PunctuationColor } else { $null })
        }

        # Plain assignments: an `if` expression would emit through the pipeline and
        # flatten an empty collection into $null.
        $payload = $null
        if ($accumulated.Count -eq 1) { $payload = $accumulated[0] }
        else { $payload = $accumulated.ToArray() }
        $node = ConvertTo-AnsiJsonNode -Value $payload -Depth $Depth

        $lines = [System.Collections.Generic.List[object]]::new()
        Add-AnsiJsonLines -Node $node -Level 0 -Prefix @() -Suffix '' -Colors $colors `
            -IndentSize $IndentSize -MaxDepth $MaxDepth -Lines $lines

        # Long rows are ellipsised, never wrapped: broken JSON reads worse than a
        # truncated row.
        $rows = [System.Collections.Generic.List[object]]::new()
        for ($i = 0; $i -lt $lines.Count; $i++) {
            $rowRuns = @($lines[$i])
            $visible = 0
            foreach ($r in $rowRuns) { $visible += $r.Text.Length }
            if ($visible -gt $width) {
                $cropped = Split-AnsiRuns -Runs $rowRuns -Width $width -Overflow Ellipsis
                $rowRuns = @($cropped[0])
            }
            $null = $rows.Add($rowRuns)
        }

        return (New-AnsiRendering -Kind 'Json' -Rows $rows.ToArray() -Width $width `
                -Column $anchor.Column -NoColor $noColor)
    }
}

function New-AnsiJsonRun {
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

# Normalise any input into a tree of Object / Array / Scalar nodes. Strings that
# parse as JSON are treated as JSON; everything else is serialised first.
function ConvertTo-AnsiJsonNode {
    [CmdletBinding()]
    param(
        [AllowNull()][object]$Value,
        [Parameter(Mandatory)][int]$Depth
    )
    $parsed = $Value

    # -Depth bounds serialisation only; reading back always uses the maximum so a
    # deliberately truncated tree still parses.
    $readDepth = 100

    if ($Value -is [string]) {
        try {
            $parsed = (ConvertFrom-AnsiJsonText -Text $Value -ReadDepth $readDepth).Value
        } catch {
            $parsed = $Value
        }
    } elseif ($null -ne $Value -and -not (Test-AnsiJsonScalar -Value $Value)) {
        # -InputObject, not the pipeline: piping would unroll an empty collection
        # into nothing and serialise it as `null`.
        $json = ConvertTo-Json -InputObject $Value -Depth $Depth -Compress
        $parsed = (ConvertFrom-AnsiJsonText -Text $json -ReadDepth $readDepth).Value
    }

    return (New-AnsiJsonNode -Value $parsed)
}

# Parse JSON text without letting the pipeline flatten it: -NoEnumerate keeps a
# top-level array intact, and the result is handed back boxed in a carrier object
# so an empty array survives the return as well.
function ConvertFrom-AnsiJsonText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text,
        [Parameter(Mandatory)][int]$ReadDepth
    )
    $result = $Text | ConvertFrom-Json -Depth $ReadDepth -NoEnumerate -ErrorAction Stop
    return [PSCustomObject]@{ Value = $result }
}

function Test-AnsiJsonScalar {
    [CmdletBinding()]
    param([AllowNull()][object]$Value)
    if ($null -eq $Value) { return $true }
    return ($Value -is [string] -or $Value -is [bool] -or $Value -is [datetime] -or
        $Value -is [char] -or $Value -is [System.ValueType] -and $Value -isnot [System.Enum] -or
        $Value -is [System.Enum])
}

function New-AnsiJsonNode {
    [CmdletBinding()]
    param([AllowNull()][object]$Value)

    if ($null -eq $Value) {
        return [PSCustomObject]@{ Kind = 'Scalar'; Text = 'null'; ValueKind = 'Null' }
    }
    if ($Value -is [System.Management.Automation.PSCustomObject] -or $Value -is [hashtable] -or
        $Value -is [System.Collections.Specialized.OrderedDictionary]) {

        $pairs = [System.Collections.Generic.List[object]]::new()
        if ($Value -is [System.Management.Automation.PSCustomObject]) {
            foreach ($p in $Value.PSObject.Properties) {
                $null = $pairs.Add([PSCustomObject]@{ Key = $p.Name; Node = (New-AnsiJsonNode -Value $p.Value) })
            }
        } else {
            foreach ($k in $Value.Keys) {
                $null = $pairs.Add([PSCustomObject]@{ Key = [string]$k; Node = (New-AnsiJsonNode -Value $Value[$k]) })
            }
        }
        return [PSCustomObject]@{ Kind = 'Object'; Pairs = $pairs.ToArray() }
    }
    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
        $items = [System.Collections.Generic.List[object]]::new()
        foreach ($item in $Value) { $null = $items.Add((New-AnsiJsonNode -Value $item)) }
        return [PSCustomObject]@{ Kind = 'Array'; Items = $items.ToArray() }
    }

    # Scalars, rendered the way JSON spells them.
    if ($Value -is [bool]) {
        return [PSCustomObject]@{ Kind = 'Scalar'; Text = $(if ($Value) { 'true' } else { 'false' }); ValueKind = 'Boolean' }
    }
    if ($Value -is [string] -or $Value -is [char] -or $Value -is [datetime] -or $Value -is [System.Enum]) {
        $text = if ($Value -is [datetime]) { $Value.ToString('o') } else { [string]$Value }
        return [PSCustomObject]@{ Kind = 'Scalar'; Text = (ConvertTo-AnsiJsonString -Text $text); ValueKind = 'String' }
    }
    if ($Value -is [System.ValueType]) {
        $text = if ($Value -is [double] -or $Value -is [single] -or $Value -is [decimal]) {
            [string]([System.Convert]::ToString($Value, [cultureinfo]::InvariantCulture))
        } else {
            [string]$Value
        }
        return [PSCustomObject]@{ Kind = 'Scalar'; Text = $text; ValueKind = 'Number' }
    }
    return [PSCustomObject]@{ Kind = 'Scalar'; Text = (ConvertTo-AnsiJsonString -Text ([string]$Value)); ValueKind = 'String' }
}

function ConvertTo-AnsiJsonString {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)
    $escaped = $Text.
    Replace('\', '\\').
    Replace('"', '\"').
    Replace("`n", '\n').
    Replace("`r", '\r').
    Replace("`t", '\t')
    return '"' + $escaped + '"'
}

# Flatten a node into rows of runs. Each row is an object[] of runs.
function Add-AnsiJsonLines {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Node,
        [Parameter(Mandatory)][int]$Level,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Prefix,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Suffix,
        [Parameter(Mandatory)][hashtable]$Colors,
        [Parameter(Mandatory)][int]$IndentSize,
        [Parameter(Mandatory)][int]$MaxDepth,
        [Parameter(Mandatory)][AllowEmptyCollection()][System.Collections.Generic.List[object]]$Lines
    )
    $indent = ' ' * ($Level * $IndentSize)
    $punct = $Colors.Punctuation

    switch ($Node.Kind) {
        'Object' {
            if ($MaxDepth -gt 0 -and $Level -ge $MaxDepth -and $Node.Pairs.Count -gt 0) {
                Add-AnsiJsonRow -Lines $Lines -Indent $indent -Prefix $Prefix `
                    -Runs @(New-AnsiJsonRun -Text ('{' + [char]0x2026 + '}') -Fg $punct) -Suffix $Suffix -Punct $punct
                return
            }
            if ($Node.Pairs.Count -eq 0) {
                Add-AnsiJsonRow -Lines $Lines -Indent $indent -Prefix $Prefix `
                    -Runs @(New-AnsiJsonRun -Text '{}' -Fg $punct) -Suffix $Suffix -Punct $punct
                return
            }
            Add-AnsiJsonRow -Lines $Lines -Indent $indent -Prefix $Prefix `
                -Runs @(New-AnsiJsonRun -Text '{' -Fg $punct) -Suffix '' -Punct $punct

            for ($i = 0; $i -lt $Node.Pairs.Count; $i++) {
                $pair = $Node.Pairs[$i]
                $comma = if ($i -lt $Node.Pairs.Count - 1) { ',' } else { '' }
                $keyRuns = @(
                    (New-AnsiJsonRun -Text (ConvertTo-AnsiJsonString -Text $pair.Key) -Fg $Colors.Key)
                    (New-AnsiJsonRun -Text ': ' -Fg $punct)
                )
                Add-AnsiJsonLines -Node $pair.Node -Level ($Level + 1) -Prefix $keyRuns -Suffix $comma `
                    -Colors $Colors -IndentSize $IndentSize -MaxDepth $MaxDepth -Lines $Lines
            }

            Add-AnsiJsonRow -Lines $Lines -Indent $indent -Prefix @() `
                -Runs @(New-AnsiJsonRun -Text '}' -Fg $punct) -Suffix $Suffix -Punct $punct
        }
        'Array' {
            if ($MaxDepth -gt 0 -and $Level -ge $MaxDepth -and $Node.Items.Count -gt 0) {
                Add-AnsiJsonRow -Lines $Lines -Indent $indent -Prefix $Prefix `
                    -Runs @(New-AnsiJsonRun -Text ('[' + [char]0x2026 + ']') -Fg $punct) -Suffix $Suffix -Punct $punct
                return
            }
            if ($Node.Items.Count -eq 0) {
                Add-AnsiJsonRow -Lines $Lines -Indent $indent -Prefix $Prefix `
                    -Runs @(New-AnsiJsonRun -Text '[]' -Fg $punct) -Suffix $Suffix -Punct $punct
                return
            }
            Add-AnsiJsonRow -Lines $Lines -Indent $indent -Prefix $Prefix `
                -Runs @(New-AnsiJsonRun -Text '[' -Fg $punct) -Suffix '' -Punct $punct

            for ($i = 0; $i -lt $Node.Items.Count; $i++) {
                $comma = if ($i -lt $Node.Items.Count - 1) { ',' } else { '' }
                Add-AnsiJsonLines -Node $Node.Items[$i] -Level ($Level + 1) -Prefix @() -Suffix $comma `
                    -Colors $Colors -IndentSize $IndentSize -MaxDepth $MaxDepth -Lines $Lines
            }

            Add-AnsiJsonRow -Lines $Lines -Indent $indent -Prefix @() `
                -Runs @(New-AnsiJsonRun -Text ']' -Fg $punct) -Suffix $Suffix -Punct $punct
        }
        default {
            $fg = switch ($Node.ValueKind) {
                'String' { $Colors.String }
                'Number' { $Colors.Number }
                'Boolean' { $Colors.Boolean }
                default { $Colors.Null }
            }
            Add-AnsiJsonRow -Lines $Lines -Indent $indent -Prefix $Prefix `
                -Runs @(New-AnsiJsonRun -Text $Node.Text -Fg $fg) -Suffix $Suffix -Punct $punct
        }
    }
}

function Add-AnsiJsonRow {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][System.Collections.Generic.List[object]]$Lines,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Indent,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Prefix,
        [Parameter(Mandatory)][object[]]$Runs,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Suffix,
        [AllowNull()][string]$Punct
    )
    $row = [System.Collections.Generic.List[object]]::new()
    if ($Indent) { $null = $row.Add((New-AnsiJsonRun -Text $Indent -Fg $null)) }
    foreach ($r in $Prefix) { $null = $row.Add($r) }
    foreach ($r in $Runs) { $null = $row.Add($r) }
    if ($Suffix) { $null = $row.Add((New-AnsiJsonRun -Text $Suffix -Fg $Punct)) }
    $null = $Lines.Add($row.ToArray())
}

Export-ModuleMember -Function Format-AnsiJson
