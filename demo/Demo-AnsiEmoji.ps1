#Requires -Version 7.2

# Demo-AnsiEmoji.ps1
# Every :name: the library knows, as one large matrix, plus the tokens in use.
# Run: pwsh -File .\demo\Demo-AnsiEmoji.ps1
#
# Piping this strips the colour by design — run it in a terminal. The matrix is
# long: 1430 names, so page it, or filter it with -Filter.
#
# Glyphs are one character to the library but two columns wide in most terminals,
# so the matrix looks a cell wide here and there. Names and layout are exact.

[CmdletBinding()]
param(
    # Only show names matching this wildcard, e.g. -Filter '*heart*'.
    [string]$Filter = '*',

    # Skip the full matrix and show the sections around it.
    [switch]$NoMatrix
)

$ErrorActionPreference = 'Stop'
$srcRoot = Join-Path (Split-Path -Parent $PSScriptRoot) 'src'

Import-Module (Join-Path $srcRoot 'Format-AnsiText.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $srcRoot 'Format-AnsiRule.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $srcRoot 'Format-AnsiGrid.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $srcRoot 'Format-AnsiPanel.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $srcRoot 'Format-AnsiTable.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $srcRoot 'Format-AnsiTree.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $srcRoot 'Out-AnsiHost.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $srcRoot 'Out-AnsiString.psm1') -Force -DisableNameChecking

# Last, on purpose. Every component imports Ansi.Core, and Ansi.Core imports this one
# with -Force — which unloads it and re-imports it nested, taking a global import
# of it down with it. Imported after them, the table's two helpers stay callable
# here. They are internal to the built module; a script that only writes :name:
# tokens never needs them.
Import-Module (Join-Path $srcRoot 'Ansi.Emoji.psm1') -Force -DisableNameChecking

function Show-DemoHeader {
    param([string]$Title)
    Write-Host ''
    Write-Host ('─' * 78) -ForegroundColor DarkGray
    Write-Host " $Title" -ForegroundColor Cyan
    Write-Host ('─' * 78) -ForegroundColor DarkGray
}

$table = Get-AnsiEmojiTable
$names = @($table.Keys | Where-Object { $_ -like $Filter } | Sort-Object)

# 1. What there is
Show-DemoHeader '1. The table'
Format-AnsiTable @(
    [PSCustomObject]@{ Names = $table.Count; Shown = $names.Count; Filter = $Filter }
) -Border Rounded -BorderColor DarkGray -HeaderColor BrightCyan | Out-AnsiHost
Format-AnsiText '[DarkGray]The usual shortcode names, replaced wherever -Markdown is on.[/]' | Out-AnsiHost

# 2. PwshAnsi's own short names
Show-DemoHeader "2. PwshAnsi's own short names come first"
$short = 'check', 'cross', 'warn', 'info', 'star', 'heart', 'arrow', 'bullet',
'fire', 'rocket', 'bug', 'sparkles', 'tada'
Format-AnsiGrid -Items ($short | ForEach-Object { ":${_}: `:$_`:" }) -ColumnCount 4 -Padding 3 -Markdown |
    Out-AnsiHost
Format-AnsiText ('[DarkGray]A short name wins over the same name in the table: :star: is the ' +
    'text star, where the table has ' + $table['star'] + '.[/]') -Markdown | Out-AnsiHost

# 3. The matrix — every name the library knows
if (-not $NoMatrix) {
    Show-DemoHeader "3. The matrix — $($names.Count) names, grouped by first letter"
    foreach ($group in ($names | Group-Object { $_.Substring(0, 1).ToUpperInvariant() })) {
        Format-AnsiRule $group.Name -Alignment Left -LineColor DarkGray -TitleColor BrightCyan | Out-AnsiHost
        # Format-AnsiGrid -Items flows a flat list into as many columns as fit, so the
        # matrix is as wide as the terminal is.
        $cells = foreach ($name in $group.Group) { "$($table[$name]) [DarkGray]$name[/]" }
        Format-AnsiGrid -Items $cells -Padding 2 | Out-AnsiHost
        Write-Host ''
    }
} else {
    Show-DemoHeader '3. The matrix — skipped (-NoMatrix)'
}

# 4. A named page of it
Show-DemoHeader '4. A page of the matrix — fixed columns'
$faces = @($names | Where-Object { $_ -like '*face*' } | Select-Object -First 24)
Format-AnsiGrid -Items ($faces | ForEach-Object { "$($table[$_]) $_" }) -ColumnCount 3 -Padding 2 |
    Out-AnsiHost

# 5. Tokens in the components that take text
Show-DemoHeader '5. Tokens work wherever text does'
Format-AnsiText ':rocket: Deploy, :bug: fix, :sparkles: polish, :tada: ship' -Markdown | Out-AnsiHost
Format-AnsiRule ':check: All green' -Width 60 -Markdown -Alignment Center -LineColor BrightGreen | Out-AnsiHost
Format-AnsiPanel @(
    ':check: Restore, compile, pack'
    ':cross: [BrightRed]Smoke tests failed[/]'
) -Title '[bold]:warning: Build[/]' -Markdown -Border Heavy -BorderColor BrightRed | Out-AnsiHost
Format-AnsiTree @{
    Value    = '[bold]:package: Release[/]'
    Children = @(
        @{ Value = ':check: Tests' }
        @{ Value = ':check: Docs' }
        @{ Value = ':cross: Signature' }
    )
} -Markdown | Out-AnsiHost
Format-AnsiTable @(
    [PSCustomObject]@{ Step = 'Restore'; Result = ':check: Ok' }
    [PSCustomObject]@{ Step = 'Publish'; Result = ':cross: Failed' }
) -Markdown -Border Rounded -BorderColor DarkGray -HeaderColor BrightCyan | Out-AnsiHost

# 6. What the grammar does and does not take
Show-DemoHeader '6. The token grammar'
Format-AnsiText 'Digits are in: :1st_place_medal: :2nd_place_medal: :3rd_place_medal: :keycap_10:' -Markdown |
    Out-AnsiHost
Format-AnsiText 'Case does not matter: :ROCKET: :Grinning_Face: :thumbs_UP:' -Markdown | Out-AnsiHost
Format-AnsiText 'An unknown name is left as written: :not_a_real_emoji:' -Markdown | Out-AnsiHost
Format-AnsiText 'Without -Markdown nothing is replaced: :rocket:' | Out-AnsiHost
Format-AnsiText 'With -Escape nothing is replaced either: :rocket:' -Escape | Out-AnsiHost

# 7. Multi-codepoint names keep every codepoint
Show-DemoHeader '7. Variation selectors are part of the glyph'
$rows = foreach ($name in 'warning', 'information', 'check_mark', 'red_heart', 'airplane') {
    $glyph = $table[$name]
    $codes = @()
    for ($i = 0; $i -lt $glyph.Length; $i++) {
        if ([char]::IsHighSurrogate($glyph[$i]) -and $i + 1 -lt $glyph.Length) {
            $codes += 'U+{0:X4}' -f [char]::ConvertToUtf32($glyph[$i], $glyph[$i + 1])
            $i++
        } else {
            $codes += 'U+{0:X4}' -f [int]$glyph[$i]
        }
    }
    [PSCustomObject]@{ Token = ":${name}:"; Glyph = $glyph; Codepoints = ($codes -join ' ') }
}
Format-AnsiTable $rows -Border Rounded -BorderColor DarkGray -HeaderColor BrightCyan | Out-AnsiHost

# 8. Anchoring — the matrix resumes at the column it started at
Show-DemoHeader '8. Anchoring, and -NoNewline'
Write-Host 'Faces: ' -NoNewline -ForegroundColor DarkGray
Format-AnsiGrid -Items ($faces | Select-Object -First 9 | ForEach-Object { "$($table[$_]) $_" }) `
    -ColumnCount 3 -Padding 2 -MaxWidth 60 | Out-AnsiHost

Write-Host ''
Format-AnsiText ':check: Done' -Markdown | Out-AnsiHost -NoNewline
Write-Host ' ← cursor stayed here' -ForegroundColor DarkGray

# 9. Two panes — left and right
Show-DemoHeader '9. Two panes — left and right'
$left = Format-AnsiGrid -Items (@($names | Where-Object { $_ -like '*cat*' } | Select-Object -First 8) |
        ForEach-Object { "$($table[$_]) $_" }) -ColumnCount 1 -MaxWidth 34 | Out-AnsiString -Plain
$right = Format-AnsiGrid -Items (@($names | Where-Object { $_ -like '*dog*' -or $_ -like '*wolf*' } |
            Select-Object -First 8) | ForEach-Object { "$($table[$_]) $_" }) -ColumnCount 1 -MaxWidth 34 |
    Out-AnsiString -Plain

$paneWidth = 38
for ($i = 0; $i -lt [Math]::Max(@($left).Count, @($right).Count); $i++) {
    $l = if ($i -lt @($left).Count) { @($left)[$i] } else { '' }
    $r = if ($i -lt @($right).Count) { @($right)[$i] } else { '' }
    Format-AnsiText ($l.PadRight($paneWidth)) -Escape -Color BrightWhite | Out-AnsiHost -NoNewline
    Format-AnsiText $r -Escape -Color BrightWhite | Out-AnsiHost
}

# 10. Looking one up from a script
Show-DemoHeader '10. Looking one up'
Format-AnsiText "Get-AnsiEmoji rocket [DarkGray]->[/] $(Get-AnsiEmoji -Name 'rocket')" | Out-AnsiHost
Format-AnsiText "Get-AnsiEmoji nope   [DarkGray]->[/] [DarkGray]<null>[/]" | Out-AnsiHost
Format-AnsiText '[DarkGray]Both helpers are internal to the built module; in src they import from Ansi.Emoji.psm1.[/]' |
    Out-AnsiHost

Show-DemoHeader 'Done'
Write-Host ''
