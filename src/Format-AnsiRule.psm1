#Requires -Version 7.2

# Format-AnsiRule.psm1
# Public: Format-AnsiRule — builds an [Ansi.Rendering].
# Paint it with Out-AnsiHost, or turn it into strings with Out-AnsiString.

Import-Module (Join-Path $PSScriptRoot 'Ansi.Core.psm1') -Force -DisableNameChecking

$script:AnsiRuleBorderMap = @{
    'line'   = [string][char]0x2500   # ─
    'double' = [string][char]0x2550   # ═
    'heavy'  = [string][char]0x2501   # ━
    'ascii'  = '-'
    'dashed' = [string][char]0x2504   # ┄
    'dotted' = [string][char]0x2508   # ┈
}

function Format-AnsiRule {
    [CmdletBinding()]
    [OutputType('Ansi.Rendering')]
    param(
        [Parameter(Position = 0, ValueFromPipeline)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Title,

        [ValidateSet('Left', 'Center', 'Right')]
        [string]$Alignment = 'Left',

        [Alias('Color')]
        [string]$TitleColor,

        [string]$LineColor,

        [ValidateSet('Line', 'Double', 'Heavy', 'Ascii', 'Dashed', 'Dotted')]
        [string]$Border = 'Line',

        [ValidateNotNullOrEmpty()]
        [string]$Char,

        [ValidateRange(0, [int]::MaxValue)]
        [int]$TitlePadding = 1,

        [int]$Width = 0,

        [switch]$Expand,

        [ValidateRange(0, [int]::MaxValue)]
        [int]$Spacing = 0,

        [switch]$Markdown,

        [switch]$Escape
    )
    process {
        $anchor = Get-AnsiAnchor -MaxWidth $Width
        $noColor = Test-AnsiNoColor

        if ($Expand) {
            $ruleWidth = if ($Width -gt 0) { $Width } else { $anchor.BufferWidth }
            $prefixColumn = 0
        } else {
            $ruleWidth = $anchor.Width
            $prefixColumn = $anchor.Column
        }
        $ruleWidth = [Math]::Max(1, $ruleWidth)

        $lineChar = if ($Char) { $Char } else { $script:AnsiRuleBorderMap[$Border.ToLowerInvariant()] }

        $lineFg = if ($LineColor) { Get-AnsiColorName -Name $LineColor } else { $null }
        $titleFg = if ($TitleColor) { Get-AnsiColorName -Name $TitleColor } else { $null }

        $titleRuns = @()
        if (-not [string]::IsNullOrEmpty($Title)) {
            # A rule is a single row: hard breaks in the title collapse to spaces.
            $flat = $Title -replace "`r?`n", ' '
            if ($Escape) {
                $titleRuns = @(New-AnsiRuleRun -Text $flat -Fg $titleFg)
            } else {
                # Plain assignment, not @(): ConvertFrom-AnsiMarkup returns the run
                # array comma-wrapped, so @() would nest it one level deeper.
                $titleRuns = ConvertFrom-AnsiMarkup -Text $flat -AsMarkdown:$Markdown
                foreach ($r in $titleRuns) { if (-not $r.Fg) { $r.Fg = $titleFg } }
            }
        }

        $runs = Get-AnsiRuleRuns -TitleRuns $titleRuns -Width $ruleWidth -Alignment $Alignment `
            -LineChar $lineChar -LineFg $lineFg -TitlePadding $TitlePadding

        $blank = @(, @(New-AnsiRuleRun -Text '' -Fg $null))

        $rows = [System.Collections.Generic.List[object]]::new()
        for ($i = 0; $i -lt $Spacing; $i++) { $null = $rows.Add(@($blank[0])) }
        $null = $rows.Add(@($runs))
        for ($i = 0; $i -lt $Spacing; $i++) { $null = $rows.Add(@($blank[0])) }

        return (New-AnsiRendering -Kind 'Rule' -Rows $rows.ToArray() -Width $ruleWidth `
                -Column $prefixColumn -NoColor $noColor)
    }
}

function New-AnsiRuleRun {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text,
        [string]$Fg
    )
    [PSCustomObject]@{
        Text   = $Text
        Fg     = $(if ($Fg) { $Fg } else { $null })
        Bg     = $null
        Styles = @()
        Link   = $null
    }
}

# Repeat (and tile, for multi-character overrides) up to an exact width.
function Get-AnsiRuleLine {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Char,
        [Parameter(Mandatory)][int]$Length
    )
    if ($Length -le 0) { return '' }
    $sb = [System.Text.StringBuilder]::new()
    while ($sb.Length -lt $Length) { $null = $sb.Append($Char) }
    return $sb.ToString().Substring(0, $Length)
}

# Lay the row out as line/title/line runs, truncating the title if it cannot fit.
function Get-AnsiRuleRuns {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$TitleRuns,
        [Parameter(Mandatory)][int]$Width,
        [Parameter(Mandatory)][string]$Alignment,
        [Parameter(Mandatory)][string]$LineChar,
        [AllowNull()][string]$LineFg,
        [Parameter(Mandatory)][int]$TitlePadding
    )
    if ($TitleRuns.Count -eq 0) {
        return , @(New-AnsiRuleRun -Text (Get-AnsiRuleLine -Char $LineChar -Length $Width) -Fg $LineFg)
    }

    # Gaps: one padded side for Left/Right, two for Center. Each side that
    # carries a line keeps at least one line character.
    $gaps = if ($Alignment -eq 'Center') { 2 } else { 1 }
    $minLine = $gaps
    $available = $Width - ($TitlePadding * $gaps) - $minLine

    if ($available -lt 2) {
        # No room for a title worth reading at this width (a lone ellipsis is
        # noise) — render a plain line instead.
        return , @(New-AnsiRuleRun -Text (Get-AnsiRuleLine -Char $LineChar -Length $Width) -Fg $LineFg)
    }

    $visible = 0
    foreach ($r in $TitleRuns) { $visible += $r.Text.Length }
    if ($visible -gt $available) {
        $wrapped = Split-AnsiRuns -Runs $TitleRuns -Width $available -Overflow Ellipsis
        $TitleRuns = @($wrapped[0])
        $visible = 0
        foreach ($r in $TitleRuns) { $visible += $r.Text.Length }
    }

    $remaining = [Math]::Max(0, $Width - $visible - ($TitlePadding * $gaps))
    $pad = ' ' * $TitlePadding

    $runs = [System.Collections.Generic.List[object]]::new()
    switch ($Alignment) {
        'Left' {
            foreach ($r in $TitleRuns) { $null = $runs.Add($r) }
            if ($TitlePadding -gt 0) { $null = $runs.Add((New-AnsiRuleRun -Text $pad)) }
            $null = $runs.Add((New-AnsiRuleRun -Text (Get-AnsiRuleLine -Char $LineChar -Length $remaining) -Fg $LineFg))
        }
        'Right' {
            $null = $runs.Add((New-AnsiRuleRun -Text (Get-AnsiRuleLine -Char $LineChar -Length $remaining) -Fg $LineFg))
            if ($TitlePadding -gt 0) { $null = $runs.Add((New-AnsiRuleRun -Text $pad)) }
            foreach ($r in $TitleRuns) { $null = $runs.Add($r) }
        }
        default {
            $left = [int][Math]::Floor($remaining / 2)
            $right = $remaining - $left
            $null = $runs.Add((New-AnsiRuleRun -Text (Get-AnsiRuleLine -Char $LineChar -Length $left) -Fg $LineFg))
            if ($TitlePadding -gt 0) { $null = $runs.Add((New-AnsiRuleRun -Text $pad)) }
            foreach ($r in $TitleRuns) { $null = $runs.Add($r) }
            if ($TitlePadding -gt 0) { $null = $runs.Add((New-AnsiRuleRun -Text $pad)) }
            $null = $runs.Add((New-AnsiRuleRun -Text (Get-AnsiRuleLine -Char $LineChar -Length $right) -Fg $LineFg))
        }
    }
    return , $runs.ToArray()
}

Export-ModuleMember -Function Format-AnsiRule
