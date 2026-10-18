# NTSD ARM64 experimental build

Native ARM64 Wine/FEX runtime for Apple Silicon on macOS 27 or later. Rosetta
is not used by this target. The original Windows game still uses x86 CPU
translation; this is not a source port of its engine.

**NTSD 2.8.3.3 currently fails during startup. This build is not playable.**
The native bundle, prefix setup, signatures and 32-bit Windows TCP/UDP transport
checks pass. Full matches, in-game input, fullscreen, music and actual multiplayer
remain unverified. Updating FEX and testing 4 KB pages did not resolve startup.
See TESTING.md for inputs and preserved results.

The existing Intel build remains the default. This ARM64 target is opt-in:
`NTSD_RUNTIME=arm64 ./build.sh ~/Downloads/NTSD2.8.3.3.zip`.

The loader retains Hadron's provisioned signature. App Sandbox is absent;
no system firewall or privacy settings are disabled. All component licences and
corresponding-source references are bundled.
