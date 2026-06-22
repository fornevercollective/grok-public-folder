#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
DEST="$HOME/Library/Application Support/Blackmagic Design/DaVinci Resolve/Fusion/Scripts/Utility"

mkdir -p "$DEST"

KEEP=(
  "Grok Menu.py"
  "Grok Console.py"
  "Grok Bootstrap.lua"
)

REMOVE=(
  "Import Grok Artifacts.py"
  "Import Grok Artifacts.lua"
  "Grok Panel.py"
  "Grok Startup.py"
  "Grok Console Import.py"
)

for file in "${REMOVE[@]}"; do
  rm -f "$DEST/$file"
done

for file in "${KEEP[@]}"; do
  cp "$ROOT/resolve/utility/$file" "$DEST/"
done

chmod +x "$DEST/"*.py 2>/dev/null || true

echo "installed grok resolve scripts to"
echo "$DEST"
echo "menu: Workspace -> Scripts -> Utility -> Grok Menu"