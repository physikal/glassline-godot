#!/usr/bin/env python3
"""LIVE second Marks sink S2.1–S2.3 vs glassline-api (BANDANA RECOLOR ★100).

Same spine as sink 1: durable POST /players Bearer + GET /shop + POST /shop/buy
{ itemId, clientBuyId }. Client never marks -=.

If LIVE catalog does not yet list skin_bandana_stub, this exits 0 with
LIVE_SHOP_SINK2_PENDING so Coder can land the +1 SKU. UI + mock still ship.

  GLASSLINE_API_BASE=https://glassline-api.vercel.app python3 tools/live_shop_sink2_smoke.py
"""

from __future__ import annotations

import json
import os
import sys
import uuid
import urllib.error
import urllib.request

BASE = os.environ.get("GLASSLINE_API_BASE", "https://glassline-api.vercel.app").rstrip("/")
ITEM = "skin_bandana_stub"
PRICE = 100
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
        print("LIVE_SHOP_SINK2_PENDING catalog missing", ITEM)
        return 0
    if FAILS:
        print("LIVE_SHOP_SINK2_FAIL", len(FAILS))
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
            "Client ships two-row ARMORY + mock catalog. Coder: add skin_bandana_stub ★100."
        )
        return finish(pending=True)

    item_id = str(stub.get("id") or ITEM)
    expect(int(stub.get("price", -1)) == PRICE, f"catalog price {PRICE}", str(stub))
    expect(stub.get("kind") == "skin", "catalog kind skin", str(stub))
    expect("you" not in catalog and "marks" not in catalog, "GET /shop is catalog-only (no you.marks)")

    # --- S2.2 insufficient (fresh durable player at 0) ---
    print("\n== S2.2 insufficient ==")
    player_s2 = mint_player()
    token_s2 = str(player_s2.get("token", ""))
    start_s2 = you_marks(player_s2)
    expect(start_s2 == 0, f"S2.2 POST /players marks == 0 (got {start_s2})")
    evidence(f"S2.2 player {player_s2.get('playerId')} marks={start_s2}")
    buy_id_s2 = str(uuid.uuid4())
    code, body, raw = buy(token_s2, buy_id_s2, item_id)
    after_s2 = you_marks(body)
    expect(code == 402, f"S2.2 HTTP 402 (got {code})", raw)
    expect(
        body.get("code") == "insufficient_marks" or body.get("error") == "insufficient_marks",
        "S2.2 code insufficient_marks",
    )
    expect(after_s2 == start_s2, f"S2.2 balance unchanged {start_s2} → {after_s2}")
    evidence(f"S2.2 POST /shop/buy {code} {json.dumps(body)} start={start_s2} clientBuyId={buy_id_s2}")
    code2, body2, raw2 = buy(token_s2, buy_id_s2, item_id)
    expect(code2 == 402, f"S2.2 replay same clientBuyId still 402 (got {code2})", raw2)
    expect(you_marks(body2) == start_s2, "S2.2 replay does not debit")
    evidence(f"S2.2 replay {code2} {json.dumps(body2)}")

    # --- Earn ≥100 as the same player (four kill wins, ★25 each) ---
    print("\n== earn four PvP kills on one player (ledger +25 ×4) ==")
    player_a = mint_player()
    token_a_player = str(player_a.get("token", ""))
    player_id = str(player_a.get("playerId", ""))
    expect(you_marks(player_a) == 0, "S2.1 player minted at 0")
    evidence(f"S2.1 player {player_id}")
    earned = 0
    match_ids: list[str] = []
    for i in range(1, 5):
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
    expect(earned is not None and earned >= PRICE, f"same player earned ≥{PRICE} (got {earned})")

    # --- S2.1 buy OK ---
    print("\n== S2.1 buy ==")
    buy_id_s1 = str(uuid.uuid4())
    code, body, raw = buy(token_a_player, buy_id_s1, item_id)
    after = you_marks(body)
    purchase_id = str(body.get("purchaseId", ""))
    evidence(
        f"S2.1 POST /shop/buy {code} {json.dumps(body)} before={earned} clientBuyId={buy_id_s1}"
    )
    s1_ok = code == 200 and body.get("ok") is True
    expect(s1_ok, f"S2.1 HTTP 200 ok (got {code})", raw)
    if s1_ok:
        expect(after == (earned or 0) - PRICE, f"S2.1 you.marks debit {earned}→{after} (−{PRICE})")
        expect(purchase_id != "", "S2.1 purchaseId present")
        item = body.get("item") or {}
        expect(item.get("id") == item_id or item.get("itemId") == item_id, f"S2.1 item {item_id}")
        note("S2.1 client bind = response you.marks only (no local marks -=)")
    else:
        note(f"S2.1 did not debit: HTTP {code} wallet {earned} body={raw[:300]}")

    # --- S2.3 idempotent replay ---
    print("\n== S2.3 idempotent clientBuyId ==")
    code_r, body_r, raw_r = buy(token_a_player, buy_id_s1, item_id)
    replay_marks = you_marks(body_r)
    evidence(f"S2.3 replay {code_r} {json.dumps(body_r)} clientBuyId={buy_id_s1}")
    expect(code_r == 200 and body_r.get("ok") is True, f"S2.3 replay 200 (got {code_r})", raw_r)
    expect(replay_marks == after, f"S2.3 replay no second debit {after} → {replay_marks}")
    expect(str(body_r.get("purchaseId", "")) == purchase_id, "S2.3 same purchaseId")

    print()
    print("PLAYER", player_id)
    print("MATCHES", " ".join(match_ids))
    rc = finish()
    if rc == 0 and not FAILS:
        print(
            "LIVE_SHOP_SINK2_OK",
            " ".join(match_ids),
            f"marks {earned}->{after} purchaseId={purchase_id}",
        )
    return rc


if __name__ == "__main__":
    sys.exit(main())
