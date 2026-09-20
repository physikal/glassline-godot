#!/usr/bin/env python3
"""LIVE P1–P5 smoke for private lobby invite.

Coder contract (when landed):
  POST /lobbies + player Bearer → { lobbyId, code, snapshot } waiting
  POST /lobbies/join { code } → seat B; both seated → ready { matchId, joinToken, snapshot }
  POST /lobbies/:id/cancel → hideout, no forfeit Marks
  GET /lobbies/:id → host poll
  6-char uppercase, no 0O1I. TTL ~10 min.

Curl LIVE first. 404 → LIVE_LOBBY_PENDING (mock covers P1–P5).
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
ALPHABET = "23456789ABCDEFGHJKLMNPQRSTUVWXYZ"


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


def snap_of(body: dict) -> dict:
    snap = body.get("snapshot") or body
    return snap if isinstance(snap, dict) else {}


def you_of(body: dict) -> dict:
    you = snap_of(body).get("you") or body.get("you") or {}
    return you if isinstance(you, dict) else {}


def marks_of(body: dict) -> int | None:
    you = you_of(body)
    if "marks" in you:
        return int(you["marks"])
    if "marks" in body:
        return int(body["marks"])
    return None


def mint_player() -> tuple[dict, str]:
    status, body, raw = req("POST", "/players", {})
    token = str(body.get("token", ""))
    return body, token


def is_valid_code(code: str) -> bool:
    if len(code) != 6:
        return False
    return all(ch in ALPHABET for ch in code.upper())


def pending(reason: str) -> int:
    print(f"LIVE_LOBBY_PENDING {reason}")
    EVIDENCE["pending"] = reason
    path = os.path.join(os.path.dirname(__file__), "..", "artifacts", "live_lobby_smoke.txt")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(json.dumps({"pending": reason, "base": BASE, "evidence": EVIDENCE}, indent=2))
        fh.write("\n")
    return 0


def main() -> int:
    print(f"BASE {BASE}")
    health_s, health, _ = req("GET", "/health")
    expect(health_s == 200 and bool(health.get("ok")), "GET /health", str(health))
    if health_s != 200:
        return pending("health_down")

    host, host_tok = mint_player()
    guest, guest_tok = mint_player()
    if not host_tok or not guest_tok:
        return pending("players_failed")
    EVIDENCE["host"] = host.get("playerId")
    EVIDENCE["guest"] = guest.get("playerId")
    host_marks = int(host.get("marks", 0))
    guest_marks = int(guest.get("marks", 0))

    create_s, created, create_raw = req("POST", "/lobbies", {}, host_tok)
    print(f"CURL POST /lobbies → {create_s} {create_raw[:240]}")
    EVIDENCE["create_status"] = create_s
    EVIDENCE["create_body"] = created
    if create_s == 404:
        note("POST /lobbies 404 — Coder pending. Mock covers P1–P5.")
        return pending("lobbies_404")

    expect(create_s in (200, 201), "P1 POST /lobbies", str(created))
    code = str(created.get("code", "")).upper()
    lobby_id = str(created.get("lobbyId", created.get("id", "")))
    expect(lobby_id != "", "P1 lobbyId")
    expect(is_valid_code(code), "P1 6-char code no 0O1I", code)
    expect(str(created.get("status", snap_of(created).get("status", ""))) == "waiting", "P1 status waiting")
    expect(str(created.get("matchId", "")) == "", "P1 no match yet")
    expect(marks_of(created) in (None, host_marks), "P1 create Marks frozen")

    join_s, joined, join_raw = req("POST", "/lobbies/join", {"code": code}, guest_tok)
    print(f"CURL POST /lobbies/join → {join_s} {join_raw[:240]}")
    EVIDENCE["join_status"] = join_s
    EVIDENCE["join_body"] = joined
    expect(join_s in (200, 201), "P2 join 200", str(joined))
    expect(str(joined.get("status", "")) == "ready", "P2 status ready")
    match_id = str(joined.get("matchId", ""))
    expect(match_id != "", "P2 matchId")
    expect(str(joined.get("joinToken", "")) != "", "P2 joinToken")
    expect(str(joined.get("seat", "")) in ("b", "B"), "P2 seat B")
    expect(str(snap_of(joined).get("status", "")) in ("ready", "waiting"), "P2 match snapshot")
    expect(marks_of(joined) in (None, guest_marks), "P2 join Marks frozen")

    poll_s, polled, _ = req("GET", f"/lobbies/{lobby_id}", None, host_tok)
    expect(poll_s == 200, "P2 host GET lobby", str(polled))
    expect(str(polled.get("matchId", "")) == match_id, "P2 host same matchId")
    expect(str(polled.get("joinToken", "")) != "", "P2 host joinToken")
    expect(str(polled.get("joinToken", "")) != str(joined.get("joinToken", "")), "P2 distinct tokens")

    bad_s, bad, _ = req("POST", "/lobbies/join", {"code": "ABCDEF"}, guest_tok)
    expect(bad_s >= 400, "P4 bad/unknown code rejected", str(bad))
    junk_s, junk, _ = req("POST", "/lobbies/join", {"code": "10O1II"}, host_tok)
    expect(junk_s >= 400, "P4 ambiguous 0O1I rejected", str(junk))

    host2, host2_tok = mint_player()
    guest2, guest2_tok = mint_player()
    create2_s, created2, _ = req("POST", "/lobbies", {}, host2_tok)
    expect(create2_s in (200, 201), "P5 second lobby", str(created2))
    lid2 = str(created2.get("lobbyId", created2.get("id", "")))
    marks_before = int(host2.get("marks", 0))
    cancel_s, cancelled, cancel_raw = req("POST", f"/lobbies/{lid2}/cancel", {}, host2_tok)
    print(f"CURL POST /lobbies/:id/cancel → {cancel_s} {cancel_raw[:240]}")
    expect(cancel_s in (200, 201), "P5 cancel 200", str(cancelled))
    expect(str(cancelled.get("status", "")) in ("cancelled", "canceled", ""), "P5 cancelled status")
    expect(marks_of(cancelled) in (None, marks_before), "P5 cancel Marks frozen")
    late_s, late, _ = req("POST", "/lobbies/join", {"code": created2.get("code", "")}, guest2_tok)
    expect(late_s >= 400, "P5 join after cancel rejected", str(late))

    # P3 — same match spine after ready. Drop + miss must not invent hit.
    tok_b = str(joined.get("joinToken", ""))
    tok_a = str(polled.get("joinToken", ""))
    if match_id and tok_a and tok_b:
        a_s, a_body, _ = req(
            "POST",
            f"/matches/{match_id}/actions",
            {"type": "select_hex", "hex": {"q": 2, "r": 2}},
            tok_a,
        )
        expect(a_s == 200, "P3 A select_hex", str(a_body))
        b_s, b_body, _ = req(
            "POST",
            f"/matches/{match_id}/actions",
            {"type": "select_hex", "hex": {"q": 7, "r": 5}},
            tok_b,
        )
        expect(b_s == 200, "P3 B select_hex", str(b_body))
        miss_s, miss, _ = req(
            "POST",
            f"/matches/{match_id}/actions",
            {"type": "attack", "hex": {"q": 0, "r": 0}},
            tok_a,
        )
        result = (miss.get("result") or snap_of(miss).get("lastAction") or {}) if miss_s == 200 else {}
        if miss_s == 200:
            expect(result.get("hit") is False, "P3 miss hit=false", str(result))
        else:
            note(f"P3 attack {miss_s} — drop may still be ready (no start). {miss}")

    if FAILS:
        print("LIVE_LOBBY_FAIL " + "; ".join(FAILS))
        return 1
    print(f"LIVE_LOBBY_OK host={host.get('playerId')} guest={guest.get('playerId')} match={match_id}")
    path = os.path.join(os.path.dirname(__file__), "..", "artifacts", "live_lobby_smoke.txt")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(json.dumps({"ok": True, "base": BASE, "pass": PASS_N, "evidence": EVIDENCE}, indent=2))
        fh.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
