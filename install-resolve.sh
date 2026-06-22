#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS="$HOME/Library/Application Support/Blackmagic Design/DaVinci Resolve/Fusion/Scripts"
UTIL_DEST="$SCRIPTS/Utility"

# Resolve lists Utility scripts under Scripts on every page (Comp/Edit/Color/Deliver).
# One file "Grok.py" — same entry on each page, not separate scripts.

GROK_NAMES=(
  "Grok.py"
  "Grok Menu.py"
  "Grok Bootstrap.lua"
  "Grok Console.py"
  "Import Grok Artifacts.py"
  "Import Grok Artifacts.lua"
  "Grok Panel.py"
  "Grok Startup.py"
  "Grok Console Import.py"
)

for dir in Utility Comp Tool Edit Color Deliver Fairlight; do
  target="$SCRIPTS/$dir"
  [[ -d "$target" ]] || continue
  for file in "${GROK_NAMES[@]}"; do
    rm -f "$target/$file"
  done
  rm -rf "$target/__pycache__"
done

mkdir -p "$UTIL_DEST"
cp "$ROOT/resolve/utility/Grok.py" "$UTIL_DEST/"
chmod +x "$UTIL_DEST/Grok.py" 2>/dev/null || true

echo "installed $UTIL_DEST/Grok.py"
echo "Workspace -> Scripts -> Grok (under Comp / Edit / Color / Deliver on each page)"