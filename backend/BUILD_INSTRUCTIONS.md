# Building Whisper Flow as a macOS App

This guide will help you build Whisper Flow as a standalone macOS application that you can double-click to launch.

## Prerequisites

Before building, make sure you have:

1. **Node.js** (v16 or higher)
   ```bash
   node --version
   ```

2. **Python 3** (3.8 or higher)
   ```bash
   python3 --version
   ```

3. **Groq API Key**
   - Get one from [console.groq.com](https://console.groq.com)
   - Free tier available

## Quick Build

Simply run the build script:

```bash
./build-app.sh
```

This will:
1. Install Node.js dependencies
2. Set up Python virtual environment
3. Build the macOS app
4. Create a DMG installer

## Manual Build Steps

If you prefer to build manually:

### 1. Install Dependencies

```bash
# Install Node dependencies
npm install

# Set up Python environment
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

### 2. Build the App

Choose your build target:

```bash
# Universal binary (works on Intel & Apple Silicon)
npm run build-universal

# Intel Mac only
npm run build-dmg

# Apple Silicon only
npm run build-arm
```

### 3. Find Your App

After building, you'll find:

```
dist/
├── Whisper Flow.app          # The application
├── Whisper Flow.dmg          # Installer (drag to Applications)
└── Whisper Flow-mac.zip      # Portable version
```

## Installation

### From DMG (Recommended)

1. Open `dist/Whisper Flow.dmg`
2. Drag **Whisper Flow** to the **Applications** folder
3. Eject the DMG
4. Launch from Applications folder

### First Launch

On first launch, macOS may show a security warning:

**Option 1: Right-click Method**
1. Right-click (or Ctrl+click) the app
2. Select "Open"
3. Click "Open" in the dialog

**Option 2: System Preferences**
1. Go to **System Preferences** → **Security & Privacy**
2. Click "Open Anyway" for Whisper Flow
3. Click "Open" in the confirmation dialog

## Using the App

Once launched:

1. **Floating Pill**: A minimalistic pill appears at the bottom of your screen
2. **Select Microphone**: Choose your input device from the dropdown
3. **Choose Model**: Select "Standard" or "Turbo" for transcription
4. **Record**: Click the microphone button to start recording
5. **Stop**: Click the square button to stop and transcribe
6. **Result**: Transcription is automatically copied to clipboard

## Customization

### Custom Icon

To use your own app icon:

1. Create a 512x512 or 1024x1024 PNG image
2. Save it as `assets/icon.png`
3. Rebuild the app

### App Settings

The app stores settings in:
```
~/Library/Application Support/Whisper Flow/config.json
```

## Troubleshooting

### Build Fails

**Error: "electron-builder not found"**
```bash
npm install electron-builder --save-dev
```

**Error: "Python module not found"**
```bash
source venv/bin/activate
pip install -r requirements.txt
```

### App Won't Open

**"App is damaged and can't be opened"**

This happens when macOS blocks unsigned apps:

```bash
xattr -cr "/Applications/Whisper Flow.app"
```

Then try opening again.

**Microphone Permission Denied**

1. Go to **System Preferences** → **Security & Privacy** → **Privacy**
2. Select **Microphone** from the left sidebar
3. Check the box next to **Whisper Flow**

### Port 8080 Already in Use

If the Flask server can't start:

```bash
# Find and kill the process using port 8080
lsof -ti:8080 | xargs kill -9
```

Or edit `app.py` to use a different port.

## Development Mode

To run in development mode (without building):

```bash
npm start
```

This launches the app with the Flask backend and opens the pill overlay.

## Uninstalling

To remove the app:

1. Drag **Whisper Flow** from Applications to Trash
2. Remove settings (optional):
   ```bash
   rm -rf ~/Library/Application\ Support/Whisper\ Flow
   ```

## Distribution

To share the app with others:

1. Upload `Whisper Flow.dmg` from the `dist` folder
2. Recipients can install by opening the DMG and dragging to Applications
3. They'll need to obtain their own Groq API key

## Notes

- **Size**: The app is ~200MB (includes Electron runtime)
- **Python**: The app bundles its own Python environment
- **Updates**: Rebuild to get the latest changes
- **Code Signing**: For proper distribution, you'll need an Apple Developer certificate

## Support

For issues or questions:
- Check the main README.md
- Review troubleshooting section above
- Ensure API key is configured correctly