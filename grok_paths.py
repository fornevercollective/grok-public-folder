#!/usr/bin/env python3
"""Single source of truth for grok-public-folder paths."""

from __future__ import annotations

import os
from pathlib import Path

ROOT = Path(os.environ.get("GROK_PUBLIC_FOLDER", Path(__file__).resolve().parent))
VIDEO_DIR = ROOT / "video"
IMAGE_DIR = ROOT / "image"
BRIDGE_DIR = ROOT / "bridge"
BROWSER_DIR = ROOT / "browser"
IMDB_DIR = ROOT / "imdb"
STREAMING_DIR = ROOT / "streaming"
BLANK_DIR = ROOT / "blank"
BLANK_DOWNLOADS_DIR = BLANK_DIR / "downloads"
BLANK_SNAPSHOTS_DIR = BLANK_DIR / "snapshots"
BLANK_CACHE_DIR = BLANK_DIR / "cache"
PROJECT_DIR = ROOT / "project"
TIMELINE_SCAN_FILE = PROJECT_DIR / "timeline-grok-clips.json"
PRESETS_MANIFEST = PROJECT_DIR / "presets-manifest.json"
PRESET_CACHE_DIR = PROJECT_DIR / "preset-cache"
CINEMATIC_PACK = PROJECT_DIR / "cinematic-pack-50.json"
GROK_ROOT_MARKER = PROJECT_DIR / ".grok-root"
GENERATE_UI = PROJECT_DIR / "generate-ui.json"
STARTUP_CONFIG = PROJECT_DIR / "grok-resolve-startup.yaml"
RESOLVE_LUA_DIR = ROOT / "resolve" / "lua"
RESOLVE_UTILITY_DIR = ROOT / "resolve" / "utility"
RESOLVE_EDIT_DIR = ROOT / "resolve" / "edit"
BIN_DIR = ROOT / "bin"

MAX_VIDEO_RESOLUTION = "720p"
MAX_TIMELINE_WIDTH = 3840
MAX_TIMELINE_HEIGHT = 2160