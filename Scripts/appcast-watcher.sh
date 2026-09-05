#!/usr/bin/env bash
#
# Checks whether the newest published GitHub Release has already been signed
# into docs/appcast.xml, and if not, runs publish-appcast.sh and pushes the
# result — the same two commands the Releases section of CONTRIBUTING.md has
# always told a maintainer to run by hand, just no longer dependent on
# somebody remembering to.
#
# Meant to run unattended on a schedule (see Scripts/launchd/) against a
# clone dedicated to this job alone — never a maintainer's working checkout.
# It fast-forwards to origin/main on every run, which is exactly the kind of
# thing that silently destroys uncommitted work if pointed at a real
# development checkout. The marker file check below is a guard against that,
# not a formality: refuse to run anywhere that isn't set up for it.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"

[ -f "$ROOT/.appcast-watcher-clone" ] || {
    echo "refusing to run: $ROOT is not marked as a dedicated appcast-watcher clone" >&2
    echo "(see Scripts/launchd/README.md for how to set one up)" >&2
    exit 1
}

# One run at a time. A slow notarization check or network hiccup should never
# overlap with the next scheduled tick.
LOCK="/tmp/copas-appcast-watcher.lock"
exec 9>"$LOCK"
flock -n 9 || { echo "$(date '+%F %T') already running, skipping"; exit 0; }

echo "$(date '+%F %T') checking for an unpublished release"

git fetch origin --quiet
git checkout main --quiet
# Fast-forward only. A clone dedicated to this job should never have local
# commits to lose — if it somehow does, fail loudly rather than discard them.
git pull --ff-only origin main --quiet

LATEST_TAG="$(gh release list --limit 1 --exclude-drafts --exclude-pre-releases \
    --json tagName -q '.[0].tagName' 2>/dev/null || true)"
if [ -z "$LATEST_TAG" ]; then
    echo "$(date '+%F %T') no published release found"
    exit 0
fi

TOP_VERSION="$(grep -m1 '<sparkle:shortVersionString>' docs/appcast.xml \
    | sed -E 's/.*<sparkle:shortVersionString>(.*)<\/sparkle:shortVersionString>.*/\1/')"
LATEST_VERSION="${LATEST_TAG#v}"

if [ "$TOP_VERSION" = "$LATEST_VERSION" ]; then
    echo "$(date '+%F %T') appcast already up to date at $TOP_VERSION"
    exit 0
fi

echo "$(date '+%F %T') publishing appcast for $LATEST_TAG (appcast currently at $TOP_VERSION)"
Scripts/publish-appcast.sh "$LATEST_TAG"

git add docs/appcast.xml
git commit -m "Release $LATEST_VERSION"
git push origin main
echo "$(date '+%F %T') pushed appcast for $LATEST_TAG"
