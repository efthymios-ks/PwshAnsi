# Format-AnsiProgress

A progress bar as an `[Ansi.Rendering]`: an optional label, a bar, and an optional
suffix on one row. `Out-AnsiHost` paints it, `Out-AnsiString` turns it into strings.

```powershell
Format-AnsiProgress 40 | Out-AnsiHost
Format-AnsiProgress 3 'Restore' -Total 7 -Show Count -BarColor BrightGreen | Out-AnsiHost
```

```
Restore ████████████░░░░░░░░░░░░░░░░░░   40%
```

It draws one state of one bar; it does not animate. Redrawing over time is
[`Invoke-AnsiTask`](Invoke-AnsiTask.md)'s job, which paints these.

## Parameters

```powershell
Format-AnsiProgress [-Value] <double> [[-Label] <string>] [-Total <double>]
                   [-Width <int>] [-BarWidth <int>] [-LabelWidth <int>]
                   [-Show <Percent|Count|Both|None>]
                   [-Style <Blocks|Line|Dots|Ascii>]
                   [-BarColor <c>] [-EmptyColor <c>] [-LabelColor <c>]
                   [-SuffixColor <c>] [-CompleteColor <c>] [-Markdown] [-Escape]
```

| Parameter        | Default   | Description                                                     |
| ---------------- | --------- | --------------------------------------------------------------- |
| `-Value`         | required  | How far along, in `-Total` units. Takes the pipeline.            |
| `-Total`         | `100`     | What counts as finished.                                         |
| `-Label`         | none      | Text before the bar. Markup unless `-Escape`.                    |
| `-Width`         | anchor    | Whole row: label, bar, and suffix together.                      |
| `-BarWidth`      | what's left | The bar itself, whatever the label costs.                      |
| `-LabelWidth`    | `0`       | Pad the label so a column of bars lines up.                      |
| `-Show`          | `Percent` | What trails the bar.                                             |
| `-Style`         | `Blocks`  | Which characters the bar is drawn with.                          |
| `-BarColor`      | none      | The filled part. `-Color` is an alias.                           |
| `-EmptyColor`    | none      | The remainder.                                                   |
| `-LabelColor`    | none      | The label, where its own markup does not say otherwise.          |
| `-SuffixColor`   | none      | The percent or count.                                            |
| `-CompleteColor` | none      | Replaces `-BarColor` once `-Value` reaches `-Total`.             |

## The bar

Whole cells only — no partial blocks. The same value always draws the same bar, and
a terminal without a good font shows the shape a fancy one does.

Two ends are guarded, because the shape is what gets read:

- **Never full short of the total.** 99 out of 100 across 20 cells rounds to 20;
  it draws 19, because a full bar means finished.
- **Never empty past zero.** 1 out of 1000 rounds to 0; it draws one cell, because
  an empty bar means nothing has happened yet.

Values outside `0..Total` are clamped, so a caller that overshoots its own total
still gets a sensible bar.

| `-Style` | Filled | Empty |
| -------- | ------ | ----- |
| `Blocks` | `█`    | `░`   |
| `Line`   | `━`    | `─`   |
| `Dots`   | `●`    | `·`   |
| `Ascii`  | `#`    | `-`   |

## The suffix

| `-Show`   | Example    |
| --------- | ---------- |
| `Percent` | `  40%`    |
| `Count`   | `  3/7`    |
| `Both`    | `  3/7   43%` |
| `None`    | nothing    |

The percent is right-aligned to four columns and the count is padded to the width
of `-Total`, so the bar does not shift as the numbers grow. Whole numbers stay
whole, fractions keep one decimal, and both are formatted invariantly — `1.5/4`
reads the same on a comma locale as on a dot one.

## Width

Like every component, the default width runs from the cursor to the right edge, so
a bar written at column 20 stops at the same place as one written at column 0.

`-Width` sets the whole row. `-BarWidth` sets the bar itself and lets the row grow
past `-Width` if the label demands it — that is what keeps a column of bars aligned
when the labels differ in length:

```powershell
Format-AnsiProgress 55 'Short' -BarWidth 20 -LabelWidth 14
Format-AnsiProgress 55 'A much longer label' -BarWidth 20 -LabelWidth 14
```

## Colour

Colours come from the shared vocabulary — see [Colours](Colours.md). Under
`NO_COLOR` or redirected output the layout is unchanged and the styling is dropped.

`-CompleteColor` only takes over at the total, so a bar can run yellow and land
green without the caller branching:

```powershell
Format-AnsiProgress $done $name -Total $all -BarColor BrightYellow -CompleteColor BrightGreen
```

## Nesting

It is a rendering, so it goes wherever one goes — a panel's content, a grid cell, a
table cell, a tree label:

```powershell
Format-AnsiPanel @(
    Format-AnsiProgress 100 'Restore' -BarWidth 24 -LabelWidth 9 -BarColor BrightGreen
    Format-AnsiProgress 62  'Build'   -BarWidth 24 -LabelWidth 9 -BarColor BrightYellow
) -Title 'Pipeline' -Border Rounded | Out-AnsiHost
```

## Demo

```powershell
pwsh -File .\demo\Demo-AnsiProgress.ps1
```

Values, `-Total` units, labels and `-LabelWidth`, every `-Show` and `-Style`, the
colours including `-CompleteColor`, `-BarWidth`, the guarded ends, bars nested in a
panel, a grid and a table, and two panes side by side.

## Tests

`tests/Format-AnsiProgress.Tests.ps1` — 46 Pester 5 tests covering the fill
arithmetic and both guarded ends, clamping, fractional values, the pipeline, all
four styles, label markup and `-Escape`, every suffix and its padding, the anchor
and each width parameter, all five colours and `NO_COLOR`, and nesting in a panel
and a grid.

```powershell
pwsh -File .\Invoke-Test.ps1 -Path .\tests\Format-AnsiProgress.Tests.ps1
```
