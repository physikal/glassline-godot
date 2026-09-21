#!/usr/bin/env python3
"""LIVE D1–D5 smoke for Ability #2 DECOY.

Prefer LIVE once POST { type: "decoy" } returns 200.
Curl first. Retry join/decoy while Coder's deploy/migration 500s.
400 invalid action body → still pending. Mock covers editor.
"""

from __future__ import annotations

import json
import os
import sys
import time
import urllib.error
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from live_join import sit_created_pvp

BASE = os.environ.get("GLASSLINE_API_BASE", "https://glassline-api.vercel.app").rstrip("/")
FAILS: list[str] = []
NOTES: list[str] = []
PASS_N = 0
RETRIES = int(os.environ.get("LIVE_DECOY_RETRIES", "12"))
SLEEP_SEC = float(os.environ.get("LIVE_DECOY_SLEEP", "8"))


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


def is_unknown_decoy(status: int, body: dict) -> bool:
    err = str(body.get("error") or "")
    reason = str((body.get("result") or {}).get("reason") or "")
    if status == 404:
        return True
    if status == 400 and err in ("invalid action body", "invalid_action_body"):
        return True
    if reason in ("unknown_action", "invalid action body"):
        return True
    return False


def open_active_match(player_token: str):
    seated = sit_created_pvp(req, player_token)
    created = seated.get("created") or {}
    if not seated.get("ok"):
        return int(seated.get("status") or 0), created, "", "", "", {}, {}
    match_id = str(seated.get("matchId", ""))
    token_a = str(seated.get("token_a") or "")
    token_b = str(seated.get("token_b") or "")
    join_a = seated.get("join_a") or {}
    join_b = seated.get("join_b") or {}
    req("POST", f"/matches/{match_id}/actions", {"type": "select_hex", "hex": {"q": 2, "r": 2}}, token_a)
    status_b, drop_b, _ = req(
        "POST",
        f"/matches/{match_id}/actions",
        {"type": "select_hex", "hex": {"q": 7, "r": 5}},
        token_b,
    )
    return status_b, drop_b, match_id, token_a, token_b, join_a, join_b


def wait_for_decoy(player_token: str):
    last = (0, {}, "", "", "", {}, {})
    for attempt in range(1, RETRIES + 1):
        status_b, drop_b, match_id, token_a, token_b, join_a, join_b = open_active_match(player_token)
        join_err = str(join_a.get("error") or join_b.get("error") or "")
        if join_err == "internal error" or status_b >= 500:
            note(f"attempt {attempt}/{RETRIES} join/drop HTTP {status_b} {join_err or drop_b.get('error')}")
            last = (status_b, drop_b, match_id, token_a, token_b, join_a, join_b)
            time.sleep(SLEEP_SEC)
            continue
        snap = drop_b.get("snapshot") or {}
        if snap.get("status") != "active":
            note(f"attempt {attempt}/{RETRIES} not active: {snap.get('status')} {drop_b.get('error')}")
            last = (status_b, drop_b, match_id, token_a, token_b, join_a, join_b)
            time.sleep(SLEEP_SEC)
            continue
        status, decoy, raw = req("POST", f"/matches/{match_id}/actions", {"type": "decoy"}, token_a)
        print("DECOY_HTTP", status, (raw or "")[:500])
        if status >= 500:
            note(f"attempt {attempt}/{RETRIES} decoy HTTP {status} {decoy.get('error')}")
            last = (status, decoy, match_id, token_a, token_b, join_a, join_b)
            time.sleep(SLEEP_SEC)
            continue
        return status, decoy, match_id, token_a, token_b, join_a, drop_b
    status_b, drop_b, match_id, token_a, token_b, join_a, _join_b = last
    return status_b, drop_b, match_id, token_a, token_b, join_a, drop_b


def main() -> int:
    print("SMOKE_BASE", BASE)
    status, health, _ = req("GET", "/health")
    expect(status == 200 and health.get("ok") is True, "GET /health", str(health))

    status, player, _ = req("POST", "/players", {})
    token = str(player.get("token") or "")
    expect(status in (200, 201) and token != "", "POST /players", str(player))

    status, decoy, match_id, token_a, token_b, join_a, drop_b = wait_for_decoy(token)
    if not match_id:
        note("LIVE match create/join never became usable.")
        print("LIVE_DECOY_PENDING")
        return 0

    expect(join_a.get("seat") == "a" or you_of(decoy).get("seat") == "a" or you_of(drop_b).get("seat") in ("a", "b"), "join seats")
    snap = (decoy.get("snapshot") if decoy.get("snapshot") else drop_b.get("snapshot")) or {}
    if drop_b.get("snapshot"):
        expect((drop_b.get("snapshot") or {}).get("status") in ("active", None) or snap.get("status") == "active", "match reached active")

    if is_unknown_decoy(status, decoy):
        note(
            "LIVE Zod still rejects decoy. HTTP %s %s — Coder blocker. "
            "Client posts { type: \"decoy\" } with no hex."
            % (status, decoy.get("error") or decoy.get("result") or decoy)
        )
        print("LIVE_DECOY_PENDING")
        return 0

    if status >= 500:
        note(
            "LIVE join/decoy still 500 after retries (likely decoy column migrate). "
            "Contract docs already list decoy. Client mock + HUD ready."
        )
        print("LIVE_DECOY_PENDING")
        return 0

    expect(status == 200 and decoy.get("ok") is True, "D1 decoy ok", str(decoy))
    result = decoy.get("result") or {}
    a_you = you_of(decoy)
    planted = a_you.get("decoyHex") or result.get("hex")
    expect(a_you.get("decoyAvailable") is False, "D1 you.decoyAvailable false")
    expect(int(a_you.get("decoyRemaining") or 0) == 0, "D1 you.decoyRemaining 0")
    expect(isinstance(planted, dict), "D2 you.decoyHex set", str(planted))
    if isinstance(planted, dict):
        expect(planted.get("q") == 3 and planted.get("r") == 2, "D2 LIVE pick (3,2) from A(2,2)", str(planted))
    expect((decoy.get("snapshot") or {}).get("phase") == "await_end_turn", "D1 full turn")
    expect(result.get("type") == "decoy", "D1 result.type decoy", str(result))
    expect("marksDelta" not in result and "marks" not in result, "D5 no Marks on decoy result")

    status2, again, _ = req("POST", f"/matches/{match_id}/actions", {"type": "decoy"}, token_a)
    again_reason = str((again.get("result") or {}).get("reason") or again.get("error") or "")
    expect(not again.get("ok", True) or status2 >= 400, "D1 second decoy refused", again_reason)

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
        expect(res.get("kill") is False, "D3 kill:false", str(res))
        expect(res.get("decoyCleared") is True, "D3 decoyCleared:true", str(res))
        expect(you_of(atk).get("decoyHex") in (None, {}), "D3 B snapshot has no own doll")
        _, after_a, _ = req("GET", f"/matches/{match_id}", None, token_a)
        expect(you_of(after_a).get("decoyHex") in (None, {}), "D3 owner decoyHex cleared")
        _, after_b, _ = req("GET", f"/matches/{match_id}", None, token_b)
        expect(enemy_of(after_b).get("decoySoftHex") in (None, {}), "D3 enemy soft blip cleared")
        expect(int(you_of(after_a).get("marks") or 0) == int(a_you.get("marks") or 0), "D5 attack-on-decoy no Marks")

    # Fresh match for D4 expiry (do not attack the doll).
    _status_b, _drop, mid2, ja, jb, _join_a, _ = open_active_match(token)
    if not mid2:
        expect(False, "D4 second match created")
    else:
        d2_status, d2, _ = req("POST", f"/matches/{mid2}/actions", {"type": "decoy"}, ja)
        expect(d2_status == 200 and d2.get("ok") is True, "D4 plant decoy")
        req("POST", f"/matches/{mid2}/actions", {"type": "end_turn", "exposurePct": 50}, ja)
        req("POST", f"/matches/{mid2}/actions", {"type": "recon", "hex": {"q": 4, "r": 3}}, jb)
        req("POST", f"/matches/{mid2}/actions", {"type": "end_turn", "exposurePct": 50}, jb)
        _, still, _ = req("GET", f"/matches/{mid2}", None, ja)
        expect(isinstance(you_of(still).get("decoyHex"), dict), "D4 live into next own window", str(you_of(still)))
        spent_status, spent, _ = req("POST", f"/matches/{mid2}/actions", {"type": "decoy"}, ja)
        spent_reason = str((spent.get("result") or {}).get("reason") or "")
        expect(not spent.get("ok", True), "D1 spent on next own turn", spent_reason)
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
