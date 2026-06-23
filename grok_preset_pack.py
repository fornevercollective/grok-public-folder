#!/usr/bin/env python3
"""Warm preset cache and rebuild UI catalog for the cinematic 50-preset pack."""

from __future__ import annotations

import argparse
import json
import sys

from grok_generate_catalog import build_catalog
from grok_paths import GENERATE_UI, PRESET_CACHE_DIR, PROJECT_DIR, ROOT
from grok_presets import all_slugs, fetch_preset_prompt

PACK_FILE = PROJECT_DIR / "cinematic-pack-50.json"


def load_pack() -> list[str]:
    if not PACK_FILE.exists():
        return []
    data = json.loads(PACK_FILE.read_text(encoding="utf-8"))
    slugs = [str(s).strip() for s in data.get("slugs") or [] if str(s).strip()]
    return slugs


def warm_cache(slugs: list[str], force: bool = False) -> dict:
    PRESET_CACHE_DIR.mkdir(parents=True, exist_ok=True)
    ok: list[str] = []
    failed: list[str] = []
    skipped: list[str] = []
    for slug in slugs:
        cached = PRESET_CACHE_DIR / f"{slug}.txt"
        if cached.exists() and not force:
            skipped.append(slug)
            continue
        try:
            text = fetch_preset_prompt(slug)
            if text.strip():
                ok.append(slug)
            else:
                failed.append(slug)
        except RuntimeError:
            failed.append(slug)
    return {"ok": ok, "failed": failed, "skipped": skipped, "total": len(slugs)}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Cinematic 50-preset pack — cache warm + catalog rebuild")
    parser.add_argument("--warm", action="store_true", help="fetch missing preset prompts into preset-cache/")
    parser.add_argument("--force", action="store_true", help="re-fetch even when cache exists")
    parser.add_argument("--rebuild", action="store_true", help="regenerate project/generate-ui.json")
    parser.add_argument("--list", action="store_true", help="print pack slugs")
    args = parser.parse_args(argv)

    slugs = load_pack()
    if not slugs:
        print(f"no pack found at {PACK_FILE}", file=sys.stderr)
        return 1

    if args.list:
        for slug in slugs:
            print(slug)
        print(f"# {len(slugs)} slugs")
        return 0

    if not (args.warm or args.rebuild):
        args.warm = True
        args.rebuild = True

    if args.warm:
        result = warm_cache(slugs, force=args.force)
        print(
            json.dumps(
                {
                    "pack": PACK_FILE.name,
                    "root": str(ROOT),
                    "warmed": len(result["ok"]),
                    "skipped": len(result["skipped"]),
                    "failed": result["failed"],
                },
                indent=2,
            )
        )

    if args.rebuild:
        catalog = build_catalog()
        GENERATE_UI.parent.mkdir(parents=True, exist_ok=True)
        GENERATE_UI.write_text(json.dumps(catalog, indent=2), encoding="utf-8")
        pack_in_catalog = sum(
            1 for g in catalog.get("groups", []) for p in g.get("presets", []) if p.get("slug") in slugs
        )
        print(f"wrote {GENERATE_UI} — pack slugs in UI: {pack_in_catalog}/{len(slugs)} (manifest total: {len(all_slugs())})")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())