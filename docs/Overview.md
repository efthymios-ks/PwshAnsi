# Overview

A zero-dependency PowerShell 7.2+ terminal rendering library. Emits its own ANSI,
sources all colours from `$PSStyle`, and honours the caller's cursor position so
wrapped or multi-row output resumes at the anchor column instead of column zero.

- **Runtime:** PowerShell 7.2+ for the full library; PowerShell 5.1 for `Assert-PwshAnsi`
- **Dependencies:** none

## Repository layout

```
PwshAnsi/
├─ src/
│  ├─ Assert-PwshAnsi.psm1        # public: Assert-PwshAnsi — 5.1-safe bootstrap
│  ├─ Ansi.Emoji.psm1             # internal: the :name: emoji table
│  ├─ Ansi.Core.psm1              # internal helpers, imported by each component
│  ├─ Ansi.Input.psm1             # internal: shared input layer for the prompts
│  ├─ Out-AnsiHost.psm1           # public: Out-AnsiHost — paints a rendering
│  ├─ Out-AnsiString.psm1         # public: Out-AnsiString — rendering -> string[]
│  ├─ Format-AnsiText.psm1        # public: Format-AnsiText
│  ├─ Format-AnsiRule.psm1        # public: Format-AnsiRule
│  ├─ Format-AnsiPath.psm1        # public: Format-AnsiPath
│  ├─ Format-AnsiJson.psm1        # public: Format-AnsiJson
│  ├─ Format-AnsiTree.psm1        # public: Format-AnsiTree
│  ├─ Format-AnsiTable.psm1       # public: Format-AnsiTable
│  ├─ Format-AnsiGrid.psm1        # public: Format-AnsiGrid
│  ├─ Format-AnsiPanel.psm1       # public: Format-AnsiPanel
│  ├─ Format-AnsiException.psm1   # public: Format-AnsiException
│  ├─ Read-AnsiText.psm1          # public: Read-AnsiText
│  ├─ Read-AnsiConfirm.psm1       # public: Read-AnsiConfirm
│  ├─ Read-AnsiSelection.psm1     # public: Read-AnsiSelection
│  ├─ Read-AnsiMultiSelection.psm1 # public: Read-AnsiMultiSelection
│  ├─ Read-AnsiPause.psm1         # public: Read-AnsiPause
│  ├─ Format-AnsiProgress.psm1    # public: Format-AnsiProgress
│  ├─ Invoke-AnsiTask.psm1        # public: Invoke-AnsiTask
│  ├─ Start-AnsiTitleAnimation.psm1 # public: Start/Stop/Invoke-AnsiTitleAnimation
│  ├─ Format-AnsiBarChart.psm1    # public: Format-AnsiBarChart
│  └─ Format-AnsiBreakdownChart.psm1 # public: Format-AnsiBreakdownChart
├─ tests/
│  ├─ Assert-PwshAnsi.Tests.ps1   # Pester 5 tests for the bootstrap
│  ├─ Ansi.Emoji.Tests.ps1        # Pester 5 tests for the emoji table
│  ├─ Out-Ansi.Tests.ps1          # Pester 5 tests for both writers
│  ├─ Format-AnsiText.Tests.ps1   # one file per component
│  ├─ Format-AnsiRule.Tests.ps1
│  ├─ Format-AnsiPath.Tests.ps1
│  ├─ Format-AnsiJson.Tests.ps1
│  ├─ Format-AnsiTree.Tests.ps1
│  ├─ Format-AnsiTable.Tests.ps1
│  ├─ Format-AnsiGrid.Tests.ps1
│  ├─ Format-AnsiPanel.Tests.ps1
│  ├─ Format-AnsiException.Tests.ps1
│  ├─ Read-AnsiText.Tests.ps1
│  ├─ Read-AnsiConfirm.Tests.ps1
│  ├─ Read-AnsiSelection.Tests.ps1
│  ├─ Read-AnsiMultiSelection.Tests.ps1
│  ├─ Read-AnsiPause.Tests.ps1
│  ├─ Format-AnsiProgress.Tests.ps1
│  ├─ Invoke-AnsiTask.Tests.ps1
│  ├─ Start-AnsiTitleAnimation.Tests.ps1
│  ├─ Format-AnsiBarChart.Tests.ps1
│  └─ Format-AnsiBreakdownChart.Tests.ps1
├─ demo/
│  ├─ Demo-PwshAnsi.ps1           # showcase of the published module
│  ├─ Demo-AnsiText.ps1           # one demo per component, every parameter
│  ├─ Demo-AnsiRule.ps1
│  ├─ Demo-AnsiPath.ps1
│  ├─ Demo-AnsiJson.ps1
│  ├─ Demo-AnsiTree.ps1
│  ├─ Demo-AnsiTable.ps1
│  ├─ Demo-AnsiGrid.ps1
│  ├─ Demo-AnsiPanel.ps1
│  ├─ Demo-AnsiException.ps1
│  ├─ Demo-ReadAnsiText.ps1       # interactive, one per prompt
│  ├─ Demo-ReadAnsiConfirm.ps1
│  ├─ Demo-ReadAnsiSelection.ps1
│  ├─ Demo-ReadAnsiMultiSelection.ps1
│  ├─ Demo-ReadAnsiPause.ps1
│  ├─ Demo-AnsiProgress.ps1
│  ├─ Demo-AnsiBarChart.ps1
│  ├─ Demo-AnsiBreakdownChart.ps1
│  ├─ Demo-AnsiEmoji.ps1          # every :name: the table knows
│  ├─ Demo-AnsiTask.ps1
│  └─ Demo-AnsiTitleAnimation.ps1
├─ docs/                         # this documentation
├─ Publish-AnsiModule.ps1         # build three-file module + manifest, then publish
├─ artifacts/                    # built module, gitignored
├─ Invoke-Test.ps1               # test runner
└─ README.md
```

Each public function ships as its own `.psm1` and delegates shared work to
`Ansi.Core.psm1`. During development they are imported directly; the build
merges them into `PwshAnsi.Core.ps1`, loaded on 7.2+ by the 5.1-safe loader
`PwshAnsi.psm1`.

## Setup

Install Pester 5 for the test suite (requires pwsh 7.2+):

```powershell
Install-Module Pester -MinimumVersion 5.0.0 -Scope CurrentUser -Force
```

To bootstrap a script so it works from Windows PowerShell 5.1 and always runs on the
latest pwsh with the latest PwshAnsi, see [`Assert-PwshAnsi`](Assert-PwshAnsi.md).

## Import

```powershell
Import-Module .\src\Format-AnsiText.psm1 -Force
Import-Module .\src\Format-AnsiRule.psm1 -Force
Import-Module .\src\Format-AnsiPath.psm1 -Force
Import-Module .\src\Format-AnsiJson.psm1 -Force
Import-Module .\src\Format-AnsiTree.psm1 -Force
Import-Module .\src\Format-AnsiTable.psm1 -Force
Import-Module .\src\Format-AnsiGrid.psm1 -Force
Import-Module .\src\Format-AnsiPanel.psm1 -Force
Import-Module .\src\Format-AnsiException.psm1 -Force
Import-Module .\src\Read-AnsiText.psm1 -Force
Import-Module .\src\Read-AnsiConfirm.psm1 -Force
Import-Module .\src\Read-AnsiSelection.psm1 -Force
Import-Module .\src\Read-AnsiMultiSelection.psm1 -Force
Import-Module .\src\Read-AnsiPause.psm1 -Force
Import-Module .\src\Format-AnsiProgress.psm1 -Force
Import-Module .\src\Invoke-AnsiTask.psm1 -Force
Import-Module .\src\Start-AnsiTitleAnimation.psm1 -Force
Import-Module .\src\Format-AnsiBarChart.psm1 -Force
Import-Module .\src\Format-AnsiBreakdownChart.psm1 -Force
```

Each component module imports `Ansi.Core.psm1` on its own; Core's helpers are not
re-exported. Import `Out-AnsiHost.psm1` (and `Out-AnsiString.psm1` if you want
strings) as well — they are what turn a rendering into output:

```powershell
Import-Module .\src\Out-AnsiHost.psm1 -Force
Import-Module .\src\Out-AnsiString.psm1 -Force
```

## Components

| Component        | Status | Docs                                |
| ---------------- | ------ | ----------------------------------- |
| `Out-AnsiHost`    | built  | [Out-Ansi](Out-Ansi.md)               |
| `Out-AnsiString`  | built  | [Out-Ansi](Out-Ansi.md)               |
| `Format-AnsiText` | built  | [Format-AnsiText](Format-AnsiText.md) |
| `Format-AnsiRule` | built  | [Format-AnsiRule](Format-AnsiRule.md) |
| `Format-AnsiPath` | built  | [Format-AnsiPath](Format-AnsiPath.md) |
| `Format-AnsiJson` | built  | [Format-AnsiJson](Format-AnsiJson.md) |
| `Format-AnsiTree` | built  | [Format-AnsiTree](Format-AnsiTree.md) |
| `Format-AnsiTable` | built | [Format-AnsiTable](Format-AnsiTable.md) |
| `Format-AnsiGrid` | built  | [Format-AnsiGrid](Format-AnsiGrid.md) |
| `Format-AnsiPanel` | built | [Format-AnsiPanel](Format-AnsiPanel.md) |
| `Format-AnsiException` | built | [Format-AnsiException](Format-AnsiException.md) |
| `Read-AnsiText`   | built  | [Read-AnsiText](Read-AnsiText.md)     |
| `Read-AnsiConfirm` | built | [Read-AnsiConfirm](Read-AnsiConfirm.md) |
| `Read-AnsiSelection` | built | [Read-AnsiSelection](Read-AnsiSelection.md) |
| `Read-AnsiMultiSelection` | built | [Read-AnsiMultiSelection](Read-AnsiMultiSelection.md) |
| `Read-AnsiPause`  | built  | [Read-AnsiPause](Read-AnsiPause.md)   |
| `Format-AnsiProgress` | built | [Format-AnsiProgress](Format-AnsiProgress.md) |
| `Invoke-AnsiTask` | built | [Invoke-AnsiTask](Invoke-AnsiTask.md) |
| `Start-AnsiTitleAnimation` | built | [Start-AnsiTitleAnimation](Start-AnsiTitleAnimation.md) |
| `Format-AnsiBarChart` | built | [Format-AnsiBarChart](Format-AnsiBarChart.md) |
| `Format-AnsiBreakdownChart` | built | [Format-AnsiBreakdownChart](Format-AnsiBreakdownChart.md) |
| `Format-AnsiColumns` | dropped | folded into `Format-AnsiGrid -Items` |
| `Format-AnsiRows` | dropped | a one-column `Format-AnsiGrid` |
| `Format-AnsiLayout` | dropped | a six-line zip over captured rows |

## Core contracts

**Anchoring.** The caller positions the cursor; every rendering respects the row
and column it started at. Wrapped or multi-row output resumes at the original
column, never column 0. The default width is `BufferWidth - AnchorColumn`.

**Format, then write.** Every `Format-Ansi*` returns an `[Ansi.Rendering]` — rows of
runs — and writes nothing. `Out-AnsiHost` paints it; `Out-AnsiString` returns
strings. See [Out-Ansi](Out-Ansi.md).

**Colours from `$PSStyle` only.** See [Colours](Colours.md).

**Markup and markdown.** Shared by every component that takes text. See
[Markup and markdown](Markup.md).

**Non-interactive.** `NO_COLOR` set or output redirected → styles stripped,
plain text, identical layout.

## Demos

```powershell
pwsh -File .\demo\Demo-PwshAnsi.ps1
pwsh -File .\demo\Demo-AnsiText.ps1
pwsh -File .\demo\Demo-AnsiRule.ps1
pwsh -File .\demo\Demo-AnsiPath.ps1
pwsh -File .\demo\Demo-AnsiJson.ps1
pwsh -File .\demo\Demo-AnsiTree.ps1
pwsh -File .\demo\Demo-AnsiTable.ps1
pwsh -File .\demo\Demo-AnsiGrid.ps1
pwsh -File .\demo\Demo-AnsiPanel.ps1
pwsh -File .\demo\Demo-AnsiException.ps1
pwsh -File .\demo\Demo-ReadAnsiText.ps1            # interactive
pwsh -File .\demo\Demo-ReadAnsiConfirm.ps1         # interactive
pwsh -File .\demo\Demo-ReadAnsiSelection.ps1       # interactive
pwsh -File .\demo\Demo-ReadAnsiMultiSelection.ps1  # interactive
pwsh -File .\demo\Demo-ReadAnsiPause.ps1           # interactive
pwsh -File .\demo\Demo-AnsiProgress.ps1
pwsh -File .\demo\Demo-AnsiBarChart.ps1
pwsh -File .\demo\Demo-AnsiBreakdownChart.ps1
pwsh -File .\demo\Demo-AnsiEmoji.ps1               # every :name:, as one matrix
pwsh -File .\demo\Demo-AnsiTask.ps1                # redraws in place
pwsh -File .\demo\Demo-AnsiTitleAnimation.ps1      # watch the window title
```

## Build and publish

```powershell
.\Publish-AnsiModule.ps1 -Version 0.1.0
.\Publish-AnsiModule.ps1 -Version 1.0.0 -Publish -NuGetApiKey $key
```

The build produces three files in `artifacts\PwshAnsi\<version>\`:

| File | Description |
| ---- | ----------- |
| `PwshAnsi.psm1` | 5.1-safe loader: `Assert-PwshAnsi` and its helpers, plus a conditional dot-source of `PwshAnsi.Core.ps1` on 7.2+. |
| `PwshAnsi.Core.ps1` | All other components merged in order. Dot-sourced by the loader; may use any pwsh 7.2 syntax. |
| `PwshAnsi.psd1` | Manifest: `PowerShellVersion = '5.1'`, `CompatiblePSEditions = 'Desktop','Core'`, full `FunctionsToExport`. |

Per-file `#Requires`, sibling `Import-Module` lines, and each `Export-ModuleMember`
are stripped before merging. `Ansi.Core`'s and `Ansi.Emoji`'s helpers stay internal.

| Parameter       | Meaning                                                        |
| --------------- | -------------------------------------------------------------- |
| `-Version`      | Version to stamp. Required.                                    |
| `-OutputPath`   | Where to build. Default `.rtifacts`.                         |
| `-Publish`      | Publish after building; prompts unless `-Force`.               |
| `-Repository`   | Target repository. Default `PSGallery`.                        |
| `-NuGetApiKey`  | Falls back to `$env:PSGALLERY_KEY`.                            |
| `-SkipTests`    | Build without running the suite first.                         |
| `-Force`        | Overwrite an existing build, and publish without prompting.    |

The build refuses to run if the suite fails, if a `src\*.psm1` is missing from the
build order, if the merged file does not parse, if the manifest is invalid, or if
the built module does not import and render.

## Tests

Pester 5 tests live in `tests/`, one `*.Tests.ps1` per public function.

```powershell
pwsh -File .\Invoke-Test.ps1
```

`Invoke-Test.ps1` installs Pester 5 for the current user if it is missing, runs
everything under `tests/`, and exits non-zero if anything fails.

| Parameter      | Meaning                                                   |
| -------------- | --------------------------------------------------------- |
| `-Path`        | Folder or file to run. Default `./tests`.                 |
| `-Output`      | `None`/`Normal`/`Detailed`/`Diagnostic`. Default `Detailed`. |
| `-TestName`    | Wildcard filter over full test names.                     |
| `-ResultPath`  | Write NUnit XML results to this path.                     |
| `-Tag`         | Only run tests carrying one of these tags.                |
| `-SkipInstall` | Fail instead of installing Pester when it is missing.     |

Exit codes: `0` passed · `1` failures · `2` no tests discovered · `3` Pester 5
unavailable.

```powershell
pwsh -File .\Invoke-Test.ps1 -TestName '*-Overflow*' -Output Normal
pwsh -File .\Invoke-Test.ps1 -ResultPath .\testResults.xml
```
