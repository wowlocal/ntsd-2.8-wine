#!/bin/bash
# Builds, Developer ID-signs, notarizes and staples NTSD.app and its .dmg.
#
#   ./release.sh [path/to/NTSD<version>.zip] [--publish]
#
# --publish also creates a GitHub release with the dmg (needs `gh`).
# Env: CODESIGN_IDENTITY (default: first "Developer ID Application" identity),
#      NOTARY_KEYCHAIN_PROFILE (default: codex-notary, see
#      `xcrun notarytool store-credentials`).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
PUBLISH=0
ARGS=()
for arg in "$@"; do
    if [[ "$arg" == "--publish" ]]; then PUBLISH=1; else ARGS+=("$arg"); fi
done

PROFILE="${NOTARY_KEYCHAIN_PROFILE:-codex-notary}"
OUTPUT="${NTSD_BUILD_DIR:-$ROOT/build}"
case "${NTSD_RUNTIME:-intel}" in
    arm64)
        DMG_SUFFIX=arm64-experimental-macOS
        NOTES="$ROOT/RELEASE_NOTES_ARM64.md"
        PUBLISH_ARGS=(--prerelease)
        ;;
    intel)
        DMG_SUFFIX=macOS
        NOTES="$ROOT/RELEASE_NOTES.md"
        PUBLISH_ARGS=()
        ;;
    *) echo 'NTSD_RUNTIME must be arm64 or intel' >&2; exit 1 ;;
esac
IDENTITY="${CODESIGN_IDENTITY:-$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application:.*\)".*/\1/p' | head -1)}"
[[ -n "$IDENTITY" ]] || { echo "no Developer ID Application identity found" >&2; exit 1; }
xcrun notarytool history --keychain-profile "$PROFILE" --output-format json >/dev/null \
    || { echo "notary profile '$PROFILE' missing: xcrun notarytool store-credentials $PROFILE" >&2; exit 1; }

step() { printf '\n==> %s\n' "$*"; }

notarize() {  # file
    local result="$OUTPUT/$(basename "$1").notary.json"
    xcrun notarytool submit --keychain-profile "$PROFILE" "$1" --wait --timeout 1h --output-format json > "$result"
    cat "$result"
    python3 - "$result" <<'PY'
import json, sys
with open(sys.argv[1]) as f:
    result = json.load(f)
if result.get('status') != 'Accepted':
    sys.exit('Notarization was not Accepted; see ' + sys.argv[1])
PY
}

SIGN_IDENTITY="$IDENTITY" NO_DMG=1 "$ROOT/build.sh" "${ARGS[@]+"${ARGS[@]}"}"
APP="$OUTPUT/NTSD.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")"
DMG="$OUTPUT/NTSD-${VERSION}-${DMG_SUFFIX}.dmg"

step "Notarizing the app"
ditto -c -k --keepParent "$APP" "$OUTPUT/NTSD.zip"
notarize "$OUTPUT/NTSD.zip"
rm "$OUTPUT/NTSD.zip"
xcrun stapler staple "$APP"

step "Disk image"
STAGE="$(mktemp -d "$OUTPUT/.dmg-stage.XXXXXX")"
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
spctl -a -t exec -vv "$APP" 2>&1 | tee "$OUTPUT/app-gatekeeper.txt"
spctl -a -t open --context context:primary-signature -vv "$DMG" 2>&1 | tee "$OUTPUT/dmg-gatekeeper.txt"
for receipt in "$OUTPUT/app-gatekeeper.txt" "$OUTPUT/dmg-gatekeeper.txt"; do
    grep -q 'accepted' "$receipt"
    grep -q 'source=Notarized Developer ID' "$receipt"
done
(cd "$(dirname "$DMG")" && shasum -a 256 "$(basename "$DMG")") | tee "$DMG.sha256"

if [[ "$PUBLISH" == 1 ]]; then
    step "Publishing GitHub release v$BUILD"
    TITLE="NTSD $VERSION for macOS"
    [[ "${NTSD_RUNTIME:-intel}" != arm64 ]] || TITLE="NTSD $VERSION ARM64 experimental"
    gh release create "v$BUILD" "$DMG" "$DMG.sha256" ${PUBLISH_ARGS[@]+"${PUBLISH_ARGS[@]}"} \
        --title "$TITLE" --notes-file "$NOTES"
fi

step "Done: $DMG"
