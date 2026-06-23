#!/usr/bin/env python3
"""Canvas tab helpers — Grok Imagine handoff + bridge image/video from UI."""

from __future__ import annotations

import argparse
import json
import sys

from grok_bridge_client import send
from grok_paths import ROOT
from grok_secrets import load_secrets

load_secrets()


def _compose_prompt(prompt: str, slug: str = "", prompt_add: str = "", lut: str = "") -> str:
    parts: list[str] = []
    if slug:
        try:
            from grok_presets import compose_prompt

            parts.append(compose_prompt(slug, base_prompt=prompt))
        except RuntimeError:
            parts.append(prompt)
    elif prompt.strip():
        parts.append(prompt.strip())
    if lut.strip():
        try:
            from grok_presets import compose_prompt

            lut_style = compose_prompt(lut.strip(), base_prompt="")
            if lut_style:
                parts.append(lut_style)
        except RuntimeError:
            parts.append(f"apply {lut} color grade")
    if prompt_add.strip():
        parts.append(prompt_add.strip())
    return ". ".join(p for p in parts if p)


def bridge_ping() -> dict:
    message = send("ping", "", timeout=15)
    return {"ok": message is not None, "message": message or "bridge offline — run bin/bridge"}


def bridge_image(
    prompt: str,
    slug: str = "",
    prompt_add: str = "",
    lut: str = "",
    aspect: str = "16:9",
) -> dict:
    text = _compose_prompt(prompt, slug=slug, prompt_add=prompt_add, lut=lut)
    if not text:
        return {"ok": False, "error": "empty prompt"}
    opts: dict = {"aspect_ratio": aspect, "timeout": 120}
    if slug:
        opts["slug"] = slug
    message = send("image", text, **opts)
    return {"ok": message is not None, "message": message or "bridge image failed", "prompt": text}


def bridge_video(
    prompt: str,
    slug: str = "",
    prompt_add: str = "",
    lut: str = "",
    duration: int = 10,
    resolution: str = "720p",
    aspect: str = "16:9",
) -> dict:
    text = _compose_prompt(prompt, slug=slug, prompt_add=prompt_add, lut=lut)
    if not text:
        return {"ok": False, "error": "empty prompt"}
    opts: dict = {
        "duration": int(duration),
        "resolution": resolution,
        "aspect_ratio": aspect,
        "timeout": 900,
    }
    if slug:
        opts["slug"] = slug
    message = send("video", text, **opts)
    return {"ok": message is not None, "message": message or "bridge video failed", "prompt": text}


def imagine_open() -> dict:
    from grok_browser import open_imagine

    return {"ok": True, **open_imagine()}


def imagine_push(prompt: str) -> dict:
    from grok_browser import push_prompt

    result = push_prompt(prompt)
    return {"ok": bool(result.get("ok", True)), **result}


def imagine_pull() -> dict:
    from grok_browser import pull_prompt

    result = pull_prompt()
    if result.get("prompt"):
        result["ok"] = True
    return result


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Canvas Imagine + bridge commands")
    sub = parser.add_subparsers(dest="cmd", required=True)

    sub.add_parser("ping", help="test bridge online")

    p_img = sub.add_parser("image", help="bridge /image with canvas settings")
    p_img.add_argument("--prompt", required=True)
    p_img.add_argument("--slug", default="")
    p_img.add_argument("--prompt-add", default="")
    p_img.add_argument("--lut", default="")
    p_img.add_argument("--aspect", default="16:9")

    p_vid = sub.add_parser("video", help="bridge /video with canvas settings")
    p_vid.add_argument("--prompt", required=True)
    p_vid.add_argument("--slug", default="")
    p_vid.add_argument("--prompt-add", default="")
    p_vid.add_argument("--lut", default="")
    p_vid.add_argument("--duration", type=int, default=10)
    p_vid.add_argument("--resolution", default="720p")
    p_vid.add_argument("--aspect", default="16:9")

    p_push = sub.add_parser("push", help="push prompt to Grok Imagine (Safari)")
    p_push.add_argument("prompt", nargs="+")

    sub.add_parser("pull", help="pull prompt from Imagine inbox or clipboard")
    sub.add_parser("open", help="open grok.com/imagine in Safari")

    args = parser.parse_args(argv)

    try:
        if args.cmd == "ping":
            print(json.dumps(bridge_ping(), indent=2))
            return 0
        if args.cmd == "image":
            print(json.dumps(bridge_image(
                args.prompt, slug=args.slug, prompt_add=args.prompt_add,
                lut=args.lut, aspect=args.aspect,
            ), indent=2))
            return 0
        if args.cmd == "video":
            print(json.dumps(bridge_video(
                args.prompt, slug=args.slug, prompt_add=args.prompt_add,
                lut=args.lut, duration=args.duration,
                resolution=args.resolution, aspect=args.aspect,
            ), indent=2))
            return 0
        if args.cmd == "open":
            print(json.dumps(imagine_open(), indent=2))
            return 0
        if args.cmd == "push":
            prompt = " ".join(args.prompt)
            print(json.dumps(imagine_push(prompt), indent=2))
            return 0
        if args.cmd == "pull":
            result = imagine_pull()
            print(json.dumps(result, indent=2))
            return 0
    except Exception as exc:
        print(json.dumps({"ok": False, "error": str(exc), "root": str(ROOT)}))
        return 1

    return 1


if __name__ == "__main__":
    raise SystemExit(main())