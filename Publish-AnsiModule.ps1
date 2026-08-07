#Requires -Version 7.2

<#
.SYNOPSIS
    Builds src\*.psm1 into one PwshAnsi module, then optionally publishes it.

.DESCRIPTION
    Concatenates the source modules into a single PwshAnsi.psm1, writes a
    manifest beside it, validates both, imports the built module and renders with
    it, and — only when asked — publishes to a repository.

    A DLL is not an option: PowerShell script cannot be compiled to IL, so a
    binary module would mean rewriting the library in C#. One aggregate .psm1 is
    both the simpler and the faster-loading answer.

    Concatenation order is Ansi.Core, then the writers, then the components, then
    the prompts, because everything resolves in one module scope once merged. Per
    file `#Requires`, `Import-Module` of a sibling, and `Export-ModuleMember` lines
    are dropped; one Export-ModuleMember for the public surface is appended.

    The suite runs first, before anything is gathered or built: if a test fails the
    script stops there, so a red suite can never produce a build or a publish.

    Exit codes:
      0  built (and published, if asked)
      1  a step failed

.PARAMETER Version
    Module version to stamp. Required. A prerelease suffix is allowed — 1.2.0-beta1
    is stamped as ModuleVersion 1.2.0 with Prerelease beta1, which is what the
    gallery reads.

.PARAMETER OutputPath
    Where to build. Default .rtifacts.

.PARAMETER Repository
    Repository to publish to. Default PSGallery. Only used with -Publish.

.PARAMETER NuGetApiKey
    API key for -Publish. Falls back to $env:PSGALLERY_KEY.

.PARAMETER Publish
    Publish after building. Prompts unless -Force.

.PARAMETER SkipTests
    Do not run the Pester suite. Refused together with -Publish: a published build
    has to be a tested build.

.PARAMETER Force
    Overwrite an existing build, and publish without prompting.

.EXAMPLE
    .\Publish-AnsiModule.ps1 -Version 0.1.0

.EXAMPLE
    .\Publish-AnsiModule.ps1 -Version 1.0.0 -Publish -NuGetApiKey $key
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory, Position = 0)]
    [ValidatePattern('^\d+\.\d+\.\d+(-[A-Za-z0-9.]+)?$')]
    [string]$Version,

    [string]$OutputPath = (Join-Path $PSScriptRoot 'artifacts'),

    [string]$Repository = 'PSGallery',

    [string]$NuGetApiKey,

    [switch]$Publish,

    [switch]$SkipTests,

    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Stable identity across builds: a new GUID would look like a different module.
$script:ModuleName = 'PwshAnsi'
$script:ModuleGuid = 'f44b45f3-3692-4bdd-8ab3-7cee7f9841d8'

# ModuleVersion takes three numbers and nothing else, so 1.2.0-beta1 is stamped as
# 1.2.0 with beta1 in PrivateData.PSData.Prerelease — which is what the gallery
# reads to list it as a prerelease.
$script:ModuleVersion = $Version
$script:Prerelease = ''
if ($Version -match '^(?<base>\d+\.\d+\.\d+)-(?<pre>[A-Za-z0-9.]+)$') {
    $script:ModuleVersion = $Matches['base']
    $script:Prerelease = $Matches['pre']
}

# Concatenation order. Core first: a class-free script still has to define helpers
# before the functions that call them run, and the writers are used by nothing at
# load time but read best next to Core.
$script:InternalModule = @('Ansi.Core.psm1', 'Ansi.Emoji.psm1')

$script:BuildOrder = @(
    'Ansi.Emoji.psm1'
    'Ansi.Core.psm1'
    'Out-AnsiHost.psm1'
    'Out-AnsiString.psm1'
    'Format-AnsiText.psm1'
    'Format-AnsiRule.psm1'
    'Format-AnsiPath.psm1'
    'Format-AnsiJson.psm1'
    'Format-AnsiTree.psm1'
    'Format-AnsiTable.psm1'
    'Format-AnsiGrid.psm1'
    'Format-AnsiPanel.psm1'
    'Format-AnsiException.psm1'
    'Read-AnsiText.psm1'
    'Read-AnsiConfirm.psm1'
    'Read-AnsiSelection.psm1'
    'Read-AnsiMultiSelection.psm1'
    'Read-AnsiPause.psm1'
    'Format-AnsiProgress.psm1'
    'Invoke-AnsiTask.psm1'
    'Start-AnsiTitleAnimation.psm1'
    'Format-AnsiBarChart.psm1'
    'Format-AnsiBreakdownChart.psm1'
)

function Write-Step {
    param([Parameter(Mandatory)][string]$Message)
    Write-Host ''
    Write-Host "== $Message" -ForegroundColor Cyan
}

function Write-Good {
    param([Parameter(Mandatory)][string]$Message)
    Write-Host "   [ok]   $Message" -ForegroundColor Green
}

function Write-Note {
    param([Parameter(Mandatory)][string]$Message)
    Write-Host "          $Message" -ForegroundColor DarkGray
}

function Exit-WithError {
    param([Parameter(Mandatory)][string]$Message)
    Write-Host "   [fail] $Message" -ForegroundColor Red
    exit 1
}

# Everything a merged file must not keep: version guards, sibling imports, and the
# per-file export list.
function Get-MergedBody {
    param([Parameter(Mandatory)][string]$Path)

    $lines = Get-Content -LiteralPath $Path
    $kept = [System.Collections.Generic.List[string]]::new()
    $inExport = $false

    foreach ($line in $lines) {
        if ($inExport) {
            # Export-ModuleMember continues while lines end with a comma or backtick.
            if ($line -notmatch '[,`]\s*$') { $inExport = $false }
            continue
        }
        if ($line -match '^\s*#Requires\b') { continue }
        if ($line -match "^\s*Import-Module\s+\(Join-Path\s+\`$PSScriptRoot") { continue }
        if ($line -match '^\s*#\s*No -Force: a re-import would swap') { continue }
        if ($line -match '^\s*Export-ModuleMember\b') {
            $inExport = ($line -match '[,`]\s*$')
            continue
        }
        $null = $kept.Add($line)
    }

    return ($kept -join [System.Environment]::NewLine).Trim()
}

# The public surface, read from each file's own Export-ModuleMember so the built
# manifest cannot drift from the source.
function Get-PublicFunction {
    param([Parameter(Mandatory)][string]$Path)

    $text = Get-Content -LiteralPath $Path -Raw
    $match = [regex]::Match($text, '(?ms)^\s*Export-ModuleMember\s+-Function\s+(?<list>.*?)(?=\r?\n\s*\r?\n|\z)')
    if (-not $match.Success) { return @() }

    $list = $match.Groups['list'].Value
    $list = $list -replace '`\s*\r?\n', ' '
    $names = $list -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^[A-Za-z]+-[A-Za-z]+$' }
    return @($names)
}

# --- gather ---------------------------------------------------------------------

Write-Host ''
Write-Host "$script:ModuleName $Version" -ForegroundColor White

$srcRoot = Join-Path $PSScriptRoot 'src'
if (-not (Test-Path -LiteralPath $srcRoot)) { Exit-WithError "no src folder at $srcRoot" }

# --- tests ----------------------------------------------------------------------
# First, always: nothing is gathered, built, or published until the suite is green.

Write-Step 'tests'

if ($SkipTests -and $Publish) {
    Exit-WithError '-SkipTests cannot be combined with -Publish: a published build must be tested'
}

if ($SkipTests) {
    Write-Note 'skipped (-SkipTests) — build only, publishing is refused'
} else {
    $runner = Join-Path $PSScriptRoot 'Invoke-Test.ps1'
    if (-not (Test-Path -LiteralPath $runner)) { Exit-WithError "no test runner at $runner" }

    & $runner -Output None | Out-Host
    if ($LASTEXITCODE -ne 0) {
        Exit-WithError "tests failed (exit $LASTEXITCODE) — nothing was built or published"
    }
    Write-Good 'suite green'
}

Write-Step 'sources'
$sourceFiles = [System.Collections.Generic.List[string]]::new()
foreach ($name in $script:BuildOrder) {
    $path = Join-Path $srcRoot $name
    if (-not (Test-Path -LiteralPath $path)) { Exit-WithError "missing source: $name" }
    $null = $sourceFiles.Add($path)
}

# Anything in src that the build order forgot would silently not ship.
$onDisk = @(Get-ChildItem -LiteralPath $srcRoot -Filter '*.psm1' | Select-Object -ExpandProperty Name)
$missed = @($onDisk | Where-Object { $script:BuildOrder -notcontains $_ })
if ($missed.Count -gt 0) { Exit-WithError "not in the build order: $($missed -join ', ')" }
Write-Good "$($sourceFiles.Count) modules, in order"

# Ansi.Core exports its helpers so the component modules can use them; merged into
# one scope they are simply internal, so they stay out of the public surface.
$publicFunctions = [System.Collections.Generic.List[string]]::new()
foreach ($path in $sourceFiles) {
    if ((Split-Path -Leaf $path) -in $script:InternalModule) { continue }
    foreach ($name in (Get-PublicFunction -Path $path)) {
        if (-not $publicFunctions.Contains($name)) { $null = $publicFunctions.Add($name) }
    }
}
if ($publicFunctions.Count -eq 0) { Exit-WithError 'found no exported functions' }
Write-Good "$($publicFunctions.Count) public functions: $($publicFunctions -join ', ')"

# --- build ----------------------------------------------------------------------

$moduleRoot = Join-Path (Join-Path $OutputPath $script:ModuleName) $script:ModuleVersion
$psm1Path = Join-Path $moduleRoot "$script:ModuleName.psm1"
$psd1Path = Join-Path $moduleRoot "$script:ModuleName.psd1"

Write-Step "build -> $moduleRoot"

if (Test-Path -LiteralPath $moduleRoot) {
    if (-not ($Force -or $PSCmdlet.ShouldProcess($moduleRoot, 'Overwrite existing build'))) {
        Exit-WithError 'build folder exists; pass -Force to overwrite'
    }
    Remove-Item -LiteralPath $moduleRoot -Recurse -Force
}
$null = New-Item -ItemType Directory -Path $moduleRoot -Force

$header = @"
#Requires -Version 7.2

# $script:ModuleName $Version
# Built from src\*.psm1 by Publish-AnsiModule.ps1 — do not edit this file.
# Format-Ansi* build an [Ansi.Rendering]; Out-AnsiHost paints it, Out-AnsiString
# turns it into strings. Read-Ansi* are the prompts.
"@

$parts = [System.Collections.Generic.List[string]]::new()
$null = $parts.Add($header)
foreach ($path in $sourceFiles) {
    $name = Split-Path -Leaf $path
    $null = $parts.Add("#region $name")
    $null = $parts.Add((Get-MergedBody -Path $path))
    $null = $parts.Add("#endregion $name")
}
$null = $parts.Add("Export-ModuleMember -Function $($publicFunctions -join ', ')")

$newline = [System.Environment]::NewLine
Set-Content -LiteralPath $psm1Path -Value (($parts -join ($newline * 2)) + $newline) -Encoding utf8NoBOM
Write-Good "$([System.IO.Path]::GetFileName($psm1Path)) — $((Get-Item -LiteralPath $psm1Path).Length) bytes"

$manifest = @{
    Path              = $psd1Path
    RootModule        = "$script:ModuleName.psm1"
    ModuleVersion     = $script:ModuleVersion
    GUID              = $script:ModuleGuid
    Author            = 'Efthymios Koktsidis'
    CompanyName       = 'Efthymios Koktsidis'
    Copyright         = "(c) $([datetime]::UtcNow.Year) Efthymios Koktsidis. All rights reserved."
    Description       = 'Zero-dependency terminal rendering for PowerShell: text, rules, paths, JSON, trees, tables, grids, panels, exceptions, bar and breakdown charts, and prompts. Format-Ansi* builds a renderable, Out-AnsiHost paints it.'
    PowerShellVersion = '7.2'
    FunctionsToExport = @($publicFunctions)
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    Tags              = @('Console', 'Terminal', 'ANSI', 'Rendering', 'Table', 'Tree', 'Chart', 'Emoji', 'Prompt', 'TUI')
    ProjectUri        = 'https://github.com/efthymios-ks/PwshAnsi'
    LicenseUri        = 'https://github.com/efthymios-ks/PwshAnsi/blob/main/LICENSE'
    ReleaseNotes      = "$script:ModuleName $Version"
}
if ($script:Prerelease) { $manifest.Prerelease = $script:Prerelease }
New-ModuleManifest @manifest
Write-Good "$([System.IO.Path]::GetFileName($psd1Path))$(if ($script:Prerelease) { " — prerelease $script:Prerelease" })"

# --- validate -------------------------------------------------------------------

Write-Step 'validate'

$errors = $null
$null = [System.Management.Automation.Language.Parser]::ParseFile($psm1Path, [ref]$null, [ref]$errors)
if ($errors -and $errors.Count -gt 0) {
    Exit-WithError "built module does not parse: line $($errors[0].Extent.StartLineNumber): $($errors[0].Message)"
}
Write-Good 'parses'

try {
    $null = Test-ModuleManifest -Path $psd1Path -ErrorAction Stop
} catch {
    Exit-WithError "manifest is not valid: $($_.Exception.Message)"
}
Write-Good 'manifest is valid'

# Import the built module in a child session, so this one keeps the src modules.
$check = @"
`$ErrorActionPreference = 'Stop'
Import-Module '$psd1Path' -Force
`$exported = (Get-Module '$script:ModuleName').ExportedFunctions.Keys | Sort-Object
if (`$exported.Count -ne $($publicFunctions.Count)) {
    throw "exported `$(`$exported.Count) functions, expected $($publicFunctions.Count)"
}
Format-AnsiTable @(
    [PSCustomObject]@{ Module = '$script:ModuleName'; Version = '$Version'; Functions = `$exported.Count }
) -Border Rounded | Out-AnsiHost
Format-AnsiText '[bold BrightGreen]built module renders.[/]' | Out-AnsiHost
"@
& (Get-Process -Id $PID).Path -NoProfile -NoLogo -Command $check | Out-Host
if ($LASTEXITCODE -ne 0) { Exit-WithError 'built module failed to import or render' }
Write-Good 'imports and renders'

# --- publish --------------------------------------------------------------------

if (-not $Publish) {
    Write-Host ''
    Write-Host "Built $script:ModuleName $Version" -ForegroundColor Green
    Write-Note "import: Import-Module '$psd1Path' -Force"
    Write-Note "publish: .\Publish-AnsiModule.ps1 -Version $Version -Publish -NuGetApiKey <key>"
    Write-Host ''
    exit 0
}

Write-Step "publish -> $Repository"

$key = $NuGetApiKey
if (-not $key) { $key = $env:PSGALLERY_KEY }
if (-not $key) { Exit-WithError 'no API key: pass -NuGetApiKey or set $env:PSGALLERY_KEY' }

if (-not ($Force -or $PSCmdlet.ShouldProcess("$script:ModuleName $Version", "Publish to $Repository"))) {
    Write-Note 'declined — nothing was published'
    exit 0
}

try {
    Publish-Module -Path $moduleRoot -Repository $Repository `
        -NuGetApiKey $key -Force -ErrorAction Stop
} catch {
    Exit-WithError "publish failed: $($_.Exception.Message)"
}

Write-Good "published $script:ModuleName $Version to $Repository"
Write-Host ''
exit 0
