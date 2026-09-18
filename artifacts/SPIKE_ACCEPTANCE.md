# Spike acceptance

Public LIVE: **`https://glassline-api.vercel.app`**. No mil-sim. No Marks client grant.

## GD Design A2 bar — LOCKED

**Reconnect → server snapshot is sole truth** (`you.hex`, turn / `whoseTurn` / `turnIndex` / `phase`, `you.exposurePct`, `you.marks`).

Client **never invents** terrain tags, `lastAction.hit`, or wallet. `GET /matches/:id` then `ClientSession.apply_snapshot` **replaces** `last_snapshot` (no merge). Hover / optic / Marks chip / end-turn doll read the snapshot only.

| Field | Sole truth |
| --- | --- |
| Hex | `you.hex` on the caller snapshot |
| Turn | `whoseTurn`, `turnIndex`, `phase`, `status` |
| Exposure | `you.exposurePct` — end-turn doll binds this **server pct** |
| Marks | `you.marks` display bind only. Never `marks +=` |

**Exposure doll:** soft gap OK (art stub). Live path must still show the end-turn doll driven by **server `you.exposurePct`**. Slider is the next `end_turn` intent only — not truth. Art polish remains owner Godot. **Do not redo doll art this pass.**

## A2 notes — P2 UX (2026-09-18)

Soft P2 from UX: strip player-facing **`SERVER SNAPSHOT`** (and similar) debug badge from release / match UI.

Reconnect is unchanged: `GET /matches/:id` → `ClientSession.apply_snapshot` **replace** (no merge). Hex / turn / `you.exposurePct` / `you.marks` stay server sole truth. The badge was chrome only — it is not shown.

Doll stays the art stub. Binding remains `you.exposurePct` from the server. No mil-sim. No Marks client grant.

## Checklist

| Gate | Status | Evidence |
| --- | --- | --- |
| **A1** lobby | **CLEAR** | [`a1-lobby.png`](a1-lobby.png) · [`a1-after-play.png`](a1-after-play.png) · canon-pass [`ux/a1-lobby-canon-pass.png`](ux/a1-lobby-canon-pass.png) · [`A1_A3_NOTES.md`](A1_A3_NOTES.md) |
| **A2** reconnect | **PASS LIVE** (locked bar) | `LIVE_A2_SMOKE_OK m_668f470053894080abe921f8077d33d7` (hex/turn/exposure/Marks replace) · prior `m_fd248542cc05483888ea23335fb627a6` · Mock `HEADLESS_LOOP_OK` `_a2_reconnect_case` · still [`ux/a2_reconnect_server_snapshot.png`](ux/a2_reconnect_server_snapshot.png) (no `SERVER SNAPSHOT` badge) |
| **A3** attack miss / kill | **PASS** prior LIVE + mock stills | [`LIVE_SMOKE.md`](LIVE_SMOKE.md) `LIVE_HTTP_SMOKE_OK m_0e8ee5d22cd84be4b398c2d659a63e1d` · [`a3-attack-miss.png`](a3-attack-miss.png) · [`a3-attack-kill.png`](a3-attack-kill.png) |
| **A4** soft forfeit | **PASS** prior LIVE | [`LIVE_MARKS_SMOKE.md`](LIVE_MARKS_SMOKE.md) `LIVE_A4_SMOKE_OK j_26e30905934c4e52bbde019a39f0664c endReason=forfeit marks 0->0` |
| **A5** SP job | **PASS** prior LIVE | [`LIVE_MARKS_SMOKE.md`](LIVE_MARKS_SMOKE.md) `LIVE_JOBS_SMOKE_OK j_b168c483a11a427a96031e38124a9f97 marks 0->10` · [`MARKS_SP_NOTES.md`](MARKS_SP_NOTES.md) |
| **A6** Marks display-only / server ledger | **PASS** prior | [`MARKS_SP_NOTES.md`](MARKS_SP_NOTES.md) · [`LIVE_MARKS_SMOKE.md`](LIVE_MARKS_SMOKE.md) M1–M4. Client binds `you.marks` only. |

## A2 reconnect smoke

```bash
GLASSLINE_API_BASE=https://glassline-api.vercel.app python3 tools/live_a2_smoke.py
# LIVE_A2_SMOKE_OK m_668f470053894080abe921f8077d33d7
godot --headless --path . -s res://tools/headless_loop_test.gd
# HEADLESS_LOOP_OK  (_a2_reconnect_case)
```

What the smoke proves:

1. Create + join both seats on LIVE.
2. `select_hex` (2,2) / (7,5) — server reveals terrain; note caller snapshot (hex, turn, exposure, Marks).
3. `attack` (0,0) miss — `result.hit == false`, **no** terrain row for (0,0), no invented Hot.
4. Pollute a local cache: fake terrain `(8,6)=hard`, `hit=true`, `exposurePct=99`, `marks=999`, fake hex / turn.
5. Re-GET `/matches/:id` and **replace** the cache (`MatchAPI.reconnect()`).
6. Assert client bag **equals** the GET body: `you.hex`, `whoseTurn` / `turnIndex` / `phase`, `you.exposurePct`, `you.marks`, terrain keys, `lastAction.hit`. Invented terrain / hit / wallet / exposure are gone.

Godot: match `_ready` → `MatchAPI.reconnect()`. Doll → `snap.you_exposure()`. Marks chip → `snap.you_marks()`. Printed table paint is not reconnect truth.

Reconnect still (`--capture-a2`): [`ux/a2_reconnect_server_snapshot.png`](ux/a2_reconnect_server_snapshot.png) — end-turn doll at **server `you.exposurePct`**. No `SERVER SNAPSHOT` (or similar) debug badge.

## GD ping — A2 ready

Copy for GD:

> A2 **locked**. Reconnect = server snapshot sole truth (**hex, turn, exposure, Marks**). Client never invents terrain / hit / wallet.
>
> LIVE: `python3 tools/live_a2_smoke.py` → `LIVE_A2_SMOKE_OK m_668f470053894080abe921f8077d33d7`  
> Mock: `godot --headless --path . -s res://tools/headless_loop_test.gd` → `HEADLESS_LOOP_OK`  
> Doll: soft gap / art stub. Live end-turn doll binds **`you.exposurePct`** (server). Slider is next `end_turn` intent only. Art polish owner Godot — not this pass.
>
> Match UI: no player-facing `SERVER SNAPSHOT` badge. Reconnect still applies the server snapshot as sole truth.
>
> Still: `artifacts/ux/a2_reconnect_server_snapshot.png`  
> Bar: `artifacts/SPIKE_ACCEPTANCE.md`  
> PR: https://github.com/physikal/glassline-godot/pull/7

## Commands

```bash
godot --headless --path . -s res://tools/headless_loop_test.gd
GLASSLINE_API_BASE=https://glassline-api.vercel.app python3 tools/live_a2_smoke.py
GLASSLINE_API_BASE=https://glassline-api.vercel.app python3 tools/live_http_smoke.py
GLASSLINE_API_BASE=https://glassline-api.vercel.app python3 tools/live_jobs_smoke.py
GLASSLINE_API_BASE=https://glassline-api.vercel.app python3 tools/live_a4_smoke.py
```
