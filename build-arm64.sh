#!/bin/bash
# Builds an Apple Silicon app from the NTSD zip and Hadron's signed ARM64
# Wine/FEX runtime. Never re-sign its provisioned cross-architecture loader.
#
#   ./build.sh [path/to/NTSD<version>.zip]
#
# NO_DMG=1 skips the disk image. SIGN_IDENTITY picks the signing identity
# (default "-", ad-hoc); release.sh passes a Developer ID one.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
GAME_ZIP="${1:-$HOME/Downloads/NTSD2.8.3.3.zip}"
REVISION=3   # bump when the wrapper changes, so existing installs re-run setup

HADRON_VERSION=0.3.1
HADRON_URL="https://github.com/Broyojo/hadron/releases/download/v${HADRON_VERSION}/Hadron-${HADRON_VERSION}.dmg"
HADRON_SHA256=c2b1ac78b0151bb634b4a3eced8e305bddbd410d1d1e4dda99b36a9c96998192

CACHE="${NTSD_CACHE_DIR:-$ROOT/.cache}"
BUILD="${NTSD_BUILD_DIR:-$ROOT/build}"
mkdir -p "$CACHE" "$BUILD"
CACHE="$(cd "$CACHE" && pwd)"
BUILD="$(cd "$BUILD" && pwd)"
APP="$BUILD/NTSD.app"
WORK="$(mktemp -d "$BUILD/.work.XXXXXX")"
MOUNT="$WORK/hadron"
cleanup() {
    if mount | grep -Fq " on $MOUNT ("; then hdiutil detach -quiet "$MOUNT" || true; fi
    rm -rf "$WORK"
}
trap cleanup EXIT

step() { printf '\n==> %s\n' "$*"; }

fetch() {  # url sha256 destination
    if [[ -f "$3" ]] && shasum -a 256 "$3" | grep -q "^$2 "; then return; fi
    curl -fL --retry 3 -o "$3.part" "$1"
    shasum -a 256 "$3.part" | grep -q "^$2 " || { echo "checksum mismatch: $1" >&2; exit 1; }
    mv "$3.part" "$3"
}

[[ -f "$GAME_ZIP" ]] || { echo "game zip not found: $GAME_ZIP" >&2; exit 1; }
[[ "$(uname -m)" == arm64 ]] || { echo 'This build requires Apple Silicon.' >&2; exit 1; }
[[ "$(sw_vers -productVersion | cut -d. -f1)" -ge 27 ]] || { echo 'Hadron requires macOS 27 or later.' >&2; exit 1; }
GAME_TOP="$(python3 - "$GAME_ZIP" <<'PY'
import pathlib, sys, zipfile
with zipfile.ZipFile(sys.argv[1]) as z:
    paths = [pathlib.PurePosixPath(n) for n in z.namelist()]
    if any(p.is_absolute() or '..' in p.parts for p in paths):
        sys.exit('unsafe game ZIP path')
    roots = {p.parts[0] for p in paths if p.parts}
    if len(roots) != 1 or not next(iter(roots)).startswith('NTSD'):
        sys.exit('expected one NTSD directory in the ZIP')
    print(next(iter(roots)))
PY
)"
GAME_VERSION="$(sed -E 's/^[^0-9]*//' <<<"$GAME_TOP")"
[[ "$GAME_VERSION" =~ ^[0-9]+(\.[0-9]+)*$ ]] || { echo 'invalid game version' >&2; exit 1; }
BUILD_VERSION="${GAME_VERSION}.${REVISION}"

step "Hadron ${HADRON_VERSION} (native ARM64 Wine + FEX)"
fetch "$HADRON_URL" "$HADRON_SHA256" "$CACHE/Hadron-${HADRON_VERSION}.dmg"
hdiutil attach -readonly -nobrowse -mountpoint "$MOUNT" "$CACHE/Hadron-${HADRON_VERSION}.dmg"
HADRON="$MOUNT/Hadron.app"
codesign --verify --deep --strict "$HADRON"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
RES="$APP/Contents/Resources"

step 'Signed ARM64 runtime (including GStreamer)'
ditto "$HADRON/Contents/SharedSupport/runtime" "$RES/runtime"
# Only shell-script paths/usage text change. Mach-O bytes/signatures, the loader's profile,
# PE libraries, licences and corresponding-source notices stay as released.
patch -s -p1 -d "$RES/runtime" < "$ROOT/launcher/hadron-paths.patch"
hdiutil detach -quiet "$MOUNT"

step "Game: $GAME_TOP"
unzip -q "$GAME_ZIP" -d "$WORK/game"
mv "$WORK/game/$GAME_TOP" "$RES/game"
# Default keys put attack/jump/defend for players 1 and 2 on the numeric
# keypad (Windows VK 100-102 / 97-99), which most Macs don't have. Use J/K/L
# for player 1, as in the original LF2, and , . / next to the arrows for player 2.
CONTROLS="$RES/game/data/control.txt"
grep -q '^0 87 83 65 68 100 101 102 ' "$CONTROLS" && grep -q '^0 38 40 37 39 97 98 99 ' "$CONTROLS" \
    || { echo "unexpected data/control.txt layout, update the key patch" >&2; exit 1; }
sed -i '' -e '1s/^0 87 83 65 68 100 101 102 /0 87 83 65 68 74 75 76 /' \
          -e '2s/^0 38 40 37 39 97 98 99 /0 38 40 37 39 188 190 191 /' "$CONTROLS"

step "Launcher"
clang -arch arm64 -mmacosx-version-min=27.0 -fobjc-arc -O2 -Wall \
    -framework Cocoa -framework CoreGraphics \
    "$ROOT/launcher/main.m" -o "$APP/Contents/MacOS/NTSD"
sed -e "s/@GAME_VERSION@/$GAME_VERSION/g" -e "s/@BUILD_VERSION@/$BUILD_VERSION/g" \
    -e "s/@HADRON_VERSION@/$HADRON_VERSION/g" \
    "$ROOT/launcher/Info.plist" > "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
cp "$ROOT/assets/AppIcon.icns" "$RES/AppIcon.icns"
cp "$ROOT/THIRD_PARTY_NOTICES.txt" "$RES/"

IDENTITY="${SIGN_IDENTITY:--}"
step "Signing ($IDENTITY)"
# Hadron's runtime is already Developer ID signed. Signing with --deep or
# rewriting its Mach-O files would destroy the provisioned loader signature.
# Hardened runtime is enabled; App Sandbox is deliberately absent (LAN play).
xattr -cr "$APP"
SIGN_ARGS=(--force --sign "$IDENTITY" --options runtime)
[[ "$IDENTITY" == '-' ]] || SIGN_ARGS+=(--timestamp)
codesign "${SIGN_ARGS[@]}" "$APP"
python3 "$ROOT/tools/verify_bundle.py" "$APP"
du -sh "$APP"

if [[ -z "${NO_DMG:-}" ]]; then
    step "Disk image"
    DMG="$BUILD/NTSD-${GAME_VERSION}-arm64-experimental-macOS.dmg"
    mkdir "$WORK/dmg"
    cp -R "$APP" "$WORK/dmg/"
    ln -s /Applications "$WORK/dmg/Applications"
    hdiutil create -quiet -ov -volname "NTSD ${GAME_VERSION}" -srcfolder "$WORK/dmg" -format ULMO "$DMG"
    du -sh "$DMG"
fi

step "Done: $APP"
