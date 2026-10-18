# NTSD 2.8.3.3.6 for macOS — FEX and Rosetta

This prerelease keeps both runtimes available. Earlier releases remain downloadable.

| Download | Install | Requirements |
| --- | --- | --- |
| **NTSD-2.8.3.3-FEX-macOS.dmg** | NTSD FEX.app | Apple Silicon, macOS 27+; Rosetta-free |
| **NTSD-2.8.3.3-Rosetta-macOS.dmg** | NTSD Rosetta.app | macOS 11+; Rosetta on Apple Silicon |

Both apps and disk images are Developer ID signed, notarized and stapled.
Copy the chosen app to Applications. Their names, writable game copies and
Wine prefixes are separate, so they can coexist.

## Changes

- The game view scales when its window is resized or zoomed, preserving aspect
  ratio with black borders. Mouse coordinates track the scaled view.
- **⌘Return** enters fullscreen across the display and restores the window.
- Native audio and Windows DirectSound are checked with deadlines. A failed
  or stalled check selects silent software audio, and a later launch checks
  system output again. The injected Windows timeout test reaches the menu
  after its eight-second deadline.
- Both targets use hardened runtime without a microphone-input entitlement.
  The game does not require microphone access.
- Both retain unrestricted networking through the absence of App Sandbox.
  Online Game uses TCP 12345; normal macOS network permissions still apply.

## Tested scope

FEX completed local AI matches to their scoreboards at 00:35 and 00:38 with the display
support enabled. Movement, jump, attack input, fullscreen entry/exit, normal
DirectSound output and timed silent fallback were tested. The shared display
integration probe passes under both runtimes, including resize geometry, black
borders, mouse mapping and fullscreen restoration.

**Rosetta fails at startup on this macOS 27 / M4 Pro test host. Use FEX here.**
Its audio, display and network probes pass, but controlled original-game runs
hit stack-overflow/page-fault errors with both audio modes and with the scaling
DLL removed. This release does **not** claim completed Rosetta gameplay or a
paired gameplay performance comparison on this host. Its retained Wine
11.0_1 runtime is provided as the fallback. The [previous stable Rosetta release](https://github.com/wowlocal/ntsd-2.8-wine/releases/tag/v2.8.3.3.2)
and [previous FEX preview](https://github.com/wowlocal/ntsd-2.8-wine/releases/tag/v2.8.3.3.4)
remain available.

A prior 60-second FEX gameplay sample measured 30.30 frame submissions/s,
p95 39 ms and p99 45 ms. See [measurements and limitations](https://github.com/wowlocal/ntsd-2.8-wine/blob/main/docs/PERFORMANCE.md)
and [test details](https://github.com/wowlocal/ntsd-2.8-wine/blob/main/TESTING.md).

**Controls:** WASD + J/K/L; player 2 uses arrows + comma/period/slash. Battle
menus use W/S and J. Hold Option when opening the app for its game folder and
Wine reset actions. Existing controls and recordings are preserved.

Download the matching post-stapling SHA-256 checksum with each DMG. The source
archive contains the DSOAL/OpenAL sources, MinHook, patches, licenses and build
helpers. FEX still translates the original game's x86 instructions; the game
executable is unchanged.

Для Apple Silicon с macOS 27+ выбирайте **FEX**: Rosetta не нужна. Вторая сборка,
**Rosetta**, сохранена для совместимости. Окно масштабируется, полный экран —
**⌘Return**. При зависании звуковой службы игра запускается без звука; доступ
к микрофону не нужен. Проверки и ограничения тестирования описаны выше.
