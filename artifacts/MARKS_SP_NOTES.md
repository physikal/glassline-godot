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

## Create / join — SP job stub

LIVE `POST /matches` currently ignores the body (`createMatch()` takes no args). Client still sends:

```
POST /matches
{ "mode": "sp_job", "job": true, "sp": true, "jobTier": 1 }
```

If Coder adds a dedicated route, prefer keeping this body so the Godot path does not fork. `jobId` (when present) is treated as the idempotency key; mock uses `matchId` until then.

No `/jobs` endpoint exists — the hideout **JOBS → START JOB** button hits the existing create/join/actions loop with `mode: "sp_job"` and the local dummy seat as the bot. Stub defaults to **T1**.

## Client surfaces

| Surface | Behavior |
| --- | --- |
| Hideout Marks chip | `MARKS ★N` from `you.marks` / last snapshot / `MatchAPI.wallet()` mock stub (`24` until a match writes the wallet). |
| Hideout last-hunt line | `marksDelta` + `reason` from `ClientSession.last_payout` after returning from a match. |
| JOBS panel | SP job vs bot; same Attack/Recon/UAV rules. |
| Ability button (M5) | Slot caption **ABILITY**, label **UAV**. Still posts `{ type: "uav" }` (`ActionIntent.ability()` is an alias). |
| End overlay | Headline from winner / forfeit / job; then `+N MARK · ★balance` and `reason`. Never hardcodes a local table. |

## LIVE today (do not break)

`you.marks` is already the persistent `marks` table. Kill currently increments **+1** on the live API until Coder lands this table. Snapshot has no `marksDelta` / `reason` / `mode` yet — the end screen then shows **balance only** (no invented delta).

Grant is idempotent on `matchId` in the mock (`payoutSettled`). Replay of the same ended match does not add again (M4).

## Out of this slice

Art desk framing · parts/hideout sinks · Chips/IAP · ranked · Coder ledger implementation.
