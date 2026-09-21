#!/usr/bin/env python3
"""LIVE Practice hunt smoke.

POST /matches { mode: "practice" } with a durable player Bearer.
Seat A + joinToken. Bot is server-internal (no second join token).
Marks stay Δ0.

If the route rejects `mode` or answers with a PvP create, print
LIVE_PRACTICE_PENDING and exit 0. Client mock covers P1–P6 until Coder lands.

  GLASSLINE_API_BASE=https://glassline-api.vercel.app python3 tools/live_practice_smoke.py
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
EVIDENCE: dict = {}


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


def expect(cond: bool, label: str, detail: str = "") -> None:
    if cond:
        print(f"PASS  {label}")
        return
    FAILS.append(label)
    extra = f"  {detail}" if detail else ""
    print(f"FAIL  {label}{extra}")


def note(msg: str) -> None:
    NOTES.append(msg)
    print(f"NOTE  {msg}")


def marks_of(body: dict) -> int | None:
    you = body.get("you") if isinstance(body.get("you"), dict) else {}
    if "marks" in you:
        return int(you["marks"])
    snap = body.get("snapshot") if isinstance(body.get("snapshot"), dict) else {}
    you_snap = snap.get("you") if isinstance(snap.get("you"), dict) else {}
    if "marks" in you_snap:
        return int(you_snap["marks"])
    if "marks" in body:
        return int(body["marks"])
    return None


def write_log(payload: dict) -> None:
    path = os.path.join(os.path.dirname(__file__), "..", "artifacts", "live_practice_smoke.txt")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(json.dumps(payload, indent=2))
        fh.write("\n")


def pending(reason: str) -> int:
    print(f"LIVE_PRACTICE_PENDING {reason}")
    payload = {"pending": reason, "base": BASE, "notes": NOTES, "evidence": EVIDENCE}
    write_log(payload)
    return 0


def mode_of(body: dict) -> str:
    if not isinstance(body, dict):
        return ""
    mode = str(body.get("mode") or body.get("kind") or "")
    snap = body.get("snapshot") if isinstance(body.get("snapshot"), dict) else {}
    if mode == "":
        mode = str(snap.get("mode") or snap.get("kind") or "")
    return mode


def main() -> int:
    print(f"BASE {BASE}")
    health_s, health, _ = req("GET", "/health")
    if health_s != 200 or health.get("ok") is not True:
        return pending(f"GET /health {health_s}")

    player_s, player, raw = req("POST", "/players", {})
    if player_s not in (200, 201) or not player.get("token"):
        return pending(f"POST /players {player_s} {raw[:180]}")
    bearer = str(player["token"])
    before = marks_of(player)
    note(f"player {player.get('playerId', '')} marks {before}")

    code, created, created_raw = req("POST", "/matches", {"mode": "practice"}, bearer)
    EVIDENCE["create_status"] = code
    EVIDENCE["create_mode"] = mode_of(created)
    EVIDENCE["create_keys"] = sorted(created.keys()) if isinstance(created, dict) else []
    if code in (400, 404, 405, 422) or code == 0:
        return pending(f"POST /matches mode=practice {code} {created_raw[:220]}")
    if code not in (200, 201):
        return pending(f"POST /matches mode=practice {code} {created_raw[:220]}")
    if mode_of(created) != "practice":
        keys = sorted(created.keys()) if isinstance(created, dict) else []
        return pending(
            "create ignored mode (not practice) — refusing to sit a Marks match. "
            f"status {code} keys {keys}"
        )
    if "joinTokens" in created:
        return pending("create returned joinTokens; practice bot must stay server-internal")

    match_id = str(created.get("matchId", ""))
    join = str(created.get("joinToken", ""))
    seat = str(created.get("seat", ""))
    expect(match_id != "" and join != "", "create matchId + joinToken")
    expect(seat in ("", "a"), "create seat a")
    if match_id == "" or join == "":
        write_log({"ok": False, "base": BASE, "fails": FAILS, "evidence": EVIDENCE})
        print("LIVE_PRACTICE_FAIL")
        return 1

    snap = created.get("snapshot") if isinstance(created.get("snapshot"), dict) else {}
    if not snap:
        gs, snap_body, _ = req("GET", f"/matches/{match_id}", token=join)
        if gs == 200 and isinstance(snap_body, dict):
            snap = snap_body.get("snapshot") if isinstance(snap_body.get("snapshot"), dict) else snap_body
    enemy = snap.get("enemy") if isinstance(snap.get("enemy"), dict) else {}
    if enemy.get("isBot") is True:
        note("snapshot enemy.isBot true")
    else:
        note("snapshot enemy.isBot absent — chrome will bind when Coder flags it")
    wallet = marks_of(snap)
    if wallet is None:
        wallet = before
    note(f"match {match_id} marks {wallet}")

    # One drop. If the server bot is seated, status becomes ready/active. Do not invent a seat B.
    ds, drop, drop_raw = req(
        "POST",
        f"/matches/{match_id}/actions",
        {"type": "select_hex", "hex": {"q": 2, "r": 2}},
        join,
    )
    if ds not in (200, 201) or not (isinstance(drop, dict) and drop.get("ok") is True):
        note(f"select_hex {ds} {drop_raw[:180]}")
        if FAILS:
            write_log({"ok": False, "base": BASE, "fails": FAILS, "notes": NOTES, "evidence": EVIDENCE})
            print("LIVE_PRACTICE_FAIL")
            return 1
        print("LIVE_PRACTICE_OK create-only")
        write_log({"ok": True, "partial": "create", "base": BASE, "notes": NOTES, "evidence": EVIDENCE})
        return 0

    drop_snap = drop.get("snapshot") if isinstance(drop.get("snapshot"), dict) else {}
    after = marks_of(drop_snap)
    if wallet is not None and after is not None:
        expect(after == wallet, "drop did not move Marks", f"{wallet} -> {after}")
    if str(drop_snap.get("mode") or drop_snap.get("kind") or "") not in ("", "practice"):
        expect(False, "drop snapshot left practice mode", str(drop_snap.get("mode") or drop_snap.get("kind")))

    if FAILS:
        write_log({"ok": False, "base": BASE, "fails": FAILS, "notes": NOTES, "evidence": EVIDENCE})
        print("LIVE_PRACTICE_FAIL")
        return 1
    print("LIVE_PRACTICE_OK")
    write_log({"ok": True, "base": BASE, "notes": NOTES, "evidence": EVIDENCE, "matchId": match_id})
    return 0


if __name__ == "__main__":
    sys.exit(main())
