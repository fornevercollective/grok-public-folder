#!/usr/bin/env python3
"""Workspace -> Scripts -> Edit -> Grok Menu"""

import subprocess
import sys
from pathlib import Path

GROK_ROOT = "/Users/tref/film/grok-public-folder"
if GROK_ROOT not in sys.path:
    sys.path.insert(0, GROK_ROOT)

from grok_api import generate_video, import_all_artifacts, list_artifact_files, require_api_key
from grok_downloads_scan import ask_move_files, scan_downloads
from grok_meta import is_grok_download, move_to_artifacts, read_sidecar
from grok_presets import compose_prompt, fetch_preset_prompt
from grok_startup import bootstrap_resolve, format_report, load_startup_config, write_state
from grok_story import beat_prompt, load_story

ui = fusion.UIManager
dispatcher = bmd.UIDispatcher(ui)
win_id = "com.grok.resolve.menu"
STORY_PATH = Path(GROK_ROOT) / "project/stories/dusk-to-neon.json"
CONSOLE_SNIPPET = f'exec(open("{GROK_ROOT}/grok_load.py").read(), globals())'


def format_inventory() -> str:
    lines = [f"folder {GROK_ROOT}"]
    downloads = scan_downloads()
    if downloads:
        lines.append(f"downloads ready {len(downloads)}")
        for path in downloads[:6]:
            _, reason = is_grok_download(path)
            lines.append(f"  dl {path.name} [{reason}]")
    else:
        lines.append("downloads 0")

    files = list_artifact_files()
    if files:
        lines.append(f"artifacts {len(files)}")
        for path in files[-6:]:
            meta = read_sidecar(Path(path))
            tag = "grok" if meta else "file"
            lines.append(f"  {tag} {Path(path).name}")
    else:
        lines.append("artifacts 0")

    lines.append("")
    lines.append("select target bin in media pool before import")
    return "\n".join(lines)


def scan_and_move() -> list[str]:
    files = scan_downloads()
    if not files:
        return []
    if not ask_move_files(files):
        return []
    moved = []
    for path in files:
        dest = move_to_artifacts(path)
        moved.append(dest.name)
    return moved


def on_bootstrap(ev):
    config = load_startup_config()
    try:
        result = bootstrap_resolve(config, create_project=False)
        write_state(config)
        win.Find("status").Text = format_report(config, result)
    except Exception as exc:
        win.Find("status").Text = format_report(config) + f"\n\n{exc}"


def on_scan(ev):
    moved = scan_and_move()
    if not moved:
        win.Find("status").Text = "no grok files in downloads\n" + format_inventory()
        return
    win.Find("status").Text = f"moved {len(moved)} from downloads\n" + format_inventory()


def on_import(ev):
    try:
        count, _, bin_name = import_all_artifacts()
        if count == 0:
            win.Find("status").Text = "nothing to import\n" + format_inventory()
        else:
            win.Find("status").Text = f"imported {count} into {bin_name}\n" + format_inventory()
    except Exception as exc:
        win.Find("status").Text = str(exc)


def on_quick(ev):
    moved = scan_and_move()
    try:
        count, _, bin_name = import_all_artifacts()
    except Exception as exc:
        win.Find("status").Text = str(exc)
        return
    lines = []
    if moved:
        lines.append(f"moved {len(moved)} from downloads")
    if count:
        lines.append(f"imported {count} into {bin_name}")
    elif not moved:
        lines.append("nothing to move or import")
    else:
        lines.append("moved files but imported 0 — select a bin and try Import")
    win.Find("status").Text = "\n".join(lines) + "\n\n" + format_inventory()


def on_preview(ev):
    files = list_artifact_files()
    if not files:
        files = [str(p) for p in scan_downloads()]
    if not files:
        win.Find("status").Text = "nothing to preview"
        return
    for path in files[-3:]:
        subprocess.run(["open", path], check=False)
    win.Find("status").Text = "opened latest files\n" + format_inventory()


def on_folder(ev):
    subprocess.run(["open", GROK_ROOT], check=False)


def on_bridge(ev):
    subprocess.Popen(["/bin/bash", "-lc", f"export XAI_API_KEY=\"$XAI_API_KEY\"; {GROK_ROOT}/bin/bridge"])
    win.Find("status").Text = "started bin/bridge in terminal\nset XAI_API_KEY first"


def on_console(ev):
    win.Find("status").Text = (
        "python console (switch to Py3):\n"
        f"{CONSOLE_SNIPPET}\n\n"
        "lua console:\n"
        f'dofile("{GROK_ROOT}/resolve/lua/grok_bridge.lua")'
    )


def on_refresh(ev):
    win.Find("status").Text = format_inventory()


def on_slug_preview(ev):
    slug = win.Find("slug").Text.strip()
    if not slug:
        win.Find("status").Text = "enter a preset slug"
        return
    try:
        win.Find("status").Text = f"preset {slug}\n\n{fetch_preset_prompt(slug)}"
    except Exception as exc:
        win.Find("status").Text = str(exc)


def on_generate(ev):
    slug = win.Find("slug").Text.strip()
    prompt_add = win.Find("prompt").Text.strip()
    if not slug:
        win.Find("status").Text = "enter a preset slug"
        return
    try:
        api_key = require_api_key()
        config = load_startup_config()
        gen = config.get("generation", {})
        full = compose_prompt(slug, base_prompt=prompt_add)
        win.Find("status").Text = f"generating {slug}..."
        path = generate_video(
            api_key,
            full,
            duration=int(gen.get("duration_sec", 10)),
            aspect_ratio=gen.get("aspect_ratio", "16:9"),
            resolution=gen.get("resolution", "720p"),
        )
        win.Find("status").Text = f"saved {path.name}\n\n{full[:500]}"
    except Exception as exc:
        win.Find("status").Text = str(exc)


def on_beat(ev):
    beat_id = win.Find("beat").Text.strip()
    if not beat_id:
        win.Find("status").Text = "enter beat_id e.g. act2_rising"
        return
    try:
        api_key = require_api_key()
        config = load_startup_config()
        gen = config.get("generation", {})
        story = load_story(STORY_PATH)
        beat = next(b for b in story["beats"] if b["beat_id"] == beat_id)
        full = beat_prompt(story, beat)
        win.Find("status").Text = f"generating beat {beat_id} [{beat['style_slug']}]..."
        path = generate_video(
            api_key,
            full,
            duration=int(beat.get("duration_sec", 10)),
            aspect_ratio=gen.get("aspect_ratio", "16:9"),
            resolution=gen.get("resolution", "720p"),
        )
        win.Find("status").Text = f"beat {beat_id} -> {path.name}"
    except Exception as exc:
        win.Find("status").Text = str(exc)


featured = ", ".join(load_startup_config().get("featured_slugs", [])[:5])

existing = ui.FindWindow(win_id)
if existing:
    existing.Show()
    existing.Raise()
    win = existing
else:
    win = dispatcher.AddWindow(
        {"ID": win_id, "WindowTitle": "Grok Menu", "Geometry": [90, 90, 580, 580]},
        ui.VGroup([
            ui.Label({"Text": "grok menu", "Weight": 0}),
            ui.Label({"Text": f"bootstrap  scan  import  generate  |  {featured}", "Weight": 0}),
            ui.HGroup([
                ui.Button({"ID": "bootstrap", "Text": "Bootstrap"}),
                ui.Button({"ID": "scan", "Text": "Scan Downloads"}),
                ui.Button({"ID": "import", "Text": "Import"}),
                ui.Button({"ID": "quick", "Text": "Scan + Import"}),
            ]),
            ui.HGroup([
                ui.Button({"ID": "preview", "Text": "Preview"}),
                ui.Button({"ID": "folder", "Text": "Open Folder"}),
                ui.Button({"ID": "bridge", "Text": "Start Bridge"}),
                ui.Button({"ID": "console", "Text": "Console"}),
            ]),
            ui.HGroup([
                ui.Label({"Text": "slug", "Weight": 0}),
                ui.LineEdit({"ID": "slug", "Text": "neo-noir", "Weight": 1}),
                ui.Button({"ID": "slug_preview", "Text": "Preset"}),
            ]),
            ui.LineEdit({"ID": "prompt", "Text": "woman in rain on empty street at night", "Weight": 0}),
            ui.HGroup([
                ui.Button({"ID": "generate", "Text": "Generate Video"}),
                ui.Label({"Text": "beat", "Weight": 0}),
                ui.LineEdit({"ID": "beat", "Text": "act2_rising", "Weight": 1}),
                ui.Button({"ID": "beat_run", "Text": "Run Beat"}),
            ]),
            ui.TextEdit({"ID": "status", "Text": format_inventory(), "ReadOnly": True, "Weight": 1}),
        ]),
    )
    win.On[win_id].Close = lambda ev: dispatcher.ExitLoop()
    win.On["bootstrap"].Clicked = on_bootstrap
    win.On["scan"].Clicked = on_scan
    win.On["import"].Clicked = on_import
    win.On["quick"].Clicked = on_quick
    win.On["preview"].Clicked = on_preview
    win.On["folder"].Clicked = on_folder
    win.On["bridge"].Clicked = on_bridge
    win.On["console"].Clicked = on_console
    win.On["refresh"].Clicked = on_refresh
    win.On["slug_preview"].Clicked = on_slug_preview
    win.On["generate"].Clicked = on_generate
    win.On["beat_run"].Clicked = on_beat
    win.Show()
    dispatcher.RunLoop()