#!/usr/bin/env bash
# Fetch the best local speech model for the whisper.cpp engine.
#
#   scripts/fetch-model.sh [model.bin]   (default: ggml-large-v3-turbo.bin)
#
# The app itself never touches the network — recognition is on-device. This is a
# one-time setup step you run yourself; the model then lives in ./models/ and is
# loaded locally. Apple's built-in recogniser needs no download at all.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="${MODELS_DIR:-$ROOT/models}"
MODEL="${1:-ggml-large-v3-turbo.bin}"
BASE="${MODEL_BASE:-https://huggingface.co/ggerganov/whisper.cpp/resolve/main}"
URL="$BASE/$MODEL"

mkdir -p "$DEST"
if [ -f "$DEST/$MODEL" ]; then
  echo "already present: $DEST/$MODEL"
  exit 0
fi

echo "==> downloading $MODEL"
echo "    from $URL"
curl -fL --progress-bar "$URL" -o "$DEST/$MODEL.part"
mv "$DEST/$MODEL.part" "$DEST/$MODEL"

echo "==> sha256"
shasum -a 256 "$DEST/$MODEL"
echo "saved $DEST/$MODEL"
