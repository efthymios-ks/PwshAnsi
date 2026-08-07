#Requires -Version 7.2

# Out-AnsiHost.psm1
# Public: Out-AnsiHost.
# Paints an [Ansi.Rendering] — the object every Format-Ansi* returns — to the host.
# Depends on Ansi.Core.psm1 for anchoring, colour detection, and row rendering.
#
# Two ways to paint. By default the rendering lands where the cursor is and later
# rows resume at its anchor column, one host write per row. Given -Row and -Column
# — 0-based, and required together — the rendering is painted at that cell instead,
# as a single write of one frame, which is what makes a repaint flicker-free.

Import-Module (Join-Path $PSScriptRoot 'Ansi.Core.psm1') -Force -DisableNameChecking

function Out-AnsiHost {
    [CmdletBinding(DefaultParameterSetName = 'Anchor')]
    param(
        [Parameter(Position = 0, Mandatory, ValueFromPipeline)]
        [AllowNull()]
        [object]$Rendering,

        # Overrides the rendering's own decision; unset falls back to the
        # rendering, then to Test-AnsiNoColor.
        [AllowNull()]
        [System.Nullable[bool]]$NoColor = $null,

        # Anchor: overrides the anchor column recorded when the rendering was built.
        # Position: the column to paint at, 0-based. Required with -Row.
        [Parameter(ParameterSetName = 'Anchor')]
        [Parameter(ParameterSetName = 'Position', Mandatory)]
        [AllowNull()]
        [System.Nullable[int]]$Column = $null,

        # The row to paint at, 0-based, counted from the top of the screen. Turns
        # the whole rendering into one positioned frame, written once.
        [Parameter(ParameterSetName = 'Position', Mandatory)]
        [ValidateRange(0, [int]::MaxValue)]
        [int]$Row,

        [Parameter(ParameterSetName = 'Anchor')]
        [switch]$NoNewline
    )
    process {
        if ($null -eq $Rendering) { return }
        if (-not (Test-AnsiRendering -Value $Rendering)) {
            throw "Out-AnsiHost expects an [Ansi.Rendering] from a Format-Ansi* function, got '$($Rendering.GetType().FullName)'."
        }

        $rows = @($Rendering.Rows)
        if ($rows.Count -eq 0) { return }

        $stripColor = $NoColor
        if ($null -eq $stripColor) { $stripColor = $Rendering.NoColor }
        if ($null -eq $stripColor) { $stripColor = Test-AnsiNoColor }

        if ($PSCmdlet.ParameterSetName -eq 'Position') {
            # One string, one write. Redirected output gets the rows without any
            # cursor sequences, so a captured or piped frame is still readable.
            $frame = Format-AnsiFrame -Rows $rows -Width $Rendering.Width `
                -Row $Row -Column ([Math]::Max(0, [int]$Column)) `
                -NoColor:$stripColor -Plain:(-not (Test-AnsiTerminal))
            Write-AnsiFrame -Text $frame
            return
        }

        $anchorColumn = $Column
        if ($null -eq $anchorColumn) { $anchorColumn = [int]$Rendering.Column }
        $indentPrefix = ' ' * [Math]::Max(0, $anchorColumn)

        for ($i = 0; $i -lt $rows.Count; $i++) {
            $rowText = Format-AnsiLine -Runs @($rows[$i]) -Width $Rendering.Width -Justify Left -NoColor:$stripColor
            # The first row lands where the cursor already is; the rest resume at
            # the anchor column. Blank rows stay blank rather than trailing spaces.
            $prefix = ''
            if ($i -gt 0 -and $rowText -ne '') { $prefix = $indentPrefix }
            $isLast = ($i -eq $rows.Count - 1)

            if ($isLast -and $NoNewline) {
                Write-Host ($prefix + $rowText) -NoNewline
            } else {
                Write-Host ($prefix + $rowText)
            }
        }
    }
}

Export-ModuleMember -Function Out-AnsiHost
