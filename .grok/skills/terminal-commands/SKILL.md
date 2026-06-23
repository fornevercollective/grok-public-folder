---
name: terminal-commands
description: >
  Video ingest terminal recipes using yt-dlp, ffmpeg, ffplay, and ffprobe — ported from
  fornevercollective/blank. Use when the user pastes a watch URL, asks for scene snapshots,
  MKV archive commands, ffplay playback, or runs /terminal-commands. Requires yt-dlp, ffmpeg,
  ffplay on PATH. Prefer bin/blank in grok-public-folder over retyping shell one-liners.
---

# Terminal Commands (blank-style ingest)

## Prerequisites

Verify tools before running ingest:

```bash
bin/blank check
```

Requires on PATH: `yt-dlp`, `ffmpeg`, `ffplay` (and `ffprobe` for probe recipes).

## Grok CLI (preferred)

From repo root (`GROK_PUBLIC_FOLDER`):

| Task | Command |
|------|---------|
| Resolve stream URL | `bin/blank resolve '<url>'` |
| Chapters / scenes | `bin/blank intel '<url>'` |
| Single high-res still | `bin/blank snapshot '<url>' 60` |
| Batch scene stills | `bin/blank snapshots '<url>'` |
| MKV archive (background) | `bin/blank download-mkv '<url>'` |
| ffplay resolved stream | `bin/blank play '<url>'` |
| ffplay local MKV | `bin/blank play-file blank/downloads/foo.mkv` |
| Copy-paste recipes | `bin/blank commands '<url>'` |
| List downloads | `bin/blank list-downloads` |

Outputs land in `blank/snapshots/` (JPEG) and `blank/downloads/` (MKV).

## Raw shell recipes (from blank `commandsFor`)

After `bin/blank commands '<url>'`, common patterns:

**Archive MKV**
```bash
yt-dlp -f "bv*+ba/b" --merge-output-format mkv \
  -o 'blank/downloads/%(title)s.%(ext)s' '<url>'
```

**Resolve stream for ffmpeg/ffplay**
```bash
yt-dlp -f "bv*+ba/b" -g --no-warnings --no-playlist '<url>'
```

**High-res scene still @ timestamp**
```bash
STREAM=$(yt-dlp -f b -g --no-warnings --no-playlist '<url>' | head -1)
ffmpeg -hide_banner -loglevel error -ss 60 -i "$STREAM" -vframes 1 -q:v 2 snapshot-60s.jpg
```

**ffplay stream**
```bash
ffplay -autoexit -window_title 'Grok MKV' \
  $(yt-dlp -f 'bv*+ba/b' -g --no-warnings --no-playlist '<url>' | head -1)
```

**ffprobe**
```bash
ffprobe -hide_banner -loglevel quiet -show_format -show_streams -print_format json '<url>'
```

## Resolve UI

Open the **MKV** tab in `bin/grok-menu` for paste-and-click: Resolve, Scenes, Pull Scenes, Download MKV, ffplay Stream/MKV, Terminal Cmds (copies recipes to clipboard).

## Notes

- YouTube: set `YTDLP_PLAYER_CLIENT=android,tv_embedded,ios,mweb` if resolve fails.
- Live streams: intel uses rolling windows; snapshots use `-sseof` seek from live edge.
- Pattern source: https://github.com/fornevercollective/blank/ (`video-ingest.js`, `video-intel.mjs`, `ytdlp-api.mjs`).