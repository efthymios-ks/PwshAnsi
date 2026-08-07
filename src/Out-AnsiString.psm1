#Requires -Version 7.2

# Out-AnsiString.psm1
# Public: Out-AnsiString.
# Renders an [Ansi.Rendering] to strings instead of the host: one string per row,
# ANSI kept unless -Plain. No anchor prefix — the block is returned as-is, which
# is what a caller composing panes or writing to a file wants.
# Depends on Ansi.Core.psm1 for row rendering.

Import-Module (Join-Path $PSScriptRoot 'Ansi.Core.psm1') -Force -DisableNameChecking

function Out-AnsiString {
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Position = 0, Mandatory, ValueFromPipeline)]
        [AllowNull()]
        [object]$Rendering,

        # Strip every style, whatever the rendering decided.
        [switch]$Plain,

        # Return one string with the rows joined by newlines.
        [switch]$Join,

        # Prefix continuation rows with the rendering's anchor column.
        [switch]$WithAnchor
    )
    process {
        if ($null -eq $Rendering) { return }
        if (-not (Test-AnsiRendering -Value $Rendering)) {
            throw "Out-AnsiString expects an [Ansi.Rendering] from a Format-Ansi* function, got '$($Rendering.GetType().FullName)'."
        }

        $rows = @($Rendering.Rows)
        if ($rows.Count -eq 0) { return , @() }

        $stripColor = [bool]$Plain
        if (-not $stripColor -and $null -ne $Rendering.NoColor) { $stripColor = [bool]$Rendering.NoColor }

        $indentPrefix = ''
        if ($WithAnchor) { $indentPrefix = ' ' * [Math]::Max(0, [int]$Rendering.Column) }

        $out = [System.Collections.Generic.List[string]]::new()
        for ($i = 0; $i -lt $rows.Count; $i++) {
            $rowText = Format-AnsiLine -Runs @($rows[$i]) -Width $Rendering.Width -Justify Left -NoColor:$stripColor
            $prefix = if ($i -eq 0) { '' } else { $indentPrefix }
            $null = $out.Add($prefix + $rowText)
        }

        if ($Join) { return ($out -join [System.Environment]::NewLine) }
        return , $out.ToArray()
    }
}

Export-ModuleMember -Function Out-AnsiString
