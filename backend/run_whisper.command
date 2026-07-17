#!/bin/bash

# Get the directory where this script is located
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$DIR"

# Check if Python 3 is installed
if ! command -v python3 &> /dev/null; then
    osascript -e 'display dialog "Python 3 is not installed. Please install Python 3 from python.org" buttons {"OK"} default button "OK"'
    exit 1
fi

# Check if virtual environment exists, create if not
if [ ! -d "venv" ]; then
    echo "Creating virtual environment..."
    python3 -m venv venv
fi

# Activate virtual environment
source venv/bin/activate

# Install requirements if not already installed
pip install -q -r requirements.txt

# Open browser after a short delay
(sleep 2 && open http://localhost:8080) &

# Run the application
python3 app.py