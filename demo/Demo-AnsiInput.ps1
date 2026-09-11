#Requires -Version 7.2

# Demo-AnsiInput.ps1
# Exercises the input layer the Read-Ansi* prompts share. Interactive: it waits for your keys.
# Run: pwsh -File .\demo\Demo-AnsiInput.ps1
#
# What to try in each section is printed above the prompt - the caret keys, a paste
# (Ctrl+V), a label too long for the window, and a prompt painted at a cell you name.

$ErrorActionPreference = 'Stop'
$srcRoot = Join-Path (Split-Path -Parent $PSScriptRoot) 'src'

Import-Module (Join-Path $srcRoot 'Read-AnsiText.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $srcRoot 'Read-AnsiConfirm.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $srcRoot 'Read-AnsiSelection.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $srcRoot 'Read-AnsiMultiSelection.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $srcRoot 'Format-AnsiGrid.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $srcRoot 'Format-AnsiText.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $srcRoot 'Out-AnsiHost.psm1') -Force -DisableNameChecking

function Show-DemoHeader {
    param([string]$Title)
    Write-Host ''
    Write-Host ('─' * 78) -ForegroundColor DarkGray
    Write-Host " $Title" -ForegroundColor Cyan
    Write-Host ('─' * 78) -ForegroundColor DarkGray
}

function Show-DemoHint {
    param([string]$Text)
    Format-AnsiText "[BrightBlack]$Text[/]" | Out-AnsiHost
}

function Show-Answer {
    param([string]$Label, [AllowNull()][object]$Value)
    $shown = if ($null -eq $Value) {
        '[BrightBlack]<Null — cancelled or timed out>[/]'
    } elseif ($Value -is [array]) {
        "[BrightWhite]$($Value -join ', ')[/]"
    } else {
        "[BrightWhite]$Value[/]"
    }
    Format-AnsiGrid @(, @("[DarkGray]$Label[/]", $shown)) -Padding 2 | Out-AnsiHost
}

# A label long enough to need folding, and one that asks for its own break.
$branches = @(
    'users/chouliaras/features/4352315592_complimentary_gold_card'
    'users/koktsidise/4525962983_set_pass_email_blob_retention_policy'
    'develop'
)
$actions = foreach ($branch in $branches) {
    [PSCustomObject]@{
        Name  = $branch
        Label = "Delete branch $branch`n[DarkGray]Not yours (someone@example.com), can delete[/]"
    }
}

Show-DemoHeader 'The caret'
Show-DemoHint 'Type, then ← → to move the caret and insert mid-text; Backspace removes what is before it.'
Show-Answer 'Answer' (Read-AnsiText 'Branch')

Show-DemoHeader 'Scrolling sideways'
Show-DemoHint 'Paste or type past the right edge: the field scrolls and the caret stays on screen.'
Show-DemoHint 'Narrow the window first to see it in a few characters.'
Show-Answer 'Path' (Read-AnsiText 'Path' -Default 'C:\Users\you\Documents\a\rather\long\path\that\will\not\fit')

Show-DemoHeader 'Masked, with the same caret'
Show-DemoHint 'The caret and the arrows work the same; only the echo is stars.'
Show-Answer 'Secret' (Read-AnsiText 'API key' -Secret)

Show-DemoHeader 'A paste is one repaint'
Show-DemoHint 'Ctrl+V several lines: the burst is drawn once, and each line break is kept, shown as 
.'
Show-DemoHint 'Only the Enter you type yourself answers.'
Show-Answer 'Pasted' (Read-AnsiText 'Paste here' -AllowEmpty)

Show-DemoHeader 'Choices that do not fit'
Show-DemoHint 'Each label folds under its own first character, and the hard break puts the detail on line two.'
$picked = Read-AnsiSelection 'Which branch?' $actions -LabelProperty Label
Show-Answer 'Picked' $picked.Name

Show-DemoHeader 'The same list, ellipsised instead'
Show-DemoHint '-Overflow Ellipsis keeps one row per choice.'
$picked = Read-AnsiSelection 'Which branch?' $actions -LabelProperty Label -Overflow Ellipsis
Show-Answer 'Picked' $picked.Name

Show-DemoHeader 'Ticking the folded list'
Show-DemoHint 'Space toggles, a ticks everything; the folded rows stay lined up as the cursor moves.'
$ticked = Read-AnsiMultiSelection 'Which branches?' $actions -LabelProperty Label
Show-Answer 'Ticked' @($ticked | ForEach-Object { $_.Name })

# Cleared first: a positioned write lands on whatever is already on those cells.
Clear-Host
Show-DemoHeader 'Painted where you say'
Show-DemoHint 'The question below is drawn at row 6, column 30 - one synchronized write, not at the cursor.'
$confirmed = Read-AnsiConfirm 'Placed over here?' -Row 6 -Column 30
try { [Console]::SetCursorPosition(0, 8) } catch { }
Show-Answer 'Confirmed' $confirmed

Write-Host ''
