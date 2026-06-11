#!/bin/bash
set -euo pipefail

echo "=== Soulo Setup ==="

# Check XcodeGen
if ! command -v xcodegen &> /dev/null; then
    echo "Installing XcodeGen..."
    brew install xcodegen
fi

# Generate Xcode project
echo "Generating Xcode project..."
xcodegen

# Download whisper model (required)
read -p "Download Whisper transcription model (77MB tiny / 142MB base)? [y/N] " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    bash Scripts/download_models.sh
fi

echo ""
echo "=== Setup Complete ==="
echo "Open Soulo.xcodeproj to start."
echo ""
echo "First build may take a while: whisper.spm will be fetched and compiled."
echo "Make sure you have an active internet connection."
