#!/usr/bin/env python3
"""Terminal bridge: watches bridge/request.json from Resolve Lua console."""

from __future__ import annotations

import json
import sys
import time
import traceback
from pathlib import Path

from grok_api import (
    BRIDGE_DIR,
    ARTIFACTS_ROOT,
    chat,
    clear_chat_history,
    generate_image,
    generate_video,
    import_all_artifacts,
    load_chat_history,
    require_api_key,
    save_chat_history,
)

REQUEST_FILE = BRIDGE_DIR / "request.json"
RESPONSE_FILE = BRIDGE_DIR / "response.json"
PID_FILE = BRIDGE_DIR / "bridge.pid"


def write_response(payload: dict) -> None:
    BRIDGE_DIR.mkdir(parents=True, exist_ok=True)
    RESPONSE_FILE.write_text(json.dumps(payload, indent=2), encoding="utf-8")


def handle_request(payload: dict) -> dict:
    req_id = payload.get("id", "unknown")
    action = (payload.get("action") or "chat").lower()
    text = (payload.get("text") or "").strip()

    try:
        api_key = require_api_key()
    except RuntimeError as exc:
        return {"id": req_id, "ok": False, "message": str(exc), "files": []}

    try:
        if action == "ping":
            return {
                "id": req_id,
                "ok": True,
                "message": "bridge online",
                "files": [],
            }

        if action == "clear":
            clear_chat_history()
            return {
                "id": req_id,
                "ok": True,
                "message": "chat cleared",
                "files": [],
            }

        if action == "import":
            count, files, bin_name = import_all_artifacts()
            if count == 0:
                return {
                    "id": req_id,
                    "ok": False,
                    "message": "no files yet generate first with g(/video prompt)",
                    "files": [],
                }
            return {
                "id": req_id,
                "ok": True,
                "message": f"imported {count} into {bin_name}",
                "files": files,
            }

        if action == "image":
            if not text:
                raise ValueError("image request needs text")
            path = generate_image(api_key, text, aspect_ratio=payload.get("aspect_ratio", "16:9"))
            return {
                "id": req_id,
                "ok": True,
                "message": f"saved image {path.name}",
                "files": [str(path)],
            }

        if action == "video":
            if not text:
                raise ValueError("video request needs text")
            path = generate_video(
                api_key,
                text,
                duration=int(payload.get("duration", 8)),
                aspect_ratio=payload.get("aspect_ratio", "16:9"),
                resolution=payload.get("resolution", "720p"),
                on_status=lambda status: print(f"[bridge] video status: {status}"),
            )
            return {
                "id": req_id,
                "ok": True,
                "message": f"saved video {path.name}",
                "files": [str(path)],
            }

        if action == "chat":
            if not text:
                raise ValueError("chat request needs text")
            messages = load_chat_history()
            messages.append({"role": "user", "content": text})
            reply = chat(api_key, messages)
            messages.append({"role": "assistant", "content": reply})
            save_chat_history(messages)
            return {
                "id": req_id,
                "ok": True,
                "message": reply,
                "files": [],
            }

        raise ValueError(f"unknown action: {action}")
    except Exception as exc:
        return {
            "id": req_id,
            "ok": False,
            "message": str(exc),
            "files": [],
            "trace": traceback.format_exc(limit=3),
        }


def process_request_file() -> bool:
    if not REQUEST_FILE.exists():
        return False

    try:
        payload = json.loads(REQUEST_FILE.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        write_response({"id": "invalid", "ok": False, "message": f"bad request json: {exc}", "files": []})
        REQUEST_FILE.unlink(missing_ok=True)
        return True

    REQUEST_FILE.unlink(missing_ok=True)
    print(f"[bridge] {payload.get('action', 'chat')}: {payload.get('text', '')[:80]}")
    response = handle_request(payload)
    write_response(response)
    print(f"[bridge] done: {response.get('message', '')[:120]}")
    return True


def main() -> int:
    BRIDGE_DIR.mkdir(parents=True, exist_ok=True)
    PID_FILE.write_text(str(Path(__file__).resolve()), encoding="utf-8")
    print("Grok bridge running")
    print(f"Artifacts: {ARTIFACTS_ROOT}")
    print("Waiting for Resolve Lua requests...")
    print("Press Ctrl+C to stop.\n")

    try:
        while True:
            if process_request_file():
                continue
            time.sleep(0.25)
    except KeyboardInterrupt:
        print("\nBridge stopped.")
        PID_FILE.unlink(missing_ok=True)
        return 0


if __name__ == "__main__":
    raise SystemExit(main())