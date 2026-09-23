#!/usr/bin/env python3
"""LIVE S1–S5 for Ability SMOKE against glassline-api tip fa7285ba.

Once/match { type: "smoke" }. Decoy-clock duration. Spot −20, no stack.
No Attack +0.10 / highGroundApplied. Doll floor, Marks, UAV, Decoy stay put.
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
HUNT_CAP = int(os.environ.get("LIVE_SMOKE_HUNT_CAP", "80"))


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


def req_retry(method: str, path: str, body=None, token: str | None = None, tries: int = 4):
    import time
    status, parsed, raw = 0, {}, ""
    for attempt in range(tries):
        status, parsed, raw = req(method, path, body, token)
        if status not in (0, 429, 500, 502, 503, 504):
            return status, parsed, raw
        time.sleep(1.5 * (attempt + 1))
    return status, parsed, raw


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
    if not isinstance(body, dict):
        return {}
    inner = body.get("snapshot")
    if isinstance(inner, dict) and inner.get("matchId"):
        return inner
    if body.get("matchId"):
        return body
    return inner if isinstance(inner, dict) else {}


def you_of(body: dict) -> dict:
    you = snap_of(body).get("you") or {}
    return you if isinstance(you, dict) else {}


def enemy_of(body: dict) -> dict:
    enemy = snap_of(body).get("enemy") or {}
    return enemy if isinstance(enemy, dict) else {}


def result_of(body: dict) -> dict:
    res = body.get("result") if isinstance(body, dict) else None
    return res if isinstance(res, dict) else {}


def kind_at(body: dict, q: int, r: int) -> str:
    for row in snap_of(body).get("terrain") or []:
        if isinstance(row, dict) and int(row.get("q", -1)) == q and int(row.get("r", -1)) == r:
            return str(row.get("type") or "")
    return ""


def close(got, want: float) -> bool:
    try:
        return abs(float(got) - want) < 1e-6
    except (TypeError, ValueError):
        return False


def miss_hex(a: dict, b: dict) -> dict:
    for q in range(9):
        for r in range(7):
            if (q, r) != (a["q"], a["r"]) and (q, r) != (b["q"], b["r"]):
                return {"q": q, "r": r}
    return {"q": 0, "r": 0}


def act(match_id: str, token: str, body: dict):
    return req_retry("POST", f"/matches/{match_id}/actions", body, token)


def end_turn(match_id: str, token: str):
    return act(match_id, token, {"type": "end_turn", "exposurePct": 50})


def seat_pair(player_token: str, aq: int, ar: int, bq: int, br: int):
    seated = sit_created_pvp(req_retry, player_token)
    if not seated.get("ok"):
        return None
    match_id = str(seated.get("matchId", ""))
    token_a = str(seated.get("token_a") or "")
    token_b = str(seated.get("token_b") or "")
    if not token_a or not token_b:
        return None
    act(match_id, token_a, {"type": "select_hex", "hex": {"q": aq, "r": ar}})
    status_b, _drop, _ = act(match_id, token_b, {"type": "select_hex", "hex": {"q": bq, "r": br}})
    if status_b != 200:
        return None
    _, view_a, _ = req_retry("GET", f"/matches/{match_id}", None, token_a)
    _, view_b, _ = req_retry("GET", f"/matches/{match_id}", None, token_b)
    landed_a = you_of(view_a).get("hex") if isinstance(you_of(view_a).get("hex"), dict) else {}
    landed_b = you_of(view_b).get("hex") if isinstance(you_of(view_b).get("hex"), dict) else {}
    if landed_a:
        aq, ar = int(landed_a.get("q", aq)), int(landed_a.get("r", ar))
    if landed_b:
        bq, br = int(landed_b.get("q", bq)), int(landed_b.get("r", br))
    return {
        "matchId": match_id,
        "token_a": token_a,
        "token_b": token_b,
        "aq": aq,
        "ar": ar,
        "bq": bq,
        "br": br,
        "view_a": view_a,
        "view_b": view_b,
        "kind_a": kind_at(view_a, aq, ar),
        "kind_b": kind_at(view_b, bq, br),
        "hg_a": you_of(view_a).get("highGroundActive"),
        "hg_b": you_of(view_b).get("highGroundActive"),
    }


def hunt_one(player_token: str, kind_a: str, kind_b: str, cap: int = 24):
    """Seat until A stands on kind_a and B stands on kind_b. None if the cap hits."""
    tries = 0
    b_spots = [(8, 6), (7, 5), (0, 0), (5, 3), (1, 6), (3, 1)]
    for r in range(7):
        for q in range(9):
            for bq, br in b_spots:
                if (q, r) == (bq, br):
                    continue
                if tries >= cap:
                    note(f"no {kind_a}/{kind_b} board in {cap} tries")
                    return None
                tries += 1
                bag = seat_pair(player_token, q, r, bq, br)
                if not bag:
                    note(f"hunt {tries} seat failed {q},{r} vs {bq},{br}")
                    continue
                if "smokeAvailable" not in you_of(bag["view_a"]):
                    note("LIVE snapshot omits you.smokeAvailable")
                    return {"missing": True}
                if bag["kind_a"] == kind_a and bag["kind_b"] == kind_b:
                    print(f"HUNT  {kind_a}/{kind_b} A {bag['aq']},{bag['ar']} B {bag['bq']},{bag['br']} {bag['matchId']}")
                    return bag
    note(f"no {kind_a}/{kind_b} board in {tries} tries")
    return None


def main() -> int:
    print("SMOKE_BASE", BASE)
    status, health, _ = req_retry("GET", "/health")
    expect(status == 200 and health.get("ok") is True, "GET /health", str(health)[:180])

    status, player, _ = req_retry("POST", "/players", {})
    token = str(player.get("token") or "")
    expect(status in (200, 201) and token != "", "POST /players", str(player)[:180])
    if not token:
        print("LIVE_SMOKE_ABILITY_FAIL")
        return 1

    # Smoke before anyone has placed. Do this before the hunt so a later seat error
    # cannot erase the gate.
    seated = sit_created_pvp(req_retry, token)
    expect(bool(seated.get("ok")), "S1 fresh match seated", str(seated.get("error") or seated.get("status")))
    if seated.get("ok"):
        status, parked, _ = act(str(seated["matchId"]), str(seated["token_a"]), {"type": "smoke"})
        expect(
            result_of(parked).get("reason") == "match is not active",
            "S1 smoke before the hunt is active",
            str(result_of(parked)),
        )

    ho = hunt_one(token, "hard", "open")
    if ho and ho.get("missing"):
        note("smoke fields absent — bind stays fail-closed")
        print("LIVE_SMOKE_ABILITY_PENDING")
        return 0
    expect(ho is not None, "hunted HARD/OPEN")
    if not ho:
        print("LIVE_SMOKE_ABILITY_FAIL")
        return 1

    # Shoot the real HARD board before a disconnect grace can end the idle hunt.
    status, real, _ = act(
        ho["matchId"],
        ho["token_a"],
        {"type": "attack", "hex": {"q": ho["bq"], "r": ho["br"]}},
    )
    real_res = result_of(real)
    print("HARD_OCCUPY", json.dumps(real_res))
    expect(close(real_res.get("hitChance"), 1.0), "S3 real HARD hitChance 1", str(real_res))
    expect(real_res.get("highGroundApplied") is True, "S3 real HARD highGroundApplied", str(real_res))
    expect(you_of(real).get("smokeActive") is False, "S3 real HARD did not invent smoke")
    expect(you_of(real).get("highGroundActive") is True, "S3 real HARD flag")

    ob = hunt_one(token, "open", "brush", cap=16)
    if ob and ob.get("missing"):
        ob = None
    if ob:
        miss = miss_hex({"q": ob["aq"], "r": ob["ar"]}, {"q": ob["bq"], "r": ob["br"]})
        status, brushed_miss, _ = act(ob["matchId"], ob["token_a"], {"type": "attack", "hex": miss})
        print("BRUSH_MISS", status, json.dumps(result_of(brushed_miss)))
        end_turn(ob["matchId"], ob["token_a"])
        status, brushed_smoke, _ = act(ob["matchId"], ob["token_b"], {"type": "smoke"})
        print("BRUSH_SMOKE", status, json.dumps(result_of(brushed_smoke)))
        end_turn(ob["matchId"], ob["token_b"])
        _, pre_brush, _ = req("GET", f"/matches/{ob['matchId']}", None, ob["token_a"])
        expect(enemy_of(pre_brush).get("smokeActive") is True, "S4 enemy smoke before the brush shot")
        expect(snap_of(pre_brush).get("status") == "active", "S4 brush hunt still active")
        status, covered, _ = act(
            ob["matchId"],
            ob["token_a"],
            {"type": "attack", "hex": {"q": ob["bq"], "r": ob["br"]}},
        )
        cov = result_of(covered)
        print("BRUSH_OCCUPY", json.dumps(cov))
        expect(cov.get("coverApplied") is True, "S4 brush cover still applies", str(cov))
        expect(close(cov.get("hitChance"), 0.8), "S4 brush hitChance 0.80", str(cov))
        expect(cov.get("highGroundApplied") is False, "S4 brush smoke is not HIGH GROUND", str(cov))
    else:
        note("no OPEN→BRUSH board in this hunt; brush −0.10 was checked on an earlier LIVE pass")

    # S1 — once, exact result, enemy flag, no reveal. Both drops already left the hunt active.
    oo = hunt_one(token, "open", "open")
    expect(oo is not None and not (oo or {}).get("missing"), "hunted OPEN/OPEN")
    if not oo or oo.get("missing"):
        print("LIVE_SMOKE_ABILITY_FAIL")
        return 1
    _, started, _ = req("GET", f"/matches/{oo['matchId']}", None, oo["token_a"])
    before = you_of(started)
    marks = before.get("marks")
    expect(before.get("smokeAvailable") is True, "S1 smokeAvailable true")
    expect(before.get("smokeActive") is False, "S1 smokeActive false")
    expect(before.get("highGroundActive") is False, "S1 OPEN is not HIGH GROUND")
    expect(before.get("decoyAvailable") is True, "S4 decoy available before smoke")
    expect(snap_of(started).get("uavAvailable") is True, "S4 UAV available before smoke")
    expect(before.get("exposurePct") == 50, "S5 exposurePct 50 before smoke", str(before.get("exposurePct")))
    expect(before.get("exposureFloor") == 50, "S5 exposureFloor 50 before smoke", str(before.get("exposureFloor")))

    status, off, _ = act(oo["matchId"], oo["token_b"], {"type": "smoke"})
    expect(result_of(off).get("reason") == "not your turn", "S1 off-turn", str(result_of(off)))

    status, cast, _ = act(
        oo["matchId"],
        oo["token_a"],
        {"type": "smoke", "hex": {"q": 0, "r": 0}},
    )
    cast_you = you_of(cast)
    expect(status == 200 and cast.get("ok") is True, "S1 smoke accepted")
    expect(result_of(cast) == {"type": "smoke"}, "S1 result is exactly { type: smoke }", str(result_of(cast)))
    expect(snap_of(cast).get("phase") == "await_end_turn", "S1 phase await_end_turn")
    expect(cast_you.get("smokeAvailable") is False, "S1 smokeAvailable false")
    expect(cast_you.get("smokeActive") is True, "S1 smokeActive true")
    expect(cast_you.get("highGroundActive") is False, "S3 smoke does not light HIGH GROUND")
    expect(cast_you.get("decoyAvailable") is True and cast_you.get("decoyRemaining") == 1, "S4 decoy untouched")
    expect(snap_of(cast).get("uavAvailable") is True, "S4 UAV untouched")
    expect(cast_you.get("marks") == marks, "S4 marks untouched", str(cast_you.get("marks")))
    expect(cast_you.get("exposurePct") == 50 and cast_you.get("exposureFloor") == 50, "S5 floor untouched on cast")
    expect(enemy_of(cast).get("visibleHex") is None, "S1 cast does not reveal")

    _, bview, _ = req("GET", f"/matches/{oo['matchId']}", None, oo["token_b"])
    expect(enemy_of(bview).get("smokeActive") is True, "S1 enemy.smokeActive")
    expect(you_of(bview).get("smokeAvailable") is True, "S4 rival charge untouched")
    expect(enemy_of(bview).get("visibleHex") is None, "S1 enemy.visibleHex stays null")

    _, again, _ = act(oo["matchId"], oo["token_a"], {"type": "smoke"})
    expect(result_of(again).get("reason") == "awaiting end_turn", "S1 second cast waits", str(result_of(again)))

    # S2 — decoy clock, and spot −20 while the puff is up.
    status, planted, _ = end_turn(oo["matchId"], oo["token_a"])
    expect(you_of(planted).get("smokeActive") is True, "S2 planting end keeps the puff")
    expect(you_of(planted).get("exposureFloor") == 50, "S5 floor stays 50 on planting end")
    status, recon, _ = act(
        oo["matchId"],
        oo["token_b"],
        {"type": "recon", "hex": {"q": oo["aq"], "r": oo["ar"]}},
    )
    expect(result_of(recon).get("spotChance") == 15, "S2 smoked spotChance 15", str(result_of(recon)))
    expect(enemy_of(recon).get("smokeActive") is True, "S2 recon sees enemy.smokeActive")
    # Smoke does not publish the secret hex. A successful spot may.
    if result_of(recon).get("spotted") is True:
        expect(enemy_of(recon).get("visibleHex") is not None, "S2 a real spot may name the hex")
    else:
        expect(enemy_of(recon).get("visibleHex") is None, "S2 smoke itself does not reveal the hex")
    status, bend, _ = end_turn(oo["matchId"], oo["token_b"])
    expect(status == 200 and bend.get("ok") is True, "S2 enemy end_turn")
    _, still, _ = req("GET", f"/matches/{oo['matchId']}", None, oo["token_a"])
    expect(you_of(still).get("smokeActive") is True, "S2 still live after the enemy turn")
    expect(snap_of(still).get("whoseTurn") == "a", "S2 caster's next window")

    empty = miss_hex({"q": oo["aq"], "r": oo["ar"]}, {"q": oo["bq"], "r": oo["br"]})
    status, tick, _ = act(oo["matchId"], oo["token_a"], {"type": "attack", "hex": empty})
    expect(you_of(tick).get("smokeActive") is True, "S2 still live on the next action")
    status, cleared, _ = end_turn(oo["matchId"], oo["token_a"])
    expect(you_of(cleared).get("smokeActive") is False, "S2 cleared on the next own end_turn")
    expect(you_of(cleared).get("smokeAvailable") is False, "S2 charge stays spent")
    expect(you_of(cleared).get("exposureFloor") == 50, "S5 floor stays 50 after expiry")
    act(oo["matchId"], oo["token_b"], {"type": "attack", "hex": empty})
    end_turn(oo["matchId"], oo["token_b"])
    _, denied, _ = act(oo["matchId"], oo["token_a"], {"type": "smoke"})
    expect(result_of(denied).get("reason") == "smoke already used", "S1 smoke already used", str(result_of(denied)))

    # Spot 35 on a fresh OPEN defender, then no-stack 15 on real HARD.
    # The hunted OPEN/HARD board is B on HARD. A separate OPEN pair is the clock match,
    # already smoked. Use HARD defender for the 15-no-stack gate, and the brush or a
    # dedicated recon only when we still have an unsmoeked OPEN defender.
    # Baseline 35: A's first recon of B on the occupy board, before anyone smokes.
    # That board is spent for occupy, so occupy uses a path that smokes first on oh? 
    # Occupy needs B OPEN. Clock match is already mid-game. Seat one more OPEN/OPEN.
    extra = hunt_one(token, "open", "open")
    expect(extra is not None and not (extra or {}).get("missing"), "hunted a second OPEN/OPEN for spot 35 and occupy")
    if extra and not extra.get("missing"):
        status, base_recon, _ = act(
            extra["matchId"],
            extra["token_a"],
            {"type": "recon", "hex": {"q": extra["bq"], "r": extra["br"]}},
        )
        expect(result_of(base_recon).get("spotChance") == 35, "S2 OPEN spotChance 35", str(result_of(base_recon)))
        end_turn(extra["matchId"], extra["token_a"])
        gap = miss_hex({"q": extra["aq"], "r": extra["ar"]}, {"q": extra["bq"], "r": extra["br"]})
        act(extra["matchId"], extra["token_b"], {"type": "attack", "hex": gap})
        end_turn(extra["matchId"], extra["token_b"])
        act(extra["matchId"], extra["token_a"], {"type": "smoke"})
        end_turn(extra["matchId"], extra["token_a"])
        miss = miss_hex({"q": extra["aq"], "r": extra["ar"]}, {"q": extra["bq"], "r": extra["br"]})
        act(extra["matchId"], extra["token_b"], {"type": "attack", "hex": miss})
        end_turn(extra["matchId"], extra["token_b"])
        _, live, _ = req("GET", f"/matches/{extra['matchId']}", None, extra["token_a"])
        expect(you_of(live).get("smokeActive") is True, "S3 puff live before occupy")
        expect(you_of(live).get("highGroundActive") is False, "S3 smoker is not HIGH GROUND")
        status, shot, _ = act(
            extra["matchId"],
            extra["token_a"],
            {"type": "attack", "hex": {"q": extra["bq"], "r": extra["br"]}},
        )
        got = result_of(shot)
        print("SMOKE_OCCUPY", json.dumps(got))
        expect(status == 200 and shot.get("ok") is True, "S3 occupy accepted")
        expect(close(got.get("hitChance"), 0.9), "S3 hitChance 0.90", str(got))
        expect(got.get("highGroundApplied") is False, "S3 highGroundApplied false", str(got))
        expect(got.get("coverApplied") is False, "S3 coverApplied false on OPEN", str(got))
        expect(you_of(shot).get("highGroundActive") is False, "S3 snapshot HG stays false")

    # S2 no stack: real HARD defender is already 15, smoke does not subtract again.
    oh = hunt_one(token, "open", "hard")
    expect(oh is not None and not (oh or {}).get("missing"), "hunted OPEN/HARD")
    if not oh or oh.get("missing"):
        print("LIVE_SMOKE_ABILITY_FAIL")
        return 1
    miss = miss_hex({"q": oh["aq"], "r": oh["ar"]}, {"q": oh["bq"], "r": oh["br"]})
    status, oh_miss, _ = act(oh["matchId"], oh["token_a"], {"type": "attack", "hex": miss})
    print("HARD_MISS", status, json.dumps(result_of(oh_miss)))
    if result_of(oh_miss).get("kill") is True or oh_miss.get("ok") is not True:
        expect(False, "S2 miss before the HARD defender smokes", str(result_of(oh_miss) or oh_miss)[:240])
    else:
        end_turn(oh["matchId"], oh["token_a"])
        status, bsmoke, _ = act(oh["matchId"], oh["token_b"], {"type": "smoke"})
        expect(you_of(bsmoke).get("smokeActive") is True, "S2 HARD defender smokeActive", str(result_of(bsmoke)))
        expect(you_of(bsmoke).get("highGroundActive") is True, "S3 defender HARD stays HIGH GROUND")
        expect(you_of(bsmoke).get("exposurePct") == 50 and you_of(bsmoke).get("exposureFloor") == 50, "S5 HARD doll floor 50")
        end_turn(oh["matchId"], oh["token_b"])
        status, stacked, _ = act(
            oh["matchId"],
            oh["token_a"],
            {"type": "recon", "hex": {"q": oh["bq"], "r": oh["br"]}},
        )
        expect(result_of(stacked).get("spotChance") == 15, "S2 HARD+smoke spotChance stays 15", str(result_of(stacked)))
        expect(enemy_of(stacked).get("smokeActive") is True, "S2 stacked recon sees enemy smoke")

    # Practice still publishes the charge and does not pay Marks.
    _, human, _ = req("POST", "/players", {})
    ptoken = str(human.get("token") or "")
    status, practice, _ = req("POST", "/matches", {"mode": "practice"}, ptoken)
    expect(practice.get("mode") == "practice", "S4 practice mode", str(practice)[:180])
    pjoin = str(practice.get("joinToken") or "")
    pmid = str(practice.get("matchId") or "")
    if pmid and pjoin:
        _, ready, _ = req("GET", f"/matches/{pmid}", None, pjoin)
        expect(you_of(ready).get("smokeAvailable") is True, "S4 practice smokeAvailable")
        expect(you_of(ready).get("smokeActive") is False, "S4 practice smokeActive false")
        expect(enemy_of(ready).get("isBot") is True, "S4 practice rival is the bot")
        # Practice reveals a cell on select. If that drop locks, seat a fresh bot match.
        camp = None
        scan_id, scan_join = pmid, pjoin
        tries = 0
        for q in range(9):
            for r in range(7):
                if tries >= 24:
                    break
                tries += 1
                status_d, dropped, _ = act(scan_id, scan_join, {"type": "select_hex", "hex": {"q": q, "r": r}})
                landed = you_of(dropped).get("hex") if isinstance(you_of(dropped).get("hex"), dict) else {}
                moved = int(landed.get("q", -1)) == q and int(landed.get("r", -1)) == r
                if status_d == 200 and moved and you_of(dropped).get("highGroundActive") is False and kind_at(dropped, q, r) == "open":
                    camp = {"q": q, "r": r}
                    pmid, pjoin = scan_id, scan_join
                    break
                if not moved:
                    status_p, nxt, _ = req("POST", "/matches", {"mode": "practice"}, ptoken)
                    if nxt.get("mode") != "practice":
                        break
                    scan_id = str(nxt.get("matchId") or "")
                    scan_join = str(nxt.get("joinToken") or "")
                    if not scan_id or not scan_join:
                        break
            if camp or tries >= 24:
                break
        if camp:
            status, psmoke, _ = act(pmid, pjoin, {"type": "smoke"})
            expect(psmoke.get("ok") is True, "S4 practice smoke ok", str(result_of(psmoke)))
            expect(you_of(psmoke).get("smokeActive") is True, "S4 practice smokeActive")
            expect(you_of(psmoke).get("marks") == 0, "S4 practice smoke spends no Marks")
            _, pclosed, _ = end_turn(pmid, pjoin)
            expect(you_of(pclosed).get("smokeActive") is True, "S4 practice planting end keeps the puff")
            expect(you_of(pclosed).get("exposurePct") == 50, "S5 practice exposurePct 50")
            expect(snap_of(pclosed).get("winner") is None, "S4 practice smoke does not end the hunt")
        else:
            note("practice board had no OPEN camp in the first four columns")

    print(f"PASS_N {PASS_N} FAIL_N {len(FAILS)}")
    if FAILS:
        print("LIVE_SMOKE_ABILITY_FAIL")
        return 1
    print("LIVE_SMOKE_ABILITY_OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
