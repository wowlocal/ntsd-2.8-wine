#!/bin/bash
# Rebuild the Wine 11.0 WoW64 CPU module with Rosetta-safe mode transitions.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CACHE="${NTSD_CACHE_DIR:-$ROOT/.cache}"
WINE="${1:?usage: build-rosetta-bridge.sh wine-runtime output-directory}"
OUT="${2:?output directory required}"
mkdir -p "$CACHE" "$OUT"
CACHE="$(cd "$CACHE" && pwd)"
OUT="$(cd "$OUT" && pwd)"
source "$ROOT/tools/runtime-build-common.sh"

COMMIT=db11d0fe6a169c457e23d007e20404643d067aa8
SHA=18aaee150ad540885b9706ae73ccf6febca904049de2792199a9dc18a2772e6a
ARCHIVE="$CACHE/wine-source-$COMMIT.tar.gz"
fetch "https://codeload.github.com/Gcenx/wine/tar.gz/$COMMIT" "$SHA" "$ARCHIVE"
KEY="$(shasum -a 256 "$ROOT/patches/wine-rosetta-mode-switch.patch" | cut -c1-16)"
SOURCE="$CACHE/wine-rosetta-$COMMIT-$KEY"
if [[ ! -f "$SOURCE/.ntsd-patched" ]]; then
    mkdir -p "$SOURCE"
    tar -xzf "$ARCHIVE" --strip-components=1 -C "$SOURCE"
    patch -d "$SOURCE" -p1 < "$ROOT/patches/wine-rosetta-mode-switch.patch"
    touch "$SOURCE/.ntsd-patched"
fi
WORK="$(mktemp -d "$OUT/.bridge.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

# Use the exact bundled Wine exports, including its private ntdll interfaces.
python3 - "$LLVM/bin" "$WINE" "$WORK" <<'PY'
from pathlib import Path
import re
import subprocess
import sys
llvm, wine, work = map(Path, sys.argv[1:])
for dll in ('ntdll', 'wow64'):
    module = wine / 'lib/wine/x86_64-windows' / (dll + '.dll')
    exports = subprocess.check_output([str(llvm/'llvm-objdump'), '-p', str(module)], text=True).split('Export Table:', 1)[1]
    names = [m.group(1) for line in exports.splitlines()
             if (m := re.match(r'\s+\d+\s+0x[0-9a-f]+\s+(\S+)', line))]
    if dll == 'wow64':
        assert 'Wow64SystemServiceEx' in names
    else:
        assert len(names) > 1000
    definition = work / (dll + '.def')
    definition.write_text('LIBRARY ' + dll + '.dll\nEXPORTS\n' + '\n'.join(names) + '\n')
    subprocess.run([str(llvm/'llvm-dlltool'), '-m', 'i386:x86-64', '-d', str(definition),
                    '-l', str(work/('lib' + dll + '.a'))], check=True)
names = ['BTCpuGetBopCode', 'BTCpuGetContext', 'BTCpuIsProcessorFeaturePresent',
         'BTCpuProcessInit', 'BTCpuResetToConsistentState', 'BTCpuSetContext',
         'BTCpuSimulate', 'BTCpuTurboThunkControl', '__wine_get_unix_opcode']
(work/'wow64cpu.def').write_text('LIBRARY wow64cpu.dll\nEXPORTS\n' + '\n'.join(names) + '\n')
PY

# This module has no C runtime startup or dependency on Microsoft's CRT.
# ntdll supplies Wine's debug formatter, memory/string helpers and thread APIs.
x86_64-w64-mingw32-clang -O2 -D__WINESRC__ -D__WINE_PE_BUILD -Dvsnprintf=_vsnprintf \
    -I "$SOURCE/include" -shared -nostdlib -Wl,--entry,DllMain \
    -Wl,--image-base,0x7a400000 "$SOURCE/dlls/wow64cpu/cpu.c" \
    "$WORK/wow64cpu.def" -L "$WORK" -lwow64 -lntdll -o "$OUT/wow64cpu.dll"
python3 - "$OUT/wow64cpu.dll" <<'PY'
from pathlib import Path
import struct
import sys
p = Path(sys.argv[1])
data = bytearray(p.read_bytes())
assert data[:2] == b'MZ' and struct.unpack_from('<I', data, 60)[0] >= 96
# Same builtin marker as winebuild --builtin. Wine then refreshes this module
# when updating an existing prefix, instead of preserving it as a native DLL.
data[64:96] = b'Wine builtin DLL'.ljust(32, b'\0')
p.write_bytes(data)
PY
cp "$SOURCE/COPYING.LIB" "$OUT/Wine-COPYING.LIB"
printf '%s\n' "Wine Gcenx/wine $COMMIT (11.0 stable)" \
    "Source archive SHA256 $SHA" \
    'Patch: patches/wine-rosetta-mode-switch.patch' \
    'Far-call trampoline design: tsukasa-art/swingby-wine, LGPL-2.1-or-later' \
    'https://github.com/tsukasa-art/swingby-wine/blob/9c9d68d4d0b2fbf25117d9d2e737b5a9f43561ee/dlls/wow64cpu/cpu.c' \
    "llvm-mingw $LLVM_VERSION" > "$OUT/ROSETTA-SOURCES.txt"
