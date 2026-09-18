# Marks earn + SP job stub — client assumptions (Coder align)

Client half of [Slice ticket — Marks earn + SP job stub](https://www.notion.so/3df4dabdb33981b19fb7f3847132630e).  
Godot **displays only**. The mock may simulate a ledger for hideout/end chrome. LIVE remains source of truth.

Parked here: art desk framing, IAP/Chips, parts sinks.

## Hard rule

Never `marks +=` on the client as truth. `ClientSession.marks` is a display cache updated by `apply_snapshot` / `bind_marks` from a server (or mock) payload.

## Assumed field names

Scaffolded even if the live API has not shipped them yet. Parsers accept any of these bags, first hit wins: `payout` → `result` → `lastAction` → top-level snapshot.

| Field | Type | Meaning |
| --- | --- | --- |
| `marks` | `number` | **New wallet balance** after the grant (not match-local +1). |
| `marksDelta` | `number` | Signed change for this match/job end. |
| `reason` | `string` | Why the grant happened. |

Aliases the client also reads:

| Alias | Notes |
| --- | --- |
| `payout: { marks, marksDelta, reason }` | Preferred envelope. |
| `endReason` | Same vocabulary as `reason` when payout is missing. |
| `you.marks` | Live API **already** returns the `marks` table wallet here. Hideout binds this when present. |
| `wallet.marks` | Mock hideout stub (`MatchAPI.wallet()`). No LIVE route yet. |
| `marks_delta` | snake_case fallback. |
| `mode` / `matchMode` / `job` / `sp` / `spJob` / `jobId` | SP job vs PvP. |
| `forfeit` / `disconnected` / `lastAction.type` | Soft A4 forfeit chrome. |

### `reason` / `endReason` vocabulary (assumed)

`kill` · `standoff` · `loss` · `job` · `job_fail` · `forfeit` · `disconnect`

Soft A4 also treats `disconnected` and `ragequit` as forfeit UI.

## Create / join — SP job stub

LIVE `POST /matches` currently ignores the body (`createMatch()` takes no args). Client still sends:

```
POST /matches
{ "mode": "sp_job", "job": true, "sp": true }
```

If Coder adds a dedicated route, prefer keeping this body so the Godot path does not fork. `jobId` (when present) is treated as the idempotency key; mock uses `matchId` until then.

No `/jobs` endpoint exists — the hideout **JOBS → START JOB** button hits the existing create/join/actions loop with `mode: "sp_job"` and the local dummy seat as the bot.

## Stub earn table (mock display only)

GD one-pager is still TBD. Mock grants so M1–M4 chrome can be wired. **Do not treat these as locked.**

| Outcome | `reason` | `marksDelta` |
| --- | --- | --- |
| PvP kill (winner) | `kill` | `1` |
| PvP loss | `loss` | `0` |
| Standoff (turn cap) | `standoff` | `0` (Arch default until GD says otherwise) |
| SP job complete | `job` | `1` |
| SP job fail | `job_fail` | `0` |
| Forfeit winner | `forfeit` | `1` (GDD “reduced bounty” — same stub until GD) |
| Forfeit / disconnect loser | `forfeit` / `disconnect` | `0` |

Grant is idempotent on `matchId` in the mock (`payoutSettled`). Replay of the same ended match does not add again (M4).

## Client surfaces

| Surface | Behavior |
| --- | --- |
| Hideout Marks chip | `MARKS ★N` from last snapshot / `MatchAPI.wallet()` mock stub (`24` until a match writes the wallet). |
| Hideout last-hunt line | `marksDelta` + `reason` from `ClientSession.last_payout` after returning from a match. |
| JOBS panel | SP job vs bot; same Attack/Recon/UAV rules. |
| Ability button (M5) | Slot caption **ABILITY**, label **UAV**. Still posts `{ type: "uav" }` (`ActionIntent.ability()` is an alias). |
| End overlay | Headline from winner / forfeit / job; then `+N MARK · ★balance` and `reason`. Never hardcodes “Marks +1”. |

## LIVE today (do not break)

`you.marks` is already the persistent `marks` table. Kill does `incrementMarks` +1 on the server. Snapshot has no `marksDelta` / `reason` / `mode` yet — the end screen then shows **balance only** (no invented delta).

## Out of this slice

Art desk framing · parts/hideout sinks · Chips/IAP · ranked · Coder ledger / GD earn-table lock.
