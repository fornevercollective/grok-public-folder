#!/usr/bin/env python3
"""Headless actions for Grok.lua menu (Resolve Free has no Python UI)."""

from __future__ import annotations

import argparse
import subprocess
import sys

from grok_paths import ROOT


def cmd_scan(_: argparse.Namespace) -> int:
    from grok_downloads_scan import main as scan_main

    sys.argv = ["grok_downloads_scan"]
    return scan_main()


def cmd_open_folder(_: argparse.Namespace) -> int:
    subprocess.run(["open", str(ROOT)], check=False)
    return 0


def cmd_bridge(_: argparse.Namespace) -> int:
    bridge = ROOT / "bin" / "bridge"
    subprocess.Popen(["/bin/bash", "-lc", f'export XAI_API_KEY="$XAI_API_KEY"; "{bridge}"'])
    print("started bin/bridge — set XAI_API_KEY in terminal")
    return 0


def cmd_generate(args: argparse.Namespace) -> int:
    from grok_api import generate_video, require_api_key
    from grok_presets import compose_prompt
    from grok_startup import load_startup_config

    api_key = require_api_key()
    config = load_startup_config()
    gen = config.get("generation", {})
    prompt = compose_prompt(args.slug, base_prompt=args.prompt)
    path = generate_video(
        api_key,
        prompt,
        duration=int(gen.get("duration_sec", 10)),
        aspect_ratio=gen.get("aspect_ratio", "16:9"),
        resolution=gen.get("resolution", "720p"),
    )
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