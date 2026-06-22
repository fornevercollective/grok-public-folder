#!/usr/bin/env python3
"""Single source of truth for grok-public-folder paths."""

from __future__ import annotations

import os
from pathlib import Path

ROOT = Path(os.environ.get("GROK_PUBLIC_FOLDER", Path(__file__).resolve().parent))
VIDEO_DIR = ROOT / "video"
IMAGE_DIR = ROOT / "image"
BRIDGE_DIR = ROOT / "bridge"
PROJECT_DIR = ROOT / "project"
PRESETS_MANIFEST = PROJECT_DIR / "presets-manifest.json"
PRESET_CACHE_DIR = PROJECT_DIR / "preset-cache"
STARTUP_CONFIG = PROJECT_DIR / "grok-resolve-startup.yaml"
RESOLVE_LUA_DIR = ROOT / "resolve" / "lua"
RESOLVE_UTILITY_DIR = ROOT / "resolve" / "utility"
RESOLVE_EDIT_DIR = ROOT / "resolve" / "edit"
BIN_DIR = ROOT / "bin"

MAX_VIDEO_RESOLUTION = "720p"
MAX_TIMELINE_WIDTH = 3840
MAX_TIMELINE_HEIGHT = 2160