# Read-AnsiMultiSelection

Ticks several items with the space bar and returns them — the objects the caller
passed in, in list order. Returns `$null` when cancelled with Esc or timed out, and
an empty array when nothing was ticked.

The list is repainted in place as the cursor moves and items are toggled.

## Synopsis

```powershell
Read-AnsiMultiSelection [-Title] <string> [-Choices] <object[]>
                       [-LabelProperty <string>] [-Selected <object[]>]
                       [-CursorColor <string>] [-TitleColor <string>] [-ChoiceColor <string>]
                       [-MarkColor <string>] [-HintColor <string>]
                       [-PageSize <int>] [-Required] [-RequiredMessage <string>]
                       [-RequiredColor <string>] [-TimeoutSeconds <int>]
                       [-Markdown] [-Escape]
```

## Parameters

| Name               | Default                      | Description                                                                 |
| ------------------ | ---------------------------- | --------------------------------------------------------------------------- |
| `-Title`           | —                            | Row above the list. Parsed as markup; `-Markdown` adds sugar, `-Escape` turns parsing off. |
| `-Choices`         | —                            | The items. Accepts pipeline input. Empty throws.                             |
| `-LabelProperty`   | none                         | Property to label objects with. `-ChoiceLabelProperty` aliases it.            |
| `-Selected`        | none                         | Items to start ticked, matched by value against `-Choices`.                    |
| `-CursorColor`     | `BrightCyan`                 | Colour of the `›` marker and the row it is on. `-Color` aliases it.           |
| `-MarkColor`       | `BrightGreen`                | Colour of a ticked `[✓]`.                                                    |
| `-TitleColor`      | none                         | Colour of the title. Markup inside it wins.                                  |
| `-ChoiceColor`     | none                         | Colour of the other rows.                                                    |
| `-HintColor`       | `BrightBlack`                | Colour of empty boxes, the count, and the key hint.                          |
| `-PageSize`        | `10`                         | Rows shown at once; the window scrolls with the cursor.                       |
| `-Required`        | off                          | Refuse Enter while nothing is ticked.                                        |
| `-RequiredMessage` | `Select at least one item.`  | Written when `-Required` refuses.                                            |
| `-RequiredColor`   | `BrightRed`                  | Colour of that message.                                                      |
| `-TimeoutSeconds`  | `0`                          | Give up after N seconds and return `$null`.                                  |

## Keys

| Key                  | Effect                                              |
| -------------------- | --------------------------------------------------- |
| ↑ / ↓ (or `k` / `j`) | move the cursor                                      |
| Home / End           | first / last choice                                   |
| PageUp / PageDown    | move by one page                                      |
| Space                | toggles the item under the cursor                     |
| `a`                  | ticks everything, or clears it if all are ticked      |
| Enter                | accepts the current ticks                             |
| Esc                  | cancels, returns `$null`                              |

## What it draws

```
Which suites?
› [✓] Text
  [ ] Rule
  [✓] Path
2 selected  ↑↓ move · space toggle · a all · enter accept · esc cancel
```

A position counter is prefixed when the list is longer than `-PageSize`, and the
row under the hint carries the `-Required` message when Enter is refused.

## Returning objects

```powershell
$components = @(
    [PSCustomObject]@{ Name = 'Format-AnsiText'; Tests = 147 }
    [PSCustomObject]@{ Name = 'Format-AnsiTable'; Tests = 79 }
)
$chosen = Read-AnsiMultiSelection 'Which components?' $components -LabelProperty Name
Format-AnsiTable @($chosen) | Out-AnsiHost      # the objects came back
```

Results come back in list order, not in the order they were ticked.

## Empty results, cancel, and timeout

| Outcome              | Value          |
| -------------------- | -------------- |
| Enter, nothing ticked | empty array    |
| Enter, some ticked    | array of items |
| Esc                   | `$null`        |
| Timeout               | `$null`        |

`-Required` turns the first case into a re-prompt instead.

## Non-interactive and NO_COLOR

Throws when input is redirected, and when `-Choices` is empty:

```
Read-AnsiMultiSelection needs an interactive console: input is redirected.
Read-AnsiMultiSelection needs at least one choice.
```

`NO_COLOR` strips the styles but keeps the boxes, ticks, window, and hint.


**The cursor.** Hidden while this prompt owns the keyboard — nothing is typed here,
and a list redrawn under a blinking cursor reads as flicker — and put back to
whatever it was on the way out. Redirected output gets no cursor sequences at all.

## Usage patterns

**Let the selection drive what runs**

```powershell
$run = Read-AnsiMultiSelection 'Run which steps?' @('Restore', 'Build', 'Test') -Selected 'Build', 'Test'
foreach ($step in $run) { & "Invoke-$step" }
```

**Show the plan before acting**

```powershell
$rows = foreach ($step in $all) {
    , @("[DarkGray]$step[/]", $(if ($run -contains $step) { '[BrightGreen]Will run[/]' } else { '[BrightBlack]Skipped[/]' }))
}
Format-AnsiPanel (Format-AnsiGrid $rows -Padding 3) -Title 'Plan' | Out-AnsiHost
```

## Demo

```powershell
pwsh -File .\demo\Demo-ReadAnsiMultiSelection.ps1
```

Interactive: ticking, `a` for all, `-Selected`, paging, `-Required`,
`-LabelProperty` with objects, the colour parameters, a timeout, and a plan built
from the result.

## Tests

`tests/Read-AnsiMultiSelection.Tests.ps1` — 19 Pester 5 tests. The console seams are
replaced in the module scope, so scripted keys drive the prompt. Covers ticking and
unticking, list order, `a` toggling all and clearing, `-Selected`, object identity,
the checkbox rows and count, paging, `-Required` with its message, empty results,
Esc, timeouts, empty choices, and the redirected-input error.

```powershell
pwsh -File .\Invoke-Test.ps1 -Path .\tests\Read-AnsiMultiSelection.Tests.ps1
```
