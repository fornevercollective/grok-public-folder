#!/usr/bin/env python3
"""Load API keys from project/grok-secrets.env (gitignored)."""

from __future__ import annotations

import os
from pathlib import Path

from grok_paths import PROJECT_DIR, ROOT

SECRETS_FILE = PROJECT_DIR / "grok-secrets.env"
SECRETS_EXAMPLE = PROJECT_DIR / "grok-secrets.example.env"


def load_secrets() -> None:
    """Populate os.environ from grok-secrets.env when keys are not already set."""
    if not SECRETS_FILE.exists():
        return
    for raw in SECRETS_FILE.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip().strip('"').strip("'")
        if key and key not in os.environ:
            os.environ[key] = value


def secrets_status() -> dict:
    load_secrets()
    return {
        "secrets_file": str(SECRETS_FILE),
        "secrets_exists": SECRETS_FILE.exists(),
        "example_file": str(SECRETS_EXAMPLE),
        "xai_configured": bool(os.environ.get("XAI_API_KEY", "").strip()),
        "tmdb_configured": bool(os.environ.get("TMDB_API_KEY", "").strip()),
        "x_bearer_configured": bool(
            os.environ.get("X_BEARER_TOKEN", "").strip()
            or os.environ.get("X_API_BEARER_TOKEN", "").strip()
        ),
        "root": str(ROOT),
    }