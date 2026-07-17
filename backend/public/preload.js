const { contextBridge, ipcRenderer } = require('electron');

// Store active handlers by channel
const handlers = {};

// Valid channels for send (renderer -> main) — Phase 1 unified contract
const sendChannels = [
  'show-main-window',
  'pill-expand',
  'pill-compact',
  'pill-hover-expand',
  'transcription-complete', // dashboard window auto-paste path
  'recording-start',
  'recording-stop',
  'recording-cancel',
  'set-model',
  'request-pill-state',
  'auth-google-start',
  'auth-login-success',
  'auth-logout',
  'app-quit',
];

// Valid channels for ipcRenderer.invoke (two-way, returns a Promise)
const invokeChannels = [
  'get-login-item-status',
  'set-login-item',
  'get-auth-token',
  'get-app-version',
];

// Valid channels for receive (main -> renderer)
const receiveChannels = [
  'pill-state',
  'browser-record-start',  // main tells pill to start MediaRecorder (no-SoX fallback)
  'browser-record-stop',   // main tells pill to stop + transcribe
  'auth-state',            // main broadcasts { loggedIn, email } on auth change
];

// Setup listeners for all receive channels immediately
receiveChannels.forEach(channel => {
  handlers[channel] = [];
  ipcRenderer.on(channel, (event, ...args) => {
    console.log(`[preload] Received IPC: ${channel}`, args.length > 0 ? args[0] : '');
    handlers[channel].forEach(handler => {
      try {
        handler(...args);
      } catch (err) {
        console.error(`[preload] Error in handler for ${channel}:`, err);
      }
    });
  });
});

contextBridge.exposeInMainWorld('electron', {
  platform: process.platform,
  ipcRenderer: {
    send: (channel, data) => {
      if (sendChannels.includes(channel)) {
        ipcRenderer.send(channel, data);
      } else {
        console.warn(`[preload] Invalid send channel: ${channel}`);
      }
    },
    invoke: (channel, data) => {
      if (invokeChannels.includes(channel)) {
        return ipcRenderer.invoke(channel, data);
      }
      console.warn(`[preload] Invalid invoke channel: ${channel}`);
      return Promise.reject(new Error(`Invalid invoke channel: ${channel}`));
    },
    on: (channel, func) => {
      if (receiveChannels.includes(channel)) {
        console.log(`[preload] Registering handler for: ${channel}`);
        handlers[channel].push(func);
      } else {
        console.warn(`[preload] Invalid receive channel: ${channel}`);
      }
    },
    removeListener: (channel, func) => {
      if (receiveChannels.includes(channel)) {
        const index = handlers[channel].indexOf(func);
        if (index > -1) {
          handlers[channel].splice(index, 1);
          console.log(`[preload] Removed handler for: ${channel}`);
        }
      }
    },
    removeAllListeners: (channel) => {
      if (receiveChannels.includes(channel)) {
        handlers[channel] = [];
        console.log(`[preload] Removed all handlers for: ${channel}`);
      }
    }
  }
});

console.log('[preload] Preload script loaded, IPC handlers ready');
