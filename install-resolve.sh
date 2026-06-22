#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
DEST="$HOME/Library/Application Support/Blackmagic Design/DaVinci Resolve/Fusion/Scripts/Utility"

mkdir -p "$DEST"
cp "$ROOT/resolve/utility/"*.py "$DEST/"
cp "$ROOT/resolve/utility/"*.lua "$DEST/"
chmod +x "$DEST/"*.py 2>/dev/null || true

echo "installed grok resolve scripts to"
echo "$DEST"