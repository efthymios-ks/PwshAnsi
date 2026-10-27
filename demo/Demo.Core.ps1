# Demo.Core.ps1
# Dot-sourced by every Demo-*.ps1: the section header, and running every numbered
# section or only the ones the demo's -Case names.

function Show-DemoHeader {
    param([string]$Title)
    Write-Host ''
    Write-Host ('─' * 78) -ForegroundColor DarkGray
    Write-Host " $Title" -ForegroundColor Cyan
    Write-Host ('─' * 78) -ForegroundColor DarkGray
}

# One numbered section under its header, skipped when -Case names others. The body
# runs in a scope of its own, so a section needs nothing an earlier one assigned.
function Invoke-DemoCase {
    param(
        [Parameter(Mandatory)][string]$CaseNumber,
        [Parameter(Mandatory)][string]$CaseTitle,
        [Parameter(Mandatory)][scriptblock]$CaseBody
    )
    $script:DemoCaseNumbers += @($CaseNumber)
    if ($Case -and $Case -notcontains $CaseNumber) { return }
    Show-DemoHeader "$CaseNumber. $CaseTitle"
    & $CaseBody
}

# Closes a full run. With -Case, fails on a number the demo has no section for.
function Complete-Demo {
    if (-not $Case) {
        Show-DemoHeader 'Done'
        Write-Host ''
        return
    }
    $unknown = @($Case | Where-Object { $script:DemoCaseNumbers -notcontains $_ })
    if ($unknown.Count -gt 0) {
        throw "No section $($unknown -join ', ') in this demo. Its sections: $($script:DemoCaseNumbers -join ', ')."
    }
}
