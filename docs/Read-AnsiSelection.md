# Read-AnsiSelection

Picks one item from a list with the arrow keys. Returns the item the caller passed
in — not its label — or `$null` when cancelled with Esc or timed out.

The list is repainted in place as the cursor moves, so the prompt occupies the same
rows throughout.

## Synopsis

```powershell
Read-AnsiSelection [-Title] <string> [-Choices] <object[]>
                  [-LabelProperty <string>]
                  [-CursorColor <string>] [-TitleColor <string>] [-ChoiceColor <string>]
                  [-HintColor <string>] [-PageSize <int>]
                  [-TimeoutSeconds <int>] [-Markdown] [-Escape]
```

## Parameters

| Name              | Default        | Description                                                                    |
| ----------------- | -------------- | ------------------------------------------------------------------------------ |
| `-Title`          | —              | Row above the list. Parsed as markup; `-Markdown` adds sugar, `-Escape` turns parsing off. |
| `-Choices`        | —              | The items. Accepts pipeline input. Empty throws.                                |
| `-LabelProperty`  | none           | Property to label objects with. `-ChoiceLabelProperty` aliases it.               |
| `-CursorColor`    | `BrightCyan`   | Colour of the `›` marker and the row it is on. `-Color` aliases it.              |
| `-TitleColor`     | none           | Colour of the title. Markup inside it wins.                                     |
| `-ChoiceColor`    | none           | Colour of the other rows.                                                       |
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

Anything else is ignored. The cursor stops at the ends rather than wrapping.

## What it draws

```
Pick a fruit
› Apple
  Banana
  Cherry
1/5  ↑↓ move · enter select · esc cancel
```

The counter appears only when the list is longer than `-PageSize`.

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
markup titles and labels, the colour parameters, a timeout, and choosing a deploy
target.

## Tests

`tests/Read-AnsiSelection.Tests.ps1` — 27 Pester 5 tests. The console seams are
replaced in the module scope, so scripted keys drive the prompt and the painted
rows are asserted frame by frame. Covers every movement key, the ends of the list,
paging and the scrolling window, the position counter, the cursor marker, in-place
redraw, `-LabelProperty` and object identity, pipeline input, markup and `-Escape`,
Esc, timeouts, empty choices, the redirected-input error, and `NO_COLOR`.

```powershell
pwsh -File .\Invoke-Test.ps1 -Path .\tests\Read-AnsiSelection.Tests.ps1
```
