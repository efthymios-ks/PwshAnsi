# Ansi.Input *(internal)*

The shared input layer every `Read-Ansi*` prompt uses rather than rolling its own key loop.
Not exported from the top-level module —
these notes exist so a reader of the prompt sources can see what the primitives guarantee.

## Key burst grouping

`Read-AnsiKeyBurst` blocks for the first key and then drains whatever is already queued.
A paste arrives as a burst;
the prompt applies every key in order and repaints once,
so a pasted path does not stutter.
The burst limit caps at 512 keys before a forced repaint,
so a very long paste becomes two bursts rather than one frozen frame.

## Field state

`New-AnsiFieldState` and `Update-AnsiFieldState` track the text, the caret position, and the scroll window.
`Get-AnsiFieldView` returns the slice that fits the visible width and the caret column within that slice,
so the caret stays on screen regardless of how wide the text grows.
Pasted line breaks are kept in the value and drawn as `\n` (two columns),
so a multi-line paste lands whole in one field.

## Positioned rendering

`Write-AnsiPromptFrame` can paint at an arbitrary cell
(the `-Row` and `-Column` parameters on each prompt)
as a single synchronized write rather than walking the cursor up line by line.
`Set-AnsiPromptCursor` places the caret back after each frame,
because a synchronized write restores the caller's cursor position.

## Resize

`Wait-AnsiKeyBurst` polls the terminal size while waiting for a key.
When the size changes and settles —
unchanged for the settle window —
it returns a one-element burst carrying the resize sentinel from `New-AnsiResizeSignal`.
Prompts dispatch on `.Key` and treat it as a repaint trigger:
rebuild rows against the new width, then repaint.

For anchored prompts the previous frame's rows may have wrapped at the old width,
so a straight walk-up-and-rewrite would land mid-stale-frame.
`Reset-AnsiPromptRegion` jumps to the row the frame began on
and lets the terminal clear everything below before the next paint.

For non-prompt callers that only need to react to resize,
see [`Read-AnsiEvent`](Read-AnsiEvent.md) — it exposes the same primitive.

## Testable seams

The console calls (`ReadKey`, `KeyAvailable`, `Wait`, `GetWindowSize`)
are passed in as scriptblocks rather than called directly.
The test suite replaces them in the module scope,
so a scripted key list and a scripted size reading drive every prompt —
no keyboard, no waiting, no console.
