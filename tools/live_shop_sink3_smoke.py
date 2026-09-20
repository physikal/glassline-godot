#!/usr/bin/env python3
"""LIVE third Marks sink S3.1–S3.5 vs glassline-api (HIDEOUT POSTER ★150).

Same spine as sink 1 / 2: durable POST /players Bearer + GET /shop + POST /shop/buy
{ itemId, clientBuyId }. Equip uses equippedDecorId (skin slot untouched).
Client never marks -=.

If LIVE catalog does not yet list decor_poster_stub, this exits 0 with
LIVE_SHOP_SINK3_PENDING. UI + mock still ship.

  GLASSLINE_API_BASE=https://glassline-api.vercel.app python3 tools/live_shop_sink3_smoke.py
"""

from __future__ import annotations

import json
import os
import sys
import uuid
import urllib.error
import urllib.request

BASE = os.environ.get("GLASSLINE_API_BASE", "https://glassline-api.vercel.app").rstrip("/")
ITEM = "decor_poster_stub"
PRICE = 150
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


def mint_player():
    code, body, raw = req("POST", "/players", {})
    expect(code in (200, 201) and body.get("token"), "POST /players", raw[:240])
    return body


def buy(player_token: str, client_buy_id: str, item_id: str = ITEM):
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


def pvp_kill(mid: str, token_a: str, token_b: str) -> dict:
    req("POST", f"/matches/{mid}/actions", {"type": "select_hex", "hex": {"q": 2, "r": 2}}, token_a)
    req("POST", f"/matches/{mid}/actions", {"type": "select_hex", "hex": {"q": 7, "r": 5}}, token_b)
    req("POST", f"/matches/{mid}/actions", {"type": "attack", "hex": {"q": 0, "r": 0}}, token_a)
    status, hex_end, _ = req(
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
        print("LIVE_SHOP_SINK3_PENDING catalog missing", ITEM)
        return 0
    if FAILS:
        print("LIVE_SHOP_SINK3_FAIL", len(FAILS))
        for line in FAILS:
            print(f"  - {line}")
        return 1
    return 0


def main() -> int:
    print(f"BASE {BASE}")
    print(f"ITEM {ITEM} PRICE {PRICE}")
    code, health, _ = req("GET", "/health")
    expect(code == 200 and health.get("ok") is True, "GET /health")

    code, catalog, raw = req("GET", "/shop")
    expect(code == 200 and isinstance(catalog.get("items"), list), "GET /shop 200")
    items = catalog.get("items") or []
    evidence(f"GET /shop {code} {json.dumps(catalog)}")
    stub = next((i for i in items if isinstance(i, dict) and i.get("id") == ITEM), None)
    if stub is None:
        note(
            f"LIVE catalog has {len(items)} SKU(s) and no {ITEM}. "
            "Client ships three-row ARMORY + mock catalog. Coder: add decor_poster_stub ★150."
        )
        return finish(pending=True)

    item_id = str(stub.get("id") or ITEM)
    expect(int(stub.get("price", -1)) == PRICE, f"catalog price {PRICE}", str(stub))
    expect(
        stub.get("kind") in ("decor", "part", "skin"),
        "catalog kind decor|part|skin",
        str(stub),
    )
    expect("you" not in catalog and "marks" not in catalog, "GET /shop is catalog-only (no you.marks)")

    # --- S3.3 insufficient (fresh durable player at 0) ---
    print("\n== S3.3 insufficient ==")
    player_s3 = mint_player()
    token_s3 = str(player_s3.get("token", ""))
    start_s3 = you_marks(player_s3)
    expect(start_s3 == 0, f"S3.3 POST /players marks == 0 (got {start_s3})")
    evidence(f"S3.3 player {player_s3.get('playerId')} marks={start_s3}")
    buy_id_s3 = str(uuid.uuid4())
    code, body, raw = buy(token_s3, buy_id_s3, item_id)
    after_s3 = you_marks(body)
    expect(code == 402, f"S3.3 HTTP 402 (got {code})", raw)
    expect(
        body.get("code") == "insufficient_marks" or body.get("error") == "insufficient_marks",
        "S3.3 code insufficient_marks",
    )
    expect(after_s3 == start_s3, f"S3.3 balance unchanged {start_s3} → {after_s3}")
    evidence(f"S3.3 POST /shop/buy {code} {json.dumps(body)} start={start_s3} clientBuyId={buy_id_s3}")
    code2, body2, raw2 = buy(token_s3, buy_id_s3, item_id)
    expect(code2 == 402, f"S3.3 replay same clientBuyId still 402 (got {code2})", raw2)
    expect(you_marks(body2) == start_s3, "S3.3 replay does not debit")
    evidence(f"S3.3 replay {code2} {json.dumps(body2)}")

    # --- Earn ≥200 as the same player (eight kill wins, ★25 each) so poster + ghillie both fit ---
    print("\n== earn eight PvP kills on one player (ledger +25 ×8) ==")
    player_a = mint_player()
    token_a_player = str(player_a.get("token", ""))
    player_id = str(player_a.get("playerId", ""))
    expect(you_marks(player_a) == 0, "S3.2 player minted at 0")
    evidence(f"S3.2 player {player_id}")
    earned = 0
    match_ids: list[str] = []
    for i in range(1, 9):
        mid, token_a, token_b, join_a, _ = create_and_join(token_a_player)
        match_ids.append(mid)
        before = you_marks(join_a.get("snapshot") or {})
        expect(before == earned, f"kill {i} join you.marks == {earned} (got {before})")
        snap = pvp_kill(mid, token_a, token_b)
        after = you_marks(snap)
        expect(snap.get("status") == "ended", f"kill {i} PvP ended")
        expect(after == earned + 25, f"kill {i} you.marks {earned}→{after} (+25)")
        expect(str(join_a.get("playerId", "")) == player_id, f"kill {i} same playerId")
        evidence(
            f"PvP {mid} you.marks {earned}→{after} endReason={snap.get('endReason')} player={player_id}"
        )
        earned = after if after is not None else earned
    expect(earned is not None and earned >= PRICE + 50, f"same player earned ≥{PRICE + 50} (got {earned})")

    # --- S3.2 buy OK ---
    print("\n== S3.2 buy ==")
    buy_id_s1 = str(uuid.uuid4())
    code, body, raw = buy(token_a_player, buy_id_s1, item_id)
    after = you_marks(body)
    purchase_id = str(body.get("purchaseId", ""))
    evidence(
        f"S3.2 POST /shop/buy {code} {json.dumps(body)} before={earned} clientBuyId={buy_id_s1}"
    )
    s1_ok = code == 200 and body.get("ok") is True
    expect(s1_ok, f"S3.2 HTTP 200 ok (got {code})", raw)
    if s1_ok:
        expect(after == (earned or 0) - PRICE, f"S3.2 you.marks debit {earned}→{after} (−{PRICE})")
        expect(purchase_id != "", "S3.2 purchaseId present")
        item = body.get("item") or {}
        expect(item.get("id") == item_id or item.get("itemId") == item_id, f"S3.2 item {item_id}")
        expect(
            you_field(body, "equippedDecorId") == item_id,
            f"S3.2 you.equippedDecorId={you_field(body, 'equippedDecorId')}",
        )
        note("S3.2 client bind = response you.marks only (no local marks -=)")
        note("S3.2 buy auto-equips equippedDecorId; equippedSkinId unchanged")
    else:
        note(f"S3.2 did not debit: HTTP {code} wallet {earned} body={raw[:300]}")

    # --- S3.2 idempotent replay ---
    print("\n== S3.2 idempotent clientBuyId ==")
    code_r, body_r, raw_r = buy(token_a_player, buy_id_s1, item_id)
    replay_marks = you_marks(body_r)
    evidence(f"S3.2 replay {code_r} {json.dumps(body_r)} clientBuyId={buy_id_s1}")
    expect(code_r == 200 and body_r.get("ok") is True, f"S3.2 replay 200 (got {code_r})", raw_r)
    expect(replay_marks == after, f"S3.2 replay no second debit {after} → {replay_marks}")
    expect(str(body_r.get("purchaseId", "")) == purchase_id, "S3.2 same purchaseId")
    expect(
        you_field(body_r, "equippedDecorId") == item_id,
        "S3.2 replay keeps equippedDecorId",
    )

    # --- Dual slot: buy/equip skin must not clear poster ---
    print("\n== S3.4 equippedDecorId coexists with skin ==")
    ghillie_id = "skin_hideout_stub"
    buy_id_g = str(uuid.uuid4())
    code_g, body_g, raw_g = buy(token_a_player, buy_id_g, ghillie_id)
    evidence(f"S3.4 buy ghillie {code_g} {json.dumps(body_g)}")
    expect(code_g == 200 and body_g.get("ok") is True, f"S3.4 buy ghillie 200 (got {code_g})", raw_g)
    expect(you_field(body_g, "equippedSkinId") == ghillie_id, "S3.4 buy ghillie sets equippedSkinId")
    expect(you_field(body_g, "equippedDecorId") == item_id, "S3.4 buy ghillie keeps equippedDecorId")
    code_e, body_e, raw_e = equip(token_a_player, item_id, "decor")
    evidence(f"S3.4 re-equip poster {code_e} {json.dumps(body_e)}")
    expect(code_e == 200 and body_e.get("ok") is True, f"S3.4 equip poster 200 (got {code_e})", raw_e)
    expect(you_field(body_e, "equippedDecorId") == item_id, "S3.4 equip poster sets equippedDecorId")
    expect(you_field(body_e, "equippedSkinId") == ghillie_id, "S3.4 equip poster leaves skin")
    code_u, body_u, raw_u = equip(token_a_player, None, "decor")
    evidence(f"S3.4 unequip decor {code_u} {json.dumps(body_u)}")
    expect(code_u == 200 and body_u.get("ok") is True, f"S3.4 unequip decor 200 (got {code_u})", raw_u)
    expect(you_field(body_u, "equippedDecorId") in (None, ""), "S3.4 unequip decor clears poster")
    expect(you_field(body_u, "equippedSkinId") == ghillie_id, "S3.4 unequip decor leaves skin")
    code_m, me, raw_m = shop_me(token_a_player)
    evidence(f"S3.4 GET /shop/me {code_m} {json.dumps(me)}")
    expect(code_m == 200, f"S3.4 GET /shop/me 200 (got {code_m})", raw_m)
    expect(you_field(me, "equippedSkinId") == ghillie_id, "S3.4 /shop/me skin still ghillie")
    expect(you_field(me, "equippedDecorId") in (None, ""), "S3.4 /shop/me decor unequipped")

    print()
    print("PLAYER", player_id)
    print("MATCHES", " ".join(match_ids))
    rc = finish()
    if rc == 0 and not FAILS:
        print(
            "LIVE_SHOP_SINK3_OK",
            " ".join(match_ids),
            f"marks {earned}->{after} purchaseId={purchase_id}",
        )
    return rc


if __name__ == "__main__":
    sys.exit(main())
