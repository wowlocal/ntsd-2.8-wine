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
if [[ "${NTSD_RUNTIME:-both}" == both ]]; then
    # Each target gets an isolated output directory and full signing/notarization.
    NTSD_RUNTIME=arm64 NTSD_BUILD_DIR="$OUTPUT/fex" "$ROOT/release.sh" "${ARGS[@]+"${ARGS[@]}"}"
    NTSD_RUNTIME=intel NTSD_BUILD_DIR="$OUTPUT/rosetta" "$ROOT/release.sh" "${ARGS[@]+"${ARGS[@]}"}"
    APP="$OUTPUT/fex/NTSD FEX.app"
    VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
    BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")"
    INTEL_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$OUTPUT/rosetta/NTSD Rosetta.app/Contents/Info.plist")"
    [[ "$BUILD" == "$INTEL_BUILD" ]] || { echo 'Both targets must have the same wrapper revision' >&2; exit 1; }
    if [[ "$PUBLISH" == 1 ]]; then
        gh release create "v$BUILD" \
            "$OUTPUT/fex/NTSD-${VERSION}-FEX-macOS.dmg" "$OUTPUT/fex/NTSD-${VERSION}-FEX-macOS.dmg.sha256" \
            "$OUTPUT/rosetta/NTSD-${VERSION}-Rosetta-macOS.dmg" "$OUTPUT/rosetta/NTSD-${VERSION}-Rosetta-macOS.dmg.sha256" \
            "$OUTPUT/fex/NTSD-${BUILD}-runtime-sources.tar.xz" "$OUTPUT/fex/NTSD-${BUILD}-runtime-sources.tar.xz.sha256" \
            --prerelease --title "NTSD $VERSION for macOS: FEX and Rosetta" --notes-file "$ROOT/RELEASE_NOTES.md"
    fi
    exit 0
fi
case "${NTSD_RUNTIME:-arm64}" in
    arm64)
        APP_NAME="NTSD FEX.app"
        DMG_SUFFIX=FEX-macOS
        NOTES="$ROOT/RELEASE_NOTES_ARM64.md"
        PUBLISH_ARGS=(--prerelease)
        ;;
    intel)
        APP_NAME="NTSD Rosetta.app"
        DMG_SUFFIX=Rosetta-macOS
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

APP="$OUTPUT/$APP_NAME"
if [[ "${NTSD_REUSE_BUILD:-0}" == 1 ]]; then
    # Finalize an already built and tested Developer ID-signed artifact.
    [[ -d "$APP" ]] || { echo "built app missing: $APP" >&2; exit 1; }
    if [[ "${NTSD_RUNTIME:-arm64}" == arm64 ]]; then
        python3 "$ROOT/tools/verify_bundle.py" "$APP"
    else
        python3 "$ROOT/tools/verify_intel_bundle.py" "$APP"
    fi
else
    SIGN_IDENTITY="$IDENTITY" NO_DMG=1 "$ROOT/build.sh" "${ARGS[@]+"${ARGS[@]}"}"
fi
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
ditto "$APP" "$STAGE/$APP_NAME"
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

EXTRA_ASSETS=()
if [[ "${NTSD_RUNTIME:-arm64}" == arm64 || "${NTSD_RUNTIME:-arm64}" == intel ]]; then
    step "Corresponding runtime sources"
    SOURCE="$OUTPUT/NTSD-${BUILD}-runtime-sources.tar.xz"
    python3 "$ROOT/tools/package_runtime_sources.py" "${NTSD_CACHE_DIR:-$ROOT/.cache}" "$SOURCE"
    (cd "$(dirname "$SOURCE")" && shasum -a 256 "$(basename "$SOURCE")") > "$SOURCE.sha256"
    EXTRA_ASSETS=("$SOURCE" "$SOURCE.sha256")
fi

if [[ "$PUBLISH" == 1 ]]; then
    step "Publishing GitHub release v$BUILD"
    TITLE="NTSD $VERSION for macOS"
    [[ "${NTSD_RUNTIME:-arm64}" != arm64 ]] || TITLE="NTSD $VERSION ARM64 preview (Rosetta-free)"
    gh release create "v$BUILD" "$DMG" "$DMG.sha256" ${EXTRA_ASSETS[@]+"${EXTRA_ASSETS[@]}"} ${PUBLISH_ARGS[@]+"${PUBLISH_ARGS[@]}"} \
        --title "$TITLE" --notes-file "$NOTES"
fi

step "Done: $DMG"
