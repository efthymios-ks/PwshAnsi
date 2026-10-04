#Requires -Version 7.2

# Read-AnsiEvent.psm1
# Public: Read-AnsiEvent — block until a terminal event happens.
# Returns a @{ Type; ... } object, or $null on timeout. Renders nothing;
# the caller dispatches on .Type and decides what to redraw.
#
# Pair it with a render scriptblock for a view that reflows between prompts:
#
#     $render = { Clear-Host; Format-AnsiRule 'Hello' | Out-AnsiHost }
#     while ($true) {
#         & $render
#         $null = Read-AnsiEvent
#     }
#
# The Read-Ansi* prompts already handle resize internally through
# Wait-AnsiKeyBurst; Read-AnsiEvent exposes the same primitive for callers
# with no prompt in the way.

Import-Module (Join-Path $PSScriptRoot 'Ansi.Core.psm1') -Force -DisableNameChecking

function Read-AnsiEvent {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        # Only return for events of these types. Default: all known events.
        # Unknown names throw at the door so a typo does not silently block forever.
        [ValidateSet('Resized')]
        [string[]]$Type,

        # Give up after this many seconds and return $null. 0 (the default) waits
        # forever - until an event arrives, or Ctrl+C.
        [ValidateRange(0, [int]::MaxValue)]
        [int]$TimeoutSeconds = 0,

        # How long the size must stay unchanged before 'Resized' fires. A terminal
        # drag emits many intermediate sizes; this collapses them into one event
        # at the end of the drag. 0 fires on the first change seen.
        [ValidateRange(0, [int]::MaxValue)]
        [int]$SettleMilliseconds = 150
    )

    if (-not (Test-AnsiInteractive)) {
        throw 'Read-AnsiEvent needs an interactive console: input is redirected.'
    }

    # Seams so a test can drive the loop without a real console.
    $getWindowSize = { Get-AnsiWindowSize }
    $wait = { Start-AnsiWait }

    $wantResize = (-not $Type) -or ($Type -contains 'Resized')

    $baseline = & $getWindowSize
    $lastSeen = $baseline
    $lastChangeAt = $null
    $deadline = if ($TimeoutSeconds -gt 0) { [datetime]::UtcNow.AddSeconds($TimeoutSeconds) } else { $null }

    while ($true) {
        if ($null -ne $deadline -and [datetime]::UtcNow -ge $deadline) { return $null }

        if ($wantResize) {
            $current = & $getWindowSize

            if ($current.Width -ne $lastSeen.Width -or $current.Height -ne $lastSeen.Height) {
                # Still being resized: restart the settle clock on every change.
                $lastSeen = $current
                $lastChangeAt = [datetime]::UtcNow
            } elseif ($null -ne $lastChangeAt -and
                      ([datetime]::UtcNow - $lastChangeAt).TotalMilliseconds -ge $SettleMilliseconds) {
                if ($lastSeen.Width -ne $baseline.Width -or $lastSeen.Height -ne $baseline.Height) {
                    return [PSCustomObject]@{
                        Type      = 'Resized'
                        Width     = $lastSeen.Width
                        Height    = $lastSeen.Height
                        OldWidth  = $baseline.Width
                        OldHeight = $baseline.Height
                    }
                }
                # Drag that ended back on the baseline: no event, keep waiting.
                $lastChangeAt = $null
            }
        }

        & $wait
    }
}

Export-ModuleMember -Function Read-AnsiEvent
