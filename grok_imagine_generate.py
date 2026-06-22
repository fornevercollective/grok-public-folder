#!/usr/bin/env python3
"""Generate Grok Imagine media via xAI API and save into the Resolve artifacts folder."""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

ARTIFACTS_ROOT = Path(__file__).resolve().parent
API_BASE = "https://api.x.ai/v1"


def api_request(method: str, path: str, api_key: str, payload: dict | None = None) -> dict:
    data = None if payload is None else json.dumps(payload).encode("utf-8")
    request = urllib.request.Request(
        f"{API_BASE}{path}",
        data=data,
        method=method,
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=120) as response:
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"xAI API error {exc.code}: {body}") from exc


def download_file(url: str, destination: Path) -> None:
    request = urllib.request.Request(url)
    with urllib.request.urlopen(request, timeout=300) as response:
        destination.write_bytes(response.read())


def poll_video(api_key: str, request_id: str, timeout_seconds: int = 900) -> dict:
    deadline = time.time() + timeout_seconds
    while time.time() < deadline:
        result = api_request("GET", f"/videos/{request_id}", api_key)
        status = result.get("status")
        if status == "done":
            return result
        if status in {"failed", "expired"}:
            raise RuntimeError(json.dumps(result, indent=2))
        print(f"status={status}; waiting...")
        time.sleep(5)
    raise TimeoutError(f"Timed out waiting for video request {request_id}")


def generate_video(api_key: str, prompt: str, duration: int, aspect_ratio: str, resolution: str) -> Path:
    started = api_request(
        "POST",
        "/videos/generations",
        api_key,
        {
            "model": "grok-imagine-video",
            "prompt": prompt,
            "duration": duration,
            "aspect_ratio": aspect_ratio,
            "resolution": resolution,
        },
    )
    request_id = started["request_id"]
    print(f"started video job: {request_id}")
    result = poll_video(api_key, request_id)
    video_url = result["video"]["url"]
    stamp = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
    destination = ARTIFACTS_ROOT / "video" / f"grok_{stamp}.mp4"
    print(f"downloading {video_url}")
    download_file(video_url, destination)
    return destination


def generate_image(api_key: str, prompt: str) -> Path:
    result = api_request(
        "POST",
        "/images/generations",
        api_key,
        {
            "model": "grok-imagine-image-quality",
            "prompt": prompt,
        },
    )
    image_url = result["data"][0]["url"]
    stamp = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
    destination = ARTIFACTS_ROOT / "image" / f"grok_{stamp}.png"
    print(f"downloading {image_url}")
    download_file(image_url, destination)
    return destination


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate Grok Imagine assets into Resolve artifacts.")
    parser.add_argument("prompt", help="Generation prompt")
    parser.add_argument("--mode", choices=("video", "image"), default="video")
    parser.add_argument("--duration", type=int, default=8)
    parser.add_argument("--aspect-ratio", default="16:9")
    parser.add_argument("--resolution", choices=("480p", "720p"), default="720p")
    args = parser.parse_args()

    api_key = os.environ.get("XAI_API_KEY")
    if not api_key:
        print("Set XAI_API_KEY first: export XAI_API_KEY='your-key'", file=sys.stderr)
        return 1

    if args.mode == "video":
        output = generate_video(api_key, args.prompt, args.duration, args.aspect_ratio, args.resolution)
    else:
        output = generate_image(api_key, args.prompt)

    print(output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())