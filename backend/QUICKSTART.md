# Whisper Flow - Quick Start Guide

## 🚀 Two Ways to Use

### Option 1: Web Version (Instant)
Double-click [`run_whisper.command`](run_whisper.command) to launch the web interface at http://localhost:8080

### Option 2: Desktop App (Recommended)
Build and install the native macOS app for the floating pill experience.

## 📱 The Minimalistic Pill

The new pill overlay features a clean, minimalistic design:

```
┌────────────────────────────────────────────────┐
│ [●] [Microphone Selector] [Model: Turbo ▼]   │
└────────────────────────────────────────────────┘
```

**Features:**
- Clean icon-based design (no emojis)
- Built-in microphone selector dropdown
- Model selector (Standard/Turbo)
- Live waveform during recording
- Auto-copy transcription to clipboard

## 🔨 Building the Desktop App

### Quick Build
```bash
./build-app.sh
```

### What You Get
After building, find in the `dist/` folder:
- **Whisper Flow.app** - The application
- **Whisper Flow.dmg** - Drag-to-install package

### Installation
1. Open `Whisper Flow.dmg`
2. Drag **Whisper Flow** to **Applications**
3. Launch from Applications folder
4. On first run: Right-click → Open (to bypass security warning)

## ⚙️ First Time Setup

1. **Get API Key**: Sign up at [console.groq.com](https://console.groq.com)
2. **Launch App**: The pill appears at screen bottom
3. **Select Microphone**: Choose your input device
4. **Choose Model**: Standard (accurate) or Turbo (fast)
5. **Record**: Click the microphone button
6. **Transcribe**: Click stop - text auto-copies to clipboard

## 🎨 Pill Controls

| Control | Description |
|---------|-------------|
| Microphone Button | Click to start/stop recording |
| Mic Selector | Choose audio input device |
| Model Selector | Switch between Standard/Turbo |
| Waveform | Live audio visualization when recording |

## 📝 Usage Tips

**During Recording:**
- Waveform shows live audio levels
- Clean minimalistic design stays out of your way
- Click stop button to end recording

**After Recording:**
- Transcription automatically copied to clipboard
- Paste anywhere with Cmd+V
- Green checkmark confirms success

**Model Selection:**
- **Standard**: Higher accuracy, ~5-7 seconds
- **Turbo**: Faster processing, ~2-4 seconds

## 🔧 Customization

The pill is designed to be:
- Always on top (never blocked by other windows)
- Minimalistic (clean icons, no distracting emojis)
- Functional (all controls accessible without extra clicks)
- Responsive (smooth animations and transitions)

## 📂 Project Structure

```
mywhisper-flow/
├── run_whisper.command     # Web version launcher
├── build-app.sh            # App builder
├── npm start               # Dev mode
├── templates/
│   └── index.html          # React app with pill component
├── public/
│   └── electron.js         # Desktop app wrapper
└── dist/                   # Built app (after build)
```

## 💡 Pro Tips

1. **Quick Access**: Keep the pill running all day for instant voice notes
2. **Keyboard Shortcut**: Use Cmd+V immediately after recording to paste
3. **Multiple Devices**: Switch between mics without restarting
4. **Model Choice**: Use Turbo for quick notes, Standard for important content

## 🆘 Need Help?

- **Can't find the pill?** Check bottom-center of your screen
- **Microphone not working?** Grant permissions in System Preferences → Privacy
- **Build failed?** See [BUILD_INSTRUCTIONS.md](BUILD_INSTRUCTIONS.md)
- **Port in use?** Kill process: `lsof -ti:8080 | xargs kill -9`

## 🎯 What Changed?

### New Minimalistic Design:
- ✅ Removed all emoji icons from pill
- ✅ Clean SVG icons for buttons
- ✅ Built-in microphone selector
- ✅ Built-in model selector
- ✅ Cleaner glass morphism styling
- ✅ Professional icon-based UI

### Build System:
- ✅ Simple `./build-app.sh` script
- ✅ Universal binary (Intel + Apple Silicon)
- ✅ DMG installer for easy distribution
- ✅ Proper macOS entitlements

---

**Ready to build?** Run `./build-app.sh` and enjoy your minimalistic voice transcription app! 🎤