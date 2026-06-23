#!/usr/bin/env python3
"""Video ingest from blank (fornevercollective/blank) — yt-dlp, ffmpeg, ffplay."""

from __future__ import annotations

import hashlib
import json
import os
import re
import shlex
import shutil
import subprocess
import sys
import time
from pathlib import Path
from typing import Any
from urllib.parse import urlparse

from grok_paths import BLANK_DIR, BLANK_CACHE_DIR, BLANK_DOWNLOADS_DIR, BLANK_SNAPSHOTS_DIR, ROOT

YTDLP_FORMAT = "bv*+ba/b"
YTDLP_THUMB_FORMAT = "b"
INTEL_TTL_SEC = 30 * 60
RESOLVE_TIMEOUT_SEC = 120
FFMPEG_TIMEOUT_SEC = 25

TRAILING_URL_PUNCT = {".", ",", ";", ":", ")", "]", "}", "!", "`", "·", "…"}
TRACKING_PARAMS = {
    "utm_source",
    "utm_medium",
    "utm_campaign",
    "utm_term",
    "utm_content",
    "fbclid",
    "gclid",
    "si",
    "feature",
    "share_id",
    "is_from_webapp",
    "sender_device",
    "sender_web_id",
    "enter_from",
    "enter_method",
    "sec_uid",
}


def _ensure_dirs() -> None:
    BLANK_DIR.mkdir(parents=True, exist_ok=True)
    BLANK_DOWNLOADS_DIR.mkdir(parents=True, exist_ok=True)
    BLANK_SNAPSHOTS_DIR.mkdir(parents=True, exist_ok=True)
    BLANK_CACHE_DIR.mkdir(parents=True, exist_ok=True)


def _which(name: str) -> str | None:
    return shutil.which(name)


def _shell_quote(value: str) -> str:
    return shlex.quote(value)


def _json_out(payload: dict[str, Any], ok: bool = True) -> None:
    payload.setdefault("ok", ok)
    print(json.dumps(payload, indent=2))


def _error(message: str, **extra: Any) -> int:
    _json_out({"ok": False, "error": message, **extra})
    return 1


def trim_url_trailing_punct(url: str) -> str:
    text = str(url)
    while text and text[-1] in TRAILING_URL_PUNCT:
        text = text[:-1]
    return text


def extract_first_http_url(haystack: str) -> str | None:
    search = 0
    text = str(haystack)
    while search < len(text):
        tail = text[search:]
        rel = -1
        proto_len = 0
        if "https://" in tail:
            rel = tail.index("https://")
            proto_len = len("https://")
        elif "http://" in tail:
            rel = tail.index("http://")
            proto_len = len("http://")
        else:
            return None
        start = search + rel
        after_proto = text[start + proto_len :]
        end_rel = next(
            (i for i, c in enumerate(after_proto) if c.isspace() or c in "\"')]>{}"),
            -1,
        )
        end = start + proto_len + (len(after_proto) if end_rel == -1 else end_rel)
        slice_ = trim_url_trailing_punct(text[start:end])
        if len(slice_) >= len("http://x"):
            return slice_
        search = start + 1
    return None


def pick_watch_url(raw: str) -> str:
    stripped = raw.strip()
    for prefix in ("mustream://", "x-mustream://", "mustream:"):
        if stripped.lower().startswith(prefix):
            stripped = stripped[len(prefix) :].lstrip("/").strip()
            break
    unquoted = stripped.strip("\"'")
    for line in unquoted.splitlines():
        t = line.strip()
        if not t:
            continue
        embedded = extract_first_http_url(t)
        if embedded:
            return embedded
        if t.startswith("http://") or t.startswith("https://"):
            return trim_url_trailing_punct(t)
    embedded = extract_first_http_url(unquoted)
    if embedded:
        return embedded
    return trim_url_trailing_punct(unquoted)


def canonicalize_watch_url(url: str) -> str:
    try:
        parsed = urlparse(url)
        host = (parsed.hostname or "").lower().removeprefix("www.")
        if host in {"tiktok.com", "vm.tiktok.com"}:
            path = parsed.path.rstrip("/") or ""
            if host == "vm.tiktok.com" and path:
                return f"https://www.tiktok.com{path}"
            return f"https://www.tiktok.com{path or '/'}"
        from urllib.parse import parse_qsl, urlencode, urlunparse

        query_pairs = parse_qsl(parsed.query, keep_blank_values=True)
        clean_pairs = []
        for key, val in query_pairs:
            low = key.lower()
            if low in TRACKING_PARAMS or low.startswith("utm_"):
                continue
            if host.endswith("twitch.tv") and low.startswith("tt_"):
                continue
            clean_pairs.append((key, val))
        clean = parsed._replace(query=urlencode(clean_pairs), fragment="")
        out = urlunparse(clean)
        if not clean_pairs:
            out = out.rstrip("?")
        return out
    except Exception:
        return trim_url_trailing_punct(url)


def normalize_url(raw: str) -> str:
    picked = pick_watch_url(raw)
    if not picked.startswith(("http://", "https://")):
        return picked
    return canonicalize_watch_url(picked)


def classify_url(url: str) -> str:
    u = url.strip()
    if not u.startswith(("http://", "https://")):
        return "unknown"
    low = u.lower().split("?")[0].split("#")[0]
    if low.endswith(".m3u8") or ".m3u8" in low:
        return "hls"
    if re.search(r"\.(mp4|webm|mkv)$", low, re.I):
        return "direct"
    if re.search(r"youtube\.com|youtu\.be", u, re.I):
        return "youtube"
    if "vimeo.com" in u:
        return "vimeo"
    if re.search(r"tiktok\.com|vm\.tiktok\.com", u, re.I):
        return "tiktok"
    if re.search(r"twitch\.tv", u, re.I):
        return "twitch"
    if re.search(r"twitter\.com|x\.com", u, re.I):
        return "twitter"
    return "page"


def kind_label(kind: str) -> str:
    labels = {
        "youtube": "YouTube",
        "vimeo": "Vimeo",
        "tiktok": "TikTok",
        "hls": "HLS (.m3u8)",
        "direct": "Direct file",
        "twitch": "Twitch",
        "twitter": "X / Twitter",
        "page": "Watch page",
        "unknown": "Unknown",
    }
    return labels.get(kind, kind)


def format_clock(seconds: float) -> str:
    sec = max(0, int(seconds))
    h, rem = divmod(sec, 3600)
    m, s = divmod(rem, 60)
    if h:
        return f"{h}:{m:02d}:{s:02d}"
    return f"{m:02d}:{s:02d}"


def check_prereqs() -> dict[str, Any]:
    tools = {}
    for name in ("yt-dlp", "ffmpeg", "ffplay", "ffprobe"):
        path = _which(name)
        tools[name] = {"found": bool(path), "path": path}
    return {
        "ok": all(tools[n]["found"] for n in ("yt-dlp", "ffmpeg", "ffplay")),
        "tools": tools,
        "blank_dir": str(BLANK_DIR),
        "downloads_dir": str(BLANK_DOWNLOADS_DIR),
        "snapshots_dir": str(BLANK_SNAPSHOTS_DIR),
    }


def _run_ytdlp(args: list[str], timeout_sec: int = RESOLVE_TIMEOUT_SEC) -> str:
    ytdlp = _which("yt-dlp")
    if not ytdlp:
        raise RuntimeError("yt-dlp not found on PATH")
    try:
        proc = subprocess.run(
            [ytdlp, *args],
            capture_output=True,
            text=True,
            timeout=timeout_sec,
            check=False,
        )
    except subprocess.TimeoutExpired as exc:
        raise RuntimeError("yt-dlp timed out") from exc
    if proc.returncode != 0:
        tail = (proc.stderr or proc.stdout or "").strip().splitlines()[-4:]
        raise RuntimeError(" ".join(tail) or f"yt-dlp exit {proc.returncode}")
    return proc.stdout.strip()


def _run_ytdlp_for_page(page_url: str, args: list[str], timeout_sec: int = 90) -> str:
    if not re.search(r"youtube\.com|youtu\.be", page_url, re.I):
        return _run_ytdlp([*args, page_url], timeout_sec)
    clients = os.environ.get("YTDLP_PLAYER_CLIENT", "android,tv_embedded,ios,mweb").split(",")
    last_err: Exception | None = None
    for client in [c.strip() for c in clients if c.strip()]:
        try:
            return _run_ytdlp(
                [*args, "--extractor-args", f"youtube:player_client={client}", page_url],
                timeout_sec,
            )
        except RuntimeError as exc:
            last_err = exc
    if last_err:
        raise last_err
    raise RuntimeError("yt-dlp failed for all player clients")


def resolve_stream_url(page_url: str, fmt: str = YTDLP_FORMAT) -> str:
    out = _run_ytdlp_for_page(page_url, ["-f", fmt, "-g", "--no-warnings", "--no-playlist"])
    lines = [
        line.strip()
        for line in out.splitlines()
        if line.strip().startswith(("http://", "https://"))
    ]
    if not lines:
        raise RuntimeError("yt-dlp returned no stream URL")
    return lines[0]


def fetch_title(page_url: str) -> str | None:
    try:
        out = _run_ytdlp_for_page(
            page_url,
            ["--no-warnings", "--no-playlist", "--print", "%(title)s"],
            45,
        )
        for line in out.splitlines():
            t = line.strip()
            if t:
                return t
    except RuntimeError:
        return None
    return None


def _intel_cache_path(page_url: str) -> Path:
    digest = hashlib.sha256(page_url.encode("utf-8")).hexdigest()[:16]
    return BLANK_CACHE_DIR / f"intel-{digest}.json"


def fetch_intel(page_url: str, force: bool = False) -> dict[str, Any]:
    cache_path = _intel_cache_path(page_url)
    if not force and cache_path.exists():
        try:
            cached = json.loads(cache_path.read_text(encoding="utf-8"))
            if time.time() - cached.get("_cached_at", 0) < INTEL_TTL_SEC:
                return cached
        except (json.JSONDecodeError, OSError):
            pass

    raw = _run_ytdlp_for_page(page_url, ["-J", "--no-warnings", "--no-playlist"])
    data = json.loads(raw)
    is_live = (
        data.get("is_live") is True
        or data.get("live_status") in {"is_live", "post_live"}
    )
    duration = data.get("duration")
    scenes: list[dict[str, Any]] = []

    if is_live:
        now_ms = time.time() * 1000
        started_ms = (
            float(data["release_timestamp"]) * 1000
            if data.get("release_timestamp")
            else now_ms - 20 * 60 * 1000
        )
        elapsed_sec = max(0, int((now_ms - started_ms) / 1000))
        window = min(20 * 60, max(90 * 4, elapsed_sec))
        step = 90
        steps = max(1, window // step)
        for i in range(steps):
            back = i * step
            scene_end = max(step, elapsed_sec - back)
            scene_start = max(0, scene_end - step)
            label = (
                f"Live · now ({format_clock(scene_end)})"
                if back == 0
                else f"Live −{format_clock(back)} · {format_clock(scene_end)}"
            )
            scenes.append(
                {
                    "start": scene_start,
                    "end": scene_end,
                    "title": label,
                    "live": True,
                }
            )
    elif isinstance(data.get("chapters"), list) and data["chapters"]:
        for ch in data["chapters"]:
            start = float(ch.get("start_time") or 0)
            end = float(ch.get("end_time") or start)
            scenes.append(
                {
                    "start": start,
                    "end": end,
                    "title": str(ch.get("title") or "Chapter").strip(),
                }
            )
    elif not is_live and isinstance(duration, (int, float)) and duration > 30:
        max_synthetic = 24
        step = max(45, int(duration / max_synthetic))
        t = 0.0
        while t < duration:
            scenes.append(
                {
                    "start": t,
                    "end": min(t + step, duration),
                    "title": f"Scene {format_clock(t)}",
                }
            )
            t += step

    if len(scenes) > 48:
        scenes = scenes[:48]

    intel = {
        "ok": True,
        "url": page_url,
        "kind": classify_url(page_url),
        "title": str(data.get("title") or "").strip(),
        "description": str(data.get("description") or "").strip()[:2000],
        "duration": duration,
        "duration_label": "LIVE" if is_live else (format_clock(duration) if duration else None),
        "is_live": is_live,
        "scenes": scenes,
        "thumbnail": data.get("thumbnail"),
        "_cached_at": time.time(),
    }
    try:
        cache_path.write_text(json.dumps(intel, indent=2), encoding="utf-8")
    except OSError:
        pass
    return intel


def _snapshot_path(page_url: str, t_sec: float) -> Path:
    digest = hashlib.sha256(f"{page_url}\0{int(t_sec)}".encode()).hexdigest()[:12]
    safe_title = re.sub(r"[^a-zA-Z0-9_-]+", "-", (fetch_title(page_url) or "snapshot")[:40]).strip("-")
    return BLANK_SNAPSHOTS_DIR / f"{safe_title or 'snapshot'}-{int(t_sec)}s-{digest}.jpg"


def capture_snapshot(page_url: str, t_sec: float, force: bool = False) -> dict[str, Any]:
    _ensure_dirs()
    ffmpeg = _which("ffmpeg")
    if not ffmpeg:
        raise RuntimeError("ffmpeg not found on PATH")

    out_path = _snapshot_path(page_url, t_sec)
    if not force and out_path.exists() and out_path.stat().st_size > 0:
        return {
            "ok": True,
            "path": str(out_path),
            "t": t_sec,
            "cached": True,
            "width": None,
            "height": None,
        }

    stream_url = resolve_stream_url(page_url, YTDLP_THUMB_FORMAT)
    intel = fetch_intel(page_url)
    is_live = intel.get("is_live", False)
    seek_front: list[str] = []
    seek_eof: list[str] = []
    if is_live:
        back = max(0, int(t_sec))
        seek_eof = ["-sseof", f"-{back}"]
    else:
        seek_front = ["-ss", str(max(0, t_sec))]

    try:
        proc = subprocess.run(
            [
                ffmpeg,
                "-hide_banner",
                "-loglevel",
                "error",
                *seek_front,
                *seek_eof,
                "-i",
                stream_url,
                "-vframes",
                "1",
                "-q:v",
                "2",
                "-y",
                str(out_path),
            ],
            capture_output=True,
            text=True,
            timeout=FFMPEG_TIMEOUT_SEC,
            check=False,
        )
    except subprocess.TimeoutExpired as exc:
        raise RuntimeError("ffmpeg scene thumb timed out") from exc

    if proc.returncode != 0 or not out_path.exists():
        raise RuntimeError((proc.stderr or "").strip() or f"ffmpeg exit {proc.returncode}")

    return {
        "ok": True,
        "path": str(out_path),
        "t": t_sec,
        "cached": False,
        "size_bytes": out_path.stat().st_size,
    }


def capture_scene_snapshots(page_url: str, limit: int = 12, force: bool = False) -> dict[str, Any]:
    intel = fetch_intel(page_url)
    scenes = intel.get("scenes") or []
    if limit > 0:
        scenes = scenes[:limit]
    results = []
    errors = []
    for sc in scenes:
        t = float(sc.get("start") or 0)
        try:
            snap = capture_snapshot(page_url, t, force=force)
            results.append(
                {
                    "t": t,
                    "title": sc.get("title"),
                    "path": snap["path"],
                }
            )
        except RuntimeError as exc:
            errors.append({"t": t, "title": sc.get("title"), "error": str(exc)})
    return {
        "ok": True,
        "url": page_url,
        "title": intel.get("title"),
        "snapshots": results,
        "errors": errors,
    }


def start_mkv_download(page_url: str) -> dict[str, Any]:
    _ensure_dirs()
    ytdlp = _which("yt-dlp")
    if not ytdlp:
        raise RuntimeError("yt-dlp not found on PATH")
    out_tpl = str(BLANK_DOWNLOADS_DIR / "%(title)s.%(ext)s")
    args = [
        ytdlp,
        "-f",
        YTDLP_FORMAT,
        "--merge-output-format",
        "mkv",
        "-o",
        out_tpl,
        "--no-warnings",
        "--no-playlist",
        page_url,
    ]
    log_path = BLANK_CACHE_DIR / "last-download.log"
    with open(log_path, "a", encoding="utf-8") as log:
        log.write(f"\n--- {time.strftime('%Y-%m-%d %H:%M:%S')} {page_url}\n")
    proc = subprocess.Popen(
        args,
        stdout=open(log_path, "a", encoding="utf-8"),
        stderr=subprocess.STDOUT,
        start_new_session=True,
    )
    return {
        "ok": True,
        "pid": proc.pid,
        "output_template": out_tpl,
        "log": str(log_path),
        "message": "MKV download started in background",
    }


def list_downloads() -> list[dict[str, Any]]:
    _ensure_dirs()
    rows = []
    for path in sorted(BLANK_DOWNLOADS_DIR.glob("*.mkv"), key=lambda p: p.stat().st_mtime, reverse=True):
        stat = path.stat()
        rows.append(
            {
                "name": path.name,
                "path": str(path),
                "size_bytes": stat.st_size,
                "modified": stat.st_mtime,
            }
        )
    return rows


def commands_for(url: str) -> list[dict[str, str]]:
    u = normalize_url(url)
    kind = classify_url(u)
    q = _shell_quote(u)
    dl_tpl = _shell_quote(str(BLANK_DOWNLOADS_DIR / "%(title)s.%(ext)s"))
    rows = [
        {
            "section": "Archive, probe, play",
            "label": "yt-dlp archive (MKV)",
            "cmd": f'yt-dlp -f "{YTDLP_FORMAT}" --merge-output-format mkv -o {dl_tpl} {q}',
        },
        {
            "section": "Archive, probe, play",
            "label": "yt-dlp resolve stream URL",
            "cmd": f'yt-dlp -f "{YTDLP_FORMAT}" -g --no-warnings --no-playlist {q}',
        },
        {
            "section": "Archive, probe, play",
            "label": "ffprobe JSON",
            "cmd": f"ffprobe -hide_banner -loglevel quiet -show_format -show_streams -print_format json {q}",
        },
        {
            "section": "Archive, probe, play",
            "label": "ffprobe terse",
            "cmd": f"ffprobe -hide_banner {q}",
        },
        {
            "section": "Archive, probe, play",
            "label": "ffplay stream (autoexit)",
            "cmd": f"ffplay -autoexit -window_title 'Grok MKV' $(yt-dlp -f '{YTDLP_FORMAT}' -g --no-warnings --no-playlist {q} | head -1)",
        },
        {
            "section": "Snapshots",
            "label": "ffmpeg scene still @ 60s",
            "cmd": (
                f"STREAM=$(yt-dlp -f b -g --no-warnings --no-playlist {q} | head -1) && "
                f"ffmpeg -hide_banner -loglevel error -ss 60 -i \"$STREAM\" -vframes 1 -q:v 2 snapshot-60s.jpg"
            ),
        },
        {
            "section": "Grok CLI",
            "label": "bin/blank intel",
            "cmd": f"bin/blank intel {q}",
        },
        {
            "section": "Grok CLI",
            "label": "bin/blank snapshots",
            "cmd": f"bin/blank snapshots {q}",
        },
        {
            "section": "Grok CLI",
            "label": "bin/blank download-mkv",
            "cmd": f"bin/blank download-mkv {q}",
        },
    ]
    if kind in {"hls", "direct"}:
        rows.insert(
            4,
            {
                "section": "Archive, probe, play",
                "label": "ffplay direct URL",
                "cmd": f"ffplay -autoexit -window_title 'Grok MKV' {q}",
            },
        )
    return rows


def play_stream(page_url: str) -> int:
    ffplay = _which("ffplay")
    if not ffplay:
        raise RuntimeError("ffplay not found on PATH")
    stream_url = resolve_stream_url(page_url)
    title = fetch_title(page_url) or "Grok MKV"
    subprocess.Popen(
        [ffplay, "-autoexit", "-window_title", title[:80], stream_url],
        start_new_session=True,
    )
    return 0


def play_file(path: str) -> int:
    ffplay = _which("ffplay")
    if not ffplay:
        raise RuntimeError("ffplay not found on PATH")
    file_path = Path(path).expanduser().resolve()
    if not file_path.exists():
        raise RuntimeError(f"file not found: {file_path}")
    subprocess.Popen(
        [ffplay, "-autoexit", "-window_title", file_path.name, str(file_path)],
        start_new_session=True,
    )
    return 0


def main(argv: list[str] | None = None) -> int:
    args = argv if argv is not None else sys.argv[1:]
    if not args or args[0] in {"-h", "--help"}:
        print(
            "usage: grok_blank_ingest.py "
            "<check|status|resolve|intel|snapshot|snapshots|download-mkv|play|play-file|commands|list-downloads|open-folder> [args]"
        )
        print("requires: yt-dlp, ffmpeg, ffplay on PATH")
        return 0

    cmd = args[0]
    try:
        if cmd == "check":
            _json_out(check_prereqs())
            return 0 if check_prereqs()["ok"] else 1

        if cmd == "status":
            prereqs = check_prereqs()
            _json_out(
                {
                    "ok": prereqs["ok"],
                    "root": str(ROOT),
                    "blank_dir": str(BLANK_DIR),
                    "tools": prereqs["tools"],
                    "downloads": list_downloads()[:8],
                }
            )
            return 0

        if cmd in {"open-folder", "open-downloads", "open-snapshots"}:
            target = BLANK_DIR
            if cmd == "open-downloads":
                target = BLANK_DOWNLOADS_DIR
            elif cmd == "open-snapshots":
                target = BLANK_SNAPSHOTS_DIR
            _ensure_dirs()
            subprocess.run(["open", str(target)], check=False)
            _json_out({"ok": True, "opened": str(target)})
            return 0

        if cmd == "list-downloads":
            _json_out({"ok": True, "downloads": list_downloads()})
            return 0

        if cmd == "commands":
            raw = " ".join(args[1:])
            if not raw:
                raise RuntimeError("commands requires a URL")
            url = normalize_url(raw)
            _json_out(
                {
                    "ok": True,
                    "url": url,
                    "kind": classify_url(url),
                    "kind_label": kind_label(classify_url(url)),
                    "commands": commands_for(url),
                }
            )
            return 0

        if cmd == "resolve":
            raw = " ".join(args[1:])
            if not raw:
                raise RuntimeError("resolve requires a URL")
            url = normalize_url(raw)
            stream = resolve_stream_url(url)
            _json_out(
                {
                    "ok": True,
                    "url": url,
                    "kind": classify_url(url),
                    "title": fetch_title(url),
                    "stream_url": stream,
                }
            )
            return 0

        if cmd == "intel":
            raw = " ".join(args[1:])
            force = False
            if raw.startswith("--force "):
                force = True
                raw = raw[8:]
            if not raw:
                raise RuntimeError("intel requires a URL")
            url = normalize_url(raw)
            _json_out(fetch_intel(url, force=force))
            return 0

        if cmd == "snapshot":
            if len(args) < 3:
                raise RuntimeError("snapshot requires URL and seconds")
            url = normalize_url(args[1])
            t_sec = float(args[2])
            force = "--force" in args[3:]
            _json_out(capture_snapshot(url, t_sec, force=force))
            return 0

        if cmd == "snapshots":
            raw = " ".join(args[1:])
            limit = 12
            force = False
            if raw.startswith("--limit "):
                parts = raw.split()
                limit = int(parts[1])
                raw = " ".join(parts[2:])
            if raw.startswith("--force "):
                force = True
                raw = raw[8:]
            if not raw:
                raise RuntimeError("snapshots requires a URL")
            url = normalize_url(raw)
            _json_out(capture_scene_snapshots(url, limit=limit, force=force))
            return 0

        if cmd == "download-mkv":
            raw = " ".join(args[1:])
            if not raw:
                raise RuntimeError("download-mkv requires a URL")
            url = normalize_url(raw)
            _json_out(start_mkv_download(url))
            return 0

        if cmd == "play":
            raw = " ".join(args[1:])
            if not raw:
                raise RuntimeError("play requires a URL")
            url = normalize_url(raw)
            play_stream(url)
            _json_out({"ok": True, "message": f"ffplay started for {url}"})
            return 0

        if cmd == "play-file":
            if len(args) < 2:
                raise RuntimeError("play-file requires a path")
            play_file(args[1])
            _json_out({"ok": True, "message": f"ffplay started for {args[1]}"})
            return 0

    except (RuntimeError, ValueError, IndexError, json.JSONDecodeError) as exc:
        return _error(str(exc))

    return _error(f"unknown command: {cmd}")


if __name__ == "__main__":
    raise SystemExit(main())