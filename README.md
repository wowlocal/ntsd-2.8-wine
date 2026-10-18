# NTSD for macOS

A playable **Rosetta-free ARM64 preview** of NTSD 2.8.3.3 for **Apple Silicon,
macOS 27 or later**. Download the signed, notarized app from
[the ARM64 release](https://github.com/wowlocal/ntsd-2.8-wine/releases/tag/v2.8.3.3.4).

The host runtime is ARM64 Wine/FEX, based on Hadron 0.3.1 with downstream CPU
compatibility fixes. FEX translates the original Windows game's x86 code;
this is not a source port of the engine. Steam, Hadron, Homebrew and Rosetta
are not required on the player's Mac. See [TESTING.md](TESTING.md) for scope
and [the compatibility notes](docs/ARM64_CRASH_FIX.md) for the fixes.

## Playing

Open the DMG, copy NTSD to Applications, then open it. First launch copies the
game and creates a private ARM64 Wine prefix. Existing custom controls,
recordings and extra game files are preserved.

- Player 1: WASD; J attack, K jump, L defend.
- Player 2 on the same keyboard: arrows; comma attack, period jump, slash defend.
- Battle menus: W/S select, J confirm. After choosing bots, the menu initially
  selects Randomize; press W twice, then J, to start Fight.
- Fullscreen: **⌘Return**. F1 pauses during local play.
- Hold Option while opening the app for the game folder and Wine reset actions.

Use the game's fullscreen shortcut. The macOS green-button fullscreen mode
currently scales this legacy game's window incorrectly.

Audio uses Wine's normal system output. If the native audio service does not
respond to the bounded startup probe, the launcher selects silent software audio
so play can continue. It restores the prefix's previous audio setting when
returning to normal output; no host audio settings are changed.

The launcher and bundled host binaries have **no App Sandbox entitlement**.
Multiplayer is enabled. Use Online Game to host or connect to the address shown
by the host. The game uses TCP port 12345. macOS network permissions still apply;
the wrapper does not disable the firewall or privacy protections.

## Building

Requires Xcode with the macOS 27 SDK and Python 3:

```sh
./build.sh ~/Downloads/NTSD2.8.3.3.zip
```

The build verifies Hadron's download digest, downloads the pinned LLVM-mingw
compiler, and rebuilds the patched FEX and audio libraries from pinned sources.
CMake/Ninja are installed in a build-only Python environment when unavailable.
Build caches and generated files are excluded from Git.

Outputs are `build/NTSD.app` and
`build/NTSD-2.8.3.3-arm64-experimental-macOS.dmg` (`NO_DMG=1` skips the image).
Use `NTSD_BUILD_DIR` and `NTSD_CACHE_DIR` for another build volume.
`NTSD_BUILD_JOBS` controls compilation parallelism (default 2).
`NTSD_LLVM_MINGW` can name an existing LLVM-mingw 20260922 toolchain.
`NTSD_RUNTIME=intel` explicitly selects the retained legacy Intel build.

## Diagnostics

The default support directory is `~/Library/Application Support/NTSD`:
`Game`, `Prefix-arm64`, `Logs/NTSD.log`, and `ARM64/logs` / `ARM64/cache`.
The previous Intel `Prefix` is retained separately.

For isolated tests, set `NTSD_SUPPORT_DIR` to an absolute directory when running
`NTSD.app/Contents/MacOS/NTSD`. `--prepare-only` performs setup without gameplay.
`NTSD_WINEDEBUG` enables Wine logging; `NTSD_AUDIO=auto|silent|system` selects
the audio mode (default auto).

```sh
python3 tools/verify_bundle.py build/NTSD.app
```

This checks ARM64 host code, signatures, the provisioned loader, FEX, GStreamer
ASF support, minimum OS and absence of App Sandbox. Component and gameplay test
procedures are in `TESTING.md`.

## Signing and releases

```sh
./release.sh ~/Downloads/NTSD2.8.3.3.zip
```

Uses the installed Developer ID identity and Keychain profile `codex-notary`.
It notarizes and staples the app and DMG, validates both, requires Gatekeeper's
`Notarized Developer ID` assessment, and computes the DMG checksum after stapling.
`--publish` additionally creates a GitHub prerelease for ARM64.

Hadron's restricted Wine loader keeps its original signature and provisioning
profile. Only the rebuilt native helper, FEX companion, audio probe and outer app
are signed with the wrapper's identity. Do not use `codesign --deep` to sign it.
Component licences, source pins and downstream patches accompany the app;
the release also provides the modified audio libraries' corresponding source.
