# NTSD 2.8.3.3.7 for macOS — FEX and Rosetta

This update fixes the Rosetta startup crash on the M4 Pro / macOS 27.0.1 test
host. Both runtimes remain available, and earlier releases are preserved.

| Download | App | Requirements |
| --- | --- | --- |
| NTSD-2.8.3.3-FEX-macOS.dmg | NTSD FEX | Apple Silicon, macOS 27+; Rosetta-free |
| NTSD-2.8.3.3-Rosetta-macOS.dmg | NTSD Rosetta | macOS 11+; Rosetta on Apple Silicon |

Copy the chosen app to Applications. The apps have separate game directories
and Wine prefixes and can coexist. Both apps and disk images are Developer ID
signed, notarized and stapled; checksums are calculated after stapling.

- Rebuilt Wine's small WoW64 CPU bridge with Rosetta-safe far-call/return mode
  transitions. NTSD.exe is unchanged. The installed Rosetta app completed a
  Naruto-versus-Sasuke AI match to its scoreboard at **01:11**.
- Kept background Wine desktop processes out of the game's app identity.
- Allowed 30 seconds for audio configuration during Wine startup; device
  probes retain their shorter recovery deadlines.
- Retained aspect-preserving window scaling, mapped mouse input, fullscreen
  with **⌘Return**, bounded audio checks and automatic silent recovery.
- No microphone access or App Sandbox. Fresh Rosetta DNS, TCP and UDP probes
  pass. Original-game multiplayer was previously tested with FEX.

Paired 60-second fullscreen idle-gameplay traces both sustained **30.30 frame
submissions/s**; p99 was **44 ms FEX / 41 ms Rosetta**. These are single-run GDI
submission measurements at 6016×3384, not display-latency or CPU-headroom tests.

Controls: WASD + J/K/L; player 2 uses arrows + comma/period/slash. Menus use W/S
and J. Hold Option when opening the app for the game folder and Wine reset.
Existing controls and recordings are preserved.

[Crash fix](https://github.com/wowlocal/ntsd-2.8-wine/blob/main/docs/ROSETTA_CRASH_FIX.md),
[validation](https://github.com/wowlocal/ntsd-2.8-wine/blob/main/TESTING.md),
[frame-time measurements](https://github.com/wowlocal/ntsd-2.8-wine/blob/main/docs/PERFORMANCE.md).
The source archive includes complete pinned Wine, DSOAL/OpenAL, MinHook,
patches, licenses and rebuild helpers.

Исправлен сбой запуска сборки Rosetta. Обе версии сохранены. Для Apple Silicon
с macOS 27+ можно выбрать FEX без Rosetta. Полный экран — **⌘Return**.
