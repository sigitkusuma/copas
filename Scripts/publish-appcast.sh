#!/usr/bin/env bash
#
# Signs and publishes the appcast entry for a release that CI already built,
# signed, notarised and published — the one step Scripts/release.sh --skip-appcast
# leaves undone, because it needs the Sparkle private key, and that key stays
# on this Mac rather than in GitHub's secrets. It is the only secret in the
# whole pipeline with no clean rotation: every copy of Copas already installed
# has today's public key baked into Info.plist, and there is no way to tell
# them to trust a different one after the fact.
#
#   Scripts/publish-appcast.sh v1.0.4
#
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
BUILD="$ROOT/build/release"
UPDATES="$ROOT/build/artifacts/updates"

say()  { printf '\n\033[1m==> %s\033[0m\n' "$1"; }
ok()   { printf '    \033[32m✓\033[0m %s\n' "$1"; }
die()  { printf '    \033[31m✗ %s\033[0m\n' "$1" >&2; exit 1; }

TAG="${1:-}"
[ -n "$TAG" ] || die "usage: Scripts/publish-appcast.sh vX.Y.Z"
VERSION="${TAG#v}"
[ "$TAG" = "v$VERSION" ] || die "expected a tag like vX.Y.Z, got: $TAG"

# ─────────────────────────────────────────────────────────────────────────────
say "Preflight"

command -v gh >/dev/null || die "gh is not on PATH"
[ -z "$(git status --porcelain -- docs/appcast.xml)" ] \
    || die "docs/appcast.xml already has uncommitted changes — resolve those first"

gh release view "$TAG" >/dev/null 2>&1 \
    || die "no GitHub release for $TAG — did the release workflow finish?"
ok "release $TAG exists"

# The private half is in the keychain; this only proves it is reachable. Same
# check Scripts/release.sh runs when it signs the appcast itself.
SPARKLE_BIN="$(find "$ROOT/build" -type d -path '*artifacts/sparkle/Sparkle/bin' 2>/dev/null | head -1 || true)"
if [ -z "$SPARKLE_BIN" ]; then
    say "Resolving Sparkle tools"
    xcodegen generate >/dev/null
    xcodebuild -project Copas.xcodeproj -scheme Copas -configuration Release \
        -derivedDataPath "$BUILD" -resolvePackageDependencies >/dev/null
    SPARKLE_BIN="$(find "$ROOT/build" -type d -path '*artifacts/sparkle/Sparkle/bin' | head -1)"
fi
[ -n "$SPARKLE_BIN" ] || die "could not find Sparkle's bin directory"

PUBLIC_KEY="$("$SPARKLE_BIN/generate_keys" -p 2>/dev/null || true)"
[ -n "$PUBLIC_KEY" ] || die "no Sparkle signing key in the keychain — run $SPARKLE_BIN/generate_keys"

PLIST_KEY="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$ROOT/Config/Info.plist" 2>/dev/null || true)"
[ "$PUBLIC_KEY" = "$PLIST_KEY" ] \
    || die "the keychain key does not match SUPublicEDKey in Info.plist — updates would be rejected"
ok "Sparkle key matches the one compiled into the app"

# ─────────────────────────────────────────────────────────────────────────────
say "Fetching what CI published"
rm -rf "$UPDATES"; mkdir -p "$UPDATES"

gh release download "$TAG" --pattern "Copas-$VERSION.zip" --dir "$UPDATES" \
    || die "could not download Copas-$VERSION.zip from the $TAG release"
ok "$(basename "$UPDATES"/*.zip)"

# generate_appcast picks up release notes from a file named after the archive,
# not the version, and embeds them as CDATA when they are a fragment.
NOTES="$ROOT/docs/releases/$VERSION.html"
if [ -f "$NOTES" ]; then
    cp "$NOTES" "$UPDATES/Copas-$VERSION.html"
    ok "release notes will appear in the update sheet"
else
    ok "no release notes for $VERSION — the update sheet will be bare"
fi

# ─────────────────────────────────────────────────────────────────────────────
say "Signing the appcast"
"$SPARKLE_BIN/generate_appcast" \
    --download-url-prefix "https://github.com/sigitkusuma/copas/releases/download/$TAG/" \
    --link "https://github.com/sigitkusuma/copas" \
    -o "$ROOT/docs/appcast.xml" \
    "$UPDATES" \
    || die "could not generate the appcast"
ok "docs/appcast.xml written and signed"

echo
echo "    Commit and push docs/appcast.xml to publish the update:"
echo "        git add docs/appcast.xml && git commit -m 'Release $VERSION' && git push"
echo
