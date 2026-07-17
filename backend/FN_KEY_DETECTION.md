# Function (Fn) Key Detection Logic for Push-to-Talk

This document explains how the Fn key detection and Push-to-Talk (PTT) functionality was implemented in the Whisper Flow app.

## 1. Library Used: `uiohook-napi`
Standard Electron `globalShortcut` does not support `keyup` events or capturing the `Fn` key alone. We used the [`uiohook-napi`](package.json) library, which provides a global hook for keyboard and mouse events across the entire OS.

## 2. Implementation in `public/electron.js`

### Import and Initialization
```javascript
const { uIOhook } = require('uiohook-napi');

// Note: Ensure it's started after app.whenReady()
app.whenReady().then(() => {
    uIOhook.start();
});
```

### Key Detection Logic (Push-to-Talk)
We identified that the user's bottom-left key (Fn) produces code `0` in `uiohook`.

```javascript
let isHotkeyPressed = false;
const FN_KEY_CODE = 0; // Identified from logs for this specific user

uIOhook.on('keydown', (event) => {
    if (event.keycode === FN_KEY_CODE && !isHotkeyPressed) {
        isHotkeyPressed = true;
        // Signal frontend to start recording and show animation
        pillWindow.webContents.send('hotkey-start-recording');
    }
});

uIOhook.on('keyup', (event) => {
    if (event.keycode === FN_KEY_CODE && isHotkeyPressed) {
        isHotkeyPressed = false;
        // Signal frontend to stop recording and transcribe
        pillWindow.webContents.send('hotkey-stop-recording');
    }
});
```

## 3. Frontend Integration in `templates/index.html`

The frontend must respond to the IPC signals immediately to provide a zero-latency feel.

```javascript
// Inside the Pill component
useEffect(() => {
    const handleStart = async () => {
        if (stateRef.current === 'idle') {
            await startRecording(); // Immediately sets state to 'recording'
        }
    };
    const handleStop = () => {
        if (stateRef.current === 'recording') {
            stopRecording(); // Immediately sets state to 'processing'
        }
    };
    window.electron.ipcRenderer.on('hotkey-start-recording', handleStart);
    window.electron.ipcRenderer.on('hotkey-stop-recording', handleStop);
}, []);
```

## 4. Critical Requirements
1.  **Accessibility Permissions**: macOS requires the user to grant "Accessibility" permissions to the terminal or VS Code (during dev) or the final app to allow global key hooks.
2.  **Process Management**: Ensure only one instance of the app is running, as `uiohook` can conflict between multiple instances.
3.  **Key Codes**: Different keyboards may have different codes for the Fn key. Code `0` worked for this user, but `63`, `179`, or `464` are also common.

## 5. Known Issues
- `uiohook.start()` can sometimes block the main thread if permissions are not handled.
- Multiple application instances lead to multiple floating "pills" on the screen. Always kill old processes before restarting.
