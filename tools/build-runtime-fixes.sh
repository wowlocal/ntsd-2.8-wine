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

fetch() {
    if [[ -f "$3" ]] && shasum -a 256 "$3" | grep -q "^$2 "; then return; fi
    curl -fL --retry 3 "$1" -o "$3.part"
    shasum -a 256 "$3.part" | grep -q "^$2 " || { echo "checksum mismatch: $1" >&2; exit 1; }
    mv "$3.part" "$3"
}
LLVM_VERSION=20260922
LLVM="${NTSD_LLVM_MINGW:-$CACHE/llvm-mingw-$LLVM_VERSION-ucrt-macos-universal}"
if [[ ! -x "$LLVM/bin/aarch64-w64-mingw32-clang" ]]; then
    ARCHIVE="$CACHE/llvm-mingw-$LLVM_VERSION.tar.xz"
    fetch "https://github.com/mstorsjo/llvm-mingw/releases/download/$LLVM_VERSION/llvm-mingw-$LLVM_VERSION-ucrt-macos-universal.tar.xz" \
        52e5f5a7b131021d0c39a37a38fa380a1da7885cd04bd61afd0cd4ecfb8bc1f3 "$ARCHIVE"
    tar -xJf "$ARCHIVE" -C "$CACHE"
fi
export PATH="$LLVM/bin:$PATH"
if ! command -v cmake >/dev/null || ! command -v ninja >/dev/null; then
    python3 -m venv "$CACHE/build-python"
    "$CACHE/build-python/bin/pip" install cmake==3.31.10 ninja==1.13.2
    export PATH="$CACHE/build-python/bin:$PATH"
fi

source_tree() { # URL commit directory; cache is dedicated to this build
    if [[ ! -d "$3/.git" ]]; then git clone --no-checkout "$1" "$3"; fi
    git -C "$3" fetch origin "$2"
    git -C "$3" checkout --detach "$2"
    if [[ "$1" == https://github.com/FEX-Emu/FEX.git ]]; then
        # Windows CPU builds do not use the large Linux test-binary archives.
        git -C "$3" submodule update --init --recursive --jobs 4 -- \
            External/vixl External/fmt External/drm-headers External/xxhash \
            External/Catch2 External/Vulkan-Headers External/jemalloc_glibc \
            External/tracy External/range-v3 External/zydis \
            External/unordered_dense External/rpmalloc Source/Common/cpp-optparse
    else
        git -C "$3" submodule update --init --recursive --jobs 4
    fi
}
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

DSOAL_COMMIT=e11128250439d586483ee6598d1670ab52ab5e37
DSOAL_KEY="$(shasum -a 256 "$ROOT/patches/dsoal-silent-fallback.patch" | cut -c1-16)"
DSOAL="$CACHE/dsoal-$DSOAL_COMMIT-$DSOAL_KEY"
if [[ ! -f "$DSOAL/.ntsd-patched" ]]; then
    source_tree https://github.com/kcat/dsoal.git "$DSOAL_COMMIT" "$DSOAL"
    git -C "$DSOAL" apply "$ROOT/patches/dsoal-silent-fallback.patch"
    touch "$DSOAL/.ntsd-patched"
fi
cat > "$DSOAL/llvm-mingw.cmake" <<EOF
set(CMAKE_SYSTEM_NAME Windows)
set(CMAKE_C_COMPILER "$LLVM/bin/i686-w64-mingw32-clang")
set(CMAKE_CXX_COMPILER "$LLVM/bin/i686-w64-mingw32-clang++")
set(CMAKE_RC_COMPILER "$LLVM/bin/i686-w64-mingw32-windres")
set(CMAKE_SHARED_LINKER_FLAGS_INIT "-static -static-libstdc++ -static-libgcc")
EOF
cmake -S "$DSOAL" -B "$DSOAL/build" -G Ninja \
    -DCMAKE_TOOLCHAIN_FILE="$DSOAL/llvm-mingw.cmake" -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_CXX_SCAN_FOR_MODULES=OFF -DCMAKE_CXX_COMPILER_TARGET=i686-w64-windows-gnu \
    '-DCMAKE_CXX_FLAGS=-include stdlib.h -include malloc.h'
cmake --build "$DSOAL/build" -j "${NTSD_BUILD_JOBS:-2}"
cp "$DSOAL/build/dsound.dll" "$OUT/"

# Build the fallback's OpenAL null backend too, rather than relying on a mutable
# CI release. It is only selected when the native audio service is unavailable.
OPENAL_COMMIT=a70d4116118cdf6bc7ac58fe6ae7a805c7205c50
OPENAL="$CACHE/openal-$OPENAL_COMMIT"
if [[ ! -d "$OPENAL/.git" ]]; then
    source_tree https://github.com/kcat/openal-soft.git "$OPENAL_COMMIT" "$OPENAL"
fi
if [[ ! -f "$OPENAL/.ntsd-patched" ]]; then
    git -C "$OPENAL" apply "$ROOT/patches/openal-no-embedded-hrtf.patch"
    touch "$OPENAL/.ntsd-patched"
fi
cmake -S "$OPENAL" -B "$OPENAL/build" -G Ninja \
    -DCMAKE_TOOLCHAIN_FILE="$DSOAL/llvm-mingw.cmake" -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_CXX_SCAN_FOR_MODULES=OFF -DCMAKE_CXX_COMPILER_TARGET=i686-w64-windows-gnu \
    '-DCMAKE_CXX_FLAGS=-include stdlib.h -include malloc.h' \
    -DALSOFT_UTILS=OFF -DALSOFT_EXAMPLES=OFF -DALSOFT_TESTS=OFF -DALSOFT_ENABLE_MODULES=OFF \
    -DALSOFT_BACKEND_WASAPI=OFF -DALSOFT_BACKEND_DSOUND=OFF \
    -DALSOFT_BACKEND_WINMM=OFF -DALSOFT_BACKEND_WAVE=OFF -DALSOFT_EMBED_HRTF_DATA=OFF
cmake --build "$OPENAL/build" --target OpenAL -j "${NTSD_BUILD_JOBS:-2}"
cp "$OPENAL/build/OpenAL32.dll" "$OUT/dsoal-aldrv.dll"
mkdir -p "$OUT/audio-licenses"
cp "$OPENAL"/COPYING "$OUT/audio-licenses/OpenAL-COPYING"
cp "$OPENAL"/LICENSE* "$OUT/audio-licenses/"
cp "$DSOAL"/LICENSE "$OUT/audio-licenses/DSOAL-LICENSE"
cp "$DSOAL"/fmt-*/LICENSE "$OUT/audio-licenses/fmt-LICENSE"

xcrun clang -arch arm64 -mmacosx-version-min=27.0 -O2 "$ROOT/launcher/wine4k.c" -o "$OUT/wine4k"
xcrun clang -arch arm64 -mmacosx-version-min=27.0 -O2 -framework AudioToolbox \
    "$ROOT/launcher/audio-probe.c" -o "$OUT/audio-probe"
i686-w64-mingw32-clang -O2 -Wall "$ROOT/launcher/audio-config.c" \
    -o "$OUT/audio-config.exe" -lstrmiids -luuid -lole32 -ladvapi32
cp "$FEX/LICENSE" "$OUT/FEX-LICENSE"
printf '%s\n' "FEX $FEX_COMMIT + patches/hadron-fex + patches/fex" \
    "DSOAL $DSOAL_COMMIT + patches/dsoal-silent-fallback.patch" \
    'OpenAL Soft a70d4116118cdf6bc7ac58fe6ae7a805c7205c50 (null backend, patches/openal-no-embedded-hrtf.patch)' \
    > "$OUT/SOURCES.txt"
