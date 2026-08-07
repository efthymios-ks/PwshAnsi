# Markup and markdown

Shared by every component that takes text. Raw markup is parsed by default;
`-Markdown` adds sugar on top; `-Escape` turns parsing off entirely.

## Markup

Tag form: `[styles...]text[/]`. Tags nest and inherit from the enclosing frame.

```powershell
Format-AnsiText '[bold BrightRed on Blue]Alert[/] · [italic]note[/]' | Out-AnsiHost
Format-AnsiText 'Nested: [BrightRed]red [bold]red+bold[/] red again[/].' | Out-AnsiHost
```

**Grammar inside a tag**

- Style names: `bold`, `italic`, `underline`, `strikethrough`, `reverse`
- Foreground: any accepted colour name (see [Colours](Colours.md))
- Background: `on <colour>`
- Combine freely: `[bold BrightYellow on Blue]…[/]`

**Hyperlinks (OSC 8)**

```powershell
Format-AnsiText 'Visit [link=https://example.com][underline]example.com[/][/].' | Out-AnsiHost
```

**Literal brackets** — double them:

```powershell
Format-AnsiText 'Show literal [[brackets]] in output.' | Out-AnsiHost
# → Show literal [brackets] in output.
```

Parse errors throw: unknown colour or style, unbalanced tags, a tag that is
never closed with `]`, and `on` with no background colour.

## Markdown

Enable with `-Markdown`. Sugar is transformed into markup before parsing, so it
composes with tags.

| Markdown        | Renders as       |
| --------------- | ---------------- |
| `**bold**`      | bold             |
| `*italic*`      | italic           |
| `__underline__` | underline        |
| `~~strike~~`    | strikethrough    |
| `` `code` ``    | bright yellow    |
| `[text](url)`   | OSC 8 hyperlink  |
| `{style}…{/}`   | markup long form |
| `\` prefix      | escape metachar  |

```powershell
Format-AnsiText '**bold**, *italic*, `code`, [Anthropic](https://www.anthropic.com)' -Markdown | Out-AnsiHost
Format-AnsiText 'Long form: {BrightMagenta on Black}styled span{/} inline.' -Markdown | Out-AnsiHost
Format-AnsiText 'Escaped: \*not italic\* and \[not a link\].' -Markdown | Out-AnsiHost
```

Backslash escapes cover the markup metacharacters only: `\[ \] \* \_ \` \{ \} \~`.

## Emoji

`:name:` is replaced with a single glyph when `-Markdown` is on. Unknown names are
left untouched, and matching ignores case.

Names are the shortcodes emoji are commonly written with — the same
`:grinning_face:` spelling other terminal libraries and chat clients take, 1430 of
them, so a token copied from elsewhere renders here:

```powershell
Format-AnsiText ':grinning_face: :thumbs_up: :party_popper: :1st_place_medal: :keycap_10:' -Markdown | Out-AnsiHost
```

PwshAnsi's own short names come first, and keep the glyph they have always had — `:star:`
is the text star, where the full table has the emoji one:

| Token        | Glyph |
| ------------ | ----- |
| `:check:`    | ✓     |
| `:cross:`    | ✗     |
| `:warn:`     | ⚠     |
| `:info:`     | ℹ     |
| `:star:`     | ★     |
| `:heart:`    | ♥     |
| `:arrow:`    | →     |
| `:bullet:`   | •     |
| `:fire:`     | 🔥    |
| `:rocket:`   | 🚀    |
| `:bug:`      | 🐛    |
| `:sparkles:` | ✨    |
| `:tada:`     | 🎉    |

```powershell
Format-AnsiText ':check: Ok · :cross: fail · :warn: careful · :rocket: launch' -Markdown | Out-AnsiHost
```

A token is `:` then letters, digits and underscores, then `:` — which is what names
like `:1st_place_medal:` and `:keycap_10:` need, and why a name is only ever
recognised as a whole token. The table itself is data in `src/Ansi.Emoji.psm1`, one
line per emoji, built on the first lookup rather than at import: a script that writes
no emoji pays nothing for it.

Every emoji Unicode gives a single codepoint sequence is in; sequences that join
several emoji into one — families, most flags — are not.

```powershell
pwsh -File .\demo\Demo-AnsiEmoji.ps1                    # every name, as one matrix
pwsh -File .\demo\Demo-AnsiEmoji.ps1 -Filter '*heart*'  # or just some of them
```

## Escaping everything

`-Escape` treats the input as literal text: no markup, no markdown, no emoji.
It wins over `-Markdown`, and invalid markup no longer throws. Colour and layout
parameters still apply.

```powershell
Format-AnsiText '[bold]X[/]' -Escape -Color BrightRed | Out-AnsiHost   # prints [bold]x[/] in red
```
