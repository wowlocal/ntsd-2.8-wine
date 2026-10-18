#!/bin/bash
# Common 32-bit Windows support for both Wine/FEX and Wine/Rosetta.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CACHE="${NTSD_CACHE_DIR:-$ROOT/.cache}"
OUT="${1:?usage: build-windows-support.sh output-directory}"
mkdir -p "$CACHE" "$OUT"
CACHE="$(cd "$CACHE" && pwd)"
OUT="$(cd "$OUT" && pwd)"
source "$ROOT/tools/runtime-build-common.sh"

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


xcrun clang -arch arm64 -arch x86_64 -mmacosx-version-min=11.0 -O2 -framework AudioToolbox \
    "$ROOT/launcher/audio-probe.c" -o "$OUT/audio-probe"
i686-w64-mingw32-clang -O2 -Wall -Wextra "$ROOT/launcher/audio-config.c" \
    -o "$OUT/audio-config.exe" -lstrmiids -luuid -lole32 -ladvapi32
i686-w64-mingw32-clang -O2 -Wall -Wextra "$ROOT/launcher/audio-probe-win.c" \
    -o "$OUT/audio-probe.exe" -ldsound -luser32
MINHOOK="$ROOT/vendor/minhook"
i686-w64-mingw32-clang -O2 -Wall -Wextra -Wno-unused-parameter -shared \
    -I "$MINHOOK/include" "$ROOT/launcher/display-shim.c" "$ROOT/launcher/display-shim.def" \
    "$MINHOOK/src/buffer.c" "$MINHOOK/src/hook.c" "$MINHOOK/src/trampoline.c" "$MINHOOK/src/hde/hde32.c" \
    -lgdi32 -luser32 -o "$OUT/ddraw.dll"
cp "$MINHOOK/LICENSE.txt" "$OUT/MinHook-LICENSE.txt"
printf '%s\n' "DSOAL $DSOAL_COMMIT + patches/dsoal-silent-fallback.patch" \
    "OpenAL Soft $OPENAL_COMMIT (null backend, patches/openal-no-embedded-hrtf.patch)" \
    'MinHook c3fcafdc10146beb5919319d0683e44e3c30d537 (v1.3.4, unmodified)' > "$OUT/WINDOWS-SOURCES.txt"

mkdir -p "$OUT/toolchain-licenses"
cp "$LLVM/LICENSE.TXT" "$OUT/toolchain-licenses/LLVM-LICENSE.txt"
cp "$LLVM/i686-w64-mingw32/share/mingw32/"COPYING* "$OUT/toolchain-licenses/"
