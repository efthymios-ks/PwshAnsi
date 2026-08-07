# Format-AnsiTree

Renders a hierarchy with box-drawing guides. Takes nested hashtables or objects,
draws one row per node, collapses branches past a depth limit, and wraps long
labels under the label column instead of the guide.

## Synopsis

```powershell
Format-AnsiTree [-Data] <object> | Out-AnsiHost
              [-Guide <Line|DoubleLine|BoldLine|Ascii>]
              [-Color <string>]              # -GuideColor is an alias
              [-LabelColor <string>]
              [-MaxDepth <int>]
              [-Property <string>]
              [-ChildProperty <string>]
              [-MaxWidth <int>]
              [-Markdown]
              [-Escape]
              [-NoNewline]
```

## Parameters

| Name             | Type                                       | Default         | Description                                                                                          |
| ---------------- | ------------------------------------------ | --------------- | ---------------------------------------------------------------------------------------------------- |
| `-Data`          | `object` (pipeline, pos. 0)                | —               | A node, or a collection of nodes to render as a forest. One tree per pipeline item.                   |
| `-Guide`         | `Line`\|`DoubleLine`\|`BoldLine`\|`Ascii`  | `Line`          | Which characters draw the guides. Every guide is four columns wide.                                   |
| `-Color`         | `string`                                   | none            | Guide colour. `-GuideColor` aliases this parameter.                                                  |
| `-LabelColor`    | `string`                                   | none            | Label colour. Labels that set their own colour via markup win.                                       |
| `-MaxDepth`      | `int`                                      | `0` (unlimited) | Levels below the root to render. Deeper branches collapse to a single `…` row.                        |
| `-Property`      | `string`                                   | *auto*          | Property or key holding the label. Default: `Value`, `Label`, `Name`, or `Text`, whichever exists.    |
| `-ChildProperty` | `string`                                   | *auto*          | Property or key holding the children. Default: `Children`, `Items`, or `Nodes`.                      |
| `-MaxWidth`      | `int`                                      | *auto*          | Override the effective width. Default is `BufferWidth - AnchorColumn`.                                |
| `-Markdown`      | `switch`                                   | off             | Enable [markdown sugar](Markup.md#markdown) in labels.                                                |
| `-Escape`        | `switch`                                   | off             | Treat labels as literal text. Wins over `-Markdown`; `-LabelColor` still applies.                     |
| `-NoNewline`     | `switch`                                   | off             | Do not emit a trailing newline after the last row.                                                    |

Colour names: [Colours](Colours.md). Label syntax: [Markup and markdown](Markup.md).

## Guides

| `-Guide`     | Branch | Continue | Last  |
| ------------ | ------ | -------- | ----- |
| `Line`       | `├──`  | `│`      | `└──` |
| `DoubleLine` | `╠══`  | `║`      | `╚══` |
| `BoldLine`   | `┣━━`  | `┃`      | `┗━━` |
| `Ascii`      | `\|--` | `\|`     | `` `-- `` |

```powershell
Format-AnsiTree $tree | Out-AnsiHost
# root
# ├── branch-a
# │   ├── leaf-a1
# │   └── leaf-a2
# │       └── deep-a2x
# ├── branch-b
# └── branch-c
#     └── leaf-c1
```

## Input shapes

The root renders without a guide; children hang beneath it. Nodes may be
hashtables, ordered dictionaries, or objects.

```powershell
# nested hashtables
Format-AnsiTree @{ | Out-AnsiHost
    Value    = 'root'
    Children = @(
        @{ Value = 'branch'; Children = @(@{ Value = 'leaf' }) }
        @{ Value = 'other' }
    )
}

Format-AnsiTree @{ Name = 'named'; Items = @(@{ Name = 'sub' }) } | Out-AnsiHost        # Name/Items
Format-AnsiTree ([PSCustomObject]@{ Value = 'obj'; Children = @(…) }) | Out-AnsiHost     # objects
Format-AnsiTree @{ label = 'L'; kids = @(…) } -Property label -ChildProperty kids | Out-AnsiHost
```

A bare string or number renders as a single leaf. A collection of nodes renders
as a forest — several roots, one after another — and so does piping several
items in. `$null` renders nothing.

```powershell
Format-AnsiTree 'Just a leaf' | Out-AnsiHost
Format-AnsiTree @(@{ Value = 'Tree-1' }, @{ Value = 'Tree-2' }) | Out-AnsiHost
@{ Value = 'a' }, @{ Value = 'b' } | Format-AnsiTree
```

## Nesting another rendering

A node's label may be an `[Ansi.Rendering]`, so a whole block can hang off a
branch. Its rows keep the node's indentation, and the guide bar continues down
the side while siblings remain:

```powershell
$counts = Format-AnsiGrid @(, @('Passed', '712'), @('Failed', '0')) -MaxWidth 20
Format-AnsiTree @{ Value = 'Test run'; Children = @(@{ Value = $counts }, @{ Value = 'Duration 13s' }) }
# test run
# ├── passed  712
# │   failed    0
# └── duration 13s
```

## Depth limit

`-MaxDepth` counts levels below the root. A branch with hidden children shows one
`…` row so the elision is visible; childless nodes are untouched.

```powershell
Format-AnsiTree $tree -MaxDepth 1 | Out-AnsiHost
# root
# ├── branch-a
# │   └── …
# ├── branch-b
# └── branch-c
#     └── …
```

## Label wrapping

A label wider than the remaining width folds at word boundaries. Continuation
rows keep the ancestors' guides and align under the label, not under the guide.

```powershell
Format-AnsiTree $notes -MaxWidth 40 | Out-AnsiHost
# notes
# ├── a deliberately long label that has
#     to wrap across several rows to fit
# └── short one
```

## Styling

```powershell
Format-AnsiTree $tree -Color DarkGray -LabelColor BrightWhite | Out-AnsiHost
Format-AnsiTree @{ Value = '[bold]Build[/]'; Children = @(@{ Value = ':check: **Done**' }) } -Markdown | Out-AnsiHost
Format-AnsiTree @{ Value = '[bold]Literal[/]' } -Escape | Out-AnsiHost
```

## Anchoring

The first row starts wherever the cursor already is; every later row resumes at
that column, so the whole tree hangs under its prefix.

```powershell
Write-Host 'Tree: ' -NoNewline
Format-AnsiTree $tree | Out-AnsiHost
# tree: root
#       ├── first
#       └── last
```

## Usage patterns

**A real directory tree**

```powershell
function ConvertTo-Tree {
    param([System.IO.DirectoryInfo]$Directory, [int]$Depth = 2)
    $children = @()
    if ($Depth -gt 0) {
        foreach ($d in Get-ChildItem $Directory.FullName -Directory) {
            $children += ConvertTo-Tree -Directory $d -Depth ($Depth - 1)
        }
        foreach ($f in Get-ChildItem $Directory.FullName -File) {
            $children += @{ Value = $f.Name }
        }
    }
    @{ Value = $Directory.Name; Children = $children }
}
Format-AnsiTree (ConvertTo-Tree (Get-Item .)) -Color DarkGray | Out-AnsiHost
```

**Build or task status**

```powershell
Format-AnsiTree @{ | Out-AnsiHost
    Value    = '[bold]deploy[/]'
    Children = @(
        @{ Value = '[BrightGreen]build :check:[/]' }
        @{ Value = '[BrightRed]smoke tests :cross:[/]' }
    )
} -Markdown -Color DarkGray
```

**Dependency graph summary**

```powershell
Format-AnsiTree $dependencies -MaxDepth 2 -Guide Ascii -MaxWidth 100 | Out-AnsiHost
```

**Two panes, side by side**

Components write whole rows, so a column layout means capturing each pane's rows
and zipping them. Pad on *visible* width — with the ANSI stripped — so colours
survive:

```powershell
function Get-Rows {
    param([scriptblock]$Render)
    $rows = @((& $Render 6>&1) | ForEach-Object { [string]$_ })
    return , $rows
}
$visible = { param($t) ($t -replace "`e\[[\d;]*m", '').Length }

$w = 30
$left = Get-Rows { Format-AnsiTree $srcTree -MaxWidth $w -Color DarkGray }
$right = Get-Rows { Format-AnsiTree $docsTree -MaxWidth $w -Color DarkGray }

for ($i = 0; $i -lt [Math]::Max($left.Count, $right.Count); $i++) {
    $l = if ($i -lt $left.Count) { $left[$i] } else { '' }
    $r = if ($i -lt $right.Count) { $right[$i] } else { '' }
    Write-Host ($l + (' ' * [Math]::Max(0, $w - (& $visible $l))) + '  │  ' + $r)
}
# src                             │  docs
#   ├── Ansi.Core.psm1             │    ├── Overview.md
#   └── Format-AnsiTree.psm1        │    └── Markup.md
```

## Demo

```powershell
pwsh -File .\demo\Demo-AnsiTree.ps1
```

Numbered sections per feature: default rendering, all four guides, colours,
markup/markdown labels, `-Escape`, `-MaxDepth`, label wrapping, alternative
input shapes, bare values and forests, pipeline input, anchoring, `-NoNewline`, a
real directory tree, two trees side by side, `NO_COLOR`.

## Tests

`tests/Format-AnsiTree.Tests.ps1` — 68 Pester 5 tests covering guide layout for
every style, sibling/last-child continuation, all input shapes and property
overrides, forests, `-MaxDepth` collapsing, guide and label colours, markup and
markdown labels, label wrapping and its alignment, anchoring, `-NoNewline`, and
the no-colour path.

```powershell
pwsh -File .\Invoke-Test.ps1 -TestName '*AnsiTree*'
```
