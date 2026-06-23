#!/usr/bin/env python3
"""Timeline Grok clip scan, meta editing, and batch processing."""

from __future__ import annotations

import argparse
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

from grok_meta import read_sidecar, sidecar_path, write_sidecar
from grok_paths import BRIDGE_DIR, IMAGE_DIR, PROJECT_DIR, ROOT, VIDEO_DIR

SCAN_FILE = PROJECT_DIR / "timeline-grok-clips.json"
SCAN_REQUEST_FILE = PROJECT_DIR / "timeline-scan-request.json"
BATCH_FILE = BRIDGE_DIR / "timeline-batch.json"
MEDIA_DIRS = (VIDEO_DIR, IMAGE_DIR)


def _read_json(path: Path) -> dict | None:
    if not path.exists():
        return None
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return None


def _write_json(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2), encoding="utf-8")


def _enrich_clip(clip: dict) -> dict:
    file_path = clip.get("file_path") or ""
    path = Path(file_path) if file_path else None
    sidecar = clip.get("sidecar")
    if not sidecar and path and path.exists():
        sidecar = read_sidecar(path)
    if sidecar:
        clip["sidecar"] = sidecar
    clip["prompt"] = (sidecar or {}).get("prompt", "")
    clip["slug"] = (sidecar or {}).get("slug", "")
    clip["lut"] = (sidecar or {}).get("lut", "")
    clip["duration"] = (sidecar or {}).get("duration")
    clip["resolution"] = (sidecar or {}).get("resolution", "")
    clip["aspect_ratio"] = (sidecar or {}).get("aspect_ratio", "")
    clip["continuity"] = (sidecar or {}).get("continuity", "")
    clip["prompt_add"] = (sidecar or {}).get("prompt_add", "")
    return clip


def load_scan(enrich: bool = True) -> dict:
    data = _read_json(SCAN_FILE) or {
        "scanned_at": None,
        "project_name": "",
        "timeline_name": "",
        "clip_count": 0,
        "clips": [],
    }
    if enrich and data.get("clips"):
        data["clips"] = [_enrich_clip(dict(c)) for c in data["clips"]]
    return data


def _get_resolve_project():
    try:
        from grok_api import get_resolve
    except ImportError:
        return None, {"ok": False, "error": "grok_api unavailable", "clips": []}

    resolve = get_resolve()
    if not resolve:
        return None, {
            "ok": False,
            "error": "Resolve not connected — use Scan Timeline from Grok menu inside Resolve",
            "clips": [],
        }

    project = resolve.GetProjectManager().GetCurrentProject()
    if not project:
        return None, {"ok": False, "error": "open a project first", "clips": []}
    return project, None


def _timeline_duration_label(timeline) -> str | None:
    try:
        start = int(timeline.GetStartFrame() or 0)
        end = int(timeline.GetEndFrame() or 0)
        if end > start:
            frames = end - start
            return f"{frames} fr"
    except Exception:
        pass
    return None


def list_project_timelines() -> dict:
    project, err = _get_resolve_project()
    if err:
        return err

    current = project.GetCurrentTimeline()
    current_name = current.GetName() if current else None
    count = int(project.GetTimelineCount() or 0)
    timelines: list[dict] = []
    for idx in range(1, count + 1):
        try:
            tl = project.GetTimelineByIndex(idx)
        except Exception:
            tl = None
        if not tl:
            continue
        name = str(tl.GetName() or f"Timeline {idx}")
        is_current = False
        if current is not None:
            try:
                is_current = tl == current
            except Exception:
                is_current = name == (current_name or "")
        if not is_current and current_name:
            is_current = name == current_name
        timelines.append(
            {
                "index": idx,
                "name": name,
                "is_current": is_current,
                "duration_label": _timeline_duration_label(tl),
            }
        )

    return {
        "ok": True,
        "project_name": project.GetName(),
        "timeline_count": len(timelines),
        "current_timeline": current_name,
        "timelines": timelines,
    }


def _select_timeline(project, timeline_index: int | None = None, timeline_name: str | None = None):
    if timeline_index is not None:
        timeline = project.GetTimelineByIndex(int(timeline_index))
        if not timeline:
            return None, f"timeline index {timeline_index} not found"
        try:
            project.SetCurrentTimeline(timeline)
        except Exception:
            pass
        return timeline, None

    if timeline_name:
        count = int(project.GetTimelineCount() or 0)
        for idx in range(1, count + 1):
            tl = project.GetTimelineByIndex(idx)
            if tl and str(tl.GetName() or "") == timeline_name:
                try:
                    project.SetCurrentTimeline(tl)
                except Exception:
                    pass
                return tl, None
        return None, f"timeline not found: {timeline_name}"

    timeline = project.GetCurrentTimeline()
    if not timeline:
        return None, "open a timeline first"
    return timeline, None


def scan_resolve_timeline(
    timeline_index: int | None = None,
    timeline_name: str | None = None,
) -> dict:
    project, err = _get_resolve_project()
    if err:
        return err

    timeline, tl_err = _select_timeline(project, timeline_index, timeline_name)
    if tl_err or not timeline:
        return {"ok": False, "error": tl_err or "timeline not available", "clips": []}

    fps = float(project.GetSetting("timelineFrameRate") or 24)
    clips: list[dict] = []
    track_count = timeline.GetTrackCount("video") or 0
    grok_root = str(ROOT)

    for track_index in range(1, track_count + 1):
        items = timeline.GetItemListInTrack("video", track_index) or []
        for item_index, item in enumerate(items, start=1):
            try:
                media_item = item.GetMediaPoolItem()
                if not media_item:
                    continue
                file_path = str(media_item.GetClipProperty("File Path") or "")
                file_name = str(media_item.GetClipProperty("File Name") or media_item.GetName() or "")
                if not _is_grok_path(file_path, file_name):
                    continue
                start_frame = int(item.GetStart() or 0)
                end_frame = int(item.GetEnd() or 0)
                if end_frame <= start_frame:
                    duration_frames = int(item.GetDuration() or 0)
                    if duration_frames > 0:
                        end_frame = start_frame + duration_frames
                duration = max(0, end_frame - start_frame)
                sidecar = read_sidecar(Path(file_path)) if file_path else None
                clips.append(
                    {
                        "id": f"v{track_index}_{item_index}",
                        "track": track_index,
                        "track_type": "video",
                        "name": file_name,
                        "file_path": file_path,
                        "start_frame": start_frame,
                        "end_frame": end_frame,
                        "duration_frames": duration,
                        "timeline_in": _frames_to_tc(start_frame, fps),
                        "timeline_out": _frames_to_tc(end_frame, fps),
                        "sidecar": sidecar,
                        "is_grok": True,
                    }
                )
            except Exception as exc:
                print(f"timeline scan: skipped v{track_index}_{item_index}: {exc}", file=sys.stderr)

    timeline_index_used = timeline_index
    if timeline_index_used is None and timeline_name:
        count = int(project.GetTimelineCount() or 0)
        for idx in range(1, count + 1):
            tl = project.GetTimelineByIndex(idx)
            if tl and str(tl.GetName() or "") == str(timeline.GetName() or ""):
                timeline_index_used = idx
                break

    payload = {
        "scanned_at": datetime.now(timezone.utc).isoformat(),
        "project_name": project.GetName(),
        "timeline_name": timeline.GetName(),
        "timeline_index": timeline_index_used,
        "fps": fps,
        "clip_count": len(clips),
        "clips": [_enrich_clip(c) for c in clips],
        "source": "python",
    }
    _write_json(SCAN_FILE, payload)
    return {"ok": True, "clip_count": len(clips), "scan": payload}


def _is_grok_path(file_path: str, file_name: str) -> bool:
    path = file_path or ""
    name = (file_name or Path(path).name).lower()
    if str(ROOT) in path:
        return True
    if name.startswith("grok_"):
        return True
    if path and read_sidecar(Path(path)):
        return True
    return False


def _frames_to_tc(frames: int, fps: float) -> str:
    fps = fps or 24
    total_seconds = int(frames / fps)
    f = int(frames % fps)
    s = total_seconds % 60
    m = (total_seconds // 60) % 60
    h = total_seconds // 3600
    return f"{h:02d}:{m:02d}:{s:02d}:{f:02d}"


def scan_artifacts_only() -> dict:
    """Fallback: all local artifacts with sidecars (no timeline positions)."""
    clips: list[dict] = []
    for folder in MEDIA_DIRS:
        if not folder.exists():
            continue
        for path in sorted(folder.iterdir()):
            if not path.is_file() or path.name.startswith("."):
                continue
            if path.suffix == ".grok.json":
                continue
            sidecar = read_sidecar(path)
            if not sidecar and not path.name.lower().startswith("grok_"):
                continue
            clips.append(
                _enrich_clip(
                    {
                        "id": f"artifact_{len(clips) + 1}",
                        "track": 0,
                        "track_type": "artifact",
                        "name": path.name,
                        "file_path": str(path),
                        "start_frame": 0,
                        "end_frame": 0,
                        "duration_frames": 0,
                        "timeline_in": "—",
                        "timeline_out": "—",
                        "sidecar": sidecar,
                        "is_grok": True,
                    }
                )
            )
    payload = {
        "scanned_at": datetime.now(timezone.utc).isoformat(),
        "project_name": "",
        "timeline_name": "(artifacts library — run Scan Timeline in Resolve for positions)",
        "clip_count": len(clips),
        "clips": clips,
        "source": "artifacts",
    }
    _write_json(SCAN_FILE, payload)
    return {"ok": True, "clip_count": len(clips), "scan": payload}


def update_clip_meta(clip_id: str, fields: dict) -> dict:
    scan = load_scan(enrich=True)
    clip = next((c for c in scan.get("clips", []) if c.get("id") == clip_id), None)
    if not clip:
        return {"ok": False, "error": f"clip not found: {clip_id}"}
    file_path = clip.get("file_path")
    if not file_path:
        return {"ok": False, "error": "clip has no file_path"}
    path = Path(file_path)
    if not path.exists():
        return {"ok": False, "error": f"file missing: {file_path}"}

    existing = read_sidecar(path) or {"source": "grok", "file": path.name}
    for key in ("prompt", "slug", "lut", "duration", "resolution", "aspect_ratio", "continuity", "prompt_add"):
        if key in fields and fields[key] is not None:
            existing[key] = fields[key]
    write_sidecar(path, existing)

    for key, value in fields.items():
        clip[key] = value
    clip["sidecar"] = existing
    _write_json(SCAN_FILE, scan)
    return {"ok": True, "clip": clip}


def batch_update(updates: list[dict]) -> dict:
    results = []
    for item in updates:
        clip_id = item.get("id")
        if not clip_id:
            continue
        fields = {k: v for k, v in item.items() if k != "id"}
        results.append(update_clip_meta(clip_id, fields))
    ok = all(r.get("ok") for r in results)
    return {"ok": ok, "results": results, "count": len(results)}


def prepare_batch_regenerate(clip_ids: list[str]) -> dict:
    scan = load_scan(enrich=True)
    jobs = []
    for clip in scan.get("clips", []):
        if clip.get("id") not in clip_ids:
            continue
        prompt = (clip.get("prompt") or "").strip()
        if not prompt:
            continue
        jobs.append(
            {
                "id": clip["id"],
                "file_path": clip.get("file_path"),
                "slug": clip.get("slug") or "neo-noir",
                "prompt": prompt,
                "duration": clip.get("duration") or 10,
                "resolution": clip.get("resolution") or "720p",
                "aspect_ratio": clip.get("aspect_ratio") or "16:9",
                "lut": clip.get("lut") or "",
                "prompt_add": clip.get("prompt_add") or "",
                "continuity": clip.get("continuity") or "",
            }
        )
    payload = {
        "created_at": datetime.now(timezone.utc).isoformat(),
        "job_count": len(jobs),
        "jobs": jobs,
    }
    _write_json(BATCH_FILE, payload)
    return {"ok": True, "job_count": len(jobs), "batch_file": str(BATCH_FILE)}


def run_batch_regenerate() -> int:
    batch = _read_json(BATCH_FILE)
    if not batch or not batch.get("jobs"):
        print("no batch jobs in timeline-batch.json", file=sys.stderr)
        return 1
    from grok_api import generate_video, require_api_key
    from grok_presets import compose_prompt

    api_key = require_api_key()
    code = 0
    for job in batch["jobs"]:
        slug = job.get("slug") or "neo-noir"
        prompt = compose_prompt(slug, job.get("prompt", ""), job.get("prompt_add", ""))
        print(f"generate {job['id']}: {slug} — {prompt[:80]}…")
        try:
            generate_video(
                api_key,
                prompt,
                duration=int(job.get("duration") or 10),
                aspect_ratio=job.get("aspect_ratio") or "16:9",
                resolution=job.get("resolution") or "720p",
            )
        except Exception as exc:
            print(f"  failed: {exc}", file=sys.stderr)
            code = 1
    return code


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Grok timeline clip manager")
    sub = parser.add_subparsers(dest="cmd")

    sub.add_parser("load", help="print scan json")
    sub.add_parser("list-timelines", help="list timelines in the open Resolve project")
    p_scan = sub.add_parser("scan", help="scan via Python Resolve API (Studio) or artifacts")
    p_scan.add_argument("--artifacts-only", action="store_true")
    p_scan.add_argument("--timeline", type=int, default=None, help="timeline index (1-based)")
    p_scan.add_argument("--timeline-name", default=None, help="timeline name")
    p_update = sub.add_parser("update", help="update one clip sidecar")
    p_update.add_argument("--id", required=True)
    p_update.add_argument("--prompt", default="")
    p_update.add_argument("--slug", default="")
    p_update.add_argument("--lut", default="")
    p_update.add_argument("--continuity", default="")
    p_batch = sub.add_parser("batch-save", help="batch update from json file")
    p_batch.add_argument("file")
    p_prep = sub.add_parser("batch-prepare", help="write regenerate batch for clip ids")
    p_prep.add_argument("ids", nargs="+")
    sub.add_parser("batch-run", help="run batch regenerate jobs")

    args = parser.parse_args(argv)
    if args.cmd == "load":
        print(json.dumps(load_scan(), indent=2))
        return 0
    if args.cmd == "list-timelines":
        print(json.dumps(list_project_timelines(), indent=2))
        return 0
    if args.cmd == "scan":
        if args.artifacts_only:
            result = scan_artifacts_only()
        else:
            result = scan_resolve_timeline(
                timeline_index=args.timeline,
                timeline_name=args.timeline_name,
            )
            if not result.get("ok"):
                result = scan_artifacts_only()
                result["fallback"] = True
                result["note"] = result.get("error")
        print(json.dumps(result, indent=2))
        return 0 if result.get("ok") else 1
    if args.cmd == "update":
        result = update_clip_meta(
            args.id,
            {
                "prompt": args.prompt,
                "slug": args.slug,
                "lut": args.lut,
                "continuity": args.continuity,
            },
        )
        print(json.dumps(result, indent=2))
        return 0 if result.get("ok") else 1
    if args.cmd == "batch-save":
        updates = json.loads(Path(args.file).read_text(encoding="utf-8"))
        result = batch_update(updates)
        print(json.dumps(result, indent=2))
        return 0 if result.get("ok") else 1
    if args.cmd == "batch-prepare":
        result = prepare_batch_regenerate(args.ids)
        print(json.dumps(result, indent=2))
        return 0 if result.get("ok") else 1
    if args.cmd == "batch-run":
        return run_batch_regenerate()

    parser.print_help()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())