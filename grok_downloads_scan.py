#!/usr/bin/env python3
"""Scan Downloads for Grok media and offer to move into artifacts."""

from __future__ import annotations

import argparse
import subprocess
from pathlib import Path

from grok_meta import ARTIFACTS_ROOT, is_grok_download, move_to_artifacts

DOWNLOADS = Path.home() / "Downloads"
MEDIA_EXT = {".mp4", ".mov", ".m4v", ".webm", ".png", ".jpg", ".jpeg", ".webp", ".gif"}


def scan_downloads(downloads_dir: Path = DOWNLOADS) -> list[Path]:
    hits: list[Path] = []
    if not downloads_dir.exists():
        return hits
    for path in sorted(downloads_dir.iterdir()):
        if not path.is_file() or path.name.startswith("."):
            continue
        if path.suffix.lower() not in MEDIA_EXT:
            continue
        ok, _ = is_grok_download(path)
        if ok:
            hits.append(path)
    return hits


def ask_yes_no(title: str, message: str) -> bool:
    script = f'display dialog {json_escape(message)} with title {json_escape(title)} buttons {{"No", "Yes"}} default button "Yes"'
    try:
        result = subprocess.run(["osascript", "-e", script], check=True, capture_output=True, text=True)
        return "Yes" in result.stdout
    except subprocess.CalledProcessError:
        return False


def ask_move_files(files: list[Path]) -> bool:
    lines = [f"• {path.name}" for path in files[:12]]
    if len(files) > 12:
        lines.append(f"• ...and {len(files) - 12} more")
    body = "Move these Grok downloads into artifacts?\n\n" + "\n".join(lines)
    return ask_yes_no("Grok Downloads", body)


def json_escape(value: str) -> str:
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


def preview_files(files: list[Path]) -> None:
    for path in files[:6]:
        subprocess.run(["open", str(path)], check=False)


def main() -> int:
    parser = argparse.ArgumentParser(description="Scan Downloads for Grok media")
    parser.add_argument("--yes", action="store_true", help="move without asking")
    parser.add_argument("--preview", action="store_true", help="open files in default app")
    parser.add_argument("--downloads", default=str(DOWNLOADS))
    args = parser.parse_args()

    files = scan_downloads(Path(args.downloads))
    if not files:
        print("no grok media found in downloads")
        print("looking for grok.com or x.ai in download metadata")
        return 0

    print(f"found {len(files)} grok file(s)")
    for path in files:
        _, reason = is_grok_download(path)
        print(f"  {path.name}  [{reason}]")

    if args.preview:
        preview_files(files)

    if not args.yes and not ask_move_files(files):
        print("skipped")
        return 0

    moved = []
    for path in files:
        dest = move_to_artifacts(path)
        moved.append(dest)
        print(f"moved {dest.name} -> {dest.parent.name}/")

    print(f"done moved {len(moved)} into {ARTIFACTS_ROOT}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())