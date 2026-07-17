Mac SoX binary placement
========================

Place a working macOS sox binary here as `sox-bundle/mac/sox` BEFORE
running `npm run build-universal` / `build-arm` / `build-dmg`.

The Mac build prompt under D:\wisper_flow\Echo Prompts\mac\1.2.10.txt
walks through the exact copy command. Quick reference:

  # Apple Silicon (M1/M2/M3)
  cp $(brew --prefix sox)/bin/sox sox-bundle/mac/sox
  cp $(brew --prefix sox)/lib/libsox.*.dylib sox-bundle/mac/ 2>/dev/null || true
  chmod +x sox-bundle/mac/sox

  # OR Intel
  cp /usr/local/bin/sox sox-bundle/mac/sox
  chmod +x sox-bundle/mac/sox

Why we ship it instead of relying on the user's brew install:
  - Finder-launched Electron apps don't inherit the user's shell PATH,
    so /usr/local/bin and /opt/homebrew/bin are NOT visible to spawn().
  - Many Mac users don't have Homebrew at all.
  - Without a bundled sox, the app silently falls into the browser
    MediaRecorder fallback — the bug that hit Windows pre-v1.2.7.

If this directory is empty at build time, the Mac binary won't ship
and Mac users will see the same silent-fallback behavior the audit
flagged as C2.
