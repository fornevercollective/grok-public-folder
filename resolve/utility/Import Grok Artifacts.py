#!/usr/bin/env python3
"""Workspace -> Scripts -> Utility -> Import Grok Artifacts

Scan Downloads for Grok media, offer to move into the public folder,
import everything into the active Media Pool bin, then show results.
"""

import subprocess
import sys
from pathlib import Path

GROK_ROOT = "/Users/tref/film/grok-public-folder"
if GROK_ROOT not in sys.path:
    sys.path.insert(0, GROK_ROOT)

from grok_downloads_scan import ask_move_files, scan_downloads
from grok_meta import move_to_artifacts, read_sidecar
from grok_api import import_all_artifacts, list_artifact_files

ui = fusion.UIManager
dispatcher = bmd.UIDispatcher(ui)
win_id = "com.grok.resolve.import"


def format_result(moved_names: list[str], count: int, bin_name: str, files: list[str]) -> str:
    lines = [f"folder {GROK_ROOT}"]

    if moved_names:
        lines.append(f"moved {len(moved_names)} from downloads")
        for name in moved_names[:8]:
            lines.append(f"  + {name}")
        if len(moved_names) > 8:
            lines.append(f"  + ...{len(moved_names) - 8} more")
    elif scan_downloads():
        lines.append("downloads scan skipped")
    else:
        lines.append("downloads 0")

    if count:
        lines.append(f"imported {count} into {bin_name}")
        for path in files[-8:]:
            meta = read_sidecar(Path(path))
            tag = "grok" if meta else "file"
            lines.append(f"  {tag} {Path(path).name}")
    elif not moved_names:
        lines.append("artifacts 0")
        lines.append("")
        lines.append("generate with bin/grok or download from grok.com")
        lines.append("select your target bin then run again")
    else:
        lines.append("imported 0")
        lines.append("select a bin in media pool and click run again")

    lines.append("")
    lines.append("thumbnails appear after import")
    return "\n".join(lines)


def run_import_workflow() -> tuple[str, list[str], int, str, list[str]]:
    moved_names: list[str] = []
    downloads = scan_downloads()
    if downloads and ask_move_files(downloads):
        for path in downloads:
            dest = move_to_artifacts(path)
            moved_names.append(dest.name)

    try:
        count, files, bin_name = import_all_artifacts()
    except Exception as exc:
        return str(exc), moved_names, 0, "current bin", []

    return format_result(moved_names, count, bin_name, files), moved_names, count, bin_name, files


def on_preview(ev):
    files = list_artifact_files()
    if not files:
        win.Find("status").Text = "nothing to preview\n" + win.Find("status").Text
        return
    for path in files[-3:]:
        subprocess.run(["open", path], check=False)


def on_open_folder(ev):
    subprocess.run(["open", GROK_ROOT], check=False)


def on_retry(ev):
    text, _, _, _, _ = run_import_workflow()
    win.Find("status").Text = text


result_text, _, _, _, _ = run_import_workflow()

existing = ui.FindWindow(win_id)
if existing:
    existing.Find("status").Text = result_text
    existing.Show()
    existing.Raise()
    win = existing
else:
    win = dispatcher.AddWindow(
        {"ID": win_id, "WindowTitle": "Import Grok Artifacts", "Geometry": [140, 140, 500, 380]},
        ui.VGroup([
            ui.Label({"Text": "grok import", "Weight": 0}),
            ui.Label({"Text": "scan downloads  move  import active bin", "Weight": 0}),
            ui.TextEdit({"ID": "status", "Text": result_text, "ReadOnly": True, "Weight": 1}),
            ui.HGroup([
                ui.Button({"ID": "preview", "Text": "Preview"}),
                ui.Button({"ID": "folder", "Text": "Open Folder"}),
                ui.Button({"ID": "retry", "Text": "Run Again"}),
            ]),
        ]),
    )
    win.On[win_id].Close = lambda ev: dispatcher.ExitLoop()
    win.On["preview"].Clicked = on_preview
    win.On["folder"].Clicked = on_open_folder
    win.On["retry"].Clicked = on_retry
    win.Show()
    dispatcher.RunLoop()