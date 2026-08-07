# Format-AnsiBreakdownChart

A breakdown chart as an `[Ansi.Rendering]`: one bar split between the parts by share,
then a legend naming each of them. `Out-AnsiHost` paints it, `Out-AnsiString` turns it
into strings.

```powershell
$fruit = @(
    [PSCustomObject]@{ Label = 'Apples'; Value = 12; Color = 'BrightGreen' }
    [PSCustomObject]@{ Label = 'Oranges'; Value = 5; Color = 'Yellow' }
    [PSCustomObject]@{ Label = 'Bananas'; Value = 2.2 }
)
Format-AnsiBreakdownChart $fruit -Width 50 | Out-AnsiHost
```

```
██████████████████████████████████░░░░░░░░░░░░░░░░
█ Apples 12   █ Oranges 5   █ Bananas 2.2
```

There is no chart-item type to build first: the data is plain objects, the same way
[`Format-AnsiTable`](Format-AnsiTable.md) takes rows. Same data, same shapes as
[`Format-AnsiBarChart`](Format-AnsiBarChart.md) — one compares values, this one splits
a whole.

## Parameters

```powershell
Format-AnsiBreakdownChart [-Data] <object[]> [[-Width] <int>]
                         [-HideTags] [-HideTagValues] [-ShowPercentage] [-FullSize]
                         [-Style <Blocks|Line|Dots|Ascii>] [-ValueFormat <string>]
                         [-Palette <c[]>] [-TagColor <c>] [-ValueColor <c>]
                         [-LabelProperty <string>] [-ValueProperty <string>]
                         [-ColorProperty <string>] [-Markdown] [-Escape]
```

| Parameter         | Default  | Description                                          |
| ----------------- | -------- | ---------------------------------------------------- |
| `-Data`           | required | What to chart. Takes the pipeline.                   |
| `-Width`          | anchor   | The bar and the legend. `-MaxWidth` is an alias.     |
| `-HideTags`       | off      | Drop the legend and keep the bar.                    |
| `-HideTagValues`  | off      | Keep the legend, drop the numbers in it.             |
| `-ShowPercentage` | off      | Print each part's share instead of its value.        |
| `-FullSize`       | off      | One legend entry per row.                            |
| `-Style`          | `Blocks` | Which characters the bar is drawn with.              |
| `-ValueFormat`    | none     | A .NET numeric format, e.g. `N0`, `0.00`.            |
| `-Palette`        | built-in | Colours for items that name none, in turn, cycling.  |
| `-TagColor`       | the part | The tag text, instead of the colour of its part.     |
| `-ValueColor`     | none     | The numbers in the legend.                           |
| `-LabelProperty`  | `Label`  | Which property the tag comes from.                   |
| `-ValueProperty`  | `Value`  | Which property the value comes from.                 |
| `-ColorProperty`  | `Color`  | Which property the colour comes from.                |

## The data

Anything with a label, a value, and optionally a colour:

```powershell
# objects
Format-AnsiBreakdownChart @([PSCustomObject]@{ Label = 'Used'; Value = 412; Color = 'BrightRed' })

# hashtables
Format-AnsiBreakdownChart @(@{ Label = 'Pass'; Value = 219 }, @{ Label = 'Fail'; Value = 6 })

# bare numbers — a bar with an unlabelled legend
Format-AnsiBreakdownChart @(50, 30, 20) -ShowPercentage

# whatever you already have, named with the -*Property parameters
Get-Process | Group-Object Company -NoElement |
    Format-AnsiBreakdownChart -LabelProperty Name -ValueProperty Count
```

Values may be numbers or text that parses as one — `'2.5'` is read invariantly
first, so it means two and a half on a comma locale too. A value that is not a
number throws, as does an item with no value at all and an unknown colour. `null`
items are skipped, negative values are ignored, and no items at all renders nothing.

## The bar

Cells are whole, and they add up: the parts are handed out by largest remainder, so
the shares fill the bar's width exactly rather than drifting a cell out. A part with
a value is never invisible — if rounding would drop it, it borrows a cell from the
widest part. What no part claims is drawn as the empty character, so a bar that does
not add up to its width says so.

| `-Style` | Filled | Empty |
| -------- | ------ | ----- |
| `Blocks` | `█`    | `░`   |
| `Line`   | `━`    | `─`   |
| `Dots`   | `●`    | `·`   |
| `Ascii`  | `#`    | `-`   |

## The legend

Each entry is a swatch in the part's colour, its tag, and its number. Entries flow
across the chart's width, three spaces apart, wrapping onto as many rows as they
need; `-FullSize` gives each one a row of its own.

```powershell
Format-AnsiBreakdownChart $fruit -Width 50 -HideTagValues   # █ Apples   █ Oranges   █ Bananas
Format-AnsiBreakdownChart $fruit -Width 50 -ShowPercentage  # █ Apples 62.5%   ...
Format-AnsiBreakdownChart $fruit -Width 50 -HideTags        # the bar on its own
```

Whole numbers stay whole, fractions keep one decimal, `-ValueFormat` overrides both,
and everything is formatted invariantly — `-ShowPercentage -ValueFormat N0` rounds
the shares to whole percents.

Tags take markup, `-Markdown`, and `-Escape` like every other component; see
[Markup and markdown](Markup.md). A legend entry is one line, so a hard break in a
tag collapses to a space.

## Width

Like every component, the default width runs from the cursor to the right edge, so a
chart written at column 20 stops where one written at column 0 does, and the legend
wraps inside that same width.

## Colour

Colours come from the shared vocabulary — see [Colours](Colours.md). Hex is not one
of them: `#FFFF00` throws, `BrightYellow` does not.

An item's own colour wins; failing that the palette is handed out in turn and
cycles, and `-Palette` replaces it. Tags take the colour of the part they name
unless `-TagColor` says otherwise. Under `NO_COLOR` or redirected output the layout
is unchanged and the styling is dropped — which is why the parts are still one bar
of identical characters, not a lie about who owns which cell.

## Nesting

It is a rendering, so it goes wherever one goes — a panel's content, a grid cell, a
table cell:

```powershell
Format-AnsiTable @(
    [PSCustomObject]@{
        Suite = 'Text'
        Split = (Format-AnsiBreakdownChart @(96, 4) -Width 24 -HideTags -Palette BrightGreen, BrightRed)
    }
) -Border Rounded | Out-AnsiHost
```

## Demo

```powershell
pwsh -File .\demo\Demo-AnsiBreakdownChart.ps1
```

Every input shape, the legend and each switch that trims it, `-FullSize` and
wrapping, `-Palette`, `-TagColor` and `-ValueColor`, all four styles, the cell
arithmetic including a part too small to round up, the `-*Property` names, markup in
tags, charts nested in a panel, a grid and a table, anchoring, and two panes side by
side.

## Tests

`tests/Format-AnsiBreakdownChart.Tests.ps1` — 46 Pester 5 tests covering the share
arithmetic, largest remainder, the borrowed cell and the empty bar, every input shape
and every rejection, the legend and its wrapping, `-ShowPercentage` and
`-ValueFormat`, the anchor and width, the palette and every colour parameter,
`NO_COLOR`, and nesting in a panel.

```powershell
pwsh -File .\Invoke-Test.ps1 -Path .\tests\Format-AnsiBreakdownChart.Tests.ps1
```
