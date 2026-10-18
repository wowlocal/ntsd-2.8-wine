#!/usr/bin/env python3
"""Package corresponding audio-library sources without caches or credentials."""
import hashlib
import io
from pathlib import Path
import re
import subprocess
import sys
import tarfile

root = Path(__file__).resolve().parents[1]
cache = Path(sys.argv[1]).resolve(strict=True)
output = Path(sys.argv[2]).resolve()
source_file = cache / 'ntsd-runtime-fixes/SOURCES.txt'
if not source_file.exists():
    source_file = cache / 'ntsd-runtime-fixes/WINDOWS-SOURCES.txt'
sources = source_file.read_text()
dsoal_commit = re.search(r'^DSOAL ([0-9a-f]{40})', sources, re.M).group(1)
openal_commit = re.search(r'^OpenAL Soft ([0-9a-f]{40})', sources, re.M).group(1)
key = hashlib.sha256((root / 'patches/dsoal-silent-fallback.patch').read_bytes()).hexdigest()[:16]
trees = {
    'DSOAL': (cache / f'dsoal-{dsoal_commit}-{key}', dsoal_commit),
    'OpenAL-Soft': (cache / f'openal-{openal_commit}', openal_commit),
}
prefix = 'NTSD-runtime-sources'


def metadata(member):
    member.uid = member.gid = 0
    member.uname = member.gname = ''
    member.mtime = 0
    return member


def add_text(archive, name, text):
    data = text.encode()
    member = tarfile.TarInfo(f'{prefix}/{name}')
    member.size = len(data)
    member.mode = 0o644
    archive.addfile(metadata(member), io.BytesIO(data))


output.parent.mkdir(parents=True, exist_ok=True)
temporary = output.with_suffix(output.suffix + '.part')
with tarfile.open(temporary, 'w:xz') as archive:
    for name, (tree, commit) in trees.items():
        actual = subprocess.check_output(['git', '-C', str(tree), 'rev-parse', 'HEAD'], text=True).strip()
        if actual != commit:
            raise SystemExit(f'Unexpected source revision: {tree}')
        data = subprocess.check_output(['git', '-C', str(tree), 'archive', '--format=tar', commit])
        # Copy tar members directly; no upstream path is extracted onto the host.
        with tarfile.open(fileobj=io.BytesIO(data), mode='r:') as upstream:
            for member in upstream:
                path = Path(member.name)
                if path.is_absolute() or '..' in path.parts:
                    raise SystemExit('Unsafe source archive path')
                stream = upstream.extractfile(member) if member.isfile() else None
                member.name = f'{prefix}/{name}/{member.name}'
                archive.addfile(metadata(member), stream)
    for name in ['patches', 'launcher', 'tools/build-runtime-fixes.sh',
                 'tools/package_runtime_sources.py', 'tools/build-windows-support.sh',
                 'tools/runtime-build-common.sh', 'vendor/minhook']:
        archive.add(root / name, arcname=f'{prefix}/{name}', filter=metadata)
    if (cache / 'ntsd-runtime-fixes/FEX-LICENSE').exists():
        archive.add(cache / 'ntsd-runtime-fixes/FEX-LICENSE',
                    arcname=f'{prefix}/FEX-LICENSE', filter=metadata)
    add_text(archive, 'SOURCES.txt', sources)
    add_text(archive, 'README.txt',
             'Complete upstream DSOAL and OpenAL Soft sources, downstream patches and build helpers.\n\n'
             'Apply patches/dsoal-silent-fallback.patch to DSOAL and '
             'patches/openal-no-embedded-hrtf.patch to OpenAL-Soft.\n'
             'tools/build-runtime-fixes.sh records the pinned compiler, source commits and flags. '
             'It also rebuilds the MIT-licensed FEX WoW64 translator from its pinned public '
             'source with the included patches.\n\n'
             'Full wrapper: https://github.com/wowlocal/ntsd-2.8-wine\n'
             'No game archive, Wine prefix or signing credentials are included.\n')
temporary.replace(output)
print(output)
