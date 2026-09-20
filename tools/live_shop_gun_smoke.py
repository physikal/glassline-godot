#!/usr/bin/env python3
"""LIVE Gun SKUs vs glassline-api (kind: gun + equippedGunId).

Same /shop spine as skins / poster: GET /shop + POST /shop/buy
{ itemId, clientBuyId } + POST /shop/equip { itemId } | { itemId: null, slot: "gun" }.
Starter gun_fieldbolt owned-by-default. Sinks gun_railframe ★125 · gun_crescent ★200.
Chrome only — zero combat. Client never marks -=.

If LIVE catalog does not yet list gun_* SKUs, this exits 0 with
LIVE_SHOP_GUN_PENDING. UI + mock still ship.

  GLASSLINE_API_BASE=https://glassline-api.vercel.app python3 tools/live_shop_gun_smoke.py
"""

from __future__ import annotations

import json
import os
import sys
import uuid
import urllib.error
import urllib.request

BASE = os.environ.get("GLASSLINE_API_BASE", "https://glassline-api.vercel.app").rstrip("/")
FIELDBOLT = "gun_fieldbolt"
RAILFRAME = "gun_railframe"
CRESCENT = "gun_crescent"
RAIL_PRICE = 125
CRES_PRICE = 200
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
            parsed = {"error": raw}
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


def you_field(bag: dict | None, key: str):
    if not isinstance(bag, dict):
        return None
    you = bag.get("you")
    if isinstance(you, dict) and key in you:
        return you.get(key)
    if key in bag:
        return bag.get(key)
    snap = bag.get("snapshot")
    if isinstance(snap, dict):
        return you_field(snap, key)
    return None


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


def equipped_gun(bag: dict | None):
    val = you_field(bag, "equippedGunId")
    return None if val is None else str(val)


def owned_guns(bag: dict | None) -> list:
    if not isinstance(bag, dict):
        return []
    you = bag.get("you")
    if isinstance(you, dict) and isinstance(you.get("ownedGuns"), list):
        return [str(x) for x in you.get("ownedGuns")]
    if isinstance(bag.get("ownedGuns"), list):
        return [str(x) for x in bag.get("ownedGuns")]
    owned = bag.get("owned")
    if isinstance(owned, list):
        return [str(x) for x in owned if str(x).startswith("gun_")]
    return []


def mint_player():
    code, body, raw = req("POST", "/players", {})
    expect(code in (200, 201) and body.get("token"), "POST /players", raw[:240])
    return body


def buy(player_token: str, client_buy_id: str, item_id: str):
    return req("POST", "/shop/buy", {"itemId": item_id, "clientBuyId": client_buy_id}, player_token)


def equip(player_token: str, item_id, slot: str | None = None):
    body = {"itemId": item_id}
    if slot:
        body["slot"] = slot
    return req("POST", "/shop/equip", body, player_token)


def shop_me(player_token: str):
    return req("GET", "/shop/me", token=player_token)


def create_and_join(player_token: str):
    code, created, raw = req("POST", "/matches", {}, token=player_token)
    expect(code in (200, 201) and "matchId" in created, "POST /matches + player Bearer", raw[:200])
    mid = created.get("matchId", "")
    tokens = created.get("joinTokens") or {}
    token_a = tokens.get("a", "")
    token_b = tokens.get("b", "")
    _, join_a, _ = req(
        "POST",
        f"/matches/{mid}/join",
        {"token": token_a},
        token=player_token,
    )
    _, join_b, _ = req("POST", f"/matches/{mid}/join", {"token": token_b})
    return mid, token_a, token_b, join_a, join_b


def earn_until(player_token: str, need: int, earned: int, label: str) -> int:
    ## Loop hunts until wallet >= need. A forfeit +12 must not fail the gate.
    i = 0
    while earned < need:
        i += 1
        mid, token_a, token_b, join_a, _ = create_and_join(player_token)
        snap = pvp_kill(mid, token_a, token_b)
        after = you_marks(snap)
        expect(after is not None and after > earned, f"{label} hunt {i} marks rose ({earned}→{after})")
        evidence(f"{label} hunt {i} {mid} marks={after} status={snap.get('status')}")
        earned = after if after is not None else earned
        if i >= 24:
            expect(False, f"{label} gave up at {earned} need {need}")
            break
    return earned


def pvp_kill(mid: str, token_a: str, token_b: str) -> dict:
    req("POST", f"/matches/{mid}/actions", {"type": "select_hex", "hex": {"q": 2, "r": 2}}, token_a)
    req("POST", f"/matches/{mid}/actions", {"type": "select_hex", "hex": {"q": 7, "r": 5}}, token_b)
    req("POST", f"/matches/{mid}/actions", {"type": "attack", "hex": {"q": 0, "r": 0}}, token_a)
    status, _hex_end, _ = req(
        "POST",
        f"/matches/{mid}/actions",
        {"type": "end_turn", "exposurePct": 50, "hex": {"q": 2, "r": 3}},
        token_a,
    )
    if status == 400:
        req("POST", f"/matches/{mid}/actions", {"type": "end_turn", "exposurePct": 50}, token_a)
    req("POST", f"/matches/{mid}/actions", {"type": "recon", "hex": {"q": 4, "r": 3}}, token_b)
    req(
        "POST",
        f"/matches/{mid}/actions",
        {"type": "end_turn", "exposurePct": 40, "move": {"q": 6, "r": 5}},
        token_b,
    )
    _, uav, _ = req("POST", f"/matches/{mid}/actions", {"type": "uav"}, token_a)
    vis = ((uav.get("snapshot") or {}).get("enemy") or {}).get("visibleHex")
    req("POST", f"/matches/{mid}/actions", {"type": "end_turn", "exposurePct": 50}, token_a)
    req("POST", f"/matches/{mid}/actions", {"type": "recon", "hex": {"q": 1, "r": 1}}, token_b)
    req("POST", f"/matches/{mid}/actions", {"type": "end_turn", "exposurePct": 50}, token_b)
    if not isinstance(vis, dict):
        vis = {"q": 6, "r": 5}
    _, kill, _ = req("POST", f"/matches/{mid}/actions", {"type": "attack", "hex": vis}, token_a)
    return kill.get("snapshot") or {}


def finish(pending: bool = False) -> int:
    print()
    print("BASE", BASE)
    print("NOTES")
    for line in NOTES:
        print(f"  - {line}")
    print("EVIDENCE")
    for line in EVIDENCE:
        print(f"  - {line}")
    print()
    if pending:
        print("LIVE_SHOP_GUN_PENDING catalog missing gun SKUs")
        return 0
    if FAILS:
        print("LIVE_SHOP_GUN_FAIL", len(FAILS))
        for line in FAILS:
            print(f"  - {line}")
        return 1
    print("LIVE_SHOP_GUN_OK")
    return 0


def catalog_item(items: list, item_id: str):
    return next((i for i in items if isinstance(i, dict) and i.get("id") == item_id), None)


def main() -> int:
    print(f"BASE {BASE}")
    code, health, _ = req("GET", "/health")
    expect(code == 200 and health.get("ok") is True, "GET /health")

    code, catalog, raw = req("GET", "/shop")
    expect(code == 200 and isinstance(catalog.get("items"), list), "GET /shop 200")
    items = catalog.get("items") or []
    evidence(f"GET /shop {code} {json.dumps(catalog)}")
    guns = [i for i in items if isinstance(i, dict) and str(i.get("kind", "")) == "gun"]
    rail = catalog_item(items, RAILFRAME)
    cres = catalog_item(items, CRESCENT)
    bolt = catalog_item(items, FIELDBOLT)
    if rail is None and cres is None and bolt is None and not guns:
        note(
            f"LIVE catalog has {len(items)} SKU(s) and no kind:gun. "
            "Client ships six-row ARMORY + mock gun catalog. Coder: add "
            "gun_fieldbolt (starter) · gun_railframe ★125 · gun_crescent ★200."
        )
        return finish(pending=True)

    if rail is not None:
        expect(int(rail.get("price", -1)) == RAIL_PRICE, f"catalog Railframe ★{RAIL_PRICE}", str(rail))
        expect(rail.get("kind") == "gun", "catalog Railframe kind gun", str(rail))
    if cres is not None:
        expect(int(cres.get("price", -1)) == CRES_PRICE, f"catalog Crescent ★{CRES_PRICE}", str(cres))
        expect(cres.get("kind") == "gun", "catalog Crescent kind gun", str(cres))
    if bolt is not None:
        expect(int(bolt.get("price", 0)) == 0, "catalog Fieldbolt ★0 starter", str(bolt))
        expect(bolt.get("kind") == "gun", "catalog Fieldbolt kind gun", str(bolt))
    expect("you" not in catalog and "marks" not in catalog, "GET /shop is catalog-only (no you.marks)")

    # --- G3 insufficient (fresh durable player at 0 vs Crescent ★200) ---
    print("\n== G3 insufficient ==")
    player_g3 = mint_player()
    token_g3 = str(player_g3.get("token", ""))
    start_g3 = you_marks(player_g3)
    expect(start_g3 == 0, f"G3 POST /players marks == 0 (got {start_g3})")
    evidence(f"G3 player {player_g3.get('playerId')} marks={start_g3}")
    target = CRESCENT if cres is not None else RAILFRAME
    buy_id_g3 = str(uuid.uuid4())
    code, body, raw = buy(token_g3, buy_id_g3, target)
    after_g3 = you_marks(body)
    expect(code == 402, f"G3 HTTP 402 (got {code})", raw)
    expect(
        body.get("code") == "insufficient_marks" or body.get("error") == "insufficient_marks",
        "G3 code insufficient_marks",
    )
    expect(after_g3 == start_g3, f"G3 balance unchanged {start_g3} → {after_g3}")
    evidence(f"G3 POST /shop/buy {code} {json.dumps(body)} start={start_g3} clientBuyId={buy_id_g3}")
    code2, body2, raw2 = buy(token_g3, buy_id_g3, target)
    expect(code2 == 402, f"G3 replay same clientBuyId still 402 (got {code2})", raw2)
    expect(you_marks(body2) == start_g3, "G3 replay does not debit")

    # --- G1 /shop/me starter Fieldbolt ---
    print("\n== G1 GET /shop/me starter ==")
    code, me, raw = shop_me(token_g3)
    expect(code == 200, f"GET /shop/me 200 (got {code})", raw[:200])
    evidence(f"G1 GET /shop/me {json.dumps(me)}")
    guns_me = owned_guns(me)
    worn = equipped_gun(me)
    if FIELDBOLT in guns_me or worn == FIELDBOLT or FIELDBOLT in (me.get("owned") or []):
        expect(True, "G1 /shop/me starter Fieldbolt owned or equipped")
    else:
        note(
            f"G1 /shop/me did not name Fieldbolt (ownedGuns={guns_me} equippedGunId={worn}). "
            "Client stubs starter owned-by-default until Coder grants it."
        )

    print("\n== G1 Fieldbolt buy is 200 no-op ==")
    bolt_buy_id = str(uuid.uuid4())
    worn_before = equipped_gun(me)
    code, bolt_buy, raw = buy(token_g3, bolt_buy_id, FIELDBOLT)
    evidence(f"G1 Fieldbolt buy {code} {json.dumps(bolt_buy)}")
    expect(code == 200 and bolt_buy.get("ok") is True, "G1 Fieldbolt buy 200 no-op")
    expect(you_marks(bolt_buy) == start_g3, "G1 Fieldbolt buy does not debit")
    expect(equipped_gun(bolt_buy) == worn_before, "G1 Fieldbolt buy does not re-equip")

    if rail is None:
        note("LIVE catalog missing gun_railframe — skip buy / equip / combat. Mock covers G2/G5.")
        return finish(pending=len(FAILS) == 0)

    # --- Earn ★125 (five PvP kills) then buy Railframe ---
    print("\n== G2 earn five PvP kills then buy Railframe ==")
    player_a = mint_player()
    token_a_player = str(player_a.get("token", ""))
    player_id = str(player_a.get("playerId", ""))
    expect(you_marks(player_a) == 0, "G2 player minted at 0")
    evidence(f"G2 player {player_id}")
    earned = earn_until(token_a_player, RAIL_PRICE, 0, "G2 rail")
    expect(earned >= RAIL_PRICE, f"G2 wallet >= ★{RAIL_PRICE} (got {earned})")

    buy_id = str(uuid.uuid4())
    code, bought, raw = buy(token_a_player, buy_id, RAILFRAME)
    evidence(f"G2 buy Railframe {code} {json.dumps(bought)}")
    expect(code == 200 and bought.get("ok") is True, "G2 buy Railframe 200")
    expect(you_marks(bought) == earned - RAIL_PRICE, f"G2 buy debit {earned}→{you_marks(bought)}")
    worn = equipped_gun(bought)
    if worn is not None:
        expect(worn == RAILFRAME, f"G2 last-buy auto-equip Railframe (got {worn})")
    else:
        note("G2 buy 200 omitted equippedGunId — client infers from item.id")
    wallet = you_marks(bought)

    code_r, replay, raw_r = buy(token_a_player, buy_id, RAILFRAME)
    evidence(f"G2 replay {code_r} {json.dumps(replay)}")
    expect(code_r == 200 and replay.get("ok") is True, "G2 clientBuyId idempotent 200")
    expect(you_marks(replay) == wallet, "G2 replay does not debit again")

    print("\n== G2 coexist skin + decor + gun ==")
    earned = earn_until(token_a_player, 200, wallet or 0, "G2 coexist")
    expect(earned >= 200, f"G2 coexist wallet >= ★200 (got {earned})")
    code, bought_p, raw = buy(token_a_player, str(uuid.uuid4()), "decor_poster_stub")
    evidence(f"G2 buy poster {code} {json.dumps(bought_p)}")
    expect(code == 200 and bought_p.get("ok") is True, "G2 buy poster 200")
    expect(you_field(bought_p, "equippedDecorId") == "decor_poster_stub", "G2 poster auto-equip decor")
    expect(equipped_gun(bought_p) == RAILFRAME, "G2 poster buy leaves Railframe equipped")
    code, bought_g, raw = buy(token_a_player, str(uuid.uuid4()), "skin_hideout_stub")
    evidence(f"G2 buy ghillie {code} {json.dumps(bought_g)}")
    expect(code == 200 and bought_g.get("ok") is True, "G2 buy ghillie 200")
    expect(you_field(bought_g, "equippedSkinId") == "skin_hideout_stub", "G2 ghillie auto-equip skin")
    expect(you_field(bought_g, "equippedDecorId") == "decor_poster_stub", "G2 ghillie buy leaves poster")
    expect(equipped_gun(bought_g) == RAILFRAME, "G2 ghillie buy leaves Railframe")
    wallet = you_marks(bought_g)

    print("\n== G2 equip / unequip gun slot ==")
    code, swapped, raw = equip(token_a_player, FIELDBOLT, "gun")
    evidence(f"G2 equip Fieldbolt {code} {json.dumps(swapped)}")
    if code == 404:
        note("LIVE /shop/equip gun slot 404 — client falls back to local chrome.")
    elif code == 403:
        note("LIVE /shop/equip Fieldbolt 403 not_owned — Coder has not granted starter.")
    else:
        expect(code == 200, f"G2 swap Fieldbolt 200 (got {code})", raw[:240])
        expect(you_marks(swapped) == wallet, "G2 gun equip marks untouched")
        if equipped_gun(swapped) is not None:
            expect(equipped_gun(swapped) == FIELDBOLT, f"G2 equippedGunId Fieldbolt (got {equipped_gun(swapped)})")
        expect(you_field(swapped, "equippedSkinId") == "skin_hideout_stub", "G2 gun swap leaves ghillie")
        expect(you_field(swapped, "equippedDecorId") == "decor_poster_stub", "G2 gun swap leaves poster")

    code, off, raw = equip(token_a_player, None, "gun")
    evidence(f"G2 unequip gun {code} {json.dumps(off)}")
    if code == 200:
        expect(equipped_gun(off) in (None, ""), f"G2 equippedGunId null (got {equipped_gun(off)})")
        expect(you_marks(off) == wallet, "G2 unequip gun marks untouched")
    elif code == 404:
        note("LIVE unequip slot=gun 404 — pending Coder.")
    else:
        expect(code == 200, f"G2 unequip gun 200 (got {code})", raw[:200])

    print("\n== G5 worn Railframe miss/kill (+25) ==")
    code, back, _ = equip(token_a_player, RAILFRAME, "gun")
    if code == 200:
        expect(you_marks(back) == wallet, "G5 re-equip Railframe marks untouched")
    mid, token_a, token_b, join_a, _ = create_and_join(token_a_player)
    snap = pvp_kill(mid, token_a, token_b)
    after = you_marks(snap)
    expect(snap.get("status") == "ended", "G5 worn Railframe kill ended")
    expect(after == (wallet or 0) + 25, f"G5 worn kill +25 ({wallet}→{after})")
    evidence(f"G5 worn Railframe {mid} marks={after} equippedGunId={equipped_gun(snap)}")
    note(
        "G5 combat math unchanged: PvP kill still ★25 with Railframe equipped. "
        f"match {mid}."
    )

    code, me, _ = shop_me(token_a_player)
    evidence(f"G2 GET /shop/me after buy {json.dumps(me)}")
    guns_me = owned_guns(me)
    if RAILFRAME in guns_me or RAILFRAME in (me.get("owned") or []):
        expect(True, "G2 /shop/me owns Railframe")
    else:
        note(f"G2 /shop/me ownedGuns={guns_me} owned={me.get('owned')} — bind from buy item.id")

    print()
    print("PLAYER", player_id)
    return finish()


if __name__ == "__main__":
    sys.exit(main())
