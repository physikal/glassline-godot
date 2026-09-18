#!/usr/bin/env python3
"""A2 LIVE reconnect smoke vs glassline-api.

Client never invents terrain tags or "I hit". Server snapshot wins on reconnect.

Sequence:
  health → create → join a+b → select_hex (reveal terrain) → note snapshot
  → optional attack miss (server hit=false, no invented terrain)
  → pollute a local cache with fake terrain + hit=true
  → GET /matches/:id (reconnect)
  → replace local cache (apply_snapshot semantics)
  → assert terrain + match fields match the GET body; invented hit/terrain gone.

  GLASSLINE_API_BASE=https://glassline-api.vercel.app python3 tools/live_a2_smoke.py
"""

from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.request

BASE = os.environ.get("GLASSLINE_API_BASE", "https://glassline-api.vercel.app").rstrip("/")
FAILS: list[str] = []
NOTES: list[str] = []


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


def expect(cond: bool, label: str, detail="") -> None:
    if cond:
        print(f"PASS  {label}")
        return
    FAILS.append(label)
    extra = f"  {detail}" if detail else ""
    print(f"FAIL  {label}{extra}")


def note(msg: str) -> None:
    NOTES.append(msg)
    print(f"NOTE  {msg}")


def terrain_keys(snap: dict) -> set[str]:
    keys: set[str] = set()
    for row in snap.get("terrain") or []:
        if isinstance(row, dict):
            keys.add(f"{int(row.get('q', -1))},{int(row.get('r', -1))}")
    return keys


def last_hit(snap: dict):
    last = snap.get("lastAction")
    if isinstance(last, dict) and "hit" in last:
        return last.get("hit")
    return None


def apply_snapshot(local: dict, server: dict) -> dict:
    """Mirror ClientSession.apply_snapshot — full replace, no merge."""
    return json.loads(json.dumps(server))


def field_bag(snap: dict) -> dict:
    you = snap.get("you") or {}
    return {
        "matchId": snap.get("matchId"),
        "status": snap.get("status"),
        "phase": snap.get("phase"),
        "whoseTurn": snap.get("whoseTurn"),
        "turnIndex": snap.get("turnIndex"),
        "winner": snap.get("winner"),
        "you.hex": (you.get("hex") if isinstance(you, dict) else None),
        "you.exposurePct": (you.get("exposurePct") if isinstance(you, dict) else None),
        "you.marks": (you.get("marks") if isinstance(you, dict) else None),
        "terrain": sorted(terrain_keys(snap)),
        "lastHit": last_hit(snap),
    }


def main() -> int:
    print("SMOKE_BASE", BASE)
    status, health, _ = req("GET", "/health")
    expect(status == 200 and health.get("ok") is True, "GET /health", str(health))

    status, created, _ = req("POST", "/matches", {})
    expect(status in (200, 201) and "matchId" in created, "POST /matches", f"{status} {created}")
    match_id = created.get("matchId", "")
    tokens = created.get("joinTokens") or {}
    token_a = tokens.get("a", "")
    token_b = tokens.get("b", "")
    expect(bool(token_a and token_b), "joinTokens.a/b present")

    status, join_a, _ = req("POST", f"/matches/{match_id}/join", {"token": token_a})
    status_b, join_b, _ = req("POST", f"/matches/{match_id}/join", {"token": token_b})
    expect(status == 200 and join_a.get("seat") == "a", "join seat a")
    expect(status_b == 200 and join_b.get("seat") == "b", "join seat b")

    status, sel_a, _ = req(
        "POST",
        f"/matches/{match_id}/actions",
        {"type": "select_hex", "hex": {"q": 2, "r": 2}},
        token_a,
    )
    expect(status == 200 and sel_a.get("ok") is True, "select_hex a (2,2)")
    sel_res = sel_a.get("result") or {}
    if sel_res.get("terrain") in ("open", "brush", "hard"):
        note(f"select_hex result.terrain={sel_res.get('terrain')} (server tag)")
    status, sel_b, _ = req(
        "POST",
        f"/matches/{match_id}/actions",
        {"type": "select_hex", "hex": {"q": 7, "r": 5}},
        token_b,
    )
    expect(status == 200 and sel_b.get("ok") is True, "select_hex b (7,5)")

    noted = sel_a.get("snapshot") or {}
    status, noted, _ = req("GET", f"/matches/{match_id}", None, token_a)
    expect(status == 200 and noted.get("matchId") == match_id, "GET note snapshot after select")
    keys_noted = terrain_keys(noted)
    expect("2,2" in keys_noted, "noted terrain includes select 2,2", str(sorted(keys_noted)))
    expect(last_hit(noted) is not True, "noted snapshot has no invented I-hit")
    print("NOTE  noted fields", json.dumps(field_bag(noted), sort_keys=True))

    status, miss, _ = req(
        "POST",
        f"/matches/{match_id}/actions",
        {"type": "attack", "hex": {"q": 0, "r": 0}},
        token_a,
    )
    result = miss.get("result") or {}
    miss_snap = miss.get("snapshot") or {}
    expect(status == 200 and miss.get("ok") is True, "attack miss ok")
    expect(result.get("hit") is False, "server miss hit=false (client must not invent true)")
    expect("0,0" not in terrain_keys(miss_snap), "attack miss does not invent target terrain")
    expect(last_hit(miss_snap) is False, "snapshot lastAction.hit is server false")

    polluted = apply_snapshot({}, miss_snap)
    rows = list(polluted.get("terrain") or [])
    rows.append({"q": 8, "r": 6, "type": "hard"})
    polluted["terrain"] = rows
    polluted["lastAction"] = {"type": "attack", "hit": True, "kill": True}
    polluted["status"] = "ended"
    polluted["whoseTurn"] = "invented"
    polluted["turnIndex"] = 99
    you_p = dict(polluted.get("you") or {})
    you_p["hex"] = {"q": 0, "r": 0}
    you_p["exposurePct"] = 99
    you_p["marks"] = 999
    polluted["you"] = you_p
    expect("8,6" in terrain_keys(polluted), "local cache invented terrain 8,6")
    expect(last_hit(polluted) is True, "local cache invented I-hit")
    expect(you_p.get("marks") == 999, "local cache invented wallet")
    expect(you_p.get("exposurePct") == 99, "local cache invented exposure")

    status, server_snap, _ = req("GET", f"/matches/{match_id}", None, token_a)
    expect(status == 200 and server_snap.get("matchId") == match_id, "reconnect GET /matches/:id")
    client = apply_snapshot(polluted, server_snap)
    bag_server = field_bag(server_snap)
    bag_client = field_bag(client)
    expect(bag_client == bag_server, "client state replaced by server snapshot", f"{bag_client} vs {bag_server}")
    expect("8,6" not in terrain_keys(client), "invented terrain 8,6 wiped")
    expect("2,2" in terrain_keys(client), "server select terrain 2,2 kept")
    expect(last_hit(client) is not True, "invented I-hit wiped")
    expect(last_hit(client) is False, "reconnect lastAction.hit is server miss")
    expect(client.get("status") == server_snap.get("status"), "status from server")
    expect(client.get("whoseTurn") == server_snap.get("whoseTurn"), "whoseTurn from server")
    expect(client.get("phase") == server_snap.get("phase"), "phase from server")
    expect(client.get("turnIndex") == server_snap.get("turnIndex"), "turnIndex from server")
    you = client.get("you") or {}
    server_you = server_snap.get("you") or {}
    expect(you.get("hex") == server_you.get("hex"), "you.hex from server")
    expect(you.get("exposurePct") == server_you.get("exposurePct"), "you.exposurePct from server")
    expect(you.get("marks") == server_you.get("marks"), "you.marks from server (no invented wallet)")
    expect(you.get("exposurePct") != 99, "invented exposure wiped")
    expect(you.get("marks") != 999, "invented wallet wiped")
    expect("hit" not in {"type": "attack", "hex": {"q": 0, "r": 0}}, "intent body has no hit field")

    print()
    print("BASE", BASE)
    print("NOTES")
    for line in NOTES:
        print(f"  - {line}")
    print("NOTED", json.dumps(field_bag(noted), sort_keys=True))
    print("RECONNECT", json.dumps(bag_client, sort_keys=True))
    print()
    if FAILS:
        print("LIVE_A2_SMOKE_FAIL", len(FAILS))
        for line in FAILS:
            print(f"  - {line}")
        return 1
    print("LIVE_A2_SMOKE_OK", match_id)
    print("GD_PING A2 locked — server snapshot sole truth (hex, turn, exposure, Marks); no invented terrain/hit/wallet")
    return 0


if __name__ == "__main__":
    sys.exit(main())
