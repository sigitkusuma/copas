<img src="docs/logo.png" alt="Copas" width="88">

# Copas

A clipboard manager for macOS. Everything you copy, kept, searchable, and one
keystroke away.

Copas lives in the menu bar. Press **⇧⌘V** and a panel opens with everything you
have copied listed down the left, newest first, grouped by day — and the whole of
whichever one you are on beside it. Arrow to a clip or click it, press Return, and
it pastes into whatever you were just typing in.

- **⇧⌘1** captures a region of the screen directly as an **image**.
- **⇧⌘2** captures a region of the screen and puts *the text in it* on your
  clipboard — a receipt, an error dialog, a screenshot somebody sent you.

---

## What it does

- **Text and images**, with formatting preserved. Copy something bold out of a
  document and it pastes back bold.
- **Search that reaches the whole clip**, not just the first line — including
  text recognised inside pictures. Type anywhere on the board to start.
- **Reads text in images automatically**, on this Mac, as they arrive. A
  screenshot of a receipt is findable by what the receipt says.
- **Pinned clips (`⌘P`)**: Keep essential snippets permanently at the top of
  your board, immune to retention pruning.
- **Multi-select & merge (`⌘M`)**: Select multiple clips with ⌘-click or
  Shift-click, choose a delimiter (paragraphs, newlines, commas, tabs, spaces),
  and merge them to the pasteboard or export them as a single file.
- **Text transforms (`⌘T`)**: Format snippets on the fly with 15 built-in
  transforms — case conversions, whitespace cleaning, line sorting, duplicate
  removal, JSON formatting, URL/Base64 encoding, and more.
- **Smart filter pills**: Instant one-tap filter pills beneath search for All
  (`⌘⌥0`), Pinned (`⌘⌥1`), Links (`⌘⌥2`), Code (`⌘⌥3`), Images (`⌘⌥4`), and Colors
  (`⌘⌥5`).
- **Right-click actions & native sharing**: Right-click any clip to Share
  (AirDrop, Messages, Mail, Notes, Reminders), Export to disk (`.txt`, `.json`,
  `.md`, `.png`), Paste, Copy, Pin, or Delete.
- **Clipboard insights & statistics**: Explore your clipboard history, text vs.
  image breakdown, storage footprint, and top source applications in Settings → Stats.
- **Skips what it should.** Anything a password manager marks as concealed is
  never read, never hashed, and never written to disk. You can exclude other
  apps by hand.

---

## Keyboard

| Shortcut | Action |
|---|---|
| `⇧⌘V` | Show the board |
| `⇧⌘1` | Capture region of screen as image |
| `⇧⌘2` | Capture region of screen as text |
| Type anything | Search |
| `↑` `↓` | Move between clips |
| `⌥↑` `⌥↓` | Jump a day at a time |
| `⇞` `⇟` | Move a screenful at a time |
| `Home` `End` | First and last clip |
| `↩` | Paste into active app |
| `⌘↩` | Copy without pasting |
| `⌘1`–`⌘9` | Paste the nth clip |
| `⌘P` | Pin / unpin clip |
| `⌘M` | Merge selected clips (multi-selection) |
| `⌘T` | Open text transform menu |
| `⌘Y` / `Space` | Expand clip preview |
| `⌘⌫` | Delete focused or selected clips |
| `⌘⌥0` | Filter: All |
| `⌘⌥1` | Filter: Pinned |
| `⌘⌥2` | Filter: Links |
| `⌘⌥3` | Filter: Code |
| `⌘⌥4` | Filter: Images |
| `⌘⌥5` | Filter: Colors |
| `⌘,` | Open Settings |
| `⎋` | Dismiss preview, clear search/selection, or close board |

---

## Search & Filters

Free text matches the clip, text recognised inside pictures, and the source app
it came from. Filters narrow it:

```
is:pinned              pinned clips only
app:xcode              copied from Xcode
type:image             pictures only
type:text              text only
has:text invoice       pictures with recognised text mentioning "invoice"
```

You can also use the filter pills beneath the search bar or shortcuts `⌘⌥0`–`⌘⌥5`
to quickly isolate **Pinned**, **Links**, **Code**, **Images**, or **Colors**
(hex & CSS colors).

Anything else with a colon in it — a URL, a `key: value` line you copied — is
searched for literally rather than treated as a filter.

---

## Text Transforms

Press **⌘T** on any text clip (or right-click → Transform) to apply formatting
instantly:

- **Case**: UPPERCASE, lowercase, Title Case
- **Clean Up**: Trim Whitespace, Sort Lines Alphabetically, Remove Duplicate Lines, Number Lines
- **Developer & Web**: Pretty Print JSON, Minify JSON, URL Encode / Decode, Base64 Encode / Decode, Escape HTML, Wrap in Quotes

---

## Privacy

Everything stays on your Mac. There is no account, no sync, and no analytics.
Text recognition runs locally through Live Text and Vision. The only network
request Copas ever makes is to its own update feed.

Clips live in `~/Library/Application Support/Copas/`, unencrypted, readable by
anything running as you — the same as any clipboard manager. If that matters for
what you copy, exclude the app it comes from in Settings → History.

---

## Installing

Download the latest `.dmg` from
[Releases](https://github.com/sigitkusuma/copas/releases/latest) and drag Copas
to Applications. Builds are signed and notarised by Apple.

Copas asks for two permissions, and only when it first needs them:

- **Accessibility**, to press ⌘V for you. Without it the clip still lands on the
  clipboard and ⌘V by hand works.
- **Screen Recording**, for screen capture. Only when you first press ⇧⌘1 or ⇧⌘2.

Requires macOS 14 or later. Universal — Apple silicon and Intel.

---

## Building

```bash
brew install xcodegen
xcodegen generate
open Copas.xcodeproj
```

`project.yml` is the source of truth; `Copas.xcodeproj` is generated and not
checked in. See [CONTRIBUTING.md](CONTRIBUTING.md).

---

## Contributing

Bug reports and pull requests are welcome — see
[CONTRIBUTING.md](CONTRIBUTING.md) for the layout, the test suite, and what's
deliberate about the style. Found a security issue? See
[SECURITY.md](SECURITY.md) instead of opening a public issue.

This project follows a [Code of Conduct](CODE_OF_CONDUCT.md).

---

## Licence

MIT — see [LICENSE](LICENSE). Copas embeds
[Sparkle](https://sparkle-project.org) and [GRDB](https://github.com/groue/GRDB.swift),
both MIT licensed.
