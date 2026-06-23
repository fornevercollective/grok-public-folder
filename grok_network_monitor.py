#!/usr/bin/env python3
"""Unix clock, epoch drift, and network speed test for Grok header monitor."""

from __future__ import annotations

import json
import os
import socket
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone

from grok_paths import ROOT
from grok_secrets import load_secrets
from grok_token_meter import meter_summary, reset_session

load_secrets()

DRIFT_URLS = (
    "https://worldtimeapi.org/api/timezone/Etc/UTC",
    "https://timeapi.io/api/Time/current/zone?timeZone=UTC",
)
LATENCY_URLS = (
    "https://api.x.ai/v1/models",
    "https://www.cloudflare.com/cdn-cgi/trace",
)
SPEED_URL = "https://speed.cloudflare.com/__down?bytes=262144"


def _now_unix() -> float:
    return time.time()


def unix_clock() -> dict:
    now = _now_unix()
    dt = datetime.fromtimestamp(now, tz=timezone.utc)
    return {
        "unix": now,
        "unix_int": int(now),
        "iso_utc": dt.strftime("%Y-%m-%d %H:%M:%S UTC"),
    }


def _fetch_remote_unix() -> tuple[float | None, str, str]:
    errors: list[str] = []
    for url in DRIFT_URLS:
        try:
            request = urllib.request.Request(url, headers={"User-Agent": "grok-public-folder/1.0"})
            started = time.perf_counter()
            with urllib.request.urlopen(request, timeout=8) as response:
                payload = json.loads(response.read().decode("utf-8"))
            rtt_ms = round((time.perf_counter() - started) * 1000, 1)
            if "unixtime" in payload:
                return float(payload["unixtime"]), url, f"rtt {rtt_ms}ms"
            if "epoch" in payload:
                return float(payload["epoch"]), url, f"rtt {rtt_ms}ms"
            if "dateTime" in payload:
                parsed = datetime.fromisoformat(str(payload["dateTime"]).replace("Z", "+00:00"))
                return parsed.timestamp(), url, f"rtt {rtt_ms}ms"
        except (urllib.error.URLError, json.JSONDecodeError, ValueError, TimeoutError) as exc:
            errors.append(f"{url}: {exc}")
    return None, "", "; ".join(errors[:2])


def epoch_drift() -> dict:
    local_before = _now_unix()
    remote, source, detail = _fetch_remote_unix()
    local_after = _now_unix()
    local = (local_before + local_after) / 2
    if remote is None:
        return {
            "ok": False,
            "drift_ms": None,
            "drift_label": "n/a",
            "remote_unix": None,
            "local_unix": local,
            "source": "",
            "error": detail or "drift probe failed",
        }
    rtt_ms = 0.0
    if "rtt " in detail:
        try:
            rtt_ms = float(detail.split("rtt ", 1)[1].replace("ms", ""))
        except ValueError:
            rtt_ms = 0.0
    remote_adjusted = remote + (rtt_ms / 2000.0)
    drift_ms = round((local - remote_adjusted) * 1000, 1)
    label = f"{drift_ms:+.0f}ms" if abs(drift_ms) < 1000 else f"{(local - remote):+.2f}s"
    status = "ok" if abs(drift_ms) < 500 else "warn" if abs(drift_ms) < 5000 else "bad"
    return {
        "ok": True,
        "drift_ms": drift_ms,
        "drift_label": label,
        "remote_unix": remote,
        "local_unix": local,
        "source": source,
        "detail": detail,
        "status": status,
    }


def _latency_probe() -> dict:
    api_key = os.environ.get("XAI_API_KEY", "").strip()
    best_ms: float | None = None
    host = ""
    for url in LATENCY_URLS:
        started = time.perf_counter()
        try:
            headers = {"User-Agent": "grok-public-folder/1.0"}
            if "api.x.ai" in url and api_key:
                headers["Authorization"] = f"Bearer {api_key}"
            request = urllib.request.Request(url, method="HEAD", headers=headers)
            with urllib.request.urlopen(request, timeout=8) as response:
                response.read(0)
            elapsed = round((time.perf_counter() - started) * 1000, 1)
            if best_ms is None or elapsed < best_ms:
                best_ms = elapsed
                host = urllib.parse.urlparse(url).netloc
        except urllib.error.HTTPError as exc:
            if exc.code in {401, 403, 405}:
                elapsed = round((time.perf_counter() - started) * 1000, 1)
                if best_ms is None or elapsed < best_ms:
                    best_ms = elapsed
                    host = urllib.parse.urlparse(url).netloc
        except (urllib.error.URLError, TimeoutError):
            continue
    if best_ms is None:
        try:
            started = time.perf_counter()
            socket.getaddrinfo("api.x.ai", 443, type=socket.SOCK_STREAM)
            best_ms = round((time.perf_counter() - started) * 1000, 1)
            host = "api.x.ai (dns)"
        except OSError:
            return {"ok": False, "latency_ms": None, "host": "", "status": "offline"}
    status = "ok" if best_ms < 120 else "slow" if best_ms < 400 else "bad"
    return {"ok": True, "latency_ms": best_ms, "host": host, "status": status}


def speed_test() -> dict:
    latency = _latency_probe()
    download_mbps: float | None = None
    bytes_read = 0
    try:
        request = urllib.request.Request(SPEED_URL, headers={"User-Agent": "grok-public-folder/1.0"})
        started = time.perf_counter()
        with urllib.request.urlopen(request, timeout=15) as response:
            chunk = response.read()
            bytes_read = len(chunk)
        elapsed = max(time.perf_counter() - started, 0.001)
        download_mbps = round((bytes_read * 8) / elapsed / 1_000_000, 1)
    except (urllib.error.URLError, TimeoutError):
        download_mbps = None

    if not latency.get("ok"):
        net_status = "offline"
    elif download_mbps is None:
        net_status = latency.get("status", "slow")
    elif download_mbps >= 20:
        net_status = "ok"
    elif download_mbps >= 5:
        net_status = "slow"
    else:
        net_status = "bad"

    return {
        "ok": latency.get("ok", False),
        "latency_ms": latency.get("latency_ms"),
        "latency_host": latency.get("host", ""),
        "latency_status": latency.get("status", "offline"),
        "download_mbps": download_mbps,
        "bytes": bytes_read,
        "status": net_status,
    }


def monitor_status(*, full: bool = True) -> dict:
    clock = unix_clock()
    payload: dict = {
        "ok": True,
        "root": str(ROOT),
        "clock": clock,
        "tokens": meter_summary(),
    }
    if full:
        payload["drift"] = epoch_drift()
        payload["network"] = speed_test()
    return payload


def main(argv: list[str] | None = None) -> int:
    args = argv if argv is not None else sys.argv[1:]
    if not args or args[0] in {"-h", "--help"}:
        print("usage: grok_network_monitor.py <status|clock|drift|speed|tokens|reset-session> [--quick]")
        return 0

    cmd = args[0]
    quick = "--quick" in args
    try:
        if cmd == "status":
            print(json.dumps(monitor_status(full=not quick), indent=2))
            return 0
        if cmd == "clock":
            print(json.dumps(unix_clock(), indent=2))
            return 0
        if cmd == "drift":
            print(json.dumps(epoch_drift(), indent=2))
            return 0
        if cmd == "speed":
            print(json.dumps(speed_test(), indent=2))
            return 0
        if cmd == "tokens":
            print(json.dumps(meter_summary(), indent=2))
            return 0
        if cmd == "reset-session":
            print(json.dumps(reset_session(), indent=2))
            return 0
    except Exception as exc:
        print(json.dumps({"ok": False, "error": str(exc)}))
        return 1

    print(json.dumps({"ok": False, "error": f"unknown command: {cmd}"}))
    return 1


if __name__ == "__main__":
    raise SystemExit(main())