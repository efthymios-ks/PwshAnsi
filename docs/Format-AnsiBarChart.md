# Format-AnsiBarChart

A bar chart as an `[Ansi.Rendering]`: one row per item — a label, a bar scaled
against the largest value, and the value. `Out-AnsiHost` paints it, `Out-AnsiString`
turns it into strings.

```powershell
$fruit = @(
    [PSCustomObject]@{ Label = 'Apples'; Value = 12; Color = 'BrightGreen' }
    [PSCustomObject]@{ Label = 'Oranges'; Value = 5; Color = 'Yellow' }
    [PSCustomObject]@{ Label = 'Bananas'; Value = 2.2 }
)
Format-AnsiBarChart $fruit 'Fruit sales' -Width 50 | Out-AnsiHost
```

```
                   Fruit sales
 Apples ██████████████████████████████████████ 12
Oranges ████████████████                       5
Bananas ███████                                2.2
```

There is no chart-item type to build first: the data is plain objects, the same way
[`Format-AnsiTable`](Format-AnsiTable.md) takes rows.

## Parameters

```powershell
Format-AnsiBarChart [-Data] <object[]> [[-Label] <string>]
                   [-Width <int>] [-BarWidth <int>] [-LabelWidth <int>]
                   [-MaxValue <double>] [-HideValues] [-ShowPercentage]
                   [-Style <Blocks|Line|Dots|Ascii>] [-ValueFormat <string>]
                   [-Palette <c[]>] [-BarColor <c>] [-LabelColor <c>]
                   [-ValueColor <c>] [-TitleColor <c>]
                   [-TitleAlignment <Left|Center|Right>]
                   [-LabelAlignment <Left|Right>]
                   [-LabelProperty <string>] [-ValueProperty <string>]
                   [-ColorProperty <string>] [-Markdown] [-Escape]
```

| Parameter          | Default     | Description                                            |
| ------------------ | ----------- | ------------------------------------------------------ |
| `-Data`            | required    | What to chart. Takes the pipeline.                     |
| `-Label`           | none        | A title above the chart. `-Title` is an alias.         |
| `-Width`           | anchor      | The whole chart. `-MaxWidth` is an alias.              |
| `-BarWidth`        | what's left | The bar column, whatever the labels and values cost.   |
| `-LabelWidth`      | widest      | Pad the label column to this width.                    |
| `-MaxValue`        | largest     | What a full bar means.                                 |
| `-HideValues`      | off         | Drop the value column.                                 |
| `-ShowPercentage`  | off         | Print each value's share of the total instead.          |
| `-Style`           | `Blocks`    | Which character the bars are drawn with.               |
| `-ValueFormat`     | none        | A .NET numeric format, e.g. `N0`, `0.00`.              |
| `-Palette`         | built-in    | Colours for items that name none, in turn, cycling.    |
| `-BarColor`        | none        | One colour for the items that name none. `-Color` too. |
| `-LabelColor`      | none        | The labels, where their own markup does not say.       |
| `-ValueColor`      | none        | The value column.                                      |
| `-TitleColor`      | none        | The title.                                             |
| `-TitleAlignment`  | `Center`    | Where the title sits over the chart.                   |
| `-LabelAlignment`  | `Right`     | Label text inside the label column.                    |
| `-LabelProperty`   | `Label`     | Which property the label comes from.                   |
| `-ValueProperty`   | `Value`     | Which property the value comes from.                   |
| `-ColorProperty`   | `Color`     | Which property the colour comes from.                  |

## The data

Anything with a label, a value, and optionally a colour:

```powershell
# objects
Format-AnsiBarChart @([PSCustomObject]@{ Label = 'Apples'; Value = 12; Color = 'BrightGreen' })

# hashtables
Format-AnsiBarChart @(@{ Label = 'Hit'; Value = 88 }, @{ Label = 'Miss'; Value = 12 })

# bare numbers — a chart with no labels
Format-AnsiBarChart @(12, 5, 2.2)

# whatever you already have, named with the -*Property parameters
Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 5 |
    Format-AnsiBarChart -LabelProperty ProcessName -ValueProperty WorkingSet64 -ValueFormat N0
```

Values may be numbers or text that parses as one — `'2.5'` is read invariantly
first, so it means two and a half on a comma locale too. A value that is not a
number throws, as does an item with no value at all and an unknown colour. `null`
items are skipped, and no items at all renders nothing.

## The bars

Whole cells only — no partial blocks, so the same data always draws the same chart.
Bars are scaled against the largest value unless `-MaxValue` says otherwise, and a
value past zero always keeps one cell: a share too small to round up still shows.
Zero draws nothing, and so does a negative value, which is still printed.

| `-Style` | Filled |
| -------- | ------ |
| `Blocks` | `█`    |
| `Line`   | `━`    |
| `Dots`   | `●`    |
| `Ascii`  | `#`    |

## Labels and values

The label column is as wide as the widest label, or `-LabelWidth`, and its text is
right-aligned by default so the bars start together. Values are printed in a column
of their own, past the widest bar, so they read down the chart rather than trailing
each bar.

Whole numbers stay whole, fractions keep one decimal, `-ValueFormat` overrides
both, and everything is formatted invariantly. `-ShowPercentage` prints shares of
the total instead — `-ValueFormat N0` rounds them to whole percents.

Labels take markup, `-Markdown`, and `-Escape` like every other component; see
[Markup and markdown](Markup.md). A chart row is one line, so a hard break in a
label collapses to a space.

## Width

Like every component, the default width runs from the cursor to the right edge.
`-Width` sets the whole chart; `-BarWidth` sets the bar column and lets the chart
grow past `-Width` if the labels demand it, which is what keeps two charts
comparable when their labels differ:

```powershell
Format-AnsiBarChart $q1 -BarWidth 24 -LabelWidth 10
Format-AnsiBarChart $q2 -BarWidth 24 -LabelWidth 10
```

## Colour

Colours come from the shared vocabulary — see [Colours](Colours.md). Hex is not one
of them: `#FFFF00` throws, `BrightYellow` does not.

An item's own colour wins. Failing that, `-BarColor` colours every bar, and failing
that the palette is handed out in turn and cycles — `-Palette` replaces it. Under
`NO_COLOR` or redirected output the layout is unchanged and the styling is dropped.

## Nesting

It is a rendering, so it goes wherever one goes — a panel's content, a grid cell, a
table cell:

```powershell
Format-AnsiPanel (Format-AnsiBarChart $fruit -Width 40) -Title 'Fruit' -Border Rounded | Out-AnsiHost
```

## Demo

```powershell
pwsh -File .\demo\Demo-AnsiBarChart.ps1
```

Every input shape, the title and its alignment, colour from the item, `-BarColor`
and `-Palette`, the value column and `-ShowPercentage`, the label column, `-MaxValue`
and `-BarWidth`, all four styles, the `-*Property` names, markup in labels, charts
nested in a panel, a grid and a table, the guarded ends, anchoring, and two panes
side by side.

## Tests

`tests/Format-AnsiBarChart.Tests.ps1` — 59 Pester 5 tests covering the scaling
arithmetic and its guarded ends, every input shape and every rejection, the label
and value columns, `-ShowPercentage` and `-ValueFormat`, the title and its
alignment, the anchor and each width parameter, the palette and every colour
parameter, `NO_COLOR`, and nesting in a panel.

```powershell
pwsh -File .\Invoke-Test.ps1 -Path .\tests\Format-AnsiBarChart.Tests.ps1
```
