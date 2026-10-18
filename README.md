# NTSD for macOS

NTSD 2.8.3.3 is packaged in two builds. Both are kept in each new release;
previous release downloads remain available.

| Download | Host runtime | Requirements |
| --- | --- | --- |
| `NTSD-2.8.3.3-FEX-macOS.dmg` | ARM64 Wine 11.18 + FEX, based on Hadron 0.3.1 | Apple Silicon, macOS 27+; no Rosetta |
| `NTSD-2.8.3.3-Rosetta-macOS.dmg` | Intel Wine 11.0_1 | macOS 11+; Rosetta on Apple Silicon |

[Download both builds](https://github.com/wowlocal/ntsd-2.8-wine/releases/tag/v2.8.3.3.6).
The FEX build has passed complete gameplay tests on this Mac. The Rosetta build
is retained as a fallback; its audio and display integration probes pass, but
controlled Rosetta runs hit a startup exception on this macOS 27 test host.
Use FEX on this Mac. Rosetta is retained for other macOS configurations;
this update does not claim completed Rosetta gameplay here. See [TESTING.md](TESTING.md).

FEX translates the original game's x86 instructions. This is a Rosetta-free
runtime, not a source port of the game engine. Steam, Hadron and Homebrew are
not required on the player's Mac.

## Playing

Open the DMG and copy **NTSD FEX** or **NTSD Rosetta** into Applications.
The apps have distinct names and Wine prefixes and can coexist. First launch
creates a writable game copy and private Wine environment. Custom controls,
recordings and extra game files are preserved.

- Player 1: WASD; J attack, K jump, L defend.
- Player 2: arrows; comma attack, period jump, slash defend.
- Battle menus: W/S select, J confirm. After selecting bots, W twice then J
  starts Fight from the default Randomize selection.
- Resize or zoom the game window; the view scales with black borders to preserve
  its aspect ratio. Mouse coordinates follow the scaled view.
- **⌘Return** toggles fullscreen and restores the window. F1 pauses local play.
- Hold Option when opening the app to open the game folder or reset Wine.

Startup checks native audio and Windows DirectSound in bounded helper processes.
If either fails or stalls, the game starts with clocked silent audio. A later
launch restores the prefix's previous audio configuration and checks it again.
The helpers use output only. Host audio settings and microphone permissions are
not changed; host executables use hardened runtime without an audio-input entitlement.

Both builds lack App Sandbox restrictions. Use Online Game to host/connect
(TCP 12345). macOS network permissions still apply. The wrapper does not change
the firewall or privacy protections.

## Building

FEX requires Apple Silicon and Xcode with the macOS 27 SDK. The Intel target
builds its universal launcher for macOS 11+. Python 3 is also required.

```sh
# FEX (default)
./build.sh ~/Downloads/NTSD2.8.3.3.zip
# Retained Intel Wine / Rosetta target
NTSD_RUNTIME=intel ./build.sh ~/Downloads/NTSD2.8.3.3.zip
# Both, in independent build/fex and build/rosetta directories
NTSD_RUNTIME=both ./build.sh ~/Downloads/NTSD2.8.3.3.zip
```

Single-target outputs are `build/NTSD FEX.app` or `build/NTSD Rosetta.app` and
the matching named DMG. `NO_DMG=1` skips the image. `NTSD_RUNTIME=fex|rosetta`
are aliases for `arm64|intel` in build.sh.

Downloads and source revisions are pinned. The shared display DLL, MinHook,
DirectSound fallback and audio helpers build for both targets; the Intel build
does not build or depend on FEX. `NTSD_BUILD_DIR`, `NTSD_CACHE_DIR`,
`NTSD_BUILD_JOBS` (default 2) and `NTSD_LLVM_MINGW` select output/cache/toolchain
locations. CMake/Ninja are installed into a build-only Python environment when
needed. Build caches and generated binaries are excluded from Git.

## Diagnostics

Support files live in `~/Library/Application Support/NTSD`:

| Build | Game files | Wine prefix | Launcher log |
| --- | --- | --- | --- |
| FEX | `Game-arm64` | `Prefix-arm64` | `Logs/NTSD.log` |
| Rosetta | `Game` | `Prefix` | `Logs/Rosetta.log` |

On upgrade, FEX seeds its separate game directory from the previous `Game`
copy. Its runtime logs/cache remain under `ARM64`. Each runtime refreshes only
its own writable game directory.

`NTSD_SUPPORT_DIR` selects an absolute test directory. FEX's `--prepare-only`
performs setup without gameplay. `NTSD_WINEDEBUG` enables Wine tracing;
`NTSD_AUDIO=silent` forces the fallback, and `auto`/`system` attempt system
output with failure recovery.

```sh
python3 tools/verify_bundle.py 'build/NTSD FEX.app'
python3 tools/verify_intel_bundle.py 'build/NTSD Rosetta.app'
```

See [TESTING.md](TESTING.md), [frame-time measurements](docs/PERFORMANCE.md),
and [ARM64 compatibility fixes](docs/ARM64_CRASH_FIX.md).

## Signing and releases

```sh
# Builds, signs, notarizes and staples both targets by default
./release.sh ~/Downloads/NTSD2.8.3.3.zip
# Publishes both named DMGs, checksums and corresponding sources in one prerelease
./release.sh ~/Downloads/NTSD2.8.3.3.zip --publish
```

`NTSD_RUNTIME=arm64|intel` selects a single release target.
`NTSD_REUSE_BUILD=1` finalizes an already tested, signed app in the selected
output directory; its architecture, entitlements and signatures are rechecked. The installed
Developer ID identity and Keychain profile **codex-notary** are used. Both app
and DMG must pass stapling validation and Gatekeeper's **Notarized Developer ID**
assessment. Checksums are generated after stapling.

Hadron's provisioned Wine loader keeps its vendor signature and provisioning
profile. Do not sign it with `codesign --deep`. Component licenses, source pins,
and downstream patches accompany the app; corresponding DSOAL/OpenAL and
MinHook sources and build helpers accompany the release.
