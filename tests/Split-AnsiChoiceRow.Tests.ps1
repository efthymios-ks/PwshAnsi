#Requires -Version 7.2

# Split-AnsiChoiceRow.Tests.ps1
# The folding a choice list depends on: a long label hangs under its own first character,
# and the caller is told how many physical rows it took.

BeforeAll {
    $script:Core = Import-Module (Join-Path $PSScriptRoot '..' 'src' 'Ansi.Core.psm1') -Force -DisableNameChecking -PassThru

    function New-Run {
        param([string]$Text, [string]$Fg = $null)
        [PSCustomObject]@{ Text = $Text; Fg = $Fg; Bg = $null; Styles = @(); Link = $null }
    }

    function Get-RowText {
        param($Row)
        return (@($Row | ForEach-Object { $_.Text }) -join '')
    }

    function Split-Row {
        param([object[]]$Prefix, [object[]]$Label, [int]$Width)
        return & $script:Core { param($p, $l, $w) Split-AnsiChoiceRow -Prefix $p -Label $l -Width $w } $Prefix $Label $Width
    }
}

Describe 'Split-AnsiChoiceRow' {
    It 'leaves a label that fits on one row' {
        $rows = Split-Row -Prefix @((New-Run '  '), (New-Run '[ ] ')) -Label @((New-Run 'Short label')) -Width 40
        @($rows).Count | Should -Be 1
        Get-RowText $rows[0] | Should -BeExactly '  [ ] Short label'
    }

    It 'folds a long label and hangs it under its own first character' {
        $prefix = @((New-Run '  '), (New-Run '[ ] '))
        $rows = Split-Row -Prefix $prefix -Label @((New-Run ('x' * 40))) -Width 20

        @($rows).Count | Should -BeGreaterThan 1
        # 20 wide, 6 of prefix, one column held back: 13 characters of label per row.
        Get-RowText $rows[0] | Should -BeExactly ('  [ ] ' + ('x' * 13))
        foreach ($row in $rows[1..($rows.Count - 1)]) {
            (Get-RowText $row) | Should -Match '^ {6}\S'
        }
    }

    It 'never reaches the last column of the buffer' {
        $prefix = @((New-Run '  '), (New-Run '[ ] '))
        $rows = Split-Row -Prefix $prefix -Label @((New-Run ('word ' * 30))) -Width 24
        foreach ($row in $rows) {
            (Get-RowText $row).Length | Should -BeLessOrEqual 23
        }
    }

    It 'breaks on a space rather than mid-word when it can' {
        $rows = Split-Row -Prefix @((New-Run '  ')) -Label @((New-Run 'alpha bravo charlie delta')) -Width 16
        Get-RowText $rows[0] | Should -BeExactly '  alpha bravo'
    }

    It 'keeps the label runs styles on every row' {
        $rows = Split-Row -Prefix @((New-Run '> ')) -Label @((New-Run ('y' * 30) 'BrightCyan')) -Width 14
        foreach ($row in $rows) {
            $styled = @($row | Where-Object { $_.Fg -eq 'BrightCyan' })
            $styled.Count | Should -BeGreaterThan 0
        }
    }

    It 'indents continuation rows by the prefix width, not by two' {
        $rows = Split-Row -Prefix @((New-Run '  '), (New-Run '[x] '), (New-Run '')) -Label @((New-Run ('z' * 30))) -Width 18
        @($rows).Count | Should -BeGreaterThan 1
        $rows[1][0].Text | Should -BeExactly ('      ')
    }

    It 'breaks where the label says to, and wraps each of those lines' {
        $label = @((New-Run ("Delete branch some/very/long/branch/name`nNot yours (someone@example.com), can delete")))
        $rows = Split-Row -Prefix @((New-Run '  '), (New-Run '[ ] ')) -Label $label -Width 30

        @($rows).Count | Should -BeGreaterThan 2
        Get-RowText $rows[0] | Should -BeExactly '  [ ] Delete branch'
        foreach ($row in $rows[1..($rows.Count - 1)]) {
            (Get-RowText $row) | Should -Match '^ {6}\S'
            (Get-RowText $row).Length | Should -BeLessOrEqual 29
        }
        (@($rows | ForEach-Object { Get-RowText $_ }) -join '') | Should -Match 'someone@example\.com'
    }

    It 'crops to one row when asked' {
        $rows = & $script:Core { param($p, $l, $w) Split-AnsiChoiceRow -Prefix $p -Label $l -Width $w -Overflow Ellipsis } `
            @((New-Run '  '), (New-Run '[ ] ')) @((New-Run ('x' * 40))) 20
        @($rows).Count | Should -Be 1
        (Get-RowText $rows[0]) | Should -Match ([char]0x2026)
    }

    It 'keeps Crop and Ellipsis to one row even when the label breaks' {
        $label = @((New-Run ("Head`nTail")))
        foreach ($mode in 'Crop', 'Ellipsis') {
            $rows = & $script:Core { param($p, $l, $w, $o) Split-AnsiChoiceRow -Prefix $p -Label $l -Width $w -Overflow $o } `
                @((New-Run '  ')) $label 40 $mode
            @($rows).Count | Should -Be 1
            (Get-RowText $rows[0]) | Should -Not -Match 'Tail'
        }
    }

    It 'handles an empty label without throwing' {
        $rows = Split-Row -Prefix @((New-Run '  ')) -Label @() -Width 20
        @($rows).Count | Should -Be 1
    }
}
