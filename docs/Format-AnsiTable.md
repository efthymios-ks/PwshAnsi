# Format-AnsiTable

Renders objects as a bordered table. Sizes columns to their content, shrinks the
widest column first when space runs out, and ellipsises or folds cells that still
do not fit.

## Synopsis

```powershell
Format-AnsiTable [-Data] <object> [[-Property] <object[]>] | Out-AnsiHost
               [-Border <None|Ascii|Square|Rounded|Heavy|Double|Horizontal>]
               [-BorderColor <string>]
               [-HeaderColor <string>]
               [-TextColor <string>]
               [-Align <string[]>]
               [-Width <int>]                # -MaxWidth is an alias
               [-Title <string>] [-TitleColor <string>]
               [-HideHeaders]
               [-ShowRowSeparators]
               [-Wrap]
               [-Expand]
               [-Markdown]
               [-Escape]
               [-NoNewline]
```

## Parameters

| Name                 | Type                        | Default   | Description                                                                                          |
| -------------------- | --------------------------- | --------- | ---------------------------------------------------------------------------------------------------- |
| `-Data`              | `object` (pipeline, pos. 0) | —         | Rows to render. Objects, hashtables, or scalars. Pipeline items accumulate into one table.             |
| `-Property`          | `object[]` (pos. 1)         | *all*     | Column names, or calculated columns as `@{ Name = 'x'; Expression = { … } }`. Default: the first item's properties. |
| `-Border`            | see below                   | `Rounded` | Border style. `None` and `Horizontal` drop the verticals.                                             |
| `-BorderColor`       | `string`                    | none      | Colour of borders and rules.                                                                          |
| `-HeaderColor`       | `string`                    | none      | Colour of the header row.                                                                             |
| `-TextColor`         | `string`                    | none      | Colour of body cells. Cells that set their own colour via markup win.                                 |
| `-Align`             | `string[]`                  | `Left`    | Per-column `Left`/`Center`/`Right`. Fewer values than columns → the last one repeats.                  |
| `-Width`             | `int`                       | *auto*    | Total table width. Default is `BufferWidth - AnchorColumn`. `-MaxWidth` aliases it.                    |
| `-Title`             | `string`                    | none      | Caption centered above the table; truncates with `…` when wider.                                      |
| `-TitleColor`        | `string`                    | none      | Colour of the title.                                                                                  |
| `-HideHeaders`       | `switch`                    | off       | Omit the header row and its rule; columns then size to the body only.                                  |
| `-ShowRowSeparators` | `switch`                    | off       | Draw a rule between body rows.                                                                        |
| `-Wrap`              | `switch`                    | off       | Fold over-long cells onto extra rows instead of ellipsising them.                                     |
| `-Expand`            | `switch`                    | off       | Grow columns to fill the width instead of sizing to content.                                          |
| `-Markdown`          | `switch`                    | off       | Enable [markdown sugar](Markup.md#markdown) in cells, headers, and the title.                          |
| `-Escape`            | `switch`                    | off       | Treat cell text as literal. Wins over `-Markdown`; colours still apply.                               |
| `-NoNewline`         | `switch`                    | off       | Do not emit a trailing newline after the last row.                                                    |

Colour names: [Colours](Colours.md). Cell syntax: [Markup and markdown](Markup.md).

## Borders

| `-Border`    | Look                                                     |
| ------------ | -------------------------------------------------------- |
| `Rounded`    | `╭─┬─╮` … `╰─┴─╯` (default)                              |
| `Square`     | `┌─┬─┐` … `└─┴─┘`                                        |
| `Heavy`      | `┏━┳━┓` … `┗━┻━┛`                                        |
| `Double`     | `╔═╦═╗` … `╚═╩═╝`                                        |
| `Ascii`      | `+---+`                                                  |
| `Horizontal` | rules above the header, under it, and below the last row  |
| `None`       | no glyphs; columns separated by two spaces                |

```powershell
Format-AnsiTable $data | Out-AnsiHost
# ╭───────┬───────┬────────╮
# │ Name  │ Tests │ Status │
# ├───────┼───────┼────────┤
# │ Text  │ 147   │ built  │
# ╰───────┴───────┴────────╯

Format-AnsiTable $data -Border None | Out-AnsiHost
# Name   Tests  Status
# Text   147    built
```

## Columns

Without `-Property`, the first item decides the columns — its properties, a
hashtable's keys, or a single `Value` column for scalars.

```powershell
Format-AnsiTable $data -Property Component, Status | Out-AnsiHost
Format-AnsiTable $data -Property Name, @{ Name = 'X2'; Expression = { $_.Tests * 2 } } | Out-AnsiHost
Format-AnsiTable @(@{ key = 'Retries'; value = 3 }) -Property key, value | Out-AnsiHost
Format-AnsiTable @('Alpha', 'Bravo') | Out-AnsiHost          # one 'Value' column
```

`Label`/`E` work as aliases of `Name`/`Expression`. A property that does not
exist renders as an empty cell rather than throwing.

## Nesting another rendering

A cell value may be an `[Ansi.Rendering]` — typically from a calculated column. Its
rows become the cell's lines, its widest row the column's natural width, and the
table row grows to the tallest cell:

```powershell
Format-AnsiTable $suites -Property `
    Suite,
    @{ Name = 'Counts'; Expression = { Format-AnsiGrid @(, @('Pass', $_.Passed), @('Fail', $_.Failed)) -MaxWidth 16 } }
# │ text  │ pass  147 │
# │       │ fail    0 │
```

## Width, overflow, and -Expand

Columns start at their natural width (widest of header and cells). If the table
would exceed the available width, the widest column is trimmed one column at a
time until it fits, then cells are ellipsised — or folded with `-Wrap`, which
grows the row and pads the shorter columns.

```powershell
Format-AnsiTable $data -Width 24 | Out-AnsiHost          # │ Name │ Tests │ Stat… │
Format-AnsiTable $notes -Width 56 -Wrap | Out-AnsiHost   # long cells fold onto extra rows
Format-AnsiTable $data -Expand | Out-AnsiHost            # columns share the slack, table fills the width
```

A hard `` `n `` inside a cell always splits it across rows.

## Alignment

```powershell
Format-AnsiTable $data -Align Left, Right, Center | Out-AnsiHost
Format-AnsiTable $data -Align Right | Out-AnsiHost        # applies to every column
```

Headers follow the same alignment as their column.

## Styling

```powershell
Format-AnsiTable $data -BorderColor DarkGray -HeaderColor BrightWhite -TextColor BrightCyan | Out-AnsiHost
Format-AnsiTable $data -Title 'Components' -TitleColor BrightWhite | Out-AnsiHost
Format-AnsiTable $steps -Markdown | Out-AnsiHost          # ':check: **ok**' in cells
Format-AnsiTable $patterns -Escape | Out-AnsiHost         # '[bold]x[/]' stays literal
```

Column widths are measured on *visible* text, so markup never inflates a column.

## Anchoring

The first row starts wherever the cursor already is; every later row resumes at
that column, so the whole table hangs under its prefix. With `-Expand` the table
fills the remaining buffer, not the whole terminal.

## Usage patterns

**Summary with a total row**

```powershell
$total = ($rows | Measure-Object Tests -Sum).Sum
$summary = @($rows) + @([PSCustomObject]@{ Component = '[bold]Total[/]'; Tests = $total })
Format-AnsiTable $summary -Align Left, Right -HeaderColor BrightWhite -BorderColor DarkGray | Out-AnsiHost
```

**Cmdlet output**

```powershell
Get-ChildItem .\src -File |
    Select-Object Name, Length |
    Format-AnsiTable -Align Left, Right -Border Horizontal | Out-AnsiHost
```

**Status matrix with markup**

```powershell
Format-AnsiTable @( | Out-AnsiHost
    [PSCustomObject]@{ Step = 'restore'; Result = '[BrightGreen]:check: ok[/]' }
    [PSCustomObject]@{ Step = 'smoke'; Result = '[BrightRed]:cross: failed[/]' }
) -Markdown -BorderColor DarkGray
```

**Two tables side by side** — see the pattern in
[Format-AnsiTree](Format-AnsiTree.md#usage-patterns): capture each pane's rows, pad on
visible width, zip them.

## Demo

```powershell
pwsh -File .\demo\Demo-AnsiTable.ps1
```

Numbered sections per feature: default rendering, every border, colours, title,
alignment, `-HideHeaders`/`-ShowRowSeparators`, `-Property` and calculated
columns, `-Width`/`-Expand`, cell overflow vs `-Wrap`, markup/markdown cells,
`-Escape`, input shapes, anchoring, `-NoNewline`, a summary table, two tables side
by side, `NO_COLOR`.

## Tests

`tests/Format-AnsiTable.Tests.ps1` — 78 Pester 5 tests covering exact border
output for every style, header/rule/title layout, alignment, `-Property` forms,
input shapes, width shrinking and `-Expand`, ellipsis vs `-Wrap`, hard breaks in
cells, all four colour parameters, markup measurement, anchoring, `-NoNewline`,
and the no-colour path.

```powershell
pwsh -File .\Invoke-Test.ps1 -TestName '*AnsiTable*'
```
