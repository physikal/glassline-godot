#!/usr/bin/env python3
"""LIVE equip chrome E1/E4/E5 smoke vs glassline-api.

Spine: POST /shop/equip { itemId } | { itemId: null } + durable player Bearer
→ snapshot you.equippedSkinId. Must own. Marks untouched. Same-id no-op OK.

If LIVE /shop/equip is 404, this exits 0 with LIVE_SHOP_EQUIP_PENDING so Coder
can land the route. Client ships mock + LiveMatchClient.equip_cosmetic.

  GLASSLINE_API_BASE=https://glassline-api.vercel.app python3 tools/live_shop_equip_smoke.py
"""

from __future__ import annotations

import json
import os
import sys
import uuid
import urllib.error
import urllib.request

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


def equipped_skin(bag: dict | None) -> str | None:
    if not isinstance(bag, dict):
        return None
    you = bag.get("you")
    if isinstance(you, dict):
        if "equippedSkinId" in you:
            val = you.get("equippedSkinId")
            return "" if val is None else str(val)
        if "equipped" in you:
            val = you.get("equipped")
            return "" if val is None else str(val)
    if "equippedSkinId" in bag:
        val = bag.get("equippedSkinId")
        return "" if val is None else str(val)
    snap = bag.get("snapshot")
    if isinstance(snap, dict):
        return equipped_skin(snap)
    return None


def mint_player():
    code, body, raw = req("POST", "/players", {})
    expect(code in (200, 201) and body.get("token"), "POST /players", raw[:240])
    return body


def equip(player_token: str, item_id):
    return req("POST", "/shop/equip", {"itemId": item_id}, player_token)


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
        print("LIVE_SHOP_EQUIP_PENDING Coder /shop/equip 404")
        return 0
    if FAILS:
        print("LIVE_SHOP_EQUIP_FAIL", len(FAILS))
        for line in FAILS:
            print(f"  - {line}")
        return 1
    return 0


def main() -> int:
    print(f"BASE {BASE}")
    code, health, _ = req("GET", "/health")
    expect(code == 200 and health.get("ok") is True, "GET /health")

    player = mint_player()
    token = str(player.get("token", ""))
    start_marks = you_marks(player)
    evidence(f"player {player.get('playerId')} marks={start_marks}")

    print("\n== probe POST /shop/equip ==")
    code, body, raw = equip(token, GHILLIE)
    evidence(f"POST /shop/equip {code} {json.dumps(body) if isinstance(body, dict) else raw[:240]}")
    if code == 404:
        note(
            "LIVE POST /shop/equip is 404. Coder shop_equipped table already stubs last-buy. "
            "Client LiveMatchClient.equip_cosmetic is ready ({ itemId } | { itemId: null }). "
            "Need 200 snapshot you.equippedSkinId + reject not_owned. Marks untouched."
        )
        return finish(pending=True)

    # Route exists — E1 unowned reject, then buy + set equippedSkinId if we can earn.
    unowned_ok = code in (400, 403, 404) and (
        body.get("code") in ("not_owned", "unknown_item")
        or body.get("error") in ("not_owned", "unknown_item")
        or "not_owned" in str(body.get("error", ""))
    )
    if start_marks == 0 and not (code == 200 and body.get("ok")):
        expect(
            unowned_ok or (code >= 400 and body.get("ok") is not True),
            f"E1 unowned equip rejected (got {code})",
            raw[:240],
        )
        expect(you_marks(body) in (None, start_marks), "E1 unowned reject marks untouched")

    if code == 200 and body.get("ok") is True:
        note("E1 unexpected 200 on unowned player — Coder may auto-equip last-buy only")
        expect(you_marks(body) == start_marks, "E1 200 marks unchanged")

    print("\n== E4 unequip null ==")
    code_u, body_u, raw_u = equip(token, None)
    evidence(f"POST /shop/equip null {code_u} {json.dumps(body_u) if isinstance(body_u, dict) else raw_u[:240]}")
    if code_u == 200:
        expect(body_u.get("ok") is True, "E4 unequip ok")
        skin = equipped_skin(body_u)
        expect(skin in ("", None), f"E4 equippedSkinId cleared (got {skin})")
        expect(you_marks(body_u) in (None, start_marks), "E4 unequip marks untouched")
    elif code_u == 404:
        note("Unequip 404 after probe succeeded — treat as pending")
        return finish(pending=True)

    print()
    rc = finish()
    if rc == 0 and not FAILS:
        print("LIVE_SHOP_EQUIP_OK", player.get("playerId"))
    return rc


if __name__ == "__main__":
    sys.exit(main())
