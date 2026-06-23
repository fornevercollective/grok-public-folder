#!/usr/bin/env python3
"""Track xAI token usage for Grok for Resolve header metering."""

from __future__ import annotations

import json
from datetime import datetime, timezone
from pathlib import Path

from grok_paths import PROJECT_DIR

TOKEN_METER_FILE = PROJECT_DIR / "token-meter.json"

_EMPTY_BUCKET = {"prompt": 0, "completion": 0, "total": 0, "requests": 0}


def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def _empty_meter() -> dict:
    return {
        "session": dict(_EMPTY_BUCKET),
        "lifetime": dict(_EMPTY_BUCKET),
        "by_action": {},
        "last_updated": None,
    }


def load_meter() -> dict:
    if not TOKEN_METER_FILE.exists():
        return _empty_meter()
    try:
        data = json.loads(TOKEN_METER_FILE.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return _empty_meter()
    for key in ("session", "lifetime"):
        if key not in data or not isinstance(data[key], dict):
            data[key] = dict(_EMPTY_BUCKET)
        for field in _EMPTY_BUCKET:
            data[key].setdefault(field, 0)
    data.setdefault("by_action", {})
    return data


def save_meter(data: dict) -> None:
    PROJECT_DIR.mkdir(parents=True, exist_ok=True)
    data["last_updated"] = _now_iso()
    TOKEN_METER_FILE.write_text(json.dumps(data, indent=2), encoding="utf-8")


def estimate_tokens(text: str) -> int:
    cleaned = (text or "").strip()
    if not cleaned:
        return 0
    return max(1, len(cleaned) // 4)


def record_usage(
    action: str,
    *,
    prompt_tokens: int = 0,
    completion_tokens: int = 0,
    total_tokens: int = 0,
    estimated: bool = False,
) -> dict:
    prompt = max(0, int(prompt_tokens))
    completion = max(0, int(completion_tokens))
    total = max(0, int(total_tokens)) or (prompt + completion)
    if total == 0:
        return load_meter()

    meter = load_meter()
    for bucket in ("session", "lifetime"):
        meter[bucket]["prompt"] += prompt
        meter[bucket]["completion"] += completion
        meter[bucket]["total"] += total
        meter[bucket]["requests"] += 1

    entry = meter["by_action"].setdefault(
        action,
        {"prompt": 0, "completion": 0, "total": 0, "requests": 0, "estimated": False},
    )
    entry["prompt"] += prompt
    entry["completion"] += completion
    entry["total"] += total
    entry["requests"] += 1
    if estimated:
        entry["estimated"] = True

    save_meter(meter)
    return meter


def record_from_api_response(action: str, result: dict, *, fallback_prompt: str = "") -> dict:
    usage = result.get("usage") or {}
    prompt = int(usage.get("prompt_tokens") or 0)
    completion = int(usage.get("completion_tokens") or 0)
    total = int(usage.get("total_tokens") or 0)
    if total == 0 and fallback_prompt:
        est = estimate_tokens(fallback_prompt)
        return record_usage(action, prompt_tokens=est, completion_tokens=est // 2, estimated=True)
    return record_usage(action, prompt_tokens=prompt, completion_tokens=completion, total_tokens=total)


def reset_session() -> dict:
    meter = load_meter()
    meter["session"] = dict(_EMPTY_BUCKET)
    save_meter(meter)
    return meter


def meter_summary() -> dict:
    meter = load_meter()
    session = meter.get("session") or {}
    lifetime = meter.get("lifetime") or {}
    return {
        "session_total": session.get("total", 0),
        "session_requests": session.get("requests", 0),
        "lifetime_total": lifetime.get("total", 0),
        "lifetime_requests": lifetime.get("requests", 0),
        "last_updated": meter.get("last_updated"),
        "by_action": meter.get("by_action") or {},
    }