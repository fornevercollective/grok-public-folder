#!/usr/bin/env python3
"""Build generate-ui.json for the Resolve Grok generate panel."""

from __future__ import annotations

import argparse
import json
import re
import urllib.error
import urllib.request
from pathlib import Path

from grok_paths import PRESET_CACHE_DIR, PRESETS_MANIFEST, ROOT, STARTUP_CONFIG
from grok_presets import all_slugs, fetch_preset_prompt, imagine_root, load_manifest, slug_group
from grok_startup import load_startup_config

IMAGINE_RAW = "https://raw.githubusercontent.com/fornevercollective/imagine/main"
GENERATE_UI = ROOT / "project" / "generate-ui.json"
THUMBNAIL_DIR = ROOT / "project" / "thumbnails"

GROUP_LABELS = {
    "featured": "Featured",
    "cinematic_genre": "Cinematic Genre",
    "film_emulation": "Film Emulation",
    "pinterest_aesthetic": "Aesthetic",
}

LUT_HINT = re.compile(r"(lut|logc|bleach|teal-orange|cross-process|day-for-night|color.?grade|rec709)", re.I)


def fetch_meta(slug: str) -> dict:
    local = imagine_root()
    if local:
        path = local / "style_presets" / slug / "meta.json"
        if path.exists():
            return json.loads(path.read_text(encoding="utf-8"))
    url = f"{IMAGINE_RAW}/style_presets/{slug}/meta.json"
    try:
        with urllib.request.urlopen(url, timeout=12) as response:
            return json.loads(response.read().decode("utf-8"))
    except (urllib.error.URLError, json.JSONDecodeError, TimeoutError):
        return {}


def prompt_preview(slug: str) -> str:
    cached = PRESET_CACHE_DIR / f"{slug}.txt"
    if cached.exists():
        text = cached.read_text(encoding="utf-8").strip()
    else:
        try:
            text = fetch_preset_prompt(slug)
        except RuntimeError:
            return ""
    return text[:220] + ("…" if len(text) > 220 else "")


def resolve_thumbnail(slug: str) -> dict:
    candidates: list[Path] = [
        THUMBNAIL_DIR / f"{slug}.jpg",
        THUMBNAIL_DIR / f"{slug}.png",
    ]
    root = imagine_root()
    if root:
        for pattern in (
            root / "style_presets" / slug / "img",
            root / "featured_templates" / slug / "img",
        ):
            if pattern.is_dir():
                for path in sorted(pattern.iterdir()):
                    if path.suffix.lower() in {".jpg", ".jpeg", ".png", ".webp"}:
                        candidates.append(path)
        iteration = root / "assets" / "iterations" / f"{slug}.jpg"
        if iteration.exists():
            candidates.append(iteration)

    for path in candidates:
        if path.exists() and path.is_file():
            return {"kind": "file", "path": str(path)}

    remote = f"{IMAGINE_RAW}/assets/iterations/{slug}.jpg"
    try:
        request = urllib.request.Request(remote, method="HEAD")
        with urllib.request.urlopen(request, timeout=8) as response:
            if response.status == 200:
                return {"kind": "url", "path": remote}
    except urllib.error.URLError:
        pass
    return {"kind": "none", "path": ""}


def display_name(slug: str, meta: dict) -> str:
    if meta.get("display"):
        return str(meta["display"])
    return slug.replace("-", " ").title()


def is_lut_preset(slug: str, meta: dict, group: str | None) -> bool:
    tags = " ".join(meta.get("tags", []))
    haystack = f"{slug} {tags}"
    if LUT_HINT.search(haystack):
        return True
    if group == "film_emulation":
        return True
    return slug in {
        "bleach-bypass-lut",
        "teal-orange-hollywood-cc",
        "day-for-night-lut",
        "teal-orange-blockbuster",
        "cross-process-e-6-to-c-41",
        "arri-alexa-logc-to-rec709",
    }


def build_preset(slug: str, group_id: str) -> dict:
    meta = fetch_meta(slug)
    thumb = resolve_thumbnail(slug)
    return {
        "slug": slug,
        "display": display_name(slug, meta),
        "group": group_id,
        "tags": meta.get("tags", []),
        "best_for": meta.get("best_for", ""),
        "notes": meta.get("notes", ""),
        "prompt_preview": prompt_preview(slug),
        "thumbnail": thumb,
        "is_lut": is_lut_preset(slug, meta, group_id),
    }


def build_catalog() -> dict:
    manifest = load_manifest()
    config = load_startup_config()
    gen = config.get("generation", {})
    featured = manifest.get("featured_templates", [])
    groups_cfg = manifest.get("groups", {})

    groups: list[dict] = []
    lut_presets: list[dict] = []
    seen_lut: set[str] = set()

    if featured:
        presets = [build_preset(slug, "featured") for slug in featured]
        groups.append({"id": "featured", "label": GROUP_LABELS["featured"], "presets": presets})
        for preset in presets:
            if preset["is_lut"] and preset["slug"] not in seen_lut:
                lut_presets.append(preset)
                seen_lut.add(preset["slug"])

    for group_id, slugs in groups_cfg.items():
        presets = [build_preset(slug, group_id) for slug in slugs]
        groups.append(
            {
                "id": group_id,
                "label": GROUP_LABELS.get(group_id, group_id.replace("_", " ").title()),
                "presets": presets,
            }
        )
        for preset in presets:
            if preset["is_lut"] and preset["slug"] not in seen_lut:
                lut_presets.append(preset)
                seen_lut.add(preset["slug"])

    defaults = {
        "slug": (config.get("featured_slugs") or ["neo-noir"])[0],
        "prompt": "woman in rain on empty street at night",
        "duration_sec": int(gen.get("duration_sec", 10)),
        "resolution": gen.get("resolution", "720p"),
        "aspect_ratio": gen.get("aspect_ratio", "16:9"),
        "lut_slug": "",
        "prompt_add": "",
        "continuity_notes": "",
    }

    return {
        "version": 1,
        "preset_count": len(all_slugs()),
        "defaults": defaults,
        "groups": groups,
        "lut_presets": lut_presets,
        "durations": [5, 8, 10, 12, 15],
        "resolutions": ["480p", "720p"],
        "aspect_ratios": ["16:9", "9:16", "1:1", "4:3", "3:4", "21:9"],
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Build Grok generate UI catalog")
    parser.add_argument("--stdout", action="store_true", help="print JSON instead of writing file")
    args = parser.parse_args()

    catalog = build_catalog()
    payload = json.dumps(catalog, indent=2)
    if args.stdout:
        print(payload)
        return 0

    GENERATE_UI.parent.mkdir(parents=True, exist_ok=True)
    GENERATE_UI.write_text(payload, encoding="utf-8")
    print(f"wrote {GENERATE_UI} ({catalog['preset_count']} slugs)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())