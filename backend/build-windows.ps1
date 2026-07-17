<#
.SYNOPSIS
  Guarded Windows release build for Echo (audit #17).

.DESCRIPTION
  ONE script that freezes the Python backend VIA THE SPEC and then ASSERTS every
  shipping invariant, exiting non-zero if any is missing - so a broken installer can
  never be produced. It encodes the invariants that have bitten us before:
    * re-freeze actually ran and produced a working backend,
    * python-jose + keyring are bundled (the jose-less 105 MB build regression),
    * the vendored UI (static/vendor/*) and templates are bundled (blank-window regression),
    * SoX is bundled (recording falls back to the fragile browser path otherwise).

  The installer is UNSIGNED (see the "Code signing (deferred)" section of BUILD_WINDOWS.md).

.PARAMETER SkipBuild
  Freeze + assert the backend only; skip electron-builder (no installer produced).

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\build-windows.ps1
#>
[CmdletBinding()]
param([switch]$SkipBuild)

$ErrorActionPreference = 'Stop'

# --- paths (this script lives in the project root, mywhisper\) --------------------
$Root      = $PSScriptRoot
$VenvPy    = Join-Path $Root 'venv\Scripts\python.exe'
$Spec      = Join-Path $Root 'build-backend\echo-backend.spec'
$DistDir   = Join-Path $Root 'build-backend\dist'
$WorkDir   = Join-Path $Root 'build-backend\work'
$Frozen    = Join-Path $DistDir 'echo-backend'
$FrozenExe = Join-Path $Frozen 'echo-backend.exe'
$Internal  = Join-Path $Frozen '_internal'
$IndexHtml = Join-Path $Root 'templates\index.html'
$VendorDir = Join-Path $Root 'static\vendor'
$SoxExe    = Join-Path $Root 'sox-bundle\win\sox.exe'

function Fail($m) { Write-Host "FAIL : $m" -ForegroundColor Red; exit 1 }
function Ok($m)   { Write-Host "OK   : $m" -ForegroundColor Green }
function Warn($m) { Write-Host "WARN : $m" -ForegroundColor Yellow }
function Step($m) { Write-Host "`n=== $m ===" -ForegroundColor Cyan }

# ---------------------------------------------------------------------------------
Step '1/9  Pre-flight: release stray processes holding dist locks'
# echo-backend.exe is unambiguously ours - kill it (native, no cmd dependency).
Get-Process -Name 'echo-backend' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
# Only stop the VENV python (never unrelated Python installs).
try {
    $venvPyResolved = (Resolve-Path $VenvPy -ErrorAction SilentlyContinue).Path
    if ($venvPyResolved) {
        Get-CimInstance Win32_Process -Filter "Name='python.exe'" -ErrorAction SilentlyContinue |
            Where-Object { $_.ExecutablePath -eq $venvPyResolved } |
            ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    }
} catch {}
Ok 'stray backend/python processes cleared'

# ---------------------------------------------------------------------------------
Step '2/9  Assert venv + Python 3.11'
if (-not (Test-Path $VenvPy)) { Fail "venv python not found: $VenvPy  (run: python -m venv venv)" }
$ver = (& $VenvPy --version 2>&1 | Out-String).Trim()
if ($ver -notmatch 'Python 3\.11') { Fail "venv is '$ver' but the freeze MUST use Python 3.11" }
Ok $ver

# ---------------------------------------------------------------------------------
Step '3/9  Assert runtime deps importable in the venv (jose-less guard)'
$pycheck = @'
import importlib
for m in ['jose', 'keyring', 'groq', 'boto3', 'flask', 'cryptography']:
    importlib.import_module(m)
import PyInstaller  # build tool must be present too
print('deps-ok')
'@
$depOut = (& $VenvPy -c $pycheck 2>&1 | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $depOut -notmatch 'deps-ok') {
    Fail "venv is missing a required dependency.`n$depOut`n(fix: venv\Scripts\python -m pip install -r requirements.txt pyinstaller)"
}
Ok 'jose, keyring, groq, boto3, flask, cryptography, PyInstaller all importable'

# ---------------------------------------------------------------------------------
Step '4/9  Assert source bits the freeze depends on'
if (-not (Test-Path $Spec)) { Fail "spec not found: $Spec" }
$specText = Get-Content $Spec -Raw
foreach ($needle in @("collect_submodules('jose')", "collect_submodules('keyring')")) {
    if ($specText -notmatch [regex]::Escape($needle)) { Fail "spec is missing $needle" }
}
if ($specText -notmatch "'static'") { Fail "spec is not bundling the static/ folder (vendored UI)" }
if ($specText -notmatch "'templates'") { Fail "spec is not bundling templates/" }
Ok 'spec collects jose + keyring and bundles templates + static'

if (-not (Test-Path $IndexHtml)) { Fail "missing templates\index.html" }
# Derive the required vendor libs straight from index.html so the list can't drift.
$vendorRefs = [regex]::Matches((Get-Content $IndexHtml -Raw), '/static/vendor/([^"'']+)') |
              ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique
if ($vendorRefs.Count -lt 1) { Fail 'index.html references no /static/vendor/* libs - vendoring regressed?' }
foreach ($lib in $vendorRefs) {
    if (-not (Test-Path (Join-Path $VendorDir $lib))) { Fail "vendored lib referenced by index.html is missing: static\vendor\$lib" }
}
Ok ("vendored UI libs present (" + $vendorRefs.Count + "): " + ($vendorRefs -join ', '))

if (-not (Test-Path $SoxExe)) { Fail "missing sox-bundle\win\sox.exe (recording would fall back to the browser path)" }
Ok 'sox-bundle\win\sox.exe present'

# ---------------------------------------------------------------------------------
Step '5/9  Freeze the backend via the spec (PyInstaller, onedir)'
& $VenvPy -m PyInstaller --noconfirm $Spec --distpath $DistDir --workpath $WorkDir
if ($LASTEXITCODE -ne 0) { Fail 'PyInstaller freeze failed' }
Ok 'freeze completed'

# ---------------------------------------------------------------------------------
Step '6/9  Assert frozen output contains the UI + templates'
if (-not (Test-Path $FrozenExe)) { Fail "frozen exe missing: $FrozenExe" }
if (-not (Test-Path (Join-Path $Internal 'templates\index.html'))) { Fail '_internal\templates\index.html missing from frozen build' }
foreach ($lib in $vendorRefs) {
    if (-not (Test-Path (Join-Path $Internal "static\vendor\$lib"))) { Fail "_internal\static\vendor\$lib missing from frozen build" }
}
Ok 'frozen build has echo-backend.exe + templates + all vendored UI libs'

# ---------------------------------------------------------------------------------
Step '7/9  Smoke-test the frozen backend offline (no Python, no internet)'
# 7a - jose + keyring really import inside the FROZEN binary.
$env:ECHO_SELFTEST = '1'
$selftest = (& $FrozenExe 2>&1 | Out-String).Trim()
Remove-Item Env:\ECHO_SELFTEST -ErrorAction SilentlyContinue
if ($LASTEXITCODE -ne 0 -or $selftest -notmatch 'selftest-ok') {
    Fail "frozen self-test failed (jose/keyring not bundled?):`n$selftest"
}
Ok 'frozen self-test: jose + keyring import inside the packaged exe'

# 7b - it actually serves the vendored UI.
$tmp = Join-Path $env:TEMP ('echo-smoke-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
$env:ECHO_DATA_DIR = $tmp
$proc = Start-Process -FilePath $FrozenExe -PassThru -WindowStyle Hidden
try {
    $portFile = Join-Path $tmp 'server_port.txt'
    $port = $null
    for ($i = 0; $i -lt 40; $i++) {     # ~20 s
        if (Test-Path $portFile) { $port = (Get-Content $portFile -Raw).Trim(); if ($port) { break } }
        Start-Sleep -Milliseconds 500
    }
    if (-not $port) { Fail 'frozen backend never wrote server_port.txt' }

    $base = "http://127.0.0.1:$port"
    # NB: do NOT name this $root - PowerShell vars are case-insensitive and $Root is the
    # script dir used later in step 9 (Join-Path), so $root would clobber it.
    $rootResp = Invoke-WebRequest -Uri "$base/" -UseBasicParsing -TimeoutSec 10
    if ($rootResp.StatusCode -ne 200) { Fail "GET / returned $($rootResp.StatusCode)" }
    $reactLib = ($vendorRefs | Where-Object { $_ -match 'react\.' } | Select-Object -First 1)
    if ($reactLib) {
        $vend = Invoke-WebRequest -Uri "$base/static/vendor/$reactLib" -UseBasicParsing -TimeoutSec 10
        if ($vend.StatusCode -ne 200) { Fail "GET /static/vendor/$reactLib returned $($vend.StatusCode) - Flask static_folder fix regressed" }
    }
    $cfg = Invoke-WebRequest -Uri "$base/api/auth-config" -UseBasicParsing -TimeoutSec 10
    if ($cfg.Content -notmatch '"mode"') { Fail '/api/auth-config did not return a mode' }
    Ok "frozen backend served / (200), /static/vendor (200) and /api/auth-config on port $port"

    # 7c - the renderer actually MOUNTS. The curl checks above only prove bytes are served;
    # they never execute the in-browser Babel/React, so a wrong Babel major (8's automatic JSX
    # runtime emits an unresolvable 'import react/jsx-runtime') leaves #root empty -> a blank
    # window that still passes every HTTP-200 check. That is the bug that shipped in 1.2.13-1.2.15.
    # Render the page in headless Chrome/Edge and assert #root is populated.
    $browser = @(
        (Join-Path $env:ProgramFiles 'Google\Chrome\Application\chrome.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'Google\Chrome\Application\chrome.exe'),
        (Join-Path $env:ProgramFiles 'Microsoft\Edge\Application\msedge.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'Microsoft\Edge\Application\msedge.exe')
    ) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
    if (-not $browser) {
        Warn 'no Chrome/Edge found - SKIPPING the headless render check (cannot prove the UI mounts)'
    } else {
        # Use Start-Process with file redirection: browsers spam stderr (harmless startup noise),
        # and under $ErrorActionPreference='Stop' even `& browser 2>$null` turns native stderr into
        # a terminating error. Start-Process never routes native output through PowerShell's streams.
        $udd    = Join-Path $env:TEMP ('echo-cdp-' + [guid]::NewGuid().ToString('N'))
        $domOut = Join-Path $env:TEMP ('echo-dom-' + [guid]::NewGuid().ToString('N') + '.html')
        $domErr = "$domOut.err"
        $bArgs  = @('--headless','--disable-gpu','--no-sandbox','--log-level=3',
                    "--user-data-dir=$udd",'--virtual-time-budget=8000','--dump-dom',"$base/#/")
        Start-Process -FilePath $browser -ArgumentList $bArgs -NoNewWindow -Wait -PassThru `
            -RedirectStandardOutput $domOut -RedirectStandardError $domErr | Out-Null
        $dom = if (Test-Path $domOut) { (Get-Content $domOut -Raw) } else { '' }
        Remove-Item -Recurse -Force $udd -ErrorAction SilentlyContinue
        Remove-Item -Force $domOut, $domErr -ErrorAction SilentlyContinue
        $marker = '<div id="root">'
        $idx = $dom.IndexOf($marker)
        if ($idx -lt 0) { Fail 'headless render: <div id="root"> not present in the rendered DOM' }
        $after = $dom.Substring($idx + $marker.Length).TrimStart()
        if ($after.StartsWith('</div>')) {
            Fail 'headless render: #root is EMPTY - the React UI did not mount (blank-window bug). Check static\vendor\babel.min.js is Babel 7.x (NOT 8) - see feedback_vendor_babel7_not_8.'
        }
        Ok ("headless render: #root is populated (" + ($browser.Split('\')[-1]) + ") - the UI actually mounts")
    }
}
finally {
    if ($proc -and -not $proc.HasExited) { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue }
    Remove-Item Env:\ECHO_DATA_DIR -ErrorAction SilentlyContinue
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}

# ---------------------------------------------------------------------------------
if ($SkipBuild) {
    Write-Host "`n-SkipBuild set: backend frozen + verified; installer NOT built." -ForegroundColor Yellow
    exit 0
}

Step '8/9  Build the Windows installer (electron-builder NSIS)'
npm run build-win
if ($LASTEXITCODE -ne 0) {
    Write-Host "electron-builder failed. If it was the winCodeSign 'Cannot create symbolic link' error, see BUILD_WINDOWS.md:" -ForegroundColor Yellow
    Write-Host "  Fix A: enable Windows Developer Mode, then rerun." -ForegroundColor Yellow
    Write-Host '  Fix B (no admin): pre-extract winCodeSign excluding the darwin folder (-x!darwin), then rerun.' -ForegroundColor Yellow
    Fail 'installer build failed'
}
Ok 'electron-builder finished'

# ---------------------------------------------------------------------------------
Step '9/9  Assert packaged output bundles backend + SoX + UI'
$res = Join-Path $Root 'dist\win-unpacked\resources'
if (-not (Test-Path (Join-Path $res 'backend\echo-backend\echo-backend.exe'))) { Fail 'packaged backend exe missing' }
if (-not (Test-Path (Join-Path $res 'sox\sox.exe'))) { Fail 'packaged sox\sox.exe missing' }
foreach ($lib in $vendorRefs) {
    if (-not (Test-Path (Join-Path $res "backend\echo-backend\_internal\static\vendor\$lib"))) { Fail "packaged _internal\static\vendor\$lib missing" }
}
Ok 'packaged app has backend + sox + vendored UI'

$installer = Get-ChildItem (Join-Path $Root 'dist') -Filter 'Echo Setup *.exe' -ErrorAction SilentlyContinue |
             Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($installer) {
    $mb = [math]::Round($installer.Length / 1MB, 1)
    Ok "installer: $($installer.FullName)  ($mb MB)"
} else {
    Write-Host 'WARN : no "Echo Setup *.exe" found under dist\ (check electron-builder output)' -ForegroundColor Yellow
}

Write-Host "`n=== BUILD VERIFIED ===" -ForegroundColor Green
Write-Host 'NOTE: this installer is UNSIGNED -> SmartScreen "unknown publisher" + higher AV risk.' -ForegroundColor Yellow
Write-Host '      See the "Code signing (deferred)" section of BUILD_WINDOWS.md.' -ForegroundColor Yellow
Write-Host 'REMINDERS: bump package.json version; move the installer to ..\Echo - Windows v<ver> Installer\;' -ForegroundColor Yellow
Write-Host '           and write the matching Echo Prompts\mac\<ver>.txt + linux\<ver>.txt.' -ForegroundColor Yellow
