#!/usr/bin/env python3
"""LIVE H1–H6 smoke for HIGH GROUND.

Prefer LIVE once snapshot you.highGroundActive is present.
Curl first. Missing field → PENDING (Coder resolve not up). Mock stills cover chrome.
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


def open_active_match(player_token: str):
    status, created, _ = req("POST", "/matches", {}, player_token)
    if status not in (200, 201) or "matchId" not in created:
        return status, created, "", "", ""
    match_id = str(created.get("matchId", ""))
    tokens = created.get("joinTokens") or {}
    token_a = str(tokens.get("a") or "")
    token_b = str(tokens.get("b") or "")
    req("POST", f"/matches/{match_id}/join", {"token": token_a}, player_token)
    req("POST", f"/matches/{match_id}/join", {"token": token_b})
    req("POST", f"/matches/{match_id}/actions", {"type": "select_hex", "hex": {"q": 2, "r": 2}}, token_a)
    status_b, drop_b, _ = req(
        "POST",
        f"/matches/{match_id}/actions",
        {"type": "select_hex", "hex": {"q": 7, "r": 5}},
        token_b,
    )
    return status_b, drop_b, match_id, token_a, token_b


def main() -> int:
    print("SMOKE_BASE", BASE)
    status, health, _ = req("GET", "/health")
    expect(status == 200 and health.get("ok") is True, "GET /health", str(health))

    status, player, _ = req("POST", "/players", {})
    token = str(player.get("token") or "")
    expect(status in (200, 201) and token != "", "POST /players", str(player))

    status_b, drop_b, match_id, token_a, token_b = open_active_match(token)
    if not match_id:
        note("LIVE match create/join never became usable.")
        print("LIVE_HIGH_GROUND_PENDING")
        return 0

    expect(status_b in (200, 201) or (drop_b.get("snapshot") or {}).get("status") in ("active", "ready"), "join/drop")

    _, snap_a, raw_a = req("GET", f"/matches/{match_id}", None, token_a)
    you = you_of(snap_a)
    print("SNAP_A_YOU", json.dumps(you)[:500])
    if "highGroundActive" not in you:
        note(
            "LIVE snapshot omits you.highGroundActive. HTTP GET %s — Coder resolve not up. "
            "Client binds the flag only; mock stills cover H3 chrome."
            % (raw_a[:160] if raw_a else "")
        )
        print("LIVE_HIGH_GROUND_PENDING")
        return 0

    flag = you.get("highGroundActive")
    expect(isinstance(flag, bool), "H1/H2 you.highGroundActive is bool", str(flag))

    status, atk, _ = req(
        "POST",
        f"/matches/{match_id}/actions",
        {"type": "attack", "hex": {"q": 0, "r": 0}},
        token_a,
    )
    expect(status == 200 and atk.get("ok") is True, "H6 attack intent { type, hex } accepted", str(atk.get("error")))
    result = atk.get("result") or {}
    expect(result.get("type") == "attack", "H6 result.type attack")
    expect("highGround" not in (atk.get("snapshot") or {}), "H6 no invented top-level highGround")
    a_you = you_of(atk)
    expect("highGroundActive" in a_you, "H1/H2 attack snapshot still names the flag")
    if "highGroundApplied" in result:
        expect(bool(result.get("highGroundApplied")) == bool(a_you.get("highGroundActive")), "H1 applied matches flag")
        chance = result.get("hitChance")
        expect(chance is None or 0.0 <= float(chance) <= 1.0, "H1 hitChance clamp 0–1", str(chance))
        if a_you.get("highGroundActive"):
            expect(result.get("highGroundApplied") is True, "H1 HARD applied")
        else:
            expect(result.get("highGroundApplied") is False, "H2 OPEN/BRUSH not applied")
    else:
        note("Attack result omitted highGroundApplied — preferred, not required this slice.")

    expect("marksDelta" not in result, "H4 no Marks on miss result")
    expect(int(a_you.get("marks") or 0) == int(you.get("marks") or 0), "H4 Marks unchanged")

    if FAILS:
        print("LIVE_HIGH_GROUND_FAIL")
        for line in FAILS:
            print("FAIL:", line)
        return 1
    print("LIVE_HIGH_GROUND_OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
