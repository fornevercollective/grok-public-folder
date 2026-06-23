#!/usr/bin/env python3
"""Safari ↔ Grok for Resolve handoff (grok.com / Imagine)."""

from __future__ import annotations

import json
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

from grok_paths import BROWSER_DIR, ROOT

IMAGINE_URL = "https://grok.com/imagine"
INBOX_FILE = BROWSER_DIR / "inbox.json"
OUTBOX_FILE = BROWSER_DIR / "outbox.json"
STATE_FILE = BROWSER_DIR / "state.json"


def _run_applescript(script: str) -> str:
    try:
        result = subprocess.run(
            ["osascript", "-e", script],
            check=False,
            capture_output=True,
            text=True,
        )
        return (result.stdout or "").strip()
    except (subprocess.SubprocessError, FileNotFoundError):
        return ""


def _ensure_browser_dir() -> None:
    BROWSER_DIR.mkdir(parents=True, exist_ok=True)


def _write_json(path: Path, payload: dict) -> None:
    _ensure_browser_dir()
    path.write_text(json.dumps(payload, indent=2), encoding="utf-8")


def _read_json(path: Path) -> dict | None:
    if not path.exists():
        return None
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return None


def safari_front_tab() -> dict:
    script = '''
tell application "Safari"
    if (count of windows) = 0 then
        return "|||"
    end if
    set t to current tab of front window
    return (URL of t) & "|" & (name of t)
end tell
'''
    raw = _run_applescript(script)
    if not raw or raw == "|||":
        return {"url": "", "title": ""}
    parts = raw.split("|", 1)
    return {"url": parts[0], "title": parts[1] if len(parts) > 1 else ""}


def clipboard_text() -> str:
    return _run_applescript('the clipboard as text')


def set_clipboard(text: str) -> None:
    safe = text.replace("\\", "\\\\").replace('"', '\\"')
    _run_applescript(f'set the clipboard to "{safe}"')


def open_imagine() -> dict:
    _ensure_browser_dir()
    script = f'''
tell application "Safari"
    activate
    if (count of windows) = 0 then
        make new document with properties {{URL:"{IMAGINE_URL}"}}
    else
        set URL of current tab of front window to "{IMAGINE_URL}"
    end if
end tell
'''
    _run_applescript(script)
    tab = safari_front_tab()
    payload = {
        "action": "open",
        "url": tab.get("url") or IMAGINE_URL,
        "title": tab.get("title", ""),
        "opened_at": datetime.now(timezone.utc).isoformat(),
        "root": str(ROOT),
    }
    _write_json(STATE_FILE, payload)
    return payload


def push_prompt(prompt: str, source: str = "resolve") -> dict:
    text = (prompt or "").strip()
    if not text:
        return {"ok": False, "message": "empty prompt"}
    set_clipboard(text)
    payload = {
        "action": "push",
        "prompt": text,
        "source": source,
        "url": IMAGINE_URL,
        "pushed_at": datetime.now(timezone.utc).isoformat(),
    }
    _write_json(OUTBOX_FILE, payload)
    _write_json(STATE_FILE, {"last_push": payload})
    script = f'''
tell application "Safari"
    activate
    if (count of windows) = 0 then
        make new document with properties {{URL:"{IMAGINE_URL}"}}
    else
        set URL of current tab of front window to "{IMAGINE_URL}"
    end if
end tell
'''
    _run_applescript(script)
    return {"ok": True, "message": "prompt copied to clipboard and written to browser/outbox.json", "prompt": text}


def pull_prompt() -> dict:
    _ensure_browser_dir()
    tab = safari_front_tab()
    inbox = _read_json(INBOX_FILE) or {}
    clip = clipboard_text().strip()

    prompt = ""
    source = ""
    if isinstance(inbox.get("prompt"), str) and inbox["prompt"].strip():
        prompt = inbox["prompt"].strip()
        source = "browser/inbox.json"
    elif clip:
        prompt = clip
        source = "clipboard"

    payload = {
        "action": "pull",
        "prompt": prompt,
        "source": source,
        "url": tab.get("url", ""),
        "title": tab.get("title", ""),
        "pulled_at": datetime.now(timezone.utc).isoformat(),
    }
    _write_json(STATE_FILE, {"last_pull": payload})
    if not prompt:
        return {"ok": False, "message": "no prompt in inbox.json or clipboard", "tab": tab}
    return {"ok": True, "message": f"pulled from {source}", "prompt": prompt, "tab": tab}


def browser_status() -> dict:
    tab = safari_front_tab()
    state = _read_json(STATE_FILE) or {}
    return {
        "root": str(ROOT),
        "browser_dir": str(BROWSER_DIR),
        "inbox_exists": INBOX_FILE.exists(),
        "outbox_exists": OUTBOX_FILE.exists(),
        "tab": tab,
        "state": state,
    }


def main(argv: list[str] | None = None) -> int:
    args = argv if argv is not None else sys.argv[1:]
    if not args or args[0] in {"-h", "--help"}:
        print("usage: grok_browser.py <open|push|pull|status> [prompt]")
        return 0

    cmd = args[0]
    if cmd == "open":
        result = open_imagine()
        print(json.dumps(result, indent=2))
        return 0
    if cmd == "push":
        prompt = " ".join(args[1:]) if len(args) > 1 else ""
        result = push_prompt(prompt)
        print(result.get("message", ""))
        return 0 if result.get("ok") else 1
    if cmd == "pull":
        result = pull_prompt()
        print(result.get("prompt", "") if result.get("ok") else result.get("message", "pull failed"))
        return 0 if result.get("ok") else 1
    if cmd == "status":
        print(json.dumps(browser_status(), indent=2))
        return 0

    print(f"unknown command: {cmd}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())