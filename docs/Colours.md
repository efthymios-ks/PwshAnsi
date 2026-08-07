# Colours

Colours come exclusively from `$PSStyle`. Every component that takes a colour —
`-Color`, `-TextColor`, markup tags — accepts the same vocabulary,
case-insensitively.

## `$PSStyle` names (16)

`Black`, `Red`, `Green`, `Yellow`, `Blue`, `Magenta`, `Cyan`, `White`,
`BrightBlack`, `BrightRed`, `BrightGreen`, `BrightYellow`, `BrightBlue`,
`BrightMagenta`, `BrightCyan`, `BrightWhite`.

## `ConsoleColor` aliases

| Alias         | Resolves to   |
| ------------- | ------------- |
| `DarkRed`     | `Red`         |
| `DarkGreen`   | `Green`       |
| `DarkYellow`  | `Yellow`      |
| `DarkBlue`    | `Blue`        |
| `DarkMagenta` | `Magenta`     |
| `DarkCyan`    | `Cyan`        |
| `Gray`        | `White`       |
| `DarkGray`    | `BrightBlack` |

No hex, no RGB, no invented palette. Unknown names throw.

## Styles

`bold`, `italic`, `underline`, `strikethrough`, `reverse` — available inside
markup tags rather than as parameters, so they can apply to a span instead of a
whole rendering. See [Markup and markdown](Markup.md).

## `NO_COLOR` and redirected output

If `$env:NO_COLOR` is set to any non-empty value, or stdout is redirected, all
styles are stripped but layout is preserved (wrap, indent, justify, cap).
Hyperlinks degrade to their link text.

```powershell
$env:NO_COLOR = '1'
Format-AnsiText '[bold BrightRed]This renders as plain text.[/]' | Out-AnsiHost
Remove-Item Env:NO_COLOR
```
