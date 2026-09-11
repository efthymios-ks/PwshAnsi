#Requires -Version 7.2

# Read-AnsiSelection.psm1
# Public: Read-AnsiSelection — pick one item from a list with the arrow keys.
# Returns the item the caller passed in, or $null on Esc / timeout.
# -Grouped takes headed groups instead of a flat list; a header is shape only here,
# the cursor moves straight past it.
# Depends on Ansi.Core.psm1 for markup, colour, cursor control, and input seams.

Import-Module (Join-Path $PSScriptRoot 'Ansi.Core.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'Ansi.Input.psm1') -Force -DisableNameChecking

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

        [switch]$Grouped,

        [string]$GroupLabelProperty = 'Name',

        [string]$GroupChoicesProperty = 'Choices',

        [Alias('Color')]
        [string]$CursorColor = 'BrightCyan',

        [string]$TitleColor,

        [string]$ChoiceColor,

        [string]$GroupColor,

        [string]$HintColor = 'BrightBlack',

        [ValidateRange(1, [int]::MaxValue)]
        [int]$PageSize = 10,

        [ValidateRange(0, [int]::MaxValue)]
        [int]$TimeoutSeconds = 0,

        [ValidateSet('Fold', 'Crop', 'Ellipsis')]
        [string]$Overflow = 'Fold',

        [int]$Row = -1,

        [int]$Column = -1,

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
        $groupFg = if ($GroupColor) { Get-AnsiColorName -Name $GroupColor } else { $null }

        $items = $null
        if ($Grouped) {
            $items = ConvertTo-AnsiGroupedChoices -Items $collected.ToArray() `
                -GroupLabelProperty $GroupLabelProperty -GroupChoicesProperty $GroupChoicesProperty `
                -LabelProperty $LabelProperty -Fg $choiceFg -GroupFg $groupFg `
                -Markdown:$Markdown -Escape:$Escape
        } else {
            $items = ConvertTo-AnsiChoices -Items $collected.ToArray() -LabelProperty $LabelProperty `
                -Fg $choiceFg -Markdown:$Markdown -Escape:$Escape
        }

        # Headers are read, not picked, so they are not in the focus list at all.
        $focus = Get-AnsiChoiceFocus -Rows $items
        if ($focus.Count -eq 0) { throw 'Read-AnsiSelection needs at least one choice.' }

        $index = $focus[0]
        $window = Get-AnsiChoiceWindow -Index $index -Count $items.Count -PageSize $PageSize
        $drawn = 0
        $deadline = if ($TimeoutSeconds -gt 0) { [datetime]::UtcNow.AddSeconds($TimeoutSeconds) } else { $null }

        # Nothing is typed here, and a list that repaints under a blinking cursor
        # reads as flicker. Put back whatever the caller had on the way out.
        # Defined here so they bind to this module's seams, which is what the tests replace.
        $readKey = { Read-AnsiKeyInfo }
        $keyAvailable = { Test-AnsiKeyAvailable }
        $wait = { Start-AnsiWait }
        $stopOn = { param($k) [string]$k.Key -in @('Enter', 'Escape') }

        $cursor = Hide-AnsiCursor
        try {
            while ($true) {
                $rows = Get-AnsiSelectionRows -Title $Title -TitleFg $titleFg -Items $items -Index $index `
                    -Window $window -CursorFg $cursorFg -HintFg $hintFg -NoColor:$noColor `
                    -Ordinal (Get-AnsiChoiceFocusOrdinal -Focus $focus -Index $index) -Total $focus.Count `
                    -Markdown:$Markdown -Escape:$Escape -Overflow $Overflow
                $drawn = Write-AnsiPromptFrame -Rows $rows -Row $Row -Column $Column -Drawn $drawn

                $burst = Wait-AnsiKeyBurst -Deadline $deadline -ReadKey $readKey -KeyAvailable $keyAvailable `
                    -Wait $wait -StopOn $stopOn
                if ($null -eq $burst -or @($burst).Count -eq 0) { return $null }

                # The burst is applied in order, then painted once - but a key that decides has to
                # show the row it landed on before the prompt goes away.
                $decided = $false
                $answer = $null

                foreach ($key in @($burst)) {
                switch ($key.Key) {
                    'UpArrow' { $index = Step-AnsiChoiceFocus -Focus $focus -Index $index -Step -1 }
                    'DownArrow' { $index = Step-AnsiChoiceFocus -Focus $focus -Index $index -Step 1 }
                    'Home' { $index = $focus[0] }
                    'End' { $index = $focus[$focus.Count - 1] }
                    'PageUp' {
                        $index = Get-AnsiChoiceFocusNear -Focus $focus -Direction -1 `
                            -Target ([Math]::Max(0, $index - $window.Size))
                    }
                    'PageDown' {
                        $index = Get-AnsiChoiceFocusNear -Focus $focus -Direction 1 `
                            -Target ([Math]::Min($items.Count - 1, $index + $window.Size))
                    }
                    'Enter' { $decided = $true; $answer = $items[$index].Item }
                    'Escape' { $decided = $true; $answer = $null }
                    default {
                        # k/j move too, for anyone who lives in vi.
                        switch ([char]::ToLowerInvariant($key.KeyChar)) {
                            'k' { $index = Step-AnsiChoiceFocus -Focus $focus -Index $index -Step -1 }
                            'j' { $index = Step-AnsiChoiceFocus -Focus $focus -Index $index -Step 1 }
                        }
                    }
                }

                $window = Get-AnsiChoiceWindow -Index $index -Count $items.Count -PageSize $PageSize -Start $window.Start
                if ($decided) { break }
                }

                if ($decided) {
                    $rows = Get-AnsiSelectionRows -Title $Title -TitleFg $titleFg -Items $items -Index $index `
                        -Window $window -CursorFg $cursorFg -HintFg $hintFg -NoColor:$noColor `
                        -Ordinal (Get-AnsiChoiceFocusOrdinal -Focus $focus -Index $index) -Total $focus.Count `
                        -Markdown:$Markdown -Escape:$Escape -Overflow $Overflow
                    $null = Write-AnsiPromptFrame -Rows $rows -Row $Row -Column $Column -Drawn $drawn
                    return $answer
                }
            }
        } finally {
            Restore-AnsiCursor -State $cursor
        }
    }
}

# Draws title, the visible slice, and a hint row; returns how many rows it wrote so
# the next pass can move back up over them.
function Get-AnsiSelectionRows {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Title,
        [AllowNull()][string]$TitleFg,
        [Parameter(Mandatory)][object[]]$Items,
        [Parameter(Mandatory)][int]$Index,
        [Parameter(Mandatory)][object]$Window,
        [Parameter(Mandatory)][string]$CursorFg,
        [Parameter(Mandatory)][string]$HintFg,
        [int]$Ordinal = 0,
        [int]$Total = 0,
        [switch]$NoColor,
        [switch]$Markdown,
        [switch]$Escape,
        [string]$Overflow = 'Fold'
    )
    # Rows out, not painted: the caller decides whether they land at the cursor or at a cell.
    $rows = [System.Collections.Generic.List[string]]::new()

    $null = $rows.Add((Format-AnsiLine -Runs (Get-AnsiSelectionTitleRuns -Title $Title -Fg $TitleFg `
                -Markdown:$Markdown -Escape:$Escape) -Width 0 -Justify Left -NoColor:$NoColor))

    for ($i = $Window.Start; $i -le $Window.End -and $i -lt $Items.Count; $i++) {
        $prefix = [System.Collections.Generic.List[object]]::new()
        $marker = if ($i -eq $Index) { [string][char]0x203A + ' ' } else { '  ' }   # ›
        $null = $prefix.Add((New-AnsiSelectionRun -Text $marker -Fg $CursorFg))
        if ($Items[$i].Depth -gt 0) {
            $null = $prefix.Add((New-AnsiSelectionRun -Text ('  ' * $Items[$i].Depth) -Fg $null))
        }

        $label = [System.Collections.Generic.List[object]]::new()
        foreach ($r in $Items[$i].Runs) {
            $copy = $r
            if ($i -eq $Index -and -not $r.Fg) {
                $copy = [PSCustomObject]@{
                    Text = $r.Text; Fg = $CursorFg; Bg = $r.Bg; Styles = $r.Styles; Link = $r.Link
                }
            }
            $null = $label.Add($copy)
        }

        foreach ($line in (Split-AnsiChoiceRow -Prefix $prefix.ToArray() -Label $label.ToArray() -Overflow $Overflow)) {
            $null = $rows.Add((Format-AnsiLine -Runs $line -Width 0 -Justify Left -NoColor:$NoColor))
        }
    }

    $hint = ($Items.Count -gt $Window.Size) `
        ? "$Ordinal/$Total  ↑↓ move · enter select · esc cancel" `
        : '↑↓ move · enter select · esc cancel'
    $null = $rows.Add((Format-AnsiLine -Runs @((New-AnsiSelectionRun -Text $hint -Fg $HintFg)) `
                -Width 0 -Justify Left -NoColor:$NoColor))

    return , $rows.ToArray()
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
