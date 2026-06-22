#!/usr/bin/env python3
"""Shared Grok API helpers for console and Resolve bridge."""

from __future__ import annotations

import json
import os
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone
from grok_paths import BRIDGE_DIR, IMAGE_DIR, ROOT, VIDEO_DIR

ARTIFACTS_ROOT = ROOT
API_BASE = "https://api.x.ai/v1"
CHAT_MODEL = os.environ.get("GROK_CHAT_MODEL", "grok-4.3")
SYSTEM_PROMPT = (
    "You are Grok, a creative copilot for a DaVinci Resolve filmmaker. "
    "Help with prompts, shot ideas, scene planning, and editing workflow. "
    "When asked to generate media, suggest concise visual prompts. "
    "Keep answers practical and brief unless the user wants detail."
)
CHAT_HISTORY_FILE = BRIDGE_DIR / "chat_history.json"


def require_api_key() -> str:
    api_key = os.environ.get("XAI_API_KEY", "").strip()
    if not api_key:
        raise RuntimeError("XAI_API_KEY is not set")
    return api_key


def api_request(method: str, path: str, api_key: str, payload: dict | None = None, timeout: int = 120) -> dict:
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
        with urllib.request.urlopen(request, timeout=timeout) as response:
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"xAI API error {exc.code}: {body}") from exc


def download_file(url: str, destination: Path) -> None:
    request = urllib.request.Request(url)
    with urllib.request.urlopen(request, timeout=300) as response:
        destination.write_bytes(response.read())


def stamp() -> str:
    return datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")


def poll_video(api_key: str, request_id: str, timeout_seconds: int = 900, on_status=None) -> dict:
    deadline = time.time() + timeout_seconds
    while time.time() < deadline:
        result = api_request("GET", f"/videos/{request_id}", api_key, timeout=30)
        status = result.get("status")
        if on_status:
            on_status(status)
        if status == "done":
            return result
        if status in {"failed", "expired"}:
            raise RuntimeError(json.dumps(result, indent=2))
        time.sleep(5)
    raise TimeoutError(f"Timed out waiting for video request {request_id}")


def attach_sidecar(path: Path, action: str, prompt: str, **extra) -> None:
    from grok_meta import write_sidecar

    write_sidecar(
        path,
        {
            "action": action,
            "prompt": prompt,
            "model": extra.get("model", "grok-imagine-video"),
            **extra,
        },
    )


def generate_video(
    api_key: str,
    prompt: str,
    duration: int = 8,
    aspect_ratio: str = "16:9",
    resolution: str = "720p",
    on_status=None,
) -> Path:
    VIDEO_DIR.mkdir(parents=True, exist_ok=True)
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
    result = poll_video(api_key, started["request_id"], on_status=on_status)
    destination = VIDEO_DIR / f"grok_{stamp()}.mp4"
    download_file(result["video"]["url"], destination)
    attach_sidecar(destination, "video", prompt, duration=duration, aspect_ratio=aspect_ratio, resolution=resolution)
    return destination


def generate_image(api_key: str, prompt: str, aspect_ratio: str = "16:9") -> Path:
    IMAGE_DIR.mkdir(parents=True, exist_ok=True)
    result = api_request(
        "POST",
        "/images/generations",
        api_key,
        {
            "model": "grok-imagine-image-quality",
            "prompt": prompt,
            "aspect_ratio": aspect_ratio,
        },
    )
    destination = IMAGE_DIR / f"grok_{stamp()}.png"
    download_file(result["data"][0]["url"], destination)
    attach_sidecar(destination, "image", prompt, model="grok-imagine-image-quality", aspect_ratio=aspect_ratio)
    return destination


def chat(api_key: str, messages: list[dict]) -> str:
    result = api_request(
        "POST",
        "/chat/completions",
        api_key,
        {
            "model": CHAT_MODEL,
            "messages": messages,
            "temperature": 0.7,
        },
        timeout=180,
    )
    return result["choices"][0]["message"]["content"]


def load_chat_history() -> list[dict]:
    if not CHAT_HISTORY_FILE.exists():
        return [{"role": "system", "content": SYSTEM_PROMPT}]
    try:
        data = json.loads(CHAT_HISTORY_FILE.read_text(encoding="utf-8"))
        if isinstance(data, list) and data:
            return data
    except json.JSONDecodeError:
        pass
    return [{"role": "system", "content": SYSTEM_PROMPT}]


def save_chat_history(messages: list[dict]) -> None:
    BRIDGE_DIR.mkdir(parents=True, exist_ok=True)
    CHAT_HISTORY_FILE.write_text(json.dumps(messages, indent=2), encoding="utf-8")


def clear_chat_history() -> None:
    save_chat_history([{"role": "system", "content": SYSTEM_PROMPT}])


def get_resolve():
    from grok_resolve_env import ensure_resolve_env

    ensure_resolve_env()
    import DaVinciResolveScript as dvr_script

    return dvr_script.scriptapp("Resolve")


def list_artifact_files() -> list[str]:
    files: list[str] = []
    for folder in (VIDEO_DIR, IMAGE_DIR):
        if not folder.exists():
            continue
        for path in sorted(folder.iterdir()):
            if path.is_file() and not path.name.startswith("."):
                files.append(str(path))
    return files


def active_folder_name(media_pool) -> str:
    folder = media_pool.GetCurrentFolder()
    if folder:
        return folder.GetName()
    return "current bin"


def import_paths(paths: list[str]) -> tuple[list, str]:
    resolve = get_resolve()
    if not resolve:
        raise RuntimeError("resolve not running")
    project = resolve.GetProjectManager().GetCurrentProject()
    if not project:
        raise RuntimeError("open a project first")
    media_pool = project.GetMediaPool()
    bin_name = active_folder_name(media_pool)
    imported = media_pool.ImportMedia(paths) or []
    return imported, bin_name


def import_all_artifacts() -> tuple[int, list[str], str]:
    files = list_artifact_files()
    if not files:
        return 0, [], "current bin"
    imported, bin_name = import_paths(files)
    return len(imported), files, bin_name