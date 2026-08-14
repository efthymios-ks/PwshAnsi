# Read-AnsiSelection

Picks one item from a list with the arrow keys. Returns the item the caller passed
in — not its label — or `$null` when cancelled with Esc or timed out. `-Grouped`
takes a list of headed groups instead, where the headers are view only.

The list is repainted in place as the cursor moves, so the prompt occupies the same
rows throughout.

## Synopsis

```powershell
Read-AnsiSelection [-Title] <string> [-Choices] <object[]>
                  [-LabelProperty <string>]
                  [-Grouped] [-GroupLabelProperty <string>] [-GroupChoicesProperty <string>]
                  [-CursorColor <string>] [-TitleColor <string>] [-ChoiceColor <string>]
                  [-GroupColor <string>] [-HintColor <string>] [-PageSize <int>]
                  [-TimeoutSeconds <int>] [-Markdown] [-Escape]
```

## Parameters

| Name              | Default        | Description                                                                    |
| ----------------- | -------------- | ------------------------------------------------------------------------------ |
| `-Title`          | —              | Row above the list. Parsed as markup; `-Markdown` adds sugar, `-Escape` turns parsing off. |
| `-Choices`        | —              | The items. Accepts pipeline input. Empty throws.                                |
| `-LabelProperty`  | none           | Property to label objects with. `-ChoiceLabelProperty` aliases it.               |
| `-Grouped`        | off            | `-Choices` are groups, not items: a header and its members. See [Groups](#groups). |
| `-GroupLabelProperty`   | `Name`   | Property each group's header text is read from.                                  |
| `-GroupChoicesProperty` | `Choices` | Property each group's members are read from. `Group` for `Group-Object` output. |
| `-CursorColor`    | `BrightCyan`   | Colour of the `›` marker and the row it is on. `-Color` aliases it.              |
| `-TitleColor`     | none           | Colour of the title. Markup inside it wins.                                     |
| `-ChoiceColor`    | none           | Colour of the other rows.                                                       |
| `-GroupColor`     | none           | Colour of the group headers. They are bold either way.                          |
| `-HintColor`      | `BrightBlack`  | Colour of the key hint and the position counter.                                 |
| `-PageSize`       | `10`           | Rows shown at once; the window scrolls with the cursor.                          |
| `-TimeoutSeconds` | `0`            | Give up after N seconds and return `$null`.                                     |

## Keys

| Key                  | Effect                          |
| -------------------- | ------------------------------- |
| ↑ / ↓ (or `k` / `j`) | move the cursor                 |
| Home / End           | first / last choice              |
| PageUp / PageDown    | move by one page                 |
| Enter                | selects the current item         |
| Esc                  | cancels, returns `$null`         |

Anything else is ignored. The cursor stops at the ends rather than wrapping, and
with `-Grouped` it moves straight past the headers — every key lands on an item.

## What it draws

```
Pick a fruit
› Apple
  Banana
  Cherry
1/5  ↑↓ move · enter select · esc cancel
```

The counter appears only when the list is longer than `-PageSize`.

## Groups

`-Grouped` says the choices are groups rather than items — a header and the items
under it:

```powershell
$fruit = @(
    @{ Name = 'Berries'; Choices = @('Strawberry', 'Raspberry') }
    @{ Name = 'Citrus'; Choices = @('Lemon', 'Lime') }
)
Read-AnsiSelection 'Pick a fruit' $fruit -Grouped -GroupColor BrightYellow
```

```
Pick a fruit
  Berries
›   Strawberry
    Raspberry
  Citrus
    Lemon
    Lime
1/4  ↑↓ move · enter select · esc cancel
```

A header is view only here: it is bold, it takes no `›`, and the cursor never
stops on it — ↑↓, Home/End and paging all land on an item. The counter counts
items, so `1/4` above ignores the two headers; `-PageSize` counts rows, headers
included, because that is what the window holds.

Members are labelled and returned exactly as an ungrouped list's are, so
`-LabelProperty` reads objects inside the groups and Enter gives back the object:

```powershell
$grouped = @(
    @{ Name = 'Formatters'; Choices = @(Get-Formatter) }
    @{ Name = 'Prompts'; Choices = @(Get-Prompt) }
)
$chosen = Read-AnsiSelection 'Pick a component' $grouped -Grouped -LabelProperty Name
```

The shape is the one `Group-Object` already hands out — name the property its
members live under:

```powershell
Get-ChildItem .\src -File | Group-Object Extension |
    Read-AnsiSelection 'Which file?' -Grouped -GroupChoicesProperty Group -LabelProperty Name
```

An empty group draws its header and nothing else. A group with no name, or none of
the members property, throws:

```
A group has no Name. Name every group, or name the property with -GroupLabelProperty.
Group 'Berries' has no Choices. Give every group its choices, or name the property with -GroupChoicesProperty.
```

Groups holding no items at all leave nothing to pick, which is the empty-choices
error.

## Objects and labels

```powershell
$components = @(
    [PSCustomObject]@{ Name = 'Format-AnsiText'; Tests = 147 }
    [PSCustomObject]@{ Name = 'Format-AnsiTable'; Tests = 79 }
)
$chosen = Read-AnsiSelection 'Pick a component' $components -LabelProperty Name
$chosen.Tests        # the object came back, not the string
```

Labels are parsed as markup, so a list can carry its own colour:

```powershell
Read-AnsiSelection '[bold]Environment[/]' @('[BrightGreen]Dev[/]', '[BrightRed]Production[/]')
```

## Non-interactive and NO_COLOR

Throws when input is redirected, and when `-Choices` is empty:

```
Read-AnsiSelection needs an interactive console: input is redirected.
Read-AnsiSelection needs at least one choice.
```

`NO_COLOR` strips the styles but keeps the layout: the `›` marker, the window, and
the hint stay, and cursor control is still emitted so the redraw works.


**The cursor.** Hidden while this prompt owns the keyboard — nothing is typed here,
and a list redrawn under a blinking cursor reads as flicker — and put back to
whatever it was on the way out. Redirected output gets no cursor sequences at all.

## Usage patterns

**Choose a target, then act on it**

```powershell
$target = Read-AnsiSelection 'Deploy to' @('Dev', 'Staging', 'Production')
if ($null -eq $target) { return }
Format-AnsiPanel "deploying to [BrightWhite]$target[/]" -BorderColor BrightGreen | Out-AnsiHost
```

**Pick from cmdlet output**

```powershell
$branch = Get-ChildItem .\src -File | Read-AnsiSelection 'Which file?' -LabelProperty Name
```

## Demo

```powershell
pwsh -File .\demo\Demo-ReadAnsiSelection.ps1
```

Interactive: a short list, `-PageSize` paging, `-LabelProperty` with objects,
markup titles and labels, the colour parameters, a timeout, `-Grouped` on both a
literal list and `Group-Object` output, and choosing a deploy target.

## Tests

`tests/Read-AnsiSelection.Tests.ps1` — 42 Pester 5 tests. The console seams are
replaced in the module scope, so scripted keys drive the prompt and the painted
rows are asserted frame by frame. Covers every movement key, the ends of the list,
paging and the scrolling window, the position counter, the cursor marker, in-place
redraw, `-LabelProperty` and object identity, pipeline input, markup and `-Escape`,
Esc, timeouts, empty choices, the redirected-input error, and `NO_COLOR` — and for
`-Grouped`: the drawn headers and indented members, headers skipped by every
movement key, page moves snapping onto an item, the item-only counter, labels and
object identity inside groups, `Group-Object` input, `-GroupColor`, empty groups,
and both malformed-group errors.

```powershell
pwsh -File .\Invoke-Test.ps1 -Path .\tests\Read-AnsiSelection.Tests.ps1
```
