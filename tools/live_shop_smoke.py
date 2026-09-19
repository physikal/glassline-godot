#!/usr/bin/env python3
"""LIVE Marks sink S1–S3 smoke vs glassline-api.

Catalog: GET /shop → skin_hideout_stub ★50
Buy:     POST /shop/buy { itemId, clientBuyId } + Bearer joinToken
Bind:    you.marks from the response only (client never marks -=)

  GLASSLINE_API_BASE=https://glassline-api.vercel.app python3 tools/live_shop_smoke.py

Does not push the API repo. Cosmetic chrome only — no combat/spot/hit delta.
"""

from __future__ import annotations

import json
import os
import sys
import uuid
import urllib.error
import urllib.request

BASE = os.environ.get("GLASSLINE_API_BASE", "https://glassline-api.vercel.app").rstrip("/")
ITEM = "skin_hideout_stub"
PRICE = 50
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


def buy(token: str, client_buy_id: str, item_id: str = ITEM):
    return req("POST", "/shop/buy", {"itemId": item_id, "clientBuyId": client_buy_id}, token)


def create_and_join():
    code, created, raw = req("POST", "/matches", {})
    expect(code in (200, 201) and "matchId" in created, "POST /matches", raw[:200])
    mid = created.get("matchId", "")
    tokens = created.get("joinTokens") or {}
    token_a = tokens.get("a", "")
    token_b = tokens.get("b", "")
    _, join_a, _ = req("POST", f"/matches/{mid}/join", {"token": token_a})
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


def main() -> int:
    print(f"BASE {BASE}")
    print(f"ITEM {ITEM} PRICE {PRICE}")
    code, health, _ = req("GET", "/health")
    expect(code == 200 and health.get("ok") is True, "GET /health")

    code, catalog, raw = req("GET", "/shop")
    expect(code == 200 and isinstance(catalog.get("items"), list), "GET /shop 200")
    items = catalog.get("items") or []
    stub = next((i for i in items if isinstance(i, dict) and i.get("id") == ITEM), None)
    expect(stub is not None, "catalog includes skin_hideout_stub", raw)
    if stub:
        expect(int(stub.get("price", -1)) == PRICE, f"catalog price {PRICE}", str(stub))
        expect(stub.get("kind") == "skin", "catalog kind skin", str(stub))
        evidence(f"GET /shop {code} {json.dumps(catalog)}")
    expect("you" not in catalog and "marks" not in catalog, "GET /shop is catalog-only (no you.marks)")

    # --- S2 insufficient (fresh wallet 0) ---
    print("\n== S2 insufficient ==")
    mid_s2, token_s2, _tb, join_s2, _ = create_and_join()
    start_s2 = you_marks(join_s2.get("snapshot") or {})
    expect(start_s2 == 0, f"S2 starting you.marks == 0 (got {start_s2})")
    buy_id_s2 = str(uuid.uuid4())
    code, body, raw = buy(token_s2, buy_id_s2)
    after_s2 = you_marks(body)
    expect(code == 402, f"S2 HTTP 402 (got {code})", raw)
    expect(body.get("code") == "insufficient_marks" or body.get("error") == "insufficient_marks", "S2 code insufficient_marks")
    expect(after_s2 == start_s2, f"S2 balance unchanged {start_s2} → {after_s2}")
    evidence(f"S2 POST /shop/buy {code} {json.dumps(body)} start={start_s2}")
    code2, body2, raw2 = buy(token_s2, buy_id_s2)
    expect(code2 == 402, f"S2 replay same clientBuyId still 402 (got {code2})", raw2)
    expect(you_marks(body2) == start_s2, "S2 replay does not debit")
    evidence(f"S2 replay {code2} {json.dumps(body2)} clientBuyId={buy_id_s2}")

    # --- Earn a PvP kill (+25) so S1 can try a real debit ---
    print("\n== earn PvP kill (ledger +25) ==")
    mid, token_a, token_b, join_a, _ = create_and_join()
    before_match = you_marks(join_a.get("snapshot") or {}) or 0
    snap = pvp_kill(mid, token_a, token_b)
    earned = you_marks(snap)
    expect(snap.get("status") == "ended", "PvP ended")
    expect(earned == before_match + 25, f"PvP you.marks {before_match}→{earned} (+25)")
    evidence(f"PvP {mid} you.marks {before_match}→{earned} endReason={snap.get('endReason')}")

    # --- S1 buy OK (needs ≥50). LIVE wallets are per playerId; one kill is +25. ---
    print("\n== S1 buy ==")
    buy_id_s1 = str(uuid.uuid4())
    code, body, raw = buy(token_a, buy_id_s1)
    after = you_marks(body)
    evidence(f"S1 POST /shop/buy {code} {json.dumps(body)} before={earned} clientBuyId={buy_id_s1}")
    s1_ok = code == 200 and body.get("ok") is True
    if s1_ok:
        expect(after == (earned or 0) - PRICE, f"S1 you.marks debit {earned}→{after} (−{PRICE})")
        expect("purchaseId" in body, "S1 purchaseId present")
        item = body.get("item") or {}
        expect(item.get("id") == ITEM or item.get("itemId") == ITEM, "S1 item skin_hideout_stub")
        # Client bind rule: display cache would take `after`, never earned-PRICE locally.
        note("S1 client bind = response you.marks only (no local marks -=)")
    else:
        expect(code == 402, f"S1 expected 200 debit or 402 (got {code})", raw)
        expect(after == earned, f"S1 rejected; balance unchanged {earned} → {after}")
        note(
            f"S1 cannot 200 on LIVE: player wallet {earned} < ★{PRICE}. "
            "Wallets are per playerId; POST /matches and POST /jobs mint a new player at 0. "
            "Max single-match earn is PvP kill +25 (2× kill was Coder's price rationale)."
        )
        FAILS.append("S1 buy OK (you.marks −50)")

    # --- S3 idempotent replay ---
    print("\n== S3 idempotent clientBuyId ==")
    code_r, body_r, raw_r = buy(token_a, buy_id_s1)
    replay_marks = you_marks(body_r)
    evidence(f"S3 replay {code_r} {json.dumps(body_r)} clientBuyId={buy_id_s1}")
    if s1_ok:
        expect(code_r == 200 and body_r.get("ok") is True, f"S3 replay 200 (got {code_r})", raw_r)
        expect(replay_marks == after, f"S3 replay no second debit {after} → {replay_marks}")
        expect(body_r.get("purchaseId") == body.get("purchaseId"), "S3 same purchaseId")
    else:
        expect(code_r == code, f"S3 replay same status {code} (got {code_r})")
        expect(replay_marks == after, f"S3 replay balance still {after} (got {replay_marks})")
        note("S3 one-debit not observed: S1 never charged. Replay stayed non-debit.")
        FAILS.append("S3 one debit on replay")

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
        print("LIVE_SHOP_SMOKE_FAIL", len(FAILS))
        for line in FAILS:
            print(f"  - {line}")
        return 1
    print("LIVE_SHOP_SMOKE_OK", mid, f"marks {earned}->{after}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
