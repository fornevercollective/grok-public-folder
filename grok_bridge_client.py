#!/usr/bin/env python3
"""File bridge client for Resolve console -> terminal grok_bridge.py"""

from __future__ import annotations

import json
import random
import time
from grok_paths import BRIDGE_DIR, ROOT
REQUEST_FILE = BRIDGE_DIR / "request.json"
RESPONSE_FILE = BRIDGE_DIR / "response.json"

DEFAULT_TIMEOUT = {
    "ping": 15,
    "clear": 15,
    "chat": 180,
    "image": 120,
    "video": 900,
    "import": 60,
}


def send(action, text="", timeout=None, **options):
    BRIDGE_DIR.mkdir(parents=True, exist_ok=True)
    req_id = f"{int(time.time())}{random.randint(1000, 9999)}"
    payload = {
        "id": req_id,
        "action": action,
        "text": text or "",
    }
    payload.update(options)

    if RESPONSE_FILE.exists():
        RESPONSE_FILE.unlink()

    REQUEST_FILE.write_text(json.dumps(payload), encoding="utf-8")

    wait_for = timeout or DEFAULT_TIMEOUT.get(action, 30)
    print("waiting")
    deadline = time.time() + wait_for

    while time.time() < deadline:
        if RESPONSE_FILE.exists():
            data = json.loads(RESPONSE_FILE.read_text(encoding="utf-8"))
            if data.get("id") == req_id:
                message = data.get("message", "")
                if data.get("ok"):
                    print(message)
                    return message
                print(message)
                return None
        time.sleep(0.5)

    print("bridge timeout")
    print(f"start {ROOT / 'bin' / 'bridge'} in terminal")
    return None