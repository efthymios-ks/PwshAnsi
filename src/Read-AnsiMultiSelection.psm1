#Requires -Version 7.2

# Read-AnsiMultiSelection.psm1
# Public: Read-AnsiMultiSelection — tick several items with space, accept with enter.
# Returns the items the caller passed in, or $null on Esc / timeout.
# -Grouped takes headed groups instead of a flat list. A header is shape only until
# -ToggleGroups, which puts it in the cursor's path and makes space set or clear the
# whole group at once — never each member on its own.
# Depends on Ansi.Core.psm1 for markup, colour, cursor control, and input seams.

Import-Module (Join-Path $PSScriptRoot 'Ansi.Core.psm1') -Force -DisableNameChecking

function Read-AnsiMultiSelection {
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

        [Alias('GroupToggle')]
        [switch]$ToggleGroups,

        [object[]]$Selected,

        [Alias('Color')]
        [string]$CursorColor = 'BrightCyan',

        [string]$TitleColor,

        [string]$ChoiceColor,

        [string]$GroupColor,

        [string]$MarkColor = 'BrightGreen',

        [string]$HintColor = 'BrightBlack',

        [ValidateRange(1, [int]::MaxValue)]
        [int]$PageSize = 10,

        [switch]$Required,

        [string]$RequiredMessage = 'Select at least one item.',

        [string]$RequiredColor = 'BrightRed',

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
        if ($collected.Count -eq 0) { throw 'Read-AnsiMultiSelection needs at least one choice.' }
        if ($ToggleGroups -and -not $Grouped) {
            throw 'Read-AnsiMultiSelection -ToggleGroups needs -Grouped: there are no groups to toggle.'
        }
        if (-not (Test-AnsiInteractive)) {
            throw 'Read-AnsiMultiSelection needs an interactive console: input is redirected.'
        }

        $noColor = Test-AnsiNoColor
        $cursorFg = Get-AnsiColorName -Name $CursorColor
        $markFg = Get-AnsiColorName -Name $MarkColor
        $hintFg = Get-AnsiColorName -Name $HintColor
        $requiredFg = Get-AnsiColorName -Name $RequiredColor
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

        # A header is only in the cursor's path when it can be toggled.
        $focus = Get-AnsiChoiceFocus -Rows $items -IncludeGroups:$ToggleGroups
        if ($focus.Count -eq 0) { throw 'Read-AnsiMultiSelection needs at least one choice.' }

        # Pre-ticked items, matched by value against the original objects. Headers
        # hold no tick of their own — theirs is read off their members.
        $ticked = New-Object bool[] $items.Count
        if ($Selected) {
            for ($i = 0; $i -lt $items.Count; $i++) {
                if ($items[$i].IsGroup) { continue }
                foreach ($pre in $Selected) {
                    if ($items[$i].Item -eq $pre) { $ticked[$i] = $true; break }
                }
            }
        }

        $index = $focus[0]
        $window = Get-AnsiChoiceWindow -Index $index -Count $items.Count -PageSize $PageSize
        $drawn = 0
        $note = ''
        $deadline = if ($TimeoutSeconds -gt 0) { [datetime]::UtcNow.AddSeconds($TimeoutSeconds) } else { $null }

        # Keys only, no typing: a blinking cursor would ride every repaint.
        $cursor = Hide-AnsiCursor
        	try {
            while ($true) {
                $drawn = Write-AnsiMultiList -Title $Title -TitleFg $titleFg -Items $items -Ticked $ticked `
                    -Index $index -Window $window -CursorFg $cursorFg -MarkFg $markFg -HintFg $hintFg `
                    -Ordinal (Get-AnsiChoiceFocusOrdinal -Focus $focus -Index $index) -Total $focus.Count `
                    -ToggleGroups:$ToggleGroups `
                    -Note $note -NoteFg $requiredFg -NoColor:$noColor -Markdown:$Markdown -Escape:$Escape `
                    -Redraw ($drawn -gt 0) -Drawn $drawn
                $note = ''

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
                    'Spacebar' { Switch-AnsiMultiTick -Items $items -Ticked $ticked -Index $index }
                    'Escape' { return $null }
                    'Enter' {
                        $chosen = [System.Collections.Generic.List[object]]::new()
                        for ($i = 0; $i -lt $items.Count; $i++) {
                            if ($items[$i].IsGroup) { continue }
                            if ($ticked[$i]) { $null = $chosen.Add($items[$i].Item) }
                        }
                        if ($Required -and $chosen.Count -eq 0) {
                            $note = $RequiredMessage
                            continue
                        }
                        return , $chosen.ToArray()
                    }
                    default {
                        switch ([char]::ToLowerInvariant($key.KeyChar)) {
                            ' ' { Switch-AnsiMultiTick -Items $items -Ticked $ticked -Index $index }
                            'k' { $index = Step-AnsiChoiceFocus -Focus $focus -Index $index -Step -1 }
                            'j' { $index = Step-AnsiChoiceFocus -Focus $focus -Index $index -Step 1 }
                            'a' {
                                # Toggle every item, whatever group it is in: all on
                                # unless everything is already on.
                                $allOn = $true
                                for ($i = 0; $i -lt $items.Count; $i++) {
                                    if ($items[$i].IsGroup) { continue }
                                    if (-not $ticked[$i]) { $allOn = $false; break }
                                }
                                for ($i = 0; $i -lt $items.Count; $i++) {
                                    if ($items[$i].IsGroup) { continue }
                                    $ticked[$i] = -not $allOn
                                }
                            }
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

# One space: an item flips, a group is set whole or cleared whole. A group that is
# already all on clears; anything else fills, so a part-ticked group completes first.
function Switch-AnsiMultiTick {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object[]]$Items,
        [Parameter(Mandatory)][bool[]]$Ticked,
        [Parameter(Mandatory)][int]$Index
    )
    if (-not $Items[$Index].IsGroup) {
        $Ticked[$Index] = -not $Ticked[$Index]
        return
    }
    $fill = (Get-AnsiGroupTickState -Rows $Items -Ticked $Ticked -GroupIndex $Index) -ne 'All'
    for ($i = 0; $i -lt $Items.Count; $i++) {
        if ($Items[$i].Group -eq $Index) { $Ticked[$i] = $fill }
    }
}

function Write-AnsiMultiList {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Title,
        [AllowNull()][string]$TitleFg,
        [Parameter(Mandatory)][object[]]$Items,
        [Parameter(Mandatory)][bool[]]$Ticked,
        [Parameter(Mandatory)][int]$Index,
        [Parameter(Mandatory)][object]$Window,
        [Parameter(Mandatory)][string]$CursorFg,
        [Parameter(Mandatory)][string]$MarkFg,
        [Parameter(Mandatory)][string]$HintFg,
        [int]$Ordinal = 0,
        [int]$Total = 0,
        [switch]$ToggleGroups,
        [AllowEmptyString()][string]$Note = '',
        [AllowNull()][string]$NoteFg,
        [switch]$NoColor,
        [switch]$Markdown,
        [switch]$Escape,
        [bool]$Redraw = $false,
        [int]$Drawn = 0
    )
    if ($Redraw) { Move-AnsiCursorUp -Lines $Drawn }

    $rows = 0
    $check = [string][char]0x2713   # ✓

    Clear-AnsiLine
    Write-Host (Format-AnsiLine -Runs (Get-AnsiMultiTitleRuns -Title $Title -Fg $TitleFg `
                -Markdown:$Markdown -Escape:$Escape) -Width 0 -Justify Left -NoColor:$NoColor)
    $rows++

    for ($i = $Window.Start; $i -le $Window.End -and $i -lt $Items.Count; $i++) {
        $runs = [System.Collections.Generic.List[object]]::new()
        $marker = if ($i -eq $Index) { [string][char]0x203A + ' ' } else { '  ' }
        $null = $runs.Add((New-AnsiMultiRun -Text $marker -Fg $CursorFg))
        if ($Items[$i].Depth -gt 0) {
            $null = $runs.Add((New-AnsiMultiRun -Text ('  ' * $Items[$i].Depth) -Fg $null))
        }

        if ($Items[$i].IsGroup) {
            # A group's box reports its members: all, some, none. Without
            # -ToggleGroups the header carries no box at all — it is a label.
            if ($ToggleGroups) {
                $state = Get-AnsiGroupTickState -Rows $Items -Ticked $Ticked -GroupIndex $i
                $glyph = switch ($state) { 'All' { $check } 'Some' { '-' } default { ' ' } }
                $null = $runs.Add((New-AnsiMultiRun -Text "[$glyph] " `
                            -Fg $(if ($state -eq 'None') { $HintFg } else { $MarkFg })))
            }
        } else {
            $box = if ($Ticked[$i]) { "[$check] " } else { '[ ] ' }
            $null = $runs.Add((New-AnsiMultiRun -Text $box -Fg $(if ($Ticked[$i]) { $MarkFg } else { $HintFg })))
        }

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

    $count = 0
    for ($i = 0; $i -lt $Items.Count; $i++) {
        if (-not $Items[$i].IsGroup -and $Ticked[$i]) { $count++ }
    }
    $hint = "$count selected  ↑↓ move · space toggle · a all · enter accept · esc cancel"
    if ($Items.Count -gt $Window.Size) { $hint = "$Ordinal/$Total  " + $hint }
    Clear-AnsiLine
    Write-Host (Format-AnsiLine -Runs @((New-AnsiMultiRun -Text $hint -Fg $HintFg)) `
            -Width 0 -Justify Left -NoColor:$NoColor)
    $rows++

    # The note row is always drawn, empty or not, so the redraw count stays stable.
    Clear-AnsiLine
    Write-Host (Format-AnsiLine -Runs @((New-AnsiMultiRun -Text $Note -Fg $NoteFg)) `
            -Width 0 -Justify Left -NoColor:$NoColor)
    $rows++

    return $rows
}

function Get-AnsiMultiTitleRuns {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Title,
        [AllowNull()][string]$Fg,
        [switch]$Markdown,
        [switch]$Escape
    )
    if ($Escape) { return , @(New-AnsiMultiRun -Text $Title -Fg $Fg) }
    $runs = ConvertFrom-AnsiMarkup -Text $Title -AsMarkdown:$Markdown
    foreach ($r in $runs) { if (-not $r.Fg) { $r.Fg = $Fg } }
    return , @($runs)
}

function New-AnsiMultiRun {
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

Export-ModuleMember -Function Read-AnsiMultiSelection
