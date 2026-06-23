#!/usr/bin/env python3
"""Workflow logs and health for in-window Terminal tab."""

from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path

from grok_paths import BIN_DIR, BRIDGE_DIR, ROOT

MENU_LOG = BRIDGE_DIR / "menu-last.log"
REQUEST_FILE = BRIDGE_DIR / "request.json"
RESPONSE_FILE = BRIDGE_DIR / "response.json"
PID_FILE = BRIDGE_DIR / "bridge.pid"

WHITELIST = {
    "status": [sys.executable, str(ROOT / "grok_workflow_log.py"), "status"],
    "resolve-check": ["/bin/bash", str(BIN_DIR / "resolve-check")],
    "scan": ["/bin/bash", str(BIN_DIR / "scan")],
    "catalog": ["/bin/bash", str(BIN_DIR / "grok-catalog")],
}


def _tail(path: Path, max_lines: int = 200) -> list[str]:
    if not path.exists():
        return []
    try:
        lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    except OSError:
        return []
    return lines[-max_lines:]


def _pid_alive(pid: int) -> bool:
    try:
        os.kill(pid, 0)
        return True
    except OSError:
        return False


def bridge_running() -> bool:
    if not PID_FILE.exists():
        return False
    try:
        pid = int(PID_FILE.read_text(encoding="utf-8").strip())
    except ValueError:
        return False
    return _pid_alive(pid)


def _read_json(path: Path) -> dict | None:
    if not path.exists():
        return None
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return None


def workflow_status() -> dict:
    return {
        "root": str(ROOT),
        "bridge_dir": str(BRIDGE_DIR),
        "bridge_running": bridge_running(),
        "xai_configured": bool(os.environ.get("XAI_API_KEY", "").strip()),
        "tmdb_configured": bool(os.environ.get("TMDB_API_KEY", "").strip()),
        "last_request": _read_json(REQUEST_FILE),
        "last_response": _read_json(RESPONSE_FILE),
        "menu_log_lines": len(_tail(MENU_LOG, 500)),
    }


def tail_logs(max_lines: int = 250) -> str:
    sections: list[str] = []
    status = workflow_status()
    sections.append("── Grok workflow status ──")
    sections.append(f"bridge: {'online' if status['bridge_running'] else 'offline'}")
    sections.append(f"XAI_API_KEY: {'set' if status['xai_configured'] else 'not set'}")
    sections.append(f"TMDB_API_KEY: {'set' if status['tmdb_configured'] else 'not set'}")
    if status.get("last_request"):
        action = status["last_request"].get("action", "")
        text = (status["last_request"].get("text") or "")[:80]
        sections.append(f"last bridge request: {action} {text}")
    if status.get("last_response"):
        msg = (status["last_response"].get("message") or "")[:120]
        ok = status["last_response"].get("ok")
        sections.append(f"last bridge response: ok={ok} {msg}")
    sections.append("")
    sections.append(f"── {MENU_LOG.name} (last {max_lines} lines) ──")
    sections.extend(_tail(MENU_LOG, max_lines) or ["(no log yet — run Scan, Generate, or Bridge)"])
    return "\n".join(sections)


def run_command(name: str) -> tuple[int, str]:
    cmd = WHITELIST.get(name.strip().lower())
    if not cmd:
        return 1, f"unknown command: {name} (allowed: {', '.join(sorted(WHITELIST))})"
    env = os.environ.copy()
    env["GROK_PUBLIC_FOLDER"] = str(ROOT)
    try:
        result = subprocess.run(
            cmd,
            cwd=str(ROOT),
            env=env,
            capture_output=True,
            text=True,
            timeout=120,
        )
        out = (result.stdout or "") + (result.stderr or "")
        return result.returncode, out.strip() or f"exit {result.returncode}"
    except subprocess.TimeoutExpired:
        return 1, "command timed out"
    except OSError as exc:
        return 1, str(exc)


def main(argv: list[str] | None = None) -> int:
    args = argv if argv is not None else sys.argv[1:]
    if not args or args[0] in {"-h", "--help"}:
        print("usage: grok_workflow_log.py <tail|status|run> [cmd]")
        return 0
    cmd = args[0]
    if cmd == "tail":
        lines = int(args[1]) if len(args) > 1 else 250
        print(tail_logs(lines))
        return 0
    if cmd == "status":
        print(json.dumps(workflow_status(), indent=2))
        return 0
    if cmd == "run":
        if len(args) < 2:
            print("run requires a command name", file=sys.stderr)
            return 1
        code, out = run_command(args[1])
        print(out)
        return code
    print(f"unknown: {cmd}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())