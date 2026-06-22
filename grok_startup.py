#!/usr/bin/env python3
"""Bootstrap Resolve project: 4K timeline, media bins, preset pipe."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import yaml

from grok_paths import PROJECT_DIR, ROOT, STARTUP_CONFIG
from grok_presets import all_slugs, load_manifest
from grok_resolve_env import connection_help, diagnose


def load_startup_config() -> dict:
    return yaml.safe_load(STARTUP_CONFIG.read_text(encoding="utf-8"))


def ensure_story_dirs() -> None:
    (PROJECT_DIR / "stories").mkdir(parents=True, exist_ok=True)
    (ROOT / "video").mkdir(exist_ok=True)
    (ROOT / "image").mkdir(exist_ok=True)
    (ROOT / "bridge").mkdir(exist_ok=True)


def write_state(config: dict) -> Path:
    state = {
        "project": config.get("project", {}),
        "resolve": config.get("resolve", {}),
        "generation": config.get("generation", {}),
        "import_target_bin": config.get("import_target_bin"),
        "featured_slugs": config.get("featured_slugs", []),
        "all_slug_count": len(all_slugs()),
        "pipe": config.get("pipe", {}),
    }
    path = PROJECT_DIR / "startup-state.json"
    path.write_text(json.dumps(state, indent=2), encoding="utf-8")
    return path


def get_resolve():
    from grok_api import get_resolve

    return get_resolve()


def find_or_create_bin(media_pool, root, path: str):
    parts = [p for p in path.split("/") if p]
    current = root
    for part in parts:
        found = None
        if hasattr(current, "GetSubFolderList"):
            for sub in current.GetSubFolderList() or []:
                if sub.GetName() == part:
                    found = sub
                    break
        if found is None:
            found = media_pool.AddSubFolder(current, part)
        current = found
    return current


def apply_resolve_settings(project, resolve_cfg: dict) -> list[str]:
    applied = []
    settings = {
        "timelineResolutionWidth": str(resolve_cfg.get("timeline_width", 3840)),
        "timelineResolutionHeight": str(resolve_cfg.get("timeline_height", 2160)),
        "timelineFrameRate": str(resolve_cfg.get("timeline_frame_rate", "23.976")),
    }
    for key, value in settings.items():
        if project.SetSetting(key, value):
            applied.append(f"{key}={value}")
    return applied


def bootstrap_resolve(config: dict, create_project: bool = False, project_name: str = "Grok Resolve Startup") -> dict:
    resolve = get_resolve()
    if not resolve:
        raise RuntimeError(connection_help())

    pm = resolve.GetProjectManager()
    project = pm.GetCurrentProject()
    if not project and create_project:
        project = pm.CreateProject(project_name)
    if not project:
        raise RuntimeError("open a resolve project first or pass --create-project")

    media_pool = project.GetMediaPool()
    root = media_pool.GetRootFolder()
    bins = []
    for spec in config.get("media_pool_bins", []):
        folder = find_or_create_bin(media_pool, root, spec)
        bins.append(spec)
        target = config.get("import_target_bin")
        if target and spec == target:
            media_pool.SetCurrentFolder(folder)

    settings = apply_resolve_settings(project, config.get("resolve", {}))
    return {
        "project": project.GetName(),
        "bins": bins,
        "settings": settings,
        "import_target_bin": config.get("import_target_bin"),
    }


def format_report(config: dict, resolve_result: dict | None = None) -> str:
    resolve_cfg = config.get("resolve", {})
    gen = config.get("generation", {})
    lines = [
        f"startup {config.get('project', {}).get('name', 'grok-resolve-startup')}",
        f"timeline {resolve_cfg.get('timeline_width')}x{resolve_cfg.get('timeline_height')} @ {resolve_cfg.get('timeline_frame_rate')} fps",
        f"generation {gen.get('resolution')} {gen.get('aspect_ratio')} (upscale in post)",
        f"presets {len(all_slugs())} slugs from imagine",
        f"featured {', '.join(config.get('featured_slugs', [])[:6])}...",
    ]
    if resolve_result:
        lines.append(f"resolve project {resolve_result.get('project')}")
        lines.append(f"bins {len(resolve_result.get('bins', []))}")
        lines.append(f"active bin {resolve_result.get('import_target_bin')}")
        for item in resolve_result.get("settings", []):
            lines.append(f"  {item}")
    pipe = config.get("pipe", {})
    lines.append("")
    lines.append("pipe")
    lines.append(f"  imagine → {pipe.get('generation', {}).get('output', 'video/ image/')}")
    lines.append(f"  resolve → {pipe.get('editing', {}).get('import_bin')}")
    lines.append(f"  colossus → {pipe.get('training', {}).get('launch')}")
    lines.append(f"  dojo     → slug {pipe.get('training', {}).get('dojo_slug')}")
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description="Grok Resolve startup bootstrap")
    parser.add_argument("--create-project", action="store_true", help="create project if none open")
    parser.add_argument("--project-name", default="Grok Resolve Startup")
    parser.add_argument("--resolve-only", action="store_true", help="only configure resolve, skip state write")
    parser.add_argument("--list-slugs", action="store_true")
    parser.add_argument("--check", action="store_true", help="diagnose terminal connection to Resolve")
    args = parser.parse_args()

    if args.check:
        info = diagnose()
        for key, value in info.items():
            print(f"{key}: {value}")
        if not info.get("connected"):
            print()
            print(connection_help())
            return 1
        return 0

    if args.list_slugs:
        manifest = load_manifest()
        for group, slugs in manifest.get("groups", {}).items():
            print(f"[{group}]")
            for slug in slugs:
                print(f"  {slug}")
        print("[featured]")
        for slug in manifest.get("featured_templates", []):
            print(f"  {slug}")
        return 0

    config = load_startup_config()
    ensure_story_dirs()
    resolve_result = None
    try:
        resolve_result = bootstrap_resolve(config, create_project=args.create_project, project_name=args.project_name)
    except RuntimeError as exc:
        print(str(exc), file=sys.stderr)

    if not args.resolve_only:
        state_path = write_state(config)
        print(f"state {state_path}")

    print(format_report(config, resolve_result))
    if resolve_result:
        return 0
    print("\nfolder + presets ready")
    print("resolve bootstrap: use Workspace → Scripts → Utility → Grok Bootstrap")
    print("(Terminal link requires Resolve Studio + External scripting → Local)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())