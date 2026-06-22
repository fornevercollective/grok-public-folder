#!/usr/bin/env python3
"""Headless actions for Grok.lua menu (Resolve Free has no Python UI)."""

from __future__ import annotations

import argparse
import subprocess
import sys
import traceback
from datetime import datetime, timezone

from grok_paths import BRIDGE_DIR, ROOT

LOG_FILE = BRIDGE_DIR / "menu-last.log"


def log(message: str) -> None:
    BRIDGE_DIR.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")
    line = f"[{stamp}] {message}\n"
    with LOG_FILE.open("a", encoding="utf-8") as handle:
        handle.write(line)
    print(message, flush=True)


def notify_macos(title: str, message: str) -> None:
    safe_title = title.replace("\\", "\\\\").replace('"', '\\"')
    safe_message = message.replace("\\", "\\\\").replace('"', '\\"')
    subprocess.run(
        [
            "osascript",
            "-e",
            f'display notification "{safe_message}" with title "{safe_title}"',
        ],
        check=False,
    )


def cmd_scan(_: argparse.Namespace) -> int:
    from grok_downloads_scan import main as scan_main

    log("scan: starting")
    sys.argv = ["grok_downloads_scan"]
    try:
        code = scan_main()
    except Exception as exc:
        log(f"scan: failed — {exc}")
        notify_macos("Grok", f"scan failed: {exc}")
        return 1
    log(f"scan: finished (exit {code})")
    return code


def cmd_open_folder(_: argparse.Namespace) -> int:
    subprocess.run(["open", str(ROOT)], check=False)
    log("open-folder: opened in Finder")
    return 0


def cmd_bridge(_: argparse.Namespace) -> int:
    bridge = ROOT / "bin" / "bridge"
    log("bridge: starting in background")
    subprocess.Popen(["/bin/bash", "-lc", f'export XAI_API_KEY="$XAI_API_KEY"; "{bridge}"'])
    print("started bin/bridge — set XAI_API_KEY in terminal")
    return 0


def cmd_generate(args: argparse.Namespace) -> int:
    from grok_api import generate_video, require_api_key
    from grok_presets import compose_prompt
    from grok_startup import load_startup_config

    slug = args.slug.strip()
    prompt = args.prompt.strip()
    log(f"generate: slug={slug!r} prompt={prompt!r}")

    try:
        api_key = require_api_key()
        config = load_startup_config()
        gen = config.get("generation", {})
        composed = compose_prompt(slug, base_prompt=prompt)
        log(f"generate: composed prompt ({len(composed)} chars)")
        log("generate: calling xAI video API — this can take several minutes")

        def on_status(status: str | None) -> None:
            if status:
                log(f"generate: status={status}")

        path = generate_video(
            api_key,
            composed,
            duration=int(gen.get("duration_sec", 10)),
            aspect_ratio=gen.get("aspect_ratio", "16:9"),
            resolution=gen.get("resolution", "720p"),
            on_status=on_status,
        )
    except Exception as exc:
        log(f"generate: failed — {exc}")
        traceback.print_exc()
        notify_macos("Grok generate failed", str(exc))
        print(f"\nERROR: {exc}", file=sys.stderr)
        if "XAI_API_KEY" in str(exc):
            print("Set your key in Terminal: export XAI_API_KEY=your-key", file=sys.stderr)
        return 1

    log(f"generate: saved {path}")
    notify_macos("Grok", f"video saved: {path.name}")
    print(path)
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Grok menu CLI for Lua launcher")
    sub = parser.add_subparsers(dest="cmd", required=True)

    sub.add_parser("scan", help="scan downloads and offer to move")
    sub.add_parser("open-folder", help="open grok-public-folder in Finder")
    sub.add_parser("bridge", help="start terminal bridge")

    gen = sub.add_parser("generate", help="generate video with imagine slug")
    gen.add_argument("--slug", required=True)
    gen.add_argument("--prompt", default="")

    args = parser.parse_args()
    if args.cmd == "scan":
        return cmd_scan(args)
    if args.cmd == "open-folder":
        return cmd_open_folder(args)
    if args.cmd == "bridge":
        return cmd_bridge(args)
    if args.cmd == "generate":
        return cmd_generate(args)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())