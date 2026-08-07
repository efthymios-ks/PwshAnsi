# Read-AnsiPause

Waits for a key before carrying on. Returns `$true` when a key was pressed,
`$false` on Esc, and `$null` when the timeout expires — so a pause can also act as
a checkpoint the caller may abort.

The message row is transient by default: it is erased once the key arrives, leaving
no trace in the transcript.

## Synopsis

```powershell
Read-AnsiPause [[-Message] <string>] [-Enter] [-MessageColor <string>]
              [-TimeoutSeconds <int>] [-ShowCountdown] [-KeepMessage]
              [-Markdown] [-Escape]
```

## Parameters

| Name              | Default                            | Description                                                                |
| ----------------- | ---------------------------------- | -------------------------------------------------------------------------- |
| `-Message`        | `Press any key to continue`        | The row to show. `-Prompt` aliases it. Parsed as markup; `-Markdown` adds sugar, `-Escape` turns parsing off. |
| `-Enter`          | off                                | Wait for Enter specifically; other keys are ignored. Default message becomes `Press enter to continue`. |
| `-MessageColor`   | `BrightBlack`                      | Colour of the message. `-Color` aliases it. Markup inside the message wins.  |
| `-TimeoutSeconds` | `0` (wait forever)                 | Give up after N seconds and return `$null`.                                 |
| `-ShowCountdown`  | off                                | Append the seconds left, ticking in place. Needs `-TimeoutSeconds`.          |
| `-KeepMessage`    | off                                | Leave the message on screen instead of erasing it.                           |

## Keys

| Key   | Result   |
| ----- | -------- |
| any   | `$true`  |
| Enter | `$true`  |
| Esc   | `$false` |

With `-Enter`, only Enter and Esc are acted on.

```powershell
Read-AnsiPause
Read-AnsiPause 'Next page' -Enter
Read-AnsiPause ':warn: **Read this**, then continue' -Markdown -MessageColor BrightYellow
Read-AnsiPause 'Continuing shortly' -TimeoutSeconds 5 -ShowCountdown
Read-AnsiPause 'This line stays' -KeepMessage
```

## Non-interactive and NO_COLOR

Throws when input is redirected — a pause that cannot be released must fail rather
than hang:

```
Read-AnsiPause needs an interactive console: input is redirected.
```

`NO_COLOR` strips the styles and keeps the wording. Cursor control is still emitted
so the erase and the countdown work.


**The cursor.** Hidden while this prompt owns the keyboard — nothing is typed here,
and a list redrawn under a blinking cursor reads as flicker — and put back to
whatever it was on the way out. Redirected output gets no cursor sequences at all.

## Usage patterns

**Page through output**

```powershell
foreach ($page in $pages) {
    Format-AnsiPanel $page | Out-AnsiHost
    if (-not (Read-AnsiPause 'Next page' -Enter)) { break }   # Esc stops paging
}
```

**A last look before something destructive**

```powershell
Format-AnsiPanel $whatWillHappen -Title 'Review' -BorderColor BrightRed | Out-AnsiHost
if (-not (Read-AnsiPause 'Press a key to proceed, esc to abort')) { return }
```

**Continue on its own if nobody is watching**

```powershell
$answer = Read-AnsiPause 'Continuing in a moment' -TimeoutSeconds 10 -ShowCountdown
if ($null -eq $answer) { 'Unattended — carrying on' }
```

## Demo

```powershell
pwsh -File .\demo\Demo-ReadAnsiPause.ps1
```

Interactive: any key, `-Enter`, custom and markdown messages, `-KeepMessage`, a
timeout, a countdown, Esc, paging through renderings, and a destructive-step
checkpoint.

## Tests

`tests/Read-AnsiPause.Tests.ps1` — 27 Pester 5 tests. The console seams
(`Test-AnsiInteractive`, `Test-AnsiKeyAvailable`, `Read-AnsiKeyInfo`, `Start-AnsiWait`)
are replaced in the module scope, so scripted keys drive the pause. Covers any key,
Enter, arrows, Esc, `-Enter` filtering, the default and custom messages, markup,
`-Markdown`, `-Escape`, colours, erasing versus `-KeepMessage`, timeouts,
`-ShowCountdown`, the redirected-input error, and `NO_COLOR`.

```powershell
pwsh -File .\Invoke-Test.ps1 -Path .\tests\Read-AnsiPause.Tests.ps1
```
