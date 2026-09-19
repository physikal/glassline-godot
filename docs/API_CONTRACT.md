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
  you: { seat, hex, placed, marks, exposurePct, movedLastTurn, decoyAvailable, decoyHex? },
  enemy: { seat, visibleHex, softHotTurnsLeft, decoySoftHex? },
  terrain: [{ q, r, type }],
  lastAction: ActionResult | null,
  winner: a|b|draw|null
}
```

## Actions `POST /matches/:id/actions`
```
{ type: "select_hex", hex: {q,r} }
{ type: "start" }
{ type: "attack", hex: {q,r} }
{ type: "recon", hex: {q,r} }   // sector = center + 6 neighbors
{ type: "uav" }
{ type: "decoy" }            // no hex; server picks adjacent empty. LIVE Zod pending Coder.
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

## Other REST
- `GET /health` → `{ ok: true }`
- `GET /matches/:id` → caller-scoped snapshot (reconnect)
