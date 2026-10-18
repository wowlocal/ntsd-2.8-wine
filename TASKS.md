# Current work

- [x] Maintain separate FEX and Intel Wine / Rosetta build targets with distinct app names, prefixes and game directories.
- [ ] Publish both clearly named DMGs and checksums together; preserve existing release downloads.
- [ ] Obtain a paired gameplay frame-time comparison. **Blocked on this macOS 27 host:** Rosetta NTSD hits a startup exception, including without the scaling DLL and with system audio. Valid FEX data, a plot, analysis tools and the failed-baseline record are saved in docs/PERFORMANCE.md.
- [x] Verify startup, bounded DirectSound checks, silent recovery and restoration to system audio.
- [x] Scale the game view with window resizing while preserving aspect ratio; verify mapped mouse input.
- [x] Scale fullscreen to the display and restore the window, including native green-button transitions.
- [x] Verify gameplay through complete FEX matches and both runtimes' display/audio/network integration probes.
- [x] Finish signing, notarization, stapling and Gatekeeper checks for both revision 6 builds; verify the mounted images.
- [ ] Push main and publish the combined release.
