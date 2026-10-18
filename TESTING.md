# ARM64 compatibility results — 2026-10-18

**Status: experimental; NTSD 2.8.3.3 does not yet start successfully.**
The native runtime and transport checks pass. This is not a playable ARM64
release or a completed native engine port. The established Intel target remains
`build.sh`'s default. `NTSD_RUNTIME=arm64` explicitly selects the experimental
target and has no Rosetta fallback.

Test host: Apple Silicon, macOS 27.0.1 (26A434).

## Inputs

- NTSD distribution: `NTSD2.8.3.3.zip`, SHA-256
  `fca38bfe1391d969b9d29d1289c51bbf5270a384fa7da6d4a7c053da77c52b2d`.
- Hadron 0.3.1: release commit
  `3f5f18e2c08e22eb539f1fbbee52d4ba3d9e05c4`, DMG SHA-256
  `c2b1ac78b0151bb634b4a3eced8e305bddbd410d1d1e4dda99b36a9c96998192`.
- Bundled Wine identifies as 11.18. Hadron's FEX pin is
  `0df84d3844bcdb87bb7d3f5b8fb0959cd009c038` (2026-09-28).
- A diagnostic build of FEX's WoW64 translator and macOS helper from upstream
  `741e146fdf5a89517e1a67e3c899907cfba6131a` (2026-10-18), with Hadron's five
  existing macOS patches, was also tested. It is not bundled in the ARM64 target.
  The fresh prefix's `xtajit.dll` hash matches the newly built translator.

The game executable is unchanged (SHA-256
`5eda51440039099069d041e5bd13fde8be9fd8c7b20983985b1712a59719d86b`).
Only the previously established default key
patch in `data/control.txt` is applied during packaging.

## Checks that passed

- Shell and Python syntax checks, clean patch application and plist validation.
- All 129 bundled host Mach-O files have ARM64 slices; no Intel-only host code.
  The launcher itself is ARM64-only.
- The original Wine loader retains its signature, restricted cross-architecture
  entitlement and embedded provisioning profile. FEX's WoW64 and ARM64EC DLLs
  and the native GStreamer ASF plugin are present.
- Deep/strict code-signature verification on the built app.
- First-run setup in an isolated directory: a fresh ARM64 prefix, ARM64
  `system32/ntdll.dll`, game copy and setup stamp were created successfully.
- An Intel-to-ARM64 setup exercise preserved custom key bindings, extra game
  files, the previous setup marker and a sentinel in the old Intel prefix.
- The retained legacy launcher compiles for both x86_64 and ARM64; its source
  is byte-identical to the previous launcher. Legacy runtime downloads were not
  repeated in this ARM64 investigation.
- A separately compiled **32-bit Windows** Winsock probe ran in the bundled
  Wine/FEX runtime: localhost DNS, outbound TCP echo, outbound UDP echo, and a
  guest TCP listener accepting a connection from the host all passed. Traffic
  was over loopback; this is a transport check, not an inter-Mac game match.
- Sampling the actual probe process reports `Code Type: ARM64`. Rosetta was not
  uninstalled from the Mac; process and binary checks establish this execution
  path without changing the user's existing software.
- No bundled host binary has `com.apple.security.app-sandbox` enabled.
  App Sandbox is not blocking sockets. Local Network usage descriptions are
  supplied for the launcher and generated game bundle. No system firewall or
  privacy protections were disabled.

Reproduce bundle and socket checks (the second command requires an i686 Windows
cross-compiler and a support directory initialized with `--prepare-only`):

```sh
python3 tools/verify_bundle.py /path/to/NTSD.app
python3 tools/check_network.py /path/to/NTSD.app /path/to/i686-w64-mingw32-clang /path/to/test-support /path/to/test-output
```

`NTSD_SUPPORT_DIR=/absolute/test-support NTSD.app/Contents/MacOS/NTSD --prepare-only`
prepares an isolated prefix. Test output and compiler caches should be kept on
the designated external build volume.

## NTSD startup failure

The bundled FEX default and a build with the current upstream FEX both report:

```text
wine: Unhandled page fault on read access to E4AFC2E8 at address 0085D843 (thread 0024), starting debugger...
```

The same failure occurs in the standalone runtime and the assembled NTSD app.
Limiting the large-address-aware setting did not resolve it. Diagnostic runs
using full code validation, disabled multiblock compilation and one instruction
per block exited without reaching a usable game; these are not shipped as fixes.
The precise compatibility defect has not been established.

A separate diagnostic launcher also tested macOS's 4 KB page spawn API with the
original provisioned loader. After correcting the helper's DYLD environment
forwarding, prefix setup completed, but NTSD exited with status 128 during
startup. The helper is not included in the delivered runtime. Its earlier
font-library dependency failure and the corrected run are retained separately.
A further run with FEX's small-counter scaling disabled also exited during
startup (status 136); it is not a shipped workaround.

Full matches, keyboard behavior in a match, fullscreen, actual game sound/music
and game-level LAN/Internet multiplayer remain **unverified because startup
fails**. Passing socket checks or Apple notarization does not close those gates.

## Signed package verification

- App notarization: **Accepted**, submission
  `841224a7-97e0-4a95-8e45-8a8e171fd34b`.
- DMG notarization: **Accepted**, submission
  `5c1c7885-c8c0-44d2-bc84-6ecac272ce8f`.
- App and DMG stapling/validation and deep/strict signature checks passed.
  Gatekeeper reports **accepted**, source **Notarized Developer ID**, for both.
- The final DMG was mounted read-only and its app is byte-identical to the
  signed, stapled app. The checksum file was generated after stapling and checked.
- The Winsock probe passed again using the signed, notarized app; its generated
  game bundle contains the Local Network usage description. Native ARM64 process
  sampling passed again.
- The signed, notarized app also reproduces the same NTSD startup access
  violation (observed after 41.16 seconds). It remains an experimental artifact;
  no playable ARM64 release is claimed.

Artifact: `NTSD-2.8.3.3-arm64-experimental-macOS.dmg`, SHA-256
`a1a69e50c92b7bb7835cdbaf105f984b51241a7960365d64303869b260de348f`.
It and its checksum are in the local evidence directory's `release/` folder.
No GitHub binary release was published during this investigation.

## Local evidence

Build logs, failed runs, upstream-source build logs, native process samples,
network results, isolated prefixes and notarization receipts are retained under
`/Volumes/NTSD-Builds/tasks/ntsd28-arm64-20261018/`. Build/download artifacts are
on the T7-backed APFS volume. No game archive, runtime payload, prefix, password
or signing credential is committed to this repository.
