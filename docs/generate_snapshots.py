#!/usr/bin/env python3
"""Generate UI reference snapshots for GitHub Pages (Resolve blue-grey theme)."""

from __future__ import annotations

from pathlib import Path

try:
    from PIL import Image, ImageDraw, ImageFont
except ImportError:
    raise SystemExit("pip install pillow")

OUT = Path(__file__).parent / "images"
W, H = 960, 580

# Resolve cool blue-grey palette
BG = (27, 29, 32)
HEADER = (23, 25, 28)
PANEL = (37, 39, 43)
ROW = (45, 47, 51)
FIELD = (21, 23, 26)
BORDER = (74, 77, 83)
TEXT = (232, 234, 237)
MUTED = (192, 195, 200)
LABEL = (174, 178, 184)
ACCENT = (249, 139, 20)
TAB_ACTIVE = (59, 61, 65)

TABS = [
    "Canvas", "Import", "Scan", "Bootstrap", "Bridge", "Terminal",
    "Timeline", "Browser", "IMDb", "Stream", "Folder",
]

SCENES: dict[str, dict] = {
    "canvas": {
        "active": "Canvas",
        "panels": [
            ("left", 0.02, 0.16, 0.30, 0.78, "CANVAS VIEWER\nMedia | Preset\n[preview]\nCONTENT META\nFILE · grok_….mp4"),
            ("center", 0.34, 0.16, 0.38, 0.78, "GENRE / PRESET\nPrompt · Imagine + bridge\nOpen · Pull · Push · Bridge Video"),
            ("right", 0.74, 0.16, 0.24, 0.78, "LUT VIEWER\n[poster]\nKodak Portra notes"),
        ],
        "footer": "Close · Generate Video",
    },
    "import": {"active": "Import", "body": "Import clips from video/ and image/\ninto the active Media Pool bin.", "buttons": ["Import to Resolve", "Scan + Import"]},
    "scan": {"active": "Scan", "body": "Find Grok media in Downloads via macOS metadata.", "buttons": ["Scan Downloads"]},
    "bootstrap": {"active": "Bootstrap", "body": "Create 4K bins + grok_generated import target.", "buttons": ["Run Bootstrap"]},
    "bridge": {"active": "Bridge", "body": "Terminal bridge for chat + headless generate.", "buttons": ["Start Bridge"]},
    "terminal": {
        "active": "Terminal",
        "body": "── Grok workflow status ──\nbridge: online\n── menu-last.log ──\n[scan] finished",
        "buttons": ["Refresh", "Run", "Start Bridge", "Open Terminal"],
    },
    "timeline": {
        "active": "Timeline",
        "body": "V1 grok_….mp4 · 01:00:00:00\nClip editor: prompt / slug / LUT\nBatch Save · Batch Regenerate",
        "buttons": ["Scan Timeline", "Refresh", "Batch Regenerate"],
    },
    "browser": {
        "active": "Browser",
        "body": "Safari ↔ grok.com/imagine handoff\ninbox.json · outbox.json · clipboard",
        "buttons": ["Open Safari", "Pull Prompt", "Push Prompt"],
    },
    "imdb": {
        "active": "IMDb",
        "body": "Search title or feel\nResults · Detail · Add to Prompt\nTMDB ✓ · xAI ✓",
        "buttons": ["Search Title", "Generate LUT", "Setup Keys"],
    },
    "stream": {
        "active": "Stream",
        "body": "X.com live workflow\nOBS overlay.html · X Studio RTMP",
        "buttons": ["Open X Studio", "Start Workflow", "Announce on X"],
    },
    "folder": {"active": "Folder", "body": "Open grok-public-folder in Finder.", "buttons": ["Open Folder"]},
}


def font(size: int, bold: bool = False):
    names = [
        "/System/Library/Fonts/SFNS.ttf",
        "/System/Library/Fonts/Supplemental/Arial.ttf",
        "/Library/Fonts/Arial.ttf",
    ]
    for name in names:
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            continue
    return ImageFont.load_default()


def draw_window(draw: ImageDraw.ImageDraw, scene: dict) -> None:
    draw.rectangle([0, 0, W, H], fill=BG)
    draw.rectangle([0, 0, 4, 52], fill=ACCENT)
    draw.text((14, 14), "GROK FOR RESOLVE", fill=TEXT, font=font(11, True))
    draw.text((14, 30), "Imagine canvas → Resolve edit", fill=MUTED, font=font(10))

    x = 10
    for tab in TABS:
        active = tab == scene.get("active")
        tw = 72
        draw.rectangle([x, 58, x + tw, 86], fill=TAB_ACTIVE if active else ROW, outline=BORDER)
        color = ACCENT if active else MUTED
        draw.text((x + 8, 66), tab, fill=color, font=font(9, active))
        x += tw + 2

    if "panels" in scene:
        for _, px, py, pw, ph, label in scene["panels"]:
            x1, y1 = int(W * px), int(H * py)
            x2, y2 = int(W * (px + pw)), int(H * (py + ph))
            draw.rectangle([x1, y1, x2, y2], fill=PANEL, outline=BORDER)
            draw.multiline_text((x1 + 8, y1 + 8), label, fill=MUTED, font=font(9), spacing=4)
        if scene.get("footer"):
            draw.rectangle([0, H - 88, W, H - 44], fill=PANEL, outline=BORDER)
            draw.text((W - 220, H - 72), scene["footer"], fill=TEXT, font=font(10))
    else:
        draw.text((24, 110), scene.get("active", ""), fill=TEXT, font=font(16, True))
        body = scene.get("body", "")
        draw.multiline_text((24, 145), body, fill=MUTED, font=font(11), spacing=6)
        bx = 24
        for btn in scene.get("buttons", []):
            bw = 8 * len(btn) + 24
            draw.rectangle([bx, 280, bx + bw, 308], fill=ROW, outline=BORDER)
            draw.text((bx + 8, 288), btn, fill=TEXT, font=font(9))
            bx += bw + 8

    draw.rectangle([0, H - 44, W, H], fill=HEADER, outline=BORDER)
    draw.text((10, H - 34), "DaVinci Resolve → Workspace → Scripts → Grok", fill=LABEL, font=font(8))


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    for name, scene in SCENES.items():
        img = Image.new("RGB", (W, H), BG)
        draw = ImageDraw.Draw(img)
        draw_window(draw, scene)
        path = OUT / f"tab-{name}.png"
        img.save(path, "PNG")
        print(path)


if __name__ == "__main__":
    main()