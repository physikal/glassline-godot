#!/usr/bin/env python3
"""LIVE exposure gear floor smoke (E1–E5) against glassline-api.

API tip a66a8ac: you.exposureFloor is server-owned (L1–4 → 50, L5–9 → 40,
L10–14 → 30, L15+ → 20). Client tip 8ed38a5 reads that field and never posts it.

  GLASSLINE_API_BASE=https://glassline-api.vercel.app python3 tools/live_exposure_floor_smoke.py

Does not push the API repo. Forfeit wins are the published XP grant (+50).
"""

from __future__ import annotations

import json
import os
import sys
import time
import uuid
import urllib.error
import urllib.request
from collections import deque

BASE = os.environ.get("GLASSLINE_API_BASE", "https://glassline-api.vercel.app").rstrip("/")
API_TIP = "a66a8ac"
CLIENT_TIP = "8ed38a5"
ROOT = os.path.join(os.path.dirname(__file__), "..")

FAILS: list[str] = []
NOTES: list[str] = []
GATES: dict[str, dict] = {}
EVIDENCE: dict = {}
CREATES: deque[float] = deque()


def req(method: str, path: str, body=None, token: str | None = None, timeout: float = 30.0, tries: int = 6):
    data = None
    headers = {"Accept": "application/json"}
    if body is not None:
        data = json.dumps(body).encode()
        headers["Content-Type"] = "application/json"
    if token:
        headers["Authorization"] = f"Bearer {token}"
    last = (0, {"error": "no attempt"}, "")
    for attempt in range(tries):
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
                parsed = {"error": raw[:300]}
            last = (err.code, parsed, raw)
            if err.code == 429 and attempt + 1 < tries:
                time.sleep(min(20.0, 3.0 * (attempt + 1)))
                continue
            return err.code, parsed, raw
        except (urllib.error.URLError, TimeoutError, OSError) as err:
            last = (0, {"error": str(err)}, str(err))
            if attempt + 1 < tries:
                time.sleep(1.5 * (attempt + 1))
                continue
            return 0, {"error": str(err)}, str(err)
    return last


def pace_create() -> None:
    """Stay under the in-process match-create limit (20/min)."""
    now = time.time()
    while CREATES and now - CREATES[0] > 60.0:
        CREATES.popleft()
    if len(CREATES) >= 17:
        wait = 60.0 - (now - CREATES[0]) + 0.4
        note(f"pace create {wait:.1f}s ({len(CREATES)} in window)")
        time.sleep(max(0.5, wait))
    CREATES.append(time.time())


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


def you_of(snap: dict) -> dict:
    you = snap.get("you") if isinstance(snap, dict) else None
    if not isinstance(you, dict):
        posted = snap.get("snapshot") if isinstance(snap, dict) else None
        if isinstance(posted, dict):
            you = posted.get("you") if isinstance(posted.get("you"), dict) else {}
        else:
            you = {}
    keep = (
        "seat",
        "marks",
        "xp",
        "operativeLevel",
        "exposureFloor",
        "exposurePct",
        "equippedSkinId",
        "equippedDecorId",
        "equippedGunId",
        "movedLastTurn",
        "hex",
    )
    return {key: you.get(key) for key in keep if key in you}


def snap_of(body: dict) -> dict:
    if not isinstance(body, dict):
        return {}
    posted = body.get("snapshot")
    if isinstance(posted, dict) and (posted.get("matchId") or posted.get("status") or posted.get("you")):
        return posted
    if body.get("matchId") or body.get("status"):
        return body
    return {}


def level_of(xp: int) -> int:
    return 1 + int(xp) // 100


def floor_of(level: int) -> int:
    if level <= 4:
        return 50
    if level <= 9:
        return 40
    if level <= 14:
        return 30
    return 20


def attack_delta(floor: int) -> float:
    return {50: 0.0, 40: -0.05, 30: -0.10, 20: -0.15}.get(int(floor), 99.0)


def recon_delta(floor: int) -> int:
    return {50: 0, 40: -5, 30: -10, 20: -15}.get(int(floor), 99)


def close(got, want, eps: float = 0.011) -> bool:
    try:
        return abs(float(got) - float(want)) <= eps
    except (TypeError, ValueError):
        return False


def new_player() -> dict:
    code, body, raw = req("POST", "/players", {})
    if code not in (200, 201) or not body.get("token"):
        note(f"POST /players {code} {raw[:160]}")
        return {}
    return body


def create_match(bearer: str | None, mode: str | None = None) -> dict:
    pace_create()
    body = {} if mode is None else {"mode": mode}
    code, created, raw = req("POST", "/matches", body, bearer)
    if code not in (200, 201) or not isinstance(created, dict) or not created.get("matchId"):
        note(f"create {code} {raw[:180]}")
        return {}
    created["_http"] = code
    return created


def act(match_id: str, token: str, body: dict) -> tuple[int, dict, dict]:
    code, payload, raw = req("POST", f"/matches/{match_id}/actions", body, token)
    snap = snap_of(payload if isinstance(payload, dict) else {})
    if code not in (200, 201):
        note(f"{body.get('type')} {code} {raw[:160]}")
    return code, payload if isinstance(payload, dict) else {}, snap


def sit_pvp(host_bearer: str, guest_bearer: str, aq: int = 2, ar: int = 2, bq: int = 7, br: int = 5) -> dict:
    created = create_match(host_bearer)
    if not created:
        return {}
    mid = str(created["matchId"])
    ja = str(created.get("joinToken") or "")
    code_a, join_a, _ = req("POST", f"/matches/{mid}/join", {"token": ja}, host_bearer)
    code_b, join_b, raw_b = req("POST", f"/matches/{mid}/join", {}, guest_bearer)
    jb = str((join_b or {}).get("joinToken") or "")
    if code_a != 200 or code_b != 200 or not ja or not jb:
        note(f"sit join a {code_a} b {code_b} {raw_b[:120]}")
        return {}
    _, _, snap_a = act(mid, ja, {"type": "select_hex", "hex": {"q": aq, "r": ar}})
    code_b, _, snap_b = act(mid, jb, {"type": "select_hex", "hex": {"q": bq, "r": br}})
    if str(snap_b.get("status")) != "active":
        note(f"sit not active {code_b} {snap_b.get('status')}")
        return {}
    return {
        "matchId": mid,
        "token_a": ja,
        "token_b": jb,
        "snap": snap_b,
        "you_a_after_drop": you_of(snap_a),
    }


def forfeit_win(winner_bearer: str, loser_bearer: str) -> dict:
    seated = sit_pvp(winner_bearer, loser_bearer)
    if not seated:
        return {}
    code, body, snap = req("POST", f"/matches/{seated['matchId']}/abandon", token=seated["token_b"])[0:3]
    # req returns 3-tuple; slice keeps it. Re-read below if abandon used act-style.
    return {"seated": seated, "abandon_code": code, "abandon": body if isinstance(body, dict) else {}, "snap": snap_of(body if isinstance(body, dict) else {})}


def forfeit_win_clean(winner_bearer: str, loser_bearer: str) -> dict:
    seated = sit_pvp(winner_bearer, loser_bearer)
    if not seated:
        return {}
    code, body, raw = req("POST", f"/matches/{seated['matchId']}/abandon", token=seated["token_b"])
    if code != 200:
        note(f"abandon {code} {raw[:140]}")
        return {}
    gs, got, _ = req("GET", f"/matches/{seated['matchId']}", token=seated["token_a"])
    snap = got if gs == 200 else {}
    return {"matchId": seated["matchId"], "http": code, "snap": snap, "you": you_of(snap)}


def expected_hit(floor: int, high_ground: bool, cover: bool) -> float:
    chance = 0.90 + (0.10 if high_ground else 0.0) - (0.10 if cover else 0.0) + attack_delta(floor)
    return max(0.0, min(1.0, chance))


def expected_spot(floor: int, moved: bool) -> int:
    chance = 35 + (25 if moved else 0) + recon_delta(floor)
    return max(10, min(85, chance))


def band_check(defender_bearer: str, attacker_bearer: str, floor: int, label: str) -> dict:
    """Defender is seat A. Camp, then attacker recon + attack the secret."""
    seated = sit_pvp(defender_bearer, attacker_bearer)
    out = {"label": label, "floor": floor, "ok": False}
    if not seated:
        out["error"] = "sit failed"
        return out
    mid, ja, jb = seated["matchId"], seated["token_a"], seated["token_b"]
    out["matchId"] = mid
    code, miss, snap = act(mid, ja, {"type": "attack", "hex": {"q": 0, "r": 0}})
    miss_r = miss.get("result") if isinstance(miss.get("result"), dict) else {}
    out["emptyHitChance"] = miss_r.get("hitChance")
    if str(snap.get("phase")) != "await_end_turn":
        out["error"] = f"miss phase {snap.get('phase')} {code}"
        return out
    _, _, snap = act(mid, ja, {"type": "end_turn", "exposurePct": 50})
    moved = bool((snap.get("you") or {}).get("movedLastTurn")) if isinstance(snap.get("you"), dict) else True
    out["defenderMoved"] = moved
    code, recon, snap = act(mid, jb, {"type": "recon", "hex": {"q": 2, "r": 2}})
    recon_r = recon.get("result") if isinstance(recon.get("result"), dict) else {}
    out["spotChance"] = recon_r.get("spotChance")
    out["reconType"] = recon_r.get("type")
    want_spot = expected_spot(floor, moved)
    out["spotWant"] = want_spot
    if str(snap.get("phase")) == "await_end_turn":
        act(mid, jb, {"type": "end_turn", "exposurePct": 50})
    # Seat A camps again so B can shoot.
    code, _, snap = act(mid, ja, {"type": "attack", "hex": {"q": 0, "r": 1}})
    if str(snap.get("phase")) == "await_end_turn":
        act(mid, ja, {"type": "end_turn", "exposurePct": 50})
    code, shot, snap = act(mid, jb, {"type": "attack", "hex": {"q": 2, "r": 2}})
    shot_r = shot.get("result") if isinstance(shot.get("result"), dict) else {}
    out["hitChance"] = shot_r.get("hitChance")
    out["hit"] = shot_r.get("hit")
    out["highGroundApplied"] = shot_r.get("highGroundApplied")
    out["coverApplied"] = shot_r.get("coverApplied")
    out["shotType"] = shot_r.get("type")
    want_hit = expected_hit(floor, shot_r.get("highGroundApplied") is True, shot_r.get("coverApplied") is True)
    out["hitWant"] = want_hit
    out["you"] = you_of(snap)
    spot_ok = out["spotChance"] == want_spot or close(out["spotChance"], want_spot, 0.01)
    hit_ok = close(out["hitChance"], want_hit)
    empty_ok = out["emptyHitChance"] == 0 or close(out["emptyHitChance"], 0)
    out["ok"] = spot_ok and hit_ok and empty_ok and out["reconType"] == "recon"
    if not out["ok"]:
        note(f"band {label} spot {out['spotChance']} want {want_spot} hit {out['hitChance']} want {want_hit} empty {out['emptyHitChance']}")
    # Defender abandons if the shot did not end the match, so this probe cannot
    # grant the operative a forfeit win (+50 XP) and move the floor early.
    if str(snap.get("status")) != "ended":
        req("POST", f"/matches/{mid}/abandon", token=ja)
    return out


def practice_probe(bearer: str) -> dict:
    created = create_match(bearer, "practice")
    out: dict = {"ok": False}
    if not created:
        out["error"] = "create failed"
        return out
    mid = str(created["matchId"])
    join = str(created.get("joinToken") or "")
    out["matchId"] = mid
    gs, got, _ = req("GET", f"/matches/{mid}", token=join)
    snap = got if gs == 200 else {}
    before = you_of(snap)
    out["before"] = before
    out["mode"] = snap.get("mode")
    out["kind"] = snap.get("kind")
    out["isBot"] = ((snap.get("enemy") or {}) if isinstance(snap.get("enemy"), dict) else {}).get("isBot")
    act(mid, join, {"type": "select_hex", "hex": {"q": 1, "r": 1}})
    ended = {}
    you = {}
    for _ in range(4):
        code, shot, snap = act(mid, join, {"type": "attack", "hex": {"q": 8, "r": 6}})
        result = shot.get("result") if isinstance(shot.get("result"), dict) else {}
        out["lastAttack"] = {
            "hit": result.get("hit"),
            "kill": result.get("kill"),
            "hitChance": result.get("hitChance"),
            "status": snap.get("status"),
        }
        if str(snap.get("status")) == "ended":
            ended = snap
            you = you_of(snap)
            break
        if str(snap.get("phase")) == "await_end_turn":
            # Client percent must not stick. Floor stays the server value.
            _, ended_body, snap = act(mid, join, {"type": "end_turn", "exposurePct": 37, "exposureFloor": 20})
            you = you_of(snap)
            out["afterIntent"] = you
            if str(snap.get("status")) == "ended":
                ended = snap
                break
        else:
            break
    if not ended:
        code, left, _ = req("POST", f"/matches/{mid}/abandon", token=join)
        ended = snap_of(left if isinstance(left, dict) else {})
        you = you_of(ended)
        out["abandoned"] = code
    out["after"] = you
    out["endReason"] = ended.get("endReason")
    out["status"] = ended.get("status")
    xp_same = you.get("xp") == before.get("xp") == 0
    marks_same = you.get("marks") == before.get("marks")
    floor_same = you.get("exposureFloor") == before.get("exposureFloor") == 50
    pct_is_floor = you.get("exposurePct") == you.get("exposureFloor")
    intent = out.get("afterIntent") or {}
    intent_ignored = (not intent) or (
        intent.get("exposureFloor") == 50 and intent.get("exposurePct") == 50
    )
    out["ok"] = bool(xp_same and marks_same and floor_same and pct_is_floor and intent_ignored and out["isBot"] is True)
    return out


def job_probe(bearer: str) -> dict:
    pace_create()
    code, job, raw = req("POST", "/jobs", {"tier": 1}, bearer)
    out: dict = {"http": code}
    if code not in (200, 201) or not isinstance(job, dict) or not job.get("matchId"):
        out["error"] = raw[:160]
        out["ok"] = False
        return out
    mid = str(job["matchId"])
    token = str(job.get("joinToken") or "")
    before = you_of(job.get("snapshot") or {})
    out["before"] = before
    out["matchId"] = mid
    act(mid, token, {"type": "select_hex", "hex": {"q": 1, "r": 1}})
    _, uav, snap = act(mid, token, {"type": "uav"})
    vis = ((snap.get("enemy") or {}) if isinstance(snap.get("enemy"), dict) else {}).get("visibleHex")
    if str(snap.get("phase")) == "await_end_turn":
        act(mid, token, {"type": "end_turn", "exposurePct": 50})
    target = vis if isinstance(vis, dict) else {"q": 8, "r": 6}
    ended = {}
    for _ in range(3):
        _, shot, snap = act(mid, token, {"type": "attack", "hex": target})
        if str(snap.get("status")) == "ended":
            ended = snap
            break
        enemy = snap.get("enemy") if isinstance(snap.get("enemy"), dict) else {}
        if isinstance(enemy.get("visibleHex"), dict):
            target = enemy["visibleHex"]
        if str(snap.get("phase")) == "await_end_turn":
            act(mid, token, {"type": "end_turn", "exposurePct": 50})
    you = you_of(ended or snap)
    if str((ended or snap).get("status")) != "ended":
        code_left, left, _ = req("POST", f"/matches/{mid}/abandon", token=token)
        if code_left == 200:
            ended = snap_of(left if isinstance(left, dict) else {}) or ended
            you = you_of(ended) or you
            out["abandoned"] = code_left
    out["after"] = you
    out["endReason"] = (ended or snap).get("endReason")
    out["kind"] = (ended or snap).get("kind")
    won = str((ended or {}).get("endReason")) == "kill" and str((ended or {}).get("winner")) in ("a", "A", str((you or {}).get("seat")))
    xp_held = you.get("xp") == before.get("xp") == 0
    floor_held = you.get("exposureFloor") == 50
    marks_ok = (you.get("marks") == (before.get("marks") or 0) + 10) if won else (you.get("xp") == 0)
    out["won"] = won
    out["ok"] = bool(xp_held and floor_held and (marks_ok if won else xp_held))
    if not won:
        out["ok"] = bool(xp_held and floor_held)
        note(f"job did not end in a kill; xp stayed {you.get('xp')}")
    return out


def read(rel: str) -> str:
    path = os.path.join(ROOT, rel)
    with open(path, encoding="utf-8") as fh:
        return fh.read()


def client_audit() -> dict:
    intent = read("types/action_intent.gd")
    screen = read("scenes/match/match_screen.gd")
    doll = read("scenes/match/exposure_doll.gd")
    contract = read("types/contract.gd")
    snap = read("types/snapshot.gd")
    end = intent.split("static func end_turn", 1)[-1].split("static func", 1)[0]
    on_end = screen.split("func _on_end_turn", 1)[-1].split("\nfunc ", 1)[0]
    bind = screen.split("func _bind_server_exposure", 1)[-1].split("\nfunc ", 1)[0]
    findings = {
        "end_turn_posts_exposurePct": '"exposurePct"' in end,
        # Comment may name the field. The posted dict must not.
        "end_turn_omits_exposureFloor": '"exposureFloor"' not in end and "'exposureFloor'" not in end,
        "end_turn_omits_operativeLevel": "operativeLevel" not in end,
        "on_end_clamps": "clamp_exposure_intent" in on_end,
        "on_end_uses_intent": "ActionIntent.end_turn" in on_end,
        "slider_min_is_floor": "_exposure.min_value = float(floor)" in bind,
        "slider_not_hardcoded_zero": "min_value = 0" not in screen,
        "doll_binds_floor": "func bind_floor" in doll and "exposure_floor_or_start" in doll,
        "doll_label_template": 'const EXPOSURE_FLOOR_LABEL := "Exposure %d%%"' in contract,
        "fail_closed_start": "const EXPOSURE_FLOOR_START := 50" in contract,
        "snapshot_reads_you_floor": 'you_state.has("exposureFloor")' in snap,
        "recon_base_035": "const RECON_BASE := 0.35" in contract,
        "attack_base_090": "const BASE_HIT_CHANCE := 0.90" in contract,
        "no_iap_word": "iap" not in (intent + screen + doll).lower(),
    }
    findings["ok"] = all(findings.values())
    return findings


def cosmetics(bearer: str, xp: int, floor: int, marks_before: int) -> dict:
    buy_id = str(uuid.uuid4())
    code, bought, raw = req(
        "POST",
        "/shop/buy",
        {"itemId": "skin_hideout_stub", "clientBuyId": buy_id},
        bearer,
    )
    out: dict = {"buy": code, "buyId": buy_id}
    you = (bought.get("you") if isinstance(bought, dict) else None) or {}
    out["buyYou"] = {k: you.get(k) for k in ("marks", "equippedSkinId", "equippedGunId", "xp", "exposureFloor", "operativeLevel") if isinstance(you, dict)}
    if code not in (200, 201) or bought.get("ok") is not True:
        out["error"] = raw[:180]
        out["ok"] = False
        return out
    eq, equipped, raw_e = req("POST", "/shop/equip", {"itemId": "skin_hideout_stub"}, bearer)
    gun, gunned, _ = req("POST", "/shop/equip", {"itemId": "gun_fieldbolt"}, bearer)
    out["equip"] = eq
    out["gun"] = gun
    # Replay the same buy id — must not debit again.
    replay, replayed, _ = req(
        "POST",
        "/shop/buy",
        {"itemId": "skin_hideout_stub", "clientBuyId": buy_id},
        bearer,
    )
    out["replay"] = replay
    shop_s, shop, _ = req("GET", "/shop/me", token=bearer)
    out["shop"] = shop if shop_s == 200 else {"http": shop_s}
    seated = sit_pvp(bearer, new_player().get("token") or "")
    if not seated:
        # Guest create can fail if new_player returned empty; try once more inside sit.
        out["ok"] = False
        out["error"] = "post-equip sit failed"
        return out
    gs, got, _ = req("GET", f"/matches/{seated['matchId']}", token=seated["token_a"])
    snap = got if gs == 200 else {}
    brief = you_of(snap)
    out["matchYou"] = brief
    out["matchId"] = seated["matchId"]
    # Host abandon is a forfeit loss: XP stays, so the floor probe is not a grant.
    if str(snap.get("status")) != "ended":
        req("POST", f"/matches/{seated['matchId']}/abandon", token=seated["token_a"])
    marks_after = brief.get("marks")
    out["ok"] = bool(
        brief.get("exposureFloor") == floor
        and brief.get("exposurePct") == floor
        and brief.get("xp") == xp
        and brief.get("operativeLevel") == level_of(xp)
        and brief.get("equippedSkinId") == "skin_hideout_stub"
        and brief.get("equippedGunId") == "gun_fieldbolt"
        and isinstance(marks_after, int)
        and marks_after == marks_before - 50
        and "exposureFloor" not in {"itemId": "skin_hideout_stub"}
    )
    if not out["ok"]:
        note(f"cosmetics buy {code} equip {eq} you {brief} raw {raw_e[:80]}")
    return out


def write_log(payload: dict) -> None:
    path = os.path.join(ROOT, "artifacts", "live_exposure_floor_smoke.txt")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(json.dumps(payload, indent=2, default=str))
        fh.write("\n")
    print(f"WROTE {path}")


def finish(ok: bool) -> int:
    payload = {
        "ok": ok and not FAILS,
        "base": BASE,
        "apiTip": API_TIP,
        "clientTip": CLIENT_TIP,
        "gates": GATES,
        "fails": FAILS,
        "notes": NOTES,
        "evidence": EVIDENCE,
    }
    write_log(payload)
    print("LIVE_EXPOSURE_FLOOR_OK" if payload["ok"] else "LIVE_EXPOSURE_FLOOR_FAIL")
    return 0 if payload["ok"] else 1


def main() -> int:
    print(f"BASE {BASE}")
    health_s, health, _ = req("GET", "/health")
    expect(health_s == 200 and health.get("ok") is True, "GET /health", str(health))
    if health_s != 200:
        return finish(False)

    audit = client_audit()
    EVIDENCE["client"] = audit
    gate(
        "E3_client_doll",
        audit.get("doll_binds_floor") is True
        and audit.get("doll_label_template") is True
        and audit.get("slider_min_is_floor") is True
        and audit.get("on_end_clamps") is True
        and audit.get("fail_closed_start") is True
        and audit.get("snapshot_reads_you_floor") is True
        and audit.get("recon_base_035") is True
        and audit.get("attack_base_090") is True,
        "doll bind_floor + label Exposure N% + slider min = floor; RECON 0.35 / attack 0.90 unchanged",
    )
    gate(
        "E5_client_no_post",
        audit.get("end_turn_posts_exposurePct") is True
        and audit.get("end_turn_omits_exposureFloor") is True
        and audit.get("end_turn_omits_operativeLevel") is True
        and audit.get("on_end_uses_intent") is True
        and audit.get("no_iap_word") is True
        and audit.get("slider_not_hardcoded_zero") is True,
        "end_turn posts exposurePct only; no exposureFloor, operativeLevel, or IAP",
    )

    hero = new_player()
    guest = new_player()
    if not hero or not guest:
        gate("E1", False, "POST /players failed")
        return finish(False)
    hero_pub = {k: hero.get(k) for k in ("playerId", "marks", "xp", "operativeLevel", "exposureFloor")}
    EVIDENCE["player"] = hero_pub
    print("SNIP ", json.dumps(hero_pub))
    e1_player = (
        hero.get("xp") == 0
        and hero.get("operativeLevel") == 1
        and hero.get("exposureFloor") == 50
        and hero.get("marks") == 0
    )

    # Anonymous seat (no players row) still publishes floor 50.
    anon = create_match(None)
    anon_you = {}
    if anon:
        mid = str(anon["matchId"])
        token = str(anon.get("joinToken") or "")
        js, joined, _ = req("POST", f"/matches/{mid}/join", {"token": token})
        anon_you = you_of(snap_of(joined if js == 200 else {}))
        EVIDENCE["anonymous"] = {"matchId": mid, "you": anon_you}
        print("SNIP anonymous", json.dumps(anon_you))

    seated = sit_pvp(hero["token"], guest["token"])
    if not seated:
        gate("E1", False, "PvP sit failed")
        return finish(False)
    EVIDENCE["sit"] = {"matchId": seated["matchId"], "you": you_of(seated["snap"])}
    # Seat B's snapshot is the guest. Re-read seat A.
    gs, got, _ = req("GET", f"/matches/{seated['matchId']}", token=seated["token_a"])
    live = got if gs == 200 else {}
    live_you = you_of(live)
    EVIDENCE["l1_snapshot"] = {"matchId": seated["matchId"], "you": live_you, "status": live.get("status")}
    print("SNIP L1", json.dumps(live_you))

    mid, ja = seated["matchId"], seated["token_a"]
    code, miss, snap = act(mid, ja, {"type": "attack", "hex": {"q": 0, "r": 0}})
    miss_r = miss.get("result") if isinstance(miss.get("result"), dict) else {}
    neg_code, neg, neg_snap = act(mid, ja, {"type": "end_turn", "exposurePct": -1})
    neg_reason = ""
    if isinstance(neg.get("result"), dict):
        neg_reason = str(neg["result"].get("reason") or "")
    EVIDENCE["reject_negative"] = {
        "http": neg_code,
        "ok": neg.get("ok"),
        "reason": neg_reason,
        "you": you_of(neg_snap),
        "phase": neg_snap.get("phase"),
    }
    print("SNIP end_-1", json.dumps(EVIDENCE["reject_negative"]))
    code0, end0, snap0 = act(
        mid,
        ja,
        {"type": "end_turn", "exposurePct": 0, "exposureFloor": 20, "operativeLevel": 9, "xp": 999},
    )
    you0 = you_of(snap0)
    EVIDENCE["end_zero"] = {"http": code0, "ok": end0.get("ok"), "you": you0, "phase": snap0.get("phase")}
    print("SNIP end_0", json.dumps(EVIDENCE["end_zero"]))

    # Guest turn: miss then end_turn 10. Floor must stay 50.
    code_m, _, snap_m = act(mid, seated["token_b"], {"type": "attack", "hex": {"q": 0, "r": 0}})
    if str(snap_m.get("phase")) == "await_end_turn":
        code10, end10, snap10 = act(mid, seated["token_b"], {"type": "end_turn", "exposurePct": 10})
        you10 = you_of(snap10)
    else:
        code10, end10, you10, snap10 = 0, {}, {}, snap_m
        note(f"guest miss phase {snap_m.get('phase')} {code_m}")
    EVIDENCE["end_ten"] = {"http": code10, "ok": end10.get("ok") if isinstance(end10, dict) else None, "you": you10}
    print("SNIP end_10", json.dumps(EVIDENCE["end_ten"]))
    # Close the probe as a loss so it cannot grant the operative XP.
    if str(snap10.get("status") if isinstance(snap10, dict) else "") not in ("ended",):
        req("POST", f"/matches/{mid}/abandon", token=ja)

    negative_rejected = (
        (neg.get("ok") is False or neg_code in (400, 422))
        and (neg_snap.get("phase") == "await_end_turn" or neg_code in (400, 422))
        and ("0" in neg_reason or "100" in neg_reason or "exposure" in neg_reason.lower() or neg_code in (400, 422))
    )
    e1_ok = bool(
        e1_player
        and live_you.get("exposureFloor") == 50
        and live_you.get("exposurePct") == 50
        and live_you.get("operativeLevel") == 1
        and live_you.get("xp") == 0
        and anon_you.get("exposureFloor") == 50
        and anon_you.get("exposurePct") == 50
        and miss_r.get("hitChance") == 0
        and negative_rejected
        and end0.get("ok") is True
        and you0.get("exposureFloor") == 50
        and you0.get("exposurePct") == 50
        and you0.get("operativeLevel") == 1
        and you0.get("xp") == 0
        and you10.get("exposureFloor") == 50
        and you10.get("exposurePct") == 50
    )
    gate(
        "E1",
        e1_ok,
        f"player {hero_pub} snapshot {live_you} anon {anon_you} end0 {you0} end10 {you10} neg {neg_reason}",
    )
    gate(
        "E5_server_ignores_client_floor",
        end0.get("ok") is True and you0.get("exposureFloor") == 50 and you0.get("xp") == 0 and you0.get("operativeLevel") == 1,
        f"end_turn exposurePct 0 + injected exposureFloor 20 / xp 999 stored {you0}",
    )

    # Floor 50 combat bands before any XP.
    band50 = band_check(hero["token"], guest["token"], 50, "floor50")
    EVIDENCE["band50"] = band50
    print("SNIP band50", json.dumps({k: band50.get(k) for k in ("matchId", "spotChance", "spotWant", "hitChance", "hitWant", "emptyHitChance", "highGroundApplied", "coverApplied", "ok")}))

    practice = practice_probe(hero["token"])
    EVIDENCE["practice"] = practice
    print("SNIP practice", json.dumps({k: practice.get(k) for k in ("matchId", "before", "after", "afterIntent", "endReason", "status", "isBot", "ok")}))
    gate(
        "E4_practice",
        practice.get("ok") is True,
        f"practice xp/marks/floor {practice.get('before')} -> {practice.get('after')} intent {practice.get('afterIntent')}",
    )

    job = job_probe(hero["token"])
    EVIDENCE["job"] = job
    print("SNIP job", json.dumps({k: job.get(k) for k in ("matchId", "before", "after", "endReason", "won", "ok")}))

    # Ladder. Forfeit win is +50 XP and +12 Marks. Shop spend happens at floor 50 once marks allow ghillie.
    ladder = []
    seen = {"50": False, "40": False, "30": False, "20": False}
    bands = {}
    hero_xp = 0
    cosmetics_done = False
    target = 1400
    wins = 0
    while hero_xp < target and wins < 32:
        won = forfeit_win_clean(hero["token"], guest["token"])
        if not won:
            gate("E2", False, f"forfeit failed at xp {hero_xp}")
            return finish(False)
        brief = won["you"]
        wins += 1
        hero_xp = int(brief.get("xp") or 0)
        lvl = int(brief.get("operativeLevel") or 0)
        fl = int(brief.get("exposureFloor") or -1)
        row = {
            "n": wins,
            "matchId": won["matchId"],
            "xp": hero_xp,
            "operativeLevel": lvl,
            "exposureFloor": fl,
            "exposurePct": brief.get("exposurePct"),
            "marks": brief.get("marks"),
        }
        ladder.append(row)
        print(f"LADDER {wins} xp {hero_xp} L{lvl} floor {fl} marks {brief.get('marks')}")
        if fl == floor_of(level_of(hero_xp)) and fl in (50, 40, 30, 20):
            seen[str(fl)] = True
        # Boundaries worth a combat sample: first time we land on 40, 30, 20.
        if fl in (40, 30, 20) and str(fl) not in bands and hero_xp in (400, 900, 1400):
            sample = band_check(hero["token"], guest["token"], fl, f"floor{fl}")
            bands[str(fl)] = sample
            print("SNIP band", fl, json.dumps({k: sample.get(k) for k in ("matchId", "spotChance", "spotWant", "hitChance", "hitWant", "emptyHitChance", "ok")}))
        if (not cosmetics_done) and int(brief.get("marks") or 0) >= 50 and fl == 50:
            cos = cosmetics(hero["token"], hero_xp, fl, int(brief.get("marks")))
            EVIDENCE["cosmetics"] = cos
            cosmetics_done = True
            print("SNIP cosmetics", json.dumps({k: cos.get(k) for k in ("buy", "equip", "matchId", "matchYou", "ok")}))
            # Marks on the next forfeit are independent; hero_xp is unchanged by shop.
            if cos.get("matchYou", {}).get("xp") == hero_xp:
                pass
            else:
                note(f"cosmetics moved xp {cos.get('matchYou')}")

    EVIDENCE["ladder"] = ladder
    EVIDENCE["bands"] = bands

    # Explicit replay: last match GET twice equals.
    if ladder:
        # forfeit_win_clean does not keep the join token. Do one dedicated replay match.
        replay_seat = sit_pvp(hero["token"], guest["token"])
        if replay_seat:
            req("POST", f"/matches/{replay_seat['matchId']}/abandon", token=replay_seat["token_b"])
            r1s, r1, _ = req("GET", f"/matches/{replay_seat['matchId']}", token=replay_seat["token_a"])
            r2s, r2, _ = req("GET", f"/matches/{replay_seat['matchId']}", token=replay_seat["token_a"])
            y1, y2 = you_of(r1 if r1s == 200 else {}), you_of(r2 if r2s == 200 else {})
            EVIDENCE["replay"] = {"matchId": replay_seat["matchId"], "first": y1, "second": y2}
            print("SNIP replay", json.dumps(EVIDENCE["replay"]))
        else:
            y1, y2 = {}, {"xp": "missing"}

    def row_ok(row: dict) -> bool:
        xp = int(row["xp"])
        return (
            xp == row["n"] * 50
            and row["operativeLevel"] == level_of(xp)
            and row["exposureFloor"] == floor_of(row["operativeLevel"])
            and row["exposurePct"] == row["exposureFloor"]
            and row["exposureFloor"] in (50, 40, 30, 20)
            and row["exposureFloor"] != 0
        )

    bad_rows = [row for row in ladder if not row_ok(row)]
    crossed = {
        "xp350_floor50": any(r["xp"] == 350 and r["exposureFloor"] == 50 and r["operativeLevel"] == 4 for r in ladder),
        "xp400_floor40": any(r["xp"] == 400 and r["exposureFloor"] == 40 and r["operativeLevel"] == 5 for r in ladder),
        "xp850_floor40": any(r["xp"] == 850 and r["exposureFloor"] == 40 and r["operativeLevel"] == 9 for r in ladder),
        "xp900_floor30": any(r["xp"] == 900 and r["exposureFloor"] == 30 and r["operativeLevel"] == 10 for r in ladder),
        "xp1350_floor30": any(r["xp"] == 1350 and r["exposureFloor"] == 30 and r["operativeLevel"] == 14 for r in ladder),
        "xp1400_floor20": any(r["xp"] == 1400 and r["exposureFloor"] == 20 and r["operativeLevel"] == 15 for r in ladder),
    }
    EVIDENCE["crossed"] = crossed
    replay_ok = bool(EVIDENCE.get("replay") and EVIDENCE["replay"]["first"].get("xp") == EVIDENCE["replay"]["second"].get("xp") == hero_xp + 50)
    # The dedicated replay is an extra forfeit, so xp is ladder xp + 50.
    e2_ok = bool(ladder) and not bad_rows and all(crossed.values()) and replay_ok and seen["20"]
    gate(
        "E2",
        e2_ok,
        f"steps {crossed} bad {bad_rows[:2]} replay {EVIDENCE.get('replay', {}).get('first')} -> {EVIDENCE.get('replay', {}).get('second')}",
    )

    band_ok = band50.get("ok") is True and all(bands.get(str(fl), {}).get("ok") is True for fl in (40, 30, 20))
    gate(
        "E3_bands",
        band_ok and GATES.get("E3_client_doll", {}).get("ok") is True,
        f"50 { {k: band50.get(k) for k in ('spotChance','hitChance','hitWant','ok')} } steps { {k: {kk: bands[k].get(kk) for kk in ('spotChance','hitChance','ok')} for k in bands} }",
    )

    cos = EVIDENCE.get("cosmetics") or {}
    gate(
        "E4_cosmetics",
        cos.get("ok") is True and job.get("ok") is True,
        f"shop {cos.get('matchYou')} job {job.get('after')} won {job.get('won')}",
    )

    e5_ok = (
        GATES.get("E5_client_no_post", {}).get("ok") is True
        and GATES.get("E5_server_ignores_client_floor", {}).get("ok") is True
    )
    gate("E5", e5_ok, "client omits exposureFloor; server discarded injected floor / xp")

    # Doll label is a pure function of the live floor. L1 snapshot 50 → "Exposure 50%".
    if live_you.get("exposureFloor") == 50:
        note('client doll label for this L1 snapshot is "Exposure 50%" (EXPOSURE_FLOOR_LABEL). Slider min is that floor.')
    if not any(r["exposureFloor"] != 50 for r in ladder):
        note("could not force a live floor drop; tip still is the mock capture already on 8ed38a5")
    else:
        note("live floor did drop via operative XP; one-shot tip still was captured on the mock path in 8ed38a5 (no test hook to open the Godot tip without a second account level in-client)")

    return finish(not FAILS)


if __name__ == "__main__":
    sys.exit(main())
