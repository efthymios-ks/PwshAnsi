#Requires -Version 7.2

# Demo-AnsiTitleAnimation.ps1
# Exercises Start-AnsiTitleAnimation, Stop-AnsiTitleAnimation, Invoke-AnsiTitleAnimation.
# Run: pwsh -File .\demo\Demo-AnsiTitleAnimation.ps1
#
# Watch the window title / taskbar entry, not this pane: that is where the dots
# turn. Nothing is animated when output is redirected, so run it in a terminal.

$ErrorActionPreference = 'Stop'
$srcRoot = Join-Path (Split-Path -Parent $PSScriptRoot) 'src'

Import-Module (Join-Path $srcRoot 'Start-AnsiTitleAnimation.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $srcRoot 'Format-AnsiText.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $srcRoot 'Format-AnsiGrid.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $srcRoot 'Format-AnsiPanel.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $srcRoot 'Out-AnsiHost.psm1') -Force -DisableNameChecking

$dots = [string][char]0x280B   # the first of the ten braille frames

function Show-DemoHeader {
    param([string]$Title)
    Write-Host ''
    Write-Host ('─' * 78) -ForegroundColor DarkGray
    Write-Host " $Title" -ForegroundColor Cyan
    Write-Host ('─' * 78) -ForegroundColor DarkGray
}

function Show-Watch {
    param([string]$What)
    # -Escape on the sample: a frame is text, not markup.
    Format-AnsiText 'Watch the title: ' -Color DarkGray | Out-AnsiHost -NoNewline
    Format-AnsiText $What -Escape -Color BrightWhite | Out-AnsiHost
}

# 0. Proof: read the title back while it animates. If these lines change but your
#    title bar does not, the terminal is suppressing application titles rather than
#    the animation failing — in Windows Terminal that is suppressApplicationTitle
#    (or a tabTitle) in the profile.
Show-DemoHeader '0. Self check — what the console actually holds'
$null = Start-AnsiTitleAnimation 'Building' -Speed Fast -Force
$samples = [System.Collections.Generic.List[string]]::new()
foreach ($i in 1..12) {
    try { $null = $samples.Add([Console]::Title) } catch { }
    Start-Sleep -Milliseconds 130
}
Stop-AnsiTitleAnimation
$distinct = @($samples | Select-Object -Unique)
if ($distinct.Count -gt 1) {
    Format-AnsiText "the title took $($distinct.Count) different values:" -Color BrightGreen | Out-AnsiHost
    foreach ($sample in $distinct) {
        Format-AnsiText "  [$sample]" -Escape -Color BrightWhite | Out-AnsiHost
    }
} elseif ($distinct.Count -eq 1) {
    Format-AnsiText 'The title never changed - this host does not report it back' -Color BrightYellow | Out-AnsiHost
} else {
    Format-AnsiText 'This platform cannot read the title back' -Color DarkGray | Out-AnsiHost
}

# 1. The default: the dots turning to the left of the text
Show-DemoHeader '1. The dots turn while your code runs'
Show-Watch "$dots building"
$null = Start-AnsiTitleAnimation 'Building'
Start-Sleep -Seconds 4
Stop-AnsiTitleAnimation

# 2. -FrameLast puts the dots after the text
Show-DemoHeader '2. -FrameLast — dots on the right instead'
Show-Watch "deploying $dots"
$null = Start-AnsiTitleAnimation 'Deploying' -FrameLast
Start-Sleep -Seconds 4
Stop-AnsiTitleAnimation

# 3. -Speed is one of three names, not a number of milliseconds
Show-DemoHeader '3. -Speed Slow / Normal / Fast'
Show-Watch 'The same dots, three speeds'
foreach ($speed in 'Slow', 'Normal', 'Fast') {
    $null = Start-AnsiTitleAnimation $speed.ToLowerInvariant() -Speed $speed
    Start-Sleep -Seconds 3
    Stop-AnsiTitleAnimation
}

# 4. No text at all: just the dots
Show-DemoHeader '4. Text is optional'
Show-Watch "$dots on its own"
$null = Start-AnsiTitleAnimation
Start-Sleep -Seconds 3
Stop-AnsiTitleAnimation

# 5. Invoke wraps a job: animate, run, restore
Show-DemoHeader '5. Invoke-AnsiTitleAnimation wraps a job'
Show-Watch "$dots measuring while the job runs"
$result = Invoke-AnsiTitleAnimation -Text 'Measuring' -ScriptBlock {
    Start-Sleep -Seconds 3
    'The scriptblock result comes straight back'
}
Format-AnsiText "[BrightGreen]$result[/]" | Out-AnsiHost

# 6. The title goes back even when the job throws
Show-DemoHeader '6. The title is restored even when the job fails'
Show-Watch 'Then back to whatever it was'
try {
    Invoke-AnsiTitleAnimation -Text 'Failing' -ScriptBlock {
        Start-Sleep -Seconds 2
        throw 'As planned'
    }
} catch {
    Format-AnsiText "[BrightRed]caught:[/] $($_.Exception.Message)" | Out-AnsiHost
}

# 7. -FinalTitle leaves something useful behind
Show-DemoHeader '7. -FinalTitle'
Show-Watch 'ends on "build done"'
$null = Invoke-AnsiTitleAnimation -Text 'Building' -FinalTitle 'Build done' -ScriptBlock {
    Start-Sleep -Seconds 3
}

# 8. Usage pattern — a long job, with the terminal free to print progress
Show-DemoHeader '8. Usage pattern — a long job that still prints'
Show-Watch "$dots running tests"
$null = Invoke-AnsiTitleAnimation -Text 'Running tests' -Speed Fast -ScriptBlock {
    foreach ($suite in 'Text', 'Table', 'Tree', 'Panel') {
        Format-AnsiGrid @(, @("[DarkGray]suite[/]", "[BrightWhite]$suite[/]", '[BrightGreen]Passed[/]')) `
            -Padding 2 | Out-AnsiHost
        Start-Sleep -Milliseconds 700
    }
}
Format-AnsiPanel 'All suites passed' -Border Square -BorderColor BrightGreen | Out-AnsiHost

Show-DemoHeader 'Done'
Write-Host ''
