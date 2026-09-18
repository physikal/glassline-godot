# LIVE smoke vs glassline-api (8787)

**Result: PASS** (HTTP + Godot `LiveMatchClient`)

A1/A3 mock stills were already on `main`. This pass used a local copy of [physikal/glassline-api](https://github.com/physikal/glassline-api) — **not pushed**.

Anonymous `git clone` 404s (private repo). Working tree was materialized under `/tmp/glassline-api` from GitHub MCP file contents. Local Postgres 16:

```
DATABASE_URL=postgresql://glassline:glassline@127.0.0.1:5432/glassline
pnpm install && pnpm migrate && pnpm start
```

`GET http://127.0.0.1:8787/health` → `{"ok":true}`

Client flipped with `GLASSLINE_USE_LIVE_API=1` and `GLASSLINE_API_BASE=http://127.0.0.1:8787`. Mock remains the editor default.

## Sequence

| Step | Result | Notes |
| --- | --- | --- |
| `GET /health` | PASS | `{ ok: true }` |
| `POST /matches` | PASS | HTTP **201** `{ matchId, joinTokens: { a, b } }` |
| `POST /matches/:id/join` a then b | PASS | both seated → `ready` |
| `select_hex` a (2,2) + b (7,5) | PASS | second drop **auto-`active`**, `whoseTurn: a`, `phase: await_action` |
| `{ type: "start" }` | **400** (expected mismatch) | Zod: `invalid action body`. Client no-ops start when already `active`. |
| `attack` (0,0) miss | PASS | `hit: false`, `kill: false`, no Hot, **no terrain row** |
| `end_turn` | PASS | `{ exposurePct: 50 }` → turn to `b`. Extra `hex` is stripped (live field is `move`). |
| `recon` b + `end_turn.move` | PASS | result includes `softMarks` |
| `uav` a | PASS | `revealed: true`, `enemy.visibleHex` set |
| end_turn / filler / `attack` visible hex | PASS | `hit+kill`, `status: ended`, `winner: a`, **Marks +1** |
| `GET /matches/:id/events` Bearer | PASS | `text/event-stream`, first event has `snapshot.matchId` |

Godot: `LIVE_LOOP_OK m_5633bc587ce840518f9cb5ac09a8950f`  
HTTP: `LIVE_HTTP_SMOKE_OK m_4150a654877b42dabe0f9b07f68740fa`  
Mock regression: `HEADLESS_LOOP_OK`

## Contract mismatches (live vs older client draft)

| Client / mock draft | Live API (locked) |
| --- | --- |
| `{ type: "start" }` after both drops | **No `start`.** Second `select_hex` → `active`. POST start = HTTP 400. |
| `end_turn.hex` | `end_turn.move`. Bare `hex` is stripped; camp still succeeds. |
| `you.placed` | Omitted. Infer from `you.hex != null`. |
| Attack miss reveals target terrain | Attack/recon **never** insert terrain. Terrain only on `select_hex` / `end_turn.move`. |
| `POST /matches` 200 | **201** |
| Recon result `{ spotted, hex? }` | Also `softMarks: number` |
| `end_turn` result `{ type }` | Also `moved: boolean` |
| Snapshot | Extra `uavAvailable`, `softMarks` (client already reads `uavRemaining`) |
| Realtime | WS preferred (`GET /matches/:id/ws`); SSE fallback is the path Godot uses |

Client adaptations (this repo only): `end_turn` sends both `hex` and `move`; `you_placed()` falls back to `you.hex`; `LiveMatchClient` treats `start` as a reconnect no-op when `status == active`; dummy drop refetches the caller snapshot after live auto-activate.

API repo was not renamed, rewritten, or pushed.
