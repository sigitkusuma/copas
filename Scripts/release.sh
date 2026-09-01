#!/usr/bin/env bash
#
# Builds, signs, notarises, staples and publishes a Copas release.
#
# The ordering here is not arbitrary. Three earlier releases of the app this
# replaces shipped unnotarised: the script warned and carried on, the artifacts
# looked fine locally, and the failure only appeared on somebody else's machine
# where Gatekeeper refused to open them. So: every credential is checked before
# anything is compiled, every failure is fatal, and the artifacts are inspected
# after the fact rather than assumed.
#
#   Scripts/release.sh --dry-run        build and gate, skip notarising
#   Scripts/release.sh v1.0.0           the real thing
#   Scripts/release.sh v1.0.0 --draft   publish as a draft release
#
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
BUILD="$ROOT/build/release"
EXPORT="$BUILD/export"
ARTIFACTS="$ROOT/build/artifacts"

DRY_RUN=0
DRAFT=0
TAG=""

for argument in "$@"; do
    case "$argument" in
        --dry-run) DRY_RUN=1 ;;
        --draft) DRAFT=1 ;;
        -*) echo "unknown option: $argument" >&2; exit 2 ;;
        *) TAG="$argument" ;;
    esac
done

say()  { printf '\n\033[1m==> %s\033[0m\n' "$1"; }
ok()   { printf '    \033[32m✓\033[0m %s\n' "$1"; }
die()  { printf '    \033[31m✗ %s\033[0m\n' "$1" >&2; exit 1; }

# ─────────────────────────────────────────────────────────────────────────────
say "Preflight"
# Everything that can fail for a reason unrelated to the code fails here, before
# a ten-minute build and a notarisation round trip have been spent.

[ -f "$ROOT/.env" ] || die "no .env — copy .env.example and fill it in"
# shellcheck disable=SC1091
source "$ROOT/.env"

: "${SIGN_IDENTITY:?SIGN_IDENTITY is not set in .env}"
: "${NOTARY_PROFILE:?NOTARY_PROFILE is not set in .env}"

for tool in xcodegen xcodebuild ditto hdiutil; do
    command -v "$tool" >/dev/null || die "$tool is not on PATH"
done
ok "build tools present"

if [ "$DRY_RUN" -eq 0 ]; then
    command -v gh >/dev/null || die "gh is not on PATH, and the release needs it"
fi

# Output is captured before being searched, here and everywhere below. Piping
# into `grep -q` looks tidier and is a trap: grep exits at the first match, the
# producer takes SIGPIPE, and `set -o pipefail` turns a successful check into a
# failed one. It cost an hour to find, and it would have aborted good releases
# at the notarisation gates rather than bad ones.
IDENTITIES="$(security find-identity -v -p codesigning)"
grep -qF "$SIGN_IDENTITY" <<<"$IDENTITIES" \
    || die "signing identity not in the keychain: $SIGN_IDENTITY"
ok "signing identity resolves"

TEAM_ID="$(awk -F' *= *' '/^DEVELOPMENT_TEAM/ {print $2}' "$ROOT/Config/App.xcconfig" | tr -d ' ')"
[ -n "$TEAM_ID" ] || die "could not read DEVELOPMENT_TEAM from Config/App.xcconfig"

VERSION="$(awk -F' *= *' '/^MARKETING_VERSION/ {print $2}' "$ROOT/Config/Version.xcconfig" | tr -d ' ')"
BUILD_NUMBER="$(awk -F' *= *' '/^CURRENT_PROJECT_VERSION/ {print $2}' "$ROOT/Config/Version.xcconfig" | tr -d ' ')"
[ -n "$VERSION" ] || die "could not read MARKETING_VERSION from Config/Version.xcconfig"
ok "version $VERSION (build $BUILD_NUMBER)"

if [ -n "$TAG" ]; then
    # The tag and the compiled-in version have to agree, or an update feed will
    # advertise a version the app does not report and Sparkle will offer it for
    # ever.
    [ "$TAG" = "v$VERSION" ] || die "tag $TAG does not match MARKETING_VERSION $VERSION (expected v$VERSION)"
    ok "tag matches the version"
fi

if [ "$DRY_RUN" -eq 0 ]; then
    [ -n "$TAG" ] || die "a tag is required for a real release (try v$VERSION)"
    [ -z "$(git status --porcelain)" ] || die "working tree is dirty"
    ok "working tree is clean"

    xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 \
        || die "notary profile '$NOTARY_PROFILE' does not resolve — see .env.example"
    ok "notary credentials resolve"
fi

# The private half is in the keychain; this only proves it is reachable.
SPARKLE_BIN="$(find "$ROOT/build" -type d -path '*artifacts/sparkle/Sparkle/bin' 2>/dev/null | head -1)"
if [ -z "$SPARKLE_BIN" ]; then
    say "Resolving Sparkle tools"
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

FEED_URL="$(/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "$ROOT/Config/Info.plist" 2>/dev/null || true)"
[ -n "$FEED_URL" ] || die "SUFeedURL is empty — the updater would have nowhere to look"
ok "feed URL is $FEED_URL"

# ─────────────────────────────────────────────────────────────────────────────
say "Building"
rm -rf "$BUILD" "$ARTIFACTS"
mkdir -p "$ARTIFACTS"

xcodegen generate >/dev/null
ok "project generated"

# The identity comes from Config/App.xcconfig, which applies it to the app target
# alone. Forcing it on the command line reaches Swift Package targets too — and
# GRDB's resource bundle signs automatically, so it refuses a manually specified
# identity and the archive fails. Only the team is safe to impose globally.
xcodebuild -project Copas.xcodeproj -scheme Copas -configuration Release \
    -derivedDataPath "$BUILD" \
    -archivePath "$BUILD/Copas.xcarchive" \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    archive >/dev/null
ok "archived"

xcodebuild -exportArchive \
    -archivePath "$BUILD/Copas.xcarchive" \
    -exportPath "$EXPORT" \
    -exportOptionsPlist "$ROOT/Scripts/ExportOptions.plist" >/dev/null
ok "exported"

APP="$EXPORT/Copas.app"
[ -d "$APP" ] || die "no app at $APP"

# ─────────────────────────────────────────────────────────────────────────────
say "Checking the build before spending a notarisation on it"

ARCHS="$(lipo -archs "$APP/Contents/MacOS/Copas")"
[[ "$ARCHS" == *arm64* && "$ARCHS" == *x86_64* ]] \
    || die "not universal: $ARCHS — an appcast has no architecture predicate"
ok "universal ($ARCHS)"

codesign --verify --strict --deep-verify "$APP" 2>/dev/null \
    || die "the app's signature does not verify"
ok "app signature verifies"

# Ties the identity named in .env to the one actually used. Without this the
# preflight only proves the certificate exists, not that the build used it.
SIGNATURE="$(codesign -dvv "$APP" 2>&1)"
grep -qF "Authority=$SIGN_IDENTITY" <<<"$SIGNATURE" \
    || die "the app is not signed by $SIGN_IDENTITY"
ok "signed by the expected Developer ID"

# Verified separately, because this is the part `codesign --deep` gets wrong:
# nested code that passes a bundle-level check and then fails at update time.
SPARKLE_FRAMEWORK="$APP/Contents/Frameworks/Sparkle.framework"
[ -d "$SPARKLE_FRAMEWORK" ] || die "Sparkle.framework was not embedded"
codesign --verify --strict "$SPARKLE_FRAMEWORK" 2>/dev/null \
    || die "Sparkle.framework's signature does not verify"
ok "Sparkle.framework verifies on its own"

for key in SUFeedURL SUPublicEDKey; do
    value="$(/usr/libexec/PlistBuddy -c "Print :$key" "$APP/Contents/Info.plist" 2>/dev/null || true)"
    # A missing key ships an updater that is permanently broken, and invisibly so
    # until the release after this one.
    [ -n "$value" ] || die "$key is missing from the built app"
done
ok "the built app carries its feed URL and public key"

# ─────────────────────────────────────────────────────────────────────────────
if [ "$DRY_RUN" -eq 1 ]; then
    say "Dry run — stopping before notarisation"
    ditto -c -k --keepParent "$APP" "$ARTIFACTS/Copas-$VERSION.zip"
    ok "wrote $ARTIFACTS/Copas-$VERSION.zip (unnotarised, do not publish)"
    echo
    echo "    Everything that can be checked without an Apple round trip passed."
    exit 0
fi

say "Notarising the app"
# The app is notarised and stapled *first*, and the ZIP and DMG are built from
# the stapled bundle afterwards. Packaging first and stapling the packages leaves
# the app inside them unstapled, which is fine until somebody copies it out.
ditto -c -k --keepParent "$APP" "$BUILD/notarize-app.zip"
xcrun notarytool submit "$BUILD/notarize-app.zip" \
    --keychain-profile "$NOTARY_PROFILE" --wait \
    || die "notarisation failed"
xcrun stapler staple "$APP" || die "could not staple the app"
xcrun stapler validate "$APP" || die "the staple does not validate"
ok "app notarised and stapled"

say "Packaging"
ZIP="$ARTIFACTS/Copas-$VERSION.zip"
DMG="$ARTIFACTS/Copas-$VERSION.dmg"

ditto -c -k --keepParent "$APP" "$ZIP"
ok "$(basename "$ZIP")"

STAGE="$BUILD/dmg"
rm -rf "$STAGE"; mkdir -p "$STAGE"
ditto "$APP" "$STAGE/Copas.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Copas" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
codesign --sign "$SIGN_IDENTITY" "$DMG"
ok "$(basename "$DMG")"

say "Notarising the disk image"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait \
    || die "DMG notarisation failed"
xcrun stapler staple "$DMG" || die "could not staple the DMG"
ok "disk image notarised and stapled"

# ─────────────────────────────────────────────────────────────────────────────
say "Checking the artifacts the way a user would receive them"
# Unpacked from the archive and assessed by Gatekeeper, rather than trusted
# because the build said so. This is the check that caught three bad releases.

VERIFY="$BUILD/verify"
rm -rf "$VERIFY"; mkdir -p "$VERIFY"
ditto -x -k "$ZIP" "$VERIFY"
ASSESSMENT="$(spctl -a -vv -t install "$VERIFY/Copas.app" 2>&1 || true)"
grep -q "source=Notarized Developer ID" <<<"$ASSESSMENT" \
    || die "the app in the ZIP is not accepted as notarised: $ASSESSMENT"
ok "ZIP contents pass Gatekeeper"

DMG_ASSESSMENT="$(spctl -a -vv -t open --context context:primary-signature "$DMG" 2>&1 || true)"
grep -q "accepted" <<<"$DMG_ASSESSMENT" \
    || die "the disk image is not accepted: $DMG_ASSESSMENT"
ok "disk image passes Gatekeeper"

# ─────────────────────────────────────────────────────────────────────────────
say "Publishing"
NOTES="$ROOT/docs/releases/$VERSION.html"
NOTES_ARGUMENT=()
[ -f "$NOTES" ] && NOTES_ARGUMENT=(--notes-file "$NOTES")

DRAFT_ARGUMENT=()
[ "$DRAFT" -eq 1 ] && DRAFT_ARGUMENT=(--draft)

# Assets first, feed second. A feed that points at a release which does not exist
# yet hands every running copy a download that 404s.
gh release create "$TAG" "$ZIP" "$DMG" \
    --title "Copas $VERSION" \
    "${NOTES_ARGUMENT[@]}" "${DRAFT_ARGUMENT[@]}" \
    || die "could not create the GitHub release"
ok "release $TAG created with both assets"

say "Updating the appcast"
"$SPARKLE_BIN/generate_appcast" \
    --download-url-prefix "https://github.com/sigitkusuma/copas/releases/download/$TAG/" \
    --link "https://github.com/sigitkusuma/copas" \
    -o "$ROOT/docs/appcast.xml" \
    "$ARTIFACTS" \
    || die "could not generate the appcast"
ok "docs/appcast.xml written and signed"

echo
echo "    Commit and push docs/appcast.xml to publish the update:"
echo "        git add docs/appcast.xml && git commit -m 'Release $VERSION' && git push"
echo
