#!/usr/bin/env python3
"""Load Imagine preset slugs and compose generation prompts."""

from __future__ import annotations

import json
import os
import urllib.request
from pathlib import Path

from grok_paths import PRESET_CACHE_DIR, PRESETS_MANIFEST, ROOT

IMAGINE_RAW = "https://raw.githubusercontent.com/fornevercollective/imagine/main"


def imagine_root() -> Path | None:
    for candidate in (
        os.environ.get("IMAGINE_REPO", "").strip(),
        str(ROOT / "vendor" / "imagine"),
        str(Path.home() / "film" / "imagine"),
    ):
        if candidate and Path(candidate).exists():
            return Path(candidate)
    return None


def load_manifest() -> dict:
    return json.loads(PRESETS_MANIFEST.read_text(encoding="utf-8"))


def all_slugs() -> list[str]:
    manifest = load_manifest()
    slugs: list[str] = []
    slugs.extend(manifest.get("featured_templates", []))
    for group in manifest.get("groups", {}).values():
        slugs.extend(group)
    seen: set[str] = set()
    ordered: list[str] = []
    for slug in slugs:
        if slug not in seen:
            seen.add(slug)
            ordered.append(slug)
    return ordered


def slug_group(slug: str) -> str | None:
    manifest = load_manifest()
    if slug in manifest.get("featured_templates", []):
        return "featured"
    for group, members in manifest.get("groups", {}).items():
        if slug in members:
            return group
    return None


def _local_preset_path(slug: str) -> Path | None:
    root = imagine_root()
    if not root:
        return None
    path = root / "style_presets" / slug / "prompt.txt"
    return path if path.exists() else None


def fetch_preset_prompt(slug: str) -> str:
    cached = PRESET_CACHE_DIR / f"{slug}.txt"
    if cached.exists():
        return cached.read_text(encoding="utf-8").strip()

    local = _local_preset_path(slug)
    if local:
        text = local.read_text(encoding="utf-8").strip()
        PRESET_CACHE_DIR.mkdir(parents=True, exist_ok=True)
        cached.write_text(text, encoding="utf-8")
        return text

    url = f"{IMAGINE_RAW}/style_presets/{slug}/prompt.txt"
    try:
        with urllib.request.urlopen(url, timeout=30) as response:
            text = response.read().decode("utf-8").strip()
    except Exception as exc:
        raise RuntimeError(f"preset slug not found: {slug} ({exc})") from exc

    PRESET_CACHE_DIR.mkdir(parents=True, exist_ok=True)
    cached.write_text(text, encoding="utf-8")
    return text


def compose_prompt(
    slug: str,
    base_prompt: str = "",
    prompt_add: str = "",
    ancestry_bible: str = "",
    continuity_notes: str = "",
) -> str:
    style = fetch_preset_prompt(slug)
    parts = [p.strip() for p in (ancestry_bible, base_prompt, style, prompt_add, continuity_notes) if p.strip()]
    return ". ".join(parts)


def compose_from_slug_line(line: str) -> tuple[str, str]:
    """Parse 'neo-noir woman in rain' or '/slug neo-noir woman in rain'."""
    text = line.strip()
    if text.startswith("/slug "):
        text = text[6:].strip()
    if not text:
        raise ValueError("add a slug and prompt")
    slug, _, rest = text.partition(" ")
    if not slug or slug not in all_slugs():
        raise ValueError(f"unknown slug: {slug!r}. use a slug from imagine presets-manifest.")
    prompt = compose_prompt(slug, base_prompt=rest.strip())
    return slug, prompt