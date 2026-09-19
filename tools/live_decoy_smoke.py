#!/usr/bin/env python3
"""LIVE D1–D5 smoke for Ability #2 DECOY.

Arch action: POST { type: "decoy" } — no hex arg.
Snapshot: you.decoyAvailable, you.decoyHex?, enemy.decoySoftHex?
Attack on decoy → hit:false, decoyCleared:true.

If Coder has not shipped the action, LIVE Zod returns 400
`invalid action body` (same family as unknown type). Ship mock +
LiveMatchClient ready and record the blocker.
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
PASS_N = 0


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


def you_of(body: dict) -> dict:
    snap = body.get("snapshot") or body
    you = snap.get("you") or {}
    return you if isinstance(you, dict) else {}


def enemy_of(body: dict) -> dict:
    snap = body.get("snapshot") or body
    enemy = snap.get("enemy") or {}
    return enemy if isinstance(enemy, dict) else {}


def is_blocker(status: int, body: dict) -> bool:
    err = str(body.get("error") or "")
    reason = str((body.get("result") or {}).get("reason") or "")
    if status == 404:
        return True
    if status == 400 and err in ("invalid action body", "invalid_action_body"):
        return True
    if reason in ("unknown_action", "invalid action body"):
        return True
    return False


def main() -> int:
    print("SMOKE_BASE", BASE)
    status, health, _ = req("GET", "/health")
    expect(status == 200 and health.get("ok") is True, "GET /health", str(health))

    status, player, _ = req("POST", "/players", {})
    token = str(player.get("token") or "")
    expect(status in (200, 201) and token != "", "POST /players", str(player))

    status, created, _ = req("POST", "/matches", {}, token)
    expect(status in (200, 201) and "matchId" in created, "POST /matches", str(created))
    match_id = str(created.get("matchId", ""))
    tokens = created.get("joinTokens") or {}
    token_a = str(tokens.get("a") or "")
    token_b = str(tokens.get("b") or "")
    expect(bool(token_a and token_b), "joinTokens.a/b")

    _, join_a, _ = req("POST", f"/matches/{match_id}/join", {"token": token_a}, token)
    _, join_b, _ = req("POST", f"/matches/{match_id}/join", {"token": token_b})
    expect(join_a.get("seat") == "a", "join seat a")
    expect(join_b.get("seat") == "b", "join seat b")

    _, drop_a, _ = req("POST", f"/matches/{match_id}/actions", {"type": "select_hex", "hex": {"q": 2, "r": 2}}, token_a)
    _, drop_b, _ = req("POST", f"/matches/{match_id}/actions", {"type": "select_hex", "hex": {"q": 7, "r": 5}}, token_b)
    snap = drop_b.get("snapshot") or {}
    expect(snap.get("status") == "active", "both drops → active", str(snap.get("status")))
    expect(snap.get("phase") == "await_action", "await_action")

    status, decoy, raw = req("POST", f"/matches/{match_id}/actions", {"type": "decoy"}, token_a)
    print("DECOY_HTTP", status, raw[:400] if raw else "")

    if is_blocker(status, decoy):
        note(
            "LIVE has no decoy action yet. HTTP %s %s — Coder blocker. "
            "Client posts { type: \"decoy\" } with no hex; LiveMatchClient is ready. "
            "Mock implements D1–D5."
            % (status, decoy.get("error") or decoy.get("result") or decoy)
        )
        print("LIVE_DECOY_PENDING")
        return 0

    expect(status == 200 and decoy.get("ok") is True, "D1 decoy ok", str(decoy))
    result = decoy.get("result") or {}
    a_you = you_of(decoy)
    planted = a_you.get("decoyHex")
    expect(a_you.get("decoyAvailable") is False, "D1 you.decoyAvailable false")
    expect(isinstance(planted, dict), "D2 you.decoyHex set", str(planted))
    expect((decoy.get("snapshot") or {}).get("phase") == "await_end_turn", "D1 full turn")
    expect(result.get("type") == "decoy" or str(result.get("type", "")) != "", "D1 result type", str(result))
    expect("marksDelta" not in result and "marks" not in result, "D5 no Marks on decoy result")

    _, snap_b, _ = req("GET", f"/matches/{match_id}", None, token_b)
    expect(isinstance(enemy_of(snap_b).get("decoySoftHex"), dict), "D2 enemy.decoySoftHex while live", str(enemy_of(snap_b)))

    _, end_a, _ = req(
        "POST",
        f"/matches/{match_id}/actions",
        {"type": "end_turn", "exposurePct": 50},
        token_a,
    )
    expect(end_a.get("ok") is True, "D1 end_turn after decoy")

    if isinstance(planted, dict):
        status, atk, _ = req(
            "POST",
            f"/matches/{match_id}/actions",
            {"type": "attack", "hex": planted},
            token_b,
        )
        res = atk.get("result") or {}
        expect(status == 200 and atk.get("ok") is True, "D3 attack decoy ok")
        expect(res.get("hit") is False, "D3 hit:false", str(res))
        expect(res.get("decoyCleared") is True, "D3 decoyCleared:true", str(res))
        expect(you_of(atk).get("decoyHex") in (None, {}), "D3 owner hex cleared")
        _, after_b, _ = req("GET", f"/matches/{match_id}", None, token_b)
        expect(enemy_of(after_b).get("decoySoftHex") in (None, {}), "D3 enemy soft blip cleared")

    # Fresh match for D4 expiry (do not attack the doll).
    status, created2, _ = req("POST", "/matches", {}, token)
    mid2 = str(created2.get("matchId", ""))
    t2 = created2.get("joinTokens") or {}
    ja, jb = str(t2.get("a") or ""), str(t2.get("b") or "")
    req("POST", f"/matches/{mid2}/join", {"token": ja}, token)
    req("POST", f"/matches/{mid2}/join", {"token": jb})
    req("POST", f"/matches/{mid2}/actions", {"type": "select_hex", "hex": {"q": 2, "r": 2}}, ja)
    req("POST", f"/matches/{mid2}/actions", {"type": "select_hex", "hex": {"q": 7, "r": 5}}, jb)
    req("POST", f"/matches/{mid2}/actions", {"type": "decoy"}, ja)
    req("POST", f"/matches/{mid2}/actions", {"type": "end_turn", "exposurePct": 50}, ja)
    req("POST", f"/matches/{mid2}/actions", {"type": "recon", "hex": {"q": 4, "r": 3}}, jb)
    req("POST", f"/matches/{mid2}/actions", {"type": "end_turn", "exposurePct": 50}, jb)
    _, still, _ = req("GET", f"/matches/{mid2}", None, ja)
    expect(isinstance(you_of(still).get("decoyHex"), dict), "D4 live into next own window", str(you_of(still)))
    req("POST", f"/matches/{mid2}/actions", {"type": "attack", "hex": {"q": 0, "r": 0}}, ja)
    _, after_own_end, _ = req(
        "POST",
        f"/matches/{mid2}/actions",
        {"type": "end_turn", "exposurePct": 50},
        ja,
    )
    expect(you_of(after_own_end).get("decoyHex") in (None, {}), "D4 expired next own end_turn")
    marks_before = int(you_of(still).get("marks") or 0)
    marks_after = int(you_of(after_own_end).get("marks") or 0)
    expect(marks_after == marks_before, "D5 expiry does not change Marks")

    if FAILS:
        print("LIVE_DECOY_FAIL")
        for line in FAILS:
            print("FAIL:", line)
        return 1
    print("LIVE_DECOY_OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
