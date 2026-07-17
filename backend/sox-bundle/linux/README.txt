Linux SoX binary placement
==========================

Place a working Linux x64 sox binary here as `sox-bundle/linux/sox`
BEFORE running `npm run build-linux-appimage`.

The Linux build prompt walks through it. Quick reference:

  sudo apt install -y sox
  cp $(which sox) sox-bundle/linux/sox
  chmod +x sox-bundle/linux/sox

Why we ship it (AppImage specifically):
  - .deb users get sox via `Depends:` in package.json (no bundling needed).
  - AppImage has NO way to declare external dependencies, so without
    a bundled sox, AppImage users on systems without sox fall into the
    browser MediaRecorder fallback — same bug Windows had pre-v1.2.7.

The .deb build doesn't strictly need this bundled binary (it'll find
sox in /usr/bin), but bundling it is harmless and makes the .deb
self-contained too.

If this directory is empty at build time on AppImage, AppImage users
without system sox will hit the silent-fallback bug.
