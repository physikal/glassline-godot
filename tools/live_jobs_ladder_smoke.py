#!/usr/bin/env python3
"""LIVE J1–J4 SP job ladder vs glassline-api.

Durable POST /players Bearer. POST /jobs { tier, clientJobId }.
Credit is match/job end (T1 ★10 / T2 ★15 / T3 ★20). Snapshot you.marks only.

  GLASSLINE_API_BASE=https://glassline-api.vercel.app python3 tools/live_jobs_ladder_smoke.py

Does not push the API repo.
"""

from __future__ import annotations

import json
import os
import sys
import uuid
import urllib.error
import urllib.request

BASE = os.environ.get("GLASSLINE_API_BASE", "https://glassline-api.vercel.app").rstrip("/")
FAILS: list[str] = []
EVIDENCE: list[str] = []

# LIVE src/bot.ts SP_BOT_HEX
BOT = {1: {"q": 8, "r": 6}, 2: {"q": 7, "r": 5}, 3: {"q": 8, "r": 5}}
PAY = {1: 10, 2: 15, 3: 20}
NAME = {1: "Rooftop Rookie", 2: "Warehouse Watch", 3: "Night Contract"}


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


def expect(cond: bool, label: str, detail: str = "") -> bool:
    if cond:
        print(f"PASS  {label}")
        return True
    FAILS.append(label)
    extra = f"  {detail}" if detail else ""
    print(f"FAIL  {label}{extra}")
    return False


def evid(msg: str) -> None:
    EVIDENCE.append(msg)
    print(f"EVID  {msg}")


def you_marks(bag: dict | None) -> int:
    if not isinstance(bag, dict):
        return 0
    you = bag.get("you") if isinstance(bag.get("you"), dict) else {}
    if "marks" in you:
        return int(you.get("marks") or 0)
    snap = bag.get("snapshot") if isinstance(bag.get("snapshot"), dict) else {}
    you2 = snap.get("you") if isinstance(snap.get("you"), dict) else {}
    if "marks" in you2:
        return int(you2.get("marks") or 0)
    return int(bag.get("marks") or 0)


def complete_job(player_token: str, tier: int, client_job_id: str) -> dict:
    code, job, raw = req(
        "POST",
        "/jobs",
        {"tier": tier, "clientJobId": client_job_id},
        player_token,
    )
    expect(
        code in (200, 201) and "matchId" in job and "joinToken" in job,
        f"POST /jobs T{tier}",
        raw[:240],
    )
    if "matchId" not in job:
        return {"ok": False, "error": raw, "tier": tier}
    expect(int(job.get("tier", 0)) == tier, f"create T{tier} tier field")
    expect(str(job.get("name", "")) == NAME[tier], f"create T{tier} name {NAME[tier]}")
    snap = job.get("snapshot") or {}
    expect(snap.get("kind") == "sp_job", f"T{tier} snapshot.kind sp_job")
    job_field = snap.get("job") if isinstance(snap.get("job"), dict) else {}
    expect(int(job_field.get("tier", 0)) == tier, f"T{tier} snapshot.job.tier")
    match_id = job["matchId"]
    token = job["joinToken"]
    start = you_marks(snap)
    code, drop, _ = req(
        "POST",
        f"/matches/{match_id}/actions",
        {"type": "select_hex", "hex": {"q": 1, "r": 1}},
        token,
    )
    expect(code == 200 and drop.get("ok") is True, f"T{tier} select_hex")
    snap = drop.get("snapshot") or {}
    expect(snap.get("status") == "active", f"T{tier} auto-active after drop")
    code, atk, raw_atk = req(
        "POST",
        f"/matches/{match_id}/actions",
        {"type": "attack", "hex": BOT[tier]},
        token,
    )
    expect(code == 200 and atk.get("ok") is True, f"T{tier} attack bot hex", raw_atk[:240])
    snap = atk.get("snapshot") or {}
    expect(snap.get("status") == "ended", f"T{tier} job ended")
    expect(snap.get("endReason") == "kill", f"T{tier} endReason kill")
    after = you_marks(snap)
    return {
        "ok": True,
        "tier": tier,
        "jobId": job.get("jobId", ""),
        "matchId": match_id,
        "joinToken": token,
        "clientJobId": client_job_id,
        "start": start,
        "after": after,
        "snapshot": snap,
    }


def main() -> int:
    print(f"BASE {BASE}")
    code, health, _ = req("GET", "/health")
    expect(code == 200 and health.get("ok") is True, "GET /health")

    code, player, raw = req("POST", "/players", {})
    expect(code in (200, 201) and player.get("token"), "POST /players durable Bearer", raw[:240])
    token = str(player.get("token", ""))
    pid = str(player.get("playerId", ""))
    expect(int(player.get("marks") or 0) == 0, "fresh player marks 0")
    evid(f"playerId={pid}")

    wallet = 0
    last = {}
    for gate, tier in (("J1", 1), ("J2", 2), ("J3", 3)):
        cid = str(uuid.uuid4())
        result = complete_job(token, tier, cid)
        last = result
        after = int(result.get("after") or 0)
        expect(after == wallet + PAY[tier], f"{gate} T{tier} → ★{PAY[tier]} ({wallet}→{after})")
        evid(
            f"{gate} jobId={result.get('jobId')} clientJobId={cid} "
            f"marks {result.get('start')}->{after}"
        )
        wallet = after
        code, auth, _ = req("POST", "/auth/dev", {"token": token})
        expect(code == 200 and int(auth.get("marks") or 0) == wallet, f"{gate} auth/dev you.marks {wallet}")

    cid = str(last.get("clientJobId", ""))
    match_id = str(last.get("matchId", ""))
    join = str(last.get("joinToken", ""))
    job_id = str(last.get("jobId", ""))

    code, replay, _ = req("GET", f"/matches/{match_id}", token=join)
    expect(code == 200 and you_marks(replay) == wallet, "J4 GET /matches replay no double-credit")
    code, replay_job, _ = req("GET", f"/jobs/{job_id}", token=join)
    replay_snap = replay_job.get("snapshot") or replay_job
    expect(you_marks(replay_snap) == wallet, "J4 GET /jobs/:id replay same wallet")

    code, atk, _ = req(
        "POST",
        f"/matches/{match_id}/actions",
        {"type": "attack", "hex": BOT[3]},
        join,
    )
    ended = atk.get("snapshot") or atk
    after_atk = you_marks(ended) if isinstance(ended, dict) else wallet
    expect(after_atk == wallet, f"J4 re-attack ended job stays ★{wallet} (got {after_atk})")

    code, again, raw = req("POST", "/jobs", {"tier": 3, "clientJobId": cid}, token)
    expect(code in (200, 201), "J4 POST /jobs same clientJobId accepted", raw[:240])
    expect(you_marks(again.get("snapshot") or again) == wallet, "J4 replay POST does not grant")
    code, auth, _ = req("POST", "/auth/dev", {"token": token})
    expect(code == 200 and int(auth.get("marks") or 0) == wallet, f"J4 durable wallet still {wallet}")
    evid(f"J4 replay clientJobId={cid} jobId={job_id} marks {wallet}")

    if FAILS:
        print("LIVE_JOBS_LADDER_FAIL " + ", ".join(FAILS))
        return 1
    print(f"LIVE_JOBS_LADDER_OK {pid} marks 0->{wallet}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
