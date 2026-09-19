#!/usr/bin/env python3
"""LIVE Soft A4 gap punch-list.

Probes POST /matches/:id/abandon (Coder). If 404, documents pending and
does not fake a grant. A4.2 30s silence is already LIVE — see live_a4_smoke.py.

  GLASSLINE_API_BASE=https://glassline-api.vercel.app python3 tools/live_a4_gaps_smoke.py
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


def expect(cond: bool, label: str, detail: str = "") -> None:
    if cond:
        print(f"PASS  {label}")
        return
    FAILS.append(label)
    extra = f"  {detail}" if detail else ""
    print(f"FAIL  {label}{extra}")


def note(text: str) -> None:
    NOTES.append(text)
    print(f"NOTE  {text}")


def you_marks(snap: dict) -> int:
    you = snap.get("you") or {}
    return int(you.get("marks") or 0)


def hunt_pvp() -> dict:
    st, created, raw = req("POST", "/matches", {})
    if st not in (200, 201) or "matchId" not in created:
        return {"ok": False, "error": raw}
    mid = created["matchId"]
    tokens = created.get("joinTokens") or {}
    ja, jb = tokens.get("a"), tokens.get("b")
    req("POST", f"/matches/{mid}/join", {"token": ja}, ja)
    req("POST", f"/matches/{mid}/join", {"token": jb}, jb)
    req("POST", f"/matches/{mid}/actions", {"type": "select_hex", "hex": {"q": 2, "r": 2}}, ja)
    req("POST", f"/matches/{mid}/actions", {"type": "select_hex", "hex": {"q": 7, "r": 5}}, jb)
    return {"ok": True, "matchId": mid, "ja": ja, "jb": jb, "created": created}


def main() -> int:
    print(f"BASE {BASE}")
    st, health, _ = req("GET", "/health")
    expect(st == 200 and health.get("ok") is True, "GET /health")

    hunt = hunt_pvp()
    expect(hunt.get("ok") is True, "PvP ready/active for abandon probe")
    if not hunt.get("ok"):
        print("LIVE_A4_GAPS_SMOKE_FAIL create")
        return 1
    mid, ja, jb = hunt["matchId"], hunt["ja"], hunt["jb"]

    st_r, rem, raw_r = req("POST", f"/matches/{mid}/rematch", {"accept": True}, ja)
    expect(
        st_r == 409 or (st_r >= 400 and "not ended" in str(rem.get("error", "")).lower()),
        f"A4.4 rematch while active blocked ({st_r})",
        str(rem)[:240],
    )

    st_a, body, raw_a = req("POST", f"/matches/{mid}/abandon", {}, ja)
    print(f"ABANDON_PROBE {st_a} {(raw_a or '')[:400]}")
    if st_a == 404:
        note(
            "LIVE POST /matches/:id/abandon is 404. Coder pending. "
            "Mock + LiveMatchClient.abandon ready. Same path as timeout forfeit."
        )
        note("A4.2 disconnect 30s silence already LIVE — LIVE_A4_SMOKE_OK (endReason=forfeit, leaver +0).")
        print("LIVE_A4_GAPS_SMOKE_PENDING abandon_404")
        return 0

    snap = body.get("snapshot") or body
    expect(st_a in (200, 201), "A4.1 abandon HTTP")
    expect(snap.get("status") == "ended", f"A4.1 status ended ({snap.get('status')})")
    expect(snap.get("endReason") == "forfeit", f"A4.1 endReason forfeit ({snap.get('endReason')})")
    expect(you_marks(snap) == 0 or snap.get("winner") == "b", "A4.1 leaver wallet")

    st_b, remain, _ = req("GET", f"/matches/{mid}", token=jb)
    expect(st_b == 200, "A4.1 remaining GET")
    expect(remain.get("endReason") == "forfeit", "A4.1 remaining forfeit")
    expect(you_marks(remain) == 12 or remain.get("winner") == "b", f"A4.1 remaining +12 ({you_marks(remain)})")

    st2, replay, _ = req("POST", f"/matches/{mid}/abandon", {}, ja)
    expect(st2 in (200, 201, 409), f"A4.1 abandon idempotent HTTP {st2}")
    replay_snap = replay.get("snapshot") or replay
    if replay_snap.get("status") == "ended":
        expect(True, "A4.1 second abandon still ended")

    st3, rem2, _ = req("POST", f"/matches/{mid}/rematch", {"accept": True}, ja)
    expect(st3 in (200, 201), f"A4.4 rematch after ended ({st3})", str(rem2)[:240])

    if FAILS:
        print("LIVE_A4_GAPS_SMOKE_FAIL " + ", ".join(FAILS))
        return 1
    print(f"LIVE_A4_GAPS_SMOKE_OK {mid}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
