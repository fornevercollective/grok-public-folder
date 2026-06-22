#!/usr/bin/env python3
"""Workspace -> Scripts -> Utility -> Grok Panel"""

import sys

GROK_ROOT = "/Users/tref/film/grok-public-folder"
if GROK_ROOT not in sys.path:
    sys.path.insert(0, GROK_ROOT)

from grok_downloads_scan import ask_move_files, scan_downloads
from grok_meta import is_grok_download, move_to_artifacts, read_sidecar
from grok_api import import_all_artifacts, list_artifact_files
from pathlib import Path

ui = fusion.UIManager
dispatcher = bmd.UIDispatcher(ui)
win_id = "com.grok.resolve.panel"


def format_inventory():
    lines = [f"folder {GROK_ROOT}"]
    downloads = scan_downloads()
    if downloads:
        lines.append(f"downloads ready {len(downloads)}")
        for path in downloads[:8]:
            _, reason = is_grok_download(path)
            lines.append(f"  dl {path.name} [{reason}]")
    else:
        lines.append("downloads ready 0")

    files = list_artifact_files()
    if files:
        lines.append(f"artifacts {len(files)}")
        for path in files[-8:]:
            meta = read_sidecar(Path(path))
            tag = "grok" if meta else "file"
            lines.append(f"  {tag} {Path(path).name}")
    else:
        lines.append("artifacts 0")

    lines.append("")
    lines.append("thumbnails show in media pool after import")
    lines.append("select your target bin before import")
    return "\n".join(lines)


def on_scan(ev):
    files = scan_downloads()
    if not files:
        win.Find("status").Text = "no grok files in downloads"
        return
    if not ask_move_files(files):
        win.Find("status").Text = "scan cancelled\n" + format_inventory()
        return
    moved = []
    for path in files:
        moved.append(move_to_artifacts(path))
    win.Find("status").Text = f"moved {len(moved)} from downloads\n" + format_inventory()


def on_import(ev):
    try:
        count, _, bin_name = import_all_artifacts()
        if count == 0:
            win.Find("status").Text = "no artifacts to import"
        else:
            win.Find("status").Text = f"imported {count} into {bin_name}\n" + format_inventory()
    except Exception as exc:
        win.Find("status").Text = str(exc)


def on_refresh(ev):
    win.Find("status").Text = format_inventory()


def on_preview(ev):
    files = list_artifact_files()
    if not files:
        files = [str(p) for p in scan_downloads()]
    if not files:
        win.Find("status").Text = "nothing to preview"
        return
    import subprocess
    for path in files[-3:]:
        subprocess.run(["open", path], check=False)
    win.Find("status").Text = "opened latest files\n" + format_inventory()


existing = ui.FindWindow(win_id)
if existing:
    existing.Show()
    existing.Raise()
else:
    win = dispatcher.AddWindow(
        {"ID": win_id, "WindowTitle": "Grok Panel", "Geometry": [120, 120, 520, 420]},
        ui.VGroup([
            ui.Label({"Text": "grok public folder", "Weight": 0}),
            ui.Label({"Text": "scan downloads move to folder import to active bin", "Weight": 0}),
            ui.HGroup([
                ui.Button({"ID": "scan", "Text": "Scan Downloads"}),
                ui.Button({"ID": "import", "Text": "Import"}),
                ui.Button({"ID": "preview", "Text": "Preview"}),
                ui.Button({"ID": "refresh", "Text": "Refresh"}),
            ]),
            ui.TextEdit({"ID": "status", "Text": format_inventory(), "ReadOnly": True, "Weight": 1}),
        ]),
    )
    win.On[win_id].Close = lambda ev: dispatcher.ExitLoop()
    win.On["scan"].Clicked = on_scan
    win.On["import"].Clicked = on_import
    win.On["preview"].Clicked = on_preview
    win.On["refresh"].Clicked = on_refresh
    win.Show()
    dispatcher.RunLoop()