# Format-AnsiText

Renders styled text to the host with anchoring, wrapping, justification, indent,
row capping, and configurable overflow. Accepts markup, markdown, or literal
input.

## Synopsis

```powershell
Format-AnsiText [-Message] <string[]> | Out-AnsiHost
              [-Color <string>]
              [-Justify <Left|Center|Right>]
              [-MaxWidth <int>]
              [-Indent <int>]
              [-MaxRows <int>]
              [-Overflow <Fold|Crop|Ellipsis>]
              [-Markdown]
              [-Escape]
              [-NoNewline]
```

## Parameters

| Name         | Type                          | Default  | Description                                                                                                                                            |
| ------------ | ----------------------------- | -------- | ------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `-Message`   | `string[]` (pipeline, pos. 0) | —        | Text to render. One line per array item or pipeline item. Embedded `` `n `` inside a string is a hard break.                                            |
| `-Color`     | `string`                      | none     | Primary content colour. Any [accepted colour name](Colours.md). Applies to runs that don't set their own foreground via markup.                          |
| `-Justify`   | `Left`\|`Center`\|`Right`     | `Left`   | Horizontal alignment within the effective width.                                                                                                       |
| `-MaxWidth`  | `int`                         | *auto*   | Override the effective width. Default is `BufferWidth - AnchorColumn`.                                                                                 |
| `-Indent`    | `int`                         | `0`      | Hanging indent for continuation rows (columns added after the anchor column).                                                                          |
| `-MaxRows`   | `int`                         | `0` (∞)  | Row cap. Forces `Fold` wrapping, keeps the first N rows, and appends `…` to the last kept row when there is more content. Overrides `-Overflow`.        |
| `-Overflow`  | `Fold`\|`Crop`\|`Ellipsis`    | `Fold`   | Per-line overflow strategy. `Fold` wraps; `Crop` truncates; `Ellipsis` truncates with `…`. Ignored when `-MaxRows` is set.                              |
| `-Markdown`  | `switch`                      | off      | Enable [markdown sugar](Markup.md#markdown). Applied before markup parsing.                                                                            |
| `-Escape`    | `switch`                      | off      | Treat input as literal — no markup or markdown parsing. `-Color` still applies.                                                                        |
| `-NoNewline` | `switch`                      | off      | Do not emit a trailing newline after the last rendered row. Lets you chain calls on one line.                                                           |

## Anchoring

`Format-AnsiText` reads the cursor column when it starts rendering. Wrapped
continuation rows resume at that column, never at column 0. If you pre-position
with a prefix, the whole block hangs beneath it:

```powershell
Write-Host 'Prefix › ' -NoNewline
Format-AnsiText 'Long paragraph…' -MaxWidth 60 | Out-AnsiHost
# Prefix › Long paragraph that wraps and each continuation
#         row starts at the same column as the first one.
```

The default effective width is `BufferWidth - AnchorColumn`, so the block never
overflows the terminal. `-MaxWidth` overrides that.

## Styling

Colour names and `NO_COLOR` behaviour: [Colours](Colours.md).
Tags, markdown sugar, emoji, and escaping: [Markup and markdown](Markup.md).

```powershell
Format-AnsiText 'Job finished :check:. Wrote **42** rows to `sink.parquet`.' -Markdown | Out-AnsiHost
Format-AnsiText '[bold BrightRed on Blue]Alert[/] · [italic]note[/]' | Out-AnsiHost
```

## Overflow and truncation

`-Overflow` controls how a single source line behaves when it exceeds the
effective width:

- `Fold` (default) — wrap at word boundaries; break in the middle only if a
  single word exceeds the width.
- `Crop` — hard truncate; drop the rest of the source line.
- `Ellipsis` — truncate and append `…` in the last column.

`-MaxRows` caps the total row count. When set, wrapping is forced to `Fold`
(intermediate rows render in full) and `…` is appended only to the last kept
row when there is more content. `-Overflow` is ignored while `-MaxRows` is
active.

```powershell
Format-AnsiText $long -MaxWidth 40 -Overflow Fold | Out-AnsiHost
Format-AnsiText $long -MaxWidth 40 -Overflow Crop | Out-AnsiHost
Format-AnsiText $long -MaxWidth 40 -Overflow Ellipsis | Out-AnsiHost
Format-AnsiText $long -MaxWidth 40 -MaxRows 2 | Out-AnsiHost
```

## Input forms

**Pipeline** — one line per item:

```powershell
'Alpha', 'Bravo', 'Charlie' | Format-AnsiText -Color BrightCyan
```

**Array positional** — same shape without a pipe:

```powershell
Format-AnsiText 'Alpha', 'Bravo', 'Charlie' -Color BrightCyan | Out-AnsiHost
```

**Hard newlines inside one string** — `` `n `` inside a double-quoted string:

```powershell
Format-AnsiText "line one`nline two`nline three" -Color BrightGreen | Out-AnsiHost
```

**Chained `-NoNewline`** — build one row from several calls:

```powershell
Format-AnsiText 'Part-one '  -Color BrightRed | Out-AnsiHost -NoNewline
Format-AnsiText 'Part-two '  -Color BrightGreen | Out-AnsiHost -NoNewline
Format-AnsiText 'Part-three'           -Color BrightBlue | Out-AnsiHost
```

An empty string renders one blank row; `$null` and an empty collection render
nothing at all.

## Usage patterns

**Prefixed status line**

```powershell
Write-Host '[INFO] ' -NoNewline -ForegroundColor DarkGray
Format-AnsiText 'Job finished :check:. Wrote **42** rows to `sink.parquet`.' -Markdown | Out-AnsiHost
```

**Two-column key/value with wrapping**

```powershell
foreach ($kv in $items.GetEnumerator()) {
    Write-Host ("  {0,-14}" -f $kv.Key) -NoNewline -ForegroundColor DarkGray
    Format-AnsiText $kv.Value -MaxWidth 60 | Out-AnsiHost
}
```

**Bulleted list with hanging indent**

```powershell
foreach ($line in $bullets) {
    Write-Host '  • ' -NoNewline
    Format-AnsiText $line -Indent 4 -MaxWidth 70 | Out-AnsiHost
}
```

**Truncated single-line summary**

```powershell
Format-AnsiText $veryLongLine -MaxWidth 80 -Overflow Ellipsis | Out-AnsiHost
```

**Capped multi-line preview**

```powershell
Format-AnsiText $document -MaxWidth 80 -MaxRows 5 | Out-AnsiHost
```

## Demo

```powershell
pwsh -File .\demo\Demo-AnsiText.ps1
```

The demo has numbered sections corresponding to each feature (plain text, colour,
markup, markdown, emoji, direct `[link=…]`, escape/literal, justify, wrap, indent,
`-MaxRows`, `-Overflow`, anchoring, `-NoNewline`, pipeline/array/`` `n ``, combined,
`NO_COLOR`).

## Tests

`tests/Format-AnsiText.Tests.ps1` — 147 Pester 5 tests covering input forms,
colour vocabulary, markup and markdown, justification, wrapping, indent,
anchoring, row capping, overflow modes, escaping, `-NoNewline`, the no-colour
path, and parameter validation.

```powershell
pwsh -File .\Invoke-Test.ps1
```
