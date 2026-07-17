#!/bin/bash

# Echo Linux Build Script (v1.2)
# This script should be run inside WSL (Ubuntu) to generate the Linux version.

# 1. Ensure we are on Linux
if [[ "$OSTYPE" != "linux-gnu"* ]]; then
    echo "ERROR: This script must be run inside a Linux environment (like WSL Ubuntu)."
    exit 1
fi

echo "--- Starting Echo Linux Build ---"

# 2. Setup Python environment and build backend
echo "[1/4] Building Python Backend..."
if [ ! -d "venv-linux" ]; then
    python3 -m venv venv-linux
fi
source venv-linux/bin/activate
pip install -r requirements.txt
pip install pyinstaller

# Create Linux executable for the backend
pyinstaller --noconfirm --onedir --windowed --name "echo-backend" \
    --add-data "app.py:." \
    --collect-all groq \
    app.py

# Move backend build to the expected location for electron-builder
mkdir -p build-backend/dist
rm -rf build-backend/dist/echo-backend
cp -r dist/echo-backend build-backend/dist/
echo "Backend build complete."

# 3. Setup Node dependencies
echo "[2/4] Installing Node dependencies..."
npm install

# 4. Build the Electron App
echo "[3/4] Packaging Electron App (.deb and .AppImage)..."
npm run build-linux

echo "--- Build Complete! ---"
echo "Your Linux files are in: mywhisper/dist/"
echo "1. echo-dictation_1.2.0_amd64.deb"
echo "2. Echo-1.2.0.AppImage"
