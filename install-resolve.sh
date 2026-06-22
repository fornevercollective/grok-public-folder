#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS="$HOME/Library/Application Support/Blackmagic Design/DaVinci Resolve/Fusion/Scripts"
EDIT_DEST="$SCRIPTS/Edit"

# Utility scripts repeat under Comp / Edit / Color / Deliver on every page.
# Install only under Edit so Grok appears once: Workspace -> Scripts -> Edit -> Grok Menu

GROK_NAMES=(
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

mkdir -p "$EDIT_DEST"
cp "$ROOT/resolve/edit/Grok Menu.py" "$EDIT_DEST/"
chmod +x "$EDIT_DEST/Grok Menu.py" 2>/dev/null || true

echo "installed grok resolve script to"
echo "$EDIT_DEST/Grok Menu.py"
echo "open: Workspace -> Scripts -> Edit -> Grok Menu"