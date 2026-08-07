#Requires -Version 7.2

# Format-AnsiException.psm1
# Public: Format-AnsiException — builds an [Ansi.Rendering].
# Paint it with Out-AnsiHost, or turn it into strings with Out-AnsiString.

Import-Module (Join-Path $PSScriptRoot 'Ansi.Core.psm1') -Force -DisableNameChecking

function Format-AnsiException {
    [CmdletBinding()]
    [OutputType('Ansi.Rendering')]
    param(
        [Parameter(Position = 0, ValueFromPipeline)]
        [AllowNull()]
        [object]$Exception,

        [ValidateSet('Short', 'Default', 'Full')]
        [string]$Detail = 'Default',

        [switch]$ShowStackTrace,

        [ValidateRange(0, [int]::MaxValue)]
        [int]$MaxFrames = 0,

        [string]$MessageColor = 'BrightRed',

        [string]$TypeColor = 'BrightWhite',

        [string]$PathColor = 'BrightCyan',

        [string]$LineNumberColor = 'BrightYellow',

        [string]$FrameColor = 'BrightBlack',

        [ValidateRange(0, [int]::MaxValue)]
        [int]$Indent = 4,

        [Alias('Width')]
        [int]$MaxWidth = 0
    )
    begin {
        $records = [System.Collections.Generic.List[object]]::new()
    }
    process {
        if ($null -ne $Exception) { $null = $records.Add($Exception) }
    }
    end {
        if ($records.Count -eq 0) { return }

        $anchor = Get-AnsiAnchor -MaxWidth $MaxWidth
        $noColor = Test-AnsiNoColor
        $width = [Math]::Max(1, $anchor.Width)

        $colors = @{
            Message = Get-AnsiColorName -Name $MessageColor
            Type    = Get-AnsiColorName -Name $TypeColor
            Path    = Get-AnsiColorName -Name $PathColor
            Line    = Get-AnsiColorName -Name $LineNumberColor
            Frame   = Get-AnsiColorName -Name $FrameColor
        }

        # Short: message only. Default: + type and frames. Full: + inner exceptions.
        $wantFrames = ($Detail -ne 'Short') -and ($ShowStackTrace -or $Detail -eq 'Full')
        $wantType = ($Detail -ne 'Short')
        $wantInner = ($Detail -eq 'Full')

        $lines = [System.Collections.Generic.List[object]]::new()

        foreach ($record in $records) {
            $info = ConvertTo-AnsiExceptionInfo -Value $record
            Add-AnsiExceptionLines -Info $info -Colors $colors -Width $width -Indent $Indent `
                -WantType:$wantType -WantFrames:$wantFrames -WantInner:$wantInner `
                -MaxFrames $MaxFrames -Level 0 -Lines $lines
        }

        return (New-AnsiRendering -Kind 'Exception' -Rows $lines.ToArray() -Width $width `
                -Column $anchor.Column -NoColor $noColor)
    }
}

function New-AnsiExceptionRun {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text,
        [AllowNull()][string]$Fg
    )
    [PSCustomObject]@{
        Text   = $Text
        Fg     = $(if ($Fg) { $Fg } else { $null })
        Bg     = $null
        Styles = @()
        Link   = $null
    }
}

# Normalise an ErrorRecord, an Exception, or anything else into one shape:
# Message / TypeName / Frames / Inner / Position.
function ConvertTo-AnsiExceptionInfo {
    [CmdletBinding()]
    param([AllowNull()][object]$Value)

    $message = ''
    $typeName = ''
    $stackText = ''
    $position = ''
    $inner = $null

    if ($Value -is [System.Management.Automation.ErrorRecord]) {
        $message = [string]$Value.Exception.Message
        $typeName = $Value.Exception.GetType().FullName
        # ScriptStackTrace reads better than the CLR trace for script errors.
        $stackText = [string]$Value.ScriptStackTrace
        if (-not $stackText) { $stackText = [string]$Value.Exception.StackTrace }
        if ($Value.InvocationInfo -and $Value.InvocationInfo.ScriptName) {
            $position = '{0}: line {1}' -f $Value.InvocationInfo.ScriptName, $Value.InvocationInfo.ScriptLineNumber
        }
        $inner = $Value.Exception.InnerException
    } elseif ($Value -is [System.Exception]) {
        $message = [string]$Value.Message
        $typeName = $Value.GetType().FullName
        $stackText = [string]$Value.StackTrace
        $inner = $Value.InnerException
    } else {
        # Anything else is treated as a bare message: reporting its .NET type
        # (System.String and friends) would be noise, not information.
        $message = [string]$Value
    }

    $frames = @()
    if ($stackText) {
        $frames = @($stackText -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    }

    [PSCustomObject]@{
        Message  = $message
        TypeName = $typeName
        Frames   = $frames
        Position = $position
        Inner    = $inner
    }
}

# A frame line, split into its parts so the path and line number can be coloured:
#   at Format-AnsiText<End>, C:\path\file.psm1: line 71
function Split-AnsiExceptionFrame {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Frame)

    $head = $Frame
    $path = ''
    $lineNumber = ''

    if ($Frame -match '^(?<head>.*?),\s*(?<path>.+?):\s*line\s*(?<line>\d+)\s*$') {
        $head = $Matches['head'] + ', '
        $path = $Matches['path']
        $lineNumber = $Matches['line']
    } elseif ($Frame -match '^(?<head>.*?)\s+in\s+(?<path>.+?):line\s*(?<line>\d+)\s*$') {
        # CLR format: at Type.Method() in C:\path\file.cs:line 42
        $head = $Matches['head'] + ' in '
        $path = $Matches['path']
        $lineNumber = $Matches['line']
    }

    [PSCustomObject]@{ Head = $head; Path = $path; Line = $lineNumber }
}

function Add-AnsiExceptionRow {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][System.Collections.Generic.List[object]]$Lines,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Runs,
        [Parameter(Mandatory)][int]$Width,
        [Parameter(Mandatory)][AllowEmptyString()][string]$HangingIndent
    )
    # Long rows fold, with continuation rows hanging under the first.
    $wrapped = Split-AnsiRuns -Runs $Runs -Width ([Math]::Max(1, $Width - $HangingIndent.Length)) -Overflow Fold

    for ($i = 0; $i -lt $wrapped.Count; $i++) {
        $row = [System.Collections.Generic.List[object]]::new()
        $prefix = if ($i -eq 0) { '' } else { $HangingIndent }
        if ($prefix) { $null = $row.Add((New-AnsiExceptionRun -Text $prefix -Fg $null)) }
        foreach ($r in @($wrapped[$i])) { $null = $row.Add($r) }
        $null = $Lines.Add($row.ToArray())
    }
}

function Add-AnsiExceptionLines {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Info,
        [Parameter(Mandatory)][hashtable]$Colors,
        [Parameter(Mandatory)][int]$Width,
        [Parameter(Mandatory)][int]$Indent,
        [Parameter(Mandatory)][int]$MaxFrames,
        [Parameter(Mandatory)][int]$Level,
        [Parameter(Mandatory)][AllowEmptyCollection()][System.Collections.Generic.List[object]]$Lines,
        [switch]$WantType,
        [switch]$WantFrames,
        [switch]$WantInner
    )
    $levelIndent = ' ' * ($Level * $Indent)
    $frameIndent = ' ' * (($Level * $Indent) + $Indent)

    # Message row: type first when it is wanted, then the message.
    $header = [System.Collections.Generic.List[object]]::new()
    if ($levelIndent) { $null = $header.Add((New-AnsiExceptionRun -Text $levelIndent -Fg $null)) }
    if ($Level -gt 0) {
        $null = $header.Add((New-AnsiExceptionRun -Text ([string][char]0x2514 + [string][char]0x2500 + ' ') -Fg $Colors.Frame))
    }
    if ($WantType -and $Info.TypeName) {
        $null = $header.Add((New-AnsiExceptionRun -Text $Info.TypeName -Fg $Colors.Type))
        $null = $header.Add((New-AnsiExceptionRun -Text ': ' -Fg $Colors.Frame))
    }
    $null = $header.Add((New-AnsiExceptionRun -Text $Info.Message -Fg $Colors.Message))
    Add-AnsiExceptionRow -Lines $Lines -Runs $header.ToArray() -Width $Width -HangingIndent $frameIndent

    if ($WantType -and $Info.Position) {
        $positionRuns = @(
            (New-AnsiExceptionRun -Text ($frameIndent + 'at ') -Fg $Colors.Frame)
            (New-AnsiExceptionRun -Text $Info.Position -Fg $Colors.Path)
        )
        Add-AnsiExceptionRow -Lines $Lines -Runs $positionRuns -Width $Width -HangingIndent $frameIndent
    }

    if ($WantFrames -and $Info.Frames.Count -gt 0) {
        $frames = @($Info.Frames)
        $dropped = 0
        if ($MaxFrames -gt 0 -and $frames.Count -gt $MaxFrames) {
            $dropped = $frames.Count - $MaxFrames
            $frames = @($frames[0..($MaxFrames - 1)])
        }

        foreach ($frame in $frames) {
            $parts = Split-AnsiExceptionFrame -Frame $frame
            $runs = [System.Collections.Generic.List[object]]::new()
            $null = $runs.Add((New-AnsiExceptionRun -Text $frameIndent -Fg $null))
            $null = $runs.Add((New-AnsiExceptionRun -Text $parts.Head -Fg $Colors.Frame))
            if ($parts.Path) {
                $null = $runs.Add((New-AnsiExceptionRun -Text $parts.Path -Fg $Colors.Path))
                $null = $runs.Add((New-AnsiExceptionRun -Text ': line ' -Fg $Colors.Frame))
                $null = $runs.Add((New-AnsiExceptionRun -Text $parts.Line -Fg $Colors.Line))
            }
            Add-AnsiExceptionRow -Lines $Lines -Runs $runs.ToArray() -Width $Width `
                -HangingIndent ($frameIndent + '  ')
        }

        if ($dropped -gt 0) {
            $more = @(
                (New-AnsiExceptionRun -Text $frameIndent -Fg $null)
                (New-AnsiExceptionRun -Text ([string][char]0x2026 + " $dropped more frame" + $(if ($dropped -eq 1) { '' } else { 's' })) -Fg $Colors.Frame)
            )
            Add-AnsiExceptionRow -Lines $Lines -Runs $more -Width $Width -HangingIndent $frameIndent
        }
    }

    if ($WantInner -and $null -ne $Info.Inner) {
        $innerInfo = ConvertTo-AnsiExceptionInfo -Value $Info.Inner
        Add-AnsiExceptionLines -Info $innerInfo -Colors $Colors -Width $Width -Indent $Indent `
            -WantType:$WantType -WantFrames:$WantFrames -WantInner:$WantInner `
            -MaxFrames $MaxFrames -Level ($Level + 1) -Lines $Lines
    }
}

Export-ModuleMember -Function Format-AnsiException
