#Requires -Version 7.2

<#
.SYNOPSIS
    Records each numbered demo section as a docs image, a PNG or a GIF, and links it
    into its docs page.

.DESCRIPTION
    Each section runs in its own pwsh in a hidden pseudo console (ConPTY), so
    PwshAnsi draws in colour and its prompts take keys. The script types a prompt's
    keys once it shows, then draws the result: the last screen as a PNG, or every
    change as a GIF. Each image is cropped to the rows and columns the section used.

    The demos run from a copy in C:\PwshAnsiDemo, so no path on screen names this
    repository. Images go to docs\media\<demo>\<section>.png or .gif, and each is
    linked into its docs page under the heading the table below names, between
    demo-media markers rewritten on every run.

    Exit codes:
      0  every section recorded
      1  a section failed; the others are still recorded

.PARAMETER Name
    Only these demos: AnsiTable for Demo-AnsiTable.ps1. Default: every demo.

.PARAMETER Case
    Only these sections, by number. Needs exactly one -Name.

.PARAMETER DocsOnly
    Record nothing; only rewrite the image links in the docs from docs\media.

.EXAMPLE
    .\Export-DemoMedia.ps1

.EXAMPLE
    .\Export-DemoMedia.ps1 -Name AnsiTable -Case 2, 3b

.EXAMPLE
    .\Export-DemoMedia.ps1 -DocsOnly
#>

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
    Justification = 'Progress for the person running it.')]
[CmdletBinding()]
param(
    [string[]]$Name,

    [string[]]$Case,

    [switch]$DocsOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Recorded from a copy here, so paths on screen show this folder and not the repository.
$script:StageRoot = 'C:\PwshAnsiDemo'
$script:DemoRoot = Join-Path $PSScriptRoot 'demo'
$script:DocsRoot = Join-Path $PSScriptRoot 'docs'
$script:MediaRoot = Join-Path $script:DocsRoot 'media'
$script:MediaStart = '<!-- demo-media -->'
$script:MediaEnd = '<!-- /demo-media -->'
$script:DefaultHeading = 'Demo'

$script:DefaultColumns = 80
# A static section draws on a screen taller than it, so nothing scrolls away; the crop trims the rest.
$script:StaticRows = 400
# A live section gets a screen of a usual size, since prompts page to the window height.
$script:LiveRows = 40
$script:FontSize = 16
# A GIF frame is taken once the console has drawn nothing for this long, so no frame
# shows half a repaint.
$script:QuietMilliseconds = 80
# How long a GIF's last screen stays before it loops.
$script:HoldMilliseconds = 2500
# How long the console gets to finish drawing after the section exits.
$script:SettleMilliseconds = 400
$script:CaseTimeoutMilliseconds = 120000
# The longest a key waits for its screen text before the section counts as failed.
$script:WaitForMilliseconds = 30000
# The pause before a key when the table gives none: long enough to read the screen.
$script:PressPauseMilliseconds = 900

# What to record, demo by demo. Every numbered section of a demo is one image.
#   Name       The demo, Demo-<Name>.ps1, and its folder under docs\media.
#   Doc        The docs page its images go into.
#   Live       Record a GIF: the screen moves, or waits for keys.
#   ShowTitle  Draw the window title above the screen: the demo animates it.
#   Columns    Screen width, when the content needs more than 80 columns.
#   Skip       Sections left out, each with the reason.
#   Headings   The docs heading each section's image goes under. The rest go under Demo.
#   Presses    The keys a section needs, in order. WaitFor: a screen text to wait for
#              first. Key: a key name, such as Enter, DownArrow, Spacebar or Y. Text:
#              typed a character at a time. PauseMilliseconds: the wait before it.
$script:Recordings = @(
    @{
        Name     = 'AnsiBarChart'
        Doc      = 'Format-AnsiBarChart.md'
        Headings = @{
            '1'  = 'The data'
            '2'  = 'Labels and values'
            '3'  = 'Labels and values'
            '4'  = 'Colour'
            '5'  = 'Labels and values'
            '6'  = 'Labels and values'
            '7'  = 'Width'
            '8'  = 'The bars'
            '9'  = 'The data'
            '10' = 'The data'
            '11' = 'Labels and values'
            '12' = 'Nesting'
            '13' = 'The bars'
        }
    }
    @{
        Name     = 'AnsiBreakdownChart'
        Doc      = 'Format-AnsiBreakdownChart.md'
        Headings = @{
            '1'  = 'The data'
            '2'  = 'The legend'
            '3'  = 'The legend'
            '4'  = 'The legend'
            '5'  = 'Colour'
            '6'  = 'The bar'
            '7'  = 'The bar'
            '8'  = 'The data'
            '9'  = 'The data'
            '10' = 'The legend'
            '11' = 'Nesting'
        }
    }
    @{
        Name     = 'AnsiEmoji'
        Doc      = 'Markup.md'
        Columns  = 100
        Skip     = @{
            '3' = 'the matrix lists every emoji name, too tall for a docs page'
        }
        Headings = @{
            '1'  = 'Emoji'
            '2'  = 'Emoji'
            '4'  = 'Emoji'
            '5'  = 'Emoji'
            '6'  = 'Emoji'
            '7'  = 'Emoji'
            '8'  = 'Emoji'
            '9'  = 'Emoji'
            '10' = 'Emoji'
        }
    }
    @{
        Name     = 'AnsiException'
        Doc      = 'Format-AnsiException.md'
        Columns  = 90
        Headings = @{
            '1'  = 'Detail levels'
            '2'  = 'Detail levels'
            '3'  = 'Frames'
            '4'  = 'Frames'
            '5'  = 'Inner exceptions'
            '6'  = 'Width and anchoring'
            '10' = 'Width and anchoring'
            '11' = 'Width and anchoring'
            '12' = 'Width and anchoring'
            '14' = 'Usage patterns'
            '15' = 'Usage patterns'
            '16' = 'Usage patterns'
        }
    }
    @{
        Name     = 'AnsiGrid'
        Doc      = 'Format-AnsiGrid.md'
        Headings = @{
            '1'  = 'Writing rows — two PowerShell traps'
            '3'  = 'Sizing'
            '4'  = 'Sizing'
            '5'  = 'Sizing'
            '6'  = 'Flowing a flat list'
            '7'  = 'Flowing a flat list'
            '8'  = 'Flowing a flat list'
            '11' = 'Sizing'
            '12' = 'Writing rows — two PowerShell traps'
            '13' = 'Writing rows — two PowerShell traps'
            '15' = 'Anchoring'
            '16' = 'Anchoring'
            '17' = 'Usage patterns'
            '18' = 'Usage patterns'
            '19' = 'Nesting another rendering'
        }
    }
    @{
        Name     = 'AnsiJson'
        Doc      = 'Format-AnsiJson.md'
        Headings = @{
            '1'  = 'Input forms'
            '2'  = 'Input forms'
            '3'  = 'Input forms'
            '4'  = 'Structure and indentation'
            '5'  = 'Depth limits'
            '8'  = 'Width'
            '9'  = 'Input forms'
            '10' = 'Input forms'
            '11' = 'Depth limits'
            '12' = 'Anchoring'
            '13' = 'Anchoring'
            '14' = 'Usage patterns'
            '15' = 'Usage patterns'
        }
    }
    @{
        Name     = 'AnsiPanel'
        Doc      = 'Format-AnsiPanel.md'
        Headings = @{
            '3'  = 'Borders'
            '4'  = 'Borders'
            '6'  = 'Sizing'
            '7'  = 'Sizing'
            '8'  = 'Sizing'
            '9'  = 'Sizing'
            '12' = 'Framing pre-rendered strings with -Rendered'
            '13' = 'Anchoring'
            '14' = 'Anchoring'
            '15' = 'Usage patterns'
            '16' = 'Usage patterns'
            '17' = 'Nesting another rendering'
        }
    }
    @{
        Name     = 'AnsiPath'
        Doc      = 'Format-AnsiPath.md'
        Headings = @{
            '1'  = 'Path shapes'
            '4'  = 'Truncation'
            '5'  = 'Truncation'
            '7'  = 'Path shapes'
            '8'  = 'Input forms'
            '9'  = 'Input forms'
            '10' = 'Anchoring'
            '11' = 'Anchoring'
            '12' = 'Usage patterns'
            '13' = 'Usage patterns'
        }
    }
    @{
        Name     = 'AnsiProgress'
        Doc      = 'Format-AnsiProgress.md'
        Headings = @{
            '1'  = 'The bar'
            '2'  = 'The bar'
            '3'  = 'Width'
            '4'  = 'The suffix'
            '5'  = 'The bar'
            '6'  = 'Colour'
            '7'  = 'Width'
            '8'  = 'The bar'
            '9'  = 'Nesting'
            '10' = 'Nesting'
        }
    }
    @{
        Name     = 'AnsiRule'
        Doc      = 'Format-AnsiRule.md'
        Headings = @{
            '1'  = 'Borders'
            '2'  = 'Title layout'
            '3'  = 'Borders'
            '4'  = 'Borders'
            '5'  = 'Title layout'
            '6'  = 'Styling'
            '7'  = 'Styling'
            '8'  = 'Styling'
            '9'  = 'Styling'
            '10' = 'Title layout'
            '11' = 'Anchoring, width, and spacing'
            '12' = 'Anchoring, width, and spacing'
            '14' = 'Anchoring, width, and spacing'
            '15' = 'Usage patterns'
            '16' = 'Usage patterns'
        }
    }
    @{
        Name     = 'AnsiTable'
        Doc      = 'Format-AnsiTable.md'
        Headings = @{
            '1'  = 'Borders'
            '2'  = 'Borders'
            '3'  = 'Styling'
            '3b' = 'Styling'
            '3c' = 'Styling'
            '3d' = 'Styling'
            '4'  = 'Styling'
            '5'  = 'Alignment'
            '6'  = 'Columns'
            '7'  = 'Columns'
            '8'  = 'Width, overflow, and -Expand'
            '9'  = 'Width, overflow, and -Expand'
            '10' = 'Styling'
            '11' = 'Styling'
            '13' = 'Anchoring'
            '14' = 'Anchoring'
            '15' = 'Usage patterns'
            '16' = 'Usage patterns'
            '17' = 'Nesting another rendering'
        }
    }
    @{
        Name     = 'AnsiText'
        Doc      = 'Format-AnsiText.md'
        Headings = @{
            '1'   = 'Styling'
            '2'   = 'Styling'
            '3'   = 'Styling'
            '4'   = 'Styling'
            '5'   = 'Styling'
            '5b'  = 'Styling'
            '6'   = 'Styling'
            '7'   = 'Anchoring'
            '8'   = 'Overflow and truncation'
            '9'   = 'Overflow and truncation'
            '10'  = 'Overflow and truncation'
            '11'  = 'Overflow and truncation'
            '12'  = 'Overflow and truncation'
            '13'  = 'Anchoring'
            '14'  = 'Anchoring'
            '15'  = 'Input forms'
            '15b' = 'Input forms'
            '15c' = 'Input forms'
            '15d' = 'Overflow and truncation'
            '16'  = 'Usage patterns'
            '17'  = 'Usage patterns'
        }
    }
    @{
        Name     = 'AnsiTree'
        Doc      = 'Format-AnsiTree.md'
        Headings = @{
            '1'  = 'Guides'
            '2'  = 'Guides'
            '3'  = 'Styling'
            '4'  = 'Styling'
            '5'  = 'Styling'
            '6'  = 'Depth limit'
            '7'  = 'Label wrapping'
            '8'  = 'Input shapes'
            '9'  = 'Input shapes'
            '10' = 'Input shapes'
            '11' = 'Anchoring'
            '12' = 'Anchoring'
            '13' = 'Usage patterns'
            '14' = 'Usage patterns'
            '15' = 'Nesting another rendering'
        }
    }
    @{
        Name     = 'AnsiTask'
        Doc      = 'Invoke-AnsiTask.md'
        Live     = $true
        Headings = @{
            '5'  = 'What a step gets'
            '5b' = 'What a step gets'
            '6'  = 'What a step gets'
            '7'  = 'Output and failure'
            '8'  = 'Output and failure'
            '8b' = 'Ending early'
        }
    }
    @{
        Name      = 'AnsiTitleAnimation'
        Doc       = 'Start-AnsiTitleAnimation.md'
        Live      = $true
        ShowTitle = $true
        Headings  = @{
            '0' = 'When the title does not move'
            '1' = 'Start-AnsiTitleAnimation'
            '2' = 'Start-AnsiTitleAnimation'
            '3' = 'One animation, no styles'
            '4' = 'Start-AnsiTitleAnimation'
            '5' = 'Invoke-AnsiTitleAnimation'
            '6' = 'Invoke-AnsiTitleAnimation'
            '7' = 'Stop-AnsiTitleAnimation'
            '8' = 'Usage patterns'
        }
    }
    @{
        Name     = 'ReadAnsiConfirm'
        Doc      = 'Read-AnsiConfirm.md'
        Live     = $true
        Headings = @{
            '1' = 'Keys'
            '2' = 'Keys'
            '3' = 'Keys'
            '5' = 'Usage patterns'
        }
        Presses  = @{
            '1' = @(
                @{ WaitFor = 'Deploy now?'; Key = 'Y' }
            )
            '2' = @(
                @{ WaitFor = 'Delete everything?'; Key = 'N' }
            )
            '3' = @(
                @{ WaitFor = 'Are you sure?'; Key = 'Enter' }
                @{ Key = 'Y' }
            )
            '5' = @(
                @{ WaitFor = 'Drop the database?'; Key = 'N' }
            )
        }
    }
    @{
        Name     = 'ReadAnsiMultiSelection'
        Doc      = 'Read-AnsiMultiSelection.md'
        Live     = $true
        # The hotkey hint is wider than 80 columns.
        Columns  = 100
        Headings = @{
            '1'  = 'Keys'
            '2'  = 'Keys'
            '3'  = 'What it draws'
            '4'  = 'What it draws'
            '5'  = 'Empty results, cancel, and timeout'
            '6'  = 'Returning objects'
            '7'  = 'What it draws'
            '8'  = 'Empty results, cancel, and timeout'
            '9'  = 'Groups'
            '10' = 'Groups'
            '11' = 'Groups'
            '12' = 'Hotkeys'
            '13' = 'Usage patterns'
        }
        Presses  = @{
            '1'  = @(
                @{ WaitFor = 'Which suites?'; Key = 'Spacebar' }
                @{ Key = 'DownArrow'; PauseMilliseconds = 400 }
                @{ Key = 'DownArrow'; PauseMilliseconds = 400 }
                @{ Key = 'Spacebar' }
                @{ Key = 'Enter' }
            )
            '2'  = @(
                @{ WaitFor = 'Which suites?'; Key = 'A' }
                @{ Key = 'Enter' }
            )
            '3'  = @(
                @{ WaitFor = 'Which suites?'; Key = 'Enter' }
            )
            '4'  = @(
                @{ WaitFor = 'Which suites?'; Key = 'DownArrow' }
                @{ Key = 'DownArrow'; PauseMilliseconds = 400 }
                @{ Key = 'DownArrow'; PauseMilliseconds = 400 }
                @{ Key = 'DownArrow'; PauseMilliseconds = 400 }
                @{ Key = 'DownArrow'; PauseMilliseconds = 400 }
                @{ Key = 'Spacebar' }
                @{ Key = 'Enter' }
            )
            '5'  = @(
                @{ WaitFor = 'Which suites?'; Key = 'Enter' }
                @{ WaitFor = 'Pick at least one'; Key = 'Spacebar' }
                @{ Key = 'Enter' }
            )
            '6'  = @(
                @{ WaitFor = 'Which components?'; Key = 'Spacebar' }
                @{ Key = 'DownArrow'; PauseMilliseconds = 400 }
                @{ Key = 'Spacebar' }
                @{ Key = 'Enter' }
            )
            '7'  = @(
                @{ WaitFor = 'Which suites?'; Key = 'Spacebar' }
                @{ Key = 'DownArrow'; PauseMilliseconds = 400 }
                @{ Key = 'Spacebar' }
                @{ Key = 'Enter' }
            )
            '9'  = @(
                @{ WaitFor = 'Which suites?'; Key = 'Spacebar' }
                @{ Key = 'DownArrow'; PauseMilliseconds = 400 }
                @{ Key = 'DownArrow'; PauseMilliseconds = 400 }
                @{ Key = 'Spacebar' }
                @{ Key = 'Enter' }
            )
            '10' = @(
                @{ WaitFor = 'Which suites?'; Key = 'Spacebar' }
                @{ Key = 'Enter' }
            )
            '11' = @(
                @{ WaitFor = 'Which components?'; Key = 'Spacebar' }
                @{ Key = 'Enter' }
            )
            '12' = @(
                @{ WaitFor = 'Which suites?'; Key = 'I' }
                @{ Key = 'Enter' }
            )
            '13' = @(
                @{ WaitFor = 'Run which steps?'; Key = 'Spacebar' }
                @{ Key = 'Enter' }
            )
        }
    }
    @{
        Name     = 'ReadAnsiPause'
        Doc      = 'Read-AnsiPause.md'
        Live     = $true
        Headings = @{
            '1'  = 'Keys'
            '2'  = 'Keys'
            '8'  = 'Keys'
            '9'  = 'Usage patterns'
            '10' = 'Usage patterns'
        }
        Presses  = @{
            '1'  = @(
                @{ WaitFor = 'Press any key to continue'; Key = 'Spacebar' }
            )
            '2'  = @(
                @{ WaitFor = 'Press enter to continue'; Key = 'Spacebar' }
                @{ Key = 'Enter' }
            )
            '3'  = @(
                @{ WaitFor = 'then press a key'; Key = 'Spacebar' }
            )
            '4'  = @(
                @{ WaitFor = 'Stop and read this'; Key = 'Spacebar' }
            )
            '5'  = @(
                @{ WaitFor = 'This line stays after the key'; Key = 'Spacebar' }
            )
            '8'  = @(
                @{ WaitFor = 'Press esc to stop here'; Key = 'Escape' }
            )
            '9'  = @(
                @{ WaitFor = 'Next page'; Key = 'Enter' }
            )
            '10' = @(
                @{ WaitFor = 'Press a key to proceed'; Key = 'Spacebar' }
            )
        }
    }
    @{
        Name     = 'ReadAnsiSelection'
        Doc      = 'Read-AnsiSelection.md'
        Live     = $true
        Headings = @{
            '1'  = 'Keys'
            '2'  = 'Keys'
            '3'  = 'Objects and labels'
            '4'  = 'What it draws'
            '5'  = 'What it draws'
            '6b' = 'Keys'
            '7'  = 'Groups'
            '8'  = 'Groups'
            '9'  = 'Hotkeys'
            '10' = 'Usage patterns'
        }
        Presses  = @{
            '1'  = @(
                @{ WaitFor = 'Pick a fruit'; Key = 'DownArrow' }
                @{ Key = 'DownArrow'; PauseMilliseconds = 500 }
                @{ Key = 'Enter' }
            )
            '2'  = @(
                @{ WaitFor = 'Pick a fruit'; Key = 'PageDown' }
                @{ Key = 'End' }
                @{ Key = 'Enter' }
            )
            '3'  = @(
                @{ WaitFor = 'Pick a component'; Key = 'DownArrow' }
                @{ Key = 'Enter' }
            )
            '4'  = @(
                @{ WaitFor = 'Environment'; Key = 'DownArrow' }
                @{ Key = 'Enter' }
            )
            '5'  = @(
                @{ WaitFor = 'Pick a fruit'; Key = 'DownArrow' }
                @{ Key = 'Enter' }
            )
            '6b' = @(
                @{ WaitFor = 'Pick a fruit'; Key = 'Enter'; PauseMilliseconds = 1500 }
            )
            '7'  = @(
                @{ WaitFor = 'Pick a fruit'; Key = 'DownArrow' }
                @{ Key = 'DownArrow'; PauseMilliseconds = 500 }
                @{ Key = 'DownArrow'; PauseMilliseconds = 500 }
                @{ Key = 'Enter' }
            )
            '8'  = @(
                @{ WaitFor = 'Which file?'; Key = 'DownArrow' }
                @{ Key = 'DownArrow'; PauseMilliseconds = 500 }
                @{ Key = 'DownArrow'; PauseMilliseconds = 500 }
                @{ Key = 'Enter' }
            )
            '9'  = @(
                @{ WaitFor = 'Pick a fruit'; Key = 'DownArrow' }
                @{ Key = 'DownArrow'; PauseMilliseconds = 500 }
                @{ Key = 'R' }
                @{ Key = 'F'; PauseMilliseconds = 1500 }
                @{ Key = 'Enter' }
            )
            '10' = @(
                @{ WaitFor = 'Deploy to'; Key = 'DownArrow' }
                @{ Key = 'Enter' }
            )
        }
    }
    @{
        Name     = 'ReadAnsiText'
        Doc      = 'Read-AnsiText.md'
        Live     = $true
        Headings = @{
            '1' = 'Keys'
            '2' = 'Empty answers, defaults, validation'
            '4' = 'Keys'
            '5' = 'Empty answers, defaults, validation'
            '6' = 'Empty answers, defaults, validation'
        }
        Presses  = @{
            '1' = @(
                @{ WaitFor = 'Your name'; Text = 'Ada' }
                @{ Key = 'Enter' }
            )
            '2' = @(
                @{ WaitFor = 'Branch'; Key = 'Enter' }
            )
            '3' = @(
                @{ WaitFor = 'Environment'; Key = 'Enter' }
            )
            '4' = @(
                @{ WaitFor = 'API key'; Text = 'sk-demo-1234' }
                @{ Key = 'Enter' }
            )
            '5' = @(
                @{ WaitFor = 'Port'; Text = 'abc' }
                @{ Key = 'Enter' }
                @{ WaitFor = 'Digits only'; Key = 'Backspace' }
                @{ Key = 'Backspace'; PauseMilliseconds = 200 }
                @{ Key = 'Backspace'; PauseMilliseconds = 200 }
                @{ Text = '8080' }
                @{ Key = 'Enter' }
            )
            '6' = @(
                @{ WaitFor = 'Note (optional)'; Key = 'Enter' }
            )
        }
    }
)

# ── Console, screen and images ───────────────────────────────────────────────

# DemoRecorder runs a section in a hidden pseudo console and keeps what it draws.
# DemoScreen is the terminal behind it: it reads the VT stream into rows of cells.
# DemoRenderer draws those cells as a PNG, or a run of them as a GIF.
$script:DemoSource = @'
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Drawing.Text;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.Win32.SafeHandles;

namespace PwshAnsi.Demo
{
    // One step of a recorded answer: wait for a screen text, pause, then press a key or type text.
    public sealed class DemoPress
    {
        public string WaitFor { get; set; }
        public string Key { get; set; }
        public string Text { get; set; }
        public int PauseMilliseconds { get; set; }
    }

    // One cell. Colours are ARGB, or 0 for the terminal's default. Width 0 is the
    // right half of a wide glyph.
    public struct DemoCell
    {
        public string Text;
        public int Foreground;
        public int Background;
        public byte Style;
        public byte Width;
    }

    public sealed class DemoSnapshot
    {
        public DemoCell[] Cells;
        public int Columns;
        public int Rows;
        public string Title;
        public long Milliseconds;
    }

    public sealed class DemoRun
    {
        public List<DemoSnapshot> Frames = new List<DemoSnapshot>();
        public DemoSnapshot Final;
        public int ExitCode;
        public string Problem = "";
    }

    public sealed class DemoScreen
    {
        public const int DefaultColor = 0;
        public const byte Bold = 1;
        public const byte Dim = 2;
        public const byte Italic = 4;
        public const byte Underline = 8;
        public const byte Strike = 16;
        public const byte Reverse = 32;

        // Windows Terminal's default scheme, Campbell.
        public static readonly int[] Palette =
        {
            0x0C0C0C, 0xC50F1F, 0x13A10E, 0xC19C00, 0x0037DA, 0x881798, 0x3A96DD, 0xCCCCCC,
            0x767676, 0xE74856, 0x16C60C, 0xF9F1A5, 0x3B78FF, 0xB4009E, 0x61D6D6, 0xF2F2F2,
        };

        // Code points two cells wide, as ranges: East Asian wide and emoji shown as emoji.
        private static readonly int[] WideRanges =
        {
            0x1100, 0x115F, 0x231A, 0x231B, 0x2329, 0x232A, 0x23E9, 0x23EC, 0x23F0, 0x23F0, 0x23F3, 0x23F3,
            0x25FD, 0x25FE, 0x2614, 0x2615, 0x2648, 0x2653, 0x267F, 0x267F, 0x2693, 0x2693, 0x26A1, 0x26A1,
            0x26AA, 0x26AB, 0x26BD, 0x26BE, 0x26C4, 0x26C5, 0x26CE, 0x26CE, 0x26D4, 0x26D4, 0x26EA, 0x26EA,
            0x26F2, 0x26F3, 0x26F5, 0x26F5, 0x26FA, 0x26FA, 0x26FD, 0x26FD, 0x2705, 0x2705, 0x270A, 0x270B,
            0x2728, 0x2728, 0x274C, 0x274C, 0x274E, 0x274E, 0x2753, 0x2755, 0x2757, 0x2757, 0x2795, 0x2797,
            0x27B0, 0x27B0, 0x27BF, 0x27BF, 0x2B1B, 0x2B1C, 0x2B50, 0x2B50, 0x2B55, 0x2B55, 0x2E80, 0x303E,
            0x3041, 0x33FF, 0x3400, 0x4DBF, 0x4E00, 0x9FFF, 0xA000, 0xA4CF, 0xAC00, 0xD7A3, 0xF900, 0xFAFF,
            0xFE10, 0xFE19, 0xFE30, 0xFE6F, 0xFF00, 0xFF60, 0xFFE0, 0xFFE6, 0x1F004, 0x1F004, 0x1F0CF, 0x1F0CF,
            0x1F18E, 0x1F18E, 0x1F191, 0x1F19A, 0x1F200, 0x1F251, 0x1F300, 0x1F64F, 0x1F680, 0x1F6FF,
            0x1F7E0, 0x1F7EB, 0x1F90C, 0x1F9FF, 0x1FA70, 0x1FAFF, 0x20000, 0x3FFFD,
        };

        private enum ParseState
        {
            Ground,
            Escape,
            EscapeIntermediate,
            Csi,
            Osc,
            OscEscape,
            Ignore,
            IgnoreEscape,
        }

        private readonly int columns;
        private readonly int rows;
        private readonly Decoder decoder = new UTF8Encoding(false).GetDecoder();
        private readonly StringBuilder sequence = new StringBuilder();
        private readonly List<string> replies = new List<string>();
        private DemoCell[] cells;
        private DemoCell[] mainCells;
        private ParseState state;
        private char pendingHigh;
        private int row;
        private int column;
        private int savedRow;
        private int savedColumn;
        private bool wrapPending;
        private int foreground;
        private int background;
        private byte style;
        private int top;
        private int bottom;
        private int lastIndex = -1;
        private string title = "";

        public DemoScreen(int columns, int rows)
        {
            this.columns = columns;
            this.rows = rows;
            cells = NewCells();
            bottom = rows - 1;
        }

        public long Version { get; private set; }

        public void Feed(byte[] buffer, int count)
        {
            char[] chars = new char[count + 1];
            int decoded = decoder.GetChars(buffer, 0, count, chars, 0);
            for (int index = 0; index < decoded; index++)
            {
                Process(chars[index]);
            }
            Version++;
        }

        // What the terminal answers back, such as a cursor position report.
        public string[] TakeReplies()
        {
            string[] taken = replies.ToArray();
            replies.Clear();
            return taken;
        }

        public string Text()
        {
            StringBuilder text = new StringBuilder(rows * (columns + 1));
            for (int index = 0; index < cells.Length; index++)
            {
                text.Append(string.IsNullOrEmpty(cells[index].Text) ? " " : cells[index].Text);
                if ((index + 1) % columns == 0)
                {
                    text.Append('\n');
                }
            }
            return text.ToString();
        }

        public DemoSnapshot Snapshot()
        {
            return new DemoSnapshot
            {
                Cells = (DemoCell[])cells.Clone(),
                Columns = columns,
                Rows = rows,
                Title = title,
            };
        }

        public static int CellWidth(int codePoint)
        {
            bool joins = codePoint == 0x200B || codePoint == 0x200C || codePoint == 0x200D ||
                (codePoint >= 0x0300 && codePoint <= 0x036F) || (codePoint >= 0x20D0 && codePoint <= 0x20FF) ||
                (codePoint >= 0xFE00 && codePoint <= 0xFE0F) || (codePoint >= 0x1F3FB && codePoint <= 0x1F3FF) ||
                (codePoint >= 0xE0020 && codePoint <= 0xE007F);
            if (joins)
            {
                return 0;
            }
            for (int index = 0; index < WideRanges.Length; index += 2)
            {
                if (codePoint < WideRanges[index])
                {
                    return 1;
                }
                if (codePoint <= WideRanges[index + 1])
                {
                    return 2;
                }
            }
            return 1;
        }

        private DemoCell[] NewCells()
        {
            DemoCell[] fresh = new DemoCell[columns * rows];
            for (int index = 0; index < fresh.Length; index++)
            {
                fresh[index].Width = 1;
            }
            return fresh;
        }

        private DemoCell Blank()
        {
            return new DemoCell { Background = background, Width = 1 };
        }

        private void Process(char character)
        {
            switch (state)
            {
                case ParseState.Ground:
                    if (character == '\u001b')
                    {
                        state = ParseState.Escape;
                    }
                    else if (character < ' ' || character == '\u007f')
                    {
                        Control(character);
                    }
                    else
                    {
                        Printable(character);
                    }
                    break;
                case ParseState.Escape:
                    Escape(character);
                    break;
                case ParseState.EscapeIntermediate:
                    state = ParseState.Ground;
                    break;
                case ParseState.Csi:
                    if (character >= '@' && character <= '~')
                    {
                        state = ParseState.Ground;
                        Csi(character, sequence.ToString());
                    }
                    else if (character == '\u001b')
                    {
                        state = ParseState.Escape;
                    }
                    else if (character >= ' ')
                    {
                        sequence.Append(character);
                    }
                    break;
                case ParseState.Osc:
                    if (character == '\u0007')
                    {
                        Osc();
                    }
                    else if (character == '\u001b')
                    {
                        state = ParseState.OscEscape;
                    }
                    else
                    {
                        sequence.Append(character);
                    }
                    break;
                case ParseState.OscEscape:
                    Osc();
                    if (character != '\\')
                    {
                        state = ParseState.Escape;
                        Escape(character);
                    }
                    break;
                case ParseState.Ignore:
                    if (character == '\u001b')
                    {
                        state = ParseState.IgnoreEscape;
                    }
                    else if (character == '\u0007')
                    {
                        state = ParseState.Ground;
                    }
                    break;
                case ParseState.IgnoreEscape:
                    state = character == '\\' ? ParseState.Ground : ParseState.Ignore;
                    break;
            }
        }

        private void Escape(char character)
        {
            state = ParseState.Ground;
            switch (character)
            {
                case '[':
                    sequence.Clear();
                    state = ParseState.Csi;
                    break;
                case ']':
                    sequence.Clear();
                    state = ParseState.Osc;
                    break;
                case 'P':
                case 'X':
                case '^':
                case '_':
                    state = ParseState.Ignore;
                    break;
                case '(':
                case ')':
                case '*':
                case '+':
                case '-':
                case '.':
                case '/':
                case '#':
                case '%':
                    state = ParseState.EscapeIntermediate;
                    break;
                case '7':
                    savedRow = row;
                    savedColumn = column;
                    break;
                case '8':
                    row = savedRow;
                    column = savedColumn;
                    wrapPending = false;
                    break;
                case 'D':
                    LineFeed();
                    break;
                case 'E':
                    column = 0;
                    LineFeed();
                    break;
                case 'M':
                    ReverseIndex();
                    break;
                case 'c':
                    cells = NewCells();
                    row = 0;
                    column = 0;
                    foreground = DefaultColor;
                    background = DefaultColor;
                    style = 0;
                    top = 0;
                    bottom = rows - 1;
                    break;
            }
        }

        private void Osc()
        {
            state = ParseState.Ground;
            string text = sequence.ToString();
            int split = text.IndexOf(';');
            if (split < 0)
            {
                return;
            }
            string code = text.Substring(0, split);
            if (code == "0" || code == "2")
            {
                title = text.Substring(split + 1);
            }
        }

        private void Control(char character)
        {
            switch (character)
            {
                case '\r':
                    column = 0;
                    wrapPending = false;
                    break;
                case '\n':
                case '\u000b':
                case '\u000c':
                    LineFeed();
                    break;
                case '\b':
                    if (column > 0)
                    {
                        column--;
                    }
                    wrapPending = false;
                    break;
                case '\t':
                    column = Math.Min(columns - 1, ((column / 8) + 1) * 8);
                    break;
            }
        }

        private void Printable(char character)
        {
            string text;
            int codePoint;
            if (char.IsHighSurrogate(character))
            {
                pendingHigh = character;
                return;
            }
            if (char.IsLowSurrogate(character) && pendingHigh != '\0')
            {
                text = new string(new[] { pendingHigh, character });
                codePoint = char.ConvertToUtf32(pendingHigh, character);
                pendingHigh = '\0';
            }
            else
            {
                text = character.ToString();
                codePoint = character;
            }

            int width = CellWidth(codePoint);
            if (width == 0)
            {
                if (lastIndex >= 0)
                {
                    cells[lastIndex].Text += text;
                    WidenForEmojiPresentation(codePoint);
                }
                return;
            }
            if (wrapPending)
            {
                column = 0;
                LineFeed();
            }
            if (width == 2 && column == columns - 1)
            {
                cells[(row * columns) + column] = Blank();
                column = 0;
                LineFeed();
            }

            int index = (row * columns) + column;
            // Writing over half of a wide glyph clears its other half.
            if (cells[index].Width == 0 && column > 0)
            {
                cells[index - 1] = Blank();
            }
            if (cells[index].Width == 2 && width == 1 && column + 1 < columns)
            {
                cells[index + 1] = Blank();
            }
            cells[index] = new DemoCell
            {
                Text = text,
                Foreground = foreground,
                Background = background,
                Style = style,
                Width = (byte)width,
            };
            if (width == 2 && column + 1 < columns)
            {
                cells[index + 1] = new DemoCell
                {
                    Text = "",
                    Foreground = foreground,
                    Background = background,
                    Style = style,
                    Width = 0,
                };
            }
            lastIndex = index;
            column += width;
            if (column >= columns)
            {
                column = columns - 1;
                wrapPending = true;
            }
        }

        // U+FE0F asks for the emoji form: two cells in Windows Terminal, and to PwshAnsi,
        // which counts UTF-16 characters. The console behind a pseudo console can keep
        // one cell, which would shift the rest of the row left.
        private void WidenForEmojiPresentation(int codePoint)
        {
            const int EmojiPresentation = 0xFE0F;
            bool justBehind = lastIndex == (row * columns) + column - 1 && !wrapPending;
            if (codePoint != EmojiPresentation || cells[lastIndex].Width != 1 || !justBehind || column >= columns)
            {
                return;
            }
            cells[lastIndex].Width = 2;
            cells[lastIndex + 1] = new DemoCell
            {
                Text = "",
                Foreground = foreground,
                Background = background,
                Style = style,
                Width = 0,
            };
            column++;
            if (column >= columns)
            {
                column = columns - 1;
                wrapPending = true;
            }
        }

        private void LineFeed()
        {
            wrapPending = false;
            if (row == bottom)
            {
                ScrollUp(1);
            }
            else if (row < rows - 1)
            {
                row++;
            }
        }

        private void ReverseIndex()
        {
            wrapPending = false;
            if (row == top)
            {
                ScrollDown(1);
            }
            else if (row > 0)
            {
                row--;
            }
        }

        private void ScrollUp(int count)
        {
            for (int line = top; line <= bottom; line++)
            {
                int source = line + count;
                for (int x = 0; x < columns; x++)
                {
                    cells[(line * columns) + x] = source <= bottom ? cells[(source * columns) + x] : Blank();
                }
            }
            lastIndex = -1;
        }

        private void ScrollDown(int count)
        {
            for (int line = bottom; line >= top; line--)
            {
                int source = line - count;
                for (int x = 0; x < columns; x++)
                {
                    cells[(line * columns) + x] = source >= top ? cells[(source * columns) + x] : Blank();
                }
            }
            lastIndex = -1;
        }

        private void Erase(int from, int to)
        {
            for (int index = Math.Max(0, from); index < Math.Min(cells.Length, to); index++)
            {
                cells[index] = Blank();
            }
        }

        private void Csi(char final, string text)
        {
            char marker = '\0';
            if (text.Length > 0 && "?>=<".IndexOf(text[0]) >= 0)
            {
                marker = text[0];
                text = text.Substring(1);
            }
            // Sequences with intermediates, such as the cursor shape, change nothing drawn.
            if (text.Any(character => character >= ' ' && character <= '/'))
            {
                return;
            }
            int[] values = text.Length == 0
                ? new int[0]
                : text.Replace(':', ';').Split(';').Select(part => part.Length == 0 ? 0 : int.Parse(part)).ToArray();
            Func<int, int, int> argument = (position, fallback) =>
                position < values.Length && values[position] > 0 ? values[position] : fallback;
            int count = argument(0, 1);
            int start = row * columns;

            if (final != 'm')
            {
                wrapPending = false;
            }
            switch (final)
            {
                case 'A':
                    row = Math.Max(0, row - count);
                    break;
                case 'B':
                case 'e':
                    row = Math.Min(rows - 1, row + count);
                    break;
                case 'C':
                case 'a':
                    column = Math.Min(columns - 1, column + count);
                    break;
                case 'D':
                    column = Math.Max(0, column - count);
                    break;
                case 'E':
                    row = Math.Min(rows - 1, row + count);
                    column = 0;
                    break;
                case 'F':
                    row = Math.Max(0, row - count);
                    column = 0;
                    break;
                case 'G':
                case '`':
                    column = Math.Min(columns - 1, count - 1);
                    break;
                case 'd':
                    row = Math.Min(rows - 1, count - 1);
                    break;
                case 'H':
                case 'f':
                    row = Math.Min(rows - 1, argument(0, 1) - 1);
                    column = Math.Min(columns - 1, argument(1, 1) - 1);
                    break;
                case 'J':
                    int screenMode = values.Length > 0 ? values[0] : 0;
                    if (screenMode == 0)
                    {
                        Erase(start + column, cells.Length);
                    }
                    else if (screenMode == 1)
                    {
                        Erase(0, start + column + 1);
                    }
                    else
                    {
                        Erase(0, cells.Length);
                    }
                    break;
                case 'K':
                    int lineMode = values.Length > 0 ? values[0] : 0;
                    if (lineMode == 0)
                    {
                        Erase(start + column, start + columns);
                    }
                    else if (lineMode == 1)
                    {
                        Erase(start, start + column + 1);
                    }
                    else
                    {
                        Erase(start, start + columns);
                    }
                    break;
                case 'X':
                    Erase(start + column, start + Math.Min(columns, column + count));
                    break;
                case '@':
                    for (int x = columns - 1; x >= column; x--)
                    {
                        cells[start + x] = x - count >= column ? cells[start + x - count] : Blank();
                    }
                    break;
                case 'P':
                    for (int x = column; x < columns; x++)
                    {
                        cells[start + x] = x + count < columns ? cells[start + x + count] : Blank();
                    }
                    break;
                case 'L':
                case 'M':
                    if (row >= top && row <= bottom)
                    {
                        int savedTop = top;
                        top = row;
                        for (int step = 0; step < count; step++)
                        {
                            if (final == 'L')
                            {
                                ScrollDown(1);
                            }
                            else
                            {
                                ScrollUp(1);
                            }
                        }
                        top = savedTop;
                    }
                    break;
                case 'S':
                    for (int step = 0; step < count; step++)
                    {
                        ScrollUp(1);
                    }
                    break;
                case 'T':
                    for (int step = 0; step < count; step++)
                    {
                        ScrollDown(1);
                    }
                    break;
                case 'r':
                    top = argument(0, 1) - 1;
                    bottom = Math.Min(rows - 1, argument(1, rows) - 1);
                    if (top >= bottom)
                    {
                        top = 0;
                        bottom = rows - 1;
                    }
                    row = 0;
                    column = 0;
                    break;
                case 's':
                    savedRow = row;
                    savedColumn = column;
                    break;
                case 'u':
                    row = savedRow;
                    column = savedColumn;
                    break;
                case 'h':
                case 'l':
                    if (marker == '?' && values.Any(mode => mode == 1049 || mode == 1047 || mode == 47))
                    {
                        AlternateScreen(final == 'h');
                    }
                    break;
                case 'n':
                    if (argument(0, 0) == 6)
                    {
                        replies.Add(string.Format("\u001b[{0};{1}R", row + 1, column + 1));
                    }
                    else if (argument(0, 0) == 5)
                    {
                        replies.Add("\u001b[0n");
                    }
                    break;
                case 'c':
                    replies.Add(marker == '>' ? "\u001b[>0;10;1c" : "\u001b[?1;0c");
                    break;
                case 'm':
                    Sgr(values);
                    break;
            }
        }

        private void AlternateScreen(bool enable)
        {
            if (enable && mainCells == null)
            {
                mainCells = cells;
                cells = NewCells();
            }
            else if (!enable && mainCells != null)
            {
                cells = mainCells;
                mainCells = null;
            }
            lastIndex = -1;
        }

        private void Sgr(int[] values)
        {
            if (values.Length == 0)
            {
                values = new[] { 0 };
            }
            for (int index = 0; index < values.Length; index++)
            {
                int value = values[index];
                if (value == 38 || value == 48)
                {
                    int color = ExtendedColor(values, ref index);
                    if (value == 38)
                    {
                        foreground = color;
                    }
                    else
                    {
                        background = color;
                    }
                    continue;
                }
                if (value >= 30 && value <= 37)
                {
                    foreground = Opaque(Palette[value - 30]);
                }
                else if (value >= 40 && value <= 47)
                {
                    background = Opaque(Palette[value - 40]);
                }
                else if (value >= 90 && value <= 97)
                {
                    foreground = Opaque(Palette[value - 90 + 8]);
                }
                else if (value >= 100 && value <= 107)
                {
                    background = Opaque(Palette[value - 100 + 8]);
                }
                else
                {
                    switch (value)
                    {
                        case 0:
                            foreground = DefaultColor;
                            background = DefaultColor;
                            style = 0;
                            break;
                        case 1:
                            style |= Bold;
                            break;
                        case 2:
                            style |= Dim;
                            break;
                        case 3:
                            style |= Italic;
                            break;
                        case 4:
                        case 21:
                            style |= Underline;
                            break;
                        case 7:
                            style |= Reverse;
                            break;
                        case 9:
                            style |= Strike;
                            break;
                        case 22:
                            style &= unchecked((byte)~(Bold | Dim));
                            break;
                        case 23:
                            style &= unchecked((byte)~Italic);
                            break;
                        case 24:
                            style &= unchecked((byte)~Underline);
                            break;
                        case 27:
                            style &= unchecked((byte)~Reverse);
                            break;
                        case 29:
                            style &= unchecked((byte)~Strike);
                            break;
                        case 39:
                            foreground = DefaultColor;
                            break;
                        case 49:
                            background = DefaultColor;
                            break;
                    }
                }
            }
        }

        private static int ExtendedColor(int[] values, ref int index)
        {
            if (index + 2 < values.Length && values[index + 1] == 5)
            {
                int color = Color256(values[index + 2]);
                index += 2;
                return color;
            }
            if (index + 4 < values.Length && values[index + 1] == 2)
            {
                int color = Opaque((values[index + 2] << 16) | (values[index + 3] << 8) | values[index + 4]);
                index += 4;
                return color;
            }
            index = values.Length;
            return DefaultColor;
        }

        private static int Color256(int index)
        {
            if (index < 16)
            {
                return Opaque(Palette[index]);
            }
            if (index < 232)
            {
                int[] levels = { 0, 95, 135, 175, 215, 255 };
                int cube = index - 16;
                return Opaque((levels[cube / 36] << 16) | (levels[(cube / 6) % 6] << 8) | levels[cube % 6]);
            }
            int gray = 8 + ((index - 232) * 10);
            return Opaque((gray << 16) | (gray << 8) | gray);
        }

        private static int Opaque(int rgb)
        {
            return unchecked((int)0xFF000000) | rgb;
        }
    }

    public static class DemoRecorder
    {
        private const uint ExtendedStartupInfoPresent = 0x00080000;
        private const int UseStandardHandles = 0x00000100;
        private const int PseudoConsoleAttribute = 0x00020016;
        private const uint WaitObject0 = 0;
        private const int TypeIntervalMilliseconds = 90;
        private const int PollMilliseconds = 15;
        // A console that never goes quiet, such as a fast spinner, still gets a frame this often.
        private const int StaleMilliseconds = 500;
        private static readonly IntPtr InvalidHandle = new IntPtr(-1);

        // The VT sequences a terminal sends for each key.
        private static readonly Dictionary<string, string> KeySequences = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
        {
            { "Enter", "\r" },
            { "Escape", "\u001b" },
            { "Spacebar", " " },
            { "Backspace", "\u007f" },
            { "Tab", "\t" },
            { "UpArrow", "\u001b[A" },
            { "DownArrow", "\u001b[B" },
            { "RightArrow", "\u001b[C" },
            { "LeftArrow", "\u001b[D" },
            { "Home", "\u001b[H" },
            { "End", "\u001b[F" },
            { "PageUp", "\u001b[5~" },
            { "PageDown", "\u001b[6~" },
            { "Insert", "\u001b[2~" },
            { "Delete", "\u001b[3~" },
            { "F1", "\u001bOP" },
            { "F2", "\u001bOQ" },
            { "F3", "\u001bOR" },
            { "F4", "\u001bOS" },
            { "F5", "\u001b[15~" },
            { "F6", "\u001b[17~" },
            { "F7", "\u001b[18~" },
            { "F8", "\u001b[19~" },
            { "F9", "\u001b[20~" },
            { "F10", "\u001b[21~" },
            { "F11", "\u001b[23~" },
            { "F12", "\u001b[24~" },
        };

        [StructLayout(LayoutKind.Sequential)]
        private struct Coord
        {
            public short X;
            public short Y;
        }

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct StartupInfo
        {
            public int Size;
            public IntPtr Reserved;
            public IntPtr Desktop;
            public IntPtr Title;
            public int X;
            public int Y;
            public int XSize;
            public int YSize;
            public int XCountChars;
            public int YCountChars;
            public int FillAttribute;
            public int Flags;
            public short ShowWindow;
            public short Reserved2Size;
            public IntPtr Reserved2;
            public IntPtr StandardInput;
            public IntPtr StandardOutput;
            public IntPtr StandardError;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct StartupInfoEx
        {
            public StartupInfo StartupInfo;
            public IntPtr AttributeList;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct ProcessInformation
        {
            public IntPtr Process;
            public IntPtr Thread;
            public int ProcessId;
            public int ThreadId;
        }

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern int CreatePseudoConsole(
            Coord size,
            SafeFileHandle input,
            SafeFileHandle output,
            uint flags,
            out IntPtr pseudoConsole);

        [DllImport("kernel32.dll")]
        private static extern void ClosePseudoConsole(IntPtr pseudoConsole);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool CreatePipe(
            out SafeFileHandle read,
            out SafeFileHandle write,
            IntPtr attributes,
            int size);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool InitializeProcThreadAttributeList(
            IntPtr list,
            int count,
            int flags,
            ref IntPtr size);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool UpdateProcThreadAttribute(
            IntPtr list,
            uint flags,
            IntPtr attribute,
            IntPtr value,
            IntPtr size,
            IntPtr previous,
            IntPtr returnSize);

        [DllImport("kernel32.dll")]
        private static extern void DeleteProcThreadAttributeList(IntPtr list);

        [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        private static extern bool CreateProcessW(
            string application,
            StringBuilder commandLine,
            IntPtr processAttributes,
            IntPtr threadAttributes,
            bool inheritHandles,
            uint flags,
            IntPtr environment,
            string directory,
            ref StartupInfoEx startupInfo,
            out ProcessInformation information);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern uint WaitForSingleObject(IntPtr handle, uint milliseconds);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool GetExitCodeProcess(IntPtr process, out int exitCode);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool TerminateProcess(IntPtr process, int exitCode);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool CloseHandle(IntPtr handle);

        // Runs the command line in a pseudo console of the given size, answers it with
        // the presses, and returns its last screen, plus a frame per change when asked.
        public static DemoRun Run(
            string application,
            string commandLine,
            string directory,
            int columns,
            int rows,
            DemoPress[] presses,
            bool keepFrames,
            int quietMilliseconds,
            int timeoutMilliseconds,
            int waitForMilliseconds,
            int settleMilliseconds)
        {
            DemoScreen screen = new DemoScreen(columns, rows);
            object screenGate = new object();
            object inputGate = new object();
            DemoRun run = new DemoRun();

            SafeFileHandle inputRead;
            SafeFileHandle inputWrite;
            SafeFileHandle outputRead;
            SafeFileHandle outputWrite;
            if (!CreatePipe(out inputRead, out inputWrite, IntPtr.Zero, 0) ||
                !CreatePipe(out outputRead, out outputWrite, IntPtr.Zero, 0))
            {
                throw new Win32Exception();
            }
            IntPtr console;
            int result = CreatePseudoConsole(new Coord { X = (short)columns, Y = (short)rows }, inputRead, outputWrite, 0, out console);
            if (result != 0)
            {
                throw new Win32Exception(result);
            }
            // The pseudo console keeps its own copies of these ends.
            inputRead.Dispose();
            outputWrite.Dispose();

            ProcessInformation process = Start(application, commandLine, directory, console);
            FileStream output = new FileStream(outputRead, FileAccess.Read, 4096, false);
            FileStream input = new FileStream(inputWrite, FileAccess.Write, 4096, false);
            Action<string> send = text =>
            {
                byte[] bytes = Encoding.UTF8.GetBytes(text);
                lock (inputGate)
                {
                    input.Write(bytes, 0, bytes.Length);
                    input.Flush();
                }
            };

            Stopwatch clock = Stopwatch.StartNew();
            long lastFeed = 0;
            Thread reader = new Thread(() =>
            {
                byte[] buffer = new byte[16384];
                try
                {
                    int read;
                    while ((read = output.Read(buffer, 0, buffer.Length)) > 0)
                    {
                        string[] replies;
                        lock (screenGate)
                        {
                            screen.Feed(buffer, read);
                            lastFeed = clock.ElapsedMilliseconds;
                            replies = screen.TakeReplies();
                        }
                        foreach (string reply in replies)
                        {
                            send(reply);
                        }
                    }
                }
                catch (IOException)
                {
                }
                catch (ObjectDisposedException)
                {
                }
            });
            reader.IsBackground = true;
            reader.Start();

            CancellationTokenSource stop = new CancellationTokenSource();
            Func<string, bool> shows = text =>
            {
                lock (screenGate)
                {
                    return screen.Text().IndexOf(text, StringComparison.Ordinal) >= 0;
                }
            };
            Task play = Task.Run(() => Play(presses, shows, send, waitForMilliseconds, stop.Token));

            long lastVersion = -1;
            long lastFrame = 0;
            while (true)
            {
                bool exited = WaitForSingleObject(process.Process, PollMilliseconds) == WaitObject0;
                if (keepFrames)
                {
                    lock (screenGate)
                    {
                        long now = clock.ElapsedMilliseconds;
                        bool settled = now - lastFeed >= quietMilliseconds || now - lastFrame >= StaleMilliseconds;
                        if (screen.Version != lastVersion && settled)
                        {
                            DemoSnapshot frame = screen.Snapshot();
                            frame.Milliseconds = now;
                            run.Frames.Add(frame);
                            lastVersion = screen.Version;
                            lastFrame = now;
                        }
                    }
                }
                if (exited)
                {
                    break;
                }
                if (clock.ElapsedMilliseconds > timeoutMilliseconds)
                {
                    TerminateProcess(process.Process, 1);
                    run.Problem = string.Format("did not end within {0} seconds.", timeoutMilliseconds / 1000);
                    break;
                }
            }

            Thread.Sleep(settleMilliseconds);
            lock (screenGate)
            {
                run.Final = screen.Snapshot();
                run.Final.Milliseconds = clock.ElapsedMilliseconds;
                if (keepFrames && screen.Version != lastVersion)
                {
                    run.Frames.Add(run.Final);
                }
            }
            int exitCode;
            GetExitCodeProcess(process.Process, out exitCode);
            run.ExitCode = exitCode;

            // The last key can still be returning when the section it answered ends.
            try
            {
                play.Wait(1000);
            }
            catch (AggregateException)
            {
            }
            if (run.Problem.Length == 0)
            {
                if (play.IsFaulted)
                {
                    run.Problem = play.Exception.GetBaseException().Message;
                }
                else if (!play.IsCompleted)
                {
                    run.Problem = "the section ended before every key was pressed.";
                }
            }
            stop.Cancel();

            // Closing can wait for the output to be read, so the reader keeps reading meanwhile.
            ClosePseudoConsole(console);
            reader.Join(5000);
            output.Dispose();
            input.Dispose();
            CloseHandle(process.Thread);
            CloseHandle(process.Process);
            return run;
        }

        private static ProcessInformation Start(string application, string commandLine, string directory, IntPtr console)
        {
            IntPtr size = IntPtr.Zero;
            InitializeProcThreadAttributeList(IntPtr.Zero, 1, 0, ref size);
            IntPtr list = Marshal.AllocHGlobal(size);
            try
            {
                if (!InitializeProcThreadAttributeList(list, 1, 0, ref size) ||
                    !UpdateProcThreadAttribute(list, 0, (IntPtr)PseudoConsoleAttribute, console, (IntPtr)IntPtr.Size, IntPtr.Zero, IntPtr.Zero))
                {
                    throw new Win32Exception();
                }
                StartupInfoEx startup = new StartupInfoEx();
                startup.StartupInfo.Size = Marshal.SizeOf(typeof(StartupInfoEx));
                // Invalid standard handles, so the section never inherits this process's
                // redirected ones and writes to the pseudo console instead.
                startup.StartupInfo.Flags = UseStandardHandles;
                startup.StartupInfo.StandardInput = InvalidHandle;
                startup.StartupInfo.StandardOutput = InvalidHandle;
                startup.StartupInfo.StandardError = InvalidHandle;
                startup.AttributeList = list;
                ProcessInformation information;
                if (!CreateProcessW(application, new StringBuilder(commandLine), IntPtr.Zero, IntPtr.Zero, false,
                    ExtendedStartupInfoPresent, IntPtr.Zero, directory, ref startup, out information))
                {
                    throw new Win32Exception();
                }
                return information;
            }
            finally
            {
                DeleteProcThreadAttributeList(list);
                Marshal.FreeHGlobal(list);
            }
        }

        private static void Play(
            DemoPress[] presses,
            Func<string, bool> shows,
            Action<string> send,
            int waitForMilliseconds,
            CancellationToken stop)
        {
            foreach (DemoPress press in presses)
            {
                if (!string.IsNullOrEmpty(press.WaitFor))
                {
                    Stopwatch waited = Stopwatch.StartNew();
                    while (!shows(press.WaitFor))
                    {
                        stop.ThrowIfCancellationRequested();
                        if (waited.ElapsedMilliseconds > waitForMilliseconds)
                        {
                            // Escape makes a prompt give up, so the section still ends.
                            send(KeySequences["Escape"]);
                            throw new TimeoutException(string.Format("the screen never showed '{0}'.", press.WaitFor));
                        }
                        Thread.Sleep(50);
                    }
                }
                Thread.Sleep(press.PauseMilliseconds);
                if (!string.IsNullOrEmpty(press.Text))
                {
                    foreach (char character in press.Text)
                    {
                        send(character.ToString());
                        Thread.Sleep(TypeIntervalMilliseconds);
                    }
                }
                if (!string.IsNullOrEmpty(press.Key))
                {
                    send(KeySequence(press.Key));
                }
            }
        }

        private static string KeySequence(string key)
        {
            string sequence;
            if (KeySequences.TryGetValue(key, out sequence))
            {
                return sequence;
            }
            if (key.Length == 1 && char.IsLetterOrDigit(key[0]))
            {
                return key.ToLowerInvariant();
            }
            throw new ArgumentException("Unknown key: " + key);
        }
    }

    public sealed class DemoRenderer : IDisposable
    {
        private const int Padding = 14;
        // Blends between a text colour and its background, for the antialiased edges of a GIF's glyphs.
        private const int BlendLevels = 6;
        private const int MinimumDelayCentiseconds = 2;
        private const uint MarkMissingGlyphs = 1;
        private const ushort MissingGlyph = 0xFFFF;
        private const int BoxFirst = 0x2500;
        private const int BlockFirst = 0x2580;
        private const int BlockLast = 0x259F;

        // The arms of each box-drawing character from U+2500: up, right, down, left, as
        // 0 none, 1 light, 2 heavy, 3 double. x leaves the glyph to the font (dashes,
        // diagonals). Drawn as shapes, lines meet across rows, which the font's glyphs
        // do not at every cell height.
        private static readonly string[] BoxArms =
        {
            "0101", "0202", "1010", "2020", "x", "x", "x", "x",             // U+2500
            "x", "x", "x", "x", "0110", "0210", "0120", "0220",             // U+2508
            "0011", "0012", "0021", "0022", "1100", "1200", "2100", "2200", // U+2510
            "1001", "1002", "2001", "2002", "1110", "1210", "2110", "1120", // U+2518
            "2120", "2210", "1220", "2220", "1011", "1012", "2011", "1021", // U+2520
            "2021", "2012", "1022", "2022", "0111", "0112", "0211", "0212", // U+2528
            "0121", "0122", "0221", "0222", "1101", "1102", "1201", "1202", // U+2530
            "2101", "2102", "2201", "2202", "1111", "1112", "1211", "1212", // U+2538
            "2111", "1121", "2121", "2112", "2211", "1122", "1221", "2212", // U+2540
            "1222", "2122", "2221", "2222", "x", "x", "x", "x",             // U+2548
            "0303", "3030", "0310", "0130", "0330", "0013", "0031", "0033", // U+2550
            "1300", "3100", "3300", "1003", "3001", "3003", "1310", "3130", // U+2558
            "3330", "1013", "3031", "3033", "0313", "0131", "0333", "1303", // U+2560
            "3101", "3303", "1313", "3131", "3333", "0110", "0011", "1001", // U+2568
            "1100", "x", "x", "x", "0001", "1000", "0100", "0010",          // U+2570
            "0002", "2000", "0200", "0020", "0201", "1020", "0102", "2010", // U+2578
        };
        private const int RoundedFirst = 0x256D;
        private const int RoundedLast = 0x2570;

        // Quadrants lit by U+2596 to U+259F: 1 upper left, 2 upper right, 4 lower left, 8 lower right.
        private static readonly int[] Quadrants = { 4, 8, 1, 13, 9, 7, 11, 2, 6, 14 };
        private static readonly Color DefaultForeground = Color.FromArgb(0xCC, 0xCC, 0xCC);
        private static readonly Color DefaultBackground = Color.FromArgb(0x0C, 0x0C, 0x0C);
        private static readonly Color TitleBackground = Color.FromArgb(0x2B, 0x2B, 0x2B);

        private readonly Font regular;
        private readonly Font bold;
        private readonly Font italic;
        private readonly Font boldItalic;
        private readonly Font symbol;
        private readonly Font emoji;
        private readonly int cellWidth;
        private readonly int cellHeight;
        private readonly Dictionary<string, bool> hasGlyph = new Dictionary<string, bool>();
        private readonly Dictionary<int, SolidBrush> brushes = new Dictionary<int, SolidBrush>();

        [DllImport("gdi32.dll")]
        private static extern IntPtr CreateCompatibleDC(IntPtr dc);

        [DllImport("gdi32.dll")]
        private static extern IntPtr SelectObject(IntPtr dc, IntPtr item);

        [DllImport("gdi32.dll")]
        private static extern bool DeleteObject(IntPtr item);

        [DllImport("gdi32.dll")]
        private static extern bool DeleteDC(IntPtr dc);

        [DllImport("gdi32.dll", CharSet = CharSet.Unicode)]
        private static extern uint GetGlyphIndicesW(IntPtr dc, string text, int count, [Out] ushort[] glyphs, uint flags);

        public DemoRenderer(float size)
        {
            string family = FirstInstalled("Cascadia Mono", "Consolas");
            regular = new Font(family, size, FontStyle.Regular, GraphicsUnit.Pixel);
            bold = new Font(family, size, FontStyle.Bold, GraphicsUnit.Pixel);
            italic = new Font(family, size, FontStyle.Italic, GraphicsUnit.Pixel);
            boldItalic = new Font(family, size, FontStyle.Bold | FontStyle.Italic, GraphicsUnit.Pixel);
            symbol = new Font("Segoe UI Symbol", size, FontStyle.Regular, GraphicsUnit.Pixel);
            emoji = new Font("Segoe UI Emoji", size, FontStyle.Regular, GraphicsUnit.Pixel);
            using (Bitmap probe = new Bitmap(1, 1))
            using (Graphics graphics = Graphics.FromImage(probe))
            {
                SizeF ten = graphics.MeasureString("MMMMMMMMMM", regular, PointF.Empty, StringFormat.GenericTypographic);
                cellWidth = (int)Math.Round(ten.Width / 10);
                cellHeight = (int)Math.Ceiling(regular.GetHeight(graphics));
            }
        }

        public void SavePng(DemoSnapshot snapshot, string path, bool showTitle)
        {
            int[] bounds = GetBounds(new[] { snapshot });
            using (Bitmap image = Render(snapshot, bounds, showTitle))
            {
                image.Save(path, ImageFormat.Png);
            }
        }

        // Frames before the first that shows anything are dropped; the last one stays for holdMilliseconds.
        public void SaveGif(IList<DemoSnapshot> frames, int holdMilliseconds, string path, bool showTitle)
        {
            List<DemoSnapshot> shown = frames.SkipWhile(frame => GetBounds(new[] { frame })[1] == 0).ToList();
            if (shown.Count == 0)
            {
                throw new InvalidOperationException("The section drew nothing.");
            }
            int[] bounds = GetBounds(shown);
            int[] palette = BuildPalette(shown, bounds, showTitle);
            Dictionary<int, byte> nearest = new Dictionary<int, byte>();
            List<GifFrame> gifFrames = new List<GifFrame>();
            byte[] previous = null;
            int width = 0;
            int height = 0;
            for (int index = 0; index < shown.Count; index++)
            {
                byte[] indices;
                using (Bitmap image = Render(shown[index], bounds, showTitle))
                {
                    width = image.Width;
                    height = image.Height;
                    indices = Index(image, palette, nearest);
                }
                long end = index + 1 < shown.Count ? shown[index + 1].Milliseconds : shown[index].Milliseconds + holdMilliseconds;
                int delay = Math.Max(MinimumDelayCentiseconds, (int)((end - shown[index].Milliseconds) / 10));
                GifFrame frame = GifFrame.Changed(previous, indices, width, height, delay);
                if (frame == null)
                {
                    gifFrames[gifFrames.Count - 1].Delay += delay;
                }
                else
                {
                    gifFrames.Add(frame);
                }
                previous = indices;
            }
            using (FileStream stream = File.Create(path))
            {
                GifFrame.Write(stream, width, height, palette, gifFrames);
            }
        }

        public void Dispose()
        {
            foreach (Font font in new[] { regular, bold, italic, boldItalic, symbol, emoji })
            {
                font.Dispose();
            }
            foreach (SolidBrush brush in brushes.Values)
            {
                brush.Dispose();
            }
        }

        // First row, row count and column count that hold everything drawn in any of the snapshots.
        private static int[] GetBounds(IEnumerable<DemoSnapshot> snapshots)
        {
            int first = int.MaxValue;
            int last = -1;
            int right = 0;
            foreach (DemoSnapshot snapshot in snapshots)
            {
                for (int y = 0; y < snapshot.Rows; y++)
                {
                    for (int x = 0; x < snapshot.Columns; x++)
                    {
                        DemoCell cell = snapshot.Cells[(y * snapshot.Columns) + x];
                        bool drawn = (!string.IsNullOrEmpty(cell.Text) && cell.Text != " ") ||
                            cell.Background != DemoScreen.DefaultColor || (cell.Style & DemoScreen.Reverse) != 0;
                        if (!drawn)
                        {
                            continue;
                        }
                        first = Math.Min(first, y);
                        last = Math.Max(last, y);
                        right = Math.Max(right, x + Math.Max(1, (int)cell.Width));
                    }
                }
            }
            return last < 0 ? new[] { 0, 0, 0 } : new[] { first, last - first + 1, right };
        }

        private Bitmap Render(DemoSnapshot snapshot, int[] bounds, bool showTitle)
        {
            int titleHeight = showTitle ? cellHeight + Padding : 0;
            int width = (Padding * 2) + (Math.Max(1, bounds[2]) * cellWidth);
            int height = titleHeight + (Padding * 2) + (Math.Max(1, bounds[1]) * cellHeight);
            Bitmap image = new Bitmap(width, height, PixelFormat.Format32bppArgb);
            using (Graphics graphics = Graphics.FromImage(image))
            {
                graphics.Clear(DefaultBackground);
                graphics.TextRenderingHint = TextRenderingHint.AntiAliasGridFit;
                if (showTitle)
                {
                    graphics.FillRectangle(Brush(TitleBackground), 0, 0, width, titleHeight);
                    graphics.DrawString(snapshot.Title ?? "", regular, Brush(DefaultForeground), Padding, Padding / 2,
                        StringFormat.GenericTypographic);
                }
                for (int y = 0; y < bounds[1]; y++)
                {
                    for (int x = 0; x < bounds[2]; x++)
                    {
                        DemoCell cell = snapshot.Cells[((bounds[0] + y) * snapshot.Columns) + x];
                        if (cell.Width == 0)
                        {
                            continue;
                        }
                        Color foreground;
                        Color background;
                        Resolve(cell, out foreground, out background);
                        int left = Padding + (x * cellWidth);
                        int top = titleHeight + Padding + (y * cellHeight);
                        int span = cellWidth * cell.Width;
                        if (background != DefaultBackground)
                        {
                            graphics.FillRectangle(Brush(background), left, top, span, cellHeight);
                        }
                        bool hasText = !string.IsNullOrEmpty(cell.Text) && cell.Text != " ";
                        if (hasText && !DrawShape(graphics, cell.Text, foreground, background, left, top, span))
                        {
                            DrawText(graphics, cell, foreground, left, top, span);
                        }
                        if ((cell.Style & DemoScreen.Underline) != 0)
                        {
                            graphics.FillRectangle(Brush(foreground), left, top + cellHeight - 2, span, 1);
                        }
                        if ((cell.Style & DemoScreen.Strike) != 0)
                        {
                            graphics.FillRectangle(Brush(foreground), left, top + (cellHeight / 2), span, 1);
                        }
                    }
                }
            }
            return image;
        }

        // A glyph from a fallback font whose outline overflows its cells is shrunk and
        // centred in them, so it never covers the next character.
        private void DrawText(Graphics graphics, DemoCell cell, Color foreground, int left, int top, int span)
        {
            Font font = FontFor(cell);
            RectangleF ink = RectangleF.Empty;
            if (font == symbol || font == emoji)
            {
                using (GraphicsPath outline = new GraphicsPath())
                {
                    outline.AddString(cell.Text, font.FontFamily, (int)font.Style, font.Size, PointF.Empty, StringFormat.GenericTypographic);
                    ink = outline.GetBounds();
                }
            }
            bool overflows = ink.Width > 0 && (ink.Left < 0 || ink.Right > span);
            if (!overflows)
            {
                graphics.DrawString(cell.Text, font, Brush(foreground), left, top, StringFormat.GenericTypographic);
                return;
            }
            float scale = Math.Min(1f, (span - 1) / ink.Width);
            GraphicsState state = graphics.Save();
            graphics.TranslateTransform(
                left + ((span - (ink.Width * scale)) / 2f) - (ink.Left * scale),
                top + (cellHeight * (1f - scale) / 2f));
            graphics.ScaleTransform(scale, scale);
            graphics.DrawString(cell.Text, font, Brush(foreground), 0, 0, StringFormat.GenericTypographic);
            graphics.Restore(state);
        }

        // Draws a box-drawing or block character as shapes. False for any other text.
        private bool DrawShape(Graphics graphics, string text, Color foreground, Color background, int left, int top, int width)
        {
            if (text.Length != 1 || text[0] < BoxFirst || text[0] > BlockLast)
            {
                return false;
            }
            int code = text[0];
            if (code >= BlockFirst)
            {
                DrawBlock(graphics, code, foreground, background, left, top, width);
                return true;
            }
            string arms = BoxArms[code - BoxFirst];
            if (arms.Length != 4)
            {
                return false;
            }
            if (code >= RoundedFirst && code <= RoundedLast)
            {
                DrawRounded(graphics, code, foreground, left, top, width);
            }
            else
            {
                DrawArms(graphics, arms, Brush(foreground), left, top, width);
            }
            return true;
        }

        private int LightWidth(int width)
        {
            return Math.Max(1, (int)Math.Round(width / 9.0));
        }

        // Each arm runs from the cell edge to the centre. A double arm is two light lines,
        // which end where they meet the lines of the other arms, as in a drawn frame.
        private void DrawArms(Graphics graphics, string arms, Brush brush, int left, int top, int width)
        {
            int right = left + width;
            int bottom = top + cellHeight;
            int cx = left + (width / 2);
            int cy = top + (cellHeight / 2);
            int light = LightWidth(width);
            int heavy = light * 2;
            int gap = light + 1;
            int up = arms[0] - '0';
            int east = arms[1] - '0';
            int down = arms[2] - '0';
            int west = arms[3] - '0';
            bool doubleAcross = east == 3 || west == 3;
            bool doubleAlong = up == 3 || down == 3;

            if (up == 1 || up == 2)
            {
                int thickness = up == 2 ? heavy : light;
                int end = doubleAcross ? cy - gap + light : cy - (thickness / 2) + thickness;
                graphics.FillRectangle(brush, cx - (thickness / 2), top, thickness, end - top);
            }
            if (down == 1 || down == 2)
            {
                int thickness = down == 2 ? heavy : light;
                int start = doubleAcross ? cy + gap - (light / 2) : cy - (thickness / 2);
                graphics.FillRectangle(brush, cx - (thickness / 2), start, thickness, bottom - start);
            }
            if (east == 1 || east == 2)
            {
                int thickness = east == 2 ? heavy : light;
                int start = doubleAlong ? cx + gap - (light / 2) : cx - (thickness / 2);
                graphics.FillRectangle(brush, start, cy - (thickness / 2), right - start, thickness);
            }
            if (west == 1 || west == 2)
            {
                int thickness = west == 2 ? heavy : light;
                int end = doubleAlong ? cx - gap + light : cx - (thickness / 2) + thickness;
                graphics.FillRectangle(brush, left, cy - (thickness / 2), end - left, thickness);
            }

            // Where a double line ends, in gaps from the centre: short of a double arm beside
            // it, at the centre for a single one or an arm ahead, past it to an outer corner.
            Func<int, int, int, int> meet = (near, ahead, far) =>
                near == 3 ? -1 : near > 0 || ahead > 0 ? 0 : far == 3 ? 1 : 0;
            if (up == 3)
            {
                // The left line, then the right one; an end of -1 stops short, 1 runs on to the far line.
                int leftEnd = cy + (meet(west, down, east) * gap);
                int rightEnd = cy + (meet(east, down, west) * gap);
                graphics.FillRectangle(brush, cx - gap - (light / 2), top, light, leftEnd - top + light - (light / 2));
                graphics.FillRectangle(brush, cx + gap - (light / 2), top, light, rightEnd - top + light - (light / 2));
            }
            if (down == 3)
            {
                int leftStart = cy - (meet(west, up, east) * gap);
                int rightStart = cy - (meet(east, up, west) * gap);
                graphics.FillRectangle(brush, cx - gap - (light / 2), leftStart - (light / 2), light, bottom - leftStart + (light / 2));
                graphics.FillRectangle(brush, cx + gap - (light / 2), rightStart - (light / 2), light, bottom - rightStart + (light / 2));
            }
            if (east == 3)
            {
                int topStart = cx - (meet(up, west, down) * gap);
                int bottomStart = cx - (meet(down, west, up) * gap);
                graphics.FillRectangle(brush, topStart - (light / 2), cy - gap - (light / 2), right - topStart + (light / 2), light);
                graphics.FillRectangle(brush, bottomStart - (light / 2), cy + gap - (light / 2), right - bottomStart + (light / 2), light);
            }
            if (west == 3)
            {
                int topEnd = cx + (meet(up, east, down) * gap);
                int bottomEnd = cx + (meet(down, east, up) * gap);
                graphics.FillRectangle(brush, left, cy - gap - (light / 2), topEnd - left + light - (light / 2), light);
                graphics.FillRectangle(brush, left, cy + gap - (light / 2), bottomEnd - left + light - (light / 2), light);
            }
        }

        // ╭ ╮ ╯ ╰: a quarter circle from the centre of one edge to the centre of the next.
        private void DrawRounded(Graphics graphics, int code, Color color, int left, int top, int width)
        {
            int light = LightWidth(width);
            int radius = width / 2;
            int cx = left + (width / 2);
            int cy = top + (cellHeight / 2);
            int bottom = top + cellHeight;
            int right = left + width;
            // Pen lines are centred on their path; filled bars start at a pixel edge.
            float x = cx - (light / 2) + (light / 2f);
            float y = cy - (light / 2) + (light / 2f);
            Brush brush = Brush(color);
            RectangleF arc;
            float start;
            switch (code)
            {
                case 0x256D:
                    arc = new RectangleF(x, y, radius * 2, radius * 2);
                    start = 180;
                    graphics.FillRectangle(brush, cx - (light / 2), cy + radius, light, bottom - cy - radius);
                    break;
                case 0x256E:
                    arc = new RectangleF(x - (radius * 2), y, radius * 2, radius * 2);
                    start = 270;
                    graphics.FillRectangle(brush, left, cy - (light / 2), cx - radius - left, light);
                    graphics.FillRectangle(brush, cx - (light / 2), cy + radius, light, bottom - cy - radius);
                    break;
                case 0x256F:
                    arc = new RectangleF(x - (radius * 2), y - (radius * 2), radius * 2, radius * 2);
                    start = 0;
                    graphics.FillRectangle(brush, left, cy - (light / 2), cx - radius - left, light);
                    graphics.FillRectangle(brush, cx - (light / 2), top, light, cy - radius - top);
                    break;
                default:
                    arc = new RectangleF(x, y - (radius * 2), radius * 2, radius * 2);
                    start = 90;
                    graphics.FillRectangle(brush, cx - (light / 2), top, light, cy - radius - top);
                    break;
            }
            if (cx + radius < right && (code == 0x256D || code == 0x2570))
            {
                graphics.FillRectangle(brush, cx + radius, cy - (light / 2), right - cx - radius, light);
            }
            using (Pen pen = new Pen(color, light))
            {
                SmoothingMode smoothing = graphics.SmoothingMode;
                graphics.SmoothingMode = SmoothingMode.AntiAlias;
                graphics.DrawArc(pen, arc, start, 90);
                graphics.SmoothingMode = smoothing;
            }
        }

        // ▀ ▁…█ ▉…▏ ▐ ░ ▒ ▓ ▔ ▕ and the quadrants, as filled parts of the cell.
        private void DrawBlock(Graphics graphics, int code, Color foreground, Color background, int left, int top, int width)
        {
            int height = cellHeight;
            Brush brush = Brush(foreground);
            if (code == 0x2580)
            {
                graphics.FillRectangle(brush, left, top, width, height / 2);
            }
            else if (code <= 0x2588)
            {
                int part = (int)Math.Round(height * (code - 0x2580) / 8.0);
                graphics.FillRectangle(brush, left, top + height - part, width, part);
            }
            else if (code <= 0x258F)
            {
                int part = (int)Math.Round(width * (0x2590 - code) / 8.0);
                graphics.FillRectangle(brush, left, top, part, height);
            }
            else if (code == 0x2590)
            {
                graphics.FillRectangle(brush, left + (width / 2), top, width - (width / 2), height);
            }
            else if (code <= 0x2593)
            {
                graphics.FillRectangle(Brush(Blend(background, foreground, (code - 0x2590) / 4.0)), left, top, width, height);
            }
            else if (code == 0x2594)
            {
                graphics.FillRectangle(brush, left, top, width, Math.Max(1, (int)Math.Round(height / 8.0)));
            }
            else if (code == 0x2595)
            {
                int part = Math.Max(1, (int)Math.Round(width / 8.0));
                graphics.FillRectangle(brush, left + width - part, top, part, height);
            }
            else
            {
                int lit = Quadrants[code - 0x2596];
                int half = width / 2;
                int middle = height / 2;
                if ((lit & 1) != 0)
                {
                    graphics.FillRectangle(brush, left, top, half, middle);
                }
                if ((lit & 2) != 0)
                {
                    graphics.FillRectangle(brush, left + half, top, width - half, middle);
                }
                if ((lit & 4) != 0)
                {
                    graphics.FillRectangle(brush, left, top + middle, half, height - middle);
                }
                if ((lit & 8) != 0)
                {
                    graphics.FillRectangle(brush, left + half, top + middle, width - half, height - middle);
                }
            }
        }

        private static void Resolve(DemoCell cell, out Color foreground, out Color background)
        {
            foreground = cell.Foreground == DemoScreen.DefaultColor ? DefaultForeground : Color.FromArgb(cell.Foreground);
            background = cell.Background == DemoScreen.DefaultColor ? DefaultBackground : Color.FromArgb(cell.Background);
            if ((cell.Style & DemoScreen.Reverse) != 0)
            {
                Color swap = foreground;
                foreground = background;
                background = swap;
            }
            if ((cell.Style & DemoScreen.Dim) != 0)
            {
                foreground = Blend(foreground, background, 0.5);
            }
        }

        private static Color Blend(Color from, Color to, double amount)
        {
            return Color.FromArgb(
                (int)Math.Round(from.R + ((to.R - from.R) * amount)),
                (int)Math.Round(from.G + ((to.G - from.G) * amount)),
                (int)Math.Round(from.B + ((to.B - from.B) * amount)));
        }

        // Every colour a frame can hold: the cell colours, and steps between each text
        // colour and its background for the antialiased edges.
        private int[] BuildPalette(IList<DemoSnapshot> frames, int[] bounds, bool showTitle)
        {
            HashSet<int> solids = new HashSet<int> { DefaultBackground.ToArgb(), DefaultForeground.ToArgb() };
            HashSet<long> pairs = new HashSet<long>();
            if (showTitle)
            {
                solids.Add(TitleBackground.ToArgb());
                pairs.Add(((long)DefaultForeground.ToArgb() << 32) | (uint)TitleBackground.ToArgb());
            }
            foreach (DemoSnapshot frame in frames)
            {
                for (int y = 0; y < bounds[1]; y++)
                {
                    for (int x = 0; x < bounds[2]; x++)
                    {
                        DemoCell cell = frame.Cells[((bounds[0] + y) * frame.Columns) + x];
                        Color foreground;
                        Color background;
                        Resolve(cell, out foreground, out background);
                        solids.Add(foreground.ToArgb());
                        solids.Add(background.ToArgb());
                        pairs.Add(((long)foreground.ToArgb() << 32) | (uint)background.ToArgb());
                    }
                }
            }
            int levels = Math.Max(0, Math.Min(BlendLevels, (256 - solids.Count) / Math.Max(1, pairs.Count)));
            List<int> palette = solids.ToList();
            foreach (long pair in pairs)
            {
                Color foreground = Color.FromArgb((int)(pair >> 32));
                Color background = Color.FromArgb((int)(pair & 0xFFFFFFFF));
                for (int level = 1; level <= levels; level++)
                {
                    palette.Add(Blend(background, foreground, level / (double)(levels + 1)).ToArgb());
                }
            }
            palette = palette.Distinct().Take(256).ToList();
            while (palette.Count < 256)
            {
                palette.Add(DefaultBackground.ToArgb());
            }
            return palette.ToArray();
        }

        private static byte[] Index(Bitmap image, int[] palette, Dictionary<int, byte> nearest)
        {
            Rectangle area = new Rectangle(0, 0, image.Width, image.Height);
            BitmapData data = image.LockBits(area, ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
            int[] pixels = new int[image.Width * image.Height];
            try
            {
                for (int y = 0; y < image.Height; y++)
                {
                    Marshal.Copy(data.Scan0 + (y * data.Stride), pixels, y * image.Width, image.Width);
                }
            }
            finally
            {
                image.UnlockBits(data);
            }
            byte[] indices = new byte[pixels.Length];
            for (int index = 0; index < pixels.Length; index++)
            {
                byte entry;
                if (!nearest.TryGetValue(pixels[index], out entry))
                {
                    entry = Nearest(palette, pixels[index]);
                    nearest[pixels[index]] = entry;
                }
                indices[index] = entry;
            }
            return indices;
        }

        private static byte Nearest(int[] palette, int argb)
        {
            int red = (argb >> 16) & 0xFF;
            int green = (argb >> 8) & 0xFF;
            int blue = argb & 0xFF;
            int best = 0;
            int bestDistance = int.MaxValue;
            for (int index = 0; index < palette.Length; index++)
            {
                int dr = ((palette[index] >> 16) & 0xFF) - red;
                int dg = ((palette[index] >> 8) & 0xFF) - green;
                int db = (palette[index] & 0xFF) - blue;
                int distance = (dr * dr) + (dg * dg) + (db * db);
                if (distance < bestDistance)
                {
                    best = index;
                    bestDistance = distance;
                }
            }
            return (byte)best;
        }

        private Font FontFor(DemoCell cell)
        {
            bool emojiText = cell.Text.Length > 1 && (char.IsSurrogate(cell.Text[0]) || cell.Text.IndexOf('\uFE0F') >= 0);
            if (emojiText)
            {
                return emoji;
            }
            if (!HasGlyph(regular, cell.Text))
            {
                return HasGlyph(symbol, cell.Text) ? symbol : emoji;
            }
            bool isBold = (cell.Style & DemoScreen.Bold) != 0;
            bool isItalic = (cell.Style & DemoScreen.Italic) != 0;
            if (isBold && isItalic)
            {
                return boldItalic;
            }
            if (isBold)
            {
                return bold;
            }
            return isItalic ? italic : regular;
        }

        private bool HasGlyph(Font font, string text)
        {
            string key = font.Name + "\u0000" + text;
            bool found;
            if (hasGlyph.TryGetValue(key, out found))
            {
                return found;
            }
            IntPtr dc = CreateCompatibleDC(IntPtr.Zero);
            IntPtr handle = font.ToHfont();
            IntPtr previous = SelectObject(dc, handle);
            try
            {
                ushort[] glyphs = new ushort[text.Length];
                GetGlyphIndicesW(dc, text, text.Length, glyphs, MarkMissingGlyphs);
                found = glyphs.All(glyph => glyph != MissingGlyph);
            }
            finally
            {
                SelectObject(dc, previous);
                DeleteObject(handle);
                DeleteDC(dc);
            }
            hasGlyph[key] = found;
            return found;
        }

        private SolidBrush Brush(Color color)
        {
            SolidBrush brush;
            if (!brushes.TryGetValue(color.ToArgb(), out brush))
            {
                brush = new SolidBrush(color);
                brushes[color.ToArgb()] = brush;
            }
            return brush;
        }

        private static string FirstInstalled(params string[] families)
        {
            using (InstalledFontCollection installed = new InstalledFontCollection())
            {
                foreach (string family in families)
                {
                    if (installed.Families.Any(candidate => candidate.Name == family))
                    {
                        return family;
                    }
                }
            }
            return FontFamily.GenericMonospace.Name;
        }
    }

    // One GIF frame: the rectangle that changed since the frame before, as palette indices.
    public sealed class GifFrame
    {
        private const int MinimumCodeSize = 8;
        private const int MaximumCode = 4095;
        private const int BlockSize = 255;

        public int Left;
        public int Top;
        public int Width;
        public int Height;
        public byte[] Indices;
        public int Delay;

        // The changed rectangle, the whole image for the first frame, or null when nothing changed.
        public static GifFrame Changed(byte[] previous, byte[] current, int width, int height, int delay)
        {
            int left = width;
            int top = height;
            int right = -1;
            int bottom = -1;
            for (int y = 0; y < height; y++)
            {
                for (int x = 0; x < width; x++)
                {
                    int index = (y * width) + x;
                    if (previous != null && previous[index] == current[index])
                    {
                        continue;
                    }
                    left = Math.Min(left, x);
                    top = Math.Min(top, y);
                    right = Math.Max(right, x);
                    bottom = Math.Max(bottom, y);
                }
            }
            if (right < 0)
            {
                return null;
            }
            GifFrame frame = new GifFrame
            {
                Left = left,
                Top = top,
                Width = right - left + 1,
                Height = bottom - top + 1,
                Delay = delay,
            };
            frame.Indices = new byte[frame.Width * frame.Height];
            for (int y = 0; y < frame.Height; y++)
            {
                Array.Copy(current, ((top + y) * width) + left, frame.Indices, y * frame.Width, frame.Width);
            }
            return frame;
        }

        public static void Write(Stream stream, int width, int height, int[] palette, IList<GifFrame> frames)
        {
            BinaryWriter writer = new BinaryWriter(stream);
            writer.Write(Encoding.ASCII.GetBytes("GIF89a"));
            writer.Write((ushort)width);
            writer.Write((ushort)height);
            // A global table of 256 colours, 8 bits each.
            writer.Write((byte)0xF7);
            writer.Write((byte)0);
            writer.Write((byte)0);
            foreach (int color in palette)
            {
                writer.Write((byte)((color >> 16) & 0xFF));
                writer.Write((byte)((color >> 8) & 0xFF));
                writer.Write((byte)(color & 0xFF));
            }
            // Loop forever.
            writer.Write(new byte[] { 0x21, 0xFF, 0x0B });
            writer.Write(Encoding.ASCII.GetBytes("NETSCAPE2.0"));
            writer.Write(new byte[] { 0x03, 0x01, 0x00, 0x00, 0x00 });
            foreach (GifFrame frame in frames)
            {
                // Each frame draws over the last one, which stays.
                writer.Write(new byte[] { 0x21, 0xF9, 0x04, 0x04 });
                writer.Write((ushort)frame.Delay);
                writer.Write(new byte[] { 0x00, 0x00 });
                writer.Write((byte)0x2C);
                writer.Write((ushort)frame.Left);
                writer.Write((ushort)frame.Top);
                writer.Write((ushort)frame.Width);
                writer.Write((ushort)frame.Height);
                writer.Write((byte)0);
                WriteLzw(writer, frame.Indices);
            }
            writer.Write((byte)0x3B);
            writer.Flush();
        }

        private static void WriteLzw(BinaryWriter writer, byte[] indices)
        {
            int clearCode = 1 << MinimumCodeSize;
            int codeSize = MinimumCodeSize + 1;
            int maxCode = clearCode + 1;
            Dictionary<int, int> codes = new Dictionary<int, int>();
            List<byte> bytes = new List<byte>();
            int bitBuffer = 0;
            int bitCount = 0;
            Action<int, int> emit = (code, size) =>
            {
                bitBuffer |= code << bitCount;
                bitCount += size;
                while (bitCount >= 8)
                {
                    bytes.Add((byte)(bitBuffer & 0xFF));
                    bitBuffer >>= 8;
                    bitCount -= 8;
                }
            };

            writer.Write((byte)MinimumCodeSize);
            emit(clearCode, codeSize);
            int current = -1;
            foreach (byte value in indices)
            {
                if (current < 0)
                {
                    current = value;
                    continue;
                }
                int key = (current << 8) | value;
                int next;
                if (codes.TryGetValue(key, out next))
                {
                    current = next;
                    continue;
                }
                emit(current, codeSize);
                codes[key] = ++maxCode;
                if (maxCode >= (1 << codeSize))
                {
                    codeSize++;
                }
                if (maxCode == MaximumCode)
                {
                    emit(clearCode, codeSize);
                    codes.Clear();
                    codeSize = MinimumCodeSize + 1;
                    maxCode = clearCode + 1;
                }
                current = value;
            }
            emit(current, codeSize);
            emit(clearCode, codeSize);
            emit(clearCode + 1, MinimumCodeSize + 1);
            if (bitCount > 0)
            {
                bytes.Add((byte)(bitBuffer & 0xFF));
            }
            for (int offset = 0; offset < bytes.Count; offset += BlockSize)
            {
                int length = Math.Min(BlockSize, bytes.Count - offset);
                writer.Write((byte)length);
                writer.Write(bytes.GetRange(offset, length).ToArray());
            }
            writer.Write((byte)0);
        }
    }
}
'@

# ── Helpers ──────────────────────────────────────────────────────────────────

function Write-Step {
    param([Parameter(Mandatory)][string]$Message)
    Write-Host ''
    Write-Host "== $Message" -ForegroundColor Cyan
}

function Write-Good {
    param([Parameter(Mandatory)][string]$Message)
    Write-Host "   [ok]   $Message" -ForegroundColor Green
}

function Write-Skip {
    param([Parameter(Mandatory)][string]$Message)
    Write-Host "   [skip] $Message" -ForegroundColor DarkGray
}

$script:Problems = [System.Collections.Generic.List[string]]::new()

function Write-Problem {
    param([Parameter(Mandatory)][string]$Message)
    Write-Host "   [fail] $Message" -ForegroundColor Red
    $script:Problems.Add($Message)
}

function Get-Setting {
    param(
        [Parameter(Mandatory)][hashtable]$Table,
        [Parameter(Mandatory)][string]$Key,
        [AllowNull()][object]$Default
    )
    if ($Table.ContainsKey($Key)) { return $Table[$Key] }
    return $Default
}

# The numbered sections of a demo, in order, each with its Number and Title.
function Get-DemoCase {
    param([Parameter(Mandatory)][string]$Name)
    $path = Join-Path $script:DemoRoot "Demo-$Name.ps1"
    $pattern = "Invoke-DemoCase '(?<number>[^']+)' (?:'(?<single>(?:[^']|'')*)'|`"(?<double>[^`"]*)`")"
    $seen = @{}
    foreach ($match in [regex]::Matches((Get-Content -LiteralPath $path -Raw), $pattern)) {
        $number = $match.Groups['number'].Value
        if ($seen.ContainsKey($number)) { continue }
        $seen[$number] = $true
        $title = $match.Groups['double'].Value
        if ($match.Groups['single'].Success) { $title = $match.Groups['single'].Value -replace "''", "'" }
        [PSCustomObject]@{ Number = $number; Title = $title }
    }
}

function Import-DemoType {
    if ('PwshAnsi.Demo.DemoRecorder' -as [type]) { return }
    # Naming any reference drops Add-Type's defaults, so pwsh's reference set goes in,
    # plus System.Drawing.Common, which it lacks. Some pwsh versions split that over
    # more assemblies; a name the runtime lacks is left out.
    $references = @(Get-ChildItem -LiteralPath (Join-Path $PSHOME 'ref') -Filter '*.dll' | ForEach-Object { $_.FullName })
    foreach ($assembly in 'System.Drawing.Common', 'System.Private.Windows.GdiPlus', 'System.Private.Windows.Core') {
        try { $references += [System.Reflection.Assembly]::Load($assembly).Location } catch { }
    }
    Add-Type -TypeDefinition $script:DemoSource -ReferencedAssemblies $references
}

function Initialize-Stage {
    if (Test-Path -LiteralPath $script:StageRoot) {
        # The directory-tree demo lists this folder, so nothing extra goes in it: it is
        # told apart by holding only demo and src.
        $foreign = @(Get-ChildItem -LiteralPath $script:StageRoot -Force | Where-Object { $_.Name -notin 'demo', 'src' })
        if ($foreign.Count -gt 0) {
            throw "$script:StageRoot holds more than demo and src. Move it away and run again."
        }
        Remove-Item -LiteralPath $script:StageRoot -Recurse -Force
    }
    $null = New-Item -ItemType Directory -Path $script:StageRoot
    foreach ($folder in 'demo', 'src') {
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot $folder) -Destination $script:StageRoot -Recurse
    }
}

function Get-DemoPress {
    param(
        [Parameter(Mandatory)][hashtable]$Recording,
        [Parameter(Mandatory)][string]$Number
    )
    $presses = Get-Setting $Recording 'Presses' @{}
    $list = foreach ($entry in @(Get-Setting $presses $Number @())) {
        $press = [PwshAnsi.Demo.DemoPress]::new()
        $press.PauseMilliseconds = $script:PressPauseMilliseconds
        foreach ($property in 'WaitFor', 'Key', 'Text', 'PauseMilliseconds') {
            if ($entry.ContainsKey($property)) { $press.$property = $entry[$property] }
        }
        $press
    }
    return , ([PwshAnsi.Demo.DemoPress[]]@($list))
}

# ── Record ───────────────────────────────────────────────────────────────────

function Export-Demo {
    param([Parameter(Mandatory)][hashtable]$Recording)
    $name = $Recording.Name
    $skip = Get-Setting $Recording 'Skip' @{}
    $live = Get-Setting $Recording 'Live' $false
    $showTitle = Get-Setting $Recording 'ShowTitle' $false
    $columns = Get-Setting $Recording 'Columns' $script:DefaultColumns
    $rows = if ($live) { $script:LiveRows } else { $script:StaticRows }
    $extension = if ($live) { 'gif' } else { 'png' }
    $demoPath = Join-Path $script:StageRoot "demo\Demo-$name.ps1"
    $mediaPath = Join-Path $script:MediaRoot $name

    $sections = @(Get-DemoCase -Name $name | Where-Object { -not $Case -or $Case -contains $_.Number })
    if ($sections.Count -eq 0) { return }
    Write-Step "$name, $($sections.Count) section(s) as $extension"
    if (-not (Test-Path -LiteralPath $mediaPath)) { $null = New-Item -ItemType Directory -Path $mediaPath }

    foreach ($section in $sections) {
        $number = $section.Number
        if ($skip.ContainsKey($number)) {
            Write-Skip "$number`: $($skip[$number])"
            continue
        }
        # A plain title, as the console shows the path to pwsh.exe until the demo sets one.
        # Stop set globally, where modules read it: an error a module only writes in red
        # would otherwise leave the section with exit code 0.
        $command = "[Console]::Title = 'pwsh'; `$global:ErrorActionPreference = 'Stop'; & '$demoPath' -Case '$number'"
        $commandLine = '"{0}" -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "{1}"' -f $script:Pwsh, $command
        $presses = Get-DemoPress -Recording $Recording -Number $number
        $run = [PwshAnsi.Demo.DemoRecorder]::Run(
            $script:Pwsh,
            $commandLine,
            (Join-Path $script:StageRoot 'demo'),
            $columns,
            $rows,
            $presses,
            $live,
            $script:QuietMilliseconds,
            $script:CaseTimeoutMilliseconds,
            $script:WaitForMilliseconds,
            $script:SettleMilliseconds
        )
        if ($run.Problem) {
            Write-Problem "$name $number`: $($run.Problem)"
            continue
        }
        if ($run.ExitCode -ne 0) {
            Write-Problem "$name $number`: the section exited with $($run.ExitCode)."
            continue
        }

        Get-ChildItem -LiteralPath $mediaPath -Filter "$number.*" -File | Remove-Item -Force
        $target = Join-Path $mediaPath "$number.$extension"
        if ($live) {
            $script:Renderer.SaveGif($run.Frames, $script:HoldMilliseconds, $target, $showTitle)
        } else {
            $script:Renderer.SavePng($run.Final, $target, $showTitle)
        }
        Write-Good "$number -> docs\media\$name\$number.$extension"
    }
}

# ── Docs ─────────────────────────────────────────────────────────────────────

function Remove-MediaBlock {
    param([Parameter(Mandatory)][AllowEmptyString()][System.Collections.Generic.List[string]]$Lines)
    while (($start = $Lines.IndexOf($script:MediaStart)) -ge 0) {
        $end = $Lines.IndexOf($script:MediaEnd, $start)
        if ($end -lt 0) { throw "A $script:MediaStart has no $script:MediaEnd after it." }
        # The blank line Add-MediaBlock put above it goes too.
        if ($start -gt 0 -and $Lines[$start - 1].Length -eq 0) { $start-- }
        $Lines.RemoveRange($start, $end - $start + 1)
    }
}

# Adds the images at the end of the heading's section: the heading named, else Demo,
# else the end of the page.
function Add-MediaBlock {
    param(
        [Parameter(Mandatory)][AllowEmptyString()][System.Collections.Generic.List[string]]$Lines,
        [Parameter(Mandatory)][string]$Heading,
        [Parameter(Mandatory)][string[]]$Images
    )
    $at = $Lines.IndexOf("## $Heading")
    if ($at -lt 0) { $at = $Lines.IndexOf("## $script:DefaultHeading") }
    $end = $Lines.Count
    if ($at -ge 0) {
        for ($index = $at + 1; $index -lt $Lines.Count; $index++) {
            if ($Lines[$index].StartsWith('## ')) {
                $end = $index
                break
            }
        }
    }
    while ($end -gt 0 -and $Lines[$end - 1].Length -eq 0) { $end-- }

    $block = @('', $script:MediaStart)
    for ($index = 0; $index -lt $Images.Count; $index++) {
        if ($index -gt 0) { $block += '' }
        $block += $Images[$index]
    }
    $block += $script:MediaEnd
    $Lines.InsertRange($end, [string[]]$block)
}

function Update-DocsMedia {
    foreach ($recording in $script:Recordings) {
        $docPath = Join-Path $script:DocsRoot $recording.Doc
        $folder = Join-Path $script:MediaRoot $recording.Name
        $headings = Get-Setting $recording 'Headings' @{}
        $images = foreach ($section in Get-DemoCase -Name $recording.Name) {
            if (-not (Test-Path -LiteralPath $folder)) { break }
            $file = Get-ChildItem -LiteralPath $folder -Filter "$($section.Number).*" -File |
                Where-Object { $_.Extension -in '.png', '.gif' } |
                Select-Object -First 1
            if (-not $file) { continue }
            # Brackets in a title would end the alt text early.
            $alt = ('{0}. {1}' -f $section.Number, $section.Title) -replace '([\[\]])', '\$1'
            [PSCustomObject]@{
                Heading = Get-Setting $headings $section.Number $script:DefaultHeading
                Line    = "![$alt](media/$($recording.Name)/$($file.Name))"
            }
        }

        $bytes = [System.IO.File]::ReadAllBytes($docPath)
        $hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
        $text = [System.Text.UTF8Encoding]::new($false).GetString($bytes).TrimStart([char]0xFEFF)
        $newline = if ($text.Contains("`r`n")) { "`r`n" } else { "`n" }
        $lines = [System.Collections.Generic.List[string]]::new([string[]]($text -split '\r?\n'))
        Remove-MediaBlock -Lines $lines
        foreach ($group in @($images | Group-Object -Property Heading)) {
            Add-MediaBlock -Lines $lines -Heading $group.Name -Images @($group.Group.Line)
        }
        $updated = $lines -join $newline
        if ($updated -ne $text) {
            [System.IO.File]::WriteAllText($docPath, $updated, [System.Text.UTF8Encoding]::new($hasBom))
            Write-Good "$($recording.Doc): $(@($images).Count) image(s)"
        }
    }
}

# ── Main ─────────────────────────────────────────────────────────────────────

$selected = $script:Recordings
if ($Name) {
    $known = @($script:Recordings | ForEach-Object { $_.Name })
    $unknown = @($Name | Where-Object { $known -notcontains $_ })
    if ($unknown.Count -gt 0) { throw "No demo named $($unknown -join ', '). Known: $($known -join ', ')." }
    $selected = @($script:Recordings | Where-Object { $Name -contains $_.Name })
}
if ($Case -and @($selected).Count -ne 1) { throw '-Case needs exactly one -Name.' }

if (-not $DocsOnly) {
    # Inherited, NO_COLOR would strip every image; the sections that show it set it themselves.
    Remove-Item -Path 'Env:NO_COLOR' -ErrorAction Ignore
    Import-DemoType
    $script:Pwsh = (Get-Process -Id $PID).Path
    $script:Renderer = [PwshAnsi.Demo.DemoRenderer]::new($script:FontSize)
    try {
        Write-Step "Copying demo and src to $script:StageRoot"
        Initialize-Stage
        foreach ($recording in $selected) {
            try {
                Export-Demo -Recording $recording
            } catch {
                Write-Problem "$($recording.Name): $($_.Exception.Message)"
            }
        }
    } finally {
        $script:Renderer.Dispose()
    }
}

Write-Step 'Linking the images into the docs'
Update-DocsMedia

if ($script:Problems.Count -gt 0) {
    Write-Step "$($script:Problems.Count) problem(s)"
    $script:Problems | ForEach-Object { Write-Host "   $_" -ForegroundColor Red }
    exit 1
}
Write-Step 'Done'
