#!/usr/bin/env python3
"""LIVE Soft A4.1 abandon smoke (Coder clear).

Contract (glassline-api#10 / LIVE):
  POST /matches/:id/abandon + join Bearer, no body
  active → same forfeit path as 30s silence (endReason=forfeit, Marks +12 / 0)
  ready / waiting → 409 match_not_active
  already ended → 409 match_already_ended (idempotent: no second grant)
  rematch 409 while active; rematch OK after ended

  GLASSLINE_API_BASE=https://glassline-api.vercel.app python3 tools/live_a4_gaps_smoke.py
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


def note(text: str) -> None:
    NOTES.append(text)
    print(f"NOTE  {text}")


def snap_of(body: dict) -> dict:
    snap = body.get("snapshot") or body
    return snap if isinstance(snap, dict) else {}


def you_of(body: dict) -> dict:
    you = snap_of(body).get("you") or {}
    return you if isinstance(you, dict) else {}


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


def mint_player():
    status, body, _ = req("POST", "/players", {})
    return status, str(body.get("token") or ""), str(body.get("playerId") or ""), body


def create_match(token_a: str):
    status, created, raw = req("POST", "/matches", {}, token_a)
    if status not in (200, 201) or "matchId" not in created:
        return {"ok": False, "error": raw, "created": created}
    return {
        "ok": True,
        "matchId": str(created["matchId"]),
        "ja": str(created.get("joinToken") or ""),
        "created": created,
    }


def join_seat(match_id: str, join_token: str, player_token: str | None):
    return req("POST", f"/matches/{match_id}/join", {"token": join_token}, player_token)


def claim_seat_b(match_id: str, player_token: str):
    return req("POST", f"/matches/{match_id}/join", {}, player_token)


def drop_both(match_id: str, ja: str, jb: str):
    req("POST", f"/matches/{match_id}/actions", {"type": "select_hex", "hex": {"q": 2, "r": 2}}, ja)
    return req("POST", f"/matches/{match_id}/actions", {"type": "select_hex", "hex": {"q": 7, "r": 5}}, jb)


def abandon(match_id: str, join_token: str):
    ## Contract: no body.
    return req("POST", f"/matches/{match_id}/abandon", None, join_token)


def rematch(match_id: str, token: str, accept: bool = True):
    return req("POST", f"/matches/{match_id}/rematch", {"accept": accept}, token)


def main() -> int:
    print(f"BASE {BASE}")
    st, health, _ = req("GET", "/health")
    expect(st == 200 and health.get("ok") is True, "GET /health")
    EVIDENCE["health"] = health

    st, token_a, pid_a, player_a = mint_player()
    expect(st in (200, 201) and token_a != "", "POST /players A", str(player_a))
    st, token_b, pid_b, player_b = mint_player()
    expect(st in (200, 201) and token_b != "", "POST /players B", str(player_b))
    EVIDENCE["playerA"] = pid_a
    EVIDENCE["playerB"] = pid_b
    print(f"PLAYERS {pid_a} {pid_b}")

    ## waiting → 409
    wait = create_match(token_a)
    expect(wait.get("ok") is True, "waiting match create")
    mid_w = wait.get("matchId", "")
    ja_w = wait.get("ja", "")
    join_seat(mid_w, ja_w, token_a)
    st_w, snap_w, _ = req("GET", f"/matches/{mid_w}", None, ja_w)
    expect(st_w == 200 and snap_w.get("status") == "waiting", f"waiting status ({snap_w.get('status')})")
    st_aw, body_aw, raw_aw = abandon(mid_w, ja_w)
    print(f"ABANDON_WAITING {mid_w} {st_aw} {(raw_aw or '')[:240]}")
    expect(
        st_aw == 409 and str(body_aw.get("code") or "") == "match_not_active",
        "A4.1 waiting abandon 409 match_not_active",
        str(body_aw)[:240],
    )
    EVIDENCE["waiting"] = {"matchId": mid_w, "http": st_aw, "code": body_aw.get("code")}

    ## ready → 409
    ready = create_match(token_a)
    expect(ready.get("ok") is True, "ready match create")
    mid_r = ready.get("matchId", "")
    ja_r = ready.get("ja", "")
    join_seat(mid_r, ja_r, token_a)
    claim_seat_b(mid_r, token_b)
    st_r, snap_r, _ = req("GET", f"/matches/{mid_r}", None, ja_r)
    expect(st_r == 200 and snap_r.get("status") == "ready", f"ready status ({snap_r.get('status')})")
    st_ar, body_ar, raw_ar = abandon(mid_r, ja_r)
    print(f"ABANDON_READY {mid_r} {st_ar} {(raw_ar or '')[:240]}")
    expect(
        st_ar == 409 and str(body_ar.get("code") or "") == "match_not_active",
        "A4.1 ready abandon 409 match_not_active",
        str(body_ar)[:240],
    )
    EVIDENCE["ready"] = {"matchId": mid_r, "http": st_ar, "code": body_ar.get("code")}

    ## active hunt
    hunt = create_match(token_a)
    expect(hunt.get("ok") is True, "active match create")
    mid = hunt.get("matchId", "")
    ja = hunt.get("ja", "")
    join_a = join_seat(mid, ja, token_a)[1]
    join_b = claim_seat_b(mid, token_b)[1]
    jb = str(join_b.get("joinToken") or "")
    expect(str(join_a.get("playerId") or "") == pid_a, "seat A binds durable player")
    expect(str(join_b.get("playerId") or "") == pid_b, "seat B binds durable player")
    st_drop, drop_b, _ = drop_both(mid, ja, jb)
    snap_b = snap_of(drop_b)
    expect(st_drop == 200 and snap_b.get("status") == "active", f"active after drop ({snap_b.get('status')})")
    st_get, snap_a, _ = req("GET", f"/matches/{mid}", None, ja)
    expect(st_get == 200 and snap_a.get("status") == "active", "GET active before abandon")
    marks_a0 = marks_of(snap_a)
    marks_b0 = marks_of(snap_b)
    shop_a0 = wallet_of(token_a)
    shop_b0 = wallet_of(token_b)
    print(f"ACTIVE {mid} snap A/B {marks_a0}/{marks_b0} shop {shop_a0}/{shop_b0}")

    st_rm, rem, raw_rm = rematch(mid, ja, True)
    print(f"REMATCH_ACTIVE {st_rm} {(raw_rm or '')[:240]}")
    expect(
        st_rm == 409 and str(rem.get("code") or "") == "match_not_ended",
        "A4.4 rematch while active 409 match_not_ended",
        str(rem)[:240],
    )

    st_a, body, raw_a = abandon(mid, ja)
    print(f"ABANDON_ACTIVE {mid} {st_a} {(raw_a or '')[:500]}")
    if st_a == 404:
        note("LIVE POST /matches/:id/abandon is 404 again. Coder route missing.")
        print("LIVE_A4_GAPS_SMOKE_FAIL abandon_404")
        return 1

    snap = snap_of(body)
    expect(st_a == 200 and body.get("ok") is True, "A4.1 abandon HTTP 200", (raw_a or "")[:240])
    expect(snap.get("status") == "ended", f"A4.1 status ended ({snap.get('status')})")
    expect(snap.get("endReason") == "forfeit", f"A4.1 endReason forfeit ({snap.get('endReason')})")
    expect(snap.get("winner") == "b", f"A4.1 remaining seat wins ({snap.get('winner')})")
    last = snap.get("lastAction") or body.get("lastAction") or {}
    expect(
        isinstance(last, dict) and last.get("type") == "forfeit" and last.get("winner") == "b",
        "A4.1 lastAction forfeit winner b",
        str(last)[:200],
    )
    expect(marks_of(body) == 0, f"A4.1 leaver you.marks 0 ({marks_of(body)})")

    st_b, remain, _ = req("GET", f"/matches/{mid}", None, jb)
    expect(st_b == 200, "A4.1 remaining GET")
    expect(remain.get("endReason") == "forfeit", f"A4.1 remaining forfeit ({remain.get('endReason')})")
    expect(remain.get("winner") == "b", "A4.1 remaining winner b")
    expect(marks_of(remain) == 12, f"A4.1 remaining you.marks 12 ({marks_of(remain)})")
    rematch_field = remain.get("rematch") or snap.get("rematch") or {}
    expect(
        isinstance(rematch_field, dict) and rematch_field.get("status") == "waiting",
        f"A4.4 rematch waiting after ended ({rematch_field.get('status')})",
    )

    shop_a1 = wallet_of(token_a)
    shop_b1 = wallet_of(token_b)
    d_a, d_b = shop_a1 - shop_a0, shop_b1 - shop_b0
    print(f"MARKS {mid} leaver {shop_a0}->{shop_a1} (Δ{d_a}) remaining {shop_b0}->{shop_b1} (Δ{d_b})")
    expect(d_a == 0, f"A4.1 leaver shop Δ0 ({shop_a0}->{shop_a1})")
    expect(d_b == 12, f"A4.1 remaining shop Δ+12 ({shop_b0}->{shop_b1})")

    EVIDENCE["a41"] = {
        "matchId": mid,
        "endReason": snap.get("endReason"),
        "winner": snap.get("winner"),
        "leaver": {"playerId": pid_a, "you.marks": marks_of(body), "shop": shop_a1, "delta": d_a},
        "remaining": {"playerId": pid_b, "you.marks": marks_of(remain), "shop": shop_b1, "delta": d_b},
    }

    st2, replay, raw2 = abandon(mid, ja)
    print(f"ABANDON_REPLAY {st2} {(raw2 or '')[:240]}")
    expect(
        st2 == 409 and str(replay.get("code") or "") == "match_already_ended",
        "A4.1 second abandon 409 match_already_ended",
        str(replay)[:240],
    )
    shop_a2, shop_b2 = wallet_of(token_a), wallet_of(token_b)
    expect(shop_a2 == shop_a1 and shop_b2 == shop_b1, f"A4.1 replay abandon no second grant ({shop_a2}/{shop_b2})")
    EVIDENCE["idempotent"] = {"http": st2, "code": replay.get("code"), "shop": [shop_a2, shop_b2]}

    st3, rem2, raw3 = rematch(mid, ja, True)
    print(f"REMATCH_ENDED_A {st3} {(raw3 or '')[:300]}")
    expect(st3 in (200, 201) and rem2.get("status") in ("waiting", "ready"), f"A4.4 rematch after ended ({st3} {rem2.get('status')})", str(rem2)[:240])
    st4, rem3, raw4 = rematch(mid, jb, True)
    print(f"REMATCH_ENDED_B {st4} {(raw4 or '')[:300]}")
    expect(st4 in (200, 201) and rem3.get("status") == "ready", f"A4.4 rematch ready after ended ({st4})", str(rem3)[:240])
    new_mid = str(rem3.get("matchId") or (rem3.get("snapshot") or {}).get("matchId") or "")
    expect(new_mid != "" and new_mid != mid, f"A4.4 rematch new matchId ({new_mid})")
    EVIDENCE["rematchAfter"] = {"old": mid, "new": new_mid, "http": st4}

    print("EVIDENCE " + json.dumps(EVIDENCE, sort_keys=True))
    if FAILS:
        print("LIVE_A4_GAPS_SMOKE_FAIL " + ", ".join(FAILS))
        return 1
    print(f"LIVE_A4_GAPS_SMOKE_OK {mid} forfeit remaining Δ+12 leaver Δ0 rematch {new_mid}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
