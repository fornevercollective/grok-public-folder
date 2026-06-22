#!/usr/bin/env python3
"""Workspace -> Scripts -> Utility -> Grok Startup

Bootstrap 4K Resolve project, load Imagine preset slugs, generate + import.
"""

import subprocess
import sys

GROK_ROOT = "/Users/tref/film/grok-public-folder"
if GROK_ROOT not in sys.path:
    sys.path.insert(0, GROK_ROOT)

from grok_api import generate_video, import_all_artifacts, require_api_key
from grok_presets import all_slugs, compose_prompt, fetch_preset_prompt
from grok_startup import bootstrap_resolve, format_report, load_startup_config, write_state
from grok_story import beat_prompt, load_story

from pathlib import Path

ui = fusion.UIManager
dispatcher = bmd.UIDispatcher(ui)
win_id = "com.grok.resolve.startup"
STORY_PATH = Path(GROK_ROOT) / "project/stories/dusk-to-neon.json"


def startup_status() -> str:
    config = load_startup_config()
    try:
        result = bootstrap_resolve(config, create_project=False)
        write_state(config)
        return format_report(config, result)
    except Exception as exc:
        return format_report(config) + f"\n\nresolve: {exc}"


def on_startup(ev):
    win.Find("status").Text = startup_status()


def on_slug_preview(ev):
    slug = win.Find("slug").Text.strip()
    if not slug:
        win.Find("status").Text = "enter a preset slug"
        return
    try:
        text = fetch_preset_prompt(slug)
        win.Find("status").Text = f"preset {slug}\n\n{text}"
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
        win.Find("status").Text = f"generating {slug}...\n{full[:400]}..."
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


def on_import(ev):
    try:
        count, _, bin_name = import_all_artifacts()
        win.Find("status").Text = f"imported {count} into {bin_name}" if count else "nothing to import"
    except Exception as exc:
        win.Find("status").Text = str(exc)


def on_bridge(ev):
    subprocess.Popen(["/bin/bash", "-lc", f"export XAI_API_KEY=\"$XAI_API_KEY\"; {GROK_ROOT}/bin/bridge"])
    win.Find("status").Text = "started bin/bridge in terminal\nset XAI_API_KEY first"


featured = load_startup_config().get("featured_slugs", all_slugs()[:8])
slug_hint = ", ".join(featured[:6])

existing = ui.FindWindow(win_id)
if existing:
    existing.Show()
    existing.Raise()
else:
    win = dispatcher.AddWindow(
        {"ID": win_id, "WindowTitle": "Grok Startup", "Geometry": [100, 100, 560, 520]},
        ui.VGroup([
            ui.Label({"Text": "grok resolve startup — 4K timeline + imagine slugs", "Weight": 0}),
            ui.Label({"Text": f"slugs: {slug_hint}", "Weight": 0}),
            ui.HGroup([
                ui.Button({"ID": "startup", "Text": "Bootstrap Project"}),
                ui.Button({"ID": "bridge", "Text": "Start Bridge"}),
                ui.Button({"ID": "import", "Text": "Import"}),
            ]),
            ui.HGroup([
                ui.Label({"Text": "slug", "Weight": 0}),
                ui.LineEdit({"ID": "slug", "Text": "neo-noir", "Weight": 1}),
                ui.Button({"ID": "slug_preview", "Text": "Preview"}),
            ]),
            ui.LineEdit({"ID": "prompt", "Text": "woman in rain on empty street at night", "Weight": 0}),
            ui.HGroup([
                ui.Button({"ID": "generate", "Text": "Generate Video"}),
                ui.Label({"Text": "beat", "Weight": 0}),
                ui.LineEdit({"ID": "beat", "Text": "act2_rising", "Weight": 1}),
                ui.Button({"ID": "beat_run", "Text": "Run Beat"}),
            ]),
            ui.TextEdit({"ID": "status", "Text": "click Bootstrap Project to create bins and set 4K timeline", "ReadOnly": True, "Weight": 1}),
        ]),
    )
    win.On[win_id].Close = lambda ev: dispatcher.ExitLoop()
    win.On["startup"].Clicked = on_startup
    win.On["bridge"].Clicked = on_bridge
    win.On["import"].Clicked = on_import
    win.On["slug_preview"].Clicked = on_slug_preview
    win.On["generate"].Clicked = on_generate
    win.On["beat_run"].Clicked = on_beat
    win.Show()
    dispatcher.RunLoop()