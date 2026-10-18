#!/usr/bin/env python3
"""Reject Intel-only host code, a missing FEX loader, or sandboxed LAN builds."""
import json
from pathlib import Path
import plistlib
import struct
import subprocess
import sys


def check(*args):
    return subprocess.check_output(args, stderr=subprocess.STDOUT)


def entitlements(path):
    output = subprocess.run(
        ['codesign', '-d', '--entitlements', '-', '--xml', str(path)],
        check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    ).stdout
    return plistlib.loads(output) if output else {}


def architectures(path):
    with path.open('rb') as stream:
        magic = stream.read(4)
        if magic in (b'\xcf\xfa\xed\xfe', b'\xce\xfa\xed\xfe'):
            return {struct.unpack('<I', stream.read(4))[0]}
        if magic in (b'\xfe\xed\xfa\xcf', b'\xfe\xed\xfa\xce'):
            return {struct.unpack('>I', stream.read(4))[0]}
        if magic in (b'\xca\xfe\xba\xbe', b'\xca\xfe\xba\xbf'):
            count = struct.unpack('>I', stream.read(4))[0]
            if count > 32:  # A Java class file has the same magic.
                return set()
            stride = 32 if magic[-1] == 0xbf else 20
            records = stream.read(count * stride)
            return {struct.unpack_from('>I', records, i * stride)[0] for i in range(count)}
    return set()


def main():
    app = Path(sys.argv[1]).resolve(strict=True)
    res = app / 'Contents/Resources'
    runtime = res / 'runtime'
    loader = runtime / 'dist/lib/wine/aarch64-unix/wine.app'
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    assert info['LSMinimumSystemVersion'] == '27.0'
    assert entitlements(loader).get('com.apple.developer.cross-architecture-support') is True
    assert (loader / 'Contents/embedded.provisionprofile').is_file()
    assert not entitlements(app).get('com.apple.security.app-sandbox', False)
    fex = list((runtime / 'dist').rglob('*fex*.dll'))
    assert any('wow64' in f.name.lower() for f in fex), '32-bit FEX translator missing'
    assert (runtime / 'dist/gstreamer/lib/gstreamer-1.0/libgstasf.dylib').is_file()
    host_files = []
    for path in app.rglob('*'):
        if path.is_symlink() or not path.is_file():
            continue
        archs = architectures(path)
        if not archs:
            continue
        assert 0x0100000c in archs, f'No ARM64 slice: {path}'
        rights = entitlements(path)
        assert not rights.get('com.apple.security.app-sandbox', False), f'Sandbox restricts networking: {path}'
        assert not rights.get('com.apple.security.device.audio-input', False), f'Unexpected microphone capability: {path}'
        host_files.append(str(path.relative_to(app)))
    assert architectures(app / 'Contents/MacOS/NTSD') == {0x0100000c}
    check('codesign', '--verify', '--deep', '--strict', str(app))
    print(json.dumps({'mach_o_files_with_arm64': len(host_files), 'intel_only_host_files': 0,
                      'app_sandbox': False, 'provisioned_loader': True, 'fex_dlls': len(fex)}, indent=2))


if __name__ == '__main__':
    main()
