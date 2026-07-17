# Building the Echo Windows installer

Produces `dist/Echo Setup 1.0.0.exe` — a standalone installer. End users need
**no Python and no Node** installed; the Python backend is frozen into the app.

## Recommended: one-command guarded build (`build-windows.ps1`)
Instead of running the manual steps below and *hoping* you remembered to re-freeze, keep
python-jose, bundle SoX, etc., use the guarded script — it freezes via the spec and **asserts
every shipping invariant** (Python 3.11; jose/keyring/groq/boto3 importable; vendored UI +
templates + SoX bundled in both the frozen backend and the packaged app), failing loudly if
anything is missing:
```
powershell -ExecutionPolicy Bypass -File .\build-windows.ps1
# or just freeze + verify the backend, no installer:
powershell -ExecutionPolicy Bypass -File .\build-windows.ps1 -SkipBuild
```
The manual steps below remain as the reference for what the script does.

## Prerequisites (dev machine, one-time)
```
npm install                 # Electron + build tooling + sharp/png-to-ico
venv\Scripts\python -m pip install -r requirements.txt
venv\Scripts\python -m pip install pyinstaller
```

## Step 1 — (only if the logo changed) regenerate icons
```
node make_icons.js          # public/logo.svg -> assets/icon.ico + icon.png
```

## Step 2 — Freeze the Python backend → echo-backend\ (ONEDIR)
We use **--onedir** (a folder, not a single .exe) because Windows Defender
content-blocks unsigned **onefile** PyInstaller exes ("spawn UNKNOWN" /
"Permission denied"). Onedir is a normal exe + `_internal\` libs and isn't flagged.
```
venv\Scripts\python -m PyInstaller --noconfirm --onedir --name echo-backend ^
  --add-data "%CD%\templates;templates" ^
  --collect-all botocore --collect-all boto3 ^
  --collect-submodules groq --collect-submodules jose ^
  --distpath build-backend\dist --workpath build-backend\work --specpath build-backend ^
  app.py
```
After the first run you can rebuild faster from the generated spec:
```
venv\Scripts\python -m PyInstaller --noconfirm build-backend\echo-backend.spec ^
  --distpath build-backend\dist --workpath build-backend\work
```
Output: `build-backend\dist\echo-backend\echo-backend.exe` (bundled into the app at
`resources\backend\echo-backend\`).
Sanity check it runs with no Python:
```
set ECHO_DATA_DIR=%TEMP%\echo-test
build-backend\dist\echo-backend.exe
```
(should print a port and serve http://127.0.0.1:<port>/ ; Ctrl+C to stop)

## Step 3 — Build the installer
```
npm run build-win
```
→ `dist\Echo Setup 1.0.0.exe`

### If you hit: "Cannot create symbolic link" (winCodeSign)
This is a Windows symlink-privilege quirk in electron-builder's signing tool
(only the macOS files fail; we don't need them for an unsigned build).

**Fix A (recommended):** turn on Windows **Developer Mode**
(Settings → Privacy & Security → For developers → Developer Mode = On), then rebuild.

**Fix B (no admin):** pre-extract the tool, skipping the mac folder, then rebuild:
```
set C=%LOCALAPPDATA%\electron-builder\Cache\winCodeSign
node_modules\7zip-bin\win\x64\7za.exe x "%C%\<id>.7z" -o"%C%\winCodeSign-2.6.0" -x!darwin -y
```
(`<id>` = any of the numbered `.7z` files already in that cache folder)

## Code signing (DEFERRED — costs money, biggest lever vs SmartScreen/AV)
The installer is currently **unsigned** → Windows SmartScreen shows "unknown publisher"
(users click *More info → Run anyway*), and an unsigned networked `.exe` is a far more likely
**antivirus** target — the suspected trigger for "it won't launch / blank window" reports.
This is **deferred** (same defer-the-paid-stuff stance as cloud infra), not fixed in code.

**Runbook for when you decide to sign (Windows):**
1. Buy an **Authenticode code-signing certificate** from a CA (DigiCert, Sectigo, etc.):
   - **OV** (~$200–300/yr): cheaper; SmartScreen reputation builds up over downloads/time.
   - **EV** (~$300–500/yr): instant SmartScreen reputation, but the private key lives on a
     **hardware token / cloud HSM**, so CI/headless signing needs the vendor's signing tool.
2. Export the cert to a `.pfx` (OV) and set, before building:
   ```
   set CSC_LINK=C:\path\to\echo-codesign.pfx
   set CSC_KEY_PASSWORD=...your pfx password...
   ```
   `electron-builder` auto-signs the app + installer when `CSC_LINK` is present — no config
   change needed. (For an EV token, follow the token vendor's `signtool` integration instead.)
3. Rebuild (`build-windows.ps1` or `npm run build-win`); verify with
   `signtool verify /pa "dist\Echo Setup <ver>.exe"`.

## Notes
- Where the installed app stores data: `%APPDATA%\Echo\`
  (`config.json`, `transcription_history.json`, `recordings\`, `server_port.txt`).
- First run has no `config.json` → the app opens and prompts for the Groq API key.
- **macOS** build is a separate pass: freeze a macOS backend binary *on a Mac*,
  add it under `mac.extraResources`, then `npm run build` (+ Apple notarization).
```
