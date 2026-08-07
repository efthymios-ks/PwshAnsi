# Start-AnsiTitleAnimation, Stop-AnsiTitleAnimation, Invoke-AnsiTitleAnimation

Turns the braille dots in the terminal's window title while your code runs, so a
long job stays visible on the taskbar even when the window is behind something else.

The three functions share one piece of state, so they live in one module.

```powershell
$null = Start-AnsiTitleAnimation 'Building'
# ... long job ...
Stop-AnsiTitleAnimation

Invoke-AnsiTitleAnimation -Text 'Running tests' -ScriptBlock { ./Invoke-Test.ps1 }
```

The title reads `⠋ building`, `⠙ building`, `⠹ building` … turning at a quarter
second a frame.

## One animation, no styles

The dots are `⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏` and there is nothing to choose: a spinner is what a title
bar can actually show.

- Emoji do not survive a console title — a surrogate pair arrives as `?`.
- A marker sliding along a track needs padding, and a title bar renders in a
  proportional font, so the movement is mush and the text beside it shifts.
- Braille frames are single BMP characters. Each one lands, and the text next to
  them never moves.

The title is set with `[Console]::Title`, which is `SetConsoleTitleW` on Windows and
an escape sequence written by .NET elsewhere. Writing OSC 2 by hand would go through
`[Console]::OutputEncoding` — code page 437 in a default console, where the frames
come out as question marks.

The frames tick from a second runspace running plain .NET, so they keep moving while
the main thread sits inside a long synchronous command — which is exactly when a
title animation earns its keep.

Nothing is animated when output is redirected: a non-interactive host has no title
bar. `-Force` overrides that.

## Start-AnsiTitleAnimation

```powershell
Start-AnsiTitleAnimation [[-Text] <string>] [-Speed <Slow|Normal|Fast>] [-FrameLast] [-Force]
```

| Parameter    | Default  | Description                                       |
| ------------ | -------- | ------------------------------------------------- |
| `-Text`      | none     | Text beside the dots, e.g. `building`. Optional.   |
| `-Speed`     | `Normal` | How fast the dots turn.                            |
| `-FrameLast` | off      | Dots on the right of the text instead of the left. |
| `-Force`     | off      | Animate even when output is redirected.            |

Returns `$true` when an animation started, `$false` when it was skipped. Throws if
one is already running.

| `-Speed` | A frame every |
| -------- | ------------- |
| `Slow`   | 500 ms        |
| `Normal` | 250 ms        |
| `Fast`   | 100 ms        |

Three names, not a millisecond dial: `Normal` is a calm turn — a title bar is
glanced at, not watched — and picking 137 ms is not a decision anyone needs to make.

## Stop-AnsiTitleAnimation

```powershell
Stop-AnsiTitleAnimation [[-Title] <string>]
```

Stops the worker and puts back the title that was there before starting, or the
`-Title` you pass (including an empty one). Calling it with nothing running does
nothing, and calling it twice is safe.

## Invoke-AnsiTitleAnimation

```powershell
Invoke-AnsiTitleAnimation [-ScriptBlock] <scriptblock> [[-Text] <string>]
                         [-Speed <Slow|Normal|Fast>] [-FrameLast] [-Force]
                         [-FinalTitle <string>]
```

Starts the animation, runs the scriptblock, and stops in a `finally` — so the title
is restored even when the scriptblock throws. The scriptblock's output passes
straight through, and `-FinalTitle` leaves a chosen title behind.

```powershell
$rows = Invoke-AnsiTitleAnimation -Text 'Querying' -ScriptBlock { Invoke-Sqlcmd -Query $sql }
Invoke-AnsiTitleAnimation -Text 'Building' -FinalTitle 'Build done' -ScriptBlock { ./build.ps1 }
```

## Usage patterns

**Wrap the slow thing, keep printing**

```powershell
Invoke-AnsiTitleAnimation -Text 'Running tests' -ScriptBlock {
    foreach ($suite in $suites) {
        Format-AnsiGrid @(, @($suite, 'Passed')) | Out-AnsiHost   # the pane stays usable
    }
}
```

**Show state in the taskbar, not the pane**

```powershell
$null = Start-AnsiTitleAnimation 'Deploying' -FrameLast
try { Invoke-Deploy } finally { Stop-AnsiTitleAnimation -Title 'Deploy finished' }
```

## When the title does not move

The animation sets the title; the terminal decides whether to show it. Windows
Terminal ignores it when the profile has `suppressApplicationTitle` or a fixed
`tabTitle`, and some multiplexers rewrite it per prompt. Section 0 of the demo reads
the title back while animating, which tells you which side is at fault.

## Demo

```powershell
pwsh -File .\demo\Demo-AnsiTitleAnimation.ps1
```

Watch the window title, not the pane: a self check that reads the title back, the
dots turning, `-FrameLast`, all three speeds, no text at all,
`Invoke-AnsiTitleAnimation` around a job, restoration after a failure, `-FinalTitle`,
and a long job that keeps printing.

## Tests

`tests/Start-AnsiTitleAnimation.Tests.ps1` — 34 Pester 5 tests. The terminal seams
(`Test-AnsiTitleSupported`, `Get-AnsiTitleCurrent`, `Set-AnsiTitle`) and the worker
(`Start-AnsiTitleWorker`, `Stop-AnsiTitleWorker`) are replaced in the module scope, so
frames and lifecycle are asserted with no second runspace, no title bar, and no
sleeping. Covers the ten frames, the one-BMP-character-per-frame rule, the absence
of anything to configure, each `-Speed` and its interval, dots left and right, the
text staying put as they turn, the redirected no-op and `-Force`,
double-start refusal, restart after stop, restoration on stop and on a throw,
`-Title`/`-FinalTitle`, pass-through of the scriptblock's output, and that the title
is set through `Console::Title` rather than an encoded write.

```powershell
pwsh -File .\Invoke-Test.ps1 -Path .\tests\Start-AnsiTitleAnimation.Tests.ps1
```
