# ARM64 validation — 2026-10-18

**Playable ARM64 preview: NTSD 2.8.3.3, wrapper 2.8.3.3.4.**
Tested on Apple Silicon (M4 Pro), macOS 27.0.1 (26A434).
The original game's x86 code runs through FEX in an ARM64 Wine host.

## Gameplay

- A local Naruto-versus-Sasuke match completed to the win/loss scoreboard
  (38 seconds), followed by return to setup and another match.
- Player movement, jumping and attacks were exercised. Local pause and the
  game's fullscreen toggle **⌘Return** worked, including return to windowed mode.
- A fresh support directory was prepared with the signed release app. It reached
  the menu with normal system audio selected. Sampling the game reports
  `Code Type: ARM64` and active Wine CoreAudio code.
- Two fresh, isolated prefixes ran the **signed release build** simultaneously.
  The original game's host/listen and peer/connect paths established TCP 12345
  on the game-advertised interface of this Mac. Character selection, movement,
  attacks, health and knockback synchronized in both directions.
- The network match completed at **03:57** with matching scoreboards in both
  windows: P1 lost (90 damage, 510 HP lost); P5 won (510 damage, 90 HP lost).
  Both then remained responsive at the results screen.

This is a same-Mac, two-process multiplayer test. A separate Mac, a remote
Internet connection, every fighter/move and every game mode were not tested.
The macOS green-button fullscreen mode scales this legacy window incorrectly;
use the game's **⌘Return** shortcut.

## Runtime checks

- All **131** host Mach-O files contain ARM64 code. No Intel-only host file;
  the launcher is ARM64-only. Rosetta was not uninstalled from the test Mac;
  binary checks and native process samples establish this execution path.
- All host binaries lack the App Sandbox entitlement. No system firewall,
  privacy protection or host audio-driver configuration was disabled.
- The original Hadron Wine loader retains its Developer ID signature, restricted
  cross-architecture entitlement and embedded provisioning profile.
- Fresh Wine-prefix setup, game copying and setup stamping pass. The retained
  Intel prefix and user-controlled game files are separate from the ARM64 prefix.
- The signed bundle's 32-bit Winsock probe passes DNS, outbound TCP/UDP echo and
  inbound TCP, with ARM64 process sampling. This transport check is additional
  to the original-game multiplayer match above.
- The rebuilt FEX translator passes **38 integer-division cases**, including
  **17 expected exceptions**, fault PC/register/carry preservation and valid
  signed/unsigned boundaries: `integer divide cases=38 caught=17 failures=0`.
- Executable-memory checks pass: unflushed and inline self-modification,
  guest-visible protections, merged/split queries, a real read-only write fault
  and executable copy-on-write mappings: `memory probe complete failures=0`.
- The rebuilt DSOAL/OpenAL null backend passes DirectSound creation, cooperative
  level, PCM-buffer creation/locking/play/stop. Test it with the same
  `WINEDLLOVERRIDES=dsound=n` and `ALSOFT_DRIVERS=null` startup environment used
  by the silent-mode launcher; Wine's default DLL choice is a different path.
- The signed app switched from system audio to silent mode and back to automatic
  system output in the same prefix; both launches reached the menu.
- Silent DirectShow rendering preserves music-graph timing. Normal audio was
  used by both signed network-game instances. Audible quality/volume was not
  measured. The native audio probe has an eight-second process deadline.
- Shell syntax, clean downstream patch application, source builds, compiler
  checks and deep/strict code-signature validation pass.

## Distribution

Developer ID: `Misha Kharytonchyk (H8QG3CBM96)`.

- App notarization **Accepted**: `58d298c5-bf48-4318-9671-334c3b4be468`.
- DMG notarization **Accepted**: `ed7fa727-9bcc-4af9-985d-1f81688b14d0`.
- App and DMG stapling validation and deep/strict signatures pass. Gatekeeper
  reports **accepted**, source **Notarized Developer ID**, for both.
- The final DMG was mounted read-only. Its app passes the same bundle checks and
  stapling validation; its CDHash matches the tested signed app. The original
  game executable's SHA-256 is unchanged.
- Post-stapling DMG SHA-256:
  `8674d17caa6b8a751da66b4e65b56d8745ceb64bb34a66eb2d98d564fe88ffe8`.
- The release also includes the corresponding DSOAL/OpenAL sources, downstream
  patches, build helpers and component licences.

## Reproduction and inputs

```sh
python3 tools/verify_bundle.py /path/to/NTSD.app
NTSD_SUPPORT_DIR=/absolute/test-support /path/to/NTSD.app/Contents/MacOS/NTSD --prepare-only
python3 tools/check_network.py /path/to/NTSD.app /path/to/i686-w64-mingw32-clang /absolute/test-support /absolute/test-output
```

`tools/windows_divide_probe.c`, `tools/windows_memory_probe.c` and
`tools/windows_audio_probe.c` are standalone i686 Windows probes. Run them via
Hadron's bundled `scripts/play` with the prepared private prefix and FEX mtrack
mode. The audio probe requires its rebuilt audio DLLs beside it and the startup
variables described above.

- Game ZIP SHA-256:
  `fca38bfe1391d969b9d29d1289c51bbf5270a384fa7da6d4a7c053da77c52b2d`.
- Unchanged NTSD.exe SHA-256:
  `5eda51440039099069d041e5bd13fde8be9fd8c7b20983985b1712a59719d86b`.
- Hadron 0.3.1 DMG SHA-256:
  `c2b1ac78b0151bb634b4a3eced8e305bddbd410d1d1e4dda99b36a9c96998192`.
- FEX: `741e146fdf5a89517e1a67e3c899907cfba6131a`, five Hadron macOS patches
  and three downstream CPU patches; vendor ARM64EC translator retained.
- DSOAL: `e11128250439d586483ee6598d1670ab52ab5e37` plus silent-mode patch.
- OpenAL Soft: `a70d4116118cdf6bc7ac58fe6ae7a805c7205c50` plus the optional
  HRTF build guard; LLVM-mingw 20260922.

Local build logs, probes, process samples, fresh prefixes and notarization
receipts are under `/Volumes/NTSD-Builds/tasks/ntsd28-arm64-20261018/`.
Previous failed prototype artifacts are retained separately; their notarization
receipts do not serve as validation for this playable release.
