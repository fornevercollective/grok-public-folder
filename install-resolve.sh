#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS="$HOME/Library/Application Support/Blackmagic Design/DaVinci Resolve/Fusion/Scripts"
UTIL_DEST="$SCRIPTS/Utility"

# Resolve Free (19.1+) removed Python UIManager — use Grok.lua for the menu.
# Utility scripts appear under Scripts on each page; one Grok.lua entry.

GROK_NAMES=(
  "Grok.lua"
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
cp "$ROOT/resolve/utility/Grok.lua" "$UTIL_DEST/"
xattr -cr "$UTIL_DEST/Grok.lua" 2>/dev/null || true

if [[ -f "$ROOT/grok_generate_catalog.py" ]]; then
  python3 "$ROOT/grok_generate_catalog.py" >/dev/null 2>&1 || true
fi
if compgen -G "$ROOT/resolve/ui/*.swift" >/dev/null; then
  PLIST="$ROOT/resolve/ui/Info.plist"
  if [[ -f "$PLIST" ]]; then
    swiftc -O -o "$ROOT/bin/grok-menu-ui" "$ROOT"/resolve/ui/*.swift -framework AppKit \
      -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker "$PLIST" 2>/dev/null || true
  else
    swiftc -O -o "$ROOT/bin/grok-menu-ui" "$ROOT"/resolve/ui/*.swift -framework AppKit 2>/dev/null || true
  fi
fi

echo "installed $UTIL_DEST/Grok.lua"
echo "Workspace -> Scripts -> Grok  (Grok for Resolve)"
echo "UI panels and Terminal tabs are labeled Grok for Resolve"
echo "Resolve Free: Lua menu (Python UI not supported since 19.1)"