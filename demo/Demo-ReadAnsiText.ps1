#Requires -Version 7.2

# Demo-ReadAnsiText.ps1
# Exercises Read-AnsiText. Interactive: it waits for your keys.
# Run: pwsh -File .\demo\Demo-ReadAnsiText.ps1
# One section: pwsh -File .\demo\Demo-ReadAnsiText.ps1 -Case 1
#
# Esc cancels any prompt and returns $null; a -TimeoutSeconds prompt returns $null
# when it expires.

param(
    # Run only these sections, by number: -Case 3b. Every section by default.
    [string[]]$Case
)

$ErrorActionPreference = 'Stop'
$srcRoot = Join-Path (Split-Path -Parent $PSScriptRoot) 'src'

Import-Module (Join-Path $srcRoot 'Read-AnsiText.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $srcRoot 'Format-AnsiGrid.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $srcRoot 'Format-AnsiPanel.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $srcRoot 'Out-AnsiHost.psm1') -Force -DisableNameChecking

. (Join-Path $PSScriptRoot 'Demo.Core.ps1')

function Show-Answer {
    param([string]$Label, [AllowNull()][object]$Value)
    $shown = if ($null -eq $Value) { '[BrightBlack]<Null — cancelled or timed out>[/]' }
    elseif ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
        $joined = (@($Value) -join ', ')
        if ([string]::IsNullOrEmpty($joined)) { '[BrightBlack]<Nothing selected>[/]' } else { "[BrightWhite]$joined[/]" }
    } else { "[BrightWhite]$Value[/]" }
    Format-AnsiGrid @(, @("[DarkGray]$Label[/]", $shown)) -Padding 2 | Out-AnsiHost
}

# 1. A plain question
Invoke-DemoCase '1' 'Read-AnsiText — a plain question' {
    $name = Read-AnsiText 'Your name'
    Show-Answer 'Name' $name
}

# 2. A default answer, taken by pressing Enter
Invoke-DemoCase '2' '-Default (press Enter to take it)' {
    $branch = Read-AnsiText 'Branch' -Default 'main'
    Show-Answer 'Branch' $branch
}

# 3. Markup and markdown in the prompt, plus a coloured answer
Invoke-DemoCase '3' 'Markup in the prompt, -AnswerColor for the answer' {
    $env = Read-AnsiText '[bold]Environment[/] :rocket:' -Markdown -Default 'Dev' -AnswerColor BrightGreen
    Show-Answer 'Environment' $env
}

# 4. Masked input
Invoke-DemoCase '4' '-Secret masks what you type' {
    $secret = Read-AnsiText 'API key' -Secret
    Show-Answer 'API key length' $(if ($null -eq $secret) { $null } else { $secret.Length })
}

# 5. Validation — re-prompts until the answer passes
Invoke-DemoCase '5' '-Validate (digits only, try letters first)' {
    $port = Read-AnsiText 'Port' -Validate { param($v) $v -match '^\d+$' } -ValidationMessage 'Digits only, please'
    Show-Answer 'Port' $port
}

# 6. Empty answers
Invoke-DemoCase '6' '-AllowEmpty (just press Enter)' {
    $note = Read-AnsiText 'Note (optional)' -AllowEmpty
    Show-Answer 'Note' $note
}

# 7. A timeout
Invoke-DemoCase '7' '-TimeoutSeconds 5 (wait it out to see $null)' {
    $quick = Read-AnsiText 'Quick, say something' -TimeoutSeconds 5
    Show-Answer 'Quick' $quick
}

Complete-Demo
