# Read-AnsiEvent

Block until a terminal event happens.
Returns an object describing the event, or `$null` on timeout.
Renders nothing — the caller dispatches on `.Type` and decides what to redraw.

`Format-Ansi*` renderables measure against the terminal width when they are built;
`Out-AnsiHost` paints once and returns.
A static frame does not reflow on resize.
`Read-AnsiEvent` is the hook that lets a caller idle until the terminal changes shape,
then rebuild and repaint at the new size.

The `Read-Ansi*` prompts already handle resize internally through `Wait-AnsiKeyBurst` —
a resize mid-prompt rerenders the prompt itself.
`Read-AnsiEvent` is for the gaps *between* prompts:
a dashboard, a splash screen, a status page.

## Parameters

| Parameter               | Meaning                                                                     |
| ----------------------- | --------------------------------------------------------------------------- |
| `-Type`                 | Return only for events of these types. Default: all known events. Unknown names throw. |
| `-TimeoutSeconds`       | Give up after this many seconds and return `$null`. `0` waits forever.      |
| `-SettleMilliseconds`   | For `Resized`: wait until the size has been stable this long before firing. A drag emits many intermediate sizes; this collapses them into one event at the end. Default `150`. `0` fires on the first change. |

## Return value — `Resized`

| Property      | Meaning                                 |
| ------------- | --------------------------------------- |
| `Type`        | The string `'Resized'`.                 |
| `Width`       | Current window width, in cells.         |
| `Height`      | Current window height, in rows.         |
| `OldWidth`    | Width when the call began.              |
| `OldHeight`   | Height when the call began.             |

## Example — a static view that reflows on resize

```powershell
$render = {
    Clear-Host
    Format-AnsiRule 'Live dashboard' -Color BrightCyan | Out-AnsiHost
    Get-Process | Select-Object -First 10 Name, Id, CPU |
        Format-AnsiTable | Out-AnsiHost
    Format-AnsiText '[DarkGray]Resize the window to see it reflow. Ctrl+C to exit.[/]' |
        Out-AnsiHost
}

while ($true) {
    & $render
    $null = Read-AnsiEvent
}
```

The scriptblock paints at whatever width the terminal has now.
`Read-AnsiEvent` blocks until something happens.
The loop then redraws from scratch.
Dispatch on `.Type` to handle each kind the caller cares about:

```powershell
switch ($event.Type) {
    'Resized' { & $render }
}
```

## Example — fall back after a timeout

```powershell
$event = Read-AnsiEvent -Type Resized -TimeoutSeconds 30
if ($null -eq $event) {
    Format-AnsiText '[DarkGray]No resize in 30s. Carrying on.[/]' | Out-AnsiHost
} else {
    Format-AnsiText "Resized $($event.OldWidth)x$($event.OldHeight) -> $($event.Width)x$($event.Height)" |
        Out-AnsiHost
}
```
