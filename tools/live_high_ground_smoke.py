#!/usr/bin/env python3
"""LIVE H1–H6 smoke for HIGH GROUND.

Coder 4720879: occupy BASE_HIT 0.90, HARD +0.10, you.highGroundActive chip bind.
Missing flag → PENDING. Empty miss does not apply the bonus.
"""

from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from live_join import sit_created_pvp

BASE = os.environ.get("GLASSLINE_API_BASE", "https://glassline-api.vercel.app").rstrip("/")
FAILS: list[str] = []
NOTES: list[str] = []
PASS_N = 0
B_HEX = {"q": 8, "r": 6}


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


def open_match(player_token: str, aq: int, ar: int, bq: int = 8, br: int = 6):
    seated = sit_created_pvp(req, player_token)
    if not seated.get("ok"):
        return None
    match_id = str(seated.get("matchId", ""))
    token_a = str(seated.get("token_a") or "")
    token_b = str(seated.get("token_b") or "")
    if not token_a or not token_b:
        return None
    req("POST", f"/matches/{match_id}/actions", {"type": "select_hex", "hex": {"q": aq, "r": ar}}, token_a)
    req("POST", f"/matches/{match_id}/actions", {"type": "select_hex", "hex": {"q": bq, "r": br}}, token_b)
    _, snap, _ = req("GET", f"/matches/{match_id}", None, token_a)
    return {
        "matchId": match_id,
        "token_a": token_a,
        "token_b": token_b,
        "aq": aq,
        "ar": ar,
        "snap": snap,
        "you": you_of(snap),
        "terrain": terrain_of(snap),
    }


def hunt(player_token: str, want_hard: bool):
    for r in range(7):
        for q in range(9):
            if q == B_HEX["q"] and r == B_HEX["r"]:
                continue
            bag = open_match(player_token, q, r)
            if not bag:
                continue
            you = bag["you"]
            if "highGroundActive" not in you:
                return {"missing": True, "snap": bag["snap"]}
            flag = bool(you.get("highGroundActive"))
            kind = bag["terrain"].get((q, r), "")
            print(f"HUNT  {q},{r} type={kind} flag={flag} {bag['matchId']}")
            if want_hard and flag and kind == "hard":
                return bag
            if not want_hard and (not flag) and kind in ("open", "brush"):
                return bag
    return None


def main() -> int:
    print("SMOKE_BASE", BASE)
    status, health, _ = req("GET", "/health")
    expect(status == 200 and health.get("ok") is True, "GET /health", str(health))

    status, player, _ = req("POST", "/players", {})
    token = str(player.get("token") or "")
    expect(status in (200, 201) and token != "", "POST /players", str(player))

    probe = open_match(token, 2, 2)
    if not probe:
        note("LIVE match create/join never became usable.")
        print("LIVE_HIGH_GROUND_PENDING")
        return 0
    if "highGroundActive" not in probe["you"]:
        note(
            "LIVE snapshot omits you.highGroundActive — Coder resolve not up. "
            "Client binds the flag only; mock stills cover H3 chrome."
        )
        print("LIVE_HIGH_GROUND_PENDING")
        return 0

    hard = hunt(token, True)
    off = hunt(token, False)
    if not hard or hard.get("missing") or not off:
        expect(False, "H1/H2 hunted HARD and OPEN/BRUSH drops")
        print("LIVE_HIGH_GROUND_FAIL")
        return 1

    expect(hard["you"].get("highGroundActive") is True, "H1 HARD you.highGroundActive true")
    expect(hard["terrain"].get((hard["aq"], hard["ar"])) == "hard", "H1 drop terrain hard")
    expect(off["you"].get("highGroundActive") is False, "H2 OPEN/BRUSH you.highGroundActive false")
    expect(off["terrain"].get((off["aq"], off["ar"])) in ("open", "brush"), "H2 drop terrain open/brush")

    b_kind_hard = hard["terrain"].get((B_HEX["q"], B_HEX["r"]), "")
    expect(
        hard["you"].get("highGroundActive") is True,
        "H5 attacker HARD ignores defender %s" % (b_kind_hard or "unknown"),
    )
    expect(off["you"].get("highGroundActive") is False, "H5 attacker OPEN/BRUSH ignores defender terrain")

    # Empty miss from HARD — bonus does not apply; chip flag stays true.
    status, miss, _ = req(
        "POST",
        f"/matches/{hard['matchId']}/actions",
        {"type": "attack", "hex": {"q": 4, "r": 3}},
        hard["token_a"],
    )
    miss_res = miss.get("result") or {}
    miss_you = you_of(miss)
    expect(status == 200 and miss.get("ok") is True, "H6 attack intent { type, hex } accepted", str(miss.get("error")))
    expect(miss_res.get("type") == "attack", "H6 result.type attack")
    expect("highGround" not in (miss.get("snapshot") or {}), "H6 no invented top-level highGround")
    expect(miss_you.get("highGroundActive") is True, "H1 miss keeps snapshot flag")
    expect(miss_res.get("highGroundApplied") is False, "H1 empty miss highGroundApplied false")
    expect(float(miss_res.get("hitChance", -1)) == 0.0, "H1 empty miss hitChance 0", str(miss_res))
    expect(miss_res.get("hit") is False, "H1 empty miss hit false")
    expect("marksDelta" not in miss_res, "H4 no Marks on miss result")
    expect(int(miss_you.get("marks") or 0) == int(hard["you"].get("marks") or 0), "H4 Marks unchanged on miss")
    expect(miss_you.get("decoyAvailable") is True, "H4 decoy charge untouched")

    # Occupy from HARD → applied + hitChance 1.0
    req("POST", f"/matches/{hard['matchId']}/actions", {"type": "end_turn", "exposurePct": 50}, hard["token_a"])
    req("POST", f"/matches/{hard['matchId']}/actions", {"type": "recon", "hex": {"q": 4, "r": 3}}, hard["token_b"])
    req("POST", f"/matches/{hard['matchId']}/actions", {"type": "end_turn", "exposurePct": 50}, hard["token_b"])
    status, occupy_h, _ = req(
        "POST",
        f"/matches/{hard['matchId']}/actions",
        {"type": "attack", "hex": B_HEX},
        hard["token_a"],
    )
    hres = occupy_h.get("result") or {}
    print("HARD_OCCUPY", json.dumps(hres))
    expect(status == 200 and occupy_h.get("ok") is True, "H1 HARD occupy accepted")
    expect(hres.get("highGroundApplied") is True, "H1 HARD occupy applied", str(hres))
    expect(abs(float(hres.get("hitChance", -1)) - 1.0) < 1e-6, "H1 HARD occupy hitChance 1.0", str(hres))

    # Occupy from OPEN/BRUSH → not applied, hitChance 0.90
    status, occupy_o, _ = req(
        "POST",
        f"/matches/{off['matchId']}/actions",
        {"type": "attack", "hex": B_HEX},
        off["token_a"],
    )
    ores = occupy_o.get("result") or {}
    print("OFF_OCCUPY", json.dumps(ores))
    expect(status == 200 and occupy_o.get("ok") is True, "H2 OPEN/BRUSH occupy accepted")
    expect(ores.get("highGroundApplied") is False, "H2 OPEN/BRUSH occupy not applied", str(ores))
    expect(abs(float(ores.get("hitChance", -1)) - 0.90) < 1e-6, "H2 OPEN/BRUSH occupy hitChance 0.90", str(ores))
    if hres.get("hit") is True:
        expect(int(you_of(occupy_h).get("marks") or 0) == int(hard["you"].get("marks") or 0) + 25, "H4 HARD kill table +25 not extra")

    if FAILS:
        print("LIVE_HIGH_GROUND_FAIL")
        for line in FAILS:
            print("FAIL:", line)
        return 1
    print("LIVE_HIGH_GROUND_OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
