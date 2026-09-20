#!/usr/bin/env python3
"""LIVE Q1–Q5 smoke for Quick Match queue.

Coder LIVE (glassline-api queue.ts, 2026-09-20):
  POST   /queue Bearer player → 200 { status: queued, queuedAt, timeoutSec: 60, expiresAt }
           or 200 { status: matched, matchId, joinToken, seat, snapshot }
  GET    /queue → idle | queued+secondsLeft | matched | expired (once, then idle)
  DELETE /queue → 200 { status: idle }  (waiting rows only; Marks Δ0)
  60s TTL. Pair two humans → ready PvP. No bot fill.
  409 already_in_match | in_lobby. 401 missing bearer.

Bare 404 → LIVE_QUEUE_PENDING.
"""

from __future__ import annotations

import json
import os
import sys
import time
import urllib.error
import urllib.request

BASE = os.environ.get("GLASSLINE_API_BASE", "https://glassline-api.vercel.app").rstrip("/")
SKIP_TTL = os.environ.get("GLASSLINE_QUEUE_SKIP_TTL", "").lower() in ("1", "true", "yes")
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
    status, body, _raw = req("POST", "/players", {})
    return body, str(body.get("token", ""))


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

    idle_s, idle, _ = req("GET", "/queue", None, host_tok)
    expect(idle_s == 200 and str(idle.get("status", "")) == "idle", "Q1 GET idle first", str(idle))

    q_s, queued, _ = req("POST", "/queue", {}, host_tok)
    if is_route_missing(q_s, queued):
        return pending(f"POST /queue + bearer {q_s}")
    expect(q_s == 200, "Q1 POST /queue", str(queued))
    expect(str(queued.get("status", "")) == "queued", "Q1 status queued", str(queued))
    expect(int(queued.get("timeoutSec", 0)) == 60, "Q1 timeoutSec 60", str(queued))
    expect(str(queued.get("expiresAt", "")) != "", "Q1 expiresAt")
    expect(str(queued.get("matchId", "")) == "", "Q1 no match yet")
    expect(marks_of(queued) in (None, marks_before), "Q1 enqueue Marks frozen")
    EVIDENCE["enqueue"] = queued

    poll_s, poll, _ = req("GET", "/queue", None, host_tok)
    expect(poll_s == 200 and str(poll.get("status", "")) == "queued", "Q1 GET still queued", str(poll))
    expect(int(poll.get("secondsLeft", -1)) > 0, "Q1 secondsLeft", str(poll))
    expect(str(poll.get("matchId", "")) == "", "Q5 GET no bot fill")
    expect(wallet_marks(host_tok, marks_before) == marks_before, "Q5 lonely Marks Δ0")

    g_s, guest_q, _ = req("POST", "/queue", {}, guest_tok)
    expect(g_s == 200, "Q2 guest POST /queue", str(guest_q))
    expect(str(guest_q.get("status", "")) == "matched", "Q2 guest matched now", str(guest_q))
    match_id = str(guest_q.get("matchId", ""))
    join_b = str(guest_q.get("joinToken", ""))
    expect(match_id.startswith("m_"), "Q2 matchId m_", match_id)
    expect(join_b != "", "Q2 guest joinToken")
    expect(str(guest_q.get("seat", "")) == "b", "Q2 guest seat B")
    snap_b = guest_q.get("snapshot") if isinstance(guest_q.get("snapshot"), dict) else {}
    expect(str(snap_b.get("status", "")) == "ready", "Q2 snapshot ready")
    expect(str(snap_b.get("kind", "")) == "pvp", "Q2 kind pvp")
    expect(marks_of(guest_q) in (None, 0), "Q2 pair Marks frozen")

    h_s, host_q, _ = req("GET", "/queue", None, host_tok)
    expect(h_s == 200 and str(host_q.get("status", "")) == "matched", "Q2 host GET matched", str(host_q))
    expect(str(host_q.get("matchId", "")) == match_id, "Q2 same matchId")
    join_a = str(host_q.get("joinToken", ""))
    expect(join_a != "" and join_a != join_b, "Q2 host own joinToken")
    expect(str(host_q.get("seat", "")) == "a", "Q2 host seat A")
    EVIDENCE["matchId"] = match_id
    EVIDENCE["seats"] = {"a": host_q.get("seat"), "b": guest_q.get("seat")}

    if match_id and join_a and join_b:
        a_s, a_body, _ = req(
            "POST",
            f"/matches/{match_id}/actions",
            {"type": "select_hex", "hex": {"q": 2, "r": 2}},
            join_a,
        )
        expect(a_s == 200, "Q2 A select_hex", str(a_body))
        b_s, b_body, _ = req(
            "POST",
            f"/matches/{match_id}/actions",
            {"type": "select_hex", "hex": {"q": 7, "r": 5}},
            join_b,
        )
        expect(b_s == 200, "Q2 B select_hex", str(b_body))
        snap = b_body.get("snapshot") if isinstance(b_body.get("snapshot"), dict) else {}
        expect(str(snap.get("status", "")) in ("ready", "active"), "Q2 drop still match path", str(snap.get("status")))

    leftover, leftover_tok = mint_player()
    l_s, leftover_q, _ = req("POST", "/queue", {}, leftover_tok)
    expect(l_s == 200 and str(leftover_q.get("status", "")) == "queued", "Q5 third player not bot-filled", str(leftover_q))
    expect(str(leftover_q.get("matchId", "")) == "", "Q5 leftover no matchId")
    req("DELETE", "/queue", None, leftover_tok)

    host2, host2_tok = mint_player()
    marks2 = wallet_marks(host2_tok, marks_of(host2) or 0)
    c_s, cancel_q, _ = req("POST", "/queue", {}, host2_tok)
    expect(c_s == 200 and str(cancel_q.get("status", "")) == "queued", "Q3 enqueue for cancel", str(cancel_q))
    d_s, deleted, _ = req("DELETE", "/queue", None, host2_tok)
    expect(d_s == 200, "Q3 DELETE /queue", str(deleted))
    expect(str(deleted.get("status", "")) == "idle", "Q3 idle", str(deleted))
    d2_s, deleted2, _ = req("DELETE", "/queue", None, host2_tok)
    expect(d2_s == 200 and str(deleted2.get("status", "")) == "idle", "Q3 re-DELETE idle")
    after = wallet_marks(host2_tok, marks2)
    expect(after == marks2, "Q3 cancel Marks Δ0", f"{marks2}->{after}")
    EVIDENCE["cancel_marks"] = {"before": marks2, "after": after}

    ttl, ttl_tok = mint_player()
    marks_ttl = wallet_marks(ttl_tok, marks_of(ttl) or 0)
    t_s, ttl_q, _ = req("POST", "/queue", {}, ttl_tok)
    expect(t_s == 200 and str(ttl_q.get("status", "")) == "queued", "Q4 enqueue for TTL", str(ttl_q))
    if SKIP_TTL:
        note("Q4 skip real 60s wait (GLASSLINE_QUEUE_SKIP_TTL)")
    else:
        note("Q4 waiting 61s for LIVE TTL")
        time.sleep(61)
        exp_s, expired, _ = req("GET", "/queue", None, ttl_tok)
        expect(exp_s == 200, "Q4 GET after TTL", str(expired))
        expect(str(expired.get("status", "")) in ("expired", "idle"), "Q4 expired or idle", str(expired))
        expect(str(expired.get("matchId", "")) == "", "Q4 no match on timeout")
        idle2_s, idle2, _ = req("GET", "/queue", None, ttl_tok)
        expect(idle2_s == 200 and str(idle2.get("status", "")) == "idle", "Q4 next poll idle", str(idle2))
        after_ttl = wallet_marks(ttl_tok, marks_ttl)
        expect(after_ttl == marks_ttl, "Q4 timeout Marks Δ0", f"{marks_ttl}->{after_ttl}")
        EVIDENCE["timeout_marks"] = {"before": marks_ttl, "after": after_ttl, "first": expired}

    if FAILS:
        print("LIVE_QUEUE_FAIL " + "; ".join(FAILS))
        write_log(False)
        return 1
    print(
        f"LIVE_QUEUE_OK host={host.get('playerId')} guest={guest.get('playerId')} "
        f"match={match_id} cancel_marks={EVIDENCE.get('cancel_marks')} "
        f"timeout_marks={EVIDENCE.get('timeout_marks')}"
    )
    write_log(True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
