#!/usr/bin/env python3
"""HTTP LIVE smoke vs glassline-api on 127.0.0.1:8787.

Sequence: health → create → join a+b → select_hex → start (expect mismatch)
→ attack miss → end_turn → UAV/kill path → SSE Bearer.

Does not touch or push the API repo.
"""

from __future__ import annotations

import json
import sys
import urllib.error
import urllib.request

BASE = "http://127.0.0.1:8787"
FAILS: list[str] = []
NOTES: list[str] = []


def req(method: str, path: str, body=None, token: str | None = None, timeout: float = 8.0):
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


def main() -> int:
    status, health, _ = req("GET", "/health")
    expect(status == 200 and health.get("ok") is True, "GET /health", str(health))

    status, created, _ = req("POST", "/matches", {})
    expect(status in (200, 201) and "matchId" in created, "POST /matches", f"{status} {created}")
    if status == 201:
        note("POST /matches returns HTTP 201 (client also accepts 200 JSON).")
    match_id = created.get("matchId", "")
    tokens = created.get("joinTokens") or {}
    token_a = tokens.get("a", "")
    token_b = tokens.get("b", "")
    expect(bool(token_a and token_b), "joinTokens.a/b present")

    status, join_a, _ = req("POST", f"/matches/{match_id}/join", {"token": token_a})
    status_b, join_b, _ = req("POST", f"/matches/{match_id}/join", {"token": token_b})
    expect(status == 200 and join_a.get("seat") == "a", "join seat a", str(join_a.get("error", join_a.get("seat"))))
    expect(status_b == 200 and join_b.get("seat") == "b", "join seat b")
    snap_b = join_b.get("snapshot") or {}
    expect(snap_b.get("status") == "ready", "both joined → ready", str(snap_b.get("status")))
    you = (join_a.get("snapshot") or {}).get("you") or {}
    if "placed" not in you:
        note("snapshot.you has no `placed` (infer from you.hex).")
    if "uavAvailable" in (join_a.get("snapshot") or {}):
        note("snapshot includes uavAvailable (client also reads uavRemaining).")

    status, sel_a, _ = req(
        "POST",
        f"/matches/{match_id}/actions",
        {"type": "select_hex", "hex": {"q": 2, "r": 2}},
        token_a,
    )
    expect(status == 200 and sel_a.get("ok") is True, "select_hex a", str(sel_a.get("result") or sel_a.get("error")))
    status, sel_b, _ = req(
        "POST",
        f"/matches/{match_id}/actions",
        {"type": "select_hex", "hex": {"q": 7, "r": 5}},
        token_b,
    )
    expect(status == 200 and sel_b.get("ok") is True, "select_hex b")
    snap = sel_b.get("snapshot") or {}
    expect(snap.get("status") == "active", "both placed auto-active (no start)", str(snap.get("status")))
    expect(snap.get("whoseTurn") == "a", "whoseTurn a after drop")
    expect(snap.get("phase") == "await_action", "phase await_action")

    status, start, raw = req("POST", f"/matches/{match_id}/actions", {"type": "start"}, token_a)
    expect(status == 400, "start is rejected (locked: no start action)", f"{status} {start}")
    if status == 400:
        note("POST start → 400 invalid action body. Client LiveMatchClient no-ops start when already active.")

    status, miss, _ = req(
        "POST",
        f"/matches/{match_id}/actions",
        {"type": "attack", "hex": {"q": 0, "r": 0}},
        token_a,
    )
    result = miss.get("result") or {}
    snap = miss.get("snapshot") or {}
    expect(status == 200 and miss.get("ok") is True, "attack miss ok")
    expect(result.get("hit") is False and result.get("kill") is False, "miss hit=false kill=false", str(result))
    expect(snap.get("phase") == "await_end_turn", "miss → await_end_turn")
    expect((snap.get("enemy") or {}).get("visibleHex") is None, "miss does not invent Hot")
    terrain_keys = {f"{t.get('q')},{t.get('r')}" for t in (snap.get("terrain") or [])}
    if "0,0" not in terrain_keys:
        note("attack miss does not reveal target terrain (mock did).")
    else:
        FAILS.append("attack miss unexpectedly revealed terrain")

    status, hex_end, _ = req(
        "POST",
        f"/matches/{match_id}/actions",
        {"type": "end_turn", "exposurePct": 50, "hex": {"q": 2, "r": 3}},
        token_a,
    )
    end_a = hex_end
    if status == 400:
        note("end_turn.hex is rejected; live field is end_turn.move.")
        status, end_a, _ = req(
            "POST",
            f"/matches/{match_id}/actions",
            {"type": "end_turn", "exposurePct": 50},
            token_a,
        )
    elif status == 200 and hex_end.get("ok") is True:
        note("end_turn.hex was stripped by Zod (camp, no move). Live field is `move`.")
    else:
        expect(False, "end_turn after miss", f"{status} {hex_end}")
    expect(status == 200 and end_a.get("ok") is True, "end_turn a after miss")
    expect((end_a.get("snapshot") or {}).get("whoseTurn") == "b", "turn passed to b")
    end_res = end_a.get("result") or {}
    if "moved" in end_res:
        note("end_turn result includes moved:bool (client toast already prints it).")

    status, recon_b, _ = req(
        "POST",
        f"/matches/{match_id}/actions",
        {"type": "recon", "hex": {"q": 4, "r": 3}},
        token_b,
    )
    expect(status == 200 and recon_b.get("ok") is True, "b recon")
    recon_res = recon_b.get("result") or {}
    if "softMarks" in recon_res:
        note(f"recon result.softMarks={recon_res.get('softMarks')} (extra vs older client union).")

    status, end_b, _ = req(
        "POST",
        f"/matches/{match_id}/actions",
        {"type": "end_turn", "exposurePct": 40, "move": {"q": 6, "r": 5}},
        token_b,
    )
    expect(status == 200 and end_b.get("ok") is True, "b end_turn with move")

    status, uav, _ = req("POST", f"/matches/{match_id}/actions", {"type": "uav"}, token_a)
    expect(status == 200 and uav.get("ok") is True, "uav")
    uav_res = uav.get("result") or {}
    expect(uav_res.get("revealed") is True, "uav revealed=true", str(uav_res))
    vis = ((uav.get("snapshot") or {}).get("enemy") or {}).get("visibleHex")
    expect(isinstance(vis, dict), "uav sets enemy.visibleHex", str(vis))

    status, end_a2, _ = req(
        "POST",
        f"/matches/{match_id}/actions",
        {"type": "end_turn", "exposurePct": 50},
        token_a,
    )
    expect(status == 200 and end_a2.get("ok") is True, "a end_turn after uav")
    status, recon_b2, _ = req(
        "POST",
        f"/matches/{match_id}/actions",
        {"type": "recon", "hex": {"q": 1, "r": 1}},
        token_b,
    )
    expect(status == 200 and recon_b2.get("ok") is True, "b filler recon")
    status, end_b2, _ = req(
        "POST",
        f"/matches/{match_id}/actions",
        {"type": "end_turn", "exposurePct": 50},
        token_b,
    )
    expect(status == 200 and end_b2.get("ok") is True, "b filler end_turn")

    if not isinstance(vis, dict):
        vis = {"q": 6, "r": 5}
    status, kill, _ = req(
        "POST",
        f"/matches/{match_id}/actions",
        {"type": "attack", "hex": vis},
        token_a,
    )
    kill_res = kill.get("result") or {}
    kill_snap = kill.get("snapshot") or {}
    expect(status == 200 and kill.get("ok") is True, "attack kill ok")
    expect(kill_res.get("hit") is True and kill_res.get("kill") is True, "kill hit+kill", str(kill_res))
    expect(kill_snap.get("status") == "ended", "status ended")
    expect(kill_snap.get("winner") == "a", "winner a")
    expect(((kill_snap.get("you") or {}).get("marks") == 1), "marks +1")

    # SSE with Bearer join token — read the first event then hang up.
    sse_ok = False
    sse_event = ""
    try:
        request = urllib.request.Request(
            f"{BASE}/matches/{match_id}/events",
            headers={
                "Accept": "text/event-stream",
                "Authorization": f"Bearer {token_a}",
                "Cache-Control": "no-cache",
            },
            method="GET",
        )
        with urllib.request.urlopen(request, timeout=4.0) as resp:
            expect(resp.status == 200, "SSE GET /matches/:id/events 200")
            expect("text/event-stream" in (resp.headers.get("Content-Type") or ""), "SSE content-type")
            try:
                resp.fp.raw._sock.settimeout(1.5)
            except Exception:
                pass
            buf = b""
            while len(buf) < 8192:
                try:
                    chunk = resp.fp.read1(1024) if hasattr(resp.fp, "read1") else resp.read(64)
                except TimeoutError:
                    break
                except Exception:
                    break
                if not chunk:
                    break
                buf += chunk
                if b"\n\n" in buf or b"data:" in buf:
                    break
            text = buf.decode("utf-8", errors="replace")
            for line in text.splitlines():
                if line.startswith("event:"):
                    sse_event = line.split(":", 1)[1].strip()
                if line.startswith("data:"):
                    payload = json.loads(line.split(":", 1)[1].strip() or "{}")
                    snap = payload.get("snapshot") or payload
                    sse_ok = isinstance(snap, dict) and snap.get("matchId") == match_id
                    break
    except Exception as exc:  # noqa: BLE001
        expect(False, "SSE stream", str(exc))
    expect(sse_ok, "SSE payload has snapshot.matchId", sse_event)

    print()
    print("NOTES")
    for line in NOTES:
        print(f"  - {line}")
    print()
    if FAILS:
        print("LIVE_HTTP_SMOKE_FAIL", len(FAILS))
        for line in FAILS:
            print(f"  - {line}")
        return 1
    print("LIVE_HTTP_SMOKE_OK", match_id)
    return 0


if __name__ == "__main__":
    sys.exit(main())
