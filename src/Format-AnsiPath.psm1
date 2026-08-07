#Requires -Version 7.2

# Format-AnsiPath.psm1
# Public: Format-AnsiPath — builds an [Ansi.Rendering].
# Paint it with Out-AnsiHost, or turn it into strings with Out-AnsiString.

Import-Module (Join-Path $PSScriptRoot 'Ansi.Core.psm1') -Force -DisableNameChecking

function Format-AnsiPath {
    [CmdletBinding()]
    [OutputType('Ansi.Rendering')]
    param(
        [Parameter(Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [AllowNull()]
        [AllowEmptyString()]
        [AllowEmptyCollection()]
        [Alias('FullName', 'PSPath')]
        [string[]]$Path,

        [Alias('Color')]
        [string]$PathColor,

        [string]$RootColor,

        [string]$SeparatorColor,

        [string]$StemColor,

        [string]$LeafColor,

        [ValidateSet('Left', 'Center', 'Right')]
        [string]$Alignment = 'Left',

        [int]$MaxWidth = 0
    )
    begin {
        $accumulated = [System.Collections.Generic.List[string]]::new()
    }
    process {
        if ($null -ne $Path) {
            foreach ($p in $Path) { $null = $accumulated.Add([string]$p) }
        }
    }
    end {
        if ($accumulated.Count -eq 0) { return }

        $anchor = Get-AnsiAnchor -MaxWidth $MaxWidth
        $noColor = Test-AnsiNoColor
        $width = [Math]::Max(1, $anchor.Width)

        $base = if ($PathColor) { Get-AnsiColorName -Name $PathColor } else { $null }
        $colors = @{
            Root      = if ($RootColor) { Get-AnsiColorName -Name $RootColor } else { $base }
            Separator = if ($SeparatorColor) { Get-AnsiColorName -Name $SeparatorColor } else { $base }
            Stem      = if ($StemColor) { Get-AnsiColorName -Name $StemColor } else { $base }
            Leaf      = if ($LeafColor) { Get-AnsiColorName -Name $LeafColor } else { $base }
        }

        $rows = [System.Collections.Generic.List[object]]::new()
        foreach ($raw in $accumulated) {
            $runs = Get-AnsiPathRuns -Path $raw -Width $width -Colors $colors
            # Alignment is baked in so the rendering's rows are self-contained.
            # Parentheses, not @(): Add-AnsiJustify returns the run array
            # comma-wrapped, so @() would nest it.
            $justified = Add-AnsiJustify -Runs @($runs) -Width $width -Justify $Alignment
            $null = $rows.Add(@($justified))
        }

        return (New-AnsiRendering -Kind 'Path' -Rows $rows.ToArray() -Width $width `
                -Column $anchor.Column -NoColor $noColor)
    }
}

function New-AnsiPathRun {
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

# Break a path into root, stem segments, and leaf. The path is never validated
# and never normalised: the separator it already uses is the one rendered back.
function Split-AnsiPath {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Path)

    $separator = if ($Path -match '[\\/]') { $Matches[0] } else { [string][System.IO.Path]::DirectorySeparatorChar }

    $root = ''
    $rest = $Path
    if ($Path -match '^(\\\\[^\\/]+[\\/][^\\/]+[\\/]?)') {
        # UNC: \\server\share\
        $root = $Matches[1]
    } elseif ($Path -match '^([A-Za-z]:[\\/]?)') {
        $root = $Matches[1]
    } elseif ($Path -match '^(~[\\/]?)') {
        $root = $Matches[1]
    } elseif ($Path -match '^([\\/])') {
        $root = $Matches[1]
    }
    if ($root) { $rest = $Path.Substring($root.Length) }

    $segments = @($rest -split '[\\/]' | Where-Object { $_ -ne '' })

    $leaf = ''
    $stems = @()
    if ($segments.Count -gt 0) {
        $leaf = $segments[-1]
        if ($segments.Count -gt 1) { $stems = @($segments[0..($segments.Count - 2)]) }
    }

    # A trailing separator means the last segment is a container, not a leaf.
    if ($Path -match '[\\/]$' -and $leaf) {
        $stems = @($stems + $leaf)
        $leaf = ''
    }

    [PSCustomObject]@{
        Root      = $root
        Stems     = $stems
        Leaf      = $leaf
        Separator = $separator
    }
}

# Lay a single path out as coloured runs, dropping middle segments for `…` when
# it does not fit, and ellipsising the leaf when even that is too wide.
function Get-AnsiPathRuns {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Path,
        [Parameter(Mandatory)][int]$Width,
        [Parameter(Mandatory)][hashtable]$Colors
    )
    if ([string]::IsNullOrEmpty($Path)) {
        return , @(New-AnsiPathRun -Text '' -Fg $null)
    }

    $parts = Split-AnsiPath -Path $Path
    $ellipsis = [string][char]0x2026
    $sep = $parts.Separator

    # Widest first: keep every stem, then drop them from the left one at a time,
    # standing the dropped run in with a single `…` segment.
    for ($keep = $parts.Stems.Count; $keep -ge 0; $keep--) {
        $dropped = $parts.Stems.Count - $keep
        $kept = if ($keep -gt 0) { @($parts.Stems[($parts.Stems.Count - $keep)..($parts.Stems.Count - 1)]) } else { @() }

        $runs = [System.Collections.Generic.List[object]]::new()
        if ($parts.Root) { $null = $runs.Add((New-AnsiPathRun -Text $parts.Root -Fg $Colors.Root)) }
        if ($dropped -gt 0) {
            $null = $runs.Add((New-AnsiPathRun -Text $ellipsis -Fg $Colors.Stem))
            $null = $runs.Add((New-AnsiPathRun -Text $sep -Fg $Colors.Separator))
        }
        foreach ($stem in $kept) {
            $null = $runs.Add((New-AnsiPathRun -Text $stem -Fg $Colors.Stem))
            $null = $runs.Add((New-AnsiPathRun -Text $sep -Fg $Colors.Separator))
        }
        if ($parts.Leaf) { $null = $runs.Add((New-AnsiPathRun -Text $parts.Leaf -Fg $Colors.Leaf)) }

        $visible = 0
        foreach ($r in $runs) { $visible += $r.Text.Length }
        if ($visible -le $Width) { return , $runs.ToArray() }

        # Nothing left to drop: truncate what remains.
        if ($keep -eq 0) {
            $wrapped = Split-AnsiRuns -Runs $runs.ToArray() -Width $Width -Overflow Ellipsis
            return , @($wrapped[0])
        }
    }
}

Export-ModuleMember -Function Format-AnsiPath
