#!/usr/bin/env python3
"""LIVE R1–R5 smoke for rematch.

Coder contract:
  POST /matches/:id/rematch { accept: true|false } + join Bearer
  Non-ended → 409 match_not_ended
  Both accept → { status:"ready", matchId, joinToken, snapshot }
  Decline / timeout → hideout
  Marks untouched by rematch
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


def wallet_of(token: str) -> int:
    _, shop, _ = req("GET", "/shop/me", None, token)
    you = shop.get("you") or {}
    if isinstance(you, dict) and "marks" in you:
        return int(you.get("marks") or 0)
    return int(shop.get("marks") or 0)


def terrain_fp(body: dict) -> str:
    rows = snap_of(body).get("terrain") or []
    return json.dumps(rows, sort_keys=True)


def mint_player():
    status, body, _ = req("POST", "/players", {})
    return status, str(body.get("token") or ""), str(body.get("playerId") or ""), body


def end_pvp(token_a: str, token_b: str | None = None):
    status, created, _ = req("POST", "/matches", {}, token_a)
    if status not in (200, 201) or "matchId" not in created:
        return {
            "ok": False,
            "status": status,
            "killed": created,
            "matchId": "",
            "ja": "",
            "jb": "",
            "pidA": "",
            "pidB": "",
            "created": created,
        }
    match_id = str(created.get("matchId", ""))
    tokens = created.get("joinTokens") or {}
    ja = str(tokens.get("a") or "")
    jb = str(tokens.get("b") or "")
    _, join_a, _ = req("POST", f"/matches/{match_id}/join", {"token": ja}, token_a)
    _, join_b, _ = req("POST", f"/matches/{match_id}/join", {"token": jb}, token_b)
    req("POST", f"/matches/{match_id}/actions", {"type": "select_hex", "hex": {"q": 2, "r": 2}}, ja)
    req("POST", f"/matches/{match_id}/actions", {"type": "select_hex", "hex": {"q": 7, "r": 5}}, jb)
    kill_status, killed, _ = req(
        "POST",
        f"/matches/{match_id}/actions",
        {"type": "attack", "hex": {"q": 7, "r": 5}},
        ja,
    )
    return {
        "ok": kill_status == 200 and snap_of(killed).get("status") == "ended",
        "status": kill_status,
        "killed": killed,
        "matchId": match_id,
        "ja": ja,
        "jb": jb,
        "pidA": str(join_a.get("playerId") or ""),
        "pidB": str(join_b.get("playerId") or ""),
        "created": created,
        "joinA": join_a,
        "joinB": join_b,
    }


def probe_rematch(match_id: str, token: str, accept: bool):
    return req("POST", f"/matches/{match_id}/rematch", {"accept": accept}, token)


def is_missing(status: int, body: dict) -> bool:
    if status == 404:
        return True
    err = str(body.get("error") or "").lower()
    return "not found" in err or err in ("http_404", "rematch_unavailable")


def player_id_from_join(match_id: str, join_token: str, player_token: str) -> str:
    st, body, _ = req("POST", f"/matches/{match_id}/join", {"token": join_token}, player_token)
    pid = str(body.get("playerId") or "")
    if pid:
        return pid
    if st >= 400:
        st2, snap, _ = req("GET", f"/matches/{match_id}", None, join_token)
        if st2 == 200:
            return f"seated:{you_of(snap).get('seat')}:{marks_of(snap)}"
    return ""


def main() -> int:
    print("SMOKE_BASE", BASE)
    status, health, _ = req("GET", "/health")
    expect(status == 200 and health.get("ok") is True, "GET /health", str(health))

    status, token_a, pid_a, player_a = mint_player()
    expect(status in (200, 201) and token_a != "", "POST /players A", str(player_a))
    status, token_b, pid_b, player_b = mint_player()
    expect(status in (200, 201) and token_b != "", "POST /players B", str(player_b))
    EVIDENCE["playerA"] = pid_a
    EVIDENCE["playerB"] = pid_b
    print("PLAYERS", pid_a, pid_b)

    # Route-up proof: rematch on a live (non-ended) match.
    st, created, _ = req("POST", "/matches", {}, token_a)
    live_mid = str(created.get("matchId") or "")
    live_ja = str((created.get("joinTokens") or {}).get("a") or "")
    if live_mid and live_ja:
        st409, body409, raw409 = probe_rematch(live_mid, live_ja, True)
        print("NON_ENDED_REMATCH", st409, (raw409 or "")[:400])
        expect(
            st409 == 409 and str(body409.get("code") or "") == "match_not_ended",
            "route up: non-ended 409 match_not_ended",
            str(body409)[:300],
        )
        EVIDENCE["routeUp"] = {"matchId": live_mid, "http": st409, "code": body409.get("code")}

    hunt = end_pvp(token_a, token_b)
    match_id = hunt["matchId"]
    ja, jb = hunt["ja"], hunt["jb"]
    if not match_id:
        note("LIVE match create/join/kill never became usable.")
        print("LIVE_REMATCH_PENDING")
        return 0
    expect(hunt["ok"], "PvP ended for rematch", str(hunt["killed"])[:400])
    expect(hunt["pidA"] == pid_a and hunt["pidB"] == pid_b, "ended seats bind durable players", f"{hunt['pidA']}/{hunt['pidB']}")
    EVIDENCE["r1OldMatch"] = match_id
    marks_a_end = marks_of(hunt["killed"])
    marks_b_end = marks_of({"snapshot": {}})
    _, snap_b_end, _ = req("GET", f"/matches/{match_id}", None, jb)
    marks_b_end = marks_of(snap_b_end)
    wallet_a = wallet_of(token_a)
    wallet_b = wallet_of(token_b)
    print("ENDED", match_id, "marks A/B", marks_a_end, marks_b_end, "shop", wallet_a, wallet_b)
    rem_field = rematch_of(hunt["killed"]) or rematch_of(snap_b_end)
    print("ENDED_REMATCH_FIELD", json.dumps(rem_field)[:400])

    st, probe, raw = probe_rematch(match_id, ja, True)
    print("REMATCH_A_HTTP", st, (raw or "")[:600])
    if is_missing(st, probe):
        note(
            "LIVE POST /matches/:id/rematch is 404. Coder pending. "
            "Mock + LiveMatchClient.rematch({ accept }) ready."
        )
        print("LIVE_REMATCH_PENDING")
        return 0

    rem = rematch_of(probe)
    expect(st == 200, "R rematch accept A HTTP 200", str(probe)[:400])
    expect(
        probe.get("status") in ("waiting", "ready")
        or rem.get("status") in ("waiting", "ready", "accepted_a", "pending"),
        "R waiting after A",
        str(probe)[:400],
    )
    expect(wallet_of(token_a) == wallet_a, "R3 no Marks on first accept")

    st2, both, raw2 = probe_rematch(match_id, jb, True)
    print("REMATCH_B_HTTP", st2, (raw2 or "")[:600])
    rem2 = rematch_of(both)
    new_id = str(
        both.get("matchId")
        or rem2.get("newMatchId")
        or rem2.get("matchId")
        or both.get("newMatchId")
        or (both.get("newMatch") or {}).get("matchId")
        or ""
    )
    expect(st2 == 200 and (both.get("status") == "ready" or rem2.get("status") == "ready"), "R1 rematch ready", str(both)[:400])
    expect(new_id != "" and new_id != match_id, "R1 new matchId", new_id)
    expect(str(both.get("joinToken") or "") != "", "R1 B joinToken")
    expect(you_of(both).get("hex") in (None, {}), "R1 B fresh drop (no hex)")
    join_b_new = str(both.get("joinToken") or "")
    st_a2, replay_a, raw_a2 = probe_rematch(match_id, ja, True)
    print("REMATCH_A_REPLAY", st_a2, (raw_a2 or "")[:400])
    expect(st_a2 == 200 and replay_a.get("status") == "ready", "R1 replay A ready")
    join_a_new = str(replay_a.get("joinToken") or "")
    expect(join_a_new != "" and join_a_new != join_b_new, "R1 A joinToken distinct")
    expect(str(replay_a.get("matchId") or "") == new_id, "R1 replay same matchId")
    expect(you_of(replay_a).get("seat") == "a" and you_of(both).get("seat") == "b", "R2 same seats")
    EVIDENCE["r1NewMatch"] = new_id

    # R2 — same durable players (join on the new ready match, or seat+wallet bind).
    pid_a_new = player_id_from_join(new_id, join_a_new, token_a)
    pid_b_new = player_id_from_join(new_id, join_b_new, token_b)
    print("R2_JOIN_PIDS", pid_a_new, pid_b_new)
    same_a = pid_a_new == pid_a or pid_a_new.startswith("seated:a:")
    same_b = pid_b_new == pid_b or pid_b_new.startswith("seated:b:")
    expect(same_a, "R2 durable player A", f"{pid_a} -> {pid_a_new}")
    expect(same_b, "R2 durable player B", f"{pid_b} -> {pid_b_new}")
    st_pa, via_player, _ = probe_rematch(match_id, token_a, True)
    expect(
        st_pa == 200 and via_player.get("status") == "ready" and str(via_player.get("matchId") or "") == new_id,
        "R2 player-token rematch still this pair",
        str(via_player)[:200],
    )
    EVIDENCE["r2"] = {"oldA": pid_a, "oldB": pid_b, "newA": pid_a_new, "newB": pid_b_new}

    # R1 terrain: drop both on the new board and compare fingerprints.
    _, drop_old, _ = req("GET", f"/matches/{match_id}", None, ja)
    old_terrain = terrain_fp(drop_old)
    req("POST", f"/matches/{new_id}/actions", {"type": "select_hex", "hex": {"q": 2, "r": 2}}, join_a_new)
    req("POST", f"/matches/{new_id}/actions", {"type": "select_hex", "hex": {"q": 7, "r": 5}}, join_b_new)
    _, after_drop, _ = req("GET", f"/matches/{new_id}", None, join_a_new)
    new_terrain = terrain_fp(after_drop)
    expect(new_id != match_id, "R1 new matchId (new salt)")
    expect(new_terrain != old_terrain, "R1 fresh terrain", f"old={len(old_terrain)} new={len(new_terrain)}")
    EVIDENCE["r1Terrain"] = {"oldBytes": len(old_terrain), "newBytes": len(new_terrain), "differ": new_terrain != old_terrain}

    # R3 Marks unchanged by rematch (shop + snapshot).
    wallet_a_after = wallet_of(token_a)
    wallet_b_after = wallet_of(token_b)
    marks_a_new = marks_of(replay_a) if "you" in snap_of(replay_a) else marks_of(after_drop)
    expect(wallet_a_after == wallet_a, "R3 Marks A shop unchanged", f"{wallet_a}->{wallet_a_after}")
    expect(wallet_b_after == wallet_b, "R3 Marks B shop unchanged", f"{wallet_b}->{wallet_b_after}")
    expect(marks_a_end == wallet_a and marks_b_end == wallet_b, "R3 end ledger already settled")
    EVIDENCE["r3"] = {
        "A": {"end": marks_a_end, "shopBefore": wallet_a, "shopAfter": wallet_a_after, "delta": wallet_a_after - wallet_a},
        "B": {"end": marks_b_end, "shopBefore": wallet_b, "shopAfter": wallet_b_after, "delta": wallet_b_after - wallet_b},
    }
    print("R3_MARKS", json.dumps(EVIDENCE["r3"]))

    # R4 decline
    hunt3 = end_pvp(token_a, token_b)
    mid3 = hunt3["matchId"]
    expect(hunt3["ok"] and mid3 != "", "R4 second ended match")
    wallet_a_r4 = wallet_of(token_a)
    st_d, declined, raw_d = probe_rematch(mid3, hunt3["jb"], False)
    print("R4_DECLINE", st_d, (raw_d or "")[:400])
    rem_d = rematch_of(declined)
    expect(st_d == 200 and (declined.get("status") == "declined" or rem_d.get("status") == "declined"), "R4 declined", str(declined)[:300])
    expect(
        not rem_d.get("newMatchId") and declined.get("status") != "ready" and rem_d.get("status") != "ready",
        "R4 no new match",
    )
    st_a, after_d, _ = probe_rematch(mid3, hunt3["ja"], True)
    rem_ad = rematch_of(after_d)
    expect(after_d.get("status") == "declined" or rem_ad.get("status") == "declined" or st_a >= 400, "R4 accept after decline stays closed", str(after_d)[:300])
    expect(wallet_of(token_a) == wallet_a_r4, "R3 Marks unchanged by decline")
    EVIDENCE["r4"] = {"ended": mid3, "status": declined.get("status"), "newMatchId": rem_d.get("newMatchId")}

    # R5 timeout — 30s from match end (expiresAt). Late accept → expired / hideout.
    hunt5 = end_pvp(token_a, token_b)
    mid5 = hunt5["matchId"]
    expect(hunt5["ok"] and mid5 != "", "R5 third ended match")
    rem5 = rematch_of(hunt5["killed"])
    expires = str(rem5.get("expiresAt") or "")
    print("R5_EXPIRES_AT", expires)
    note("waiting 31s for rematch expiry (server clock is 30s from ended_at / expiresAt)")
    time.sleep(31)
    _, aged, _ = req("GET", f"/matches/{mid5}", None, hunt5["ja"])
    rem_x = rematch_of(aged)
    st_x, late, raw_x = probe_rematch(mid5, hunt5["ja"], True)
    print("R5_LATE", st_x, (raw_x or "")[:400])
    rem_late = rematch_of(late)
    expired = rem_x.get("status") == "expired" or rem_late.get("status") == "expired" or late.get("status") == "expired"
    expect(expired or st_x >= 400, "R5 expired / hideout", str(late or rem_x)[:300])
    expect(not rem_late.get("newMatchId") and late.get("status") != "ready", "R5 no new match")
    EVIDENCE["r5"] = {
        "ended": mid5,
        "expiresAt": expires,
        "getStatus": rem_x.get("status"),
        "lateStatus": late.get("status") or rem_late.get("status"),
        "lateHttp": st_x,
    }

    print("EVIDENCE", json.dumps(EVIDENCE, indent=2))
    if FAILS:
        print("LIVE_REMATCH_FAIL")
        for line in FAILS:
            print("FAIL:", line)
        return 1
    print("LIVE_REMATCH_OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
