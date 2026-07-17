# Build Echo v1.1 for macOS — self-contained guide

> This file is written so an AI agent (Claude Code / Gemini CLI) or a developer with
> **no prior context** can build the macOS app from scratch. Read it top to bottom.

## What this project is
**Echo** is a speech-to-text desktop app made of three parts that run together:
- **Electron** (`public/electron.js`) — the desktop shell + global hotkey + the floating "pill".
- **Python Flask backend** (`app.py`) — does the transcription (Groq Whisper), grammar
  correction, history, auth, DynamoDB. Electron launches it as a child process.
- **React UI** (`templates/index.html`) — a single file, no build step (Babel runs in-browser).

For a distributable app the **Python backend must be frozen** into a native executable
with **PyInstaller** (so end users need no Python), then bundled inside the Electron app.
On Windows this produced `Echo Setup 1.0.0.exe`. This guide does the macOS equivalent (`.dmg`).

## Goal
Produce `dist/Echo-1.0.0.dmg` (or `Echo-1.0.0-arm64.dmg`) — an installable macOS app named **Echo**.

---

## Prerequisites (install on the Mac first)
- **macOS** (Apple Silicon or Intel)
- **Python 3.10+** : `python3 --version`
- **Node.js 18+** : `node --version`
- **Xcode Command Line Tools** : `xcode-select --install`
- (Only for distribution outside your own Mac) an **Apple Developer account** for notarization.
  You can build + run locally without it; unsigned apps just need a right-click → Open.

---

## Step 1 — Get the code
```bash
git clone https://github.com/Zutawa-Studios/mywhisper.git
cd mywhisper
git checkout Hemanth-dev
git pull
```
(If already cloned: `cd mywhisper && git checkout Hemanth-dev && git pull`)

## Step 2 — Python env + dependencies
```bash
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
pip install pyinstaller
```

## Step 3 — Node dependencies
```bash
npm install
```

## Step 4 — Create config.json (NOT in git — it holds secrets)
The app reads `config.json` at runtime. It is gitignored, so it is NOT in the repo.
Create it from the example and add the Groq API key:
```bash
cp config.example.json config.json
# then edit config.json and set:  "api_key": "gsk_...your Groq key..."
```
> Building the `.dmg` does NOT require config.json (it's runtime data the end user
> supplies on first run). You only need it to TEST the app via `npm start`.
> Grammar correction requires AWS Bedrock — set `"bedrock_api_key": "..."`. There is
> no non-AWS grammar path; without a Bedrock key transcripts are left uncorrected.

## Step 5 — Freeze the Python backend (PyInstaller, ONEDIR)
Use **--onedir** (a folder, not one file). Onefile triggers antivirus and is slower.
macOS uses `:` (not `;`) as the add-data separator.
```bash
venv/bin/python -m PyInstaller --noconfirm --onedir --name echo-backend \
  --add-data "$(pwd)/templates:templates" \
  --collect-all botocore --collect-all boto3 \
  --collect-submodules groq --collect-submodules jose \
  --distpath build-backend/dist --workpath build-backend/work --specpath build-backend \
  app.py
```
Output: `build-backend/dist/echo-backend/echo-backend` (a Unix executable + an `_internal/` folder).

Verify it runs standalone (no Python needed):
```bash
ECHO_DATA_DIR="/tmp/echo-test" build-backend/dist/echo-backend/echo-backend
# should print a port and "Running on http://127.0.0.1:<port>". Ctrl+C to stop.
```

## Step 6 — (optional) quick live test before packaging
```bash
npm start
```
This runs Electron + the venv Python directly. Confirms features work before building the .dmg.

## Step 7 — Build the .dmg
`package.json` already bundles the frozen backend for mac via
`mac.extraResources` → `backend/echo-backend`. Just run:
```bash
npm run build            # universal-ish: builds dmg + zip for x64 + arm64
# or a single arch, faster:
npm run build-arm        # Apple Silicon only
npm run build-dmg        # Intel only
```
Output: `dist/Echo-1.0.0*.dmg`

## Step 8 — Signing / notarization (DEFERRED — costs $99/yr, removes the Gatekeeper dance)
Currently **deferred** (same defer-the-paid-stuff stance as cloud infra). Unsigned today:
testers right-click the app → **Open** (one-time Gatekeeper bypass), or run
`xattr -cr "/Applications/Echo.app"` if it says "damaged". Echo also self-heals the bundled
binaries at runtime by stripping quarantine (`public/electron.js` ~1732: `xattr -dr` +
`chmod +x`) — **signing + notarization makes that workaround unnecessary** and removes the
user-facing "unidentified developer" prompt entirely.

**Runbook for when you decide to sign (macOS):**
1. Join the **Apple Developer Program** ($99/yr) → create a **"Developer ID Application"**
   certificate; create an **app-specific password** for your Apple ID (or an App Store Connect
   API key) for notarization.
2. Set before `npm run build` (electron-builder signs with `CSC_*` and notarizes via the
   `APPLE_*` vars — keep `hardenedRuntime: true` + the entitlements, already in package.json):
   ```bash
   export CSC_LINK=/path/to/DeveloperIDApplication.p12
   export CSC_KEY_PASSWORD=...
   export APPLE_ID=you@example.com
   export APPLE_APP_SPECIFIC_PASSWORD=xxxx-xxxx-xxxx-xxxx
   export APPLE_TEAM_ID=XXXXXXXXXX
   ```
3. After building, confirm: `spctl -a -vvv "dist/mac/Echo.app"` → "accepted / Notarized
   Developer ID", and `xcrun stapler validate "dist/Echo-<ver>.dmg"`.

---

## How Echo works on macOS (for verification)
- On launch, Electron spawns the bundled backend at
  `process.resourcesPath/backend/echo-backend/echo-backend`, passing `ECHO_DATA_DIR`
  (the per-user `~/Library/Application Support/Echo` folder) so it can write
  config/history/recordings there (the app install dir is read-only).
- Push-to-talk = **Right Option**; recording uses SoX (`brew install sox`) on Mac, or the
  in-window record button (browser MediaRecorder) as a fallback.
- All saved files live in `~/Library/Application Support/Echo/`.

## Three macOS-specific bugs to VERIFY (coded but not yet tested on Mac)
1. **Minimize** works (yellow traffic-light button).
2. **Window control buttons don't overlap the logo** — the title bar has 78px left padding on macOS.
3. **Pill ↔ UI click/focus** — clicking the pill / around it when the dashboard is
   minimized vs maximized. (This one is NOT yet fixed — needs live debugging on the Mac.
   Symptom: clicking near the pill behaves differently depending on whether the main
   window is minimized.) The pill code is in `templates/index.html` (the `Pill` component)
   and `public/electron.js` (`createPillWindow`, `trackCursorAndReposition`,
   `setIgnoreMouseEvents` click-through logic).

## Common issues
- **`spawn ... ENOENT` / backend won't start**: the frozen backend folder wasn't bundled —
  confirm `dist/mac*/Echo.app/Contents/Resources/backend/echo-backend/echo-backend` exists.
- **electron-builder icon error**: if it rejects `assets/icon.png`, generate `assets/icon.icns`
  from `public/logo.svg` (e.g. with `iconutil` or an online converter) and point `mac.icon` at it.
- **"app is damaged"** on an unsigned build: `xattr -cr "/Applications/Echo.app"`.
- **No microphone**: grant mic permission in System Settings → Privacy & Security → Microphone.
