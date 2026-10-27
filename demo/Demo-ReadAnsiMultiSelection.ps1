#Requires -Version 7.2

# Demo-ReadAnsiMultiSelection.ps1
# Exercises Read-AnsiMultiSelection. Interactive: it waits for your keys.
# Run: pwsh -File .\demo\Demo-ReadAnsiMultiSelection.ps1
# One section: pwsh -File .\demo\Demo-ReadAnsiMultiSelection.ps1 -Case 1
#
# ↑↓ (or k/j) Move · Space Toggles · A Toggles All · Enter Accepts ·
# Esc Cancels and returns $null. Add your own with -Hotkeys.

param(
    # Run only these sections, by number: -Case 3b. Every section by default.
    [string[]]$Case
)

$ErrorActionPreference = 'Stop'
$srcRoot = Join-Path (Split-Path -Parent $PSScriptRoot) 'src'

Import-Module (Join-Path $srcRoot 'Read-AnsiMultiSelection.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $srcRoot 'Format-AnsiGrid.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $srcRoot 'Format-AnsiPanel.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $srcRoot 'Format-AnsiTable.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $srcRoot 'Out-AnsiHost.psm1') -Force -DisableNameChecking

. (Join-Path $PSScriptRoot 'Demo.Core.ps1')

function Show-Answers {
    param([string]$Label, [AllowNull()][object]$Value)
    $shown = ''
    if ($null -eq $Value) {
        $shown = '[BrightBlack]<Null — cancelled or timed out>[/]'
    } else {
        $joined = (@($Value) -join ', ')
        $shown = if ([string]::IsNullOrEmpty($joined)) { '[BrightBlack]<Nothing selected>[/]' } else { "[BrightWhite]$joined[/]" }
    }
    Format-AnsiGrid @(, @("[DarkGray]$Label[/]", $shown)) -Padding 2 | Out-AnsiHost
}

$suites = @('Text', 'Rule', 'Path', 'JSON', 'Tree', 'Table', 'Grid', 'Panel')
$components = @(
    [PSCustomObject]@{ Name = 'Format-AnsiText'; Tests = 147 }
    [PSCustomObject]@{ Name = 'Format-AnsiTable'; Tests = 79 }
    [PSCustomObject]@{ Name = 'Format-AnsiTree'; Tests = 69 }
    [PSCustomObject]@{ Name = 'Format-AnsiPanel'; Tests = 68 }
)

# Used by more than one section.
$grouped = @(
    @{ Name = 'Formatters'; Choices = @('Text', 'Rule', 'Path', 'JSON') }
    @{ Name = 'Layout'; Choices = @('Table', 'Grid', 'Panel', 'Tree') }
    @{ Name = 'Prompts'; Choices = @('Selection', 'Confirm', 'Text') }
)

# 1. Tick a few — space toggles, enter accepts
Invoke-DemoCase '1' 'Tick a few (space, then enter)' {
    $picked = Read-AnsiMultiSelection 'Which suites?' $suites
    Show-Answers 'Suites' $picked
}

# 2. Toggle everything with a
Invoke-DemoCase '2' 'Press a to select all (again to clear)' {
    $all = Read-AnsiMultiSelection 'Which suites?' $suites
    Show-Answers 'Suites' $all
}

# 3. Start with some already ticked
Invoke-DemoCase '3' '-Selected pre-ticks items' {
    $pre = Read-AnsiMultiSelection 'Which suites?' $suites -Selected 'Text', 'Table'
    Show-Answers 'Suites' $pre
}

# 4. Paging
Invoke-DemoCase '4' '-PageSize 4 (the window scrolls with the cursor)' {
    $paged = Read-AnsiMultiSelection 'Which suites?' $suites -PageSize 4
    Show-Answers 'Suites' $paged
}

# 5. -Required refuses an empty selection
Invoke-DemoCase '5' '-Required (press enter with nothing ticked first)' {
    $required = Read-AnsiMultiSelection 'Which suites?' $suites -Required -RequiredMessage 'Pick at least one'
    Show-Answers 'Suites' $required
}

# 6. Objects — labelled by a property, the objects come back
Invoke-DemoCase '6' '-LabelProperty (returns the objects)' {
    $chosen = Read-AnsiMultiSelection 'Which components?' $components -LabelProperty Name
    if ($null -ne $chosen -and @($chosen).Count -gt 0) {
        Format-AnsiTable @($chosen) -Border Square -BorderColor DarkGray -HeaderColor BrightWhite -Align Left, Right |
            Out-AnsiHost
    } else {
        Show-Answers 'Components' $chosen
    }
}

# 7. Colours — cursor, tick, title, rest of the list
Invoke-DemoCase '7' '-CursorColor / -MarkColor / -TitleColor / -ChoiceColor' {
    $coloured = Read-AnsiMultiSelection 'Which suites?' $suites `
        -CursorColor BrightMagenta -MarkColor BrightYellow -TitleColor BrightWhite -ChoiceColor DarkGray
    Show-Answers 'Suites' $coloured
}

# 8. A timeout
Invoke-DemoCase '8' '-TimeoutSeconds 5' {
    $timed = Read-AnsiMultiSelection 'Quick, tick some' $suites -TimeoutSeconds 5
    Show-Answers 'Suites' $timed
}

# 9. Groups, view only — headers give the list shape, the cursor skips them
Invoke-DemoCase '9' '-Grouped (headers are view only)' {
    $fromGroups = Read-AnsiMultiSelection 'Which suites?' $grouped -Grouped -GroupColor BrightYellow
    Show-Answers 'Suites' $fromGroups
}

# 10. Groups you can toggle — space on a header sets or clears the whole group
Invoke-DemoCase '10' '-ToggleGroups (space on a header sets or clears it all)' {
    $toggled = Read-AnsiMultiSelection 'Which suites?' $grouped -Grouped -ToggleGroups `
        -GroupColor BrightYellow -Selected 'Table', 'Grid'
    Show-Answers 'Suites' $toggled
}

# 11. Group-Object output, straight in — name the property the members live under
Invoke-DemoCase '11' '-Grouped over Group-Object (-GroupChoicesProperty Group)' {
    $byTests = $components | Group-Object { if ($_.Tests -ge 70) { 'Heavily tested' } else { 'Lightly tested' } }
    $picked2 = Read-AnsiMultiSelection 'Which components?' $byTests -Grouped -ToggleGroups `
        -GroupChoicesProperty Group -LabelProperty Name
    Show-Answers 'Components' $(if ($null -ne $picked2) { @($picked2).Name } else { $null })
}

# 12. -Hotkeys — add extra keys on top of the built-ins (try I to invert every tick)
Invoke-DemoCase '12' '-Hotkeys (I inverts every tick)' {
    $hotkeys = @(
        @{ Key = 'i'; Description = 'Invert'; Action = {
                param($s)
                for ($i = 0; $i -lt $s.Ticked.Length; $i++) { $s.Ticked[$i] = -not $s.Ticked[$i] }
                $s.Note = 'inverted'
            } }
    )
    $inverted = Read-AnsiMultiSelection 'Which suites?' $suites -Hotkeys $hotkeys -Selected 'Text', 'Table'
    Show-Answers 'Suites' $inverted
}

# 13. Usage pattern — the selection drives what runs next
Invoke-DemoCase '13' 'Usage pattern — run only what was ticked' {
    $run = Read-AnsiMultiSelection 'Run which steps?' @('Restore', 'Build', 'Test', 'Pack') -Selected 'Build', 'Test'
    if ($null -eq $run) {
        Format-AnsiPanel 'Cancelled' -Border Square -BorderColor DarkGray | Out-AnsiHost
    } else {
        $rows = @()
        foreach ($step in @('Restore', 'Build', 'Test', 'Pack')) {
            $state = if (@($run) -contains $step) { '[BrightGreen]Will run[/]' } else { '[BrightBlack]Skipped[/]' }
            $rows += , @("[DarkGray]$step[/]", $state)
        }
        $plan = Format-AnsiGrid $rows -Padding 3 -MaxWidth 40
        Format-AnsiPanel $plan -Title 'Plan' -BorderColor BrightBlue | Out-AnsiHost
    }
}

Complete-Demo
