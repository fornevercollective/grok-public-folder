#!/usr/bin/env python3
"""X.com live workflow streaming toolkit for Grok Resolve."""

from __future__ import annotations

import json
import os
import subprocess
import sys
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

from grok_paths import ROOT, STREAMING_DIR

STATE_FILE = STREAMING_DIR / "state.json"
OVERLAY_FILE = STREAMING_DIR / "overlay.html"
OVERLAY_JSON = STREAMING_DIR / "overlay.json"
RTMP_TEMPLATE = STREAMING_DIR / "rtmp.template.json"

X_STUDIO_URL = "https://studio.x.com"
X_BROADCAST_URL = "https://x.com/i/broadcast"
X_API_BASE = "https://api.twitter.com/2"


def _ensure_streaming_dir() -> None:
    STREAMING_DIR.mkdir(parents=True, exist_ok=True)


def _read_state() -> dict:
    if not STATE_FILE.exists():
        return {}
    try:
        return json.loads(STATE_FILE.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return {}


def _write_state(payload: dict) -> None:
    _ensure_streaming_dir()
    STATE_FILE.write_text(json.dumps(payload, indent=2), encoding="utf-8")


def _bearer_token() -> str:
    return (
        os.environ.get("X_BEARER_TOKEN", "").strip()
        or os.environ.get("X_API_BEARER_TOKEN", "").strip()
    )


def _open_url(url: str) -> None:
    subprocess.run(["open", url], check=False)


def _write_overlay(title: str, subtitle: str, status: str) -> None:
    _ensure_streaming_dir()
    payload = {
        "title": title,
        "subtitle": subtitle,
        "status": status,
        "updated_at": datetime.now(timezone.utc).isoformat(),
        "root": str(ROOT),
    }
    OVERLAY_JSON.write_text(json.dumps(payload, indent=2), encoding="utf-8")
    html = f"""<!DOCTYPE html>
<html><head><meta charset="utf-8">
<style>
  body {{ margin:0; background:transparent; font-family:-apple-system,system-ui,sans-serif; }}
  .card {{
    display:inline-block; padding:14px 18px; border-radius:6px;
    background:rgba(27,29,32,0.88); border:1px solid #4a4d53;
    color:#e8eaed; min-width:320px;
  }}
  .title {{ font-size:18px; font-weight:600; color:#f98b14; }}
  .sub {{ font-size:12px; color:#c0c3c8; margin-top:4px; }}
  .status {{ font-size:11px; color:#aeb2b8; margin-top:8px; text-transform:uppercase; letter-spacing:.04em; }}
</style></head><body>
<div class="card">
  <div class="title">{title}</div>
  <div class="sub">{subtitle}</div>
  <div class="status">{status}</div>
</div>
</body></html>"""
    OVERLAY_FILE.write_text(html, encoding="utf-8")


def _default_rtmp_template() -> dict:
    return {
        "platform": "x.com",
        "notes": "Copy stream key from X Media Studio → OBS → Settings → Stream → Custom",
        "obs_settings": {
            "service": "Custom",
            "server": "rtmps://pscp.tv/x",
            "stream_key": "PASTE_FROM_X_STUDIO",
        },
        "browser_overlay": str(OVERLAY_FILE),
        "browser_overlay_json": str(OVERLAY_JSON),
    }


def stream_status() -> dict:
    state = _read_state()
    return {
        "root": str(ROOT),
        "streaming_dir": str(STREAMING_DIR),
        "live": bool(state.get("live")),
        "state": state,
        "x_bearer_configured": bool(_bearer_token()),
        "overlay_html": str(OVERLAY_FILE),
        "studio_url": X_STUDIO_URL,
    }


def open_studio() -> dict:
    _open_url(X_STUDIO_URL)
    _open_url(X_BROADCAST_URL)
    return {"ok": True, "message": "Opened X Media Studio and broadcast pages"}


def open_obs() -> dict:
    obs_apps = [
        "/Applications/OBS.app",
        "/Applications/OBS Studio.app",
    ]
    for app in obs_apps:
        if Path(app).exists():
            subprocess.run(["open", "-a", app], check=False)
            return {"ok": True, "message": f"Opened {app}"}
    return {"ok": False, "message": "OBS not found in /Applications — install OBS for RTMP stream"}


def start_workflow(title: str, subtitle: str = "") -> dict:
    stamp = datetime.now(timezone.utc).isoformat()
    state = {
        "live": True,
        "title": title,
        "subtitle": subtitle or "Grok for Resolve · live workflow",
        "started_at": stamp,
        "updated_at": stamp,
    }
    _write_state(state)
    _write_overlay(title, state["subtitle"], "LIVE · WORKFLOW")
    if not RTMP_TEMPLATE.exists():
        RTMP_TEMPLATE.write_text(json.dumps(_default_rtmp_template(), indent=2), encoding="utf-8")
    return {"ok": True, "message": "Workflow stream started", "state": state}


def stop_workflow() -> dict:
    state = _read_state()
    state["live"] = False
    state["stopped_at"] = datetime.now(timezone.utc).isoformat()
    _write_state(state)
    _write_overlay(
        state.get("title") or "Grok Workflow",
        state.get("subtitle") or "",
        "OFFLINE",
    )
    return {"ok": True, "message": "Workflow stream stopped", "state": state}


def post_announcement(text: str) -> dict:
    token = _bearer_token()
    if not token:
        return {
            "ok": False,
            "message": "Set X_BEARER_TOKEN to post announcements (X API v2)",
        }
    if not text.strip():
        return {"ok": False, "message": "empty announcement"}
    payload = json.dumps({"text": text[:280]}).encode("utf-8")
    request = urllib.request.Request(
        f"{X_API_BASE}/tweets",
        data=payload,
        method="POST",
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            data = json.loads(response.read().decode("utf-8"))
        return {"ok": True, "message": "Posted to X", "response": data}
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        return {"ok": False, "message": f"X API {exc.code}: {body}"}


def announce_workflow(extra: str = "") -> dict:
    state = _read_state()
    title = state.get("title") or "Grok for Resolve workflow"
    subtitle = state.get("subtitle") or ""
    live = "🔴 LIVE" if state.get("live") else "Starting soon"
    text = f"{live} — {title}"
    if subtitle:
        text += f" · {subtitle}"
    if extra:
        text += f" · {extra}"
    text += " #Grok #Resolve #filmmaking"
    return post_announcement(text)


def main(argv: list[str] | None = None) -> int:
    args = argv if argv is not None else sys.argv[1:]
    if not args or args[0] in {"-h", "--help"}:
        print("usage: grok_x_stream.py <status|open-studio|open-obs|start|stop|announce> [args]")
        print("env: X_BEARER_TOKEN (optional, for posting)")
        return 0

    cmd = args[0]
    if cmd == "status":
        print(json.dumps(stream_status(), indent=2))
        return 0
    if cmd == "open-studio":
        print(json.dumps(open_studio(), indent=2))
        return 0
    if cmd == "open-obs":
        print(json.dumps(open_obs(), indent=2))
        return 0
    if cmd == "start":
        title = " ".join(args[1:]) if len(args) > 1 else "Grok Resolve Session"
        subtitle = os.environ.get("STREAM_SUBTITLE", "")
        print(json.dumps(start_workflow(title, subtitle), indent=2))
        return 0
    if cmd == "stop":
        print(json.dumps(stop_workflow(), indent=2))
        return 0
    if cmd == "announce":
        extra = " ".join(args[1:]) if len(args) > 1 else ""
        result = announce_workflow(extra)
        print(json.dumps(result, indent=2))
        return 0 if result.get("ok") else 1

    print(json.dumps({"ok": False, "error": f"unknown command: {cmd}"}), file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())