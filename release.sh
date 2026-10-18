#!/bin/bash
# Builds, Developer ID-signs, notarizes and staples NTSD.app and its .dmg.
#
#   ./release.sh [path/to/NTSD<version>.zip] [--publish]
#
# --publish also creates a GitHub release with the dmg (needs `gh`).
# Env: CODESIGN_IDENTITY (default: first "Developer ID Application" identity),
#      NOTARY_KEYCHAIN_PROFILE (default: keys-cli-notary, see
#      `xcrun notarytool store-credentials`).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
PUBLISH=0
ARGS=()
for arg in "$@"; do
    if [[ "$arg" == "--publish" ]]; then PUBLISH=1; else ARGS+=("$arg"); fi
done

PROFILE="${NOTARY_KEYCHAIN_PROFILE:-keys-cli-notary}"
IDENTITY="${CODESIGN_IDENTITY:-$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application:.*\)".*/\1/p' | head -1)}"
[[ -n "$IDENTITY" ]] || { echo "no Developer ID Application identity found" >&2; exit 1; }
xcrun notarytool history -p "$PROFILE" >/dev/null \
    || { echo "notary profile '$PROFILE' missing: xcrun notarytool store-credentials $PROFILE" >&2; exit 1; }

step() { printf '\n==> %s\n' "$*"; }

notarize() {  # file
    xcrun notarytool submit -p "$PROFILE" "$1" --wait --timeout 1h
}

SIGN_IDENTITY="$IDENTITY" NO_DMG=1 "$ROOT/build.sh" "${ARGS[@]+"${ARGS[@]}"}"
APP="$ROOT/build/NTSD.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")"
DMG="$ROOT/build/NTSD-${VERSION}-macOS.dmg"

step "Notarizing the app"
ditto -c -k --keepParent "$APP" "$ROOT/build/NTSD.zip"
notarize "$ROOT/build/NTSD.zip"
rm "$ROOT/build/NTSD.zip"
xcrun stapler staple "$APP"

step "Disk image"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
ditto "$APP" "$STAGE/NTSD.app"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -quiet -volname "NTSD ${VERSION}" -srcfolder "$STAGE" -format ULMO "$DMG"
codesign --force --sign "$IDENTITY" --timestamp "$DMG"
notarize "$DMG"
xcrun stapler staple "$DMG"

step "Validating"
for item in "$APP" "$DMG"; do
    codesign --verify --deep --strict "$item"
    xcrun stapler validate "$item"
done
spctl -a -t exec -vv "$APP"
spctl -a -t open --context context:primary-signature -vv "$DMG"
shasum -a 256 "$DMG"

if [[ "$PUBLISH" == 1 ]]; then
    step "Publishing GitHub release v$BUILD"
    gh release create "v$BUILD" "$DMG" --title "NTSD $VERSION for macOS" --notes-file "$ROOT/RELEASE_NOTES.md"
fi

step "Done: $DMG"
