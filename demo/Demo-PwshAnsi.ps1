#Requires -Version 7.2

# Demo-PwshAnsi.ps1
# A showcase of PwshAnsi installed from the PowerShell Gallery.
# Run: pwsh -File "$env:USERPROFILE\Desktop\Demo-PwshAnsi.ps1"

$ErrorActionPreference = 'Stop'
Import-Module PwshAnsi -MinimumVersion 0.0.1 -Force

# ── helpers ───────────────────────────────────────────────────────────────────

function Show-Section {
    param([string]$Title)
    Write-Host ''
    Format-AnsiRule -Title " $Title " -LineColor BrightCyan -TitleColor BrightWhite | Out-AnsiHost
}

# ── 1. Banner ─────────────────────────────────────────────────────────────────

Write-Host ''
Format-AnsiRule -LineColor BrightBlue | Out-AnsiHost
Format-AnsiText '  [bold BrightWhite]PwshAnsi[/]  [BrightBlack]·[/]  [BrightCyan]Zero-dependency terminal rendering for PowerShell[/]' | Out-AnsiHost
Format-AnsiRule -LineColor BrightBlue | Out-AnsiHost

# ── 2. Styled text ────────────────────────────────────────────────────────────

Show-Section 'Styled Text'

Format-AnsiText '[bold BrightYellow]Bold[/]  [italic BrightGreen]Italic[/]  [underline BrightMagenta]Underline[/]  [strikethrough BrightRed]Strike[/]  [reverse]Reverse[/]' | Out-AnsiHost
Format-AnsiText '**Markdown** *sugar* __underline__ ~~strike~~ `code` :check: :cross: :rocket: :fire:' -Markdown | Out-AnsiHost

# ── 3. Module status table ────────────────────────────────────────────────────

Show-Section 'Module Components'

$components = @(
    [PSCustomObject]@{ Component = 'Format-AnsiText';           Tests = 147; Status = '[BrightGreen]:check: Pass[/]' }
    [PSCustomObject]@{ Component = 'Format-AnsiRule';           Tests = 78;  Status = '[BrightGreen]:check: Pass[/]' }
    [PSCustomObject]@{ Component = 'Format-AnsiPath';           Tests = 64;  Status = '[BrightGreen]:check: Pass[/]' }
    [PSCustomObject]@{ Component = 'Format-AnsiJson';           Tests = 67;  Status = '[BrightGreen]:check: Pass[/]' }
    [PSCustomObject]@{ Component = 'Format-AnsiTree';           Tests = 68;  Status = '[BrightGreen]:check: Pass[/]' }
    [PSCustomObject]@{ Component = 'Format-AnsiTable';          Tests = 78;  Status = '[BrightGreen]:check: Pass[/]' }
    [PSCustomObject]@{ Component = 'Format-AnsiPanel';          Tests = 55;  Status = '[BrightGreen]:check: Pass[/]' }
    [PSCustomObject]@{ Component = 'Format-AnsiException';      Tests = 42;  Status = '[BrightGreen]:check: Pass[/]' }
    [PSCustomObject]@{ Component = 'Format-AnsiBarChart';       Tests = 61;  Status = '[BrightGreen]:check: Pass[/]' }
    [PSCustomObject]@{ Component = 'Format-AnsiBreakdownChart'; Tests = 48;  Status = '[BrightGreen]:check: Pass[/]' }
    [PSCustomObject]@{ Component = 'Format-AnsiProgress';       Tests = 39;  Status = '[BrightGreen]:check: Pass[/]' }
)

$total = ($components | Measure-Object -Property Tests -Sum).Sum
$rows  = @($components | Select-Object Component, Tests, Status) +
         @([PSCustomObject]@{ Component = '[bold]Total[/]'; Tests = $total; Status = '' })

Format-AnsiTable $rows `
    -Markdown `
    -Align Left, Right, Left `
    -Border Rounded `
    -BorderColor DarkGray `
    -HeaderColor BrightWhite | Out-AnsiHost

# ── 4. Bar chart — test distribution ─────────────────────────────────────────

Show-Section 'Test Distribution (Bar Chart)'

Format-AnsiBarChart -Data (
    $components | Select-Object -First 6 | ForEach-Object {
        [PSCustomObject]@{ Label = ($_.Component -replace '^Format-Ansi', ''); Value = $_.Tests }
    }
) -LabelColor BrightCyan -ValueColor BrightWhite -BarColor BrightBlue -Width 60 | Out-AnsiHost

# ── 5. Breakdown chart ────────────────────────────────────────────────────────

Show-Section 'Test Share (Breakdown Chart)'

Format-AnsiBreakdownChart -Data @(
    [PSCustomObject]@{ Label = 'Text';  Value = 147; Color = 'BrightBlue'    }
    [PSCustomObject]@{ Label = 'Rule';  Value = 78;  Color = 'BrightGreen'   }
    [PSCustomObject]@{ Label = 'Table'; Value = 78;  Color = 'BrightYellow'  }
    [PSCustomObject]@{ Label = 'Tree';  Value = 68;  Color = 'BrightMagenta' }
    [PSCustomObject]@{ Label = 'Json';  Value = 67;  Color = 'BrightCyan'    }
    [PSCustomObject]@{ Label = 'Path';  Value = 64;  Color = 'BrightRed'     }
    [PSCustomObject]@{ Label = 'Other'; Value = 125; Color = 'BrightBlack'   }
) -Width 60 | Out-AnsiHost

# ── 6. Tree ───────────────────────────────────────────────────────────────────

Show-Section 'Module Tree'

Format-AnsiTree @{
    Value    = '[bold BrightWhite]PwshAnsi[/]'
    Children = @(
        @{
            Value    = '[BrightCyan]Rendering[/]'
            Children = @(
                @{ Value = 'Format-AnsiText' }
                @{ Value = 'Format-AnsiRule' }
                @{ Value = 'Format-AnsiPanel' }
                @{ Value = 'Format-AnsiTable' }
                @{ Value = 'Format-AnsiTree' }
                @{ Value = 'Format-AnsiGrid' }
            )
        }
        @{
            Value    = '[BrightGreen]Data[/]'
            Children = @(
                @{ Value = 'Format-AnsiJson' }
                @{ Value = 'Format-AnsiPath' }
                @{ Value = 'Format-AnsiException' }
            )
        }
        @{
            Value    = '[BrightYellow]Charts[/]'
            Children = @(
                @{ Value = 'Format-AnsiBarChart' }
                @{ Value = 'Format-AnsiBreakdownChart' }
                @{ Value = 'Format-AnsiProgress' }
            )
        }
        @{
            Value    = '[BrightMagenta]Prompts[/]'
            Children = @(
                @{ Value = 'Read-AnsiText' }
                @{ Value = 'Read-AnsiConfirm' }
                @{ Value = 'Read-AnsiSelection' }
                @{ Value = 'Read-AnsiMultiSelection' }
                @{ Value = 'Read-AnsiPause' }
            )
        }
    )
} | Out-AnsiHost

# ── 7. JSON ───────────────────────────────────────────────────────────────────

Show-Section 'JSON Rendering'

$json = @{
    name         = 'PwshAnsi'
    version      = '0.0.1'
    psVersion    = '7.2+'
    dependencies = @()
    tags         = @('Console', 'Terminal', 'ANSI', 'TUI')
    published    = $true
} | ConvertTo-Json

Format-AnsiJson $json -MaxWidth 50 | Out-AnsiHost

# ── 8. Path ───────────────────────────────────────────────────────────────────

Show-Section 'Path Rendering'

Format-AnsiPath $PROFILE      | Out-AnsiHost
Format-AnsiPath $PSScriptRoot | Out-AnsiHost

# ── 9. Panel ──────────────────────────────────────────────────────────────────

Show-Section 'Panel'

$panelText = Format-AnsiText 'A zero-dependency PowerShell rendering library. Supports text, rules, tables, trees, charts, panels, exceptions, prompts, and more — all with ANSI colour.' -MaxWidth 54 -Color BrightWhite

Format-AnsiPanel `
    -Data $panelText `
    -Title ' PwshAnsi ' `
    -TitleColor BrightYellow `
    -BorderColor BrightBlue `
    -Border Rounded `
    -Width 60 | Out-AnsiHost

# ── 10. Exception ─────────────────────────────────────────────────────────────

Show-Section 'Exception Rendering'

$record = $null
try { [int]::Parse('not-a-number') } catch { $record = $_ }
Format-AnsiException $record | Out-AnsiHost

# ── 11. Footer ────────────────────────────────────────────────────────────────

Write-Host ''
Format-AnsiRule -LineColor BrightBlue | Out-AnsiHost
Format-AnsiText '  :check: [bold BrightGreen]Demo complete.[/]  Install: [BrightCyan]Install-Module PwshAnsi[/]' -Markdown | Out-AnsiHost
Format-AnsiRule -LineColor BrightBlue | Out-AnsiHost
Write-Host ''
