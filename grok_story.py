#!/usr/bin/env python3
"""Generate story beats using Imagine preset slugs."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from grok_api import generate_video, require_api_key
from grok_paths import PROJECT_DIR, STARTUP_CONFIG
from grok_presets import compose_prompt

import yaml


def load_story(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def load_defaults() -> dict:
    cfg = yaml.safe_load(STARTUP_CONFIG.read_text(encoding="utf-8"))
    return cfg.get("generation", {})


def beat_prompt(story: dict, beat: dict) -> str:
    return compose_prompt(
        beat["style_slug"],
        base_prompt=story.get("base_prompt", ""),
        prompt_add=beat.get("prompt_add", ""),
        ancestry_bible=story.get("character_ancestry_bible", ""),
        continuity_notes=story.get("continuity_notes", ""),
    )


def generate_beat(story_path: Path, beat_id: str, dry_run: bool = False) -> Path | str:
    story = load_story(story_path)
    defaults = load_defaults()
    beat = next((b for b in story.get("beats", []) if b.get("beat_id") == beat_id), None)
    if not beat:
        raise ValueError(f"beat not found: {beat_id}")

    prompt = beat_prompt(story, beat)
    if dry_run:
        return prompt

    api_key = require_api_key()
    return generate_video(
        api_key,
        prompt,
        duration=int(beat.get("duration_sec", defaults.get("duration_sec", 10))),
        aspect_ratio=defaults.get("aspect_ratio", "16:9"),
        resolution=defaults.get("resolution", "720p"),
        on_status=lambda status: print(f"  {beat_id}: {status}"),
    )


def plan_story(story_path: Path) -> None:
    story = load_story(story_path)
    print(f"{story.get('title')} — {story.get('genre')}")
    for beat in story.get("beats", []):
        print(
            f"  {beat.get('beat_id')}: {beat.get('name')} "
            f"[{beat.get('style_slug')}] {beat.get('duration_sec')}s"
        )


def main() -> int:
    parser = argparse.ArgumentParser(description="Imagine story beat generator")
    parser.add_argument("story", nargs="?", default=str(PROJECT_DIR / "stories" / "dusk-to-neon.json"))
    parser.add_argument("--beat", help="beat_id to generate")
    parser.add_argument("--plan", action="store_true")
    parser.add_argument("--dry-run", action="store_true", help="print composed prompt only")
    args = parser.parse_args()

    story_path = Path(args.story)
    if not story_path.exists():
        print(f"story not found: {story_path}", file=sys.stderr)
        return 1

    if args.plan:
        plan_story(story_path)
        return 0

    if not args.beat:
        print("pass --beat <beat_id> or --plan", file=sys.stderr)
        return 1

    try:
        result = generate_beat(story_path, args.beat, dry_run=args.dry_run)
    except Exception as exc:
        print(exc, file=sys.stderr)
        return 1

    if args.dry_run:
        print(result)
    else:
        print(f"saved {result}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())