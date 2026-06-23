#!/usr/bin/env python3
"""Resolve Py3 console entry — exec(open("grok_load.py").read(), globals())"""

from __future__ import annotations

import os
from pathlib import Path

_ROOT = Path(os.environ.get("GROK_PUBLIC_FOLDER", Path(__file__).resolve().parent))
exec(open(_ROOT / "grok_bridge_console.py", encoding="utf-8").read(), globals())