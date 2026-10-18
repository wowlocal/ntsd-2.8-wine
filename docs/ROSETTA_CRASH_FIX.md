# Rosetta startup crash — revision 7

On the M4 Pro / macOS 27.0.1 test host, the original Wine 11.0_1 runtime
failed after the first full-window draw. The exception trace identified
`wow64cpu.dll + 0x1139` (`0x7bf21139` in that run), reading `0x4ecd`.
This instruction is a 64-bit RIP-relative load. Reading its displacement as
an absolute address shows that the bridge was being decoded in 32-bit mode.
Exception delivery then produced invalid-stack/stack-overflow errors.

The failure also occurred with the display shim removed and with normal
system audio. Increasing the executable's stack reserve did not fix it;
that diagnostic change was reverted. NTSD.exe remains unchanged.

Revision 7 rebuilds Wine's small WoW64 CPU DLL from pinned Gcenx/Wine 11.0
source. Under Rosetta it uses far-call trampolines to enter 64-bit mode and
far returns to return to 32-bit mode, following the existing
[swingby-wine implementation](https://github.com/tsukasa-art/swingby-wine/blob/9c9d68d4d0b2fbf25117d9d2e737b5a9f43561ee/dlls/wow64cpu/cpu.c).
Physical Intel processors retain the original far-jump path. This was tested
on Apple Silicon; physical Intel hardware was not available for validation.

The source patch, compiler pin, imports and builtin-module marker are handled
by `tools/build-rosetta-bridge.sh`. The release source archive includes the
complete pinned Wine source and downstream patch under LGPL-2.1-or-later.
It does not add another translator to the Rosetta build.

The launcher also assigns the game app identity only when spawning the game.
Audio probes can create a background Wine desktop process; giving that process
the same identity caused app selection and accessibility queries to target it.

## Validation

- The installed revision 7 Rosetta app finished loading and accepted menu,
  movement, jump and attack input with normal DirectSound output.
- Naruto versus Sasuke AI on Wharf completed to the scoreboard at **01:11**:
  P1 lost, 0 damage / 510 HP lost; AI won, 510 damage / 0 HP lost.
- Fullscreen covered 6016×3384 and returned to the complete 1333×730 view.
- A four-thread context-resume probe completed 2,000 handled illegal-instruction
  exceptions with zero failures. The original runtime also passes this small
  probe; the original game is the reproducer for the startup failure.
- Fresh 32-bit Winsock probes passed DNS, outbound TCP/UDP and inbound TCP;
  the host process sample confirms X86-64 translation.

Game executable SHA-256:
`5eda51440039099069d041e5bd13fde8be9fd8c7b20983985b1712a59719d86b`.
