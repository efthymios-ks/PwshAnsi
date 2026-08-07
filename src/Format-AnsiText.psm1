#Requires -Version 7.2

# Format-AnsiText.psm1
# Public: Format-AnsiText — builds an [Ansi.Rendering].
# Paint it with Out-AnsiHost, or turn it into strings with Out-AnsiString.

Import-Module (Join-Path $PSScriptRoot 'Ansi.Core.psm1') -Force -DisableNameChecking

function Format-AnsiText {
    [CmdletBinding()]
    [OutputType('Ansi.Rendering')]
    param(
        [Parameter(Position = 0, ValueFromPipeline)]
        [AllowNull()]
        [AllowEmptyString()]
        [AllowEmptyCollection()]
        [string[]]$Message,

        [string]$Color,

        [ValidateSet('Left', 'Center', 'Right')]
        [string]$Justify = 'Left',

        [int]$MaxWidth = 0,

        [int]$Indent = 0,

        [int]$MaxRows = 0,

        [ValidateSet('Fold', 'Crop', 'Ellipsis')]
        [string]$Overflow = 'Fold',

        [switch]$Markdown,

        [switch]$Escape
    )
    begin {
        $accumulated = [System.Collections.Generic.List[string]]::new()
    }
    process {
        if ($null -ne $Message) {
            foreach ($m in $Message) { $null = $accumulated.Add([string]$m) }
        }
    }
    end {
        if ($accumulated.Count -eq 0) { return }

        $anchor = Get-AnsiAnchor -MaxWidth $MaxWidth
        $noColor = Test-AnsiNoColor
        $wrapWidth = [Math]::Max(1, $anchor.Width - $Indent)

        $rawText = $accumulated -join "`n"

        if ($Escape) {
            $runs = @([PSCustomObject]@{
                    Text = $rawText; Fg = $null; Bg = $null; Styles = @(); Link = $null
                })
        } else {
            $runs = ConvertFrom-AnsiMarkup -Text $rawText -AsMarkdown:$Markdown
        }

        if ($Color) {
            $canonical = Get-AnsiColorName -Name $Color
            foreach ($r in $runs) { if (-not $r.Fg) { $r.Fg = $canonical } }
        }

        # When -MaxRows is set, always wrap by Fold so intermediate rows render
        # in full — only the last kept row is ellipsised by the row cap below.
        $wrapOverflow = if ($MaxRows -gt 0) { 'Fold' } else { $Overflow }
        $lines = Split-AnsiRuns -Runs $runs -Width $wrapWidth -Overflow $wrapOverflow

        if ($MaxRows -gt 0 -and $lines.Count -gt $MaxRows) {
            $lines = $lines[0..($MaxRows - 1)]
            $last = $lines[-1]
            if ($last.Count -gt 0) {
                $tail = $last[-1]
                $others = 0
                for ($k = 0; $k -lt $last.Count - 1; $k++) { $others += $last[$k].Text.Length }
                $avail = $wrapWidth - $others
                $body = $tail.Text.TrimEnd()
                if ($body.Length + 1 -gt $avail) {
                    $body = $body.Substring(0, [Math]::Max(0, $avail - 1))
                }
                $tail.Text = $body + [char]0x2026
            }
        }

        # Rows are self-contained: justification and the hanging indent are baked
        # in, so the writers only ever add the anchor column.
        $rows = [System.Collections.Generic.List[object]]::new()
        $indentRun = $null
        if ($Indent -gt 0) {
            $indentRun = [PSCustomObject]@{
                Text = ' ' * $Indent; Fg = $null; Bg = $null; Styles = @(); Link = $null
            }
        }

        for ($i = 0; $i -lt $lines.Count; $i++) {
            $justified = Add-AnsiJustify -Runs @($lines[$i]) -Width $wrapWidth -Justify $Justify
            if ($i -gt 0 -and $indentRun) {
                $withIndent = [System.Collections.Generic.List[object]]::new()
                $null = $withIndent.Add($indentRun)
                foreach ($r in @($justified)) { $null = $withIndent.Add($r) }
                $null = $rows.Add($withIndent.ToArray())
            } else {
                $null = $rows.Add(@($justified))
            }
        }

        return (New-AnsiRendering -Kind 'Text' -Rows $rows.ToArray() -Width ($wrapWidth + $Indent) `
                -Column $anchor.Column -NoColor $noColor)
    }
}

Export-ModuleMember -Function Format-AnsiText
