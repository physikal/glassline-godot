# Glassline API contract LOCKED v0 (2026-09-18)

Source: Notion “Glassline API contract draft v0” (Godot stamp). Client types and both backends follow this shape.

**Live API (physikal/glassline-api) deltas vs this mock-era draft:** no `start` (second `select_hex` auto-`active`); `end_turn.move` not `hex`; attack miss does not write terrain; snapshot omits `you.placed` (infer from `you.hex`) and adds `uavAvailable` / `softMarks`. Client LIVE path adapts; mock still uses `start` + `hex`. Public base: `https://glassline-api.vercel.app`. SSE `GET /matches/:id/events` with poll fallback on `GET /matches/:id`. See `artifacts/LIVE_SMOKE.md`.

**Stack:** Hono + Neon Postgres · HTTPS + **SSE** (WS later, same payload) · no UDP/NGO

## Principles
- Server owns secret positions, turn index, terrain, spot/UAV/kill.
- Client sends **intents only** — never `hit` / terrain as truth.
- Reconnect = caller-scoped snapshot. Client never invents terrain or “I hit.”
- Attack miss ≠ invent Hot.

## Board
- **9×7** axial `(q,r)` — `0≤q<9`, `0≤r<7`
- Terrain on first select: `open` | `brush` | `hard` via `hash(match_id,q,r,salt)`

## Lifecycle
1. `POST /matches` → `{ matchId, joinTokens: { a, b } }`
2. `POST /matches/:id/join` `{ token }` → `{ playerId, seat, snapshot }` — `waiting` until both seated → `ready`
3. Drop: both `select_hex` while `ready`; re-drop OK until `start`
4. `{ type: "start" }` once both placed → `active`, `whoseTurn: "a"`, `turnIndex: 0`, `exposurePct: 50`
5. Turns: exactly one of `attack` | `recon` | `uav` | `decoy`, then required `end_turn`
6. `turnCap` 16 total (8 each) → `winner: "draw"`
7. Kill → Marks +1 winner

## Auth
`Authorization: Bearer <token>` from join.

## Snapshot (caller-scoped)
```
{
  matchId, status: waiting|ready|active|ended,
  turnIndex, turnCap: 16, whoseTurn: a|b|null,
  phase: await_action|await_end_turn|null,
  uavRemaining: 0|1,
  you: { seat, hex, placed, marks, exposurePct, movedLastTurn, decoyAvailable, decoyRemaining: 0|1, decoyHex? },
  enemy: { seat, visibleHex, softHotTurnsLeft, decoySoftHex? },
  terrain: [{ q, r, type }],
  lastAction: ActionResult | null,
  winner: a|b|draw|null,
  rematch?: { status: none|waiting|ready|declined|expired, youAccepted?, opponentAccepted?, expiresAt?, newMatchId? }
}
```

## Actions `POST /matches/:id/actions`
```
{ type: "select_hex", hex: {q,r} }
{ type: "start" }
{ type: "attack", hex: {q,r} }
{ type: "recon", hex: {q,r} }   // sector = center + 6 neighbors
{ type: "uav" }
{ type: "decoy" }            // no hex; server picks adjacent empty (LIVE 200)
{ type: "end_turn", exposurePct: number, hex?: {q,r} }

→ { ok, snapshot, result: ActionResult }
```

```
ActionResult =
  | { type: "select_hex", terrain: open|brush|hard }
  | { type: "start" }
  | { type: "attack", hit: boolean, kill: boolean, decoyCleared?: boolean }
  | { type: "recon", spotted: boolean, hex?: {q,r} }
  | { type: "uav", revealed: boolean, hex?: {q,r} }
  | { type: "decoy", hex?: {q,r}, planted?: boolean }
  | { type: "end_turn" }
  | { type: "reject", reason: string }
```

## Realtime
`GET /matches/:id/events` SSE → `{ event: "snapshot"|"your_turn", snapshot }`

## Rematch (ended PvP only)
`POST /matches/:id/rematch` `{ accept: true|false }`

Bearer prefers the **seat join token**. Durable `POST /players` token of a seated `playerId` also works.

Ended snapshot field:

```
rematch: { status: "none"|"waiting"|"ready"|"declined"|"expired",
           youAccepted?: boolean, opponentAccepted?: boolean,
           expiresAt?: string, newMatchId?: string }
```

POST shapes (Coder PR #9 / LIVE):

```
{ status: "waiting", youAccepted, opponentAccepted, expiresAt }
{ status: "ready", matchId, joinToken, snapshot }   // switch client; replay for the other seat
{ status: "declined" } | { status: "expired" }
```

- Both accept → new `matchId` + terrain salt; same two `playerId`s / seats; status `ready` (drop again). Marks unchanged.
- One decline or **30s** from match end → hideout. No new match.
- Ready is **idempotent**: POST again to fetch that seat’s `joinToken`.
- 409 `match_not_ended` / `rematch_not_available` (SP jobs). 400 `invalid_rematch_body`.
- Client aliases `pending|accepted_a|accepted_b` → `waiting`. Mock matches LIVE. Curl LIVE first; prefer LIVE smoke once the route is 200.

## Abandon (active PvP / job)
`POST /matches/:id/abandon` — join Bearer, **no body**. Same forfeit path as 30s silence.

```
{ ok: true, snapshot }   // status ended, endReason forfeit, winner = remaining
```

- Marks: remaining **+12** / leaver **+0**. Snapshot `you.marks` is the settled wallet.
- `ready` / `waiting` → 409 `match_not_active`.
- Already `ended` → 409 `match_already_ended` (idempotent: no second grant). Client GET-replays.
- Rematch still ended-only (409 `match_not_ended` while `active`).

## Private lobby (LIVE 2026-09-20, glassline-api #11)
`POST /lobbies` Bearer **player** → **201** `{ lobbyId: lob_…, code, status: waiting, expiresAt, snapshot }`.

Code: **6** uppercase, alphabet `23456789ABCDEFGHJKLMNPQRSTUVWXYZ` (no `0O1I`). TTL **10 min**. No ranked.

`POST /lobbies/join` `{ code }` → seat B; both seated → **200** `{ status: ready, matchId, joinToken, seat: b, snapshot }` (match snap).

`GET /lobbies/:id` host poll. Ready keeps a **lobby** snap + top-level `matchId` / `joinToken`.

`POST /lobbies/:id/cancel` waiting → **200** `{ ok, status: cancelled }`. After handoff → **409** `lobby_already_started`. **No** forfeit Marks.

Errors: **400** `invalid_lobby_code` / `invalid_join_body` · **404** `lobby_not_found` · **409** `lobby_expired` / `lobby_full` / `already_in_lobby` / `lobby_cancelled` / `lobby_already_started` · **401** missing bearer · **403** `not_member`.

Bare `POST /lobbies` 404 (no `lobby_not_found`) → route missing; mock. Prefer LIVE smoke once 200/201.

## Other REST
- `GET /health` → `{ ok: true }`
- `GET /matches/:id` → caller-scoped snapshot (reconnect)
- `POST /matches/:id/abandon` → join Bearer, no body
- `POST /matches/:id/rematch` → `{ accept }` + join-token Bearer (player token fallback)
- `POST /lobbies` · `POST /lobbies/join` · `GET /lobbies/:id` · `POST /lobbies/:id/cancel`
