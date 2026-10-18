# Dual-runtime update validation — 18–19 October 2026

Wrapper **2.8.3.3.6**, Apple M4 Pro / 24 GB / macOS 27.0.1 (26A434).
FEX uses native ARM64 Wine 11.18 and the existing patched FEX translator;
Rosetta retains Intel Wine 11.0_1. The Windows game executable is unchanged.

## New gameplay and startup checks

- Signed FEX app: normal native HAL and Windows DirectSound output probes all
  return success. The app reaches the menu and starts a match.
- A local two-human Wharf scene ran for several minutes. Movement, jump,
  attack input and fullscreen entry/exit were exercised. Fullscreen covered
  6016×3384 and restored the 1333×730 client.
- An earlier signed candidate completed a Sakura-versus-Sasuke AI match to the scoreboard at
  **00:35**: P1 lost (30 damage, 510 HP lost); computer won (510 damage,
  30 HP lost). This tests actual combat and match completion with the display
  DLL enabled.
- The final display correction completed a Naruto-versus-Sasuke AI match at
  **00:38**: P1 lost (0 damage, 550 HP lost); computer won (550 damage,
  0 HP lost). The signed revision 6 artifact then passed an upgrade launch
  and a fullscreen round trip with its complete menu restored.
- A separately signed test copy replaces only audio-probe.exe with a 60-second
  sleeping executable. The native HAL probe passes, the Windows helper times
  out after **8.0 seconds**, silent configuration succeeds, and the original
  game reaches its menu. This verifies the Wine-specific timeout recovery.
  Restoring the real probe in that same prefix then passes DirectSound and
  starts the game with normal system output again.
- tests/audio-timeout.m also verifies successful child exit and bounded
  termination: a 30-second child returns timeout status 124 in about 0.23 seconds
  with a 0.15-second test deadline.
- A fresh Rosetta prefix passes native HAL and Windows DirectSound creation,
  buffer and playback probes. Its host process samples as X86-64 (translated).
  GUI automation times out with both Retina settings and a separate Wine app
  identity. Its process sample spends substantial main-thread time in macOS
  image/color conversion; this observation does not establish the cause.
  Later controlled traces exposed a startup stack overflow/page fault after
  the first full-window copy. This also occurs with the scaling DLL removed
  and with system audio restored. The software DirectSound fallback separately
  exercises create/cooperative-level/buffer/lock/play/stop under Intel Wine
  and exits successfully.
  **Rosetta gameplay fails on this test host; no paired gameplay performance
  result is claimed.** See the [recorded failed baseline](docs/PERFORMANCE.md).

The final window-message correction also passed a native green-button fullscreen
round trip, macOS left-half tiling to a 3008×3198 window, a click on Start in the
scaled view, and restoration to the original window size with the complete mode
selection view visible. Native geometry notifications update Wine's physical
client while the engine keeps its logical buffers.

## Shared display integration probe

`tests/display-test.c` creates and controls its own test window and checks the
packaged display DLL under each Wine runtime. It passes for **both FEX and
Rosetta**:

- Original canvas 800×438; real client resized to 1000×800.
- Aspect-fit viewport 1000×548, centered at y=126; border pixel is black and
  the interior pixel retains the test color.
- Game-visible frame dimensions stay fixed while the system sees the new size.
- Mouse position (500,400) maps to logical (400,219).
- Fullscreen client is 6016×3384; returning restores 1000×800.
- Both processes exit 0. The test sends messages only to its own window.

Compile with i686-w64-mingw32-clang, linking ddraw, gdi32 and user32. Put the
built ddraw.dll beside the test EXE and run through the target runtime with
`WINEDLLOVERRIDES=ddraw=n,b`. This is an integration check, not a substitute for
original-game gameplay testing. For the native timeout test:

```sh
xcrun clang -fobjc-arc -O2 -Wall -framework Foundation tests/audio-timeout.m -o /tmp/ntsd-audio-timeout-test
/tmp/ntsd-audio-timeout-test
```

## Packaging scope

Both build targets package the same display/audio support and have independent
app names, game directories and Wine prefixes. Mach-O verification rejects App
Sandbox and microphone-input entitlements. Intel host binaries require hardened
runtime. FEX retains the provisioned vendor loader signature. No firewall,
privacy protection or host audio driver was disabled.

Both final runtime bundles also pass fresh 32-bit Winsock probes for DNS,
outbound TCP/UDP echo and inbound TCP. Process samples verify native ARM64 for
FEX and X86-64 translation for the Intel target. These transport probes do not
replace original-game multiplayer acceptance.

The complete original-game network match and CPU exception regressions below
were performed on wrapper 2.8.3.3.4. They are retained as prior evidence, rather
than presented as rerun gameplay tests for this update. New frame measurements
and their limitations are in [docs/PERFORMANCE.md](docs/PERFORMANCE.md).

## Revision 6 distribution validation

Both apps and DMGs are Developer ID signed, notarized **Accepted**, stapled,
and pass deep/strict signature and stapling validation. Gatekeeper reports
**accepted**, source **Notarized Developer ID**, for all four artifacts.

| Build | App notarization ID | DMG notarization ID |
| --- | --- | --- |
| FEX | `e569b8ba-7ade-4d2d-be7c-82c06ebba93e` | `e81fbd46-49b8-432a-8b2d-c54ca423d8be` |
| Rosetta | `0340b785-992d-41ae-bf1f-488b6f3d5bc0` | `eeeac3d6-0d7a-41e6-822d-396c2c5fd832` |

Each final disk image was mounted read-only. Its app matches the signed source
CDHash, contains no test environment override, and preserves NTSD.exe SHA-256
`5eda51440039099069d041e5bd13fde8be9fd8c7b20983985b1712a59719d86b`.
The FEX image verifies 131 ARM64-capable host files with no Intel-only host;
the Rosetta image verifies 119 hardened host files and a universal launcher.

Post-stapling DMG SHA-256:

- FEX: `4e0fd356c66a9155b86ed46578f617fa76e06c31d8b43f8d0ac162c25dcbcdea`.
- Rosetta: `702cbe9a3a89f95f281d9eded43ce1bc977b801748d2b5b4941795a314ed0fea`.

The [combined prerelease v2.8.3.3.6](https://github.com/wowlocal/ntsd-2.8-wine/releases/tag/v2.8.3.3.6)
contains both DMGs, their checksums, and the corresponding runtime source archive
and checksum. All six uploaded GitHub asset digests match their local files.
Previous v2.8.3.3.2 and v2.8.3.3.4 downloads remain intact; the former remains
GitHub's latest stable release.

`/Applications/NTSD FEX.app` also passes strict signature, stapling and Gatekeeper
checks. Its installed runtime reaches the menu, and a fresh process sample
reports **Code Type: ARM64** with its actual host path inside Applications.

Notarization validates distribution signatures; the Rosetta gameplay failure
on this host remains recorded above. Earlier private revision 5 candidates are
not the published artifacts and their receipts are not used for revision 6.

---

# Previous release: ARM64 validation — 2026-10-18

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
