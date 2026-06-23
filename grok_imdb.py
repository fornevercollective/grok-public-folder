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

from grok_paths import IMDB_DIR, ROOT

TMDB_BASE = "https://api.themoviedb.org/3"
TMDB_IMAGE = "https://image.tmdb.org/t/p/w500"
CACHE_DIR = IMDB_DIR / "cache"
POSTER_DIR = IMDB_DIR / "posters"

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
    return os.environ.get("TMDB_API_KEY", "").strip()


def _xai_key() -> str:
    return os.environ.get("XAI_API_KEY", "").strip()


def _ensure_dirs() -> None:
    IMDB_DIR.mkdir(parents=True, exist_ok=True)
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    POSTER_DIR.mkdir(parents=True, exist_ok=True)


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
        print("usage: grok_imdb.py <search|feel|detail|similar-prompt|status> [args]")
        print("env: TMDB_API_KEY (required), XAI_API_KEY (feel + trivia)")
        return 0

    cmd = args[0]
    try:
        if cmd == "status":
            print(
                json.dumps(
                    {
                        "root": str(ROOT),
                        "imdb_dir": str(IMDB_DIR),
                        "tmdb_configured": bool(_api_key()),
                        "xai_configured": bool(_xai_key()),
                    },
                    indent=2,
                )
            )
            return 0
        if cmd == "search":
            query = " ".join(args[1:])
            if not query:
                raise RuntimeError("search requires a title")
            print(json.dumps({"results": search_movies(query)}, indent=2))
            return 0
        if cmd == "feel":
            feel = " ".join(args[1:])
            if not feel:
                raise RuntimeError("feel requires a mood description")
            print(json.dumps({"results": feel_movies(feel)}, indent=2))
            return 0
        if cmd == "detail":
            tmdb_id = int(args[1])
            print(json.dumps(movie_detail(tmdb_id), indent=2))
            return 0
        if cmd == "similar-prompt":
            tmdb_id = int(args[1])
            print(add_similar_to_prompt(tmdb_id))
            return 0
    except (RuntimeError, ValueError, IndexError) as exc:
        print(json.dumps({"ok": False, "error": str(exc)}), file=sys.stderr)
        return 1

    print(json.dumps({"ok": False, "error": f"unknown command: {cmd}"}), file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())