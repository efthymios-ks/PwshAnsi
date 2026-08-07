# Out-AnsiHost and Out-AnsiString

Every `Format-Ansi*` returns an `[Ansi.Rendering]` and writes nothing. These two
functions are what turn it into output.

```powershell
Format-AnsiTable $data -Border Heavy | Out-AnsiHost          # paint at the cursor
Format-AnsiTable $data -Border Heavy | Out-AnsiString        # -> string[] with ANSI
Format-AnsiTable $data -Border Heavy | Out-AnsiString -Plain # -> string[], no styles
```

## The rendering

| Property   | Meaning                                                                       |
| ---------- | ----------------------------------------------------------------------------- |
| `Kind`     | Which component built it (`Text`, `Rule`, `Path`, `Json`, `Tree`, `Table`, `Grid`, `Panel`, `Exception`). |
| `Rows`     | `object[][]` — one array of runs per row. A run is `Text` + `Fg`/`Bg`/`Styles`/`Link`. |
| `Width`    | The width the rows were laid out for.                                          |
| `Column`   | The anchor column read when it was built.                                      |
| `NoColor`  | Whether the host could show styles at build time (`$null` = undecided).         |
| `RowCount` | Convenience count of `Rows`.                                                    |

Rows carry *runs*, not strings, so nothing has been committed to ANSI yet:
alignment and padding are baked in, colour is not. `Test-AnsiRendering` (internal)
is what the writers use to reject anything else.

## Out-AnsiHost

```powershell
Out-AnsiHost [-Rendering] <object> [-NoColor <bool>] [-Column <int>] [-NoNewline]
Out-AnsiHost [-Rendering] <object> -Row <int> -Column <int> [-NoColor <bool>]
```

| Parameter     | Default     | Description                                                                 |
| ------------- | ----------- | --------------------------------------------------------------------------- |
| `-Rendering`  | —           | The `[Ansi.Rendering]` to paint. Accepts pipeline input; `$null` paints nothing. |
| `-NoColor`    | *rendering* | Override the colour decision. Falls back to the rendering, then to the redirect/`NO_COLOR` check. |
| `-Column`     | *rendering* | Anchored: override the anchor column used for continuation rows. Positioned: the column to paint at, 0-based. |
| `-Row`        | —           | The row to paint at, 0-based, from the top of the screen. Required with `-Column`. |
| `-NoNewline`  | off         | Leave the cursor at the end of the last row. Anchored only.                  |

The first row lands wherever the cursor already is; later rows are prefixed with
the anchor column, and blank rows stay blank rather than becoming trailing spaces.

### Painting at a cell

`-Row` and `-Column` are 0-based and required together — pass both and the rendering
is painted at that cell instead of at the cursor:

```powershell
Format-AnsiProgress $done 'Restore' -BarWidth 24 | Out-AnsiHost -Row 4 -Column 2
```

That path is built for repainting. The whole rendering becomes one string and is
written **once**, because several writes are what let a terminal show a half-drawn
frame — the thing that reads as flicker. In order, the frame:

1. saves the caller's cursor (`ESC 7`) and hides it (`ESC[?25l`),
2. opens a synchronized update (`ESC[?2026h`) — terminals that know it present the
   frame atomically, the rest ignore the pair,
3. positions each row absolutely (`ESC[<row>;<col>H`) and erases to the end of the
   line (`ESC[K`) — nothing is cleared first, since a clear is the flash, and a row
   that shrank leaves nothing of the last frame behind,
4. closes the update, shows the cursor, and restores it (`ESC 8`), so a script can
   keep writing normally around the frame.

`-NoColor` still applies; positioning does not depend on it. When output is not a
terminal every cursor sequence is dropped and the rows are written in order, so a
redirected or captured frame stays readable. Nothing goes through `Write-Host` on
this path.

A dashboard is then a loop over cells:

```powershell
while ($true) {
    Format-AnsiBarChart $cpu 'CPU' -Width 40 | Out-AnsiHost -Row 1 -Column 2
    Format-AnsiBreakdownChart $disk -Width 40 | Out-AnsiHost -Row 8 -Column 2
    Start-Sleep -Milliseconds 250
}
```

## Out-AnsiString

```powershell
Out-AnsiString [-Rendering] <object> [-Plain] [-Join] [-WithAnchor]
```

| Parameter     | Default     | Description                                                        |
| ------------- | ----------- | ------------------------------------------------------------------ |
| `-Rendering`  | —           | The `[Ansi.Rendering]` to render. Accepts pipeline input.            |
| `-Plain`      | off         | Strip every style and hyperlink, whatever the rendering decided.     |
| `-Join`       | off         | Return one string with rows joined by the platform newline.         |
| `-WithAnchor` | off         | Prefix continuation rows with the anchor column.                    |

Without `-Plain` the rendering's own `NoColor` decision applies, so a redirected
session still yields plain strings. No anchor prefix by default: the block is
returned as-is, which is what composing panes or writing a file wants.

## Composing

`Format-AnsiPanel`, `Format-AnsiTable`, `Format-AnsiGrid`, and `Format-AnsiTree` accept
renderings directly — panel content, table cells, grid cells, tree labels — so
nesting needs no strings at all:

```powershell
$counts = Format-AnsiGrid @(, @('Pass', '712'), @('Fail', '0')) -MaxWidth 16
Format-AnsiPanel $counts -Title 'Counts' | Out-AnsiHost
Format-AnsiGrid @(, @($counts, (Format-AnsiTree $data))) | Out-AnsiHost
```

`Out-AnsiString` is for everything else: files, logs, or hosts that want strings.
`Format-AnsiPanel -Rendered` remains for framing pre-rendered ANSI text:

```powershell
$tree = Format-AnsiTree $data -MaxWidth 30 -Color DarkGray | Out-AnsiString
Format-AnsiPanel $tree -Rendered -Title 'Tree' -BorderColor BrightBlue | Out-AnsiHost
```

Two panes side by side — capture, pad on visible width, zip:

```powershell
$left = Format-AnsiGrid $kv -MaxWidth 30 | Out-AnsiString
$right = Format-AnsiTree $data -MaxWidth 30 | Out-AnsiString
$visible = { param($t) ($t -replace "`e\[[\d;]*m", '').Length }
for ($i = 0; $i -lt [Math]::Max($left.Count, $right.Count); $i++) {
    $l = if ($i -lt $left.Count) { $left[$i] } else { '' }
    $r = if ($i -lt $right.Count) { $right[$i] } else { '' }
    Write-Host ($l + (' ' * [Math]::Max(0, 30 - (& $visible $l))) + '  │  ' + $r)
}
```

## Other destinations

A rendering is just data, so anything that takes strings works:

```powershell
Format-AnsiJson $payload | Out-AnsiString -Plain | Set-Content .\payload.txt
Format-AnsiException $_ -Detail Full | Out-AnsiString -Plain -Join | Write-Error
```

## Tests

`tests/Out-Ansi.Tests.ps1` — 52 Pester 5 tests covering the rendering shape,
host painting, the anchor prefix and blank rows, `-NoNewline`, colour precedence
(`-NoColor` > rendering > detection), ANSI vs `-Plain`, `-Join`, `-WithAnchor`,
rejection of non-renderings, round-trips into `Format-AnsiPanel -Rendered`, and the
positioned frame: the cells it addresses, the single write, erase-to-end-of-line,
cursor save and restore, synchronized output, the non-terminal fallback, and that
`-Row` and `-Column` are required together.

```powershell
pwsh -File .\Invoke-Test.ps1 -Path .\tests\Out-Ansi.Tests.ps1
```
