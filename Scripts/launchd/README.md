# Automatic appcast publishing

`Scripts/appcast-watcher.sh` closes the one manual step left in this repo's
release pipeline: it notices when a published GitHub Release hasn't been
signed into `docs/appcast.xml` yet, and does it — the same
`Scripts/publish-appcast.sh` + commit + push a maintainer would otherwise run
by hand.

It's meant to run unattended, on a schedule, via `launchd`. That has one
consequence worth being deliberate about: it fast-forwards to `origin/main`
on every run, which would silently discard uncommitted work if pointed at a
real development checkout. So it runs against a **clone dedicated to this job
alone** — never `~/Projects/copas` or wherever you actually work.

## Setup

1. Clone the repo somewhere separate from your working copy, and mark it as
   the dedicated clone:
   ```bash
   git clone https://github.com/sigitkusuma/copas.git ~/.copas-ci/appcast-watcher-clone
   touch ~/.copas-ci/appcast-watcher-clone/.appcast-watcher-clone
   ```
   The marker file is what `appcast-watcher.sh` checks before doing anything
   destructive — without it, the script refuses to run.

2. This clone needs to authenticate as you for `git push` and `gh release
   list` — if `gh auth status` already shows you logged in on this Mac, `git`
   operations over HTTPS already use that credential automatically.

3. It also needs your Sparkle private key reachable exactly the way
   `publish-appcast.sh` expects — i.e. this has to run on the same Mac whose
   keychain holds it. There's no way around that; it's the entire reason this
   is local automation instead of a GitHub Actions job.

4. Copy the plist and fill in the real path:
   ```bash
   cp Scripts/launchd/com.sigitkusuma.copas.appcast-watcher.plist.example \
      ~/Library/LaunchAgents/com.sigitkusuma.copas.appcast-watcher.plist
   sed -i '' "s#/path/to/appcast-watcher-clone#$HOME/.copas-ci/appcast-watcher-clone#g" \
      ~/Library/LaunchAgents/com.sigitkusuma.copas.appcast-watcher.plist
   ```

5. Load it:
   ```bash
   launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.sigitkusuma.copas.appcast-watcher.plist
   ```

## Checking on it

```bash
tail -f /tmp/copas-appcast-watcher.log
launchctl print gui/$(id -u)/com.sigitkusuma.copas.appcast-watcher
```

## Turning it off

```bash
launchctl bootout gui/$(id -u)/com.sigitkusuma.copas.appcast-watcher
rm ~/Library/LaunchAgents/com.sigitkusuma.copas.appcast-watcher.plist
```

The dedicated clone can just be deleted too — it holds nothing that isn't
already on GitHub.
