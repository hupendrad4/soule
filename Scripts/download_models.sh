#!/bin/bash
set -euo pipefail

echo "=== Soulo Model Downloader ==="
echo "Downloads ML models for on-device inference."
echo ""

DOCS_DIR="$HOME/Library/Containers/com.soulo.app/Data/Documents/models"
mkdir -p "$DOCS_DIR"

TINY_URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.en.bin"
BASE_URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin"

echo "Which Whisper model do you want?"
echo "1) tiny.en (77MB, fastest, recommended for iPhone 12+)"
echo "2) base.en (142MB, slightly more accurate, iPhone 14+ only)"
read -p "Choice [1/2]: " choice

if [ "$choice" = "2" ]; then
    WHISPER_URL="$BASE_URL"
    WHISPER_FILE="ggml-base.en.bin"
    echo "Downloading base model (142MB)..."
else
    WHISPER_URL="$TINY_URL"
    WHISPER_FILE="ggml-tiny.en.bin"
    echo "Downloading tiny model (77MB)..."
fi

curl -L -o "$DOCS_DIR/$WHISPER_FILE" "$WHISPER_URL"
echo "Whisper model downloaded to $DOCS_DIR/$WHISPER_FILE"

echo ""
echo "Note: Phi-3-mini (2.3GB) and emotion2vec (50MB) are downloaded"
echo "on first app launch via the ModelDownloadService."
echo ""
echo "=== Done ==="
