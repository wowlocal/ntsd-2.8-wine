# NTSD for macOS

The ARM64 Wine/FEX build is **experimental**: the bundle and networking checks
pass, but NTSD 2.8.3.3 currently fails during startup. See [TESTING.md](TESTING.md).
The established Intel build remains the default; it requires Rosetta on Apple
Silicon. Select `NTSD_RUNTIME=arm64` explicitly to build without Rosetta.

The ARM64 target builds a self-contained `NTSD.app` for **Apple Silicon and macOS 27 or later**.
The host runtime is native ARM64 Wine with FEX, from
[Hadron 0.3.1](https://github.com/Broyojo/hadron/releases/tag/v0.3.1).
It does not install or use Rosetta. The original Windows game's x86 instructions
are translated by FEX; this is not a native source port of the game engine.

## Build

```sh
NTSD_RUNTIME=arm64 ./build.sh ~/Downloads/NTSD2.8.3.3.zip
```

Requires Xcode Command Line Tools and Python 3. Hadron is downloaded from its
release and checked against a pinned SHA-256. Wine, FEX, graphics libraries,
GStreamer and component licences are bundled; Hadron, Steam and Homebrew do not
need to be installed on the player's Mac.

Outputs:

- `build/NTSD.app`
- `build/NTSD-2.8.3.3-arm64-experimental-macOS.dmg` (`NO_DMG=1` skips the image)

Use `NTSD_BUILD_DIR` and `NTSD_CACHE_DIR` for build outputs and downloads on
another volume. Temporary staging stays inside the build directory. For example:

```sh
NTSD_BUILD_DIR=/Volumes/NTSD-Builds/tasks/ntsd-arm64/build \
NTSD_CACHE_DIR=/Volumes/NTSD-Builds/tasks/ntsd-arm64/cache \
NTSD_RUNTIME=arm64 \
./build.sh ~/Downloads/NTSD2.8.3.3.zip
```

## Running

First launch copies the game to `~/Library/Application Support/NTSD/Game` and
creates a fresh `Prefix-arm64`. The previous Intel `Prefix` is left in place.
Existing custom controls and extra game files are preserved. Player 1 defaults
to WASD + J/K/L; player 2 uses arrows + `,` `.` `/`.

Hold Option while opening the app to open the game folder or reset ARM64 Wine.
The main log is `~/Library/Application Support/NTSD/Logs/NTSD.log`; runtime and
memory-watchdog logs are in `NTSD/ARM64/logs`. GStreamer caches stay under
`NTSD/ARM64/cache`.

The launcher and Wine runtime have **no App Sandbox entitlement**. TCP/UDP
networking and multiplayer are not disabled by the wrapper. macOS Local Network
and firewall permissions, when requested, still apply. This does not by itself
establish compatibility with an Internet server or another player's game.

For isolated verification, `NTSD_SUPPORT_DIR` names an absolute alternative
support directory. `NTSD_WINEDEBUG` enables Wine diagnostics. The launcher's
`--prepare-only` option performs first-run setup without opening the game.

## Signing and notarization

```sh
NTSD_RUNTIME=arm64 ./release.sh ~/Downloads/NTSD2.8.3.3.zip
```

Uses the installed Developer ID Application identity and the Keychain profile
`codex-notary`. Override with `CODESIGN_IDENTITY` / `NOTARY_KEYCHAIN_PROFILE`.
It notarizes and staples the app and DMG, checks Gatekeeper for
`Notarized Developer ID`, and writes the DMG's SHA-256 **after** stapling.
`--publish` additionally creates a GitHub Release (a prerelease for ARM64) with
the DMG and checksum. The ARM64 prototype is not a
playable release; notarization verifies distribution signatures, not compatibility.

Hadron's Wine loader retains its original signature and embedded provisioning
profile for Apple's cross-architecture entitlement. Do not sign the runtime with
`codesign --deep`, strip it, or change loader paths with `install_name_tool`.
The build signs the outer NTSD app separately. All runtime machine code and
component licences are retained. The recorded shell-script patch relocates
logs/caches and adds Local Network usage text to the generated game bundle.

Verify a built bundle with:

```sh
python3 tools/verify_bundle.py build/NTSD.app
```

This checks every Mach-O for an ARM64 slice, the provisioned loader, FEX,
GStreamer ASF support, signatures, minimum OS and absence of App Sandbox.
Runtime test results are recorded in `TESTING.md`. Use `NTSD_RUNTIME=intel` (or
omit it) for the previous universal launcher and Intel Wine runtime; its original
launcher, metadata and notices are retained in `launcher/intel-*`.
