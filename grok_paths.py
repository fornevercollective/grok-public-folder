#!/usr/bin/env python3
"""Single source of truth for grok-public-folder paths."""

from __future__ import annotations

import os
from pathlib import Path

ROOT = Path(os.environ.get("GROK_PUBLIC_FOLDER", Path(__file__).resolve().parent))
VIDEO_DIR = ROOT / "video"
IMAGE_DIR = ROOT / "image"
BRIDGE_DIR = ROOT / "bridge"
RESOLVE_LUA_DIR = ROOT / "resolve" / "lua"
RESOLVE_UTILITY_DIR = ROOT / "resolve" / "utility"
BIN_DIR = ROOT / "bin"