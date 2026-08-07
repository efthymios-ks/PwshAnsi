# Read-AnsiConfirm

Asks a yes/no question and returns a `[bool]`. Returns `$null` when the prompt is
cancelled with Esc or the timeout expires.

Prompts write as they go — an interaction has nothing to hand to `Out-AnsiHost`.

## Synopsis

```powershell
Read-AnsiConfirm [-Prompt] <string> [-Default <bool>]
                [-SuccessMessage <string>] [-FailureMessage <string>]
                [-PromptColor <string>] [-AnswerColor <string>] [-ChoiceColor <string>]
                [-SuccessColor <string>] [-FailureColor <string>]
                [-TimeoutSeconds <int>] [-Markdown] [-Escape]
```

## Parameters

| Name              | Default       | Description                                                                                 |
| ----------------- | ------------- | ------------------------------------------------------------------------------------------- |
| `-Prompt`         | —             | The question. Parsed as markup; `-Markdown` adds sugar, `-Escape` turns parsing off.          |
| `-Default`        | `$true`       | Capitalised in the hint (`[Y/n]`) and returned on Enter. `$null` → `[y/n]` and Enter is ignored. `-DefaultAnswer` aliases it. |
| `-SuccessMessage` | none          | Written after a yes. Parsed as markup.                                                       |
| `-FailureMessage` | none          | Written after a no.                                                                          |
| `-AnswerColor`    | `BrightCyan`  | Colour of the echoed `yes`/`no`.                                                             |
| `-PromptColor`    | none          | Colour of the question. Markup inside the prompt wins.                                       |
| `-ChoiceColor`    | `BrightBlack` | Colour of the `[Y/n]` hint.                                                                  |
| `-SuccessColor`   | `BrightGreen` | Colour of `-SuccessMessage`.                                                                 |
| `-FailureColor`   | `BrightRed`   | Colour of `-FailureMessage`.                                                                 |
| `-TimeoutSeconds` | `0`           | Give up after N seconds and return `$null`.                                                  |

## Keys

| Key         | Effect                                        |
| ----------- | --------------------------------------------- |
| `y` / `Y`   | returns `$true`                                |
| `n` / `N`   | returns `$false`                               |
| Enter       | returns `-Default` (ignored when it is `$null`) |
| Esc         | cancels, returns `$null`                       |

Anything else is ignored. The answer is echoed as a word, so the row reads back as
`Deploy? [Y/n]: yes`.

```powershell
Read-AnsiConfirm 'Deploy now?'
Read-AnsiConfirm '[bold BrightRed]Delete everything?[/]' -Default $false `
    -SuccessMessage ':warn: Deleting' -FailureMessage ':check: Nothing deleted' -Markdown
Read-AnsiConfirm 'Are you sure?' -Default $null      # only y or n will do
```

## Non-interactive and NO_COLOR

Throws when input is redirected — a prompt that cannot be answered must fail
rather than hang:

```
Read-AnsiConfirm needs an interactive console: input is redirected.
```

`NO_COLOR` (or redirected output) strips every style from the question, the echoed
answer, and the messages.


**The cursor.** Hidden while this prompt owns the keyboard — nothing is typed here,
and a list redrawn under a blinking cursor reads as flicker — and put back to
whatever it was on the way out. Redirected output gets no cursor sequences at all.

## Usage patterns

**Guard a destructive step**

```powershell
if (-not (Read-AnsiConfirm 'Drop the database?' -Default $false)) { return }
```

**Distinguish "no" from "cancelled"**

```powershell
$go = Read-AnsiConfirm 'Publish?' -TimeoutSeconds 15
switch ($go) {
    $true { 'Publishing' }
    $false { 'Skipped' }
    default { 'No answer' }        # $null: Esc or timeout
}
```

## Demo

```powershell
pwsh -File .\demo\Demo-ReadAnsiConfirm.ps1
```

Interactive: default yes, `-Default $false` with success/failure messages,
`-Default $null` (`[y/n]`, Enter ignored), a timeout, and guarding a destructive
step.

## Tests

`tests/Read-AnsiConfirm.Tests.ps1` — 18 Pester 5 tests. The console seams
(`Test-AnsiInteractive`, `Test-AnsiKeyAvailable`, `Read-AnsiKeyInfo`, `Start-AnsiWait`)
are replaced in the module scope, so scripted keys drive the prompt. Covers `y`/`n`
in either case, ignored keys, the echoed word, defaults and the capitalised hint,
Enter with no default, success/failure messages and their markup, Esc, timeouts,
the redirected-input error, and `NO_COLOR`.

```powershell
pwsh -File .\Invoke-Test.ps1 -Path .\tests\Read-AnsiConfirm.Tests.ps1
```
