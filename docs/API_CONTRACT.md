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
1. `POST /matches` → `{ matchId, joinToken, seat: "a" }` (never both seat tokens)
2. `POST /matches/:id/join` `{ token }` sits that token; `{}` + Bearer claims empty seat B (`joinToken` for B). Both seated → `ready`
3. Drop: both `select_hex` while `ready`; re-drop OK until `start`
4. `{ type: "start" }` once both placed → `active`, `whoseTurn: "a"`, `turnIndex: 0`, `exposurePct: 50`
5. Turns: exactly one of `attack` | `recon` | `uav` | `decoy` | `smoke`, then required `end_turn`
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
  you: { seat, hex, placed, marks, exposurePct, movedLastTurn, decoyAvailable, decoyRemaining: 0|1, decoyHex?, highGroundActive, smokeAvailable?, smokeActive?, operativeLevel? },
  enemy: { seat, visibleHex, softHotTurnsLeft, decoySoftHex?, smokeActive? },
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
{ type: "smoke" }            // no hex; once/match. Omit fields → client fail-closed
{ type: "end_turn", exposurePct: number, hex?: {q,r} }

→ { ok, snapshot, result: ActionResult }
```

```
ActionResult =
  | { type: "select_hex", terrain: open|brush|hard }
  | { type: "start" }
  | { type: "attack", hit: boolean, kill: boolean, decoyCleared?: boolean, highGroundApplied?: boolean, coverApplied?: boolean, hitChance?: number }
  | { type: "recon", spotted: boolean, hex?: {q,r} }
  | { type: "uav", revealed: boolean, hex?: {q,r} }
  | { type: "decoy", hex?: {q,r}, planted?: boolean }
  | { type: "smoke", active?: boolean }
  | { type: "end_turn" }
  | { type: "reject", reason: string }
```

## HIGH GROUND (attacker HARD)
- Snapshot `you.highGroundActive: boolean` — true iff **your revealed cell** is `hard`. `open` / `brush` / unknown-to-self (FoW) → `false`.
- Attack intent stays `{ type: "attack", hex }`. Client never sends a bonus.
- Base hit chance when the target occupies the hex: **0.90** (LIVE `BASE_HIT`). Empty hex: **0**.
- Attacker on HARD → **+0.10 absolute**, one stack, clamp `[0, 1]` → occupy `hitChance` **1.0**. Defender terrain ignored.
- Attack result: `highGroundApplied` + final `hitChance`. Applied only on an occupy roll (empty miss stays 0).
- Guns / Decoy / Marks are blind. Client chrome binds the snapshot flag only — never invents from a local hex.

## BRUSH cover (target BRUSH)
- Correct-hex chance: `clamp(0.90 + HARD?0.10 − BRUSH?0.10, 0, 1)`.
- Target on BRUSH → **−0.10 absolute**, one stack, clamp `[0, 1]`. OPEN / HARD / unknown-to-self (FoW) → **−0**.
- Stacks with HIGH GROUND: HARD→BRUSH **0.90** · OPEN→BRUSH **0.80** · HARD→OPEN/HARD **1.0** · OPEN→OPEN/HARD **0.90**.
- Wrong hex / decoy: miss, `hitChance` **0**, `coverApplied` false.
- Attack result: `coverApplied` + existing `highGroundApplied` / `hitChance`. Applied only on an occupy roll.
- Intent stays `{ type: "attack", hex }`. No IN COVER chip this slice. Guns / Marks / Decoy stay blind.
- Client displays server fields only — never subtracts cover from a local hex.

## DECOY (once/match, operative L3)
LIVE doll tip `662dba7`. Exact `you.operativeLevel` and exact `you.decoyAvailable`. `decoyAvailable` is true only when `operativeLevel >= 3` and the once/match charge remains. Below L3 both `you.decoyAvailable` and `you.decoyRemaining` read false/0 (the charge stays unspent) and `{ type: "decoy" }` rejects `reach operative L3`. Locked ability chrome shows the tip `DECOY · L3` and a tap toasts `Reach operative L3`. No Marks, no IAP. Practice XP stays Δ0. Once unlocked, placement, miss+clear, and expiry are unchanged.
- **L3:** the chip lights only when exact `you.operativeLevel >= 3` and exact `you.decoyAvailable` is true. Below 3 the chip stays visible on the spent-wood plate with the tip `DECOY · L3`.
- **Fail closed:** a missing `operativeLevel` does not light a charge. A missing `decoyAvailable` at L3+ does not invent one. `decoyRemaining` and snake-case aliases do not unlock.

## SMOKE (once/match, exposure + spot only)
LIVE puff tip `fa7285ba`. L5 contract (Coder): exact `you.operativeLevel` and exact `you.smokeAvailable`. `smokeAvailable` is true only when `operativeLevel >= 5` and the once/match charge remains. Deployed `https://glassline-api.vercel.app` already returns those keys on `you` (level 1 → `smokeAvailable` false). No git tip SHA was readable from this client. Intent `{ type: "smoke" }` on the existing `POST /matches/:id/actions` path. No hex (an extra hex is ignored). No Marks / IAP. Practice earn stays Δ0. Success result is exactly `{ type: "smoke" }`.
- Snapshot `you.smokeAvailable` (bool) and `you.smokeActive` (bool or turns remaining). `enemy.smokeActive` too. The puff clock still accepts `smoke_active` casing. The L5 gate does not.
- **L5:** the chip lights only when exact `you.operativeLevel >= 5` and exact `you.smokeAvailable` is true. Below 5 the chip stays visible on the spent-wood plate and a tap toasts `Reach operative L5`. Practice XP does not level. The SMOKE chip does not read `xp`.
- **Fail closed:** a missing `operativeLevel` does not light a charge. A missing `smokeAvailable` at L5+ does not invent one. Snake-case aliases do not unlock. If `you.smokeActive` is absent, there is no active toast and no hex tint. If `enemy.smokeActive` is absent, the rival hex is not washed. Smoke never writes `enemy.visibleHex`.
- **Decoy clock:** cast → available false, active true, phase `await_end_turn`. The planting `end_turn` keeps it. The enemy's full turn keeps it. The caster's next action window still has it. The caster's next own `end_turn` clears `smokeActive`. `smokeAvailable` stays false. Rejects: `match is not active`, `not your turn`, `awaiting end_turn`, `smoke already used`.
- Cover-only HARD for spot (−20, no stack with a real HARD cell) and exposure. Spot math stays server-owned (`spotChance` 35 open → 15 smoked or HARD).
- **No** Attack +0.10 and no `highGroundApplied` from smoke. `you.highGroundActive` is unchanged. No IN COVER chip. UAV, Decoy, Marks, and `you.exposureFloor` stay on their own fields.

## Hideout operative plate
Soft P2 tip `7fbd884`. Hideout refresh binds **primary** to `GET /shop/me` `you.xp`, `you.operativeLevel`, and `you.exposureFloor`. Progress on the wood chip is `xp % 100` of 100 (remaining `100 - (xp % 100)`). There is no `xpToNext` field. Below L5 the chip adds a muted tip `SMOKE · L5`. L5+ drops it. A missing `xp` or `operativeLevel` hides the plate — the client does not invent either, and does not derive a level from xp. A missing `exposureFloor` keeps the last server percent (start 50 until one arrives) and is never mapped from the level. `POST /players` and match / ended `you` are the fallback only when the shop field is absent. `you.smokeAvailable` stays match-scoped and is not copied onto the shop plate. Practice does not add XP.

## Match-end XP line
Client chrome only. No new field, no `xpGranted`. The end plate paints `+N XP  ·  L#` under the Marks Δ when ended `you.xp` and `you.operativeLevel` are both present. Practice omits the line. A missing field omits it. There is no XP bar on the plate.

`N` is exact `xpDelta` when that key is already on `payout`, `result`, `lastAction`, the snapshot, or `you` (same bags as `marksDelta`). Otherwise `N` is the live grant for the same outcome Marks already paints: PvP kill win **+100**, forfeit win **+50**, everything else **0** (loss, standoff, leaver, SP job). That is not `ended.xp` minus a cached wallet. `unlocked` is only when that grant crosses a 100-XP boundary and `you.operativeLevel` is the new level. Marks Δ is unchanged.

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

- Marks: remaining **+15** / leaver **+0** (display + mock table). Snapshot `you.marks` is the settled wallet.
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

## Quick Match (LIVE 2026-09-20, Coder `queue.ts`)
`POST /queue` Bearer **player** → **200** `{ status: queued, queuedAt, timeoutSec: 60, expiresAt }`
or **200** `{ status: matched, matchId, joinToken, seat, snapshot }` (match snap, `ready`).

`GET /queue` → `idle` | queued + `secondsLeft` | `matched` | **`expired`** (once, then idle).

`DELETE /queue` → **200** `{ status: idle }`. Waiting rows only. **Marks Δ0**.

TTL **60s**. Re-POST while queued **refreshes `expiresAt`** (keeps `queuedAt`). **No bot fill.** Pair two humans → existing drop / rematch / A4.

Errors: **401** · **409** `already_in_match` / `in_lobby`. Bare 404 → `queue_unavailable`.

## Match journal (client, 2026-09-21)
`GET /journal` Bearer **player** → `{ entries: [...] }` newest first, max **10**.

```
entry: { matchId, mode, result: win|loss|forfeit|draw,
         rival: { displayName, isBot }, marksDelta, endedAt, rematchAvailable }
```

Practice rows: `marksDelta` **0**, chip `0` / `+N` / `−N`. PvP `rematchAvailable` → existing `POST /matches/:id/rematch`. Practice again is `POST /matches` `{ mode: "practice" }`, not a replay. LIVE `GET /journal` is up (`0d30bd7`); practice create echoes `mode: "practice"`. 404 still falls back to the mock ledger. No local history.

## Other REST
- `GET /health` → `{ ok: true }`
- `GET /journal` → last 10 ended matches for the Bearer player
- `GET /matches/:id` → caller-scoped snapshot (reconnect)
- `POST /matches/:id/abandon` → join Bearer, no body
- `POST /matches/:id/rematch` → `{ accept }` + join-token Bearer (player token fallback)
- `POST /lobbies` · `POST /lobbies/join` · `GET /lobbies/:id` · `POST /lobbies/:id/cancel`
- `POST /queue` · `GET /queue` · `DELETE /queue`
