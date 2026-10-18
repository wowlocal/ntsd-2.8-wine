#!/usr/bin/env python3
"""Copy the minimal part of the GStreamer macOS runtime that winegstreamer needs.

usage: gst_subset.py <expanded GStreamer root (…/Versions/1.0)> <destination>

Wine plays the game's music through DirectShow -> winegstreamer, which
builds a decodebin pipeline. We copy those plugins plus every dylib they pull
in through @rpath, keeping the lib/ + lib/gstreamer-1.0/ + libexec/ layout so
the runtime's own @loader_path rpaths keep working.
"""
import shutil
import subprocess
import sys
from pathlib import Path

# Libraries winegstreamer.so links against directly.
BASE_LIBS = [
    "libgstreamer-1.0.0.dylib",
    "libgstbase-1.0.0.dylib",
    "libgstaudio-1.0.0.dylib",
    "libgstvideo-1.0.0.dylib",
    "libgsttag-1.0.0.dylib",
    "libgobject-2.0.0.dylib",
    "libglib-2.0.0.dylib",
]

# Elements winegstreamer creates (decodebin, audioconvert, …) plus what
# decodebin needs for the game's music: it is WMA in ASF containers
# (asf + libav), with mp3/wav covered as well.
PLUGINS = [
    "coreelements", "typefindfunctions", "playback", "app",
    "audioconvert", "audioresample", "volume", "level",
    "asf", "libav", "id3demux", "audioparsers", "mpg123", "wavparse",
    "videoconvertscale", "videofilter", "deinterlace",
]


def rpath_deps(path: Path) -> list[str]:
    out = subprocess.run(["otool", "-L", str(path)], capture_output=True, text=True, check=True).stdout
    deps = []
    for line in out.splitlines()[1:]:
        name = line.strip().split(" (")[0]
        # The first entry of a dylib is its own install name; skip it.
        if name.startswith("@rpath/") and name[len("@rpath/"):] != path.name:
            deps.append(name[len("@rpath/"):])
    return deps


def main() -> None:
    src, dst = Path(sys.argv[1]), Path(sys.argv[2])
    todo = [Path("lib") / name for name in BASE_LIBS]
    todo += [Path("lib/gstreamer-1.0") / f"libgst{p}.dylib" for p in PLUGINS]
    todo.append(Path("libexec/gstreamer-1.0/gst-plugin-scanner"))

    done = set()
    while todo:
        rel = todo.pop()
        if rel in done:
            continue
        done.add(rel)
        source = src / rel
        if not source.exists():
            sys.exit(f"missing in GStreamer runtime: {rel}")
        target = dst / rel
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source.resolve(), target)
        for dep in rpath_deps(source):
            todo.append(Path("lib") / dep)

    print(f"copied {len(done)} files")


if __name__ == "__main__":
    main()
