# Spike acceptance

Public LIVE: **`https://glassline-api.vercel.app`**. Client never invents terrain tags or “I hit.” Marks are display-only (`you.marks`). No mil-sim.

## Checklist

| Gate | Status | Evidence |
| --- | --- | --- |
| **A1** lobby | **CLEAR** | [`a1-lobby.png`](a1-lobby.png) · [`a1-after-play.png`](a1-after-play.png) · canon-pass [`ux/a1-lobby-canon-pass.png`](ux/a1-lobby-canon-pass.png) · [`A1_A3_NOTES.md`](A1_A3_NOTES.md) |
| **A2** reconnect | **PASS LIVE** (this smoke) | `LIVE_A2_SMOKE_OK m_fd248542cc05483888ea23335fb627a6` · Mock `HEADLESS_LOOP_OK` `_a2_reconnect_case` · still [`ux/a2_reconnect_server_snapshot.png`](ux/a2_reconnect_server_snapshot.png) (`SERVER SNAPSHOT` + 50% doll) |
| **A3** attack miss / kill | **PASS** prior LIVE + mock stills | [`LIVE_SMOKE.md`](LIVE_SMOKE.md) `LIVE_HTTP_SMOKE_OK m_0e8ee5d22cd84be4b398c2d659a63e1d` · [`a3-attack-miss.png`](a3-attack-miss.png) · [`a3-attack-kill.png`](a3-attack-kill.png) |
| **A4** soft forfeit | **PASS** prior LIVE | [`LIVE_MARKS_SMOKE.md`](LIVE_MARKS_SMOKE.md) `LIVE_A4_SMOKE_OK j_26e30905934c4e52bbde019a39f0664c endReason=forfeit marks 0->0` |
| **A5** SP job | **PASS** prior LIVE | [`LIVE_MARKS_SMOKE.md`](LIVE_MARKS_SMOKE.md) `LIVE_JOBS_SMOKE_OK j_b168c483a11a427a96031e38124a9f97 marks 0->10` · [`MARKS_SP_NOTES.md`](MARKS_SP_NOTES.md) |
| **A6** Marks display-only / server ledger | **PASS** prior | [`MARKS_SP_NOTES.md`](MARKS_SP_NOTES.md) · [`LIVE_MARKS_SMOKE.md`](LIVE_MARKS_SMOKE.md) M1–M4. Client binds `you.marks` only. No `marks +=`. |

## A2 reconnect (this pass)

**Rule:** `GET /matches/:id` is the reconnect snapshot. `ClientSession.apply_snapshot` **replaces** `last_snapshot` (no merge). The client does not invent terrain rows or `lastAction.hit`.

```bash
GLASSLINE_API_BASE=https://glassline-api.vercel.app python3 tools/live_a2_smoke.py
# LIVE_A2_SMOKE_OK m_fd248542cc05483888ea23335fb627a6
```

Noted after both drops (caller A): `status=active`, `whoseTurn=a`, `phase=await_action`, terrain `2,2` + `7,5` (server tags; select_hex a was `hard`), `lastHit=null`, `you.exposurePct=50`. After miss + reconnect GET: same match fields from the server, `lastHit=false`, invented `(8,6)` / `hit=true` gone.

What the smoke proves:

1. Create + join both seats on LIVE.
2. `select_hex` (2,2) / (7,5) — server reveals terrain; note caller snapshot.
3. `attack` (0,0) miss — `result.hit == false`, **no** terrain row for (0,0), no invented Hot.
4. Pollute a local cache with fake terrain `(8,6)=hard` and `lastAction.hit=true`.
5. Re-GET `/matches/:id` and replace the cache (same as `MatchAPI.reconnect()`).
6. Assert client state **equals** the GET body: `matchId`, `status`, `phase`, `whoseTurn`, `turnIndex`, `you.hex`, `terrain` keys, `lastAction.hit`. Invented `(8,6)` and invented hit are gone. Select terrain `(2,2)` stays because the **server** still has it.

Godot path: match screen `_ready` calls `MatchAPI.reconnect()` (GET + replace). Hover / optic read `snapshot.terrain` only — printed table paint is not reconnect truth. Toast last-action hit is `lastAction.hit` from the snapshot.

Mock unit: `godot --headless --path . -s res://tools/headless_loop_test.gd` → `_a2_reconnect_case` (`HEADLESS_LOOP_OK`).

Reconnect UI still (`--capture-a2`): [`ux/a2_reconnect_server_snapshot.png`](ux/a2_reconnect_server_snapshot.png) — `SERVER SNAPSHOT` chip after replace, end-turn **50%** doll stub.

## Remaining — end-turn exposure doll (50%)

**Stub shipped** on the end-turn panel (`scenes/match/exposure_doll.gd`): toy silhouette + cover clip, default **50%**, tied to the exposure slider. Not mil-sim. Not a Marks grant.

**Remaining (owner Godot):** art pass / plate doll, cover materials, any optic-side 50% figure beyond this stub.

## Commands

```bash
godot --headless --path . -s res://tools/headless_loop_test.gd
GLASSLINE_API_BASE=https://glassline-api.vercel.app python3 tools/live_a2_smoke.py
GLASSLINE_API_BASE=https://glassline-api.vercel.app python3 tools/live_http_smoke.py
GLASSLINE_API_BASE=https://glassline-api.vercel.app python3 tools/live_jobs_smoke.py
GLASSLINE_API_BASE=https://glassline-api.vercel.app python3 tools/live_a4_smoke.py
```
