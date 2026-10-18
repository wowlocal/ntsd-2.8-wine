#!/usr/bin/env python3
"""Check the retained Intel runtime and its universal native launcher."""
import json
from pathlib import Path
import plistlib
import subprocess
import sys
from verify_bundle import architectures, entitlements

app = Path(sys.argv[1]).resolve(strict=True)
res = app / 'Contents/Resources'
info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
assert info['LSMinimumSystemVersion'] == '11.0'
assert architectures(app / 'Contents/MacOS/NTSD') == {0x0100000c, 0x01000007}
assert architectures(res / 'wine/lib/wine/x86_64-unix/wine') == {0x01000007}
assert (res / 'gstreamer/lib/gstreamer-1.0/libgstasf.dylib').is_file()
bridge = (res / 'wine/lib/wine/x86_64-windows/wow64cpu.dll').read_bytes()
assert bridge[64:80] == b'Wine builtin DLL'
assert b'NTSD Rosetta far-call/return gates enabled' in bridge
assert (res / 'licenses/ROSETTA-SOURCES.txt').is_file()
for name in ['audio-probe', 'audio-probe.exe', 'audio-config.exe', 'game/ddraw.dll', 'game/dsound.dll', 'game/dsoal-aldrv.dll']:
    assert (res / name).is_file(), name
hosts = 0
for path in app.rglob('*'):
    if path.is_symlink() or not path.is_file() or not architectures(path):
        continue
    rights = entitlements(path)
    assert not rights.get('com.apple.security.app-sandbox', False), path
    assert not rights.get('com.apple.security.device.audio-input', False), path
    signature = subprocess.run(['codesign', '-dv', '--verbose=2', str(path)], check=True, capture_output=True).stderr
    assert b'(runtime)' in signature, path
    hosts += 1
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
print(json.dumps({'mach_o_files': hosts, 'universal_launcher': True, 'intel_wine': True,
                  'rosetta_mode_switch_fix': True,
                  'app_sandbox': False, 'microphone_entitlement': False, 'hardened_runtime': True}, indent=2))
