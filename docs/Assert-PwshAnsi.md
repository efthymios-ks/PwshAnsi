# Assert-PwshAnsi

Ensures the calling script runs on pwsh 7.2+ with the latest PwshAnsi installed.
Call it as the first line of any script that may be launched from Windows PowerShell 5.1.

## Synopsis

```powershell
Assert-PwshAnsi [-Arguments <hashtable>]
                [-ScriptPath <string>]
                [-SkipUpdate]
```

## Parameters

| Name           | Type        | Default                   | Description                                                                                                            |
| -------------- | ----------- | ------------------------- | ---------------------------------------------------------------------------------------------------------------------- |
| `-Arguments`   | `hashtable` | caller's `$PSBoundParameters` | Parameters to forward to the relaunched script. Defaults to the bound parameters of the calling scope.             |
| `-ScriptPath`  | `string`    | `$MyInvocation.PSCommandPath` | Path of the script to relaunch. Defaults to the script that called this function.                                  |
| `-SkipUpdate`  | `switch`    | off                       | Skip the PwshAnsi gallery update check. Use when you want a fast startup and do not need the latest version.           |

## What it does

1. **pwsh check.** If no pwsh 7.2+ is found on the machine it installs the latest stable
   release via the official MSI (one UAC prompt for `msiexec`), then reruns the script there.
   When the script was started from a classic Windows PowerShell console window the rerun
   opens a Windows Terminal tab so PwshAnsi draws with a font that has the glyphs; Windows
   Terminal itself is installed on first use through `winget` (per user, no UAC) when it is
   missing. Otherwise the rerun stays in the same window. If pwsh 7.2+ is already present it
   is used as-is — no update is attempted.

2. **PwshAnsi update** *(unless `-SkipUpdate`)*.  
   Queries PSGallery for a newer version of PwshAnsi. If one exists it installs it for the
   current user and reruns the script so the new version is loaded.  
   If the gallery is unreachable or the install fails, a yellow warning is printed and the
   script continues on the currently loaded version.

When both are already satisfied the function returns immediately with no output.

## Behaviour on rerun

The rerun carries the caller's parameters through a CLIXML temp file so arrays, booleans,
switches, and hashtables survive intact. Each stage (`pwsh`, `module`) is marked in
`$env:PWSHANSI_RERUN` to prevent infinite loops. The marker is set as the first line of the
rerun command, so a Windows Terminal tab (started by the terminal, not this process) inherits
it too.

| Started from | Rerun |
| --- | --- |
| Classic Windows PowerShell window, double-click, right-click > Run with PowerShell | New Windows Terminal tab on pwsh, old window exits with `0` |
| Windows PowerShell tab inside Windows Terminal | Same tab |
| Editor terminal, e.g. VS Code | Same window |
| Redirected input or output, CI | Same window, exit code passed through |
| `wt.exe` missing, `winget` available | Windows Terminal installed, then a tab opens |
| `wt.exe` missing, `winget` also missing or offline | Same window |
| Already on pwsh 7.2+ | No rerun |
| Module update (stage `module`) | Same window |

## Example — minimal

```powershell
#Requires -Version 5.1

Import-Module PwshAnsi
Assert-PwshAnsi

# Everything below runs on pwsh 7.2+ with the latest PwshAnsi.
Format-AnsiText '[bold BrightGreen]Ready.[/]' | Out-AnsiHost
```

## Example — forwarding parameters

```powershell
#Requires -Version 5.1
param([string]$Target, [switch]$Verbose)

Import-Module PwshAnsi
Assert-PwshAnsi   # picks up $PSBoundParameters automatically

# $Target and $Verbose are available here, forwarded through the rerun.
```

## Example — skip the update check for a faster cold start

```powershell
Assert-PwshAnsi -SkipUpdate
```

## Notes

- `Assert-PwshAnsi` must be called from a script file, not from an interactive prompt or
  `ScriptBlock`. Pass `-ScriptPath` explicitly when calling from a wrapper.
- The MSI installer sets `ADD_PATH=1`, `USE_MU=1`, and `ENABLE_MU=1`; it never reboots the PC.
