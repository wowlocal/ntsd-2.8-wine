# Shared pinned compiler and source checkout helpers. Sourced by build scripts.
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
