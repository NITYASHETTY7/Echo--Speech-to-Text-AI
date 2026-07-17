# Whisper Transcription App

A beautiful macOS speech-to-text application with both **web interface** and **native desktop app** featuring a **minimalistic floating pill overlay**, real-time waveforms, and audio playback, powered by Groq's Whisper API.

## ✨ Features

### 🎨 Minimalistic Floating Pill (PERFECTED!)
- **Ultra-Compact Design** - Starts as tiny 80×23px black pill (15% opacity, 50% border)
- **Hover Actions** - Hover to see two buttons: direct record OR expand options (1-click workflow)
- **Smart Hover Effect** - Scales 20% larger on hover with no border for clean look
- **Click to Expand** - Grows to 300×60px showing all controls
- **Auto-Collapse** - Returns to compact state after 10 seconds of inactivity
- **Force Minimize** - Minimize button in expanded state for manual collapse
- **Black & White Theme** - Clean, professional monochrome design
- **No Distractions** - Almost invisible when idle, expands on demand
- **Built-in Controls** - Mic selector, model selector, minimize, and app launcher
- **Live Waveform** - Real-time audio visualization during recording
- **Recording Timer** - Shows elapsed time (minutes:seconds) during recording
- **Red Stop Button** - Clear visual feedback with red theme during recording
- **Auto-Clipboard** - Transcriptions automatically copied for instant paste
- **Fast Multi-Monitor** - Follows cursor between screens in 200ms
- **Global Hotkey** - Function+F5 for quick recording toggle (fully working!)

### 🎙️ Recording Features
- **Real-time Waveform** - Live visualization during recording
- **Microphone Selector** - Choose specific input device with dropdown
- **Model Selection** - Switch between Standard (accurate) and Turbo (fast)
- **Smooth Transitions** - Animated state changes (idle → recording → processing → success)
- **Multi-Monitor Support** - Pill follows you to active screen

### 🎵 Audio Playback
- **Integrated Player** - Play back any past recording
- **Progress Bar** - Click anywhere to seek to specific position
- **Time Display** - Current time / Total duration (e.g., "1:23 / 3:45")
- **Speed Control** - Adjustable playback from 0.5x to 2x speed
- **Clean Controls** - Play/pause button with seekable timeline

### 💾 Smart Management & Themes
- **Sidebar Navigation** - Clean left sidebar with:
  - New Recording button
  - Settings for API key management
  - Scrollable history
  - Relative timestamps ("2 hours ago", "Yesterday")
- **Dark/Light Theme** - Toggle between themes with sun/moon button
  - Professional shadcn-style dark theme
  - Clean light theme (default)
  - Persists across all components
- **Recording History** - Every transcription automatically saved
  - Preview text
  - Model indicator badges
  - Click to view full transcription + audio player
  - Organized chronologically

### 📋 Enhanced Copy Experience
- **Auto-Copy to Clipboard** - Transcriptions automatically copied
- **Click to Copy** - Click text anywhere to copy
- **Visual Feedback** - Flash animation and toast notifications
- **Keyboard Ready** - Standard Cmd+C works

### 🔧 API Key Management
- **Secure Storage** - API key saved in local `config.json` file
- **Settings Dialog** - Modal dialog on first run
- **Show/Hide Toggle** - Button to reveal/hide API key
- **Validation** - Tests API key before saving

## 🖥️ Desktop App Setup

### Launch Desktop App

```bash
cd /Users/um/Documents/mywhisper-flow
npm start
```

This will:
1. ✅ Start Flask backend automatically
2. ✅ Open floating pill overlay (80×20px, almost invisible)
3. ✅ Keep pill always on top and follows you across screens

### Pill Usage

**Visual Flow:**
```
Tiny Pill (80×20px, 15% opacity, 50% border)
    ↓ [Click anywhere on pill]
Expanded (300×60px, mic + model icon + app launcher, no border)
    ↓ [Click record button]
Recording (300×60px, shows waveform)
    ↓ [Click stop]
Processing (250×60px, "Transcribing...")
    ↓
Success (300×60px, "Copied to clipboard!")
    ↓ [Wait 2 seconds]
Expanded (ready for next recording)
    ↓ [After 10 seconds idle]
Compact (auto-minimizes to 80×20px)
```

**Steps:**
1. Click tiny black pill at screen bottom → Expands to 300px
2. Select microphone from dropdown
3. Click ⚡/🎯 icon to change model (Standard/Turbo)
4. Click ☰ icon to open full app window (optional)
5. Click record button → Start recording
6. Speak into microphone (see live waveform)
7. Click stop button → Transcribe
8. Wait for "Copied to clipboard!"
9. Paste anywhere with Cmd+V
10. Pill auto-collapses after 10 seconds idle

## 🚀 Quick Start (Web Version)

### Prerequisites

**Python 3 + Node.js**
- Python 3: `python3 --version` - [Download](https://www.python.org/downloads/)
- Node.js: `node --version` - [Download](https://nodejs.org/)

### Launch Web Interface

**Simply double-click `run_whisper.command`**

The launch script automatically:
1. ✅ Creates Python virtual environment (first run only)
2. ✅ Installs dependencies: Flask + Groq SDK (first run only)
3. ✅ Starts Flask server on http://localhost:8080
4. ✅ Opens your default web browser

**Terminal Alternative:**
```bash
cd /Users/um/Documents/mywhisper-flow
./run_whisper.command
```

### First-Time Setup

1. **Browser Opens** - Automatically to http://localhost:8080
2. **Settings Dialog Appears** - Enter your Groq API key
3. **Get API Key** - From [console.groq.com](https://console.groq.com) (free tier available)
4. **Click "Save"** - Validates and stores your key
5. **Grant Microphone** - Allow when browser prompts
6. **Start Recording!** 🎤

## 📦 Building Executable App

### Quick Build

```bash
./build-app.sh
```

This creates:
- `dist/Whisper Flow.app` - The application
- `dist/Whisper Flow.dmg` - Installer package

### Installation

1. Open `Whisper Flow.dmg`
2. Drag **Whisper Flow** to **Applications**
3. Right-click app and select "Open" (first time only)
4. Tiny pill appears at screen bottom

See [`BUILD_INSTRUCTIONS.md`](BUILD_INSTRUCTIONS.md) for detailed build guide.

## 🎨 Design Philosophy

### Minimalistic Pill Design
- **Invisible by default** - 15% opacity, black, tiny (80×20px)
- **Expand on demand** - Click to show all controls
- **Black & White only** - No colors, clean monochrome
- **No icons in compact mode** - Pure minimalism
- **Follows cursor** - Moves to active display automatically

### Color Scheme (Pill)
- **Background** - Black `rgba(0, 0, 0, 0.85)`
- **Text** - White with varying opacity
- **Buttons** - White semi-transparent (`bg-opacity-20`)
- **Compact Border** - White `rgba(255, 255, 255, 0.5)` - 50% opacity
- **Expanded Border** - None (cleaner look)

### Color Scheme (Web)
- **Primary Blue** - `#3b82f6` (buttons, accents)
- **Success Green** - `#10b981` (success states)
- **Warning Red** - `#ef4444` (recording state)
- **Neutral Grays** - Various shades for text and backgrounds

## 📁 Project Structure

```
mywhisper-flow/
├── app.py                      # Flask backend server
├── public/                     # Electron desktop app
│   ├── electron.js             # Main process (window management)
│   └── preload.js              # IPC bridge for security
├── templates/
│   └── index.html              # Complete React application
│       ├── LiveWaveform        # Real-time audio visualizer
│       ├── MicSelector         # Microphone device selector
│       ├── AudioPlayer         # Playback component
│       ├── SettingsDialog      # API key configuration
│       ├── Pill Component      # Minimalistic floating overlay
│       └── Main App            # Primary application logic
├── package.json                # Node.js dependencies
├── build-app.sh               # Build script for executable
├── run_whisper.command        # macOS web launcher script
├── requirements.txt           # Python dependencies
├── BUILD_INSTRUCTIONS.md      # Detailed build guide
├── QUICKSTART.md             # User quick start guide
├── CHANGES.md                # Recent changes log
└── README.md                 # This file
```

## 🛠️ Technical Stack

### Backend
- **Flask 3.x** - Lightweight Python web framework
- **Groq SDK** - Official Python client for Whisper API
- **File Serving** - Native Flask `send_file` for audio
- **JSON Storage** - Simple file-based persistence

### Desktop App
- **Electron** - Cross-platform desktop framework
- **Node.js** - JavaScript runtime for main process
- **IPC Communication** - Secure inter-process messaging
- **Transparent Windows** - Frameless, always-on-top overlay
- **Screen Tracking** - Follows cursor to active display

### Frontend
- **React 18** - Component-based UI library
- **Babel Standalone** - In-browser JSX transformation
- **Tailwind CSS** - Utility-first styling via CDN
- **Web Audio API** - Real-time audio analysis
- **MediaRecorder API** - Browser-native recording
- **HTML5 Canvas** - High-performance waveform rendering
- **Hash Routing** - Simple client-side routing for multi-window support

## 🎯 Key Components

### Pill Component (Minimalistic Overlay)

**Purpose:** Ultra-minimalistic floating overlay for quick transcriptions

**States:**
- **Compact** - 80×20px, 15% opacity, 50% border, empty black pill
- **Expanded** - 300×60px, shows mic selector + model icon + app launcher, no border
- **Recording** - 300×60px, shows live waveform
- **Processing** - 250×60px, "Transcribing..." message
- **Success** - 300×60px, "Copied to clipboard!" message

**Features:**
- Click anywhere on compact pill to expand
- Auto-collapses after 10 seconds of inactivity
- Auto-resizes based on state (smooth cubic-bezier transitions)
- Follows cursor to active display every 200ms
- Black & white monochrome design
- No icons in compact mode
- Model selector as icon button (⚡ Turbo / 🎯 Standard)
- App launcher button (☰) to open full interface

**IPC Communication:**
```javascript
window.electron.ipcRenderer.send('pill-expand', width);
window.electron.ipcRenderer.send('pill-compact');
```

### LiveWaveform Component

**Purpose:** Real-time audio visualization

**Modes:**
- **Static** - Symmetric frequency bars (center-aligned)
- **Scrolling** - Timeline view (right-to-left history)

**Props:**
```javascript
<LiveWaveform 
    active={boolean}           // Enable audio capture
    processing={boolean}       // Show animation
    mode="static|scrolling"    // Visualization style
    height={number}            // Canvas height in pixels
    barColor="#ffffff"         // Bar fill color (white for pill)
    barWidth={number}          // Bar width in pixels
    barGap={number}            // Spacing between bars
/>
```

## 🔧 Troubleshooting

### Pill Not Visible

**Problem:** Can't see the pill overlay

**Solutions:**
1. **Check if running** - Look for very subtle black rectangle at screen bottom
2. **Opacity** - Pill starts at 15% opacity (almost invisible by design)
3. **Hover** - Move mouse over bottom-center of screen to increase opacity
4. **Screen** - Pill follows cursor, check current display bottom
5. **Restart** - Kill and restart with `npm start`

### Pill Not Expanding

**Problem:** Clicking doesn't expand the pill

**Solutions:**
1. **Click area** - Click directly on the tiny black rectangle
2. **Console check** - Open DevTools to see React errors
3. **Refresh** - The page may need to fully load first
4. **Permissions** - Ensure mic permissions granted

### Recording Errors

**Problem:** Recording fails or shows error

**Solutions:**
1. **Check Flask** - Ensure Flask server is running (check terminal)
2. **API Key** - Verify Groq API key is configured
3. **Microphone** - Grant microphone permissions
4. **Console** - Check browser console (F12) for errors
5. **Restart** - Restart both Flask and Electron

### Multi-Monitor Issues

**Problem:** Pill doesn't follow to new screen

**Solutions:**
1. **Move cursor** - Move mouse to desired screen, pill should follow
2. **Restart** - Quit and restart app to reset positioning
3. **Check code** - Screen tracking in `public/electron.js` repositionPillWindow()

### Build Failures

**Problem:** `./build-app.sh` fails

**Solutions:**
1. **Install dependencies** - Run `npm install` first
2. **Python venv** - Ensure venv exists with `python3 -m venv venv`
3. **Permissions** - Run `chmod +x build-app.sh`
4. **Check logs** - Read terminal output for specific errors
5. **Clean build** - Delete `dist/` folder and rebuild

## 🎓 Development Notes

### Current State (Updated: 2025-10-22 Morning - Fully Polished)
- ✅ Minimalistic pill design (80×23px compact, 300×60px expanded)
- ✅ Black & white monochrome theme with smart borders
- ✅ Auto-collapse after 10 seconds idle
- ✅ **Manual minimize button** in expanded state (rightmost position)
- ✅ **Recording timer** showing minutes:seconds during recording
- ✅ **Red stop button** for clear visual feedback
- ✅ Fast multi-monitor support (200ms polling)
- ✅ **Native model selector** (dropdown works perfectly in pill)
- ✅ **Dark/Light theme toggle** with sun/moon button in title bar
- ✅ **Default light theme** (shadcn-style when dark mode enabled)
- ✅ **Draggable navbar** in main window for easy repositioning
- ✅ App launcher button for full interface
- ✅ Integrated mic selector
- ✅ Live waveform during recording
- ✅ Auto-clipboard copy
- ✅ Improved error handling
- ✅ Smooth cubic-bezier transitions
- ✅ Build system configured
- ✅ **Clean git repository** (node_modules properly ignored)
- ✅ **Global hotkey system working** - Function+F5 starts AND stops with transcription
- ✅ **Enhanced compact pill UX** - Hover shows record + expand buttons with 20% scale
- ✅ **Optimized hover buttons** - 16px circles with 10px icons for perfect fit
- ✅ **Smart hover styling** - Border removed on hover for cleaner zoom effect

### Known Issues
- **Function/Globe key not configured** - Currently using F5, needs to be changed to user's preferred key (detection system in place)
- First-time API key setup requires web interface
- Build requires manual icon setup (see assets/README.md)
- DevTools disabled on pill window (enable manually for debugging)

### Recent Fixes (2025-10-22 Morning - Final Polish)
1. **Hotkey System Fully Working** - Function+F5 properly starts, stops, AND transcribes (fixed stale model reference)
2. **Compact Pill Perfected** - Optimized button sizes (16px circles, 10px icons) with 20% hover scale
3. **Hover Styling Improved** - Border removed on hover for cleaner zoom effect
4. **Pill Height Increased** - From 20px to 23px for better proportions
5. **Key Detection Added** - Terminal logs F13-F20 key presses to help identify Function/Globe key
6. **Compact Pill Enhanced** - Hover shows two buttons: direct record + expand options (1-click workflow)
7. **Git Repository Cleaned** - Removed large Electron binaries from git history, properly configured `.gitignore`
8. **Model Selection Fixed** - Replaced custom dropdown with native `<select>` element (works perfectly in pill window)
9. **Main Window Draggable** - Added blue gradient navbar with drag functionality for repositioning the window

### Future Enhancements
- **Configure Function/Globe key** (MEDIUM PRIORITY) - User needs to test keys and update configuration
- Settings accessible from pill (without opening web)
- Multiple recording profiles
- Custom window positioning memory
- Tray icon for easy access
- Custom app icon

## 📝 License & Attribution

**Built with ❤️ using:**
- React 18 (MIT License)
- Flask 3.x (BSD License)
- Groq SDK (Apache 2.0)
- Tailwind CSS (MIT License)
- Electron (MIT License)

---

## 🎉 Start Transcribing!

Your minimalistic speech-to-text app is ready! 

**Desktop:** `npm start` → Look for tiny black pill at screen bottom
**Web:** Double-click `run_whisper.command` → http://localhost:8080

For detailed instructions, see [`QUICKSTART.md`](QUICKSTART.md) and [`BUILD_INSTRUCTIONS.md`](BUILD_INSTRUCTIONS.md).

**Happy transcribing! 🚀**