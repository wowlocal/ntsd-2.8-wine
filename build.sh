#!/bin/bash
# Builds build/NTSD.app (and a .dmg) from the NTSD zip, an open-source Wine
# build (Gcenx/macOS_Wine_builds) and the GStreamer runtime.
#
#   ./build.sh [path/to/NTSD<version>.zip]
#
# NO_DMG=1 skips the disk image.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
GAME_ZIP="${1:-$HOME/Downloads/NTSD2.8.3.3.zip}"
REVISION=1   # bump when the wrapper changes, so existing installs re-run setup

WINE_VERSION=11.0_1
WINE_URL="https://github.com/Gcenx/macOS_Wine_builds/releases/download/${WINE_VERSION}/wine-stable-${WINE_VERSION}-osx64.tar.xz"
WINE_SHA256=b50dc50ec7f41d58b115a6b685d4d1315ba3c797bd3aa0f49213f2703cb82388

GST_VERSION=1.28.6
GST_URL="https://gstreamer.freedesktop.org/data/pkg/osx/${GST_VERSION}/gstreamer-1.0-${GST_VERSION}-universal.pkg"
GST_SHA256=a8eb366c59b7e9e5dc049848fed6bcd203a8878aa7517c051639fda78797c6ad

CACHE="$ROOT/.cache"
BUILD="$ROOT/build"
APP="$BUILD/NTSD.app"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

step() { printf '\n==> %s\n' "$*"; }

fetch() {  # url sha256 destination
    if [[ -f "$3" ]] && shasum -a 256 "$3" | grep -q "^$2 "; then return; fi
    curl -fL --retry 3 -o "$3.part" "$1"
    shasum -a 256 "$3.part" | grep -q "^$2 " || { echo "checksum mismatch: $1" >&2; exit 1; }
    mv "$3.part" "$3"
}

[[ -f "$GAME_ZIP" ]] || { echo "game zip not found: $GAME_ZIP" >&2; exit 1; }
GAME_TOP="$(zipinfo -1 "$GAME_ZIP" | head -1 | cut -d/ -f1)"
GAME_VERSION="$(sed -E 's/^[^0-9]*//' <<<"$GAME_TOP")"
BUILD_VERSION="${GAME_VERSION}.${REVISION}"

step "Downloading Wine ${WINE_VERSION} and GStreamer ${GST_VERSION}"
mkdir -p "$CACHE"
fetch "$WINE_URL" "$WINE_SHA256" "$CACHE/wine-${WINE_VERSION}.tar.xz"
fetch "$GST_URL" "$GST_SHA256" "$CACHE/gstreamer-${GST_VERSION}.pkg"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
RES="$APP/Contents/Resources"

step "Wine"
tar -xJf "$CACHE/wine-${WINE_VERSION}.tar.xz" -C "$WORK" "Wine Stable.app/Contents/Resources/wine"
mv "$WORK/Wine Stable.app/Contents/Resources/wine" "$RES/wine"
# Mono and Gecko are only needed by .NET apps and the built-in browser.
rm -rf "$RES/wine/share/wine/mono" "$RES/wine/share/wine/gecko"
# Let winegstreamer find the GStreamer copy inside the bundle.
WGST="$RES/wine/lib/wine/x86_64-unix/winegstreamer.so"
install_name_tool -add_rpath @loader_path/../../../../gstreamer/lib "$WGST" 2>/dev/null
codesign --force --sign - "$WGST"

step "GStreamer (only what Wine needs for audio)"
pkgutil --expand-full "$CACHE/gstreamer-${GST_VERSION}.pkg" "$WORK/gstpkg"
mkdir -p "$WORK/gst"
for pkg in "$WORK"/gstpkg/*.pkg; do
    [[ "$pkg" == *osx-framework* ]] && continue
    cp -a "$pkg/Payload/." "$WORK/gst/"
done
python3 "$ROOT/tools/gst_subset.py" "$WORK/gst" "$RES/gstreamer"

step "Game: $GAME_TOP"
unzip -q "$GAME_ZIP" -d "$WORK/game"
mv "$WORK/game/$GAME_TOP" "$RES/game"

step "Launcher"
clang -arch arm64 -arch x86_64 -mmacosx-version-min=11.0 -fobjc-arc -O2 -Wall \
    -framework Cocoa -framework CoreGraphics \
    "$ROOT/launcher/main.m" -o "$APP/Contents/MacOS/NTSD"
sed -e "s/@GAME_VERSION@/$GAME_VERSION/g" -e "s/@BUILD_VERSION@/$BUILD_VERSION/g" \
    -e "s/@WINE_VERSION@/${WINE_VERSION%_*}/g" -e "s/@GST_VERSION@/$GST_VERSION/g" \
    "$ROOT/launcher/Info.plist" > "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
cp "$ROOT/assets/AppIcon.icns" "$RES/AppIcon.icns"
cp -R "$ROOT/launcher/ru.lproj" "$RES/"
cp "$ROOT/THIRD_PARTY_NOTICES.txt" "$RES/"

step "Signing (ad-hoc)"
xattr -cr "$APP"
codesign --force --sign - "$APP"
du -sh "$APP"

if [[ -z "${NO_DMG:-}" ]]; then
    step "Disk image"
    DMG="$BUILD/NTSD-${GAME_VERSION}-macOS.dmg"
    mkdir "$WORK/dmg"
    cp -R "$APP" "$WORK/dmg/"
    ln -s /Applications "$WORK/dmg/Applications"
    hdiutil create -quiet -ov -volname "NTSD ${GAME_VERSION}" -srcfolder "$WORK/dmg" -format ULMO "$DMG"
    du -sh "$DMG"
fi

step "Done: $APP"
