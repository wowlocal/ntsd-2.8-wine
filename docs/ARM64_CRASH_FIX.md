# ARM64 compatibility fixes

The game executable is unchanged. This wrapper runs its x86 code through FEX
inside ARM64 Wine, using Hadron 0.3.1's original provisioned loader. It does not
use Rosetta and is not a source port of the game engine.

`tools/build-runtime-fixes.sh` pins FEX to
`741e146fdf5a89517e1a67e3c899907cfba6131a`, applies the five Hadron macOS
patches, then the three patches in `patches/fex` in order. Only the WoW64
translator and its native companion are replaced. The vendor's ARM64EC pair,
Wine loader signature and provisioning profile are preserved.

The downstream fixes address reproduced architectural differences:

- Full SMC validation must not also expose physical page-write traps to guests.
- Mtrack must report the guest's requested page protections, preserve real
  read-only write faults and copy-on-write semantics, and track executable
  non-image section mappings. Protection metadata is guarded with the existing
  range lock; untrapping reads the current protection under the exclusive lock.
- ARM integer division does not trap like x86. Guest DIV zero/overflow and
  8/16/32-bit IDIV zero/overflow now raise an x86 divide error before changing
  architectural registers. A conditional fault IR operation uses the already
  loaded divisor, rather than reading a memory operand twice. Fault PC,
  registers and flags are preserved, including carry clear/set cases.

`tools/windows_divide_probe.c` exercises 38 valid and exceptional divisions,
including boundaries, 17 expected exceptions and saved fault context. The
production translator reports `integer divide cases=38 caught=17 failures=0`.
`tools/windows_memory_probe.c` covers execution, unflushed and inline
self-modification, merged/split queries, a real read-only write fault, and
executable copy-on-write mappings. It reports `memory probe complete failures=0`.
These are component results; match acceptance is recorded separately in TESTING.

The ARM64 spawn helper uses macOS's 4 KB page-size API and then executes the
original signed Wine loader. Its entitlement permits the runtime's existing
DYLD library paths; it does not acquire the restricted cross-architecture
entitlement itself.

A separate native audio probe has an eight-second process deadline. A stuck
system audio service otherwise blocks Wine before a usable menu. In silent
fallback mode, a downstream DSOAL build supplies software DirectSound buffers
through OpenAL's null backend. A uniquely named DirectShow Null Renderer keeps
music graphs and their timing functional. The prefix remembers and restores its
previous audio-driver setting when returning to system audio. No host audio
settings or third-party drivers are changed. `NTSD_AUDIO=auto|silent|system`
selects the mode; the default is auto. Audible sound is unavailable in silent
mode.

The audio configuration helper runs through Hadron's play script with the
Mac display driver enabled. It uses built-in DirectSound for Quartz's import;
the native fallback DLL is selected only for the game, beside that DLL.
Canonical game/prefix/support paths also keep the original packed-asset loader's
executable path and working directory consistent when test directories contain
symlinks.

All patches are downstream changes in this wrapper. No contribution has been
submitted to the dependency repositories. Exact source commits, patches and
licences accompany the build. Build caches, prefixes, logs and signing
credentials are excluded from Git.
