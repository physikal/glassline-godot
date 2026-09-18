#!/usr/bin/env python3
"""LIVE soft-A4 forfeit: POST /jobs T1, drop, stay silent 30s.

Expect endReason=forfeit and you.marks unchanged (disconnect loss +0).
Does not heartbeat after drop.

  GLASSLINE_API_BASE=https://glassline-api.vercel.app python3 tools/live_a4_smoke.py
"""

from __future__ import annotations

import json
import os
import sys
import time
import urllib.error
import urllib.request

BASE = os.environ.get("GLASSLINE_API_BASE", "https://glassline-api.vercel.app").rstrip("/")
GRACE = float(os.environ.get("GLASSLINE_FORFEIT_GRACE", "32"))
FAILS: list[str] = []


def req(method: str, path: str, body=None, token: str | None = None, timeout: float = 30.0):
    data = None
    headers = {"Accept": "application/json"}
    if body is not None:
        data = json.dumps(body).encode()
        headers["Content-Type"] = "application/json"
    if token:
        headers["Authorization"] = f"Bearer {token}"
    request = urllib.request.Request(BASE + path, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(request, timeout=timeout) as resp:
            raw = resp.read().decode()
            parsed = json.loads(raw) if raw else {}
            return resp.status, parsed, raw
    except urllib.error.HTTPError as err:
        raw = err.read().decode()
        try:
            parsed = json.loads(raw) if raw else {}
        except json.JSONDecodeError:
            parsed = {"error": raw}
        return err.code, parsed, raw


def expect(cond: bool, label: str) -> None:
    if cond:
        print(f"PASS  {label}")
        return
    FAILS.append(label)
    print(f"FAIL  {label}")


def you_marks(snap: dict) -> int:
    you = snap.get("you") or {}
    return int(you.get("marks") or 0)


def main() -> int:
    print(f"BASE {BASE} grace={GRACE}s")
    code, job, raw = req("POST", "/jobs", {"tier": 1})
    expect(code in (200, 201) and "matchId" in job, "POST /jobs T1")
    if "matchId" not in job:
        print(raw)
        return 1
    match_id = job["matchId"]
    token = job["joinToken"]
    job_id = job.get("jobId", "")
    start = you_marks(job.get("snapshot") or {})
    print(f"    jobId={job_id} matchId={match_id} you.marks={start}")

    code, drop, _ = req(
        "POST",
        f"/matches/{match_id}/actions",
        {"type": "select_hex", "hex": {"q": 1, "r": 1}},
        token,
    )
    expect(code == 200 and drop.get("ok") is True, "select_hex")
    snap = drop.get("snapshot") or {}
    expect(snap.get("status") == "active", "active after drop")

    print(f"    silent {GRACE:.0f}s (no heartbeat)…")
    time.sleep(GRACE)

    code, replay, _ = req("GET", f"/matches/{match_id}", token=token)
    expect(code == 200, "GET /matches/:id after grace")
    expect(replay.get("status") == "ended", f"status ended ({replay.get('status')})")
    expect(replay.get("endReason") == "forfeit", f"endReason forfeit ({replay.get('endReason')})")
    after = you_marks(replay)
    expect(after == start, f"forfeit loss you.marks unchanged ({start} → {after})")

    if FAILS:
        print("LIVE_A4_SMOKE_FAIL " + ", ".join(FAILS))
        return 1
    print(f"LIVE_A4_SMOKE_OK {job_id} endReason=forfeit marks {start}->{after}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
