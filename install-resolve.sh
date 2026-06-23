#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS="$HOME/Library/Application Support/Blackmagic Design/DaVinci Resolve/Fusion/Scripts"
UTIL_DEST="$SCRIPTS/Utility"

# Resolve Free (19.1+) removed Python UIManager — use Grok.lua for the menu.
# One-click install: patches Grok.lua with your clone path, warms preset pack, builds UI.

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

# Portable root marker (lua + bins read this when GROK_PUBLIC_FOLDER unset)
mkdir -p "$ROOT/project"
printf '%s\n' "$ROOT" > "$ROOT/project/.grok-root"

# Patch Grok.lua with this machine's clone path
if [[ ! -f "$ROOT/resolve/utility/Grok.lua" ]]; then
  echo "missing $ROOT/resolve/utility/Grok.lua" >&2
  exit 1
fi
sed "s|__GROK_INSTALL_ROOT__|${ROOT//|/\\|}|g" "$ROOT/resolve/utility/Grok.lua" > "$UTIL_DEST/Grok.lua"
xattr -cr "$UTIL_DEST/Grok.lua" 2>/dev/null || true

chmod +x "$ROOT"/bin/* 2>/dev/null || true
chmod +x "$ROOT"/install-resolve.sh 2>/dev/null || true

export GROK_PUBLIC_FOLDER="$ROOT"

if [[ -f "$ROOT/grok_preset_pack.py" ]]; then
  python3 "$ROOT/grok_preset_pack.py" --warm --rebuild 2>/dev/null || true
elif [[ -f "$ROOT/grok_generate_catalog.py" ]]; then
  python3 "$ROOT/grok_generate_catalog.py" >/dev/null 2>&1 || true
fi

if compgen -G "$ROOT/resolve/ui/*.swift" >/dev/null; then
  PLIST="$ROOT/resolve/ui/Info.plist"
  if [[ -f "$PLIST" ]]; then
    swiftc -O -o "$ROOT/bin/grok-menu-ui" "$ROOT"/resolve/ui/*.swift -framework AppKit -framework AVKit -framework AVFoundation \
      -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker "$PLIST" 2>/dev/null || true
  else
    swiftc -O -o "$ROOT/bin/grok-menu-ui" "$ROOT"/resolve/ui/*.swift -framework AppKit -framework AVKit -framework AVFoundation 2>/dev/null || true
  fi
fi

cat <<EOF

✓ Grok for Resolve installed (portable)

  Script:  $UTIL_DEST/Grok.lua
  Root:    $ROOT
  Open:    Workspace → Scripts → Grok

  API keys: cp project/grok-secrets.example.env project/grok-secrets.env
  Presets:  ./bin/preset-pack --list   (50 cinematic slugs)
  Bridge:   ./bin/bridge               (Canvas bridge image/video)

EOF