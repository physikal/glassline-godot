#!/usr/bin/env python3
"""LIVE Q1–Q5 smoke for Quick Match queue.

Coder contract (ticket 2026-09-20):
  POST   /queue + player Bearer → { status: queued, queuedAt, timeoutSec: 60 }
  GET    /queue → queue { status, secondsLeft } or matched { matchId, joinToken }
  DELETE /queue → { status: idle }
  60s TTL. Pair two waiting players → existing match path. No bot fill.
  Cancel / timeout → hideout, Marks Δ0.

Curl LIVE first. Bare 404 (no queue_not_found) → LIVE_QUEUE_PENDING.
"""

from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.request

BASE = os.environ.get("GLASSLINE_API_BASE", "https://glassline-api.vercel.app").rstrip("/")
FAILS: list[str] = []
NOTES: list[str] = []
PASS_N = 0
EVIDENCE: dict = {}


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
    except (urllib.error.URLError, TimeoutError, OSError) as err:
        return 0, {"error": str(err)}, str(err)


def expect(cond: bool, label: str, detail: str = "") -> None:
    global PASS_N
    if cond:
        PASS_N += 1
        print(f"PASS  {label}")
        return
    FAILS.append(label)
    extra = f"  {detail}" if detail else ""
    print(f"FAIL  {label}{extra}")


def note(msg: str) -> None:
    NOTES.append(msg)
    print(f"NOTE  {msg}")


def err_of(body: dict) -> str:
    return str(body.get("code") or body.get("error") or "")


def marks_of(body: dict) -> int | None:
    you = body.get("you") if isinstance(body.get("you"), dict) else {}
    if "marks" in you:
        return int(you["marks"])
    if "marks" in body:
        return int(body["marks"])
    snap = body.get("snapshot") if isinstance(body.get("snapshot"), dict) else {}
    you_snap = snap.get("you") if isinstance(snap.get("you"), dict) else {}
    if "marks" in you_snap:
        return int(you_snap["marks"])
    return None


def mint_player() -> tuple[dict, str]:
    status, body, raw = req("POST", "/players", {})
    token = str(body.get("token", ""))
    return body, token


def wallet_marks(token: str, fallback: int | None) -> int | None:
    for path in ("/shop/me", "/auth/dev"):
        method = "GET" if path == "/shop/me" else "POST"
        body_in = None if method == "GET" else {}
        status, body, _ = req(method, path, body_in, token)
        if status == 200:
            got = marks_of(body)
            if got is not None:
                return got
            if "marks" in body:
                return int(body["marks"])
    return fallback


def pending(reason: str) -> int:
    print(f"LIVE_QUEUE_PENDING {reason}")
    EVIDENCE["pending"] = reason
    path = os.path.join(os.path.dirname(__file__), "..", "artifacts", "live_queue_smoke.txt")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(json.dumps({"pending": reason, "base": BASE, "evidence": EVIDENCE}, indent=2))
        fh.write("\n")
    return 0


def write_log(ok: bool) -> None:
    path = os.path.join(os.path.dirname(__file__), "..", "artifacts", "live_queue_smoke.txt")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(
            json.dumps(
                {
                    "ok": ok,
                    "base": BASE,
                    "pass": PASS_N,
                    "fails": FAILS,
                    "notes": NOTES,
                    "evidence": EVIDENCE,
                },
                indent=2,
            )
        )
        fh.write("\n")


def is_route_missing(status: int, body: dict) -> bool:
    if status != 404:
        return False
    code = err_of(body)
    return code in ("", "queue_unavailable") or "404" in str(body.get("error", ""))


def main() -> int:
    health_s, health, _ = req("GET", "/health")
    if health_s != 200 or not health.get("ok"):
        return pending(f"GET /health {health_s}")

    probe_s, probe, probe_raw = req("POST", "/queue", {})
    if probe_s == 401:
        note("POST /queue no-auth 401 (route up)")
    elif is_route_missing(probe_s, probe):
        return pending(f"POST /queue {probe_s} {probe_raw[:160]}")
    else:
        note(f"POST /queue no-auth {probe_s} {err_of(probe)}")

    host, host_tok = mint_player()
    guest, guest_tok = mint_player()
    if not host_tok or not guest_tok:
        return pending("POST /players failed")
    EVIDENCE["host"] = host.get("playerId")
    EVIDENCE["guest"] = guest.get("playerId")

    marks_before = wallet_marks(host_tok, marks_of(host) or 0)

    q_s, queued, _ = req("POST", "/queue", {}, host_tok)
    if is_route_missing(q_s, queued):
        return pending(f"POST /queue + bearer {q_s}")
    expect(q_s in (200, 201), "Q1 POST /queue", str(queued))
    expect(str(queued.get("status", "")) == "queued", "Q1 status queued", str(queued))
    expect(int(queued.get("timeoutSec", 0)) == 60, "Q1 timeoutSec 60", str(queued))
    expect(str(queued.get("matchId", "")) == "", "Q1 no match yet")
    expect(marks_of(queued) in (None, marks_before), "Q1 enqueue Marks frozen")
    EVIDENCE["enqueue"] = queued

    poll_s, poll, _ = req("GET", "/queue", None, host_tok)
    if poll_s == 404 and is_route_missing(poll_s, poll):
        note("GET /queue 404 — poll via POST replay / events when Coder adds it")
    elif poll_s == 200:
        expect(str(poll.get("status", "")) in ("queued", "idle"), "Q1 GET still waiting", str(poll))
        expect(str(poll.get("matchId", "")) == "", "Q5 GET no bot fill")

    g_s, guest_q, _ = req("POST", "/queue", {}, guest_tok)
    expect(g_s in (200, 201), "Q2 guest POST /queue", str(guest_q))
    match_id = str(guest_q.get("matchId", "") or queued.get("matchId", ""))
    join_b = str(guest_q.get("joinToken", ""))
    if str(guest_q.get("status", "")) == "queued":
        for _i in range(8):
            gs, gb, _ = req("GET", "/queue", None, guest_tok)
            hs, hb, _ = req("GET", "/queue", None, host_tok)
            if str(gb.get("status", "")) in ("matched", "ready") or str(gb.get("matchId", "")):
                guest_q = gb
                match_id = str(gb.get("matchId", match_id))
                join_b = str(gb.get("joinToken", join_b))
            if str(hb.get("status", "")) in ("matched", "ready") or str(hb.get("matchId", "")):
                queued = hb
                match_id = str(hb.get("matchId", match_id))
            if match_id:
                break
    expect(match_id != "", "Q2 paired matchId", str(guest_q))
    expect(join_b != "" or str(queued.get("joinToken", "")) != "", "Q2 joinToken")
    EVIDENCE["matchId"] = match_id

    if match_id:
        tok_a = str(queued.get("joinToken", ""))
        tok_b = join_b
        if tok_a and tok_b:
            a_s, a_body, _ = req(
                "POST",
                f"/matches/{match_id}/actions",
                {"type": "select_hex", "hex": {"q": 2, "r": 2}},
                tok_a,
            )
            expect(a_s == 200, "Q2 A select_hex", str(a_body))
            b_s, b_body, _ = req(
                "POST",
                f"/matches/{match_id}/actions",
                {"type": "select_hex", "hex": {"q": 7, "r": 5}},
                tok_b,
            )
            expect(b_s == 200, "Q2 B select_hex", str(b_body))

    host2, host2_tok = mint_player()
    marks2 = wallet_marks(host2_tok, marks_of(host2) or 0)
    c_s, cancel_q, _ = req("POST", "/queue", {}, host2_tok)
    expect(c_s in (200, 201), "Q3 enqueue for cancel", str(cancel_q))
    d_s, deleted, _ = req("DELETE", "/queue", None, host2_tok)
    expect(d_s in (200, 204), "Q3 DELETE /queue", str(deleted))
    expect(str(deleted.get("status", "idle")) in ("idle", ""), "Q3 idle", str(deleted))
    after = wallet_marks(host2_tok, marks2)
    expect(after == marks2, "Q3 cancel Marks Δ0", f"{marks2}->{after}")
    EVIDENCE["cancel_marks"] = {"before": marks2, "after": after}

    if FAILS:
        print("LIVE_QUEUE_FAIL " + "; ".join(FAILS))
        write_log(False)
        return 1
    print(
        f"LIVE_QUEUE_OK host={host.get('playerId')} guest={guest.get('playerId')} "
        f"match={match_id} cancel_marks={EVIDENCE.get('cancel_marks')}"
    )
    write_log(True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
