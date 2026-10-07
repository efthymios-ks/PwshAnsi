#Requires -Version 7.2
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

# Assert-PwshAnsi.Tests.ps1
# Pester 5 tests for the internal rerun helpers in Assert-PwshAnsi.psm1.
# Invoke-AnsiRerun itself is not covered: both of its paths end in `exit`,
# which would end the Pester run.

BeforeAll {
    $script:src = Join-Path (Split-Path -Parent $PSScriptRoot) 'src'
    Import-Module (Join-Path $script:src 'Assert-PwshAnsi.psm1') -Force -DisableNameChecking
    $script:AnsiModule = Get-Module Assert-PwshAnsi
}

Describe 'Test-AnsiClassicConsole' {
    BeforeEach {
        $script:priorWt = $env:WT_SESSION
        $script:priorTerm = $env:TERM_PROGRAM
        Remove-Item env:WT_SESSION -ErrorAction SilentlyContinue
        Remove-Item env:TERM_PROGRAM -ErrorAction SilentlyContinue
    }
    AfterEach {
        if ($null -ne $script:priorWt) { $env:WT_SESSION = $script:priorWt } else { Remove-Item env:WT_SESSION -ErrorAction SilentlyContinue }
        if ($null -ne $script:priorTerm) { $env:TERM_PROGRAM = $script:priorTerm } else { Remove-Item env:TERM_PROGRAM -ErrorAction SilentlyContinue }
    }

    It 'returns $false when WT_SESSION is set' {
        $env:WT_SESSION = '{00000000-0000-0000-0000-000000000000}'
        (& $script:AnsiModule { Test-AnsiClassicConsole }) | Should -BeFalse
    }

    It 'returns $false when TERM_PROGRAM is set' {
        $env:TERM_PROGRAM = 'vscode'
        (& $script:AnsiModule { Test-AnsiClassicConsole }) | Should -BeFalse
    }
}

Describe 'Get-AnsiTerminalTabArgument' {
    BeforeAll {
        $script:pwsh = 'C:\Program Files\PowerShell\7\pwsh.exe'
        $script:encoded = 'ZQBuAGMAbwBkAGUAZAA='
    }

    It 'starts with -w 0 new-tab, quotes pwsh, ends with -EncodedCommand then the value' {
        Push-Location C:\
        try {
            $out = & $script:AnsiModule {
                param($pwsh, $enc) Get-AnsiTerminalTabArgument -Pwsh $pwsh -EncodedCommand $enc
            } $script:pwsh $script:encoded
        }
        finally { Pop-Location }

        $out | Should -Match '^-w 0 new-tab '
        $out | Should -Match ([regex]::Escape('"' + $script:pwsh + '"'))
        $out | Should -Match ('-EncodedCommand ' + [regex]::Escape($script:encoded) + '$')
    }

    It 'escapes a semicolon in the current folder and quotes it with -d' {
        $root = Join-Path ([IO.Path]::GetTempPath()) ('PwshAnsi-test {0};x' -f [guid]::NewGuid())
        $null = New-Item -ItemType Directory -Path $root
        try {
            Push-Location -LiteralPath $root
            try {
                $out = & $script:AnsiModule {
                    param($pwsh, $enc) Get-AnsiTerminalTabArgument -Pwsh $pwsh -EncodedCommand $enc
                } $script:pwsh $script:encoded
            }
            finally { Pop-Location }

            $expected = '-d "{0}"' -f ($root.Replace(';', '\;'))
            $out | Should -Match ([regex]::Escape($expected))
        }
        finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'escapes a trailing backslash in a drive root' {
        $drive = (Get-Location).Drive.Root
        if (-not $drive) { Set-ItResult -Skipped -Because 'no drive root available'; return }
        Push-Location -LiteralPath $drive
        try {
            $out = & $script:AnsiModule {
                param($pwsh, $enc) Get-AnsiTerminalTabArgument -Pwsh $pwsh -EncodedCommand $enc
            } $script:pwsh $script:encoded
        }
        finally { Pop-Location }

        $expected = '-d "{0}\\"' -f $drive.TrimEnd('\')
        $out | Should -Match ([regex]::Escape($expected))
    }

    It 'omits -d from a non-filesystem location (HKCU:\)' {
        Push-Location HKCU:\
        try {
            $out = & $script:AnsiModule {
                param($pwsh, $enc) Get-AnsiTerminalTabArgument -Pwsh $pwsh -EncodedCommand $enc
            } $script:pwsh $script:encoded
        }
        finally { Pop-Location }

        $out | Should -Not -Match '(^|\s)-d\s'
    }
}

Describe 'Find-AnsiTerminal' {
    It 'returns the wt.exe source when Get-Command finds it' {
        $expected = 'X:\fake\wt.exe'
        $actual = & $script:AnsiModule {
            param($path)
            function Get-Command { param($Name, $CommandType, $ErrorAction)
                [pscustomobject]@{ Source = $path }
            }
            Find-AnsiTerminal
        } $expected
        $actual | Should -Be $expected
    }

    It 'falls back to the per-user WindowsApps alias when PATH has no wt.exe' {
        $tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('PwshAnsi-wt-{0}' -f [guid]::NewGuid())
        $aliasDir = Join-Path $tempRoot 'Microsoft\WindowsApps'
        $null = New-Item -ItemType Directory -Path $aliasDir -Force
        $aliasPath = Join-Path $aliasDir 'wt.exe'
        $null = New-Item -ItemType File -Path $aliasPath
        try {
            $prior = $env:LOCALAPPDATA
            $env:LOCALAPPDATA = $tempRoot
            try {
                $actual = & $script:AnsiModule {
                    function Get-Command { param($Name, $CommandType, $ErrorAction) $null }
                    Find-AnsiTerminal
                }
            } finally { $env:LOCALAPPDATA = $prior }
            $actual | Should -Be $aliasPath
        }
        finally { Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'returns $null when wt.exe is nowhere' {
        $prior = $env:LOCALAPPDATA
        $env:LOCALAPPDATA = (Join-Path ([IO.Path]::GetTempPath()) ('PwshAnsi-empty-{0}' -f [guid]::NewGuid()))
        try {
            $actual = & $script:AnsiModule {
                function Get-Command { param($Name, $CommandType, $ErrorAction) $null }
                Find-AnsiTerminal
            }
            $actual | Should -BeNullOrEmpty
        }
        finally { $env:LOCALAPPDATA = $prior }
    }
}

Describe 'Install-AnsiWindowsTerminal' {
    It 'throws when winget is missing' {
        {
            & $script:AnsiModule {
                function Get-Command { param($Name, $CommandType, $ErrorAction) $null }
                Install-AnsiWindowsTerminal
            }
        } | Should -Throw '*winget is not available*'
    }

    It 'runs winget with the expected arguments and succeeds on exit 0' {
        $capturedArgs = $null
        & $script:AnsiModule {
            param($argsRef)
            function Get-Command { param($Name, $CommandType, $ErrorAction)
                [pscustomobject]@{ Source = 'X:\fake\winget.exe' }
            }
            function Start-Process {
                param($FilePath, $ArgumentList, [switch]$Wait, [switch]$PassThru, [switch]$NoNewWindow, $ErrorAction)
                $argsRef.Value = $ArgumentList
                [pscustomobject]@{ ExitCode = 0 }
            }
            function Write-AnsiLog { param($Message, [switch]$Outcome) }
            Install-AnsiWindowsTerminal
        } ([ref]$capturedArgs)

        $capturedArgs | Should -Contain '--id'
        $capturedArgs | Should -Contain 'Microsoft.WindowsTerminal'
        $capturedArgs | Should -Contain '--silent'
        $capturedArgs | Should -Contain '--accept-source-agreements'
        $capturedArgs | Should -Contain '--accept-package-agreements'
    }

    It 'throws on non-zero winget exit' {
        {
            & $script:AnsiModule {
                function Get-Command { param($Name, $CommandType, $ErrorAction)
                    [pscustomobject]@{ Source = 'X:\fake\winget.exe' }
                }
                function Start-Process {
                    param($FilePath, $ArgumentList, [switch]$Wait, [switch]$PassThru, [switch]$NoNewWindow, $ErrorAction)
                    [pscustomobject]@{ ExitCode = 1978 }
                }
                function Write-AnsiLog { param($Message, [switch]$Outcome) }
                Install-AnsiWindowsTerminal
            }
        } | Should -Throw '*winget exited with 1978*'
    }
}
