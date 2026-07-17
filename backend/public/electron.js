const { app, BrowserWindow, ipcMain, globalShortcut, nativeTheme, clipboard, dialog, safeStorage, shell, Tray, Menu, powerMonitor, nativeImage } = require('electron');
const path = require('path');
const os = require('os');
const { spawn, exec, execSync } = require('child_process');
const { uIOhook, UiohookKey } = require('uiohook-napi');
const http = require('http');
const https = require('https');
const crypto = require('crypto');
const fs = require('fs');

// Native audio recording
let record;
try {
  record = require('node-record-lpcm16');
} catch (e) {
  console.error('Failed to load node-record-lpcm16:', e);
}

// ============================================
// GLOBAL ERROR SAFETY NET (BUG-12 / audit #11)
// Registering these handlers suppresses Electron's fatal "A JavaScript error
// occurred in the main process" dialog and keeps us running. Policy: LOG every
// error (console + persistent diagnostic log), but only pop a user-facing modal
// for a *truly fatal* error — an uncaught exception that left the app with no
// usable window. Benign async rejections (a transient fetch, an osascript/exec
// timeout, a closed-window race) are logged silently. Specific, actionable
// startup failures already have their own targeted dialogs below.
// ============================================
let lastErrorDialogTime = 0;

// "Usable window" = the user still has a working UI. Guarded because this can be
// called before `app` is ready or after teardown.
function hasUsableWindow() {
  try { return BrowserWindow.getAllWindows().some(w => !w.isDestroyed()); }
  catch (_) { return false; }
}

function reportMainError(label, err, { fatal = false } = {}) {
  console.error(`[${label}]`, (err && err.stack) ? err.stack : String(err));
  // Persist so packaged builds (no console) remain debuggable. Best-effort —
  // writeDiagnostic is itself fully self-guarded, but wrap anyway for safety.
  try { writeDiagnostic('main-error', { label, message: (err && err.message) || String(err) }); } catch (_) {}
  if (!fatal) return;                         // benign → logged only, no modal
  const now = Date.now();
  if (now - lastErrorDialogTime > 5000) {
    lastErrorDialogTime = now;
    try {
      dialog.showErrorBox('Echo hit a problem', (err && err.message) ? err.message : String(err));
    } catch (_) {
      // dialog can be unavailable very early in startup; the log above still captured it
    }
  }
}
// Promise rejections never crash the process and are almost always benign — log only.
process.on('unhandledRejection', (reason) => reportMainError('unhandledRejection', reason));
// Uncaught throw: surface a dialog only when the app has no usable window left
// (truly dead / early-startup crash); otherwise log and keep going.
process.on('uncaughtException', (err) => reportMainError('uncaughtException', err, { fatal: !hasUsableWindow() }));

// ─────────────────────────────────────────────────────────────────────────────
// v1.2.5 — Timeout helpers
// Every blocking syscall on macOS (osascript, exec) used to wait forever. If
// one hung, the recording state stayed stuck at `recording=true`, and Echo
// kept holding the audio HAL device + Accessibility event tap, which caused
// other macOS apps to freeze. These helpers cap the wait time so a stuck
// resource ALWAYS errors out instead of hanging the state machine.
// ─────────────────────────────────────────────────────────────────────────────

/** Race a promise against a timer. Rejects with `${label} timed out` after `ms`. */
function withTimeout(promise, ms, label) {
  return new Promise((resolve, reject) => {
    const t = setTimeout(() => reject(new Error(`${label} timed out after ${ms}ms`)), ms);
    promise.then(
      (v) => { clearTimeout(t); resolve(v); },
      (e) => { clearTimeout(t); reject(e); }
    );
  });
}

/** Promise wrapper around child_process.exec with a hard timeout + SIGKILL. */
function execWithTimeout(cmd, timeoutMs) {
  return new Promise((resolve, reject) => {
    exec(cmd, { timeout: timeoutMs, killSignal: 'SIGKILL' }, (err, stdout, stderr) => {
      if (err) reject(err);
      else resolve({ stdout: stdout || '', stderr: stderr || '' });
    });
  });
}

/** Cheap "is this PID still in the process table?" check. */
function isProcessAlive(pid) {
  if (!pid || typeof pid !== 'number') return false;
  try { process.kill(pid, 0); return true; } catch (_) { return false; }
}

/** Poll until a PID exits or the timeout elapses. Resolves true if exited, false on timeout. */
function waitForProcessExit(pid, timeoutMs) {
  if (!isProcessAlive(pid)) return Promise.resolve(true);
  return new Promise((resolve) => {
    const start = Date.now();
    const iv = setInterval(() => {
      if (!isProcessAlive(pid)) { clearInterval(iv); resolve(true); return; }
      if (Date.now() - start > timeoutMs) { clearInterval(iv); resolve(false); }
    }, 100);
  });
}

// One-time, non-fatal notice (e.g. macOS Accessibility permission needed). Shown
// once per process so we never nag the user on every keypress (BUG-15 / BUG-05).
const shownNotices = new Set();
function showOneTimeNotice(key, title, message) {
  if (shownNotices.has(key)) return;
  shownNotices.add(key);
  console.warn(`[notice:${key}] ${message}`);
  try {
    dialog.showMessageBox({ type: 'warning', title, message, buttons: ['OK'] });
  } catch (_) {
    // dialog can be unavailable very early in startup; the log above still captured it
  }
}

// ============================================
// RECORDING STATE MACHINE — single source of truth (Phase 1 / D7)
// Main owns recording truth and broadcasts it to the pill over ONE channel
// ('pill-state'). No executeJavaScript injection, no parallel timers, no
// per-transition event zoo. Every start is paired with exactly one terminal
// state (success | error | idle).
// ============================================
function sendPillState(state, extra = {}) {
  currentStatus = state;
  if (pillWindow && !pillWindow.isDestroyed()) {
    pillWindow.webContents.send('pill-state', Object.assign({
      state,
      recordingId: currentRecordingId,
      recordingTime: recordingElapsed
    }, extra));
  }
}

function startRecordingTimer() {
  stopRecordingTimer();
  recordingTimer = setInterval(() => {
    recordingElapsed += 1;
    // Hard cap (#9): a latched recording must not grow past Groq's ~25MB upload
    // limit (~13min of 16kHz WAV) and fail opaquely. Auto-stop + transcribe what we
    // have at MAX. finishRecording is guarded + stops this timer, so no double-fire,
    // and it covers both the native and browser pipelines when transcribe=true.
    if (recordingElapsed >= MAX_RECORDING_SEC) {
      console.warn('[cap] Max recording length reached — auto-stopping + transcribing');
      try { writeDiagnostic('recording-max-length', { elapsed: recordingElapsed }); } catch (_) {}
      sendPillState('recording', { nearLimit: true, message: 'Max length reached — transcribing…' });
      finishRecording(true);
      return;
    }
    // Heartbeat doubles as reconciliation: while we are truly recording, keep
    // asserting it so the pill can never silently drift to idle (BUG-03 / BUG-22).
    // Warn the user before the cutoff so the auto-stop isn't a surprise.
    sendPillState('recording', recordingElapsed >= WARN_RECORDING_SEC ? { nearLimit: true } : {});
  }, 1000);
}

function stopRecordingTimer() {
  if (recordingTimer) {
    clearInterval(recordingTimer);
    recordingTimer = null;
  }
}

function shortError(err) {
  const msg = (err && err.message) ? err.message : String(err || 'Unknown error');
  return msg.length > 80 ? msg.slice(0, 77) + '…' : msg;
}

// Recorder spawn/stream failure (e.g. SoX missing, mic unplugged) — terminal error (BUG-06 / BUG-11)
function notifyRecordingError(message) {
  stopRecordingTimer();
  isRecordingActive = false;
  sendPillState('error', { message: message || 'Recording error' });
}

// Single entry point to START a recording — hotkey, F5, and pill click all use this.
//
// v1.2.6 — fixes a v1.2.5 regression. v1.2.5 moved the `isRecordingActive=true`
// flip to AFTER `await getPlatformFocusTarget()` + `await startBackgroundRecording()`
// to prevent stuck state if those awaits hung. But on Mac, those awaits take
// 50-200ms (osascript spawn + SoX spawn), and the user can finish a short tap
// (down+up in <100ms) BEFORE the awaits complete. The keyup handler then sees
// `isRecordingActive===false` and early-exits at:
//     if (!isRecordingActive && !isBackgroundRecording) return;
// which means `pendingDoubleTap` never gets set, which means the SECOND tap
// of a double-tap can't enter latch mode. Result: double-tap broken on Mac.
//
// v1.2.6 reverts the ordering: state flags flip IMMEDIATELY (so double-tap
// detection works), BUT we keep the timeout-protected awaits + the catch +
// forceResetRecordingState + the 60s watchdog. So if osascript hangs, the
// catch block (or the watchdog as last resort) still cleans up — we just no
// longer block the synchronous keyup handler from seeing the recording state.
async function beginRecording() {
  if (isRecordingActive || isBackgroundRecording) {
    return; // already recording — ignore (prevents double-start races)
  }

  // STEP 1: Flip state flags IMMEDIATELY. The keyup handler reads these
  // within milliseconds of the keydown — it can't wait for osascript/SoX.
  // Cleanup safety is provided by:
  //   - the try/catch below (resets on any await failure)
  //   - the 30s no-audio-progress watchdog (catches truly broken pipelines)
  //   - the 3s+5s timeouts on the blocking calls themselves
  // Recording runs until the user stops it OR the MAX_RECORDING_SEC cap auto-stops
  // it (#9), with a warning at WARN_RECORDING_SEC — see startRecordingTimer.
  isRecordingActive = true;
  currentRecordingId += 1;
  recordingElapsed = 0;
  recordingStartedAt = Date.now();
  // Seed the audio-progress timer to NOW so the watchdog's 30s no-progress
  // check doesn't falsely fire during the SoX spawn delay.
  lastAudioChunkAt = Date.now();
  // v1.2.11 — decide browser-vs-native at the FIRST millisecond, before the
  // getPlatformFocusTarget() osascript await (up to 3s on Mac). Previously
  // isBrowserRecording was set only deep inside the sox branch, so a fast keyup
  // during the osascript await saw it false and misrouted finishRecording into
  // the native stop path → phantom "No speech detected" (race M-3). soxAvailable
  // is fixed at startup, so this is the correct value for the whole session.
  isBrowserRecording = !soxAvailable;

  // STEP 2: capture focus target with a 3s timeout. On Mac this spawns
  // osascript. If it hangs, we get an error and the catch resets state.
  let target = null;
  try {
    target = await getPlatformFocusTarget();
  } catch (e) {
    writeDiagnostic('focus-target-error', { message: String(e && e.message) });
    target = null;
  }
  savedPasteBundleId = (target && target.value && !/electron/i.test(String(target.value))) ? target : null;

  // STEP 3: spawn the recorder. Wrapped in withTimeout so a stuck SoX spawn
  // can't wedge us forever.
  try {
    if (!soxAvailable) {
      // Browser MediaRecorder fallback (no SoX bundled or found).
      //
      // v1.2.7: previously this threw if pillWindow was destroyed, leaving the
      // user with NO feedback and a stuck-true isRecordingActive flag (the
      // catch below now resets it). Worse, even when pillWindow existed, the
      // IPC went to a window the user couldn't see if the pill had been
      // z-order-demoted, hidden by a fullscreen app, or never made visible
      // after a display change. We now (a) recreate the pill if destroyed,
      // (b) wait for it to be loaded, and (c) force-show it before sending
      // the IPC, so the user always sees the recording UI.
      //
      // isBrowserRecording was already set true at the flag flip above (v1.2.11),
      // so a fast keyup during the recreate await routes correctly to the browser
      // stop branch instead of the native path.
      if (!pillWindow || pillWindow.isDestroyed()) {
        writeDiagnostic('pill-recreate-for-recording', { reason: 'destroyed-on-begin-record' });
        createPillWindow();
        // Wait up to 2s for the renderer to load before sending IPC.
        if (pillWindow) {
          await new Promise((resolve) => {
            let done = false;
            const finish = () => { if (!done) { done = true; resolve(); } };
            pillWindow.webContents.once('did-finish-load', finish);
            setTimeout(finish, 2000); // backstop — never block forever
          });
        }
      }
      if (!pillWindow || pillWindow.isDestroyed()) {
        throw new Error('Pill window unavailable — recording cannot start without it on this platform (no SoX). Re-launch Echo from the tray.');
      }
      // Force-show + raise the pill so the user actually sees the recording UI.
      try {
        pillWindow.showInactive();
        pillWindow.setAlwaysOnTop(true, 'screen-saver');
      } catch (_) {}
      // isBrowserRecording already set true above (before the recreate await).
      sendPillState('recording');
      startRecordingTimer();
      pillWindow.webContents.send('browser-record-start');
    } else {
      await withTimeout(startBackgroundRecording(), 5000, 'startBackgroundRecording');
      // Native path also needs the pill visible for in-progress feedback.
      try {
        if (pillWindow && !pillWindow.isDestroyed()) {
          pillWindow.showInactive();
          pillWindow.setAlwaysOnTop(true, 'screen-saver');
        }
      } catch (_) {}
      sendPillState('recording');
      startRecordingTimer();
    }
    writeDiagnostic('begin-recording', {
      soxPath: soxAvailable ? soxBinaryPath : false,
      mode: soxAvailable ? 'native' : 'browser',
      pillAlive: !!(pillWindow && !pillWindow.isDestroyed()),
    });
  } catch (err) {
    writeDiagnostic('begin-recording-error', { message: String(err && err.message) });
    // If the recorder spawn failed/timed out, we still have the early flag flip
    // from Step 1 to clean up — forceResetRecordingState handles that plus any
    // partial SoX child.
    forceResetRecordingState('begin-recording-error');
    sendPillState('error', { message: shortError(err) });
  }
}

// Single entry point to STOP a recording. transcribe=false cancels without sending audio.
async function finishRecording(transcribe) {
  if (!isRecordingActive && !isBackgroundRecording) {
    return; // nothing to stop
  }
  isRecordingActive = false;
  isHotkeyPressed = false;
  // Always clean up latch/double-tap state regardless of what triggered the stop
  isLatchMode = false;
  if (pendingDoubleTap) { clearTimeout(pendingDoubleTap); pendingDoubleTap = null; }
  stopRecordingTimer();

  // Browser recording path: pill handles capture + transcription async, result
  // arrives via 'transcription-complete' IPC which updates pill state and pastes.
  if (isBrowserRecording) {
    isBrowserRecording = false;
    if (!transcribe) {
      savedPasteBundleId = null;
      if (pillWindow && !pillWindow.isDestroyed()) {
        pillWindow.webContents.send('browser-record-stop', { cancel: true });
      }
      sendPillState('idle');
      return;
    }
    sendPillState('processing');
    if (pillWindow && !pillWindow.isDestroyed()) {
      pillWindow.webContents.send('browser-record-stop', { cancel: false });
    }
    // v1.2.11 — arm the processing watchdog: the renderer now owns the
    // transcription, and if its 'transcription-complete' IPC never arrives the
    // pill would otherwise hang on 'processing' forever (M-2). Cleared the
    // instant the result lands (see the 'transcription-complete' handler).
    armBrowserProcessingTimeout();
    // savedPasteBundleId intentionally kept — transcription-complete handler reads + clears it
    return;
  }

  const pasteTarget = savedPasteBundleId;
  savedPasteBundleId = null;

  if (!transcribe) {
    try { await stopBackgroundRecording(); } catch (_) {}
    sendPillState('idle');
    return;
  }

  sendPillState('processing');

  let audioBuffer = null;
  try {
    audioBuffer = await stopBackgroundRecording();
  } catch (err) {
    sendPillState('error', { message: 'Recording failed' });
    return;
  }

  // Always resolve to a terminal state — no silent returns (BUG-02)
  if (!audioBuffer || audioBuffer.length < 1000) {
    sendPillState('error', { message: 'No speech detected' });
    return;
  }

  try {
    const text = await transcribeAudioFromMain(audioBuffer, currentModel); // BUG-04
    if (text && text.trim()) {
      clipboard.writeText(text);
      // BUG-05: auto-paste can fail (e.g. macOS Accessibility not granted). The text
      // is always on the clipboard, so tell the user to paste it themselves rather
      // than silently claiming success.
      let pasted = true;
      if (pasteTarget) {
        pasted = await platformPaste(pasteTarget);
        if (!pasted) {
          if (process.platform === 'darwin') {
            showOneTimeNotice('paste-accessibility',
              'Couldn\'t paste automatically',
              'Echo needs Accessibility permission to paste for you.\n\nGrant it in System Settings → Privacy & Security → Accessibility.\n\nYour text is on the clipboard — press ⌘V to paste it.');
          } else {
            showOneTimeNotice('paste-win',
              'Couldn\'t paste automatically',
              'Echo couldn\'t restore focus to the previous window.\n\nYour text is on the clipboard — press Ctrl+V to paste it.');
          }
        }
      }
      const pasteHint = process.platform === 'darwin' ? 'Copied — press ⌘V' : 'Copied — press Ctrl+V';
      sendPillState('success', { message: pasted ? 'Copied!' : pasteHint, text, pasted });
    } else {
      sendPillState('error', { message: 'No speech detected' });
    }
  } catch (err) {
    sendPillState('error', { message: shortError(err) }); // BUG-07 / BUG-10 message surfaced
  }
}

// Simple check for development mode (check after app ready)
let isDev = true;

// Background audio recording state
let audioRecorder = null;
let audioChunks = [];
let isBackgroundRecording = false;
// v1.2.9 — set true while stopBackgroundRecording is in flight. Tells the
// audioStream 'error' handler to ignore the SoX-exit error that SIGTERM
// causes during a normal stop (which would otherwise wipe audioChunks and
// produce a phantom "No speech detected").
let isStoppingRecording = false;

// Singleton instance lock
const gotTheLock = app.requestSingleInstanceLock();

let pillWindow = null;
let mainWindow = null;
let flaskProcess = null;
let currentDisplayId = null;
let lastCursorPosition = { x: 0, y: 0 };
let screenTrackingInterval = null;
let isHotkeyPressed = false;
let isRecordingActive = false;
let previousAppName = null; // Store the app that was focused before pill (dashboard paste path)
let serverPort = 8080; // Default port, will be updated dynamically

// --- Single source of truth for the recording lifecycle (Phase 1 / D7) ---
let currentStatus = 'idle';          // idle | recording | processing | success | error
let currentRecordingId = 0;          // increments per session; lets the renderer drop stale events
let recordingElapsed = 0;            // seconds — the ONE recording clock (BUG-01)
let recordingTimer = null;           // the ONE timer that owns recordingElapsed
let currentModel = 'whisper-large-v3-turbo'; // last model the pill selected (BUG-04)
let savedPasteBundleId = null;       // app to refocus + paste into after a hotkey/pill recording
let hotkeyListenerActive = false;    // true once uIOhook.start() succeeds (BUG-15)
let trayIcon = null;                 // system tray / menu bar icon — always-on safety net
let pillHeartbeatInterval = null;    // unconditional keep-alive so the pill survives idle/sleep

// v1.2.5 — recording lifecycle watchdog
let recordingStartedAt = 0;          // epoch ms when state flipped to recording; 0 = idle
let recordingWatchdogInterval = null; // 5s tick that force-resets stuck state
// #9 — Hard recording cap. History: v1.2.5 (60s) / v1.2.6 (30min) caps auto-CUT and
// DROPPED audio (wrong); v1.2.7 removed the ceiling, but then very long recordings
// (>~13 min of 16kHz WAV) exceeded Groq's 25MB limit and failed opaquely. The cap below
// is the middle ground: at MAX we auto-stop AND transcribe what was captured (no dropped
// audio), after WARNing the user first so the cutoff isn't a surprise. 10 min of 16kHz
// mono WAV ≈ 19MB, safely under 25MB. The progress-based watchdog (below) is unchanged.
const MAX_RECORDING_SEC  = 600;      // 10 min — auto-stop + transcribe
const WARN_RECORDING_SEC = 480;      // 8 min  — warn (pill timer turns red) before the cutoff
let lastAudioChunkAt = 0;
const NO_PROGRESS_MS = 30_000;       // 30s with no chunks while "recording" = stuck pipeline

// ─────────────────────────────────────────────────────────────────────────────
// v1.2.5 — Structured diagnostic logger
// Writes JSON-line records to <userData>/echo-diagnostic.log. When a user reports
// "Echo got stuck" or "Mac froze," ask for this file — every state-machine
// transition and every blocking-syscall outcome is recorded with timestamp +
// platform + process state. No PII (no audio, no transcribed text).
// ─────────────────────────────────────────────────────────────────────────────
function writeDiagnostic(event, data) {
  try {
    const logPath = path.join(getDataDir(), 'echo-diagnostic.log');
    const entry = {
      ts: new Date().toISOString(),
      event,
      platform: process.platform,
      version: app.getVersion ? app.getVersion() : 'unknown',
      packaged: app.isPackaged,
      pid: process.pid,
      state: {
        isRecordingActive,
        isBackgroundRecording,
        isBrowserRecording,
        recordingId: currentRecordingId,
        recordingElapsedSec: recordingElapsed,
        recordingStartedAt,
        soxPid: (audioRecorder && audioRecorder.process && audioRecorder.process.pid) || null,
        flaskPid: (flaskProcess && flaskProcess.pid) || null,
        serverPort,
      },
      data: data || {},
    };
    fs.appendFileSync(logPath, JSON.stringify(entry) + '\n');
  } catch (_) {
    // never let diagnostics crash the app
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// v1.2.5 — forceResetRecordingState
// Single canonical "burn it all down" path for the recording state machine.
// Called from: the watchdog, every catch in beginRecording / finishRecording,
// and the app-quit IPC. Guarantees that no matter what state we got into, all
// flags clear, all child processes die, and the pill returns to a usable state.
// ─────────────────────────────────────────────────────────────────────────────
function forceResetRecordingState(reason) {
  try { writeDiagnostic('force-reset', { reason: reason || 'unknown' }); } catch (_) {}

  // 1. SIGKILL the SoX child if it's still alive. audioRecorder.stop() can hang
  //    on macOS if the audio HAL is wedged — go straight to SIGKILL.
  try {
    const soxPid = audioRecorder && audioRecorder.process && audioRecorder.process.pid;
    if (soxPid && isProcessAlive(soxPid)) {
      try { process.kill(soxPid, 'SIGKILL'); } catch (_) {}
    }
  } catch (_) {}

  // 2. Reset every flag and buffer.
  audioRecorder = null;
  audioChunks = [];
  isRecordingActive = false;
  isBackgroundRecording = false;
  isBrowserRecording = false;
  isHotkeyPressed = false;
  isLatchMode = false;
  isStoppingRecording = false;
  recordingStartedAt = 0;
  lastAudioChunkAt = 0;

  // 3. Stop the recording timer + clear any pending double-tap.
  try { stopRecordingTimer(); } catch (_) {}
  if (pendingDoubleTap) { try { clearTimeout(pendingDoubleTap); } catch (_) {} pendingDoubleTap = null; }
  // v1.2.11 — also disarm the browser-fallback processing watchdog so a reset
  // (from anywhere) can never leave a stray timer that fires a phantom error.
  try { clearBrowserProcessingTimeout(); } catch (_) {}

  // 4. Send an idle state to the pill so it's visually unstuck.
  try { sendPillState('idle'); } catch (_) {}
}

// ─────────────────────────────────────────────────────────────────────────────
// v1.2.5 — Recording watchdog
// Every 5 seconds, check whether we've been in a "recording" state for more
// than RECORDING_MAX_MS (60s). If so, force-reset everything. This is the
// last-resort safety net for "Echo got stuck and hung other Mac apps" — even
// if EVERY other timeout failed, the watchdog guarantees the audio HAL device
// and Accessibility event tap are released within ~60s of getting stuck.
// ─────────────────────────────────────────────────────────────────────────────
function startRecordingWatchdog() {
  if (recordingWatchdogInterval) return;
  recordingWatchdogInterval = setInterval(() => {
    if (!isRecordingActive && !isBackgroundRecording && !isBrowserRecording) return;
    if (recordingStartedAt === 0) return; // not actually started — flag set transiently

    // Progress-based stuck detection — SoX path only. If we're "recording" but
    // no audio chunks have arrived in 30s, the audio pipeline is wedged (mic
    // disconnected, HAL deadlocked, SoX child hung) and we should reset.
    // SoX produces zero-amplitude chunks even during silence, so this only
    // fires when the audio is actually broken — not when the user pauses.
    //
    // For the browser MediaRecorder path (Windows), audio buffers stay in the
    // renderer, so we can't observe progress from main. We skip the check
    // for that path — there's no hard duration limit, so a runaway browser
    // recording will only stop when the user releases the key or double-taps
    // again to exit latch mode.
    //
    // v1.2.7 — there is NO max duration. Latch mode + active mic = keep
    // recording forever, until the user stops it or audio actually breaks.
    if (isBackgroundRecording && lastAudioChunkAt > 0) {
      const sinceLastChunk = Date.now() - lastAudioChunkAt;
      if (sinceLastChunk > NO_PROGRESS_MS) {
        const elapsed = Date.now() - recordingStartedAt;
        console.error(`[Watchdog] No audio chunks for ${sinceLastChunk}ms — force-resetting`);
        writeDiagnostic('stuck-recording', { elapsedMs: elapsed, sinceLastChunkMs: sinceLastChunk, reason: 'no-audio-progress' });
        forceResetRecordingState('watchdog-no-progress');
        try {
          sendPillState('error', { message: 'Audio input lost — please try again' });
        } catch (_) {}
      }
    }
  }, 5000);
}

function stopRecordingWatchdog() {
  if (recordingWatchdogInterval) {
    clearInterval(recordingWatchdogInterval);
    recordingWatchdogInterval = null;
  }
}

// ============================================
// AUTH (AWS Cognito) — config-driven, DORMANT until config.json has cognito_* keys.
// When unconfigured every helper no-ops and the app behaves exactly as v1.
// ============================================
let loginWindow = null;
let authTokens = null;     // { idToken, accessToken, refreshToken } cached in memory
let pkceVerifier = null;   // current OAuth PKCE code_verifier

function loadAppConfig() {
  try {
    // Read from the same writable data dir the backend uses (userData when packaged)
    return JSON.parse(fs.readFileSync(path.join(getDataDir(), 'config.json'), 'utf8'));
  } catch (_) {
    return {};
  }
}

function getAuthConfig() {
  const c = loadAppConfig();
  return {
    domain:      c.cognito_domain || '',        // e.g. myapp.auth.us-east-1.amazoncognito.com
    clientId:    c.cognito_client_id || '',
    region:      c.cognito_region || c.aws_region || 'us-east-1',
    userPoolId:  c.cognito_user_pool_id || '',
    redirectUri: 'echo://callback',
  };
}

function isAuthConfigured() {
  const a = getAuthConfig();
  return !!(a.domain && a.clientId);
}

// Local test login (email/password against DynamoDB Local). Active only when
// config has "auth_mode":"local" and Cognito is NOT configured.
function localAuthEnabled() {
  const c = loadAppConfig();
  return (c.auth_mode || '').toLowerCase() === 'local' && !c.cognito_user_pool_id;
}

// Either real Cognito or the local test login should gate the app behind a login.
function authGateActive() {
  return isAuthConfigured() || localAuthEnabled();
}

const tokensFile = () => path.join(app.getPath('userData'), 'tokens.bin');

function storeTokens(tokens) {
  authTokens = tokens;
  try {
    if (safeStorage.isEncryptionAvailable()) {
      fs.writeFileSync(tokensFile(), safeStorage.encryptString(JSON.stringify(tokens)));
    } else {
      fs.writeFileSync(tokensFile(), JSON.stringify(tokens), 'utf8');
    }
  } catch (e) {
    console.error('[Auth] storeTokens failed:', e.message);
  }
}

function loadTokens() {
  if (authTokens) return authTokens;
  try {
    const raw = fs.readFileSync(tokensFile());
    const json = safeStorage.isEncryptionAvailable() ? safeStorage.decryptString(raw) : raw.toString('utf8');
    authTokens = JSON.parse(json);
    return authTokens;
  } catch (_) {
    return null;
  }
}

function clearTokens() {
  authTokens = null;
  try { fs.unlinkSync(tokensFile()); } catch (_) {}
}

function getAuthToken() {
  const t = loadTokens();
  return t ? (t.idToken || '') : '';
}

function decodeJwtExp(token) {
  try {
    const payload = JSON.parse(Buffer.from(token.split('.')[1], 'base64').toString('utf8'));
    return typeof payload.exp === 'number' ? payload.exp : 0;
  } catch (_) { return 0; }
}

// Resolve a non-expired idToken, transparently refreshing via the Cognito
// refresh-token grant when the current one is within 2 min of expiry. Falls back
// to whatever is cached if refresh fails or no refresh token exists. Returns ''
// when logged out / unconfigured, so callers behave exactly as v1.
function ensureValidToken() {
  const t = loadTokens();
  if (!t || !t.idToken) return Promise.resolve('');
  const exp = decodeJwtExp(t.idToken);
  const stillValid = exp && (exp - Math.floor(Date.now() / 1000) > 120);
  if (stillValid || !t.refreshToken) return Promise.resolve(t.idToken);
  return refreshTokens(t.refreshToken).then((fresh) => fresh || t.idToken);
}

// Exchange a refresh token for a fresh id/access token. Cognito does NOT return a
// new refresh token on this grant, so the existing one is preserved. Resolves to
// the new idToken, or '' on any failure.
function refreshTokens(refreshToken) {
  const a = getAuthConfig();
  if (!a.domain || !a.clientId || !refreshToken) return Promise.resolve('');
  const body = new URLSearchParams({
    grant_type: 'refresh_token',
    client_id: a.clientId,
    refresh_token: refreshToken,
  }).toString();
  return new Promise((resolve) => {
    const req = https.request(
      { hostname: a.domain, path: '/oauth2/token', method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded', 'Content-Length': Buffer.byteLength(body) } },
      (res) => {
        let data = '';
        res.on('data', (c) => { data += c; });
        res.on('end', () => {
          try {
            const r = JSON.parse(data);
            if (r.id_token) {
              storeTokens({ idToken: r.id_token, accessToken: r.access_token, refreshToken });
              broadcastAuthState();
              console.log('[Auth] token refreshed');
              resolve(r.id_token);
            } else {
              console.error('[Auth] refresh returned no id_token:', data);
              resolve('');
            }
          } catch (e) { console.error('[Auth] refresh parse failed:', e.message); resolve(''); }
        });
      }
    );
    req.on('error', (e) => { console.error('[Auth] refresh failed:', e.message); resolve(''); });
    req.write(body);
    req.end();
  });
}

function base64url(buf) {
  return buf.toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

function startGoogleOAuth(identityProvider) {
  const a = getAuthConfig();
  if (!a.domain || !a.clientId) { console.warn('[Auth] OAuth not configured'); return; }
  pkceVerifier = base64url(crypto.randomBytes(32));
  const challenge = base64url(crypto.createHash('sha256').update(pkceVerifier).digest());
  const params = new URLSearchParams({
    response_type: 'code',
    client_id: a.clientId,
    redirect_uri: a.redirectUri,
    scope: 'openid email profile',
    code_challenge_method: 'S256',
    code_challenge: challenge,
  });
  if (identityProvider) params.set('identity_provider', identityProvider);
  shell.openExternal(`https://${a.domain}/oauth2/authorize?${params.toString()}`);
}

function handleOAuthCallback(rawUrl) {
  try {
    const code = new URL(rawUrl).searchParams.get('code');
    if (code) exchangeCodeForTokens(code);
  } catch (e) {
    console.error('[Auth] bad callback url:', e.message);
  }
}

function exchangeCodeForTokens(code) {
  const a = getAuthConfig();
  const body = new URLSearchParams({
    grant_type: 'authorization_code',
    client_id: a.clientId,
    code,
    redirect_uri: a.redirectUri,
    code_verifier: pkceVerifier || '',
  }).toString();
  const req = https.request(
    { hostname: a.domain, path: '/oauth2/token', method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded', 'Content-Length': Buffer.byteLength(body) } },
    (res) => {
      let data = '';
      res.on('data', (c) => { data += c; });
      res.on('end', () => {
        try {
          const t = JSON.parse(data);
          if (t.id_token) {
            completeLogin({ idToken: t.id_token, accessToken: t.access_token, refreshToken: t.refresh_token });
          } else {
            console.error('[Auth] token exchange returned no id_token:', data);
          }
        } catch (e) { console.error('[Auth] token parse failed:', e.message); }
      });
    }
  );
  req.on('error', (e) => console.error('[Auth] token exchange failed:', e.message));
  req.write(body);
  req.end();
}

function completeLogin(tokens) {
  storeTokens(tokens);
  if (loginWindow && !loginWindow.isDestroyed()) { loginWindow.close(); loginWindow = null; }
  // On successful login show BOTH the pill (always-on dictation) and the dashboard.
  if (!pillWindow || pillWindow.isDestroyed()) createPillWindow();
  if (!mainWindow || mainWindow.isDestroyed()) createMainWindow();
  broadcastAuthState();
  refreshTrayMenu();
}

function broadcastAuthState() {
  const t = loadTokens();
  let email = '';
  if (t && t.idToken) {
    try {
      email = JSON.parse(Buffer.from(t.idToken.split('.')[1], 'base64').toString('utf8')).email || '';
    } catch (_) {}
  }
  const state = { loggedIn: !!(t && t.idToken), email };
  [pillWindow, mainWindow, loginWindow].forEach((w) => {
    if (w && !w.isDestroyed()) w.webContents.send('auth-state', state);
  });
}

function createLoginWindow() {
  if (loginWindow && !loginWindow.isDestroyed()) { loginWindow.focus(); return; }
  loginWindow = new BrowserWindow({
    width: 420,
    height: 580,
    resizable: false,
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
    },
    titleBarStyle: 'hidden',
  });
  loginWindow.loadURL(`http://127.0.0.1:${serverPort}/#/login`);
  loginWindow.on('closed', () => { loginWindow = null; });
}

// Push-to-talk key: Right Option on Mac, Right Alt on Windows.
// UiohookKey.AltRight = 3640 on both platforms (cross-platform uiohook constant).
const PUSH_TO_TALK_KEY_CODE = UiohookKey.AltRight;

// SoX availability + browser recording fallback state
let soxAvailable = false;       // set once at startup by checkSoxAvailable()
let soxBinaryPath = null;       // resolved absolute path to the sox binary in use (bundled or system)
let isBrowserRecording = false; // true when active recording is using browser MediaRecorder (no SoX)

// v1.2.11 — Browser-fallback (Mac) processing watchdog.
// The native (Windows) path resolves to a terminal pill state inside
// finishRecording(); the browser path instead hands off to the renderer and
// waits for a 'transcription-complete' IPC that may never arrive (renderer
// crash, getUserMedia denied, fetch died). Without a timeout the pill is stuck
// on 'processing' forever (and 'processing' has no renderer-side auto-reset).
// We arm this when the browser path enters 'processing' and clear it the moment
// the result arrives or any reset happens. 5 min is generous for a normal
// dictation upload+transcribe while still guaranteeing eventual recovery.
let browserProcessingTimeout = null;
const BROWSER_PROCESSING_MAX_MS = 300_000;

function clearBrowserProcessingTimeout() {
  if (browserProcessingTimeout) {
    clearTimeout(browserProcessingTimeout);
    browserProcessingTimeout = null;
  }
}

function armBrowserProcessingTimeout() {
  clearBrowserProcessingTimeout();
  browserProcessingTimeout = setTimeout(() => {
    browserProcessingTimeout = null;
    writeDiagnostic('browser-processing-timeout', { maxMs: BROWSER_PROCESSING_MAX_MS });
    console.error('[Recording] Browser transcription never returned — force-resetting');
    forceResetRecordingState('browser-processing-timeout');
    try { sendPillState('error', { message: 'Transcription timed out — please try again' }); } catch (_) {}
  }, BROWSER_PROCESSING_MAX_MS);
}

// v1.2.10 — Resolve the bundled SoX binary, now per-platform.
// History: v1.2.7 bundled SoX for Windows only (root cause of the long-running
// "pill doesn't appear" / "Echo unreliable" reports — without SoX every
// recording silently fell into the brittle browser-MediaRecorder fallback).
// v1.2.10 extends the bundle to Mac + Linux for the same reasons:
//   - Finder-launched Electron on Mac does NOT inherit the user's shell PATH,
//     so /usr/local/bin/sox and /opt/homebrew/bin/sox are invisible to spawn()
//     even when the user has `brew install sox`.
//   - Linux .deb declares `sox` as a Depends, but AppImage has no dep system.
// Sources at build time:
//   sox-bundle/win/sox.exe      → resources/sox/sox.exe   (win.extraResources)
//   sox-bundle/mac/sox          → resources/sox/sox       (mac.extraResources)
//   sox-bundle/linux/sox        → resources/sox/sox       (linux.extraResources)
// Dev: also checks the platform subdir, then the legacy flat path for back-compat.
function resolveBundledSoxPath() {
  const exeName = process.platform === 'win32' ? 'sox.exe' : 'sox';
  const platformDir = process.platform === 'darwin' ? 'mac'
                    : process.platform === 'win32'  ? 'win'
                    : 'linux';
  const candidates = [];
  // Packaged: extraResources maps the per-platform subdir to `resources/sox/`
  if (process.resourcesPath) candidates.push(path.join(process.resourcesPath, 'sox', exeName));
  // Dev: per-platform staging dir
  candidates.push(path.join(__dirname, '..', 'sox-bundle', platformDir, exeName));
  // Dev: legacy flat path (pre-v1.2.10 layout) — back-compat for anyone with
  // an older sox-bundle/ checkout.
  candidates.push(path.join(__dirname, '..', 'sox-bundle', exeName));
  for (const candidate of candidates) {
    try { if (fs.existsSync(candidate)) return candidate; } catch (_) {}
  }
  return null;
}

function checkSoxAvailable() {
  return new Promise((resolve) => {
    // v1.2.8 — Windows SoX needs AUDIODRIVER=waveaudio in its environment to
    // know which audio device backend to use. Without it, `sox -d` aborts
    // immediately with "Sorry, there is no default audio device configured"
    // and node-record-lpcm16 emits stream-error within ~60ms of spawning.
    // SoX inherits the parent's env, so setting it once on process.env here
    // applies to every spawn going forward. Harmless no-op on Mac/Linux,
    // where SoX uses coreaudio / alsa by default.
    if (process.platform === 'win32' && !process.env.AUDIODRIVER) {
      process.env.AUDIODRIVER = 'waveaudio';
    }
    const bundled = resolveBundledSoxPath();
    if (bundled) {
      // v1.2.11 — Mac pre-flight for the BUNDLED sox, mirroring the backend
      // pre-flight at startFlaskServer(). The unsigned .dmg stamps
      // com.apple.quarantine on every file it ships, and the exec bit can be
      // lost in packaging. When that happens `exec("sox --version")` below
      // FAILS, soxAvailable becomes false, and Mac silently drops into the
      // fragile browser-MediaRecorder fallback — the real root cause behind
      // "Mac state management is broken / recording suddenly stops." Stripping
      // quarantine + restoring +x lets Mac use the SAME robust native path
      // Windows uses. Both ops are idempotent no-ops on later launches and on
      // dev checkouts. Harmless/skipped on Windows.
      if (process.platform === 'darwin') {
        try {
          const bundledDir = path.dirname(bundled);
          execSync(`xattr -dr com.apple.quarantine "${bundledDir}"`, { stdio: 'ignore' });
        } catch (_) {}
        try { execSync(`chmod +x "${bundled}"`, { stdio: 'ignore' }); } catch (_) {}
      }
      // Prepend the bundled binary's directory to PATH so node-record-lpcm16's
      // hardcoded `spawn('sox', ...)` (recorders/sox.js) resolves to OUR binary,
      // not a stale or missing system install.
      const bundleDir = path.dirname(bundled);
      const sep = process.platform === 'win32' ? ';' : ':';
      if (!String(process.env.PATH || '').split(sep).includes(bundleDir)) {
        process.env.PATH = bundleDir + sep + (process.env.PATH || '');
      }
      // Sanity-check by invoking with absolute path (no PATH dependency).
      exec(`"${bundled}" --version`, (err) => {
        soxAvailable = !err;
        soxBinaryPath = soxAvailable ? bundled : null;
        console.log(soxAvailable
          ? `[Recording] Bundled SoX found at ${bundled}`
          : `[Recording] Bundled SoX at ${bundled} failed to run — falling back to system PATH`);
        if (!soxAvailable) {
          // Bundled binary present but unrunnable — try system PATH as a last resort.
          exec('sox --version', (err2) => {
            soxAvailable = !err2;
            soxBinaryPath = soxAvailable ? 'sox' : null;
            try { writeDiagnostic('sox-check', { bundledPath: bundled, bundledOk: false, systemPathOk: soxAvailable }); } catch (_) {}
            resolve(soxAvailable);
          });
          return;
        }
        try { writeDiagnostic('sox-check', { bundledPath: bundled, bundledOk: true }); } catch (_) {}
        resolve(soxAvailable);
      });
      return;
    }
    // No bundled binary (e.g. Mac dev without a bundle). Fall back to system PATH.
    exec('sox --version', (err) => {
      soxAvailable = !err;
      soxBinaryPath = soxAvailable ? 'sox' : null;
      console.log(soxAvailable
        ? '[Recording] SoX found on system PATH'
        : '[Recording] SoX not found - will use browser MediaRecorder fallback');
      try { writeDiagnostic('sox-check', { bundledPath: null, systemPathOk: soxAvailable }); } catch (_) {}
      resolve(soxAvailable);
    });
  });
}

// ============================================
// DOUBLE-TAP LATCH MODE (WIN-10)
// Hold ≥400ms = push-to-talk (release stops).
// Quick double-tap = latch: recording continues until next key press.
// ============================================
const SHORT_HOLD_MAX_MS = 400;   // hold < this is a "tap", not PTT
const DOUBLE_TAP_GAP_MS = 400;   // max gap between tap-up and tap-down to count as double-tap
let isLatchMode = false;          // true while recording in latched (free-speak) mode
let pendingDoubleTap = null;      // setTimeout handle waiting for a second tap
let lastTapDownTime = 0;          // timestamp of the most recent key-down

// Temporary file for audio recording
const TEMP_AUDIO_FILE = path.join(app.getPath('temp'), 'whisper_recording.wav');

// ============================================
// BACKGROUND AUDIO RECORDING FUNCTIONS
// ============================================

/**
 * Start background audio recording using SoX (rec command)
 * This does NOT require window focus!
 */
function startBackgroundRecording() {
  return new Promise((resolve, reject) => {
    if (isBackgroundRecording) {
      console.log('[Recording] Already recording, ignoring start request');
      resolve(false);
      return;
    }

    if (!record) {
      console.error('[Recording] node-record-lpcm16 not available');
      reject(new Error('Recording library not available'));
      return;
    }

    audioChunks = [];
    console.log('[Recording] Starting background recording with SoX...');

    try {
      // Use node-record-lpcm16 with SoX
      // Note: audioType 'raw' gives us raw PCM data which we'll wrap with WAV headers
      audioRecorder = record.record({
        sampleRate: 16000,
        channels: 1,
        threshold: 0,  // Start recording immediately
        endOnSilence: false,  // Don't stop on silence
        silence: '10.0',  // Long silence threshold
        recorder: 'sox',  // Use SoX (rec command) - most reliable on macOS
        audioType: 'raw'  // Get raw PCM data - we'll add WAV headers ourselves
      });

      const audioStream = audioRecorder.stream();

      // BUG-11: a recorder binary that fails to spawn (e.g. SoX not installed)
      // emits 'error' on the child process. Unhandled, it crashes the whole main
      // process. Catch it and surface a friendly message instead of a fatal dialog.
      if (audioRecorder.process) {
        audioRecorder.process.on('error', (err) => {
          console.error('[Recording] Recorder failed to spawn:', err);
          // v1.2.5: route through forceResetRecordingState so the SoX PID is
          // SIGKILL'd even if the error came from a partial spawn that left
          // the child alive but unable to stream.
          forceResetRecordingState('recorder-process-error');
          let soxInstall = 'https://sox.sourceforge.net';
          if (process.platform === 'darwin') soxInstall = 'brew install sox';
          else if (process.platform === 'win32') soxInstall = 'choco install sox';
          else if (process.platform === 'linux') soxInstall = 'sudo apt install sox';

          const friendly = (err && err.code === 'ENOENT')
            ? `SoX is required for recording. Install it: ${soxInstall}`
            : `Recorder error: ${err && err.message ? err.message : err}`;
          notifyRecordingError(friendly);
        });
      }

      audioStream.on('data', (chunk) => {
        audioChunks.push(chunk);
        // v1.2.6 — record the most recent chunk arrival time so the watchdog's
        // progress-based stuck-detection knows audio is flowing. SoX produces
        // chunks even during silence, so this stays fresh during normal use.
        lastAudioChunkAt = Date.now();
        // Log periodically to show recording is working
        if (audioChunks.length % 10 === 0) {
          const totalBytes = audioChunks.reduce((sum, c) => sum + c.length, 0);
          console.log(`[Recording] Received ${audioChunks.length} chunks, ${totalBytes} bytes total`);
        }
      });

      audioStream.on('error', (err) => {
        console.error('[Recording] Audio stream error:', err);
        // v1.2.9 — Distinguish "we asked SoX to stop" from "SoX died on us."
        // When the user releases the hotkey, stopBackgroundRecording sends
        // SIGTERM to SoX, which causes node-record-lpcm16 to emit 'error' on
        // the stream because SoX exited with a non-zero code. That's NORMAL.
        // The pre-v1.2.9 handler unconditionally called forceResetRecordingState,
        // which wiped audioChunks BEFORE stopBackgroundRecording could read
        // them — so every recording silently came back as "No speech detected".
        // Only treat the error as a real failure if we weren't already in the
        // middle of a normal stop sequence.
        if (isStoppingRecording) {
          writeDiagnostic('audio-stream-error-during-stop', { message: String(err && err.message) });
          console.log('[Recording] Stream error during normal stop — expected, ignoring');
          return;
        }
        // v1.2.5: previously only cleared isBackgroundRecording, leaving the
        // SoX child process orphaned and holding the audio HAL. Now we
        // SIGKILL the child and clear all related state.
        forceResetRecordingState('audio-stream-error');
      });

      audioStream.on('end', () => {
        console.log('[Recording] Audio stream ended');
        // v1.2.10 — If SoX emits 'end' without us asking (mic disconnect that
        // exits cleanly, or some platform-specific SoX exit that doesn't
        // emit 'error'), the pre-v1.2.10 handler logged and did nothing —
        // leaving isBackgroundRecording=true forever until the 30s no-progress
        // watchdog noticed. Treat unexpected 'end' the same as 'error':
        // force-reset state + surface a visible error so the pill doesn't
        // silently stay in 'recording'. Normal SIGTERM-driven stops are
        // gated by isStoppingRecording (same flag the error handler checks).
        if (isStoppingRecording) return;
        writeDiagnostic('audio-stream-unexpected-end', {});
        console.warn('[Recording] Stream ended unexpectedly — treating as error');
        forceResetRecordingState('audio-stream-end');
        try {
          sendPillState('error', { message: 'Audio input lost — please try again' });
        } catch (_) {}
      });

      isBackgroundRecording = true;
      console.log('[Recording] Background recording started successfully');
      resolve(true);
    } catch (err) {
      console.error('[Recording] Failed to start recording:', err);
      isBackgroundRecording = false;
      reject(err);
    }
  });
}

/**
 * Create WAV header for raw PCM data
 * @param {number} dataLength - Length of the raw PCM data in bytes
 * @param {number} sampleRate - Sample rate (e.g., 16000)
 * @param {number} channels - Number of channels (1 for mono)
 * @param {number} bitsPerSample - Bits per sample (16 for 16-bit audio)
 * @returns {Buffer} - WAV header buffer
 */
function createWavHeader(dataLength, sampleRate = 16000, channels = 1, bitsPerSample = 16) {
  const byteRate = sampleRate * channels * bitsPerSample / 8;
  const blockAlign = channels * bitsPerSample / 8;
  const header = Buffer.alloc(44);
  
  // RIFF chunk descriptor
  header.write('RIFF', 0);
  header.writeUInt32LE(36 + dataLength, 4); // File size - 8
  header.write('WAVE', 8);
  
  // fmt sub-chunk
  header.write('fmt ', 12);
  header.writeUInt32LE(16, 16); // Subchunk1Size (16 for PCM)
  header.writeUInt16LE(1, 20); // AudioFormat (1 for PCM)
  header.writeUInt16LE(channels, 22); // NumChannels
  header.writeUInt32LE(sampleRate, 24); // SampleRate
  header.writeUInt32LE(byteRate, 28); // ByteRate
  header.writeUInt16LE(blockAlign, 32); // BlockAlign
  header.writeUInt16LE(bitsPerSample, 34); // BitsPerSample
  
  // data sub-chunk
  header.write('data', 36);
  header.writeUInt32LE(dataLength, 40); // Subchunk2Size
  
  return header;
}

/**
 * Stop background recording and return audio buffer with proper WAV headers.
 *
 * v1.2.5 — SIGKILL fallback. Previously, audioRecorder.stop() was called
 * without confirming that the SoX `rec` child actually exited. If it didn't
 * (e.g. the audio HAL device wedged it), the process would stay alive holding
 * the microphone, causing other macOS apps that needed audio to hang. Now we:
 *   1. Capture the SoX PID before signalling stop.
 *   2. Call audioRecorder.stop() (best-effort SIGTERM through node-record-lpcm16).
 *   3. Poll for up to 2s waiting for the PID to exit.
 *   4. If still alive after 2s, SIGKILL it directly via process.kill.
 * This guarantees the audio HAL is released within a bounded time.
 */
async function stopBackgroundRecording() {
  if (!isBackgroundRecording || !audioRecorder) {
    console.log('[Recording] No active recording to stop');
    return null;
  }

  // Capture the SoX PID up front so we can SIGKILL it even if audioRecorder is
  // mutated by an error handler before we get there.
  const soxPid = (audioRecorder && audioRecorder.process && audioRecorder.process.pid) || null;

  // v1.2.9 — Snapshot the audioChunks array reference BEFORE any awaits.
  // If a SoX-exit triggers the stream-error handler despite the flag below
  // (race on platforms where the error fires before the flag is checked),
  // `audioChunks = []` only rebinds the variable to a new empty array — our
  // snapshot still holds the captured data.
  const capturedChunks = audioChunks;
  isStoppingRecording = true; // tells audioStream.on('error') this exit was intentional

  try {
    console.log('[Recording] Stopping audio recorder...');
    try { audioRecorder.stop(); } catch (e) {
      console.error('[Recording] audioRecorder.stop() threw:', e && e.message);
      writeDiagnostic('sox-stop-threw', { message: String(e && e.message), soxPid });
    }
    isBackgroundRecording = false;

    // Wait briefly for buffered chunks to arrive AND for the rec process to exit.
    await new Promise((r) => setTimeout(r, 100));

    if (soxPid && isProcessAlive(soxPid)) {
      console.log(`[Recording] SoX pid ${soxPid} still alive after stop; waiting up to 2s...`);
      const exited = await waitForProcessExit(soxPid, 2000);
      if (!exited) {
        console.error(`[Recording] SoX pid ${soxPid} did not exit — SIGKILL`);
        writeDiagnostic('sox-sigkill', { soxPid });
        try { process.kill(soxPid, 'SIGKILL'); } catch (_) {}
        // Give the OS a moment to release the audio HAL.
        await new Promise((r) => setTimeout(r, 100));
      }
    }

    if (capturedChunks.length === 0) {
      console.log('[Recording] No audio chunks received');
      audioRecorder = null;
      audioChunks = [];
      isStoppingRecording = false;
      return null;
    }

    console.log(`[Recording] Processing ${capturedChunks.length} audio chunks`);

    // Combine all chunks into a single buffer (raw PCM data)
    const rawPcmData = Buffer.concat(capturedChunks);
    console.log(`[Recording] Raw PCM data size: ${rawPcmData.length} bytes`);

    // Create WAV header for the raw PCM data
    // node-record-lpcm16 with SoX outputs 16-bit signed PCM at the specified sample rate
    const wavHeader = createWavHeader(rawPcmData.length, 16000, 1, 16);

    // Combine header and PCM data to create a valid WAV file
    const wavBuffer = Buffer.concat([wavHeader, rawPcmData]);
    console.log(`[Recording] WAV buffer size: ${wavBuffer.length} bytes (with 44-byte header)`);

    // Clear chunks for next recording
    audioChunks = [];
    audioRecorder = null;
    isStoppingRecording = false;

    return wavBuffer;
  } catch (err) {
    console.error('[Recording] Error stopping recording:', err);
    // Defensive SIGKILL in the catch path too.
    if (soxPid && isProcessAlive(soxPid)) {
      try { process.kill(soxPid, 'SIGKILL'); } catch (_) {}
    }
    isBackgroundRecording = false;
    audioChunks = [];
    audioRecorder = null;
    isStoppingRecording = false;
    throw err;
  }
}

/**
 * Send audio to Flask API for transcription (from main process)
 */
async function transcribeAudioFromMain(audioBuffer, model = 'whisper-large-v3-turbo') {
  // Refresh the Cognito token if it's about to expire so push-to-talk (the hot
  // path) never fails with a 401 mid-session. No-ops when auth is unconfigured.
  const authToken = await ensureValidToken();
  return new Promise((resolve, reject) => {
    console.log(`[Transcribe] Sending ${audioBuffer.length} bytes to Flask API...`);
    
    // Create multipart form data manually
    const boundary = '----WebKitFormBoundary' + Math.random().toString(36).substring(2);
    
    // Build the multipart body
    const bodyParts = [];
    
    // Audio file part
    bodyParts.push(Buffer.from(
      `--${boundary}\r\n` +
      `Content-Disposition: form-data; name="audio"; filename="recording.wav"\r\n` +
      `Content-Type: audio/wav\r\n\r\n`
    ));
    bodyParts.push(audioBuffer);
    bodyParts.push(Buffer.from('\r\n'));
    
    // Model part
    bodyParts.push(Buffer.from(
      `--${boundary}\r\n` +
      `Content-Disposition: form-data; name="model"\r\n\r\n` +
      `${model}\r\n`
    ));
    
    // End boundary
    bodyParts.push(Buffer.from(`--${boundary}--\r\n`));
    
    const body = Buffer.concat(bodyParts);
    console.log(`[Transcribe] Total request body size: ${body.length} bytes`);
    
    const options = {
      hostname: '127.0.0.1',  // Use IPv4 explicitly to avoid IPv6 issues
      port: serverPort,
      path: '/api/transcribe',
      method: 'POST',
      headers: {
        'Content-Type': `multipart/form-data; boundary=${boundary}`,
        'Content-Length': body.length,
        'Authorization': `Bearer ${authToken}`
      }
    };
    
    const req = http.request(options, (res) => {
      let data = '';
      console.log(`[Transcribe] Response status: ${res.statusCode}`);
      
      res.on('data', (chunk) => {
        data += chunk;
      });
      
      res.on('end', () => {
        try {
          console.log(`[Transcribe] Response data: ${data.substring(0, 200)}...`);
          const response = JSON.parse(data);
          if (response.success && response.text) {
            console.log(`[Transcribe] Success! Text: "${response.text.substring(0, 50)}..."`);
            resolve(response.text);
          } else {
            console.error(`[Transcribe] Failed: ${response.error || 'Unknown error'}`);
            reject(new Error(response.error || 'Transcription failed'));
          }
        } catch (e) {
          console.error(`[Transcribe] Parse error: ${e.message}`);
          reject(e);
        }
      });
    });
    
    req.on('error', (err) => {
      console.error(`[Transcribe] Request error: ${err.message}`);
      reject(err);
    });

    // v1.2.10 — Scale timeout with audio length. The pre-v1.2.10 fixed 30s cap
    // started biting once v1.2.7 removed the recording duration ceiling — a
    // 10-minute dictation can take >30s just for the upload + Groq Whisper
    // round-trip and the timeout would silently destroy the request.
    //
    // Estimate audio seconds from buffer size: 16 kHz, mono, 16-bit = 32000
    // bytes/sec; subtract the 44-byte WAV header. Allow 6 seconds per audio
    // second (generous for slow uploads + Groq processing), with a 30-second
    // floor for tiny clips and a 10-minute ceiling so a genuinely-broken
    // request still terminates eventually.
    const audioSeconds = Math.max(0, (audioBuffer.length - 44) / 32000);
    const timeoutMs = Math.min(600_000, Math.max(30_000, Math.ceil(audioSeconds * 6_000)));
    console.log(`[Transcribe] Audio ~${audioSeconds.toFixed(1)}s, timeout ${timeoutMs}ms`);
    req.setTimeout(timeoutMs, () => {
      console.error(`[Transcribe] Request timed out after ${timeoutMs}ms`);
      req.destroy(new Error('Request timed out — please try again'));
    });

    req.write(body);
    req.end();
  });
}

// ============================================
// CROSS-PLATFORM FOCUS CAPTURE + AUTO-PASTE (WIN-01 / WIN-02)
// Mac:     osascript bundle-ID approach (existing behaviour)
// Windows: PowerShell Win32 GetForegroundWindow / SetForegroundWindow + SendKeys
// Both return/accept an opaque { type, value } focus-target handle.
// ============================================

// ============================================
// CROSS-PLATFORM FOCUS CAPTURE + AUTO-PASTE (WIN-01 / WIN-02)
//
// Mac:     osascript bundle-ID — activate app then keystroke Cmd+V
// Windows: VBScript WScript.Shell.SendKeys — sends Ctrl+V to the active window.
//          The pill is focusable:false so the user's app retains focus throughout
//          recording; no HWND tracking needed.
// ============================================

// Windows: write a tiny VBScript paste helper once at startup.
// VBScript via wscript.exe starts in ~50ms vs ~400ms for PowerShell.
let WIN_PASTE_VBS = null;
if (process.platform === 'win32') {
  WIN_PASTE_VBS = path.join(os.tmpdir(), 'wf_paste.vbs');
  try {
    fs.writeFileSync(WIN_PASTE_VBS,
      'Set wsh = CreateObject("WScript.Shell")\nwsh.SendKeys "^v"');
    console.log('[Paste] Windows paste helper written to', WIN_PASTE_VBS);
  } catch (e) {
    console.error('[Paste] Could not write paste helper:', e.message);
  }
}

// Capture the currently focused window before recording starts.
// Mac: returns { type:'bundle', value: bundleId }
// Win: returns { type:'win-sendkeys', value:'1' } — a sentinel (no HWND needed)
async function getPlatformFocusTarget() {
  try {
    if (process.platform === 'darwin') {
      // v1.2.5: hard 3s timeout on the osascript call. Previously this had NO
      // timeout — if System Events was busy (VoiceOver active, Accessibility
      // dialog open, AppleScript daemon hung), this would block forever and
      // every recording would hang in state="recording". The 3s cap means a
      // wedged AppleScript daemon costs us the focus-back feature for one
      // recording, not the entire app.
      try {
        const { stdout } = await execWithTimeout(
          `osascript -e 'tell application "System Events" to get bundle identifier of first application process whose frontmost is true'`,
          3000
        );
        return { type: 'bundle', value: stdout.trim() };
      } catch (e) {
        writeDiagnostic('osascript-timeout', { call: 'frontmost-bundle', message: String(e && e.message) });
        return null;
      }
    }
    if (process.platform === 'win32') {
      // Pill is focusable:false — user's app stays focused. No HWND tracking needed.
      return { type: 'win-sendkeys', value: '1' };
    }
    if (process.platform === 'linux') {
      // Like Windows, the pill is focusable:false so the active window remains focused.
      return { type: 'linux-xdotool', value: '1' };
    }
  } catch (_) {}
  return null;
}

// Restore focus to the previously captured window and simulate paste (Cmd+V / Ctrl+V).
// Returns true if the paste command was dispatched without error.
async function platformPaste(focusTarget) {
  if (!focusTarget) return false;

  if (focusTarget.type === 'bundle') {
    // macOS: activate app by bundle ID, then keystroke Cmd+V
    //
    // v1.2.5: both osascript calls now have 3s timeouts and are awaited
    // explicitly. The previous implementation used nested setTimeout + exec
    // callbacks with NO timeout — if either osascript hung (System Events busy,
    // target app unresponsive), the entire paste chain would hang AND the
    // AppleScript daemon would stay held, freezing other apps using it.
    await new Promise((r) => setTimeout(r, 200));
    try {
      await execWithTimeout(
        `osascript -e 'tell application id "${focusTarget.value}" to activate'`,
        3000
      );
    } catch (e) {
      writeDiagnostic('osascript-timeout', { call: 'activate', message: String(e && e.message) });
      // Best-effort fallback (also timeout-protected).
      try { await execWithTimeout(`open -b "${focusTarget.value}"`, 3000); } catch (_) {}
    }
    await new Promise((r) => setTimeout(r, 300));
    try {
      await execWithTimeout(
        `osascript -e 'tell application "System Events" to keystroke "v" using command down'`,
        3000
      );
      return true;
    } catch (e) {
      writeDiagnostic('osascript-timeout', { call: 'keystroke', message: String(e && e.message) });
      return false;
    }
  }

  if (focusTarget.type === 'win-sendkeys') {
    // Windows: ask Flask to fire Ctrl+V via ctypes (keybd_event).
    // Flask runs in the same user session so it can hit the foreground window.
    return new Promise((resolve) => {
      const http = require('http');
      const body = '{}';
      const req = http.request(
        { host: '127.0.0.1', port: serverPort, path: '/api/paste', method: 'POST',
          headers: { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(body),
                     'Authorization': `Bearer ${getAuthToken()}` } },
        (res) => {
          let data = '';
          res.on('data', (chunk) => { data += chunk; });
          res.on('end', () => {
            try { resolve(JSON.parse(data).success === true); } catch { resolve(false); }
          });
        }
      );
      req.on('error', (e) => { console.error('[Paste] /api/paste request failed:', e.message); resolve(false); });
      req.write(body);
      req.end();
    });
  }

  if (focusTarget.type === 'linux-xdotool') {
    // Linux: use xdotool to simulate Ctrl+V.
    // User must have xdotool installed (sudo apt install xdotool).
    return new Promise((resolve) => {
      exec('xdotool key ctrl+v', (err) => {
        if (err) {
          console.error('[Paste] xdotool failed:', err.message);
          resolve(false);
        } else {
          resolve(true);
        }
      });
    });
  }

  return false;
}

// Port file path
const PORT_FILE = 'server_port.txt';
// PID file for the Flask child — lets us reap an orphan left by a crashed run (BUG-21)
const FLASK_PID_FILE = 'flask.pid';
const ELECTRON_PID_FILE = 'electron.pid';

// Writable data directory shared with the backend. Dev: the project dir (app.py
// writes here by default, so local behaviour is unchanged). Packaged: the
// per-user userData folder, since the install dir is read-only. The backend is
// told this path via the ECHO_DATA_DIR env var so both sides agree.
function getDataDir() {
  return app.isPackaged ? app.getPath('userData') : path.join(__dirname, '..');
}

/**
 * Kill a Flask process orphaned by a previous crash (BUG-21).
 * If we exited uncleanly (e.g. force-quit), the old Flask can keep holding a port.
 * On launch we read flask.pid and terminate that process before starting fresh.
 */
function killStaleFlask(projectRoot) {
  const pidFilePath = path.join(projectRoot, FLASK_PID_FILE);
  try {
    if (!fs.existsSync(pidFilePath)) return;
    const pid = parseInt(fs.readFileSync(pidFilePath, 'utf8').trim(), 10);
    if (pid && pid > 0 && pid !== process.pid) {
      try {
        // process.kill needs no shell/PATH: on Windows Node maps it to
        // TerminateProcess, on macOS it sends SIGTERM. (PID could in theory be
        // recycled; risk is small since we overwrite the file every launch.)
        process.kill(pid, 'SIGTERM');
        console.log(`[Flask] Reaped stale Flask process ${pid}`);
      } catch (e) {
        // ESRCH = already gone, EPERM = not ours — either way nothing to reap
      }
    }
  } catch (err) {
    console.error('[Flask] Error checking stale PID file:', err);
  } finally {
    try { fs.unlinkSync(pidFilePath); } catch (_) {}
  }
}

/**
 * Remove the Flask PID file (on clean shutdown).
 */
function cleanupFlaskPidFile(projectRoot) {
  const pidFilePath = path.join(projectRoot, FLASK_PID_FILE);
  try {
    if (fs.existsSync(pidFilePath)) {
      fs.unlinkSync(pidFilePath);
    }
  } catch (err) {
    // Ignore cleanup errors
  }
}

/**
 * Kill any Electron processes from a previous Echo run that didn't shut down
 * cleanly (e.g. log-off, force-quit, system crash). Without this, every crash
 * leaves a tree of orphan Echo.exe + renderer processes that accumulate
 * forever in the background, eating memory and blocking new installs.
 *
 * Uses the same PID-file pattern as killStaleFlask: we write our own PID at
 * launch and reap whatever PID was written by the previous launch.
 *
 * On Windows we use taskkill /T to kill the whole process tree (the main
 * process spawns renderer/GPU/utility children that wouldn't die otherwise).
 */
function killStaleElectron(projectRoot) {
  const pidFilePath = path.join(projectRoot, ELECTRON_PID_FILE);
  try {
    if (!fs.existsSync(pidFilePath)) return;
    const pid = parseInt(fs.readFileSync(pidFilePath, 'utf8').trim(), 10);
    if (pid && pid > 0 && pid !== process.pid) {
      try {
        if (process.platform === 'win32') {
          // /T kills the whole process tree (renderer + GPU + utility children).
          // /F is force. The ignored error tolerates "process not found" cleanly.
          require('child_process').execSync(`taskkill /F /T /PID ${pid}`, { stdio: 'ignore' });
        } else {
          process.kill(pid, 'SIGTERM');
        }
        console.log(`[Electron] Reaped stale Electron process tree ${pid}`);
      } catch (e) {
        // Process already gone, or it's a recycled PID we don't own — ignore
      }
    }
  } catch (err) {
    console.error('[Electron] Error checking stale PID file:', err);
  } finally {
    try { fs.unlinkSync(pidFilePath); } catch (_) {}
  }
}

function writeElectronPidFile(projectRoot) {
  try {
    fs.writeFileSync(path.join(projectRoot, ELECTRON_PID_FILE), String(process.pid));
  } catch (err) {
    console.error('[Electron] Could not write PID file:', err);
  }
}

function cleanupElectronPidFile(projectRoot) {
  const pidFilePath = path.join(projectRoot, ELECTRON_PID_FILE);
  try {
    if (fs.existsSync(pidFilePath)) {
      fs.unlinkSync(pidFilePath);
    }
  } catch (_) {}
}

/**
 * Read the server port from the port file
 */
function readServerPort(projectRoot) {
  const portFilePath = path.join(projectRoot, PORT_FILE);
  try {
    if (fs.existsSync(portFilePath)) {
      const portStr = fs.readFileSync(portFilePath, 'utf8').trim();
      const port = parseInt(portStr, 10);
      if (!isNaN(port) && port > 0 && port < 65536) {
        return port;
      }
    }
  } catch (err) {
    console.error('[Port] Error reading port file:', err);
  }
  return null;
}

/**
 * Wait for the port file to be created and read the port
 */
// Ping Flask until it responds with HTTP 200, or give up after maxWaitMs.
// Needed because waitForPortFile only confirms the port FILE exists, not that
// Flask is actually accepting connections. The port file is written before the
// HTTP server is fully bound, so loading windows immediately after = blank pages.
function waitForFlaskHealth(port, maxWaitMs = 20000) {
  return new Promise((resolve) => {
    const start = Date.now();
    const tryOnce = () => {
      const req = http.get(`http://127.0.0.1:${port}/`, { timeout: 1000 }, (res) => {
        // Any HTTP response — even 404 — means Flask is listening
        res.resume();
        resolve(true);
      });
      req.on('error', () => {
        if (Date.now() - start > maxWaitMs) return resolve(false);
        setTimeout(tryOnce, 300);
      });
      req.on('timeout', () => {
        req.destroy();
        if (Date.now() - start > maxWaitMs) return resolve(false);
        setTimeout(tryOnce, 300);
      });
    };
    tryOnce();
  });
}

function waitForPortFile(projectRoot, maxWaitMs = 10000, checkIntervalMs = 100) {
  return new Promise((resolve, reject) => {
    const startTime = Date.now();
    
    const checkPort = () => {
      const port = readServerPort(projectRoot);
      if (port !== null) {
        console.log(`[Port] Server port detected: ${port}`);
        resolve(port);
        return;
      }
      
      if (Date.now() - startTime > maxWaitMs) {
        reject(new Error('Timeout waiting for server port file'));
        return;
      }
      
      setTimeout(checkPort, checkIntervalMs);
    };
    
    checkPort();
  });
}

/**
 * Clean up the port file
 */
function cleanupPortFile(projectRoot) {
  const portFilePath = path.join(projectRoot, PORT_FILE);
  try {
    if (fs.existsSync(portFilePath)) {
      fs.unlinkSync(portFilePath);
      console.log('[Port] Port file cleaned up');
    }
  } catch (err) {
    // Ignore cleanup errors
  }
}

// Start Flask backend
function startFlaskServer() {
  const isWin = process.platform === 'win32';
  const dataDir = getDataDir();
  try { fs.mkdirSync(dataDir, { recursive: true }); } catch (_) {}

  // Reap an orphaned backend from a previous crashed run, then clear the port file (BUG-21)
  killStaleFlask(dataDir);
  cleanupPortFile(dataDir);

  // Hand Cognito IDs to the backend so @require_auth activates only when configured
  const authCfg = getAuthConfig();
  const cognitoEnv = authCfg.userPoolId ? {
    COGNITO_REGION: authCfg.region,
    COGNITO_USER_POOL_ID: authCfg.userPoolId,
    COGNITO_APP_CLIENT_ID: authCfg.clientId,
  } : {};
  // Force UTF-8 (emoji log lines) and tell the backend where to read/write its files
  const baseEnv = { ...process.env, PYTHONUTF8: '1', PYTHONIOENCODING: 'utf-8',
                    ECHO_DATA_DIR: dataDir, ...cognitoEnv };

  if (app.isPackaged) {
    // Packaged: launch the frozen, self-contained backend (no Python on the user's PC)
    const backendExe = isWin
      ? path.join(process.resourcesPath, 'backend', 'echo-backend', 'echo-backend.exe')
      : path.join(process.resourcesPath, 'backend', 'echo-backend', 'echo-backend');

    // ── Mac pre-flight ───────────────────────────────────────────────────────
    // The .dmg is unsigned, so macOS slaps com.apple.quarantine on every file
    // inside it. When Electron then spawn()s the bundled backend, Gatekeeper
    // *silently kills the child process* — no dialog, no log line, the user
    // just sees the dashboard hang on a blank loading page and assumes Echo
    // crashed.
    //
    // The fix is to strip the quarantine attribute the first time we launch
    // and ensure the binary is executable. Both ops are idempotent — they
    // do nothing on subsequent launches once the attr is gone.
    //
    // We also recurse into the echo-backend folder because PyInstaller's
    // onedir layout has a _internal/ directory full of dylibs that ALSO
    // get quarantined and individually killed.
    if (process.platform === 'darwin') {
      const backendDir = path.join(process.resourcesPath, 'backend', 'echo-backend');
      try { execSync(`xattr -dr com.apple.quarantine "${backendDir}"`, { stdio: 'ignore' }); } catch (_) {}
      try { execSync(`chmod +x "${backendExe}"`, { stdio: 'ignore' }); } catch (_) {}
      if (!fs.existsSync(backendExe)) {
        try {
          dialog.showErrorBox(
            'Echo could not start',
            `The Echo backend binary is missing from the app bundle.\n\nExpected: ${backendExe}\n\nReinstall Echo from the original .dmg.`
          );
        } catch (_) {}
      }
    }

    console.log('[Flask] Starting bundled backend:', backendExe);
    flaskProcess = spawn(backendExe, [], { cwd: dataDir, env: baseEnv });
  } else {
    // Dev: run app.py with the venv python (or system python as fallback)
    const projectRoot = path.join(__dirname, '..');
    const venvPython = isWin
      ? path.join(projectRoot, 'venv', 'Scripts', 'python.exe')
      : path.join(projectRoot, 'venv', 'bin', 'python');
    const pythonScript = path.join(projectRoot, 'app.py');
    const fallbackPython = isWin ? 'python' : 'python3';
    const pythonExec = fs.existsSync(venvPython) ? venvPython : fallbackPython;
    console.log('[Flask] Starting Flask (dev) via', pythonExec);
    flaskProcess = spawn(pythonExec, [pythonScript], { cwd: projectRoot, env: baseEnv });
  }

  // Record the PID so a future launch can reap this process if we crash (BUG-21)
  try {
    fs.writeFileSync(path.join(dataDir, FLASK_PID_FILE), String(flaskProcess.pid));
  } catch (err) {
    console.error('[Flask] Could not write PID file:', err);
  }

  flaskProcess.stdout.on('data', (data) => {
    // Flask stdout - typically startup messages
    const msg = data.toString().trim();
    if (msg) console.log(`Flask: ${msg}`);
  });

  flaskProcess.stderr.on('data', (data) => {
    // Flask writes access logs to stderr, don't show them as errors
    // Only show actual errors (not HTTP 200 responses)
    const msg = data.toString().trim();
    if (msg && !msg.includes('HTTP/1.1" 200')) {
      console.log(`Flask: ${msg}`);
    }
  });

  // Track when we spawned so we can detect "exited almost immediately" — that's
  // the symptom of Gatekeeper killing the child, a missing dylib, or arch
  // mismatch. Without this, the user sees nothing and the dashboard hangs.
  const spawnedAt = Date.now();
  let backendErrored = false;

  flaskProcess.on('error', (err) => {
    console.error('[Flask] Failed to start Flask server:', err);
    backendErrored = true;
    // The OS couldn't launch the process at all (file not found, no exec perm).
    // Pop a real dialog — silent failure is the actual bug we're fixing.
    try {
      dialog.showErrorBox(
        'Echo backend failed to launch',
        `The Echo backend could not start:\n\n${err.message || err}\n\n` +
        (process.platform === 'darwin'
          ? 'On macOS this is usually caused by Gatekeeper quarantining the bundled binary. ' +
            'Try: quit Echo, then in Terminal run:\n  xattr -cr "/Applications/Echo.app"\nand relaunch.'
          : 'Try: quit Echo completely (system tray → Quit Echo), wait 30 seconds, then relaunch.')
      );
    } catch (_) {}
  });

  flaskProcess.on('exit', (code, signal) => {
    const lifetime = Date.now() - spawnedAt;
    console.log(`[Flask] Flask server exited with code ${code}, signal ${signal}, after ${lifetime}ms`);
    cleanupFlaskPidFile(dataDir);
    // Early exit (< 3s) with a non-zero code = the backend never came up. This
    // is the "Echo silently disappears on launch" Mac symptom.
    if (!backendErrored && lifetime < 3000 && code !== 0 && code !== null) {
      try {
        dialog.showErrorBox(
          'Echo backend crashed',
          `The Echo backend exited immediately with code ${code}` +
          (signal ? ` (signal ${signal})` : '') + '.\n\n' +
          (process.platform === 'darwin'
            ? 'On macOS this usually means Gatekeeper killed the bundled binary (quarantine attribute) ' +
              'or the wrong architecture was installed (Apple Silicon vs Intel).\n\n' +
              'Try: quit Echo, then in Terminal run:\n  xattr -cr "/Applications/Echo.app"\nand relaunch. ' +
              'If that fails, reinstall using the DMG matching your chip (arm64 for M1/M2/M3, x64 for Intel).'
            : 'Try: quit Echo completely, wait 30 seconds, then relaunch.')
        );
      } catch (_) {}
    }
  });

  // Wait for the port file to be created
  return waitForPortFile(dataDir)
    .then((port) => {
      serverPort = port;
      console.log(`[Flask] Server is running on port ${serverPort}`);
      return port;
    })
    .catch((err) => {
      console.error('[Flask] Error waiting for port:', err);
      // Fall back to default port
      serverPort = 8080;
      console.log(`[Flask] Falling back to default port ${serverPort}`);
      return serverPort;
    });
}

// Handle second instance attempt - focus existing window instead
if (!gotTheLock) {
  app.quit();
} else {
  app.on('second-instance', (event, commandLine, workingDirectory) => {
    // Windows delivers the echo:// OAuth callback as an argv on the 2nd instance
    const url = commandLine.find((arg) => typeof arg === 'string' && arg.startsWith('echo://'));
    if (url) { handleOAuthCallback(url); return; }
    // Clicking the taskbar icon (2nd launch) must always bring the app back
    focusOrReopen();
  });
}

// Re-show the app when the user clicks the taskbar/dock icon or re-launches.
// Recreates a window if none exist so the app can never get "stuck running with
// no window" (the bug that made it look like it wouldn't open).
function focusOrReopen() {
  // Logged out and auth is required → show the login screen
  if (authGateActive() && !loadTokens()) {
    createLoginWindow();
    return;
  }
  // Bring back / recreate the dashboard
  if (mainWindow && !mainWindow.isDestroyed()) {
    if (mainWindow.isMinimized()) mainWindow.restore();
    mainWindow.show();
    mainWindow.focus();
  } else {
    createMainWindow();
  }
  // Ensure the pill is present too
  if (!pillWindow || pillWindow.isDestroyed()) createPillWindow();
}

// ============================================
// SYSTEM TRAY — always-visible safety net so the app is never "invisible".
// Even if the pill is hidden, crashed, or behind a full-screen app, the user
// can always click the tray icon to bring everything back or quit cleanly.
// ============================================
function createTrayIcon() {
  if (trayIcon) return;
  try {
    const iconPath = process.platform === 'win32'
      ? path.join(__dirname, '..', 'assets', 'icon.ico')
      : path.join(__dirname, '..', 'assets', 'icon.png');
    const img = nativeImage.createFromPath(iconPath);
    // On macOS the menu-bar icon should be a small template image
    const trayImg = process.platform === 'darwin'
      ? img.resize({ width: 18, height: 18 })
      : img;
    trayIcon = new Tray(trayImg);
    trayIcon.setToolTip('Echo — speech to text');
    refreshTrayMenu();
    // Left-click brings the dashboard back (Windows behavior users expect)
    trayIcon.on('click', () => { focusOrReopen(); });
  } catch (e) {
    console.error('[Tray] Could not create tray icon:', e.message);
  }
}

function refreshTrayMenu() {
  if (!trayIcon) return;
  const loggedOut = authGateActive() && !loadTokens();
  const menu = Menu.buildFromTemplate([
    { label: 'Open Dashboard', click: () => focusOrReopen() },
    { label: 'Show Pill', enabled: !loggedOut, click: () => {
        if (!pillWindow || pillWindow.isDestroyed()) createPillWindow();
        else { try { pillWindow.showInactive(); pillWindow.setAlwaysOnTop(true, 'screen-saver'); } catch (_) {} }
      } },
    { type: 'separator' },
    { label: loggedOut ? 'Sign in…' : 'Sign out', click: () => {
        if (loggedOut) createLoginWindow();
        else { try { clearTokens(); } catch (_) {} broadcastAuthState(); refreshTrayMenu(); }
      } },
    { type: 'separator' },
    { label: 'Quit Echo', click: () => app.quit() },
  ]);
  trayIcon.setContextMenu(menu);
}

// ============================================
// PILL HEARTBEAT — unconditional keep-alive every 3 seconds.
// The old cursor-poll loop short-circuited when the mouse was still, which let
// the pill silently lose always-on-top status (full-screen app, sleep, lock,
// UAC). This heartbeat re-asserts visibility regardless of cursor movement and
// reloads the renderer if it has crashed.
// ============================================
function startPillHeartbeat() {
  if (pillHeartbeatInterval) return;
  pillHeartbeatInterval = setInterval(() => {
    if (!pillWindow || pillWindow.isDestroyed()) return;
    try {
      // Detect a dead renderer — transparent window stays "open" even when the
      // page has crashed, so isDestroyed() returns false but the pill is blank.
      if (pillWindow.webContents.isCrashed()) {
        // v1.2.11 — if a browser-fallback (Mac) recording/transcription was in
        // flight, the renderer OWNED that capture. Reloading silently discards
        // it and main would wait forever for a 'transcription-complete' that can
        // never come (M-4). Tear the recording state down with a visible error
        // FIRST, then reload to a clean idle pill.
        if (isBrowserRecording || browserProcessingTimeout) {
          console.warn('[Heartbeat] Pill renderer crashed mid browser-recording — resetting state');
          writeDiagnostic('pill-crash-during-browser-recording', {});
          forceResetRecordingState('pill-renderer-crash');
          try { sendPillState('error', { message: 'Recording interrupted — please try again' }); } catch (_) {}
        } else {
          console.warn('[Heartbeat] Pill renderer crashed — reloading');
        }
        pillWindow.webContents.reload();
        return;
      }
      // Re-assert always-on-top + visibility. These are idempotent no-ops if
      // already in the right state, but they recover from OS demotion.
      //
      // IMPORTANT: we call showInactive() unconditionally instead of guarding
      // on !isVisible(). A z-order-demoted transparent window on Windows still
      // reports isVisible() === true even though the user can't see it (DWM
      // suspended its composition, or a fullscreen app stacked above it). The
      // guarded version of this code is exactly why "the pill disappears" was
      // reported — the heartbeat never recovered because Electron thought it
      // was already visible. showInactive() on an already-visible window is
      // a cheap no-op, so calling it every 3s is fine.
      pillWindow.setAlwaysOnTop(true, 'screen-saver');
      if (process.platform === 'darwin') {
        pillWindow.setVisibleOnAllWorkspaces(true, { visibleOnFullScreen: true });
      }
      pillWindow.showInactive();
      // Windows DWM occasionally re-adds transparent windows to the taskbar
      // after a sleep/lock cycle. Re-assert the skip-taskbar bit so the pill
      // doesn't appear in Alt-Tab / taskbar after suspend.
      if (process.platform === 'win32') {
        try { pillWindow.setSkipTaskbar(true); } catch (_) {}
      }
    } catch (e) {
      // Don't kill the heartbeat on a single failure
    }
  }, 3000);
}

function stopPillHeartbeat() {
  if (pillHeartbeatInterval) {
    clearInterval(pillHeartbeatInterval);
    pillHeartbeatInterval = null;
  }
}

// ============================================
// POWER EVENTS — restore pill after sleep/wake/unlock. Without these the OS
// demotes the always-on-top window during sleep and never restores it.
// ============================================
function wirePowerMonitor() {
  const restorePill = (label) => () => {
    console.log(`[PowerMonitor] ${label} — restoring pill visibility`);
    if (!pillWindow || pillWindow.isDestroyed()) {
      // Only recreate if we're logged in / no auth required
      if (!authGateActive() || loadTokens()) createPillWindow();
      return;
    }
    try {
      pillWindow.showInactive();
      pillWindow.setAlwaysOnTop(true, 'screen-saver');
      if (process.platform === 'darwin') {
        pillWindow.setVisibleOnAllWorkspaces(true, { visibleOnFullScreen: true });
      }
      // Force a fresh paint in case the compositor dropped the transparent buffer
      pillWindow.webContents.invalidate();
    } catch (_) {}
  };
  try { powerMonitor.on('resume',         restorePill('resume')); } catch (_) {}
  try { powerMonitor.on('unlock-screen',  restorePill('unlock-screen')); } catch (_) {}
  try { powerMonitor.on('user-did-become-active', restorePill('user-active')); } catch (_) {}
}

function createPillWindow() {
  // Prevent creating multiple pill windows
  if (pillWindow && !pillWindow.isDestroyed()) {
    pillWindow.focus();
    return;
  }
  const { screen } = require('electron');
  const primaryDisplay = screen.getPrimaryDisplay();
  const { width, height } = primaryDisplay.workAreaSize;
  
  // Get scaled initial size
  const initialSize = getScaledPillSize(primaryDisplay, 'compact');
  const bottomOffset = getScaledBottomOffset(primaryDisplay);

  pillWindow = new BrowserWindow({
    width: initialSize.width,
    height: initialSize.height,
    x: Math.round((width - initialSize.width) / 2),
    y: height - initialSize.height - bottomOffset,
    frame: false,
    transparent: true,  // Enable transparency for rounded pill appearance
    backgroundColor: '#00000000',  // Fully transparent background
    alwaysOnTop: true,
    resizable: false,
    movable: false,
    minimizable: false,
    maximizable: false,
    closable: false,
    fullscreenable: false,
    hasShadow: false,
    skipTaskbar: true,
    focusable: false,  // Prevent focus stealing
    
    // macOS-specific settings for better visibility and transparency
    ...(process.platform === 'darwin' ? {
      visibleOnAllWorkspaces: true,
      type: 'panel',
      vibrancy: null,  // Disable vibrancy to ensure pure transparency
      visualEffectState: 'inactive',  // Prevent visual effects that might affect transparency
    } : {}),
    
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
      backgroundThrottling: false,  // Keep animations smooth
    },
  });

  // Force always-on-top with the strongest level on EVERY platform.
  // Previously this was Mac-only — on Windows the constructor's `alwaysOnTop: true`
  // applies only the legacy 'floating' level, which loses to fullscreen apps,
  // games, and UAC dialogs. 'screen-saver' is the highest level that respects
  // user input, and it survives those cases. setVisibleOnAllWorkspaces is a no-op
  // on Windows but harmless to call.
  try {
    pillWindow.setAlwaysOnTop(true, 'screen-saver');
    pillWindow.setVisibleOnAllWorkspaces(true, { visibleOnFullScreen: true });
  } catch (_) {}

  // Click-through is managed per-frame in trackCursorAndReposition using cursor hit-testing.

  // Right-click the pill → quick actions (the pill has no title bar, so this is how
  // you reopen the dashboard or fully quit Echo from the pill).
  pillWindow.webContents.on('context-menu', () => {
    const { Menu } = require('electron');
    Menu.buildFromTemplate([
      { label: 'Open Dashboard', click: () => {
          if (!mainWindow || mainWindow.isDestroyed()) createMainWindow();
          else { mainWindow.show(); mainWindow.focus(); }
        } },
      { type: 'separator' },
      { label: 'Quit Echo', click: () => app.quit() },
    ]).popup({ window: pillWindow });
  });

  // Load with hash route - use 127.0.0.1 to avoid IPv6 issues
  pillWindow.loadURL(`http://127.0.0.1:${serverPort}/#/pill`);
  
  pillWindow.webContents.once('did-finish-load', () => {
    // Belt-and-suspenders show: trackCursorAndReposition() calls showInactive()
    // only when the cursor moves, and on a cold boot the user may not wiggle the
    // mouse before checking. Force a visible, top-most pill the moment the
    // renderer is ready, regardless of platform.
    try {
      pillWindow.showInactive();
      pillWindow.setAlwaysOnTop(true, 'screen-saver');
    } catch (_) {}
  });

  // Auto-retry if the Flask server was slow to start and the transparent window loaded a blank page
  pillWindow.webContents.on('did-fail-load', () => {
    console.log('[Pill] Failed to load, retrying in 2 seconds...');
    setTimeout(() => {
      if (pillWindow && !pillWindow.isDestroyed()) {
        const freshPort = readServerPort(getDataDir());
        if (freshPort) serverPort = freshPort;
        pillWindow.loadURL(`http://127.0.0.1:${serverPort}/#/pill`);
      }
    }, 2000);
  });

  // DevTools disabled for production - uncomment for debugging
  // if (isDev) {
  //   pillWindow.webContents.openDevTools({ mode: 'detach' });
  // }

  pillWindow.on('closed', () => {
    pillWindow = null;
    if (screenTrackingInterval) {
      clearInterval(screenTrackingInterval);
      screenTrackingInterval = null;
    }
    stopPillHeartbeat();
    // Clean up event listeners
    screen.removeAllListeners('display-added');
    screen.removeAllListeners('display-removed');
    screen.removeAllListeners('display-metrics-changed');
  });

  // Initial positioning
  trackCursorAndReposition();

  // Unconditional heartbeat — re-asserts visibility every 3s even when the
  // user is AFK. The cursor-poll loop above is opportunistic and short-circuits
  // when the mouse is still; this heartbeat is the real keep-alive.
  startPillHeartbeat();

  // Multiple event listeners for display changes (macOS backup)
  //
  // v1.2.5: remove any existing display-* listeners FIRST. createPillWindow
  // can be called multiple times across a session (logout/login, auth-state
  // churn, manual "Show Pill" from tray). The pill.on('closed') handler also
  // removes them, but if a second createPillWindow runs before the previous
  // pill's closed event fires, listeners accumulate. Each accumulated
  // listener calls trackCursorAndReposition() — which calls setPosition() and
  // showInactive() — on every display change, thrashing the Window Server.
  screen.removeAllListeners('display-added');
  screen.removeAllListeners('display-removed');
  screen.removeAllListeners('display-metrics-changed');

  screen.on('display-added', () => {
    trackCursorAndReposition();
  });

  screen.on('display-removed', () => {
    trackCursorAndReposition();
  });

  screen.on('display-metrics-changed', () => {
    trackCursorAndReposition();
  });
  
  // Fast polling for cursor tracking (200ms = 5 times per second)
  screenTrackingInterval = setInterval(() => {
    trackCursorAndReposition();
  }, 200);
}

function trackCursorAndReposition() {
  if (!pillWindow || pillWindow.isDestroyed()) return;
  
  try {
    const { screen } = require('electron');
    const cursorPoint = screen.getCursorScreenPoint();
    
    // Debounce: Only check if cursor moved significantly (>50px)
    const movedSignificantly =
      Math.abs(cursorPoint.x - lastCursorPosition.x) > 50 ||
      Math.abs(cursorPoint.y - lastCursorPosition.y) > 50;
    
    if (!movedSignificantly && currentDisplayId !== null) {
      return; // Skip if cursor barely moved
    }
    
    lastCursorPosition = { x: cursorPoint.x, y: cursorPoint.y };
    const activeDisplay = screen.getDisplayNearestPoint(cursorPoint);

    // Only reposition if display actually changed
    if (currentDisplayId !== activeDisplay.id) {
      currentDisplayId = activeDisplay.id;
      repositionPillWindow(activeDisplay);
    }

    // Click-through hit-test: transparent area outside the pill passes clicks through;
    // hovering the actual pill widget re-enables interaction.
    const [px, py] = pillWindow.getPosition();
    const [pw, ph] = pillWindow.getSize();
    const overPill = cursorPoint.x >= px && cursorPoint.x <= px + pw &&
                     cursorPoint.y >= py && cursorPoint.y <= py + ph;
    pillWindow.setIgnoreMouseEvents(!overPill, { forward: true });

  } catch (error) {
    // Ignore cursor tracking errors
  }
}

function repositionPillWindow(activeDisplay) {
  if (!pillWindow || pillWindow.isDestroyed()) return;
  
  try {
    const { screen } = require('electron');
    
    // Get display if not provided
    if (!activeDisplay) {
      const cursorPoint = screen.getCursorScreenPoint();
      activeDisplay = screen.getDisplayNearestPoint(cursorPoint);
      currentDisplayId = activeDisplay.id;
    }
    
    // Use workArea for positioning (accounts for dock/taskbar)
    const { x, y, width, height } = activeDisplay.workArea;
    const [currentWidth, currentHeight] = pillWindow.getSize();
    const bottomOffset = getScaledBottomOffset(activeDisplay);
    
    const newX = x + Math.floor((width - currentWidth) / 2);
    const newY = y + height - currentHeight - bottomOffset;
    
    pillWindow.setPosition(newX, newY);
    pillWindow.showInactive(); // Ensure it's visible without stealing focus
  } catch (error) {
    // Ignore repositioning errors
  }
}

function createMainWindow() {
  const { screen } = require('electron');
  const primaryDisplay = screen.getPrimaryDisplay();
  const { width, height } = primaryDisplay.workAreaSize;

  mainWindow = new BrowserWindow({
    width: 1200,
    height: 800,
    x: Math.round((width - 1200) / 2),
    y: Math.round((height - 800) / 2),
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
    },
    // macOS: inset traffic lights. Windows/Linux: keep a custom title bar but show
    // the native min/maximize/CLOSE buttons via the overlay (BUG: previously hidden
    // gave no close button).
    ...(process.platform === 'darwin'
      ? { titleBarStyle: 'hiddenInset', trafficLightPosition: { x: 15, y: 15 } }
      : { titleBarStyle: 'hidden', titleBarOverlay: { color: '#0f172a', symbolColor: '#e5e7eb', height: 40 } }),
  });

  mainWindow.loadURL(`http://127.0.0.1:${serverPort}/#/`);

  // Auto-retry if Flask is slow to start and the dashboard loaded a blank page.
  // Without this the dashboard sits as a white window forever (no retry) while
  // the pill — which already has its own did-fail-load retry — eventually loads.
  let dashboardRetryCount = 0;
  mainWindow.webContents.on('did-fail-load', (event, errorCode, errorDesc, validatedURL) => {
    if (errorCode === -3) return; // -3 = aborted (e.g. user navigated away)
    dashboardRetryCount++;
    if (dashboardRetryCount > 8) return; // give up after ~16s
    console.log(`[Dashboard] Load failed (${errorCode} ${errorDesc}), retry ${dashboardRetryCount}/8 in 2s...`);
    setTimeout(() => {
      if (mainWindow && !mainWindow.isDestroyed()) {
        const freshPort = readServerPort(getDataDir());
        if (freshPort) serverPort = freshPort;
        mainWindow.loadURL(`http://127.0.0.1:${serverPort}/#/`);
      }
    }, 2000);
  });
  // Reset the retry counter once a load succeeds (so a later disconnect can retry too)
  mainWindow.webContents.on('did-finish-load', () => { dashboardRetryCount = 0; });

  // DevTools disabled for production - uncomment for debugging
  // if (isDev) {
  //   mainWindow.webContents.openDevTools({ mode: 'detach' });
  // }

  // Closing the dashboard does NOT quit the app — the pill keeps running so the
  // user can still dictate. Reopen the dashboard from the taskbar / menu bar / pill.
  //
  // On macOS, the previous behavior (let the window close and null mainWindow)
  // meant that clicking the red traffic-light caused the UI to "just disappear" —
  // there was nothing in the Dock to click back to (LSUIElement-style), and most
  // users don't know to look in the menu bar. We now intercept close on Mac and
  // hide() instead, so Cmd+Tab / Dock / menu-bar can bring it back instantly.
  // The user can still fully exit via the menu bar tray → Quit Echo.
  let dashboardCloseHintShown = false;
  mainWindow.on('close', (event) => {
    // v1.2.6 — record every close event so we can diagnose "dashboard
    // vanished by itself" reports. The most likely cause is Cmd+W (Mac
    // close-window shortcut, very common muscle memory from other Mac apps)
    // hitting this handler, which converts close → hide on Mac. Looks like a
    // bug from the user's POV. The diagnostic shows which path was taken.
    writeDiagnostic('main-window-close', {
      isQuitting: !!app.isQuitting,
      willHide: process.platform === 'darwin' && !app.isQuitting,
    });
    if (process.platform === 'darwin' && !app.isQuitting) {
      event.preventDefault();
      try { mainWindow.hide(); } catch (_) {}
      if (!dashboardCloseHintShown) {
        dashboardCloseHintShown = true;
        try { maybeShowFirstCloseHint(); } catch (_) {}
      }
      return;
    }
    try { maybeShowFirstCloseHint(); } catch (_) {}
  });
  // v1.2.6 — track every show/hide on Mac. If something is programmatically
  // hiding the dashboard outside our close handler (which would explain "vanished
  // by itself"), this captures it.
  mainWindow.on('hide', () => writeDiagnostic('main-window-hide', {}));
  mainWindow.on('show', () => writeDiagnostic('main-window-show', {}));
  // v1.2.6 — intercept Cmd+M / yellow traffic-light minimize on Mac. macOS's
  // default minimize-to-Dock behavior puts a thumbnail near the Trash icon,
  // which users mistake for "the app got minimized somewhere weird". Convert
  // minimize → hide so the window cleanly disappears and the Dock icon stays
  // as the single re-open point (consistent with our close intercept).
  mainWindow.on('minimize', (event) => {
    if (process.platform === 'darwin' && !app.isQuitting) {
      writeDiagnostic('main-window-minimize', { redirected: 'hide' });
      try { event.preventDefault(); } catch (_) {}
      try { mainWindow.hide(); } catch (_) {}
    } else {
      writeDiagnostic('main-window-minimize', { redirected: null });
    }
  });
  mainWindow.on('closed', () => {
    writeDiagnostic('main-window-closed', { isQuitting: !!app.isQuitting });
    mainWindow = null;
  });
}

// Show a one-time "Echo is still running in the tray" balloon. Stored in a
// small marker file so it never fires again after the first dashboard close.
function maybeShowFirstCloseHint() {
  if (!trayIcon || process.platform === 'darwin') return; // tray balloon is Windows/Linux
  const dataDir = getDataDir();
  const markerPath = path.join(dataDir, 'tray-hint-shown');
  if (fs.existsSync(markerPath)) return;
  try {
    trayIcon.displayBalloon({
      title: 'Echo is still running',
      content: 'Closing the window doesn\'t quit Echo — it keeps running in the tray so you can dictate any time. Right-click the tray icon → Quit Echo to fully exit.',
    });
    fs.writeFileSync(markerPath, String(Date.now()));
  } catch (_) {}
}

// IPC Handlers
ipcMain.on('show-main-window', () => {
  if (!mainWindow) {
    createMainWindow();
  } else {
    mainWindow.show();
    mainWindow.focus();
  }
});

// Fully quit the app (from the pill ✕ and Settings "Quit" button).
// The pill is created with closable:false, so app.quit()'s window.close() is a
// no-op on it and the quit stalls. destroy() bypasses that, so force-destroy every
// window + kill the backend, then quit.
ipcMain.on('app-quit', () => {
  try { if (flaskProcess) flaskProcess.kill(); } catch (_) {}
  stopPillHeartbeat();
  try { if (trayIcon) { trayIcon.destroy(); trayIcon = null; } } catch (_) {}
  [pillWindow, mainWindow, loginWindow].forEach((w) => {
    try { if (w && !w.isDestroyed()) w.destroy(); } catch (_) {}
  });
  pillWindow = null; mainWindow = null; loginWindow = null;
  app.quit();
});

// Pill window sizing - uses screen-relative calculations
// Base sizes are for a 1920px wide display, scaled proportionally for other resolutions
const BASE_SCREEN_WIDTH = 1920;
const BASE_PILL_SIZES = {
  compact: { width: 140, height: 36 },
  hoverExpanded: { width: 140, height: 40 },
  recording: { width: 140, height: 36 },
  fullyExpanded: { width: 380, height: 52 }   // wider/taller to fit the bigger Quit button (v1.2.3)
};
const BASE_BOTTOM_OFFSET = 8;

// Calculate scaled pill size based on current display
function getScaledPillSize(display, sizeKey) {
  const baseSize = BASE_PILL_SIZES[sizeKey];
  const scaleFactor = display.scaleFactor || 1;
  const displayWidth = display.workArea.width;
  
  // Scale based on display width relative to base (1920px)
  // Use a minimum scale of 0.7 and maximum of 1.5 to prevent extreme sizes
  const widthRatio = Math.min(1.5, Math.max(0.7, displayWidth / BASE_SCREEN_WIDTH));
  
  return {
    width: Math.round(baseSize.width * widthRatio),
    height: Math.round(baseSize.height * widthRatio)
  };
}

function getScaledBottomOffset(display) {
  const displayWidth = display.workArea.width;
  const widthRatio = Math.min(1.5, Math.max(0.7, displayWidth / BASE_SCREEN_WIDTH));
  return Math.round(BASE_BOTTOM_OFFSET * widthRatio);
}

ipcMain.on('pill-expand', (event, width) => {
  console.log(`[Pill] pill-expand request with width: ${width}`);
  if (pillWindow) {
    // Immediately allow clicks — don't wait for the 200ms poll to enable interaction
    pillWindow.setIgnoreMouseEvents(false);
    const { screen } = require('electron');
    const cursorPoint = screen.getCursorScreenPoint();
    const activeDisplay = screen.getDisplayNearestPoint(cursorPoint);
    const displayWidth = activeDisplay.workArea.width;
    const displayHeight = activeDisplay.workArea.height;

    // Determine size based on width parameter - use scaled sizes
    let sizeKey = 'recording';
    if (width >= 220) {
      sizeKey = 'fullyExpanded';
    }
    const size = getScaledPillSize(activeDisplay, sizeKey);
    const bottomOffset = getScaledBottomOffset(activeDisplay);
    console.log(`[Pill] Using ${sizeKey} size: ${JSON.stringify(size)} (scaled for ${displayWidth}px display)`);
    
    const newX = activeDisplay.workArea.x + Math.round((displayWidth - size.width) / 2);
    const newY = activeDisplay.workArea.y + displayHeight - size.height - bottomOffset;
    
    console.log(`[Pill] Setting bounds to: x=${newX}, y=${newY}, w=${size.width}, h=${size.height}`);
    pillWindow.setBounds({ x: newX, y: newY, width: size.width, height: size.height });
  }
});

// Hover-expanded state - slightly larger window
ipcMain.on('pill-hover-expand', () => {
  if (pillWindow) {
    // Allow clicks immediately so the user can click buttons without waiting for the poll
    pillWindow.setIgnoreMouseEvents(false);
    const { screen } = require('electron');
    const cursorPoint = screen.getCursorScreenPoint();
    const activeDisplay = screen.getDisplayNearestPoint(cursorPoint);
    const displayWidth = activeDisplay.workArea.width;
    const displayHeight = activeDisplay.workArea.height;
    const size = getScaledPillSize(activeDisplay, 'hoverExpanded');
    const bottomOffset = getScaledBottomOffset(activeDisplay);
    const newX = activeDisplay.workArea.x + Math.round((displayWidth - size.width) / 2);
    const newY = activeDisplay.workArea.y + displayHeight - size.height - bottomOffset;

    pillWindow.setBounds({ x: newX, y: newY, width: size.width, height: size.height });
  }
});

ipcMain.on('pill-compact', () => {
  if (pillWindow) {
    const { screen } = require('electron');
    const cursorPoint = screen.getCursorScreenPoint();
    const activeDisplay = screen.getDisplayNearestPoint(cursorPoint);
    const displayWidth = activeDisplay.workArea.width;
    const displayHeight = activeDisplay.workArea.height;
    const size = getScaledPillSize(activeDisplay, 'compact');
    const bottomOffset = getScaledBottomOffset(activeDisplay);
    const newX = activeDisplay.workArea.x + Math.round((displayWidth - size.width) / 2);
    const newY = activeDisplay.workArea.y + displayHeight - size.height - bottomOffset;

    pillWindow.setBounds({ x: newX, y: newY, width: size.width, height: size.height });
    // Compact = transparent background, re-enable click-through for areas outside the visible pill
    pillWindow.setIgnoreMouseEvents(true, { forward: true });
  }
});

// ============================================
// IPC: pill -> main recording commands (single unified path - Phase 1 / D7)
// ============================================
ipcMain.on('recording-start', () => { beginRecording(); });
ipcMain.on('recording-stop', () => { finishRecording(true); });
ipcMain.on('recording-cancel', () => { finishRecording(false); });

// Pill tells main which model is selected (BUG-04)
ipcMain.on('set-model', (event, model) => {
  if (typeof model === 'string' && model) currentModel = model;
});

// Pill asks main for the current state (e.g. after a reload) so it can re-sync
ipcMain.on('request-pill-state', () => {
  sendPillState(currentStatus);
});


// Handle transcription complete - browser MediaRecorder fallback path (WIN-03 / no-SoX)
ipcMain.on('transcription-complete', (event, payload) => {
  // v1.2.11 — the browser result arrived; disarm the processing watchdog so it
  // can't later fire a phantom "Transcription timed out" over a real result.
  clearBrowserProcessingTimeout();
  // payload may be a plain string (legacy) or { text } / { error } (WIN fallback)
  const text  = typeof payload === 'string' ? payload : (payload && payload.text) || '';
  const error = (payload && typeof payload === 'object') ? payload.error : '';
  if (error) {
    sendPillState('error', { message: String(error).slice(0, 80) });
    return;
  }
  if (!text || !text.trim()) {
    sendPillState('error', { message: 'No speech detected' });
    return;
  }
  clipboard.writeText(text);
  const target = savedPasteBundleId;
  savedPasteBundleId = null;
  const pasteHint = process.platform === 'darwin' ? 'Copied — press ⌘V' : 'Copied — press Ctrl+V';
  if (target) {
    // Show Copied! immediately, then update if paste succeeds/fails
    sendPillState('success', { message: 'Copied!', text, pasted: true });
    platformPaste(target).then((pasted) => {
      sendPillState('success', { message: pasted ? 'Copied!' : pasteHint, text, pasted });
    }).catch(() => {
      sendPillState('success', { message: pasteHint, text, pasted: false });
    });
  } else {
    sendPillState('success', { message: 'Copied!', text, pasted: false });
  }
});

// ============================================
// F5 fallback toggle — registration helpers (BUG-18)
// globalShortcut hijacks F5 system-wide, so a browser tab can't refresh while
// Echo runs. We release it whenever a Echo window loses focus and
// restore it on focus. Right Option (uiohook, a non-consuming listener) stays the
// always-on push-to-talk, so background dictation is unaffected.
// ============================================
function toggleRecordingFromShortcut() {
  if (!isRecordingActive && !isBackgroundRecording) {
    beginRecording();
  } else {
    finishRecording(true);
  }
}

function registerToggleShortcut() {
  if (globalShortcut.isRegistered('F5')) return;
  const ok = globalShortcut.register('F5', toggleRecordingFromShortcut);
  if (!ok) {
    console.warn('[Hotkey] Could not register F5 (another app may hold it)');
  }
}

function unregisterToggleShortcut() {
  if (globalShortcut.isRegistered('F5')) {
    globalShortcut.unregister('F5');
  }
}

// App lifecycle
app.whenReady().then(async () => {
  // Exit early if we don't have the lock (singleton check)
  if (!gotTheLock) {
    return;
  }
  
  // Check if running in development mode
  isDev = !app.isPackaged;

  // Grant microphone access to our own first-party (127.0.0.1) renderer. Packaged
  // Electron apps otherwise block getUserMedia, which made the WIN MediaRecorder
  // capture return empty audio → the misleading "No speech detected".
  try {
    const { session } = require('electron');
    session.defaultSession.setPermissionRequestHandler((wc, permission, callback) => {
      callback(true);
    });
    session.defaultSession.setPermissionCheckHandler(() => true);
  } catch (e) {
    console.error('[Perms] Could not set permission handlers:', e.message);
  }

  // Force dark mode for the app to ensure pill remains black on all displays
  nativeTheme.themeSource = 'dark';
  
  // Register the echo:// custom protocol for the OAuth redirect
  if (process.defaultApp && process.argv.length >= 2) {
    app.setAsDefaultProtocolClient('echo', process.execPath, [path.resolve(process.argv[1])]);
  } else {
    app.setAsDefaultProtocolClient('echo');
  }
  // macOS delivers the OAuth callback via open-url
  app.on('open-url', (event, url) => {
    event.preventDefault();
    handleOAuthCallback(url);
  });

  // Reap any orphan Echo.exe tree from a previous crash before doing anything
  // else — they would otherwise stack up forever and block file overwrites.
  // We have singleInstanceLock to prevent two NEW launches, but we still need
  // this to clean up zombies from a process that crashed mid-run.
  try { killStaleElectron(getDataDir()); } catch (_) {}
  try { writeElectronPidFile(getDataDir()); } catch (_) {}

  // On macOS, force the Dock icon to be visible. Without this, if every window
  // is hidden during the Flask boot wait (or if a previous run set the app to
  // accessory mode), the user sees nothing in the Dock and assumes Echo
  // crashed. Belt-and-suspenders for the silent-launch bug.
  if (process.platform === 'darwin' && app.dock) {
    try { app.dock.show(); } catch (_) {}
  }

  // Create the tray icon FIRST — before anything else can fail. This is the
  // always-visible safety net so the app is never "invisible" even if Flask
  // takes 8s to start, the pill is hidden, or login is required.
  createTrayIcon();
  wirePowerMonitor();
  startRecordingWatchdog();
  writeDiagnostic('app-start', { argv: process.argv, dataDir: getDataDir() });

  await checkSoxAvailable();

  // Visible startup error if Flask fails to come up. startFlaskServer() always
  // resolves (falls back to port 8080 even on timeout), so we can't trust its
  // promise — we have to actually ping Flask to know if it's listening.
  await startFlaskServer();
  const flaskReady = await waitForFlaskHealth(serverPort, 25000);
  if (!flaskReady) {
    try {
      const procMgrHint = process.platform === 'darwin'
        ? 'Activity Monitor'
        : process.platform === 'win32' ? 'Task Manager' : 'System Monitor';
      const avHint = process.platform === 'darwin'
        ? 'macOS Gatekeeper may be killing the bundled backend (run "xattr -cr /Applications/Echo.app" in Terminal to clear quarantine)'
        : process.platform === 'win32' ? 'Windows Defender or antivirus is scanning the backend on first launch'
        : 'A security tool is blocking the backend binary';
      dialog.showErrorBox(
        'Echo could not start',
        `The Echo backend did not start in time on port ${serverPort}.\n\nThis usually means:\n  • Another copy of Echo is still running (check ${procMgrHint} / system tray)\n  • ${avHint}\n  • The port is blocked\n\nTry: quit Echo completely, wait 30 seconds, then relaunch.`
      );
    } catch (_) {}
  }

  // Auth gate: show login first when an auth mode (Cognito OR local test) is
  // active and no token is stored yet.
  if (authGateActive() && !loadTokens()) {
    // Not logged in (and login is required) → show ONLY the login screen
    createLoginWindow();
  } else {
    // Logged in (or no auth) → show the pill + the dashboard
    createPillWindow();
    createMainWindow();
  }
  refreshTrayMenu();
  
  uIOhook.on('keydown', (event) => {
    if (event.keycode !== PUSH_TO_TALK_KEY_CODE) return;

    // Latch mode active: next key press stops the recording
    if (isLatchMode) {
      console.log('[Hotkey] Latch key pressed - stopping latch recording');
      isLatchMode = false;
      finishRecording(true);
      return;
    }

    // Second tap of a double-tap sequence → enter latch mode
    // (recording is already running from the first tap — just keep it going)
    if (pendingDoubleTap !== null) {
      clearTimeout(pendingDoubleTap);
      pendingDoubleTap = null;
      console.log('[Hotkey] Double-tap confirmed - entering latch mode');
      isLatchMode = true;
      return;
    }

    // Normal start: every path funnels through beginRecording() (Phase 1 / BUG-01)
    if (!isRecordingActive && !isBackgroundRecording) {
      console.log('[Hotkey] Key pressed - starting recording');
      isHotkeyPressed = true;
      lastTapDownTime = Date.now();
      beginRecording();
    }
  });

  uIOhook.on('keyup', (event) => {
    if (event.keycode !== PUSH_TO_TALK_KEY_CODE) return;

    // Latch mode: key release doesn't stop recording — only next keydown does
    if (isLatchMode) return;

    // Not recording: nothing to do (e.g. key released after latch stop)
    if (!isRecordingActive && !isBackgroundRecording) return;

    const holdDuration = Date.now() - lastTapDownTime;

    if (holdDuration >= SHORT_HOLD_MAX_MS) {
      // Long hold = push-to-talk: release stops recording immediately
      console.log(`[Hotkey] Key released after ${holdDuration}ms hold - stopping (PTT)`);
      isHotkeyPressed = false;
      finishRecording(true);
    } else {
      // Short tap: open a window to detect a second tap (double-tap → latch)
      console.log(`[Hotkey] Short tap (${holdDuration}ms) - waiting for double-tap`);
      pendingDoubleTap = setTimeout(() => {
        pendingDoubleTap = null;
        // No second tap came: treat as single short tap → stop recording
        if (isRecordingActive || isBackgroundRecording) {
          console.log('[Hotkey] Single tap confirmed - stopping recording');
          isHotkeyPressed = false;
          finishRecording(true);
        }
      }, DOUBLE_TAP_GAP_MS);
    }
  });
  
  // Start the hook. If it fails (typically missing macOS Accessibility permission)
  // tell the user instead of silently losing push-to-talk, and point them at the
  // F5 fallback (BUG-15).
  try {
    uIOhook.start();
    hotkeyListenerActive = true;
  } catch (error) {
    hotkeyListenerActive = false;
    console.error('[Hotkey] uIOhook failed to start:', error);
    if (process.platform === 'darwin') {
      showOneTimeNotice('accessibility',
        'Push-to-talk unavailable',
        'Echo needs Accessibility permission for the Right Option push-to-talk key.\n\nGrant it in System Settings → Privacy & Security → Accessibility, then restart Echo.\n\nYou can still use F5 to start/stop dictation.');
    } else {
      showOneTimeNotice('hotkey',
        'Push-to-talk unavailable',
        'Global push-to-talk could not start. You can still use F5 to start/stop dictation.');
    }
  }

  // F5 removed — Right Alt / Right Option is the only hotkey.
});

app.on('window-all-closed', () => {
  // With the system tray as the safety net, the app stays alive even when all
  // windows are closed — the user can reopen the dashboard or pill from the
  // tray. Only quit if the tray is gone too (it gets destroyed during app-quit).
  if (trayIcon) {
    return;
  }
  globalShortcut.unregisterAll();
  try {
    uIOhook.stop();
  } catch (e) {
    // Ignore if already stopped
  }
  if (flaskProcess) {
    flaskProcess.kill();
  }
  // Clean up port + PID files (in the data dir where the backend wrote them)
  const dataDir = getDataDir();
  cleanupPortFile(dataDir);
  cleanupFlaskPidFile(dataDir);

  if (process.platform !== 'darwin') {
    app.quit();
  }
});

app.on('activate', () => {
  focusOrReopen();
});

app.on('before-quit', () => {
  // Flip the flag so mainWindow.on('close') stops intercepting (Mac hide-on-close).
  // Without this, app.quit() can be blocked because the dashboard close handler
  // calls event.preventDefault().
  app.isQuitting = true;
  globalShortcut.unregisterAll();
  stopPillHeartbeat();
  stopRecordingWatchdog();
  // v1.2.5: SIGKILL any lingering SoX child + reset state BEFORE we tear down
  // uIOhook, so we never leave a child holding the audio HAL after Echo quits.
  try { forceResetRecordingState('app-quit'); } catch (_) {}
  try { if (trayIcon) { trayIcon.destroy(); trayIcon = null; } } catch (_) {}
  try {
    // v1.2.5: explicitly remove the keydown/keyup listeners BEFORE stopping
    // uIOhook. If uIOhook.stop() throws, the listeners would otherwise stay
    // armed and the Accessibility event tap would keep firing.
    uIOhook.removeAllListeners('keydown');
    uIOhook.removeAllListeners('keyup');
    uIOhook.stop();
  } catch (e) {
    // Ignore if already stopped
  }
  if (flaskProcess) {
    flaskProcess.kill();
  }
  // Clean up port + PID files (in the data dir where the backend wrote them)
  const dataDir = getDataDir();
  cleanupPortFile(dataDir);
  cleanupFlaskPidFile(dataDir);
  cleanupElectronPidFile(dataDir);
});

app.on('will-quit', () => {
  globalShortcut.unregisterAll();
  try {
    uIOhook.stop();
  } catch (e) {
    // Ignore if already stopped
  }
});

// Reset hotkey state when recording is manually stopped
ipcMain.on('recording-stopped', () => {
  isHotkeyPressed = false;
});

// App version — used by Settings dialog to display current version
ipcMain.handle('get-app-version', () => app.getVersion());

// Auto-start (login item) handlers
ipcMain.handle('get-login-item-status', () => {
  return app.getLoginItemSettings().openAtLogin;
});

ipcMain.handle('set-login-item', (event, enable) => {
  app.setLoginItemSettings({ openAtLogin: Boolean(enable) });
  return true;
});

// ── Auth IPC ──
// Refresh-aware: the renderer's authedFetch always gets a non-expired idToken.
ipcMain.handle('get-auth-token', () => ensureValidToken());

ipcMain.on('auth-google-start', () => { startGoogleOAuth('Google'); });

// Email/password flow authenticates in the renderer (amazon-cognito-identity-js)
// and hands the resulting tokens back here for encrypted storage.
ipcMain.on('auth-login-success', (event, tokens) => {
  if (tokens && tokens.idToken) completeLogin(tokens);
});

ipcMain.on('auth-logout', () => {
  clearTokens();
  broadcastAuthState();
  // Open login FIRST so 'window-all-closed' (→ quit on Windows) can't fire while
  // we close the pill + dashboard during logout.
  if (authGateActive()) createLoginWindow();
  const old = [pillWindow, mainWindow];
  pillWindow = null;
  mainWindow = null;
  old.forEach((w) => { if (w && !w.isDestroyed()) w.close(); });
});