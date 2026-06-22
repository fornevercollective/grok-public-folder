#!/usr/bin/env python3
"""Detect and record metadata for Grok-generated media."""

from __future__ import annotations

import json
import plistlib
import subprocess
from datetime import datetime, timezone
from pathlib import Path

from grok_paths import IMAGE_DIR, ROOT, VIDEO_DIR

ARTIFACTS_ROOT = ROOT
GROK_URL_MARKERS = (
    "grok.com",
    "x.ai",
    "imagine-public.x.ai",
    "vidgen.x.ai",
    "higgsfield.ai",
)
MEDIA_EXT = {".mp4", ".mov", ".m4v", ".webm", ".png", ".jpg", ".jpeg", ".webp", ".gif"}


def sidecar_path(media_path: Path) -> Path:
    return media_path.with_suffix(media_path.suffix + ".grok.json")


def read_where_froms(path: Path) -> list[str]:
    try:
        output = subprocess.check_output(
            ["xattr", "-p", "com.apple.metadata:kMDItemWhereFroms", str(path)],
            stderr=subprocess.DEVNULL,
        )
        data = plistlib.loads(output)
        if isinstance(data, list):
            return [str(item) for item in data]
        if isinstance(data, str):
            return [data]
    except (subprocess.CalledProcessError, plistlib.InvalidFileException, FileNotFoundError):
        pass

    try:
        output = subprocess.check_output(
            ["mdls", "-raw", "-name", "kMDItemWhereFroms", str(path)],
            stderr=subprocess.DEVNULL,
            text=True,
        ).strip()
        if output and output != "(null)":
            return [output]
    except (subprocess.CalledProcessError, FileNotFoundError):
        pass
    return []


def is_grok_download(path: Path) -> tuple[bool, str]:
    name = path.name.lower()
    if name.startswith("grok_"):
        return True, "filename"
    if path.suffix.lower() not in MEDIA_EXT:
        return False, ""

    sources = " ".join(read_where_froms(path)).lower()
    for marker in GROK_URL_MARKERS:
        if marker in sources:
            return True, f"url:{marker}"
    if "imagine" in name and path.suffix.lower() in {".mp4", ".mov", ".webm"}:
        return True, "filename:imagine"
    return False, ""


def write_sidecar(media_path: Path, payload: dict) -> Path:
    data = {
        "source": "grok",
        "file": media_path.name,
        "saved_at": datetime.now(timezone.utc).isoformat(),
    }
    data.update(payload)
    path = sidecar_path(media_path)
    path.write_text(json.dumps(data, indent=2), encoding="utf-8")
    return path


def read_sidecar(media_path: Path) -> dict | None:
    path = sidecar_path(media_path)
    if not path.exists():
        return None
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return None


def target_folder_for(path: Path) -> Path:
    if path.suffix.lower() in {".mp4", ".mov", ".m4v", ".webm"}:
        return VIDEO_DIR
    return IMAGE_DIR


def move_to_artifacts(path: Path, extra_meta: dict | None = None) -> Path:
    target_dir = target_folder_for(path)
    target_dir.mkdir(parents=True, exist_ok=True)
    destination = target_dir / path.name
    if destination.exists():
        stamp = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
        destination = target_dir / f"{path.stem}_{stamp}{path.suffix}"

    path.replace(destination)
    detected, reason = is_grok_download(destination)
    meta = {
        "detected": detected,
        "detect_reason": reason,
        "original_path": str(path),
    }
    if extra_meta:
        meta.update(extra_meta)
    write_sidecar(destination, meta)
    return destination