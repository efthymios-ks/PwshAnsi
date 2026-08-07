# PwshAnsi

A zero-dependency PowerShell 7.2+ terminal rendering library. `Format-Ansi*` builds
a renderable; `Out-AnsiHost` paints it, `Out-AnsiString` turns it into strings.

## Contents

- [Overview](docs/Overview.md) — setup, runtime, layout, import, core contracts, demos, tests
- [Out-AnsiHost / Out-AnsiString](docs/Out-Ansi.md) — the rendering object and the two writers
- [Colours](docs/Colours.md) — the shared colour vocabulary and `NO_COLOR`
- [Markup and markdown](docs/Markup.md) — tags, sugar, emoji, escaping
- [`Format-AnsiText`](docs/Format-AnsiText.md) — styled text with anchoring, wrapping, and truncation
- [`Format-AnsiRule`](docs/Format-AnsiRule.md) — horizontal rule with an optional title
- [`Format-AnsiPath`](docs/Format-AnsiPath.md) — filesystem paths with per-part colour and middle truncation
- [`Format-AnsiJson`](docs/Format-AnsiJson.md) — pretty-printed JSON with per-token colour
- [`Format-AnsiTree`](docs/Format-AnsiTree.md) — hierarchies with box-drawing guides
- [`Format-AnsiTable`](docs/Format-AnsiTable.md) — objects as a bordered, sized table
- [`Format-AnsiGrid`](docs/Format-AnsiGrid.md) — borderless grid; also flows a flat list into columns
- [`Format-AnsiPanel`](docs/Format-AnsiPanel.md) — frames text, or another rendering's output, in a titled box
- [`Format-AnsiException`](docs/Format-AnsiException.md) — errors with type, position, frames, and inner exceptions
- [`Format-AnsiProgress`](docs/Format-AnsiProgress.md) — a progress bar as a rendering
- [`Format-AnsiBarChart`](docs/Format-AnsiBarChart.md) — labelled values as scaled bars
- [`Format-AnsiBreakdownChart`](docs/Format-AnsiBreakdownChart.md) — one bar split by share, with a legend
- [`Read-AnsiText`](docs/Read-AnsiText.md) — prompt for a line of text
- [`Read-AnsiConfirm`](docs/Read-AnsiConfirm.md) — prompt for yes or no
- [`Read-AnsiSelection`](docs/Read-AnsiSelection.md) — pick one item with the arrow keys
- [`Read-AnsiMultiSelection`](docs/Read-AnsiMultiSelection.md) — tick several items
- [`Read-AnsiPause`](docs/Read-AnsiPause.md) — wait for a key before carrying on
- [`Invoke-AnsiTask`](docs/Invoke-AnsiTask.md) — run steps behind live text and a progress bar
- [`Start-AnsiTitleAnimation`](docs/Start-AnsiTitleAnimation.md) — turn the braille dots in the window title while a job runs

## Setup

```powershell
# from any shell, including Windows PowerShell 5.1
powershell -ExecutionPolicy Bypass -File .\Install-AnsiPrerequisite.ps1
```

Checks for PowerShell 7.2+ and Pester 5.x, installs what is missing, and renders a
line with PwshAnsi to prove it works. `-WhatIf` reports without installing, `-Force`
answers yes. Exit codes: `0` ready · `1` a step failed · `2` still missing.

## Test

```powershell
pwsh -File .\Invoke-Test.ps1                        # the whole suite
pwsh -File .\Invoke-Test.ps1 -TestName '*AnsiTable*' # one component
pwsh -File .\Invoke-Test.ps1 -Path .\tests\Out-Ansi.Tests.ps1
pwsh -File .\Invoke-Test.ps1 -ResultPath .\testResults.xml -Output Normal
```

Installs Pester 5 for the current user if it is missing, runs everything under
`tests\`, and exits non-zero if anything fails. Exit codes: `0` passed · `1`
failures · `2` no tests discovered · `3` Pester 5 unavailable.

## Run the demos

Each component has a demo that exercises every parameter, numbered section by
section. Run them in a terminal — piping strips the colour by design.

```powershell
pwsh -File .\demo\Demo-AnsiText.ps1
pwsh -File .\demo\Demo-AnsiRule.ps1
pwsh -File .\demo\Demo-AnsiPath.ps1
pwsh -File .\demo\Demo-AnsiJson.ps1
pwsh -File .\demo\Demo-AnsiTree.ps1
pwsh -File .\demo\Demo-AnsiTable.ps1
pwsh -File .\demo\Demo-AnsiGrid.ps1
pwsh -File .\demo\Demo-AnsiPanel.ps1
pwsh -File .\demo\Demo-AnsiException.ps1
pwsh -File .\demo\Demo-AnsiProgress.ps1
pwsh -File .\demo\Demo-AnsiBarChart.ps1
pwsh -File .\demo\Demo-AnsiBreakdownChart.ps1
pwsh -File .\demo\Demo-AnsiEmoji.ps1             # every :name:, as one matrix
pwsh -File .\demo\Demo-AnsiTask.ps1              # redraws in place
pwsh -File .\demo\Demo-AnsiTitleAnimation.ps1   # watch the window title
```

The prompt demos wait for your keys:

```powershell
pwsh -File .\demo\Demo-ReadAnsiText.ps1
pwsh -File .\demo\Demo-ReadAnsiConfirm.ps1
pwsh -File .\demo\Demo-ReadAnsiSelection.ps1
pwsh -File .\demo\Demo-ReadAnsiMultiSelection.ps1
pwsh -File .\demo\Demo-ReadAnsiPause.ps1
```

## Build and publish

```powershell
pwsh -File .\Publish-AnsiModule.ps1 -Version 0.1.0                    # build only
pwsh -File .\Publish-AnsiModule.ps1 -Version 1.0.0 -Publish -NuGetApiKey $key
```

The suite runs first: a red test stops the script before anything is built or
published, and `-SkipTests` is refused together with `-Publish`. The build
concatenates `src\*.psm1` into
`artifacts\PwshAnsi\<version>\PwshAnsi.psm1` with a manifest beside it,
then imports it and renders with it before finishing.

| Parameter      | Meaning                                                     |
| -------------- | ----------------------------------------------------------- |
| `-Version`     | Version to stamp. Required.                                 |
| `-OutputPath`  | Where to build. Default `.\artifacts`.                      |
| `-Publish`     | Publish after building; prompts unless `-Force`.             |
| `-Repository`  | Target repository. Default `PSGallery`.                     |
| `-NuGetApiKey` | Falls back to `$env:PSGALLERY_KEY`.                         |
| `-SkipTests`   | Build without the suite. Cannot be combined with `-Publish`. |
| `-Force`       | Overwrite an existing build, and publish without prompting.  |

## Release

`.github/workflows/publish.yml` runs on a version tag, and the tag is the version:
`v0.3.0` publishes `0.3.0`, `v0.4.0-beta1` publishes `0.4.0` as prerelease `beta1`.
It calls the same script — suite, build, validate, publish — with the API key from
the `PSGALLERY_KEY` secret, and keeps the build as a run artifact.

```powershell
git tag v0.3.0 && git push origin v0.3.0
```

`workflow_dispatch` takes a version instead, for a re-run without a new tag.

Import a build without publishing it:

```powershell
Import-Module .\artifacts\PwshAnsi\0.1.0\PwshAnsi.psd1 -Force
```
