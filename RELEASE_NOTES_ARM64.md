# NTSD 2.8.3.3.4 — playable ARM64 preview

Rosetta-free NTSD for **Apple Silicon on macOS 27 or later**. Copy NTSD from
the DMG to Applications and open it. The app and DMG are Developer ID signed,
notarized and stapled.

This release fixes startup failures in the ARM64 Wine/FEX runtime: executable
memory handling, section mappings and x86 integer-division exceptions. The
original game executable is unchanged. FEX still translates its x86 code;
this is not a source port of the engine.

Tested on macOS 27.0.1:

- Complete local match, repeat play, movement, jumping, attacks and pause.
- A complete two-instance network match with matching results, including
  synchronized character selection, movement and damage in both directions.
- Fresh setup, normal system audio and the silent-audio fallback.
- ARM64-only host execution, TCP/UDP checks and 38 divide regression cases.

The wrapper has no App Sandbox restriction on multiplayer. Host or connect
through Online Game; use the address shown by the host (TCP 12345).
The multiplayer test used two isolated copies on the same Mac, rather than a
second Mac or a remote Internet connection. This remains a preview based on an
early ARM64 runtime; not every character, move or game mode has been tested.

**Controls:** WASD + J attack / K jump / L defend. Battle menus use W/S and J;
after choosing bots, W twice then J starts Fight. **⌘Return** toggles the game's
fullscreen mode. The macOS green-button fullscreen mode is unsupported.

If the Mac's audio service stalls, the launcher can start with silent software
audio and restore normal output on a later healthy launch. No host audio driver,
firewall or privacy settings are changed.

Download the DMG and its post-stapling SHA-256 checksum. The accompanying source
archive contains the DSOAL/OpenAL sources, downstream patches, licences and build
helpers. Full details are in [TESTING.md](https://github.com/wowlocal/ntsd-2.8-wine/blob/main/TESTING.md).
