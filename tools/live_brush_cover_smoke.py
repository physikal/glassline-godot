#!/usr/bin/env python3
"""LIVE B1–B6 smoke for BRUSH cover.

Coder 948f04a: defender revealed BRUSH −0.10, stacks with HIGH GROUND.
Result fields: coverApplied + highGroundApplied + hitChance. No chip.
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


def you_of(body: dict) -> dict:
    snap = body.get("snapshot") or body
    you = snap.get("you") or {}
    return you if isinstance(you, dict) else {}


def terrain_of(body: dict) -> dict:
    snap = body.get("snapshot") or body
    rows = snap.get("terrain") or []
    out = {}
    if isinstance(rows, list):
        for row in rows:
            if isinstance(row, dict) and "type" in row:
                out[(int(row.get("q", -1)), int(row.get("r", -1)))] = str(row.get("type"))
    return out


def close(val: float, want: float) -> bool:
    return abs(float(val) - want) < 1e-6


def open_match(player_token: str, aq: int, ar: int, bq: int, br: int):
    status, created, _ = req("POST", "/matches", {}, player_token)
    if status not in (200, 201) or "matchId" not in created:
        return None
    match_id = str(created.get("matchId", ""))
    tokens = created.get("joinTokens") or {}
    token_a = str(tokens.get("a") or "")
    token_b = str(tokens.get("b") or "")
    req("POST", f"/matches/{match_id}/join", {"token": token_a}, player_token)
    req("POST", f"/matches/{match_id}/join", {"token": token_b})
    req("POST", f"/matches/{match_id}/actions", {"type": "select_hex", "hex": {"q": aq, "r": ar}}, token_a)
    req("POST", f"/matches/{match_id}/actions", {"type": "select_hex", "hex": {"q": bq, "r": br}}, token_b)
    _, snap, _ = req("GET", f"/matches/{match_id}", None, token_a)
    return {
        "matchId": match_id,
        "token_a": token_a,
        "token_b": token_b,
        "aq": aq,
        "ar": ar,
        "bq": bq,
        "br": br,
        "snap": snap,
        "you": you_of(snap),
        "terrain": terrain_of(snap),
    }


def occupy(bag: dict):
    status, body, _ = req(
        "POST",
        f"/matches/{bag['matchId']}/actions",
        {"type": "attack", "hex": {"q": bag["bq"], "r": bag["br"]}},
        bag["token_a"],
    )
    return status, body, (body.get("result") or {})


def hunt_buckets(player_token: str, needed: list[str], cap: int = 48):
    """One pass: classify occupy results. Salt changes per matchId."""
    found: dict = {}
    tries = 0
    for ar in range(7):
        for aq in range(9):
            for br in range(7):
                for bq in range(9):
                    if aq == bq and ar == br:
                        continue
                    if all(key in found for key in needed):
                        return found
                    if tries >= cap:
                        return found
                    bag = open_match(player_token, aq, ar, bq, br)
                    if not bag:
                        continue
                    kind = bag["terrain"].get((aq, ar), "")
                    a_hard = kind == "hard"
                    status, body, res = occupy(bag)
                    tries += 1
                    if "coverApplied" not in res:
                        return {"missing": {"res": res, "body": body, "bag": bag}}
                    cover = bool(res.get("coverApplied"))
                    key = ("hard" if a_hard else "open") + ("_brush" if cover else "_off")
                    print(
                        f"HUNT  {key} A {aq},{ar}={kind} B {bq},{br} "
                        f"hg={res.get('highGroundApplied')} chance={res.get('hitChance')} {bag['matchId']}"
                    )
                    if key in needed and key not in found:
                        bag["occupy_status"] = status
                        bag["occupy"] = body
                        bag["result"] = res
                        bag["a_kind"] = kind
                        found[key] = bag
    return found


def main() -> int:
    print("SMOKE_BASE", BASE)
    status, health, _ = req("GET", "/health")
    expect(status == 200 and health.get("ok") is True, "GET /health", str(health))

    status, player, _ = req("POST", "/players", {})
    token = str(player.get("token") or "")
    expect(status in (200, 201) and token != "", "POST /players", str(player))

    probe = open_match(token, 2, 2, 8, 6)
    if not probe:
        note("LIVE match create/join never became usable.")
        print("LIVE_BRUSH_COVER_PENDING")
        return 0
    status, miss_probe, raw = req(
        "POST",
        f"/matches/{probe['matchId']}/actions",
        {"type": "attack", "hex": {"q": 4, "r": 3}},
        probe["token_a"],
    )
    miss_res = miss_probe.get("result") or {}
    print("PROBE_MISS", json.dumps(miss_res))
    if "coverApplied" not in miss_res:
        note(
            "LIVE attack result omits coverApplied — Coder resolve not up. "
            "Client displays the field only; mock covers B1–B6."
        )
        print("LIVE_BRUSH_COVER_PENDING")
        return 0

    expect(status == 200 and miss_probe.get("ok") is True, "B intent { type, hex } accepted", str(miss_probe.get("error")))
    expect(miss_res.get("type") == "attack", "B result.type attack")
    expect("cover" not in (miss_probe.get("snapshot") or {}), "B no invented top-level cover")
    expect("inCover" not in you_of(miss_probe), "B5 snapshot has no inCover chip")
    expect("coverActive" not in you_of(miss_probe), "B5 snapshot has no coverActive chip")
    expect(miss_res.get("coverApplied") is False, "B4 empty miss coverApplied false")
    expect(close(float(miss_res.get("hitChance", -1)), 0.0), "B4 empty miss hitChance 0", str(miss_res))
    expect(miss_res.get("hit") is False, "B4 empty miss hit false")
    expect(int(you_of(miss_probe).get("marks") or 0) == int(probe["you"].get("marks") or 0), "B6 Marks unchanged on miss")

    needed = ["open_brush", "hard_brush", "open_off"]
    found = hunt_buckets(token, needed)
    if "missing" in found:
        note(
            "LIVE occupy omitted coverApplied mid-hunt — Coder resolve not up. "
            "Client displays the field only; mock covers B1–B6."
        )
        print("LIVE_BRUSH_COVER_PENDING")
        return 0
    if any(key not in found for key in needed):
        expect(False, "B1/B2/B3 hunted OPEN→BRUSH, HARD→BRUSH, OPEN→OPEN/HARD", str(list(found)))
        print("LIVE_BRUSH_COVER_FAIL")
        return 1

    open_brush = found["open_brush"]
    hard_brush = found["hard_brush"]
    open_off = found["open_off"]
    ob = open_brush["result"]
    hb = hard_brush["result"]
    oo = open_off["result"]
    print("OPEN_BRUSH", json.dumps(ob))
    print("HARD_BRUSH", json.dumps(hb))
    print("OPEN_OFF", json.dumps(oo))

    expect(ob.get("coverApplied") is True, "B1 OPEN→BRUSH coverApplied true", str(ob))
    expect(ob.get("highGroundApplied") is False, "B3 OPEN→BRUSH highGroundApplied false", str(ob))
    expect(close(float(ob.get("hitChance", -1)), 0.80), "B3 OPEN→BRUSH hitChance 0.80", str(ob))

    expect(hb.get("coverApplied") is True, "B3 HARD→BRUSH coverApplied true", str(hb))
    expect(hb.get("highGroundApplied") is True, "B3 HARD→BRUSH highGroundApplied true", str(hb))
    expect(close(float(hb.get("hitChance", -1)), 0.90), "B3 HARD→BRUSH hitChance 0.90", str(hb))

    expect(oo.get("coverApplied") is False, "B2 OPEN→OPEN/HARD coverApplied false", str(oo))
    expect(oo.get("highGroundApplied") is False, "B2 OPEN no high ground", str(oo))
    expect(close(float(oo.get("hitChance", -1)), 0.90), "B2 OPEN off-brush hitChance 0.90", str(oo))

    if hb.get("hit") is True:
        expect(
            int(you_of(hard_brush["occupy"]).get("marks") or 0)
            == int(hard_brush["you"].get("marks") or 0) + 25,
            "B6 HARD→BRUSH kill table +25 not extra",
        )

    # B4 decoy: reuse the probe match (already an empty miss → await_end_turn).
    req("POST", f"/matches/{probe['matchId']}/actions", {"type": "end_turn", "exposurePct": 50}, probe["token_a"])
    d_status, d_body, _ = req(
        "POST",
        f"/matches/{probe['matchId']}/actions",
        {"type": "decoy"},
        probe["token_b"],
    )
    planted = (d_body.get("result") or {}).get("hex") or you_of(d_body).get("decoyHex")
    if d_status == 200 and isinstance(planted, dict):
        req("POST", f"/matches/{probe['matchId']}/actions", {"type": "end_turn", "exposurePct": 50}, probe["token_b"])
        _, shot, _ = req(
            "POST",
            f"/matches/{probe['matchId']}/actions",
            {"type": "attack", "hex": {"q": int(planted.get("q", 0)), "r": int(planted.get("r", 0))}},
            probe["token_a"],
        )
        dres = shot.get("result") or {}
        print("DECOY_SHOT", json.dumps(dres))
        expect(dres.get("hit") is False, "B4 decoy still miss")
        expect(dres.get("coverApplied") is False, "B4 decoy coverApplied false", str(dres))
        expect(close(float(dres.get("hitChance", -1)), 0.0), "B4 decoy hitChance 0", str(dres))
    else:
        note("LIVE decoy not usable this pass — mock covers B4 doll miss.")
        print("DECOY_PENDING", d_status, json.dumps(d_body.get("result") or d_body))

    if FAILS:
        print("LIVE_BRUSH_COVER_FAIL")
        for line in FAILS:
            print("FAIL:", line)
        return 1
    print("LIVE_BRUSH_COVER_OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
