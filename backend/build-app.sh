#!/bin/bash

# Build script for Whisper Flow macOS App

echo "🚀 Building Whisper Flow macOS App..."
echo ""

# Check if node_modules exists
if [ ! -d "node_modules" ]; then
    echo "📦 Installing dependencies..."
    npm install
    echo ""
fi

# Check if Python venv exists
if [ ! -d "venv" ]; then
    echo "🐍 Setting up Python virtual environment..."
    python3 -m venv venv
    source venv/bin/activate
    pip install -r requirements.txt
    echo ""
else
    echo "✅ Python virtual environment already exists"
    echo ""
fi

# Build the app
echo "🔨 Building macOS application..."
npm run build-universal

echo ""
echo "✅ Build complete!"
echo ""
echo "📦 Your app is ready in the 'dist' folder:"
echo "   - Whisper Flow.app (Universal Binary - works on Intel & Apple Silicon)"
echo "   - Whisper Flow.dmg (Installer)"
echo ""
echo "To install:"
echo "1. Open dist/Whisper Flow.dmg"
echo "2. Drag Whisper Flow to Applications folder"
echo "3. Launch from Applications"
echo ""
echo "Note: On first launch, you may need to:"
echo "  - Right-click the app and select 'Open'"
echo "  - Or go to System Preferences > Security & Privacy and allow the app"