#!/usr/bin/env python3
"""LIVE Practice hunt smoke (P1–P6) against glassline-api.

POST /matches { mode: "practice" } with a durable player Bearer.
The create envelope is seat A + joinToken only. Mode and enemy.isBot
live on the snapshot. If that snapshot is not practice + bot, stop.
Never sit a PvP match and never play it for Marks.

  GLASSLINE_API_BASE=https://glassline-api.vercel.app python3 tools/live_practice_smoke.py
"""

from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.request

BASE = os.environ.get("GLASSLINE_API_BASE", "https://glassline-api.vercel.app").rstrip("/")
BOT = (8, 6)
DIRS = ((1, 0), (1, -1), (0, -1), (-1, 0), (-1, 1), (0, 1))
FAILS: list[str] = []
NOTES: list[str] = []
EVIDENCE: dict = {}
GATES: dict[str, dict] = {}


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
    if cond:
        print(f"PASS  {label}")
        return
    FAILS.append(label)
    extra = f"  {detail}" if detail else ""
    print(f"FAIL  {label}{extra}")


def note(msg: str) -> None:
    NOTES.append(msg)
    print(f"NOTE  {msg}")


def gate(name: str, ok: bool, detail: str) -> None:
    GATES[name] = {"ok": ok, "detail": detail}
    expect(ok, name, detail)


def marks_of(body: dict) -> int | None:
    if not isinstance(body, dict):
        return None
    you = body.get("you") if isinstance(body.get("you"), dict) else {}
    if "marks" in you:
        return int(you["marks"])
    snap = body.get("snapshot") if isinstance(body.get("snapshot"), dict) else {}
    you_snap = snap.get("you") if isinstance(snap.get("you"), dict) else {}
    if "marks" in you_snap:
        return int(you_snap["marks"])
    if "marks" in body:
        return int(body["marks"])
    return None


def snap_of(body: dict) -> dict:
    if not isinstance(body, dict):
        return {}
    posted = body.get("snapshot")
    if isinstance(posted, dict) and (posted.get("matchId") or posted.get("mode") or posted.get("kind") or posted.get("status")):
        return posted
    if body.get("matchId") or body.get("status"):
        return body
    return {}


def mode_of(body: dict) -> str:
    if not isinstance(body, dict):
        return ""
    return str(body.get("mode") or body.get("kind") or "")


def enemy_bot(snap: dict) -> bool:
    enemy = snap.get("enemy") if isinstance(snap.get("enemy"), dict) else {}
    return enemy.get("isBot") is True


def practice_snap(snap: dict) -> bool:
    if not snap:
        return False
    kind = str(snap.get("kind") or "")
    mode = str(snap.get("mode") or snap.get("matchMode") or "")
    if kind and mode and kind != mode:
        return False
    named = kind or mode
    return named == "practice" and enemy_bot(snap)


def write_log(payload: dict) -> None:
    path = os.path.join(os.path.dirname(__file__), "..", "artifacts", "live_practice_smoke.txt")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(json.dumps(payload, indent=2))
        fh.write("\n")


def finish(ok: bool) -> int:
    payload = {
        "ok": ok and not FAILS,
        "base": BASE,
        "gates": GATES,
        "fails": FAILS,
        "notes": NOTES,
        "evidence": EVIDENCE,
    }
    write_log(payload)
    print("LIVE_PRACTICE_OK" if payload["ok"] else "LIVE_PRACTICE_FAIL")
    return 0 if payload["ok"] else 1


def act(match_id: str, token: str, body: dict) -> tuple[int, dict, dict]:
    code, payload, raw = req("POST", f"/matches/{match_id}/actions", body, token)
    snap = snap_of(payload if isinstance(payload, dict) else {})
    if code not in (200, 201) or not (isinstance(payload, dict) and payload.get("ok") is True):
        note(f"{body.get('type')} {code} {raw[:180]}")
    return code, payload if isinstance(payload, dict) else {}, snap


def terrain_types(snap: dict) -> set[str]:
    found: set[str] = set()
    for cell in snap.get("terrain") or []:
        if isinstance(cell, dict) and cell.get("type"):
            found.add(str(cell["type"]))
    return found


def cell_type(snap: dict, q: int, r: int) -> str:
    for cell in snap.get("terrain") or []:
        if isinstance(cell, dict) and int(cell.get("q", -99)) == q and int(cell.get("r", -99)) == r:
            return str(cell.get("type") or "")
    return ""


def you_hex(snap: dict) -> tuple[int, int] | None:
    you = snap.get("you") if isinstance(snap.get("you"), dict) else {}
    hex_ = you.get("hex")
    if isinstance(hex_, dict) and "q" in hex_ and "r" in hex_:
        return int(hex_["q"]), int(hex_["r"])
    return None


def in_board(q: int, r: int) -> bool:
    return 0 <= q < 9 and 0 <= r < 7


def neighbors(q: int, r: int) -> list[tuple[int, int]]:
    return [(q + dq, r + dr) for dq, dr in DIRS if in_board(q + dq, r + dr)]


def shop_marks(bearer: str) -> int | None:
    code, body, _ = req("GET", "/shop/me", token=bearer)
    if code != 200:
        return None
    return marks_of(body)


def create_practice(bearer: str) -> tuple[str, str, dict]:
    code, created, raw = req("POST", "/matches", {"mode": "practice"}, bearer)
    EVIDENCE["create_status"] = code
    EVIDENCE["create_keys"] = sorted(created.keys()) if isinstance(created, dict) else []
    EVIDENCE["create_mode"] = mode_of(created)
    if code not in (200, 201) or not isinstance(created, dict):
        note(f"create {code} {raw[:180]}")
        return "", "", {}
    if "joinTokens" in created:
        note("create leaked joinTokens")
        return "", "", created
    match_id = str(created.get("matchId") or "")
    join = str(created.get("joinToken") or "")
    return match_id, join, created


def abandon_quietly(match_id: str, join: str) -> None:
    act(match_id, join, {"type": "select_hex", "hex": {"q": 0, "r": 0}})
    req("POST", f"/matches/{match_id}/abandon", token=join)


def main() -> int:
    print(f"BASE {BASE}")
    health_s, health, _ = req("GET", "/health")
    expect(health_s == 200 and health.get("ok") is True, "GET /health", f"{health_s}")
    if health_s != 200:
        return finish(False)

    player_s, player, raw = req("POST", "/players", {})
    if player_s not in (200, 201) or not player.get("token"):
        expect(False, "POST /players", f"{player_s} {raw[:160]}")
        return finish(False)
    bearer = str(player["token"])
    before = shop_marks(bearer)
    if before is None:
        before = marks_of(player)
    note(f"player marks {before}")
    EVIDENCE["marks_before"] = before

    # P4 prelude: hunt a brush bot cell so cover can apply on the occupy shot.
    match_id = ""
    join = ""
    snap: dict = {}
    bot_type = ""
    for attempt in range(8):
        mid, tok, created = create_practice(bearer)
        if mid == "" or tok == "":
            expect(False, "P1 create seat A + joinToken", str(created.get("error", created.keys())))
            return finish(False)
        if "joinTokens" in created:
            gate("P1", False, "create returned joinTokens")
            return finish(False)
        gs, got, _ = req("GET", f"/matches/{mid}", token=tok)
        snap = snap_of(got if gs == 200 else {})
        if not practice_snap(snap):
            gate("P1", False, f"snapshot not practice+bot status {gs} mode {mode_of(snap)} isBot {enemy_bot(snap)}")
            return finish(False)
        bot_type = cell_type(snap, *BOT)
        note(f"attempt {attempt + 1} bot {BOT} terrain {bot_type or 'hidden'}")
        if bot_type == "brush":
            match_id, join = mid, tok
            break
        abandon_quietly(mid, tok)
    if match_id == "":
        gate("P2", False, "no brush bot cell in 8 creates")
        return finish(False)

    EVIDENCE["matchId"] = match_id
    EVIDENCE["create_envelope_mode"] = ""
    EVIDENCE["snapshot_mode"] = str(snap.get("mode") or "")
    EVIDENCE["snapshot_kind"] = str(snap.get("kind") or "")
    EVIDENCE["enemy_isBot"] = enemy_bot(snap)
    EVIDENCE["bot_terrain"] = bot_type

    js, joined, jraw = req("POST", f"/matches/{match_id}/join", {"token": join}, bearer)
    joined_snap = snap_of(joined if isinstance(joined, dict) else {})
    gate(
        "P1",
        js == 200 and str(joined.get("seat", "")) == "a" and practice_snap(joined_snap) and "joinToken" not in joined,
        f"join {js} seat {joined.get('seat')} mode {mode_of(joined_snap)} isBot {enemy_bot(joined_snap)}",
    )
    if not GATES["P1"]["ok"]:
        note(jraw[:180])
        return finish(False)

    claim_s, claim, _ = req("POST", f"/matches/{match_id}/join", {})
    expect(claim_s == 409, "P4 empty seat claim rejected", f"{claim_s} {claim}")

    types: set[str] = set(terrain_types(snap))
    types.add(bot_type)
    saw: dict = {
        "terrain": sorted(types),
        "decoy": False,
        "recon": False,
        "uav": False,
        "exposure": None,
        "highGroundActive": False,
        "highGroundApplied": None,
        "coverApplied": None,
        "hitChance": None,
        "emptyHitChance": None,
    }

    code, dropped, snap = act(match_id, join, {"type": "select_hex", "hex": {"q": 0, "r": 0}})
    result = dropped.get("result") if isinstance(dropped.get("result"), dict) else {}
    types |= terrain_types(snap)
    if result.get("terrain"):
        types.add(str(result["terrain"]))
    drop_ok = code in (200, 201) and dropped.get("ok") is True and str(snap.get("status")) == "active"
    expect(drop_ok, "P2 drop activates", f"status {snap.get('status')} terrain {result.get('terrain')}")
    expect(practice_snap(snap), "P4 flags after drop", f"mode {mode_of(snap)} isBot {enemy_bot(snap)}")
    expect(marks_of(snap) == before, "P3 marks held on drop", f"{before} -> {marks_of(snap)}")
    me = you_hex(snap)
    you = snap.get("you") if isinstance(snap.get("you"), dict) else {}
    if you.get("highGroundActive") is True:
        saw["highGroundActive"] = True

    def spend(action: dict, move: tuple[int, int] | None = None) -> dict:
        nonlocal snap
        _c, body, nxt = act(match_id, join, action)
        if nxt:
            snap = nxt
        if str(snap.get("phase")) == "await_end_turn":
            end_body: dict = {"type": "end_turn", "exposurePct": 37}
            if move is not None:
                end_body["move"] = {"q": move[0], "r": move[1]}
            _e, ended, nxt = act(match_id, join, end_body)
            if nxt:
                snap = nxt
            if move is not None and you_hex(snap) != move:
                note(f"move {move} stayed {you_hex(snap)} {str(ended.get('error', ''))[:80]}")
        return body

    decoy_body = spend({"type": "decoy"})
    decoy_result = decoy_body.get("result") if isinstance(decoy_body.get("result"), dict) else {}
    saw["decoy"] = decoy_result.get("type") == "decoy" or bool(decoy_result.get("planted"))
    you = snap.get("you") if isinstance(snap.get("you"), dict) else {}
    saw["exposure"] = you.get("exposurePct")
    types |= terrain_types(snap)

    recon_body = spend({"type": "recon", "hex": {"q": 4, "r": 3}})
    recon_result = recon_body.get("result") if isinstance(recon_body.get("result"), dict) else {}
    saw["recon"] = recon_result.get("type") == "recon"
    types |= terrain_types(snap)

    # Walk until the snapshot says we stand on HARD. Empty attacks stay off the bot.
    visited: set[tuple[int, int]] = set()
    guard = 0
    while guard < 6 and not saw["highGroundActive"] and str(snap.get("status")) == "active":
        guard += 1
        here = you_hex(snap) or (0, 0)
        visited.add(here)
        step = None
        for nxt in neighbors(*here):
            if nxt == BOT or nxt in visited:
                continue
            step = nxt
            break
        if step is None:
            break
        if str(snap.get("phase")) not in ("await_action", ""):
            break
        spend({"type": "attack", "hex": {"q": 1, "r": 0}}, step)
        types |= terrain_types(snap)
        you = snap.get("you") if isinstance(snap.get("you"), dict) else {}
        if you.get("highGroundActive") is True:
            saw["highGroundActive"] = True
            break
        if you_hex(snap) == here:
            break

    # Empty shot: miss, no cover, no high-ground bonus.
    if str(snap.get("status")) == "active" and str(snap.get("phase")) in ("await_action", ""):
        _c, miss, snap = act(match_id, join, {"type": "attack", "hex": {"q": 3, "r": 3}})
        miss_result = miss.get("result") if isinstance(miss.get("result"), dict) else {}
        saw["emptyHitChance"] = miss_result.get("hitChance")
        if str(snap.get("phase")) == "await_end_turn":
            _e, _ended, nxt = act(match_id, join, {"type": "end_turn", "exposurePct": 37})
            if nxt:
                snap = nxt

    if str(snap.get("status")) == "active" and str(snap.get("phase")) in ("await_action", ""):
        _c, uav, snap = act(match_id, join, {"type": "uav"})
        uav_result = uav.get("result") if isinstance(uav.get("result"), dict) else {}
        saw["uav"] = uav_result.get("type") == "uav" and uav_result.get("revealed") is True
        enemy = snap.get("enemy") if isinstance(snap.get("enemy"), dict) else {}
        if isinstance(enemy.get("visibleHex"), dict):
            EVIDENCE["uav_hex"] = enemy.get("visibleHex")
        if str(snap.get("phase")) == "await_end_turn":
            _e, _ended, nxt = act(match_id, join, {"type": "end_turn", "exposurePct": 37})
            if nxt:
                snap = nxt

    you = snap.get("you") if isinstance(snap.get("you"), dict) else {}
    saw["highGroundActive"] = you.get("highGroundActive") is True or saw["highGroundActive"]
    types |= terrain_types(snap)

    # Occupy the bot. Cover applies only when that cell is brush and we stand on hard.
    if str(snap.get("status")) == "active":
        _c, shot, snap = act(match_id, join, {"type": "attack", "hex": {"q": BOT[0], "r": BOT[1]}})
        shot_result = shot.get("result") if isinstance(shot.get("result"), dict) else {}
        saw["highGroundApplied"] = shot_result.get("highGroundApplied")
        saw["coverApplied"] = shot_result.get("coverApplied")
        saw["hitChance"] = shot_result.get("hitChance")
        saw["hit"] = shot_result.get("hit")
        EVIDENCE["occupy"] = {
            "hit": shot_result.get("hit"),
            "kill": shot_result.get("kill"),
            "hitChance": shot_result.get("hitChance"),
            "highGroundApplied": shot_result.get("highGroundApplied"),
            "coverApplied": shot_result.get("coverApplied"),
            "status": snap.get("status"),
        }

    saw["terrain"] = sorted(types)
    EVIDENCE["rules"] = saw
    triad = {"open", "brush", "hard"} <= types
    rules_ok = (
        triad
        and saw["decoy"]
        and saw["recon"]
        and saw["exposure"] == 37
        and saw["highGroundActive"] is True
        and saw["highGroundApplied"] is True
        and saw["coverApplied"] is True
        and saw["hitChance"] == 0.9
        and saw["emptyHitChance"] == 0
    )
    gate(
        "P2",
        rules_ok,
        "terrain {t} decoy {d} optic {o} uav {u} exposure {e} hg {h} cover {c} chance {ch} empty {em}".format(
            t=sorted(types),
            d=saw["decoy"],
            o=saw["recon"],
            u=saw["uav"],
            e=saw["exposure"],
            h=saw["highGroundApplied"],
            c=saw["coverApplied"],
            ch=saw["hitChance"],
            em=saw["emptyHitChance"],
        ),
    )

    ended = snap
    if str(snap.get("status")) != "ended":
        # One more occupy if the first rolled a miss. Do not invent a hit.
        if str(snap.get("phase")) == "await_end_turn":
            _e, _ended, nxt = act(match_id, join, {"type": "end_turn", "exposurePct": 37})
            if nxt:
                snap = nxt
        if str(snap.get("status")) == "active":
            _c, shot, snap = act(match_id, join, {"type": "attack", "hex": {"q": BOT[0], "r": BOT[1]}})
        ended = snap

    wallet_after = marks_of(ended)
    shop_after = shop_marks(bearer)
    EVIDENCE["marks_snapshot"] = wallet_after
    EVIDENCE["marks_shop"] = shop_after
    EVIDENCE["end"] = {
        "status": ended.get("status"),
        "winner": ended.get("winner"),
        "endReason": ended.get("endReason"),
        "mode": ended.get("mode"),
        "kind": ended.get("kind"),
        "isBot": enemy_bot(ended),
        "rematch": (ended.get("rematch") or {}).get("status") if isinstance(ended.get("rematch"), dict) else ended.get("rematch"),
    }
    delta_ok = wallet_after == before and shop_after == before and practice_snap(ended)
    gate("P3", delta_ok, f"wallet {before} -> snap {wallet_after} shop {shop_after} endReason {ended.get('endReason')}")

    gate(
        "P4",
        practice_snap(ended) and str(ended.get("mode")) == "practice" and enemy_bot(ended) and claim_s == 409,
        f"mode {ended.get('mode')} isBot {enemy_bot(ended)} claim {claim_s}",
    )

    rematch_status = ""
    rematch_mode = ""
    rematch_bot = False
    if str(ended.get("status")) == "ended":
        rs, again, araw = req("POST", f"/matches/{match_id}/rematch", {"accept": True}, join)
        again_snap = snap_of(again if isinstance(again, dict) else {})
        rematch_status = str(again.get("status") or "")
        rematch_mode = mode_of(again_snap)
        rematch_bot = enemy_bot(again_snap)
        EVIDENCE["rematch"] = {
            "http": rs,
            "status": rematch_status,
            "mode": rematch_mode,
            "kind": again_snap.get("kind"),
            "isBot": rematch_bot,
            "marks": marks_of(again_snap),
            "newMatch": again.get("matchId") != match_id,
        }
        if rs != 200:
            note(araw[:180])
        # Decline is the hideout path. Do it on a fresh ended practice match.
    else:
        EVIDENCE["rematch"] = {"skipped": "match did not end"}

    # P5 hideout: forfeit (Δ0) then decline.
    mid2, tok2, _ = create_practice(bearer)
    hideout_ok = False
    if mid2 and tok2:
        act(mid2, tok2, {"type": "select_hex", "hex": {"q": 1, "r": 1}})
        fs, left, _ = req("POST", f"/matches/{mid2}/abandon", token=tok2)
        left_snap = snap_of(left if isinstance(left, dict) else {})
        ds, declined, _ = req("POST", f"/matches/{mid2}/rematch", {"accept": False}, bearer)
        shop_left = shop_marks(bearer)
        hideout_ok = (
            fs == 200
            and str(left_snap.get("status")) == "ended"
            and str(left_snap.get("endReason")) == "forfeit"
            and str(left_snap.get("mode")) == "practice"
            and marks_of(left_snap) == before
            and shop_left == before
            and ds == 200
            and str(declined.get("status")) == "declined"
        )
        EVIDENCE["hideout"] = {
            "abandon": fs,
            "endReason": left_snap.get("endReason"),
            "winner": left_snap.get("winner"),
            "mode": left_snap.get("mode"),
            "marks": marks_of(left_snap),
            "decline": ds,
            "decline_status": declined.get("status"),
            "shop": shop_left,
        }
    rematch_ok = rematch_status == "ready" and rematch_mode == "practice" and rematch_bot and (EVIDENCE.get("rematch") or {}).get("marks") == before
    gate("P5", hideout_ok and rematch_ok, f"decline {EVIDENCE.get('hideout')} rematch {EVIDENCE.get('rematch')}")

    # P6 is hideout chrome: Practice CTA and the no-Marks line before any create.
    root = os.path.join(os.path.dirname(__file__), "..")
    hideout = open(os.path.join(root, "scenes/lobby/hideout_lobby.gd"), encoding="utf-8").read()
    contract = open(os.path.join(root, "types/contract.gd"), encoding="utf-8").read()
    p6_ok = (
        "PRACTICE_CTA" in hideout
        and "PRACTICE_NO_MARKS" in hideout
        and 'No Marks. Win, lose, or leave' in contract
        and "practice_snapshot_ok" in hideout
    )
    gate("P6", p6_ok, "hideout Practice CTA + no-Marks confirm before start")

    return finish(not FAILS)


if __name__ == "__main__":
    sys.exit(main())
