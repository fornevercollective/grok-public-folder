#!/usr/bin/env python3
"""Resolve external scripting environment for Terminal-launched Python."""

from __future__ import annotations

import os
import subprocess
import sys

RESOLVE_SCRIPT_API = "/Library/Application Support/Blackmagic Design/DaVinci Resolve/Developer/Scripting"
RESOLVE_SCRIPT_LIB = (
    "/Applications/DaVinci Resolve/DaVinci Resolve.app/Contents/Libraries/Fusion/fusionscript.so"
)
RESOLVE_MODULES = f"{RESOLVE_SCRIPT_API}/Modules"


def ensure_resolve_env() -> None:
    os.environ.setdefault("RESOLVE_SCRIPT_API", RESOLVE_SCRIPT_API)
    os.environ.setdefault("RESOLVE_SCRIPT_LIB", RESOLVE_SCRIPT_LIB)
    if RESOLVE_MODULES not in sys.path:
        sys.path.insert(0, RESOLVE_MODULES)
    pythonpath = os.environ.get("PYTHONPATH", "")
    if RESOLVE_MODULES not in pythonpath.split(os.pathsep):
        os.environ["PYTHONPATH"] = (
            f"{pythonpath}{os.pathsep}{RESOLVE_MODULES}" if pythonpath else RESOLVE_MODULES
        )


def resolve_process_running() -> bool:
    try:
        result = subprocess.run(
            ["pgrep", "-f", "DaVinci Resolve.app/Contents/MacOS/Resolve"],
            capture_output=True,
            text=True,
            check=False,
        )
        return result.returncode == 0
    except Exception:
        return False


def connection_help() -> str:
    running = resolve_process_running()
    lines = []
    if not running:
        lines.append("resolve process: not detected — open DaVinci Resolve first")
    else:
        lines.append("resolve process: running")
        lines.append("terminal link: not connected (external scripting)")
    lines.extend(
        [
            "",
            "one-time fix for bin/startup from Terminal:",
            "  DaVinci Resolve → Preferences → System → General",
            "  External scripting using → Local",
            "  quit and reopen Resolve, then run bin/startup again",
            "",
            "works immediately without that setting:",
            "  Workspace → Scripts → Utility → Grok Startup → Bootstrap Project",
        ]
    )
    return "\n".join(lines)


def diagnose() -> dict:
    ensure_resolve_env()
    info = {
        "process_running": resolve_process_running(),
        "resolve_script_api": os.environ.get("RESOLVE_SCRIPT_API"),
        "resolve_script_lib": os.environ.get("RESOLVE_SCRIPT_LIB"),
        "modules_in_path": RESOLVE_MODULES in sys.path,
        "connected": False,
        "version": None,
        "project": None,
        "error": None,
    }
    try:
        import DaVinciResolveScript as dvr_script

        resolve = dvr_script.scriptapp("Resolve")
        if resolve:
            info["connected"] = True
            info["version"] = resolve.GetVersionString()
            project = resolve.GetProjectManager().GetCurrentProject()
            info["project"] = project.GetName() if project else None
        elif info["process_running"]:
            info["error"] = "scriptapp returned None — enable External scripting using → Local"
        else:
            info["error"] = "resolve not running"
    except Exception as exc:
        info["error"] = str(exc)
    return info