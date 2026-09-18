#!/usr/bin/env python3
"""LIVE Marks/SP job smoke vs glassline-api.

POST /jobs T1 → drop → UAV → end_turn (server bot) → attack bot hex
→ you.marks +10 once; replay GET must not double-pay (M4).

  GLASSLINE_API_BASE=https://glassline-api.vercel.app python3 tools/live_jobs_smoke.py

Does not push the API repo.
"""

from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.request

BASE = os.environ.get("GLASSLINE_API_BASE", "https://glassline-api.vercel.app").rstrip("/")
FAILS: list[str] = []

# Coder bot drop for T1 (src/bot.ts SP_BOT_HEX).
T1_BOT = {"q": 8, "r": 6}


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
    print(f"BASE {BASE}")
    code, health, _ = req("GET", "/health")
    expect(code == 200 and health.get("ok") is True, "GET /health")

    code, job, raw = req("POST", "/jobs", {"tier": 1})
    expect(code in (200, 201) and "matchId" in job and "joinToken" in job, "POST /jobs T1")
    if "matchId" not in job:
        print(raw)
        return 1
    match_id = job["matchId"]
    token = job["joinToken"]
    job_id = job.get("jobId", "")
    snap = job.get("snapshot") or {}
    expect(snap.get("kind") == "sp_job", "snapshot.kind sp_job")
    expect(isinstance(snap.get("job"), dict) and snap["job"].get("tier") == 1, "snapshot.job T1")
    expect("endReason" in snap, "snapshot.endReason present")
    start_marks = you_marks(snap)
    print(f"    jobId={job_id} matchId={match_id} you.marks={start_marks}")

    code, got, _ = req("GET", f"/jobs/{job_id}", token=token)
    expect(code == 200 and got.get("jobId") == job_id, "GET /jobs/:id")

    code, hb, _ = req("POST", f"/matches/{match_id}/heartbeat", {}, token=token)
    expect(code == 200 and (hb.get("ok") is True or "matchId" in (hb.get("snapshot") or hb)), "POST heartbeat")

    code, drop, _ = req("POST", f"/matches/{match_id}/actions", {"type": "select_hex", "hex": {"q": 1, "r": 1}}, token)
    expect(code == 200 and drop.get("ok") is True, "select_hex")
    snap = drop.get("snapshot") or {}
    expect(snap.get("status") == "active", "auto-active after player drop (bot already placed)")

    code, uav, _ = req("POST", f"/matches/{match_id}/actions", {"type": "uav"}, token)
    expect(code == 200 and uav.get("ok") is True, "uav")
    vis = ((uav.get("snapshot") or {}).get("enemy") or {}).get("visibleHex")
    expect(isinstance(vis, dict), "uav revealed bot hex")

    code, end, _ = req("POST", f"/matches/{match_id}/actions", {"type": "end_turn", "exposurePct": 50}, token)
    expect(code == 200 and end.get("ok") is True, "end_turn (server bot acts)")

    target = vis if isinstance(vis, dict) else T1_BOT
    code, atk, _ = req("POST", f"/matches/{match_id}/actions", {"type": "attack", "hex": target}, token)
    expect(code == 200 and atk.get("ok") is True, "attack revealed hex")
    snap = atk.get("snapshot") or {}
    expect(snap.get("status") == "ended", "job ended")
    expect(snap.get("endReason") == "kill", "endReason kill")
    expect(snap.get("kind") == "sp_job", "ended kind still sp_job")
    after = you_marks(snap)
    expect(after == start_marks + 10, f"you.marks +10 ({start_marks} → {after})")

    code, replay, _ = req("GET", f"/matches/{match_id}", token=token)
    expect(code == 200 and you_marks(replay) == after, "replay GET does not double-pay (M4)")
    code, replay_job, _ = req("GET", f"/jobs/{job_id}", token=token)
    replay_snap = replay_job.get("snapshot") or replay_job
    expect(you_marks(replay_snap) == after, "GET /jobs/:id replay same wallet")

    if FAILS:
        print("LIVE_JOBS_SMOKE_FAIL " + ", ".join(FAILS))
        return 1
    print(f"LIVE_JOBS_SMOKE_OK {job_id} marks {start_marks}->{after}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
