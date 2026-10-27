# Format-AnsiPanel

Frames a block of text: border, optional title set into the top rule, inner
padding. Content is `[string[]]`, so with `-Rendered` it also frames rows captured
from another `Format-Ansi*` — the one place the library composes.

## Synopsis

```powershell
Format-AnsiPanel [-Data] <string[]> | Out-AnsiHost
               [-Title <string>] [-TitleAlignment <Left|Center|Right>]
               [-Border <None|Ascii|Square|Rounded|Heavy|Double>]
               [-BorderColor <string>] [-TextColor <string>] [-TitleColor <string>]
               [-Justify <Left|Center|Right>]
               [-Padding <int>]
               [-Width <int>]              # -MaxWidth is an alias
               [-Height <int>]
               [-Expand]
               [-Rendered]
               [-Markdown] [-Escape] [-NoNewline]
```

## Parameters

| Name              | Type                            | Default   | Description                                                                                     |
| ----------------- | ------------------------------- | --------- | ----------------------------------------------------------------------------------------------- |
| `-Data`           | `string[]` (pipeline, pos. 0)   | —         | Lines to frame. A hard `` `n `` inside a line splits it. Long lines wrap to the inner width.      |
| `-Title`          | `string`                        | none      | Caption set into the top rule as `╭─ Title ─╮`. Widens the panel if longer than the content.      |
| `-TitleAlignment` | `Left`\|`Center`\|`Right`       | `Left`    | Where the title sits along the top rule.                                                         |
| `-Border`         | see below                       | `Rounded` | Border style. `None` keeps the layout but draws nothing.                                         |
| `-BorderColor`    | `string`                        | none      | Colour of the frame. Also the title's default colour.                                            |
| `-TextColor`      | `string`                        | none      | Colour of the content. Lines that set their own colour via markup win.                            |
| `-TitleColor`     | `string`                        | *border*  | Colour of the title.                                                                             |
| `-Justify`        | `Left`\|`Center`\|`Right`       | `Left`    | Horizontal alignment of content inside the panel.                                                |
| `-Padding`        | `int`                           | `1`       | Spaces between the border and the content on each side.                                          |
| `-Width`          | `int`                           | *auto*    | Total panel width. Default `BufferWidth - AnchorColumn`. `-MaxWidth` aliases it.                  |
| `-Height`         | `int`                           | *auto*    | Total row count including both rules: pads with blank rows, or drops the overflow.                |
| `-Expand`         | `switch`                        | off       | Fill the available width instead of sizing to content.                                           |
| `-Rendered`       | `switch`                        | off       | Content is already rendered: pass it through, measure visible width, truncate instead of wrap.    |
| `-Markdown`       | `switch`                        | off       | Enable [markdown sugar](Markup.md#markdown) in content and title.                                 |
| `-Escape`         | `switch`                        | off       | Treat content as literal text. Wins over `-Markdown`; colours still apply.                        |
| `-NoNewline`      | `switch`                        | off       | Do not emit a trailing newline after the bottom rule.                                            |

Colour names: [Colours](Colours.md). Content syntax: [Markup and markdown](Markup.md).

## Borders

| `-Border` | Corners      |
| --------- | ------------ |
| `Rounded` | `╭ ╮ ╰ ╯` (default) |
| `Square`  | `┌ ┐ └ ┘`    |
| `Heavy`   | `┏ ┓ ┗ ┛`    |
| `Double`  | `╔ ╗ ╚ ╝`    |
| `Ascii`   | `+ + + +`    |
| `None`    | no glyphs, layout unchanged |

```powershell
Format-AnsiPanel 'Hello' | Out-AnsiHost
# ╭───────╮
# │ hello │
# ╰───────╯

Format-AnsiPanel 'Body text here' -Title 'Build' | Out-AnsiHost
# ╭ Build ─────────╮
# │ body text here │
# ╰────────────────╯
```

<!-- demo-media -->
![3. -Title and -TitleAlignment Left / Center / Right](media/AnsiPanel/3.png)

![4. -Border Ascii / Square / Rounded / Heavy / Double / None](media/AnsiPanel/4.png)
<!-- /demo-media -->

## Sizing

The panel sizes to its widest line, widening if the title needs more room, and
never exceeds the available width — content wraps to the inner width. `-Expand`
fills the width instead; `-Height` fixes the row count.

```powershell
Format-AnsiPanel $paragraph -Width 46 | Out-AnsiHost          # wraps inside the frame
Format-AnsiPanel 'x' -Expand | Out-AnsiHost                    # fills the buffer
Format-AnsiPanel @('a', 'b') -Height 6 | Out-AnsiHost          # pads to six rows
Format-AnsiPanel @('a', 'b', 'c', 'd') -Height 3 | Out-AnsiHost # keeps the first row only
```

<!-- demo-media -->
![6. -Padding 0 / 1 (default) / 3](media/AnsiPanel/6.png)

![7. Content wraps to the inner width](media/AnsiPanel/7.png)

![8. -Justify Left / Center / Right](media/AnsiPanel/8.png)

![9. -Width / -Expand / -Height](media/AnsiPanel/9.png)
<!-- /demo-media -->

## Nesting another rendering

`-Data` accepts `[Ansi.Rendering]` objects as well as strings, so a panel can frame
any other component row for row — and mix the two in order:

```powershell
$table = Format-AnsiTable $rows -Border None -MaxWidth 24
Format-AnsiPanel $table -Title 'Stats' | Out-AnsiHost
Format-AnsiPanel @('Before', $table, 'After') -Title 'Mixed' | Out-AnsiHost
```

Nested rows are measured on their runs, so no visible-width guessing is involved.
`-Content` is an alias of `-Data` when the content is a single rendering.

<!-- demo-media -->
![17. Nested renderings inside a panel](media/AnsiPanel/17.png)
<!-- /demo-media -->

## Framing pre-rendered strings with -Rendered

Captured rows carry ANSI, which a naive width measure would count as characters.
`-Rendered` measures *visible* width (CSI and OSC 8 stripped), skips markup
parsing, and truncates over-long rows with `…` rather than re-wrapping them —
re-wrapping pre-rendered output would break its own alignment.

```powershell
function Get-Rows {
    param([scriptblock]$Render)
    $rows = @((& $Render 6>&1) | ForEach-Object { [string]$_ })
    return , $rows
}

$tree = Get-Rows { Format-AnsiTree $data -MaxWidth 30 -Color DarkGray }
Format-AnsiPanel $tree -Rendered -Title 'Tree' -BorderColor BrightBlue | Out-AnsiHost
# ╭ tree ───────────────────╮
# │ src                     │
# │ ├── Ansi.Core.psm1       │
# │ └── Format-AnsiGrid.psm1  │
# ╰─────────────────────────╯
```

<!-- demo-media -->
![12. -Rendered frames captured PwshAnsi output](media/AnsiPanel/12.png)
<!-- /demo-media -->

## Anchoring

The top rule starts wherever the cursor already is; every later row resumes at
that column, so the whole box hangs under its prefix.

<!-- demo-media -->
![13. Anchoring](media/AnsiPanel/13.png)

![14. -NoNewline](media/AnsiPanel/14.png)
<!-- /demo-media -->

## Usage patterns

**Error callout**

```powershell
Format-AnsiPanel @( | Out-AnsiHost
    '[bold]Cannot bind argument to parameter ''Runs''[/]'
    ''
    'at Split-AnsiRuns, Ansi.Core.psm1: line 261'
) -Title '[bold]:cross: error[/]' -Markdown -Border Heavy -BorderColor BrightRed
```

**Two panels side by side** — capture each pane and zip the rows (see
[Format-AnsiTree](Format-AnsiTree.md#usage-patterns)); `-Expand -Width <pane>` keeps
both boxes the same width.

**Help block**

```powershell
Format-AnsiPanel $usageLines -Title 'Usage' -Border Square -BorderColor DarkGray -Padding 2 | Out-AnsiHost
```

<!-- demo-media -->
![15. Usage pattern — error callout](media/AnsiPanel/15.png)

![16. Two panes — panels left and right](media/AnsiPanel/16.png)
<!-- /demo-media -->

## Demo

```powershell
pwsh -File .\demo\Demo-AnsiPanel.ps1
```

Numbered sections per feature: framed text, multiple lines, title alignment,
every border, colours, padding, wrapping, `-Justify`, `-Width`/`-Expand`/`-Height`,
markup/markdown, `-Escape`, `-Rendered` framing tree and json output, anchoring,
`-NoNewline`, an error callout, two panels side by side, `NO_COLOR`.

<!-- demo-media -->
![1. Framed text](media/AnsiPanel/1.png)

![2. Multiple lines](media/AnsiPanel/2.png)

![5. -BorderColor / -TextColor / -TitleColor](media/AnsiPanel/5.png)

![10. Markup / -Markdown](media/AnsiPanel/10.png)

![11. -Escape (content stays literal)](media/AnsiPanel/11.png)

![18. NO_COLOR strips styles, keeps layout](media/AnsiPanel/18.png)
<!-- /demo-media -->

## Tests

`tests/Format-AnsiPanel.Tests.ps1` — 66 Pester 5 tests covering frame layout, title
placement and widening, every border, padding, `-Justify`, wrapping, `-Expand`,
`-Height` padding and truncation, all three colour parameters, markup
measurement, `-Rendered` visible-width measurement and pass-through (including
framing captured grid output), anchoring, `-NoNewline`, and the no-colour path.

```powershell
pwsh -File .\Invoke-Test.ps1 -TestName '*AnsiPanel*'
```
