#!/bin/bash
# Rebuild downstream CPU/audio fixes from pinned upstream sources. The signed
# Hadron loader and the vendor's 64-bit translator remain byte-for-byte intact.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CACHE="${NTSD_CACHE_DIR:-$ROOT/.cache}"
OUT="${1:?usage: build-runtime-fixes.sh output-directory}"
mkdir -p "$CACHE" "$OUT"
CACHE="$(cd "$CACHE" && pwd)"
OUT="$(cd "$OUT" && pwd)"

source "$ROOT/tools/runtime-build-common.sh"

FEX_COMMIT=741e146fdf5a89517e1a67e3c899907cfba6131a
# A patch-content key gives each revision an independent, immutable source tree.
KEY="$(cat "$ROOT"/patches/{hadron-fex,fex}/*.patch | shasum -a 256 | cut -c1-16)"
FEX="$CACHE/fex-$FEX_COMMIT-$KEY"
if [[ ! -f "$FEX/.ntsd-patched" ]]; then
    source_tree https://github.com/FEX-Emu/FEX.git "$FEX_COMMIT" "$FEX"
    for patchfile in "$ROOT"/patches/hadron-fex/*.patch "$ROOT"/patches/fex/*.patch; do
        git -C "$FEX" apply --check "$patchfile"
        git -C "$FEX" apply "$patchfile"
    done
    touch "$FEX/.ntsd-patched"
fi
cmake -S "$FEX" -B "$FEX/build-windows" -G Ninja \
    -DCMAKE_TOOLCHAIN_FILE="$FEX/Data/CMake/toolchain_mingw.cmake" \
    -DMINGW_TRIPLE=aarch64-w64-mingw32 -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=OFF -DBUILD_THUNKS=OFF -DBUILD_FEX_LINUX_TESTS=OFF \
    -DBUILD_TESTING=OFF -DBUILD_STEAM_SUPPORT=OFF -DENABLE_ASSERTIONS=OFF \
    -DENABLE_LTO=OFF -DENABLE_GDB_SYMBOLS=OFF -DTUNE_CPU=generic -DTUNE_ARCH=generic
cmake --build "$FEX/build-windows" --target wow64fex -j "${NTSD_BUILD_JOBS:-2}"
cmake -S "$FEX/Source/Windows/UnixLib" -B "$FEX/build-macos" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_CXX_COMPILER="$(xcrun --find clang++)" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=27.0
cmake --build "$FEX/build-macos" --target wow64fex_unixlib -j "${NTSD_BUILD_JOBS:-2}"
cp "$FEX/build-windows/Bin/libwow64fex.dll" "$OUT/"
cp "$FEX/build-macos/libwow64fex.so" "$OUT/"

"$ROOT/tools/build-windows-support.sh" "$OUT"
xcrun clang -arch arm64 -mmacosx-version-min=27.0 -O2 "$ROOT/launcher/wine4k.c" -o "$OUT/wine4k"
cp "$FEX/LICENSE" "$OUT/FEX-LICENSE"
printf '%s\n' "FEX $FEX_COMMIT + patches/hadron-fex + patches/fex" > "$OUT/SOURCES.txt"
cat "$OUT/WINDOWS-SOURCES.txt" >> "$OUT/SOURCES.txt"
