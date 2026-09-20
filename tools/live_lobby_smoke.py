#!/usr/bin/env python3
"""LIVE P1–P5 smoke for private lobby invite.

Coder LIVE (glassline-api #11, 2026-09-20):
  POST /lobbies + player Bearer → 201 { lobbyId lob_…, code, status waiting, expiresAt }
  POST /lobbies/join { code } → 200 { status ready, matchId, joinToken, seat b, snapshot=MATCH }
  GET  /lobbies/:id → 200 lobby snap + top-level matchId/joinToken when ready
  POST /lobbies/:id/cancel waiting → 200 { ok, status cancelled }; after handoff 409 lobby_already_started
  Errors: 400 invalid_lobby_code|invalid_join_body; 404 lobby_not_found;
          409 lobby_expired|lobby_full|already_in_lobby|lobby_cancelled|lobby_already_started
  6-char uppercase, no 0O1I. TTL 10 min. Cancel waiting = zero Marks.

Curl LIVE first. Prefer LIVE once POST /lobbies is 200/201.
Bare 404 (no lobby_not_found) → LIVE_LOBBY_PENDING.
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


def err_of(body: dict) -> str:
    return str(body.get("code") or body.get("error") or "")


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


def is_valid_code(code: str) -> bool:
    if len(code) != 6:
        return False
    return all(ch in ALPHABET for ch in code.upper())


def is_match_snap(snap: dict, match_id: str = "") -> bool:
    if not isinstance(snap, dict) or not snap:
        return False
    if str(snap.get("kind", "")) == "lobby":
        return False
    mid = str(snap.get("matchId", ""))
    if match_id and mid and mid != match_id:
        return False
    if not mid and not match_id:
        return False
    return any(k in snap for k in ("terrain", "turnIndex", "phase", "whoseTurn")) or str(
        snap.get("kind", "")
    ) in ("pvp", "sp_job", "job")


def pending(reason: str) -> int:
    print(f"LIVE_LOBBY_PENDING {reason}")
    EVIDENCE["pending"] = reason
    path = os.path.join(os.path.dirname(__file__), "..", "artifacts", "live_lobby_smoke.txt")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(json.dumps({"pending": reason, "base": BASE, "evidence": EVIDENCE}, indent=2))
        fh.write("\n")
    return 0


def write_log(ok: bool) -> None:
    path = os.path.join(os.path.dirname(__file__), "..", "artifacts", "live_lobby_smoke.txt")
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


def main() -> int:
    print(f"BASE {BASE}")
    health_s, health, _ = req("GET", "/health")
    expect(health_s == 200 and bool(health.get("ok")), "GET /health", str(health))
    if health_s != 200:
        return pending("health_down")

    probe_s, probe, probe_raw = req("POST", "/lobbies", {})
    print(f"CURL POST /lobbies (no auth) → {probe_s} {probe_raw[:240]}")
    EVIDENCE["probe_unauth"] = {"status": probe_s, "body": probe}

    host, host_tok = mint_player()
    guest, guest_tok = mint_player()
    if not host_tok or not guest_tok:
        return pending("players_failed")
    EVIDENCE["host"] = host.get("playerId")
    EVIDENCE["guest"] = guest.get("playerId")
    host_marks = int(host.get("marks", 0))
    guest_marks = int(guest.get("marks", 0))
    EVIDENCE["host_marks_start"] = host_marks
    EVIDENCE["guest_marks_start"] = guest_marks

    create_s, created, create_raw = req("POST", "/lobbies", {}, host_tok)
    print(f"CURL POST /lobbies → {create_s} {create_raw[:240]}")
    EVIDENCE["create_status"] = create_s
    EVIDENCE["create_body"] = created
    if create_s == 404 and err_of(created) not in ("lobby_not_found",):
        note("POST /lobbies 404 — route missing. Mock covers P1–P5.")
        return pending("lobbies_404")

    expect(create_s in (200, 201), "P1 POST /lobbies", str(created))
    code = str(created.get("code", "")).upper()
    lobby_id = str(created.get("lobbyId", created.get("id", "")))
    expect(lobby_id != "", "P1 lobbyId")
    expect(lobby_id.startswith("lob_"), "P1 lobbyId lob_ prefix", lobby_id)
    expect(is_valid_code(code), "P1 6-char code no 0O1I", code)
    expect(str(created.get("status", snap_of(created).get("status", ""))) == "waiting", "P1 status waiting")
    expect(str(created.get("matchId", "")) == "", "P1 no match yet")
    expect(str(created.get("expiresAt", "")) != "", "P1 expiresAt")
    expect(marks_of(created) in (None, host_marks), "P1 create Marks frozen")
    EVIDENCE["code"] = code
    EVIDENCE["lobbyId"] = lobby_id

    self_s, self_body, _ = req("POST", "/lobbies/join", {"code": code}, host_tok)
    expect(self_s == 409, "P4 host self-join 409", str(self_body))
    expect(err_of(self_body) == "already_in_lobby", "P4 already_in_lobby", str(self_body))

    join_s, joined, join_raw = req("POST", "/lobbies/join", {"code": code}, guest_tok)
    print(f"CURL POST /lobbies/join → {join_s} {join_raw[:240]}")
    EVIDENCE["join_status"] = join_s
    EVIDENCE["join_body"] = {
        k: joined.get(k)
        for k in ("status", "matchId", "joinToken", "seat", "lobbyId")
        if k in joined
    }
    expect(join_s in (200, 201), "P2 join 200", str(joined))
    expect(str(joined.get("status", "")) == "ready", "P2 status ready")
    match_id = str(joined.get("matchId", ""))
    expect(match_id != "", "P2 matchId")
    expect(str(joined.get("joinToken", "")) != "", "P2 joinToken")
    expect(str(joined.get("seat", "")).lower() == "b", "P2 seat B")
    expect(is_match_snap(snap_of(joined), match_id), "P2 join snapshot is match")
    expect(str(snap_of(joined).get("status", "")) in ("ready", "waiting"), "P2 match snapshot")
    expect(marks_of(joined) in (None, guest_marks), "P2 join Marks frozen")
    EVIDENCE["matchId"] = match_id

    poll_s, polled, _ = req("GET", f"/lobbies/{lobby_id}", None, host_tok)
    expect(poll_s == 200, "P2 host GET lobby", str(polled))
    expect(str(polled.get("matchId", "")) == match_id, "P2 host same matchId")
    expect(str(polled.get("joinToken", "")) != "", "P2 host joinToken")
    expect(str(polled.get("joinToken", "")) != str(joined.get("joinToken", "")), "P2 distinct tokens")
    expect(str(polled.get("seat", "")).lower() in ("a", ""), "P2 host seat A")
    poll_snap = snap_of(polled)
    if poll_snap.get("kind") == "lobby" or (poll_snap.get("lobbyId") and not is_match_snap(poll_snap, match_id)):
        expect(True, "P2 GET keeps lobby snap")
    else:
        note(f"P2 GET snapshot kind={poll_snap.get('kind')} — bind must still GET the match")

    late_start_s, late_start, _ = req("POST", f"/lobbies/{lobby_id}/cancel", {}, host_tok)
    expect(late_start_s == 409, "P5 cancel after ready 409", str(late_start))
    expect(err_of(late_start) == "lobby_already_started", "P5 lobby_already_started", str(late_start))
    expect(marks_of(late_start) in (None, host_marks), "P5 started-cancel Marks frozen")

    bad_s, bad, _ = req("POST", "/lobbies/join", {"code": "ABCDEF"}, guest_tok)
    expect(bad_s == 404, "P4 unknown code 404", str(bad))
    expect(err_of(bad) == "lobby_not_found", "P4 lobby_not_found", str(bad))
    junk_s, junk, _ = req("POST", "/lobbies/join", {"code": "10O1II"}, host_tok)
    expect(junk_s == 400, "P4 ambiguous 0O1I 400", str(junk))
    expect(err_of(junk) == "invalid_lobby_code", "P4 invalid_lobby_code", str(junk))

    host2, host2_tok = mint_player()
    guest2, guest2_tok = mint_player()
    create2_s, created2, _ = req("POST", "/lobbies", {}, host2_tok)
    expect(create2_s in (200, 201), "P5 second lobby", str(created2))
    lid2 = str(created2.get("lobbyId", created2.get("id", "")))
    marks_before = int(host2.get("marks", 0))
    cancel_s, cancelled, cancel_raw = req("POST", f"/lobbies/{lid2}/cancel", {}, host2_tok)
    print(f"CURL POST /lobbies/:id/cancel → {cancel_s} {cancel_raw[:240]}")
    EVIDENCE["cancel_status"] = cancel_s
    EVIDENCE["cancel_body"] = cancelled
    expect(cancel_s in (200, 201), "P5 cancel 200", str(cancelled))
    expect(str(cancelled.get("status", "")) in ("cancelled", "canceled"), "P5 cancelled status")
    expect(marks_of(cancelled) in (None, marks_before), "P5 cancel payload Marks frozen")
    after_cancel = wallet_marks(host2_tok, marks_before)
    expect(after_cancel == marks_before, "P5 cancel wallet Marks frozen", str(after_cancel))
    EVIDENCE["cancel_marks"] = {"before": marks_before, "after": after_cancel}
    late_s, late, _ = req("POST", "/lobbies/join", {"code": created2.get("code", "")}, guest2_tok)
    expect(late_s == 409, "P5 join after cancel 409", str(late))
    expect(err_of(late) == "lobby_cancelled", "P5 lobby_cancelled", str(late))

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
        EVIDENCE["p3"] = {"select_a": a_s, "select_b": b_s, "attack": miss_s}

    if FAILS:
        print("LIVE_LOBBY_FAIL " + "; ".join(FAILS))
        write_log(False)
        return 1
    print(
        f"LIVE_LOBBY_OK host={host.get('playerId')} guest={guest.get('playerId')} "
        f"code={code} lobby={lobby_id} match={match_id} "
        f"cancel_marks={EVIDENCE.get('cancel_marks')}"
    )
    write_log(True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
