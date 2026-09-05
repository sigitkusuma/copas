# Contributing

Bug reports, feature requests, and pull requests all go through
[Issues](https://github.com/sigitkusuma/copas/issues) and
[Pull requests](https://github.com/sigitkusuma/copas/pulls). Security issues
are the one exception — see [SECURITY.md](SECURITY.md) instead. Participation
is covered by the [Code of Conduct](CODE_OF_CONDUCT.md).

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

## The icon

The mark — a capture viewfinder around two lines of text — is drawn in code
rather than kept as a binary nobody can edit. `Scripts/generate_icon.swift` is
the source of truth; it writes every slot in `Resources/Assets.xcassets` plus
the `docs/logo.png` the README shows.

```bash
swift Scripts/generate_icon.swift
```

It draws two variants. Above 32pt the mark carries both text bars; at and below
32pt they blur into each other, so the compact art drops to one bar and
thickens every stroke. The variant is picked by the slot's *point* size, so
16pt@2x uses the same art as 16pt@1x.

## Releases

Pushing a `v*` tag runs [`.github/workflows/release.yml`](.github/workflows/release.yml):
it waits on the test suite, then builds, signs, notarises, staples and
publishes the GitHub release on a macOS runner — no local machine required for
any of that.

One step is deliberately left out of CI: signing the appcast. `docs/appcast.xml`
carries a Sparkle EdDSA signature that every installed copy of Copas checks
before trusting an update, and that private key has no clean rotation — unlike
a signing certificate or a notarisation credential, there is no way to tell
copies already in the wild to start trusting a different key. It stays on a
maintainer's Mac rather than in GitHub's secrets. After the workflow finishes:

```bash
Scripts/publish-appcast.sh v1.0.4
git add docs/appcast.xml && git commit -m "Release 1.0.4" && git push
```

`Scripts/release.sh` is what the workflow actually runs (`--skip-appcast` is
the flag that leaves the signing step for the command above). It doubles as
the manual escape hatch if CI is ever unavailable — same build, signing and
notarisation, run locally end to end including the appcast:

```bash
Scripts/release.sh --dry-run     # build and gate, skip notarising
Scripts/release.sh v1.0.4        # the real thing, appcast included
```

Either path needs `.env` (copy `.env.example`), a Developer ID certificate,
and a notarisation profile — checked before anything is compiled, and every
failure is fatal, on the theory that a release which looked fine on one
machine and failed Gatekeeper on someone else's is worse than one that never
shipped.

Only a maintainer with signing credentials can cut a release. CI's copies of
those credentials live in the repository's Actions secrets:
`MACOS_CERT_P12_BASE64`, `MACOS_CERT_PASSWORD` (a Developer ID Application
certificate exported as a `.p12`), and `NOTARY_KEY_P8_BASE64`, `NOTARY_KEY_ID`,
`NOTARY_ISSUER_ID` (an App Store Connect API key with the Developer role,
from Users and Access → Integrations in App Store Connect). Everything up to
a real release — building, testing, a dry run — works for anyone.
