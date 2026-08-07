#Requires -Version 7.2

# Demo-AnsiTask.ps1
# Exercises every Invoke-AnsiTask parameter, section by section.
# Run: pwsh -File .\demo\Demo-AnsiTask.ps1
#
# Invoke-AnsiTask redraws in place, so run it in a terminal: piping it gives you the
# finished lines only, which is what a CI log should get.

$ErrorActionPreference = 'Stop'
$srcRoot = Join-Path (Split-Path -Parent $PSScriptRoot) 'src'

Import-Module (Join-Path $srcRoot 'Invoke-AnsiTask.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $srcRoot 'Format-AnsiText.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $srcRoot 'Format-AnsiTable.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $srcRoot 'Format-AnsiPanel.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $srcRoot 'Out-AnsiHost.psm1') -Force -DisableNameChecking

function Show-DemoHeader {
    param([string]$Title)
    Write-Host ''
    Write-Host ('─' * 78) -ForegroundColor DarkGray
    Write-Host " $Title" -ForegroundColor Cyan
    Write-Host ('─' * 78) -ForegroundColor DarkGray
}

# 1. One step
Show-DemoHeader '1. One step: a name and a scriptblock'
Invoke-AnsiTask 'Restoring packages' { Start-Sleep -Milliseconds 900 }

# 2. Several steps, with the bar counting them
Show-DemoHeader '2. Several steps — the bar counts them'
Invoke-AnsiTask -Task @(
    @{ Name = 'Restore'; Script = { Start-Sleep -Milliseconds 700 } }
    @{ Name = 'Build'; Script = { Start-Sleep -Milliseconds 1100 } }
    @{ Name = 'Test'; Script = { Start-Sleep -Milliseconds 900 } }
    @{ Name = 'Package'; Script = { Start-Sleep -Milliseconds 500 } }
)

# 3. -Show Text — no bar, just the lines
Show-DemoHeader '3. -Show Text — a line per step, nothing else'
Invoke-AnsiTask -Show Text -Task @(
    @{ Name = 'Checkout'; Script = { Start-Sleep -Milliseconds 400 } }
    @{ Name = 'Restore'; Script = { Start-Sleep -Milliseconds 400 } }
)

# 4. -Show Bar — the bar alone
Show-DemoHeader '4. -Show Bar — the bar alone, kept at the end'
Invoke-AnsiTask -Show Bar -KeepBar -Task @(
    @{ Name = 'One'; Script = { Start-Sleep -Milliseconds 500 } }
    @{ Name = 'Two'; Script = { Start-Sleep -Milliseconds 500 } }
    @{ Name = 'Three'; Script = { Start-Sleep -Milliseconds 500 } }
)

# 5. Progress inside a step
Show-DemoHeader '5. $task.Update() — progress the runner cannot count itself'
Invoke-AnsiTask 'Copying 40 files' {
    param($task)
    foreach ($i in 1..40) {
        Start-Sleep -Milliseconds 45
        $task.Update($i, 40)
    }
}

# 6. A step that says something as it goes
Show-DemoHeader '6. $task.Write() — a note above the bar'
Invoke-AnsiTask -Task @(
    @{
        Name   = 'Migrating'
        Script = {
            param($task)
            foreach ($table in 'Users', 'Orders', 'Invoices') {
                Start-Sleep -Milliseconds 500
                $task.Write("migrated $table")
            }
        }
    }
    @{ Name = 'Verifying'; Script = { Start-Sleep -Milliseconds 600 } }
)

# 7. A step that fails
Show-DemoHeader '7. A failing step stops the run and rethrows'
try {
    Invoke-AnsiTask -Task @(
        @{ Name = 'Compile'; Script = { Start-Sleep -Milliseconds 500 } }
        @{ Name = 'Link'; Script = { Start-Sleep -Milliseconds 400; throw 'Undefined symbol: main' } }
        @{ Name = 'Sign'; Script = { Start-Sleep -Milliseconds 400 } }
    )
} catch {
    Format-AnsiText "[BrightRed]caught:[/] $($_.Exception.Message)" | Out-AnsiHost
}

# 8. -ContinueOnError with -PassThru
Show-DemoHeader '8. -ContinueOnError and -PassThru'
$results = Invoke-AnsiTask -ContinueOnError -PassThru -Task @(
    @{ Name = 'Unit'; Script = { Start-Sleep -Milliseconds 500 } }
    @{ Name = 'Integration'; Script = { Start-Sleep -Milliseconds 400; throw 'Database unreachable' } }
    @{ Name = 'Smoke'; Script = { Start-Sleep -Milliseconds 400 } }
)
$rows = $results | ForEach-Object {
    [PSCustomObject]@{
        Step   = $_.Name
        Result = if ($_.Ok) { '[BrightGreen]Passed[/]' } else { '[BrightRed]Failed[/]' }
        Took   = [string]::Format([cultureinfo]::InvariantCulture, '{0:0.0}s', $_.Duration.TotalSeconds)
    }
}
Format-AnsiTable $rows -Border Rounded -BorderColor DarkGray -HeaderColor BrightCyan | Out-AnsiHost

# 9. Styles and colours
Show-DemoHeader '9. -Style and the bar colours'
Invoke-AnsiTask -Show Bar -KeepBar -Style Ascii -BarColor BrightGreen -EmptyColor DarkGray -Task @(
    @{ Name = 'a'; Script = { Start-Sleep -Milliseconds 400 } }
    @{ Name = 'b'; Script = { Start-Sleep -Milliseconds 400 } }
)
Invoke-AnsiTask -Show Bar -KeepBar -Style Line -Width 40 -BarColor BrightMagenta -Task @(
    @{ Name = 'a'; Script = { Start-Sleep -Milliseconds 400 } }
    @{ Name = 'b'; Script = { Start-Sleep -Milliseconds 400 } }
)

# 10. The whole thing as a release run
Show-DemoHeader '10. Usage pattern — a release run'
$release = Invoke-AnsiTask -PassThru -Width 60 -BarColor BrightCyan -Task @(
    @{ Name = 'Clean'; Script = { Start-Sleep -Milliseconds 400 } }
    @{
        Name   = 'Build'
        Script = {
            param($task)
            foreach ($project in 1..6) {
                Start-Sleep -Milliseconds 200
                $task.Update($project, 6)
            }
        }
    }
    @{ Name = 'Test'; Script = { Start-Sleep -Milliseconds 800 } }
    @{ Name = 'Publish'; Script = { Start-Sleep -Milliseconds 600 } }
)
$total = [TimeSpan]::FromTicks(($release | Measure-Object -Property { $_.Duration.Ticks } -Sum).Sum)
Format-AnsiPanel ([string]::Format([cultureinfo]::InvariantCulture,
        '{0} steps in {1:0.0}s', $release.Count, $total.TotalSeconds)) `
    -Border Square -BorderColor BrightGreen | Out-AnsiHost

Show-DemoHeader 'Done'
Write-Host ''
