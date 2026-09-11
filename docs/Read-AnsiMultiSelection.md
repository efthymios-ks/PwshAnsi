# Read-AnsiMultiSelection

Ticks several items with the space bar and returns them — the objects the caller
passed in, in list order. Returns `$null` when cancelled with Esc or timed out, and
an empty array when nothing was ticked.

The list is repainted in place as the cursor moves and items are toggled.
`-Grouped` takes a list of headed groups instead, and `-ToggleGroups` makes those
headers tick their whole group at once.

## Synopsis

```powershell
Read-AnsiMultiSelection [-Title] <string> [-Choices] <object[]>
                       [-LabelProperty <string>]
                       [-Grouped] [-GroupLabelProperty <string>] [-GroupChoicesProperty <string>]
                       [-ToggleGroups] [-Selected <object[]>]
                       [-Overflow <Fold|Crop|Ellipsis>]
                       [-CursorColor <string>] [-TitleColor <string>] [-ChoiceColor <string>]
                       [-GroupColor <string>] [-MarkColor <string>] [-HintColor <string>]
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
| `-Grouped`         | off                          | `-Choices` are groups, not items: a header and its members. See [Groups](#groups). |
| `-GroupLabelProperty`   | `Name`                  | Property each group's header text is read from.                              |
| `-GroupChoicesProperty` | `Choices`               | Property each group's members are read from. `Group` for `Group-Object` output. |
| `-ToggleGroups`    | off                          | Headers take a box of their own and space sets or clears the whole group. Needs `-Grouped`. `-GroupToggle` aliases it. |
| `-Selected`        | none                         | Items to start ticked, matched by value against `-Choices`.                    |
| `-CursorColor`     | `BrightCyan`                 | Colour of the `›` marker and the row it is on. `-Color` aliases it.           |
| `-MarkColor`       | `BrightGreen`                | Colour of a ticked `[✓]`, and of a group's `[✓]` or `[-]`.                    |
| `-TitleColor`      | none                         | Colour of the title. Markup inside it wins.                                  |
| `-ChoiceColor`     | none                         | Colour of the other rows.                                                    |
| `-GroupColor`      | none                         | Colour of the group headers. They are bold either way.                       |
| `-HintColor`       | `BrightBlack`                | Colour of empty boxes, the count, and the key hint.                          |
| `-PageSize`        | `10`                         | Rows shown at once; the window scrolls with the cursor.                       |
| `-Required`        | off                          | Refuse Enter while nothing is ticked.                                        |
| `-RequiredMessage` | `Select at least one item.`  | Written when `-Required` refuses.                                            |
| `-RequiredColor`   | `BrightRed`                  | Colour of that message.                                                      |
| `-Overflow`       | `Fold`         | What a choice too long for the console does: fold under its own first character, crop, or ellipsise. A hard `` `n `` in a label always breaks, and each of those lines folds in turn. |
| `-Row`, `-Column` | *cursor*      | Paint the list at that cell, 0-based and required together, as one synchronized frame. Omit both and it lands where the cursor is, as before. |
| `-TimeoutSeconds`  | `0`                          | Give up after N seconds and return `$null`.                                  |

## Keys

| Key                  | Effect                                              |
| -------------------- | --------------------------------------------------- |
| ↑ / ↓ (or `k` / `j`) | move the cursor                                      |
| Home / End           | first / last choice                                   |
| PageUp / PageDown    | move by one page                                      |
| Space                | toggles the item under the cursor, or the whole group when the cursor is on a header |
| `a`                  | ticks everything, or clears it if all are ticked      |
| Enter                | accepts the current ticks                             |
| Esc                  | cancels, returns `$null`                              |

Without `-ToggleGroups` the cursor moves straight past the headers, so every key
lands on an item.

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

## Groups

`-Grouped` says the choices are groups rather than items — a header and the items
under it. The header is shape only: no box, no cursor, skipped by every movement
key.

```powershell
$suites = @(
    @{ Name = 'Formatters'; Choices = @('Text', 'Rule', 'Path') }
    @{ Name = 'Layout'; Choices = @('Table', 'Grid', 'Panel') }
)
Read-AnsiMultiSelection 'Which suites?' $suites -Grouped -GroupColor BrightYellow
```

```
Which suites?
  Formatters
›   [✓] Text
    [ ] Rule
    [✓] Path
  Layout
    [ ] Table
    [ ] Grid
    [ ] Panel
2 selected  ↑↓ move · space toggle · a all · enter accept · esc cancel
```

`-ToggleGroups` puts the headers in the cursor's path and gives each one a box that
reports its members — `[✓]` all, `[-]` some, `[ ]` none:

```powershell
Read-AnsiMultiSelection 'Which suites?' $suites -Grouped -ToggleGroups
```

```
Which suites?
› [-] Formatters
    [✓] Text
    [ ] Rule
    [✓] Path
  [ ] Layout
    [ ] Table
    [ ] Grid
    [ ] Panel
2 selected  ↑↓ move · space toggle · a all · enter accept · esc cancel
```

Space on a header sets or clears the group whole — it never flips the members one
by one. A group already `[✓]` clears; `[-]` and `[ ]` both fill, so a part-ticked
group completes on the next space. `a` still ticks every item in every group, and
`-Selected` still pre-ticks members, with each header reporting what its members
came out as.

Only members are ever returned, in list order, headers never — whether they can be
toggled or not. The count and the position counter follow the rows the cursor can
reach: `-Grouped` counts items, `-ToggleGroups` counts headers too, and `-PageSize`
counts rows either way, because that is what the window holds.

The shape is the one `Group-Object` already hands out — name the property its
members live under:

```powershell
Get-ChildItem .\src -File | Group-Object Extension |
    Read-AnsiMultiSelection 'Which files?' -Grouped -ToggleGroups `
        -GroupChoicesProperty Group -LabelProperty Name
```

An empty group draws its header and nothing else, and toggling it does nothing. A
group with no name, or none of the members property, throws — as does
`-ToggleGroups` with no groups to toggle:

```
A group has no Name. Name every group, or name the property with -GroupLabelProperty.
Group 'Layout' has no Choices. Give every group its choices, or name the property with -GroupChoicesProperty.
Read-AnsiMultiSelection -ToggleGroups needs -Grouped: there are no groups to toggle.
```

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
`-LabelProperty` with objects, the colour parameters, a timeout, `-Grouped` with
view-only and with `-ToggleGroups` headers, `Group-Object` input, and a plan built
from the result.

## Tests

`tests/Read-AnsiMultiSelection.Tests.ps1` — 36 Pester 5 tests. The console seams are
replaced in the module scope, so scripted keys drive the prompt. Covers ticking and
unticking, list order, `a` toggling all and clearing, `-Selected`, object identity,
the checkbox rows and count, paging, `-Required` with its message, empty results,
Esc, timeouts, empty choices, and the redirected-input error — and for groups: the
boxless view-only headers, headers skipped when they cannot be toggled, members-only
results, the item count, `-ToggleGroups` filling and clearing a group whole, the
`[-]` part-ticked box from both keys and `-Selected`, other groups left untouched,
`a` across groups, the focusable-row counter, an empty group toggling nothing, and
the `-ToggleGroups` without `-Grouped` error.

```powershell
pwsh -File .\Invoke-Test.ps1 -Path .\tests\Read-AnsiMultiSelection.Tests.ps1
```
