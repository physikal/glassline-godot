# Marks earn + SP job stub — client assumptions (Coder align)

Client half of [Slice ticket — Marks earn + SP job stub](https://www.notion.so/3df4dabdb33981b19fb7f3847132630e).  
Godot **displays only**. The mock may simulate a ledger for hideout/end chrome. LIVE remains source of truth.

Parked here: art desk framing, IAP/Chips, parts sinks.

## Hard rule

Never `marks +=` on the client as truth. `ClientSession.marks` is a display cache updated by `apply_snapshot` / `bind_marks` from a server (or mock) payload.

**Balance field (Coder):** `you.marks`  
**Ability chrome (M5):** label **UAV** (slot caption `ABILITY`). Still posts `{ type: "uav" }`.

## Locked GD earn table (2026-09-18)

Server grants these. Client copy/end overlay reads `marksDelta` from the result — it does not apply the table locally.

| Outcome | `reason` | `marksDelta` |
| --- | --- | --- |
| PvP kill (winner) | `kill` | **+25** |
| PvP standoff (turn cap) | `standoff` | **+8** |
| PvP loss | `loss` | **+3** |
| Forfeit win | `forfeit` | **+12** |
| Forfeit / disconnect loss | `forfeit` / `disconnect` | **0** |
| SP job T1 complete | `job` | **+10** |
| SP job T2 complete | `job` | **+15** |
| SP job T3 complete | `job` | **+20** |
| SP job fail | `job_fail` | **0** |

Soft A4: **30s** disconnect grace, then forfeit UI (`Contract.FORFEIT_GRACE_SEC`). Client shows forfeit chrome if `endReason` / `forfeit` / `disconnect` appears; it does not run the timer (Coder).

## Assumed field names

Parsers accept any of these bags, first hit wins: `payout` → `result` → `lastAction` → top-level snapshot.

| Field | Type | Meaning |
| --- | --- | --- |
| `you.marks` | `number` | **Wallet balance** (Coder lock). Hideout binds this. |
| `marks` | `number` | New wallet balance alias (top-level / `payout.marks`). |
| `marksDelta` | `number` | Signed change for this match/job end. |
| `reason` | `string` | Why the grant happened. |

Aliases the client also reads:

| Alias | Notes |
| --- | --- |
| `payout: { marks, marksDelta, reason }` | Preferred envelope. |
| `endReason` | Same vocabulary as `reason` when payout is missing. |
| `wallet.marks` | Mock hideout stub (`MatchAPI.wallet()`). No LIVE route yet. |
| `marks_delta` | snake_case fallback. |
| `mode` / `matchMode` / `job` / `sp` / `spJob` / `jobId` / `jobTier` | SP job vs PvP. `jobTier` 1\|2\|3. |
| `forfeit` / `disconnected` / `lastAction.type` | Soft A4 forfeit chrome. |

### `reason` / `endReason` vocabulary

`kill` · `standoff` · `loss` · `job` · `job_fail` · `forfeit` · `disconnect`

Soft A4 also treats `disconnected` and `ragequit` as forfeit UI.

## LIVE API (Coder PR merged)

| Method | Path | Body / notes |
| --- | --- | --- |
| POST | `/jobs` | `{ tier: 1\|2\|3 }` → `{ jobId, matchId, playerId, seat: "a", joinToken, tier, name, snapshot }`. Bot is seat B, already dropped. |
| GET | `/jobs/:id` | Bearer. `{ …job, snapshot }` |
| POST | `/matches/:id/heartbeat` | Bearer. Keeps A4 last-seen. **30s** silence while `active` → `endReason: forfeit`. |
| GET | `/matches/:id` | Caller snapshot. Adds `kind`, `endReason`, `job`. Balance is **`you.marks` only**. |
| POST | `/matches` | PvP create (unchanged). |

Snapshot extras: `kind: pvp|sp_job`, `endReason: kill|standoff|forfeit|null`, `job: { jobId, tier, name, status }|null`.

Hideout **JOBS → START JOB** calls `MatchAPI.create_job(1)` → LIVE `POST /jobs`. Mock still simulates the same shape and runs a local dummy seat.

## Demo one LIVE payout (GD M1–M5 + A4)

1. Hideout **LIVE** (base `https://glassline-api.vercel.app`).
2. **JOBS → START JOB** (T1 Rooftop Rookie).
3. Drop a hex. Bot is already placed. Hunt: UAV → END TURN → ATTACK revealed hex → FIRE.
4. End overlay: headline + `you.marks` balance. If `marksDelta` is absent, chrome shows `table +10` (display copy only).
5. Replay the ended match / refetch snapshot: `you.marks` must not increase again (M4).
6. Soft A4: stop heartbeat/poll for 30s while `active` → `endReason: forfeit`, forfeit overlay.

## Client surfaces

| Surface | Behavior |
| --- | --- |
| Hideout Marks chip | `MARKS ★N` from `you.marks` / last snapshot / `MatchAPI.wallet()` mock stub (`24` until a match writes the wallet). |
| Hideout last-hunt line | `marksDelta` + `reason` from `ClientSession.last_payout` after returning from a match. |
| JOBS panel | `POST /jobs` T1 (LIVE) or mock stub; table copy T1 +10 / T2 +15 / T3 +20. |
| Ability button (M5) | Slot caption **ABILITY**, label **UAV**. Still posts `{ type: "uav" }` (`ActionIntent.ability()` is an alias). |
| End overlay | Headline from winner / forfeit / job; then `+N MARK · ★balance` and `reason`. Never hardcodes a local table. |

## LIVE ledger (Coder PR #2)

`you.marks` is the wallet. Kill/job grants use the locked table (T1 job **+10**, PvP kill **+25**). Snapshot carries `kind` / `endReason` / `job`. Client never invents a delta; if `marksDelta` is missing the overlay shows `table +N` plus `★you.marks`.

Replay of the same `jobId` / `matchId` must not increase `you.marks` (M4). Mock `payoutSettled` matches that.

HTTP demo (no Godot):

```bash
GLASSLINE_API_BASE=https://glassline-api.vercel.app python3 tools/live_jobs_smoke.py
```

Expect `LIVE_JOBS_SMOKE_OK` and `you.marks +10` once. Godot demo: hideout **LIVE** → **JOBS → START JOB** → drop → **UAV** → END TURN → ATTACK the revealed hex → FIRE. Overlay: JOB COMPLETE / table +10 / ★balance. Ability label is **UAV**.

Verified 2026-09-18 against `https://glassline-api.vercel.app`: `LIVE_JOBS_SMOKE_OK j_5838afbb4638437fb4b12a2f978632cd marks 0->10` (replay GET stayed 10).

## Out of this slice

Art desk framing · parts/hideout sinks · Chips/IAP · ranked · Coder ledger implementation.
