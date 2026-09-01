# Contributing

## Getting set up

```bash
brew install xcodegen
xcodegen generate
xcodebuild -project Copas.xcodeproj -scheme Copas test
```

macOS 14 or later, and a recent Xcode.

**`project.yml` is the source of truth.** `Copas.xcodeproj` is generated from it
and gitignored, so nobody ever resolves a merge conflict in a `.pbxproj`. Adding
a file means adding it to disk and running `xcodegen generate` — there is no
project file to edit.

## Layout

```
Sources/
  App/          the delegate that owns everything, preferences, logging
  Capture/      watching the pasteboard and deciding what to keep
  Store/        SQLite through GRDB — records, repository, blobs, thumbnails
  Search/       the query grammar and match highlighting
  Paste/        putting a clip back and pressing ⌘V
  Recognition/  Vision text recognition and region capture
  Input/        global shortcuts
  UI/           the board, the menu bar, settings
  Updates/      Sparkle
```

`AppCoordinator` constructs every long-lived object and injects it downward.
There are no singletons for app state and no `NotificationCenter` string-name
bus — if two things need to talk, one of them is handed the other.

## Tests

Everything that can be tested without a window is. That is the reason for a
number of the shapes in here: the pasteboard monitor produces values and holds
no database, the reading-order rule works over rectangles rather than Vision
observations, and language resolution is separate from the probe that asks the
system what it supports.

Run them with `⌘U`, or:

```bash
xcodebuild -project Copas.xcodeproj -scheme Copas test
```

New behaviour needs a test. A test that says *why* the behaviour exists is worth
more than one that restates what the code does — several of the tests here are
the only record of a bug that was genuinely hard to find.

## Style

Match what is around you. A few things that are deliberate rather than accidental:

- Comments explain **why**, not what. If a line needs a comment to say what it
  does, rename something instead.
- British spelling in prose, American in API names that mirror Apple's.
- No abbreviations in names. `combination`, not `combo`.

## Releases

`Scripts/release.sh` builds, signs, notarises, staples, publishes and updates the
appcast, and refuses to continue at the first thing that looks wrong. Try it
without touching anything:

```bash
Scripts/release.sh --dry-run
```

You will need `.env` (copy `.env.example`), a Developer ID certificate, and a
notarisation profile. Only a maintainer with signing credentials can cut a
release; everything up to that point works for anyone.
