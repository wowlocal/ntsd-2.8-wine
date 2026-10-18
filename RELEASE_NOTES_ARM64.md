# NTSD 2.8.3.3.7 — Rosetta-free FEX preview

Apple Silicon, macOS 27+. Download **NTSD-2.8.3.3-FEX-macOS.dmg**, copy
**NTSD FEX.app** to Applications and open it. The app and DMG are Developer ID
signed, notarized and stapled.

The game view now scales with window resizing/zoom while preserving aspect
ratio, and **⌘Return** fills the display and restores the window. Mouse input
follows the scaled view. Native audio and Windows DirectSound startup checks
are bounded; a failed/stalled device check selects clocked silent playback.
Host executables use hardened runtime without microphone-input or App Sandbox
entitlements. Multiplayer remains available through Online Game (TCP 12345).

Prior signed FEX candidates completed local AI matches at 00:35 and 00:38, and fullscreen,
movement, jump, attack input, normal audio and timed silent recovery were
exercised. The shared display integration probe passes under both Wine targets.
Not every character, move, mode or remote multiplayer configuration was tested.

FEX translates the unchanged Windows game's x86 instructions. This is a
Rosetta-free host runtime, not a source port of the engine. The repository also
retains an Intel Wine/Rosetta build, and the combined release provides both.

Controls: WASD + J attack / K jump / L defend; player 2 arrows + comma/period/slash.
Hold Option while opening the app for the game folder and Wine reset actions.
Download the checksum and corresponding runtime source archive too.

See [TESTING.md](https://github.com/wowlocal/ntsd-2.8-wine/blob/main/TESTING.md)
and [frame measurements](https://github.com/wowlocal/ntsd-2.8-wine/blob/main/docs/PERFORMANCE.md)
for evidence and comparison limits.
