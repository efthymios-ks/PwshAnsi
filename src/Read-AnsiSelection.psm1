#Requires -Version 7.2

# Read-AnsiSelection.psm1
# Public: Read-AnsiSelection — pick one item from a list with the arrow keys.
# Returns the item the caller passed in, or $null on Esc / timeout.
# Depends on Ansi.Core.psm1 for markup, colour, cursor control, and input seams.

Import-Module (Join-Path $PSScriptRoot 'Ansi.Core.psm1') -Force -DisableNameChecking

function Read-AnsiSelection {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0, Mandatory)]
        [AllowEmptyString()]
        [string]$Title,

        [Parameter(Position = 1, Mandatory, ValueFromPipeline)]
        [AllowEmptyCollection()]
        [object[]]$Choices,

        [Alias('ChoiceLabelProperty')]
        [string]$LabelProperty,

        [Alias('Color')]
        [string]$CursorColor = 'BrightCyan',

        [string]$TitleColor,

        [string]$ChoiceColor,

        [string]$HintColor = 'BrightBlack',

        [ValidateRange(1, [int]::MaxValue)]
        [int]$PageSize = 10,

        [ValidateRange(0, [int]::MaxValue)]
        [int]$TimeoutSeconds = 0,

        [switch]$Markdown,

        [switch]$Escape
    )
    begin {
        $collected = [System.Collections.Generic.List[object]]::new()
    }
    process {
        if ($null -eq $Choices) { return }
        foreach ($choice in $Choices) { $null = $collected.Add($choice) }
    }
    end {
        if ($collected.Count -eq 0) { throw 'Read-AnsiSelection needs at least one choice.' }
        if (-not (Test-AnsiInteractive)) {
            throw 'Read-AnsiSelection needs an interactive console: input is redirected.'
        }

        $noColor = Test-AnsiNoColor
        $cursorFg = Get-AnsiColorName -Name $CursorColor
        $hintFg = Get-AnsiColorName -Name $HintColor
        $titleFg = if ($TitleColor) { Get-AnsiColorName -Name $TitleColor } else { $null }
        $choiceFg = if ($ChoiceColor) { Get-AnsiColorName -Name $ChoiceColor } else { $null }

        $items = ConvertTo-AnsiChoices -Items $collected.ToArray() -LabelProperty $LabelProperty `
            -Fg $choiceFg -Markdown:$Markdown -Escape:$Escape

        $index = 0
        $window = Get-AnsiChoiceWindow -Index $index -Count $items.Count -PageSize $PageSize
        $drawn = 0
        $deadline = if ($TimeoutSeconds -gt 0) { [datetime]::UtcNow.AddSeconds($TimeoutSeconds) } else { $null }

        # Nothing is typed here, and a list that repaints under a blinking cursor
        # reads as flicker. Put back whatever the caller had on the way out.
        $cursor = Hide-AnsiCursor
        try {
            while ($true) {
                $drawn = Write-AnsiSelectionList -Title $Title -TitleFg $titleFg -Items $items -Index $index `
                    -Window $window -CursorFg $cursorFg -HintFg $hintFg -NoColor:$noColor `
                    -Markdown:$Markdown -Escape:$Escape -Redraw ($drawn -gt 0) -Drawn $drawn

                if ($null -ne $deadline) {
                    $timedOut = $false
                    while (-not (Test-AnsiKeyAvailable)) {
                        if ([datetime]::UtcNow -ge $deadline) { $timedOut = $true; break }
                        Start-AnsiWait
                    }
                    if ($timedOut) { return $null }
                }

                $key = Read-AnsiKeyInfo
                if ($null -eq $key) { return $null }

                switch ($key.Key) {
                    'UpArrow' { if ($index -gt 0) { $index-- } }
                    'DownArrow' { if ($index -lt $items.Count - 1) { $index++ } }
                    'Home' { $index = 0 }
                    'End' { $index = $items.Count - 1 }
                    'PageUp' { $index = [Math]::Max(0, $index - $window.Size) }
                    'PageDown' { $index = [Math]::Min($items.Count - 1, $index + $window.Size) }
                    'Enter' { return $items[$index].Item }
                    'Escape' { return $null }
                    default {
                        # k/j move too, for anyone who lives in vi.
                        switch ([char]::ToLowerInvariant($key.KeyChar)) {
                            'k' { if ($index -gt 0) { $index-- } }
                            'j' { if ($index -lt $items.Count - 1) { $index++ } }
                        }
                    }
                }

                $window = Get-AnsiChoiceWindow -Index $index -Count $items.Count -PageSize $PageSize -Start $window.Start
            }
        } finally {
            Restore-AnsiCursor -State $cursor
        }
    }
}

# Draws title, the visible slice, and a hint row; returns how many rows it wrote so
# the next pass can move back up over them.
function Write-AnsiSelectionList {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Title,
        [AllowNull()][string]$TitleFg,
        [Parameter(Mandatory)][object[]]$Items,
        [Parameter(Mandatory)][int]$Index,
        [Parameter(Mandatory)][object]$Window,
        [Parameter(Mandatory)][string]$CursorFg,
        [Parameter(Mandatory)][string]$HintFg,
        [switch]$NoColor,
        [switch]$Markdown,
        [switch]$Escape,
        [bool]$Redraw = $false,
        [int]$Drawn = 0
    )
    if ($Redraw) { Move-AnsiCursorUp -Lines $Drawn }

    $rows = 0

    Clear-AnsiLine
    Write-Host (Format-AnsiLine -Runs (Get-AnsiSelectionTitleRuns -Title $Title -Fg $TitleFg `
                -Markdown:$Markdown -Escape:$Escape) -Width 0 -Justify Left -NoColor:$NoColor)
    $rows++

    for ($i = $Window.Start; $i -le $Window.End -and $i -lt $Items.Count; $i++) {
        $runs = [System.Collections.Generic.List[object]]::new()
        $marker = if ($i -eq $Index) { [string][char]0x203A + ' ' } else { '  ' }   # ›
        $null = $runs.Add((New-AnsiSelectionRun -Text $marker -Fg $CursorFg))
        foreach ($r in $Items[$i].Runs) {
            $copy = $r
            if ($i -eq $Index -and -not $r.Fg) {
                $copy = [PSCustomObject]@{
                    Text = $r.Text; Fg = $CursorFg; Bg = $r.Bg; Styles = $r.Styles; Link = $r.Link
                }
            }
            $null = $runs.Add($copy)
        }
        Clear-AnsiLine
        Write-Host (Format-AnsiLine -Runs $runs.ToArray() -Width 0 -Justify Left -NoColor:$NoColor)
        $rows++
    }

    $hint = ($Items.Count -gt $Window.Size) `
        ? "$($Index + 1)/$($Items.Count)  ↑↓ move · enter select · esc cancel" `
        : '↑↓ move · enter select · esc cancel'
    Clear-AnsiLine
    Write-Host (Format-AnsiLine -Runs @((New-AnsiSelectionRun -Text $hint -Fg $HintFg)) `
            -Width 0 -Justify Left -NoColor:$NoColor)
    $rows++

    return $rows
}

function Get-AnsiSelectionTitleRuns {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Title,
        [AllowNull()][string]$Fg,
        [switch]$Markdown,
        [switch]$Escape
    )
    if ($Escape) { return , @(New-AnsiSelectionRun -Text $Title -Fg $Fg) }
    $runs = ConvertFrom-AnsiMarkup -Text $Title -AsMarkdown:$Markdown
    foreach ($r in $runs) { if (-not $r.Fg) { $r.Fg = $Fg } }
    return , @($runs)
}

function New-AnsiSelectionRun {
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

Export-ModuleMember -Function Read-AnsiSelection
