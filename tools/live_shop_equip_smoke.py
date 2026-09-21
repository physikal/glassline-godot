#!/usr/bin/env python3
"""LIVE equip chrome E1–E5 vs glassline-api.

Spine:
  POST /shop/equip { itemId } | { itemId: null } + durable player Bearer
  GET  /shop/me → { you: { marks, equippedSkinId }, owned }
  snapshot you.equippedSkinId — client never invents
  zero combat delta (E5 miss/kill fingerprint with vs without equip)

  GLASSLINE_API_BASE=https://glassline-api.vercel.app python3 tools/live_shop_equip_smoke.py
"""

from __future__ import annotations

import json
import os
import sys
import uuid
import urllib.error
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from live_join import sit_created_pvp

BASE = os.environ.get("GLASSLINE_API_BASE", "https://glassline-api.vercel.app").rstrip("/")
GHILLIE = "skin_hideout_stub"
BANDANA = "skin_bandana_stub"
FAILS: list[str] = []
NOTES: list[str] = []
EVIDENCE: list[str] = []


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
            parsed = {"error": raw or "http_error"}
        return err.code, parsed, raw


def expect(cond: bool, label: str, detail="") -> bool:
    if cond:
        print(f"PASS  {label}")
        return True
    FAILS.append(label)
    extra = f"  {detail}" if detail else ""
    print(f"FAIL  {label}{extra}")
    return False


def note(msg: str) -> None:
    NOTES.append(msg)
    print(f"NOTE  {msg}")


def evidence(msg: str) -> None:
    EVIDENCE.append(msg)
    print(f"EVID  {msg}")


def you_marks(bag: dict | None) -> int | None:
    if not isinstance(bag, dict):
        return None
    you = bag.get("you")
    if isinstance(you, dict) and "marks" in you:
        return int(you.get("marks") or 0)
    if "marks" in bag and not isinstance(bag.get("marks"), dict):
        return int(bag.get("marks") or 0)
    snap = bag.get("snapshot")
    if isinstance(snap, dict):
        return you_marks(snap)
    return None


def equipped_skin(bag: dict | None):
    if not isinstance(bag, dict):
        return None
    you = bag.get("you")
    if isinstance(you, dict) and "equippedSkinId" in you:
        val = you.get("equippedSkinId")
        return None if val is None else str(val)
    if "equippedSkinId" in bag:
        val = bag.get("equippedSkinId")
        return None if val is None else str(val)
    snap = bag.get("snapshot")
    if isinstance(snap, dict):
        return equipped_skin(snap)
    return None


def last_action(bag: dict | None) -> dict:
    if not isinstance(bag, dict):
        return {}
    snap = bag.get("snapshot") if isinstance(bag.get("snapshot"), dict) else bag
    last = snap.get("lastAction") if isinstance(snap, dict) else None
    return last if isinstance(last, dict) else {}


def mint_player():
    code, body, raw = req("POST", "/players", {})
    expect(code in (200, 201) and body.get("token"), "POST /players", raw[:240])
    return body


def shop_me(token: str):
    return req("GET", "/shop/me", token=token)


def buy(token: str, item_id: str, client_buy_id: str):
    return req("POST", "/shop/buy", {"itemId": item_id, "clientBuyId": client_buy_id}, token)


def equip(token: str, item_id):
    return req("POST", "/shop/equip", {"itemId": item_id}, token)


def create_and_join(player_token: str):
    seated = sit_created_pvp(req, player_token)
    created = seated.get("created") or {}
    expect(seated.get("ok") is True, "POST /matches + player Bearer", str(created)[:200])
    return (
        seated.get("matchId", ""),
        seated.get("token_a", ""),
        seated.get("token_b", ""),
        seated.get("join_a") or {},
        seated.get("join_b") or {},
    )


def act(mid: str, join_token: str, body: dict):
    return req("POST", f"/matches/{mid}/actions", body, join_token)


def combat_loop(player_token: str, label: str) -> dict:
    """Attack miss then kill. Same path with/without equippedSkinId."""
    mid, token_a, token_b, join_a, _ = create_and_join(player_token)
    act(mid, token_a, {"type": "select_hex", "hex": {"q": 2, "r": 2}})
    act(mid, token_b, {"type": "select_hex", "hex": {"q": 7, "r": 5}})
    code_m, miss, raw_m = act(mid, token_a, {"type": "attack", "hex": {"q": 0, "r": 0}})
    miss_last = last_action(miss)
    miss_snap = miss.get("snapshot") or {}
    miss_enemy = (miss_snap.get("enemy") or {}) if isinstance(miss_snap, dict) else {}
    status, _, _ = act(mid, token_a, {"type": "end_turn", "exposurePct": 50, "hex": {"q": 2, "r": 3}})
    if status == 400:
        act(mid, token_a, {"type": "end_turn", "exposurePct": 50})
    act(mid, token_b, {"type": "recon", "hex": {"q": 4, "r": 3}})
    act(mid, token_b, {"type": "end_turn", "exposurePct": 40, "move": {"q": 6, "r": 5}})
    _, uav, _ = act(mid, token_a, {"type": "uav"})
    vis = ((uav.get("snapshot") or {}).get("enemy") or {}).get("visibleHex")
    act(mid, token_a, {"type": "end_turn", "exposurePct": 50})
    act(mid, token_b, {"type": "recon", "hex": {"q": 1, "r": 1}})
    act(mid, token_b, {"type": "end_turn", "exposurePct": 50})
    if not isinstance(vis, dict):
        vis = {"q": 6, "r": 5}
    _, kill, raw_k = act(mid, token_a, {"type": "attack", "hex": vis})
    kill_last = last_action(kill)
    kill_snap = kill.get("snapshot") or {}
    fp = {
        "label": label,
        "matchId": mid,
        "miss_hit": miss_last.get("hit"),
        "miss_kill": miss_last.get("kill"),
        "miss_hot": miss_enemy.get("visibleHex"),
        "miss_exposure": ((miss_snap.get("you") or {}).get("exposurePct") if isinstance(miss_snap, dict) else None),
        "kill_hit": kill_last.get("hit"),
        "kill_kill": kill_last.get("kill"),
        "kill_status": kill_snap.get("status") if isinstance(kill_snap, dict) else None,
        "kill_delta": (kill_snap.get("payout") or {}).get("marksDelta")
        if isinstance(kill_snap, dict)
        else None,
        "kill_marks": you_marks(kill_snap),
        "join_player": str(join_a.get("playerId", "")),
    }
    if fp["kill_delta"] is None and isinstance(kill_snap, dict):
        fp["kill_delta"] = kill_snap.get("marksDelta")
    evidence(f"E5 {label} {mid} miss={miss_last} kill={kill_last} marks={fp['kill_marks']}")
    expect(code_m == 200, f"E5 {label} miss HTTP 200", raw_m[:160])
    expect(miss_last.get("hit") is False, f"E5 {label} miss hit=false")
    expect(miss_last.get("kill") in (False, None), f"E5 {label} miss kill=false")
    expect(miss_enemy.get("visibleHex") in (None, {}), f"E5 {label} miss does not invent Hot")
    expect(fp["kill_status"] == "ended", f"E5 {label} kill ended")
    expect(kill_last.get("hit") is True, f"E5 {label} kill hit=true")
    expect(kill_last.get("kill") is True, f"E5 {label} kill kill=true")
    return fp


def earn_kills(player_token: str, player_id: str, need: int, earned: int) -> int:
    i = 0
    while earned < need:
        i += 1
        fp = combat_loop(player_token, f"earn {i} toward {need}")
        expect(str(fp.get("join_player", "")) == player_id, f"earn {i} same playerId")
        after = fp.get("kill_marks")
        expect(after == earned + 25, f"earn {i} you.marks {earned}→{after} (+25)")
        earned = after if after is not None else earned
    return earned


def finish() -> int:
    print()
    print("BASE", BASE)
    print("NOTES")
    for line in NOTES:
        print(f"  - {line}")
    print("EVIDENCE")
    for line in EVIDENCE:
        print(f"  - {line}")
    print()
    if FAILS:
        print("LIVE_SHOP_EQUIP_FAIL", len(FAILS))
        for line in FAILS:
            print(f"  - {line}")
        return 1
    print("LIVE_SHOP_EQUIP_OK")
    return 0


def main() -> int:
    print(f"BASE {BASE}")
    code, health, _ = req("GET", "/health")
    expect(code == 200 and health.get("ok") is True, "GET /health")

    code, catalog, raw = req("GET", "/shop")
    expect(code == 200 and isinstance(catalog.get("items"), list), "GET /shop 200")
    evidence(f"GET /shop {json.dumps(catalog)}")

    player = mint_player()
    token = str(player.get("token", ""))
    player_id = str(player.get("playerId", ""))
    start_marks = you_marks(player)
    expect(start_marks == 0, "minted marks 0")
    evidence(f"player {player_id} marks={start_marks}")

    print("\n== GET /shop/me empty ==")
    code, me, raw = shop_me(token)
    expect(code == 200, f"GET /shop/me 200 (got {code})", raw[:200])
    expect(equipped_skin(me) is None, f"me equippedSkinId null (got {equipped_skin(me)})")
    expect(me.get("owned") == [], f"me owned [] (got {me.get('owned')})")
    expect(you_marks(me) == 0, "me marks 0")
    evidence(f"GET /shop/me {json.dumps(me)}")

    print("\n== E1 unowned reject ==")
    code, body, raw = equip(token, GHILLIE)
    evidence(f"E1 unowned POST /shop/equip {code} {json.dumps(body)}")
    expect(code == 403, f"E1 unowned HTTP 403 (got {code})", raw[:240])
    expect(body.get("code") == "not_owned" or body.get("error") == "not_owned", "E1 code not_owned")
    expect(you_marks(body) == 0, "E1 unowned marks untouched")
    expect(equipped_skin(body) is None, "E1 unowned equippedSkinId null")

    print("\n== E5 bare miss/kill (also earn ★25) ==")
    bare = combat_loop(token, "bare")
    earned = bare.get("kill_marks") or 0
    expect(earned == 25, f"E5 bare wallet 0→25 (got {earned})")

    print("\n== earn to ★50 then buy ghillie ==")
    earned = earn_kills(token, player_id, 50, earned)
    buy_id_g = str(uuid.uuid4())
    code, bought, raw = buy(token, GHILLIE, buy_id_g)
    evidence(f"E1 buy ghillie {code} {json.dumps(bought)}")
    expect(code == 200 and bought.get("ok") is True, "E1 buy ghillie 200")
    expect(you_marks(bought) == 0, f"E1 buy 50→0 (got {you_marks(bought)})")
    expect(equipped_skin(bought) == GHILLIE, f"E1 last-buy auto-equip {equipped_skin(bought)}")

    print("\n== E1 POST /shop/equip sets equippedSkinId ==")
    marks_before = you_marks(bought)
    code, eq, raw = equip(token, GHILLIE)
    evidence(f"E1 equip ghillie {code} {json.dumps(eq)}")
    expect(code == 200 and eq.get("ok") is True, "E1 equip 200")
    expect(equipped_skin(eq) == GHILLIE, f"E1 you.equippedSkinId={equipped_skin(eq)}")
    expect(you_marks(eq) == marks_before, "E1 same-id equip marks untouched")
    code, me, _ = shop_me(token)
    expect(code == 200, "E1 GET /shop/me after equip")
    expect(equipped_skin(me) == GHILLIE, f"E1 /shop/me equippedSkinId={equipped_skin(me)}")
    expect(GHILLIE in (me.get("owned") or []), "E1 /shop/me owned ghillie")
    evidence(f"E1 GET /shop/me {json.dumps(me)}")
    code2, eq2, _ = equip(token, GHILLIE)
    expect(code2 == 200 and equipped_skin(eq2) == GHILLIE, "E1 idempotent same-id 200")
    expect(you_marks(eq2) == marks_before, "E1 idempotent marks unchanged")

    print("\n== E5 worn miss/kill (ghillie equipped) ==")
    worn = combat_loop(token, "ghillie")
    for key in ["miss_hit", "miss_kill", "miss_hot", "kill_hit", "kill_kill", "kill_status"]:
        expect(bare.get(key) == worn.get(key), f"E5 parity {key} bare={bare.get(key)} worn={worn.get(key)}")
    note(
        "E5 combat math unchanged: miss hit=false / no Hot, kill hit=true marksDelta +25. "
        f"bare {bare.get('matchId')} vs worn {worn.get('matchId')} equippedSkinId={GHILLIE}."
    )
    earned = worn.get("kill_marks") or 0

    print("\n== E4 earn ★100 + buy bandana + swap / unequip ==")
    earned = earn_kills(token, player_id, 100, earned)
    buy_id_b = str(uuid.uuid4())
    code, bought_b, raw = buy(token, BANDANA, buy_id_b)
    evidence(f"E4 buy bandana {code} {json.dumps(bought_b)}")
    expect(code == 200 and bought_b.get("ok") is True, "E4 buy bandana 200")
    expect(you_marks(bought_b) == earned - 100, f"E4 buy debit {earned}→{you_marks(bought_b)}")
    expect(equipped_skin(bought_b) == BANDANA, "E4 last-buy auto-equip bandana")
    wallet = you_marks(bought_b)

    code, swapped, raw = equip(token, GHILLIE)
    evidence(f"E4 swap ghillie {code} {json.dumps(swapped)}")
    expect(code == 200, "E4 swap 200")
    expect(equipped_skin(swapped) == GHILLIE, f"E4 equippedSkinId ghillie (got {equipped_skin(swapped)})")
    expect(you_marks(swapped) == wallet, "E4 swap marks untouched")

    code, off, raw = equip(token, None)
    evidence(f"E4 unequip null {code} {json.dumps(off)}")
    expect(code == 200 and off.get("ok") is True, "E4 unequip 200")
    expect(equipped_skin(off) is None, f"E4 equippedSkinId null (got {equipped_skin(off)})")
    expect(you_marks(off) == wallet, "E4 unequip marks untouched")

    code, back, raw = equip(token, BANDANA)
    evidence(f"E4 re-equip bandana {code} {json.dumps(back)}")
    expect(code == 200 and equipped_skin(back) == BANDANA, "E4 re-equip bandana")
    expect(you_marks(back) == wallet, "E4 re-equip marks untouched")
    code, me, _ = shop_me(token)
    expect(equipped_skin(me) == BANDANA, "E4 /shop/me bandana")
    owned = me.get("owned") or []
    expect(GHILLIE in owned and BANDANA in owned, f"E4 owns both {owned}")
    evidence(f"E4 GET /shop/me {json.dumps(me)}")

    print()
    print("PLAYER", player_id)
    return finish()


if __name__ == "__main__":
    sys.exit(main())
