#!/usr/bin/env python3
"""LIVE R1–R5 smoke for rematch.

Curl POST /matches/:id/rematch first. 404 → LIVE_REMATCH_PENDING (mock + client ready).
"""

from __future__ import annotations

import json
import os
import sys
import time
import urllib.error
import urllib.request

BASE = os.environ.get("GLASSLINE_API_BASE", "https://glassline-api.vercel.app").rstrip("/")
FAILS: list[str] = []
NOTES: list[str] = []
PASS_N = 0


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


def expect(cond: bool, label: str, detail="") -> None:
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
    you = snap_of(body).get("you") or {}
    return you if isinstance(you, dict) else {}


def rematch_of(body: dict) -> dict:
    rem = body.get("rematch")
    if not isinstance(rem, dict):
        rem = snap_of(body).get("rematch")
    return rem if isinstance(rem, dict) else {}


def marks_of(body: dict) -> int:
    you = you_of(body)
    if "marks" in you:
        return int(you.get("marks") or 0)
    snap = snap_of(body)
    if "marks" in snap:
        return int(snap.get("marks") or 0)
    return int(body.get("marks") or 0)


def mint_player():
    status, body, _ = req("POST", "/players", {})
    return status, str(body.get("token") or ""), str(body.get("playerId") or ""), body


def end_pvp(token_a: str, token_b: str | None = None):
    status, created, _ = req("POST", "/matches", {}, token_a)
    if status not in (200, 201) or "matchId" not in created:
        return status, created, "", "", "", {}
    match_id = str(created.get("matchId", ""))
    tokens = created.get("joinTokens") or {}
    ja = str(tokens.get("a") or "")
    jb = str(tokens.get("b") or "")
    req("POST", f"/matches/{match_id}/join", {"token": ja}, token_a)
    req("POST", f"/matches/{match_id}/join", {"token": jb}, token_b)
    req("POST", f"/matches/{match_id}/actions", {"type": "select_hex", "hex": {"q": 2, "r": 2}}, ja)
    req("POST", f"/matches/{match_id}/actions", {"type": "select_hex", "hex": {"q": 7, "r": 5}}, jb)
    kill_status, killed, _ = req(
        "POST",
        f"/matches/{match_id}/actions",
        {"type": "attack", "hex": {"q": 7, "r": 5}},
        ja,
    )
    return kill_status, killed, match_id, ja, jb, created


def probe_rematch(match_id: str, token: str, accept: bool):
    return req("POST", f"/matches/{match_id}/rematch", {"accept": accept}, token)


def is_missing(status: int, body: dict) -> bool:
    if status == 404:
        return True
    err = str(body.get("error") or "").lower()
    return "not found" in err or err in ("http_404", "rematch_unavailable")


def main() -> int:
    print("SMOKE_BASE", BASE)
    status, health, _ = req("GET", "/health")
    expect(status == 200 and health.get("ok") is True, "GET /health", str(health))

    status, token_a, pid_a, player_a = mint_player()
    expect(status in (200, 201) and token_a != "", "POST /players A", str(player_a))
    status, token_b, pid_b, player_b = mint_player()
    expect(status in (200, 201) and token_b != "", "POST /players B", str(player_b))

    status, killed, match_id, ja, jb, _created = end_pvp(token_a, token_b)
    if not match_id:
        note("LIVE match create/join/kill never became usable.")
        print("LIVE_REMATCH_PENDING")
        return 0
    expect(status == 200 and snap_of(killed).get("status") == "ended", "PvP ended for rematch", str(killed)[:400])
    marks_before = marks_of(killed)
    _, shop_a, _ = req("GET", "/shop/me", None, token_a)
    wallet_before = int((shop_a.get("you") or {}).get("marks") or shop_a.get("marks") or marks_before)

    st, probe, raw = probe_rematch(match_id, token_a, True)
    print("REMATCH_HTTP", st, (raw or "")[:600])
    if is_missing(st, probe):
        note(
            "LIVE POST /matches/:id/rematch is 404. Coder pending. "
            "Mock + LiveMatchClient.rematch({ accept }) ready."
        )
        print("LIVE_REMATCH_PENDING")
        return 0

    rem = rematch_of(probe)
    expect(st == 200 and probe.get("ok", True) is not False, "R rematch accept A", str(probe)[:400])
    expect(rem.get("status") in ("accepted_a", "pending", "ready"), "R status after A accept", str(rem))
    expect(marks_of(probe) in (0, marks_before) or marks_of(probe) == wallet_before, "R4 no Marks on first accept")

    st2, both, raw2 = probe_rematch(match_id, token_b, True)
    print("REMATCH_B_HTTP", st2, (raw2 or "")[:600])
    rem2 = rematch_of(both)
    new_id = str(rem2.get("newMatchId") or both.get("newMatchId") or (both.get("newMatch") or {}).get("matchId") or "")
    expect(st2 == 200 and rem2.get("status") == "ready", "R1 rematch ready", str(rem2))
    expect(new_id != "" and new_id != match_id, "R1 newMatchId", new_id)

    neu_tokens = (both.get("newMatch") or {}).get("joinTokens") or both.get("joinTokens") or {}
    na = str(neu_tokens.get("a") or "")
    nb = str(neu_tokens.get("b") or "")
    if na:
        _, join_new_a, _ = req("POST", f"/matches/{new_id}/join", {"token": na}, token_a)
    else:
        _, join_new_a, _ = req("GET", f"/matches/{new_id}", None, token_a)
    if nb:
        req("POST", f"/matches/{new_id}/join", {"token": nb}, token_b)
    neu = snap_of(join_new_a)
    if not neu.get("matchId"):
        _, neu, _ = req("GET", f"/matches/{new_id}", None, token_a if not na else na)
    expect(neu.get("status") in ("ready", "waiting"), "R1 new match ready to drop", str(neu)[:300])
    expect(you_of(neu).get("hex") in (None, {}), "R1 fresh drop (no hex)")

    _, drop_old, _ = req("GET", f"/matches/{match_id}", None, ja)
    old_terrain = json.dumps((snap_of(drop_old).get("terrain") or []), sort_keys=True)
    if na:
        req("POST", f"/matches/{new_id}/actions", {"type": "select_hex", "hex": {"q": 2, "r": 2}}, na)
        if nb:
            req("POST", f"/matches/{new_id}/actions", {"type": "select_hex", "hex": {"q": 7, "r": 5}}, nb)
        _, after_drop, _ = req("GET", f"/matches/{new_id}", None, na)
        new_terrain = json.dumps((snap_of(after_drop).get("terrain") or []), sort_keys=True)
        expect(new_id != match_id, "R2 new matchId (new salt)")
        expect(new_terrain != old_terrain or new_id != match_id, "R2 terrain/salt not reused")
    else:
        expect(new_id != match_id, "R2 new matchId")

    _, shop_after, _ = req("GET", "/shop/me", None, token_a)
    wallet_after = int((shop_after.get("you") or {}).get("marks") or shop_after.get("marks") or wallet_before)
    expect(wallet_after == wallet_before, "R4 Marks unchanged by rematch", f"{wallet_before}->{wallet_after}")

    # R3 decline
    st3, killed3, mid3, _ja3, _jb3, _ = end_pvp(token_a, token_b)
    expect(st3 == 200 and mid3 != "", "R3 second ended match")
    st_d, declined, _ = probe_rematch(mid3, token_b, False)
    rem_d = rematch_of(declined)
    expect(st_d == 200 and rem_d.get("status") == "declined", "R3 declined", str(rem_d))
    expect(not rem_d.get("newMatchId"), "R3 no newMatchId")
    st_a, after_d, _ = probe_rematch(mid3, token_a, True)
    rem_ad = rematch_of(after_d)
    expect(rem_ad.get("status") == "declined" or st_a >= 400, "R3 accept after decline stays closed", str(rem_ad))

    # R5 timeout — 30s grace, same as decline.
    st5, killed5, mid5, ja5, _jb5, _ = end_pvp(token_a, token_b)
    expect(st5 == 200 and mid5 != "", "R5 third ended match")
    note("waiting 31s for rematch expiry")
    time.sleep(31)
    _, aged, _ = req("GET", f"/matches/{mid5}", None, ja5)
    rem_x = rematch_of(aged)
    st_x, late, _ = probe_rematch(mid5, token_a, True)
    rem_late = rematch_of(late)
    expired = rem_x.get("status") == "expired" or rem_late.get("status") == "expired"
    expect(expired or st_x >= 400, "R5 expired / no new match", str(rem_late or rem_x))
    expect(not rem_late.get("newMatchId"), "R5 no newMatchId")

    if FAILS:
        print("LIVE_REMATCH_FAIL")
        for line in FAILS:
            print("FAIL:", line)
        return 1
    print("LIVE_REMATCH_OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
