# Read-AnsiText

Asks for a line of text and returns it. Reads keys itself, so the answer can be
coloured, masked, timed out, and validated. Returns `$null` when the prompt is
cancelled with Esc or the timeout expires.

Prompts write as they go — an interaction has nothing to hand to `Out-AnsiHost`.

## Synopsis

```powershell
Read-AnsiText [-Prompt] <string> [-Default <string>] [-AllowEmpty] [-Secret]
             [-Validate <scriptblock>] [-ValidationMessage <string>]
             [-PromptColor <string>] [-AnswerColor <string>] [-DefaultColor <string>]
             [-ValidationColor <string>] [-TimeoutSeconds <int>] [-Markdown] [-Escape]
```

## Parameters

| Name                 | Default                     | Description                                                                          |
| -------------------- | --------------------------- | ------------------------------------------------------------------------------------ |
| `-Prompt`            | —                           | The question. Parsed as markup; `-Markdown` adds sugar, `-Escape` turns parsing off.   |
| `-Default`           | none                        | Shown dim as `[value]` and returned when the answer is empty. `-DefaultAnswer` aliases it. |
| `-AllowEmpty`        | off                         | Accept an empty answer instead of re-prompting.                                       |
| `-Secret`            | off                         | Echo `*` per character; the answer is still returned in full.                          |
| `-Validate`          | none                        | Scriptblock receiving the answer; falsy or throwing → re-prompt.                        |
| `-ValidationMessage` | `That answer is not valid.` | Written when `-Validate` rejects the answer.                                            |
| `-AnswerColor`       | `BrightCyan`                | Colour of the typed answer.                                                            |
| `-PromptColor`       | none                        | Colour of the question. Markup inside the prompt wins.                                 |
| `-DefaultColor`      | `BrightBlack`               | Colour of the `[default]` hint.                                                        |
| `-ValidationColor`   | `BrightRed`                 | Colour of validation and "answer required" notes.                                       |
| `-TimeoutSeconds`    | `0` (wait forever)          | Give up after N seconds and return `$null`.                                             |

## Keys

| Key       | Effect                        |
| --------- | ----------------------------- |
| any       | inserts at the caret, echoed in `-AnswerColor` (or `*` with `-Secret`) |
| ← / →     | moves the caret; the field scrolls sideways when the text is wider than it |
| Backspace | removes the character before the caret |

A paste arrives as a burst of keys and is drawn once, not per character. A newline inside that
burst is a pasted line break, not an answer: it is kept in the value and drawn as a literal
`
` - one row cannot show a line break, and the caret counts the two columns it occupies - so a
multi-line paste lands whole in one field instead of submitting part of itself and spilling the
rest into the next prompt. A carriage return is dropped, so CRLF draws once. Only a newline the
burst ends on submits, which is what typing Enter is.
| Enter     | accepts the answer             |
| Esc       | cancels, returns `$null`       |

Control characters are ignored.

## Empty answers, defaults, validation

An empty answer with no `-Default` and no `-AllowEmpty` re-prompts with
*An answer is required.* `-Default` goes through `-Validate` like anything else,
so a default that fails still re-prompts.

```powershell
Read-AnsiText 'Branch' -Default 'main'
Read-AnsiText 'Note (optional)' -AllowEmpty
Read-AnsiText 'Port' -Validate { param($v) $v -match '^\d+$' } -ValidationMessage 'Digits only'
Read-AnsiText 'API key' -Secret
Read-AnsiText '[bold]Environment[/] :rocket:' -Markdown -Default 'Dev'
```

## Non-interactive and NO_COLOR

Throws when input is redirected — a prompt that cannot be answered must fail
rather than hang:

```
Read-AnsiText needs an interactive console: input is redirected.
```

`NO_COLOR` (or redirected output) strips every style from the prompt, the answer,
and the notes; the wording is unchanged.


**The cursor.** Shown while the answer is being typed, whatever the caller had
before, and put back on the way out. Redirected output gets no cursor sequences.

## Usage patterns

**Treat cancel and timeout as "no answer"**

```powershell
$tag = Read-AnsiText 'Tag' -TimeoutSeconds 10
if ($null -eq $tag) { 'No answer — using the default' }
```

**A wizard whose answers end up in a rendering**

```powershell
$project = Read-AnsiText 'Project' -Default 'PwshAnsi'
$target = Read-AnsiText 'Target' -Default 'PowerShell 7.2+'
Format-AnsiGrid @(
    , @('[DarkGray]Project[/]', "[BrightWhite]$project[/]")
    , @('[DarkGray]Target[/]', "[BrightWhite]$target[/]")
) -Padding 3 | Out-AnsiHost
```

## Demo

```powershell
pwsh -File .\demo\Demo-ReadAnsiText.ps1
```

Interactive: a plain question, `-Default`, markup prompts with `-AnswerColor`,
`-Secret`, `-Validate`, `-AllowEmpty`, and a timeout.

## Tests

`tests/Read-AnsiText.Tests.ps1` — 24 Pester 5 tests. The console seams
(`Test-AnsiInteractive`, `Test-AnsiKeyAvailable`, `Read-AnsiKeyInfo`, `Start-AnsiWait`)
are replaced in the module scope, so a scripted key list drives every prompt: no
keyboard, no waiting. Covers typed answers, echo and masking, backspace, control
keys, defaults, empty answers, validation (including a throwing validator), Esc,
timeouts, markup, the redirected-input error, and `NO_COLOR`.

```powershell
pwsh -File .\Invoke-Test.ps1 -Path .\tests\Read-AnsiText.Tests.ps1
```
