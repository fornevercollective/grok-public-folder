#!/usr/bin/env python3
"""Load into Resolve Python console with:
exec(open("/Users/tref/film/grok-public-folder/grok_load.py").read(), globals())
"""

from __future__ import annotations

import sys

from grok_paths import ROOT

if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from grok_api import import_all_artifacts
from grok_bridge_client import send


def grok_help():
    print("grok python ready")
    print(f"folder {ROOT}")
    print("g()                     help")
    print("ping()                  test terminal bridge")
    print('g("your message")       chat')
    print('g("/image prompt")      still')
    print('g("/video prompt")      clip')
    print("import_artifacts()      load into active bin")
    print("")
    print("start terminal bridge first")
    print("export XAI_API_KEY=your-key")
    print(f"{ROOT / 'bin' / 'bridge'}")


def ping():
    return send("ping", "")


def grok_chat(text):
    return send("chat", text)


def grok_image(text):
    return send("image", text)


def grok_video(text, duration=8):
    return send("video", text, duration=duration)


def grok_clear():
    return send("clear", "")


def import_artifacts():
    try:
        count, _, bin_name = import_all_artifacts()
    except Exception as exc:
        print(str(exc))
        return None
    if count == 0:
        print("no files yet")
        print('generate first  g("/video your prompt")')
        return None
    print(f"imported {count} into {bin_name}")
    return count


def grok(text=None):
    if not text:
        grok_help()
        return None
    if text.startswith("/image"):
        return grok_image(text[6:].strip())
    if text.startswith("/video"):
        return grok_video(text[6:].strip())
    if text.startswith("/import"):
        return import_artifacts()
    if text.startswith("/clear"):
        return grok_clear()
    return grok_chat(text)


def g(text=None):
    return grok(text)


grok_help()