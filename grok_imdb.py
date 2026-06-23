#!/usr/bin/env python3
"""Movie knowledge for Grok Resolve — TMDB + optional xAI feel/trivia."""

from __future__ import annotations

import json
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

from grok_paths import IMDB_DIR, PROJECT_DIR, ROOT
from grok_secrets import load_secrets

load_secrets()

TMDB_BASE = "https://api.themoviedb.org/3"
TMDB_IMAGE = "https://image.tmdb.org/t/p/w500"
CACHE_DIR = IMDB_DIR / "cache"
POSTER_DIR = IMDB_DIR / "posters"
LUT_DIR = IMDB_DIR / "luts"
GENERATE_UI = PROJECT_DIR / "generate-ui.json"

GENRE_LUT_SLUGS: dict[str, str] = {
    "science fiction": "cyberpunk-neon",
    "horror": "horror-grain",
    "crime": "film-noir",
    "thriller": "film-noir",
    "mystery": "film-noir",
    "romance": "kodak-portra-400",
    "war": "bleach-bypass-lut",
    "fantasy": "fuji-velvia-50",
    "comedy": "kodak-gold-200",
    "drama": "kodak-portra-400",
    "action": "teal-orange-blockbuster",
    "adventure": "fuji-eterna-250d",
    "western": "kodak-gold-200",
    "documentary": "kodak-tri-x-400-bw",
    "animation": "fuji-velvia-50",
}

FEEL_GENRES = {
    "noir": [80, 53],
    "neo-noir": [80, 53, 9648],
    "horror": [27, 53],
    "sci-fi": [878, 12],
    "science fiction": [878],
    "fantasy": [14, 12],
    "romance": [10749, 18],
    "comedy": [35],
    "drama": [18],
    "action": [28, 12],
    "thriller": [53, 80],
    "mystery": [9648, 53],
    "western": [37],
    "war": [10752, 36],
    "documentary": [99],
    "animated": [16],
    "musical": [10402],
    "crime": [80, 53],
    "rain": [18, 53],
    "neon": [878, 80],
    "moody": [18, 53],
    "cinematic": [18, 36],
}


def _api_key() -> str:
    load_secrets()
    return os.environ.get("TMDB_API_KEY", "").strip()


def _xai_key() -> str:
    return os.environ.get("XAI_API_KEY", "").strip()


def _ensure_dirs() -> None:
    IMDB_DIR.mkdir(parents=True, exist_ok=True)
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    POSTER_DIR.mkdir(parents=True, exist_ok=True)
    LUT_DIR.mkdir(parents=True, exist_ok=True)


def _load_lut_catalog() -> list[dict]:
    if not GENERATE_UI.exists():
        return []
    try:
        data = json.loads(GENERATE_UI.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return []
    return data.get("lut_presets") or []


def _slugify_title(title: str) -> str:
    slug = re.sub(r"[^a-z0-9]+", "-", title.lower()).strip("-")
    return slug[:40] or "film"


def _heuristic_lut_prompt(detail: dict) -> str:
    title = detail.get("title") or "this film"
    year = detail.get("year") or ""
    genres = [g.lower() for g in (detail.get("genres") or [])]
    keywords = [k.lower() for k in (detail.get("keywords") or [])]
    haystack = " ".join(genres + keywords)
    if any(token in haystack for token in ("noir", "crime", "detective", "rain")):
        return (
            f"neo-noir color grade inspired by {title} ({year}): crushed blacks, "
            "sodium-vapor amber highlights, cool blue shadows, high contrast, wet reflective surfaces"
        )
    if any(token in haystack for token in ("sci-fi", "science fiction", "cyber", "neon", "future")):
        return (
            f"sci-fi neon grade inspired by {title} ({year}): teal shadows, magenta and cyan accents, "
            "high contrast, bloom on practical lights, night-city atmosphere"
        )
    if "horror" in haystack or "ghost" in haystack or "haunted" in haystack:
        return (
            f"horror grade inspired by {title} ({year}): desaturated greens, deep crushed blacks, "
            "cool sickly highlights, heavy grain, low-key lighting"
        )
    if "war" in haystack or "battle" in haystack:
        return (
            f"bleach-bypass war grade inspired by {title} ({year}): desaturated palette, silvery highlights, "
            "crushed blacks, high contrast, gritty grain"
        )
    if "romance" in haystack or "love" in haystack:
        return (
            f"warm romantic grade inspired by {title} ({year}): soft contrast, creamy highlights, "
            "golden skin tones, gentle saturation, subtle film grain"
        )
    return (
        f"cinematic color grade inspired by {title} ({year}): balanced contrast, natural skin tones, "
        "theatrical lighting, subtle film grain, cohesive shadow and highlight color"
    )


def _heuristic_lut_slug(detail: dict) -> str:
    genres = [g.lower() for g in (detail.get("genres") or [])]
    keywords = [k.lower() for k in (detail.get("keywords") or [])]
    haystack = " ".join(genres + keywords)
    for genre, slug in GENRE_LUT_SLUGS.items():
        if genre in haystack:
            return slug
    for genre in genres:
        if genre in GENRE_LUT_SLUGS:
            return GENRE_LUT_SLUGS[genre]
    return ""


def _score_lut_preset(preset: dict, detail: dict, lut_prompt: str) -> int:
    text = " ".join(
        [
            lut_prompt,
            " ".join(detail.get("genres") or []),
            " ".join(detail.get("keywords") or []),
            preset.get("slug", ""),
            preset.get("display", ""),
            preset.get("best_for", ""),
            preset.get("notes", ""),
            preset.get("prompt_preview", ""),
            " ".join(preset.get("tags") or []),
        ]
    ).lower()
    score = 0
    for tag in preset.get("tags") or []:
        token = str(tag).lower()
        if token and token in text:
            score += 3
    slug = str(preset.get("slug", "")).replace("-", " ")
    if slug and slug in text:
        score += 4
    for genre in detail.get("genres") or []:
        if genre.lower() in text:
            score += 1
    return score


def _best_lut_slug(catalog: list[dict], detail: dict, lut_prompt: str, fallback: str = "") -> str:
    if not catalog:
        return fallback
    ranked = sorted(
        ((preset.get("slug") or "", _score_lut_preset(preset, detail, lut_prompt)) for preset in catalog),
        key=lambda item: item[1],
        reverse=True,
    )
    if ranked and ranked[0][1] > 0:
        return ranked[0][0]
    return fallback


def _lut_prompt_with_xai(detail: dict) -> tuple[str, str, str]:
    catalog = _load_lut_catalog()
    slug_choices = ", ".join(p["slug"] for p in catalog[:36])
    raw = _xai_chat(
        f"Film: {detail.get('title')} ({detail.get('year')})\n"
        f"Genres: {', '.join(detail.get('genres') or [])}\n"
        f"Keywords: {', '.join(detail.get('keywords') or [])}\n"
        f"Plot: {(detail.get('plot') or '')[:500]}\n"
        f"Directors: {', '.join(detail.get('directors') or [])}\n"
        "Describe the signature color grade / LUT for AI video generation. "
        "Cover shadows, midtones, highlights, contrast, grain, and mood in 2-4 sentences.",
        "You are a senior colorist writing LUT briefs for generative video.",
    )
    lut_prompt = raw.strip() or _heuristic_lut_prompt(detail)
    match_raw = _xai_chat(
        f"LUT brief:\n{lut_prompt}\n\n"
        f"Available preset slugs:\n{slug_choices}\n\n"
        'Reply with ONLY JSON: {"best_slug": "slug-or-empty-string", "display_name": "short LUT name"}',
        "Pick the closest Imagine preset slug from the list, or empty string if none fit.",
    )
    best_slug = ""
    display = f"{detail.get('title')} LUT"
    try:
        start = match_raw.find("{")
        end = match_raw.rfind("}") + 1
        if start >= 0 and end > start:
            data = json.loads(match_raw[start:end])
            best_slug = str(data.get("best_slug") or "").strip()
            if data.get("display_name"):
                display = str(data["display_name"]).strip()
    except json.JSONDecodeError:
        pass
    if best_slug and not any(p.get("slug") == best_slug for p in catalog):
        best_slug = ""
    if not best_slug:
        best_slug = _best_lut_slug(catalog, detail, lut_prompt, _heuristic_lut_slug(detail))
    return lut_prompt, best_slug, display


def generate_lut(tmdb_id: int) -> dict:
    if not _api_key():
        raise RuntimeError("TMDB_API_KEY is not set — get a free key at https://www.themoviedb.org/settings/api")
    _ensure_dirs()
    detail = movie_detail(tmdb_id, download_poster=True)
    catalog = _load_lut_catalog()
    display = f"{detail.get('title')} LUT"

    if _xai_key():
        lut_prompt, best_slug, display = _lut_prompt_with_xai(detail)
    else:
        lut_prompt = _heuristic_lut_prompt(detail)
        best_slug = _best_lut_slug(catalog, detail, lut_prompt, _heuristic_lut_slug(detail))

    slug_part = _slugify_title(detail.get("title") or "film")
    saved = LUT_DIR / f"{tmdb_id}-{slug_part}.txt"
    saved.write_text(lut_prompt, encoding="utf-8")

    prompt_add = f"cinematic color grade inspired by {detail.get('title')} ({detail.get('year')}): {lut_prompt}"
    return {
        "ok": True,
        "id": tmdb_id,
        "title": detail.get("title") or "",
        "year": detail.get("year") or "",
        "lut_slug": best_slug,
        "lut_display": display,
        "lut_prompt": lut_prompt,
        "prompt_add": prompt_add,
        "saved_path": str(saved),
        "poster_local": detail.get("poster_local") or "",
        "xai_used": bool(_xai_key()),
    }


def _tmdb_get(path: str, params: dict | None = None) -> dict:
    key = _api_key()
    if not key:
        raise RuntimeError("TMDB_API_KEY is not set — get a free key at https://www.themoviedb.org/settings/api")
    query = {"api_key": key, "language": "en-US"}
    if params:
        query.update(params)
    url = f"{TMDB_BASE}{path}?{urllib.parse.urlencode(query)}"
    request = urllib.request.Request(url)
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"TMDB error {exc.code}: {body}") from exc


def _xai_chat(prompt: str, system: str) -> str:
    from grok_api import api_request

    key = _xai_key()
    if not key:
        return ""
    payload = {
        "model": os.environ.get("GROK_CHAT_MODEL", "grok-4.3"),
        "messages": [
            {"role": "system", "content": system},
            {"role": "user", "content": prompt},
        ],
        "temperature": 0.4,
    }
    result = api_request("POST", "/chat/completions", key, payload, timeout=60)
    try:
        from grok_token_meter import record_from_api_response

        record_from_api_response("imdb", result, fallback_prompt=prompt)
    except Exception:
        pass
    choices = result.get("choices") or []
    if not choices:
        return ""
    return (choices[0].get("message") or {}).get("content", "").strip()


def _feel_genre_ids(feel: str) -> list[int]:
    text = feel.lower()
    ids: list[int] = []
    for token, genres in FEEL_GENRES.items():
        if token in text:
            ids.extend(genres)
    if not ids:
        ids = [18, 53]
    seen: set[int] = set()
    out: list[int] = []
    for gid in ids:
        if gid not in seen:
            seen.add(gid)
            out.append(gid)
    return out[:4]


def _feel_search_terms(feel: str) -> list[str]:
    xai = _xai_key()
    if xai:
        raw = _xai_chat(
            f"Film mood request: {feel}\n"
            "Reply with ONLY JSON: {\"search_terms\": [\"term1\", \"term2\"], \"genre_ids\": [18, 53]}",
            "You map creative film moods to TMDB search terms and genre ids. JSON only.",
        )
        try:
            start = raw.find("{")
            end = raw.rfind("}") + 1
            if start >= 0 and end > start:
                data = json.loads(raw[start:end])
                terms = [str(t) for t in data.get("search_terms", []) if t]
                if terms:
                    return terms[:5]
        except json.JSONDecodeError:
            pass
    words = [w for w in re.split(r"[^a-z0-9]+", feel.lower()) if len(w) > 2]
    return words[:5] or [feel.strip()]


def search_movies(query: str, limit: int = 12) -> list[dict]:
    data = _tmdb_get("/search/movie", {"query": query, "include_adult": "false"})
    results = []
    for item in (data.get("results") or [])[:limit]:
        results.append(_summary_from_search(item))
    return results


def feel_movies(feel: str, limit: int = 12) -> list[dict]:
    terms = _feel_search_terms(feel)
    genre_ids = _feel_genre_ids(feel)
    merged: dict[int, dict] = {}
    for term in terms:
        for hit in search_movies(term, limit=8):
            merged[hit["id"]] = hit
    if genre_ids:
        discover = _tmdb_get(
            "/discover/movie",
            {
                "with_genres": ",".join(str(g) for g in genre_ids),
                "sort_by": "popularity.desc",
                "page": "1",
            },
        )
        for item in (discover.get("results") or [])[:8]:
            merged[item["id"]] = _summary_from_search(item)
    return list(merged.values())[:limit]


def _summary_from_search(item: dict) -> dict:
    year = (item.get("release_date") or "")[:4]
    poster = item.get("poster_path") or ""
    return {
        "id": item.get("id"),
        "title": item.get("title") or item.get("name") or "",
        "year": year,
        "overview": (item.get("overview") or "")[:220],
        "vote_average": item.get("vote_average"),
        "poster_url": f"{TMDB_IMAGE}{poster}" if poster else "",
        "imdb_id": None,
    }


def _download_poster(tmdb_id: int, poster_path: str | None) -> str:
    if not poster_path:
        return ""
    dest = POSTER_DIR / f"{tmdb_id}.jpg"
    if dest.exists():
        return str(dest)
    url = f"{TMDB_IMAGE}{poster_path}"
    try:
        with urllib.request.urlopen(url, timeout=30) as response:
            dest.write_bytes(response.read())
        return str(dest)
    except (urllib.error.URLError, TimeoutError):
        return ""


def _trivia_for(title: str, year: str, plot: str) -> list[str]:
    if not _xai_key():
        return [
            f"Set XAI_API_KEY for AI-generated trivia, or open IMDb for {title}.",
        ]
    raw = _xai_chat(
        f"Film: {title} ({year})\nPlot: {plot[:600]}\n"
        "List 4 interesting production or cultural trivia bullets. One per line, no numbering.",
        "You are a film historian. Brief factual trivia only.",
    )
    lines = [ln.strip("-• ").strip() for ln in raw.splitlines() if ln.strip()]
    return lines[:5] if lines else []


def _prompt_snippet(detail: dict) -> str:
    title = detail.get("title", "")
    year = detail.get("year", "")
    genres = ", ".join(detail.get("genres") or [])
    plot = (detail.get("plot") or "")[:280]
    similar = ", ".join(m["title"] for m in (detail.get("similar") or [])[:4])
    tagline = detail.get("tagline") or ""
    parts = [f"cinematic look inspired by {title} ({year})"]
    if genres:
        parts.append(f"genres: {genres}")
    if tagline:
        parts.append(f"tagline mood: {tagline}")
    if plot:
        parts.append(f"plot tone: {plot}")
    if similar:
        parts.append(f"like-minded references: {similar}")
    return ", ".join(parts)


def movie_detail(tmdb_id: int, download_poster: bool = True) -> dict:
    _ensure_dirs()
    cache_path = CACHE_DIR / f"{tmdb_id}.json"
    data = _tmdb_get(
        f"/movie/{tmdb_id}",
        {"append_to_response": "credits,videos,similar,keywords,external_ids"},
    )
    credits = data.get("credits") or {}
    cast = [
        f"{c.get('name')} as {c.get('character')}"
        for c in (credits.get("cast") or [])[:8]
    ]
    crew = credits.get("crew") or []
    directors = [c["name"] for c in crew if c.get("job") == "Director"]
    writers = [c["name"] for c in crew if c.get("job") in {"Writer", "Screenplay", "Story"}][:4]
    videos = data.get("videos", {}).get("results") or []
    trailer = next((v for v in videos if v.get("type") == "Trailer" and v.get("site") == "YouTube"), None)
    trailer_key = trailer.get("key") if trailer else ""
    similar_raw = data.get("similar", {}).get("results") or []
    similar = [
        {
            "id": s.get("id"),
            "title": s.get("title"),
            "year": (s.get("release_date") or "")[:4],
            "poster_url": f"{TMDB_IMAGE}{s['poster_path']}" if s.get("poster_path") else "",
        }
        for s in similar_raw[:10]
    ]
    external = data.get("external_ids") or {}
    imdb_id = external.get("imdb_id") or ""
    poster_local = _download_poster(tmdb_id, data.get("poster_path")) if download_poster else ""
    detail = {
        "id": tmdb_id,
        "title": data.get("title") or "",
        "year": (data.get("release_date") or "")[:4],
        "imdb_id": imdb_id,
        "imdb_url": f"https://www.imdb.com/title/{imdb_id}/" if imdb_id else "",
        "plot": data.get("overview") or "",
        "tagline": data.get("tagline") or "",
        "genres": [g.get("name") for g in data.get("genres") or []],
        "runtime": data.get("runtime"),
        "directors": directors,
        "writers": writers,
        "cast": cast,
        "trivia": _trivia_for(data.get("title") or "", (data.get("release_date") or "")[:4], data.get("overview") or ""),
        "trailer_youtube_key": trailer_key,
        "trailer_url": f"https://www.youtube.com/watch?v={trailer_key}" if trailer_key else "",
        "poster_url": f"{TMDB_IMAGE}{data['poster_path']}" if data.get("poster_path") else "",
        "poster_local": poster_local,
        "similar": similar,
        "keywords": [k.get("name") for k in (data.get("keywords") or {}).get("keywords") or []][:12],
    }
    detail["prompt_snippet"] = _prompt_snippet(detail)
    cache_path.write_text(json.dumps(detail, indent=2), encoding="utf-8")
    return detail


def add_similar_to_prompt(tmdb_id: int) -> str:
    detail = movie_detail(tmdb_id, download_poster=False)
    names = [f"{s['title']} ({s['year']})" for s in detail.get("similar") or [] if s.get("title")]
    base = detail.get("title") or "this film"
    return f"like-minded films to {base}: " + ", ".join(names[:8])


def main(argv: list[str] | None = None) -> int:
    args = argv if argv is not None else sys.argv[1:]
    if not args or args[0] in {"-h", "--help"}:
        print("usage: grok_imdb.py <search|feel|detail|similar-prompt|generate-lut|status> [args]")
        print("env: TMDB_API_KEY (required), XAI_API_KEY (feel + trivia + generate-lut)")
        return 0

    cmd = args[0]
    try:
        if cmd == "status":
            print(
                json.dumps(
                    {
                        "ok": True,
                        "root": str(ROOT),
                        "imdb_dir": str(IMDB_DIR),
                        "tmdb_configured": bool(_api_key()),
                        "xai_configured": bool(_xai_key()),
                        "secrets_file": str(PROJECT_DIR / "grok-secrets.env"),
                        "secrets_exists": (PROJECT_DIR / "grok-secrets.env").exists(),
                        "setup_hint": "cp project/grok-secrets.example.env project/grok-secrets.env",
                    },
                    indent=2,
                )
            )
            return 0
        if cmd == "search":
            query = " ".join(args[1:])
            if not query:
                raise RuntimeError("search requires a title")
            print(json.dumps({"ok": True, "results": search_movies(query)}, indent=2))
            return 0
        if cmd == "feel":
            feel = " ".join(args[1:])
            if not feel:
                raise RuntimeError("feel requires a mood description")
            print(json.dumps({"ok": True, "results": feel_movies(feel)}, indent=2))
            return 0
        if cmd == "detail":
            tmdb_id = int(args[1])
            payload = movie_detail(tmdb_id)
            payload["ok"] = True
            print(json.dumps(payload, indent=2))
            return 0
        if cmd == "similar-prompt":
            tmdb_id = int(args[1])
            print(add_similar_to_prompt(tmdb_id))
            return 0
        if cmd == "generate-lut":
            tmdb_id = int(args[1])
            print(json.dumps(generate_lut(tmdb_id), indent=2))
            return 0
        if cmd == "open-setup":
            example = PROJECT_DIR / "grok-secrets.example.env"
            target = PROJECT_DIR / "grok-secrets.env"
            if not target.exists() and example.exists():
                target.write_text(example.read_text(encoding="utf-8"), encoding="utf-8")
            subprocess = __import__("subprocess")
            subprocess.run(["open", str(PROJECT_DIR)], check=False)
            print(json.dumps({"ok": True, "message": f"opened {PROJECT_DIR}"}))
            return 0
    except (RuntimeError, ValueError, IndexError) as exc:
        print(json.dumps({"ok": False, "error": str(exc), "results": []}))
        return 1

    print(json.dumps({"ok": False, "error": f"unknown command: {cmd}", "results": []}))
    return 1


if __name__ == "__main__":
    raise SystemExit(main())