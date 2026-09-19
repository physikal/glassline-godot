# SP job T2/T3 ladder — client (J1–J5)

Client half of [Slice ticket — SP job T2/T3 ladder](https://www.notion.so/3e04dabdb33981d4a46dd9ddd25d1439).  
Hideout ladder UX + LIVE smoke. **No contract rewrite.** Server already awards T1 ★10 / T2 ★15 / T3 ★20 at match/job end.

Hard: awards < PvP kill ★25 · durable `POST /players` Bearer · snapshot-only Marks. No new cosmetics, IAP, combat reward chrome, or mil-sim art.

## LIVE shapes (curled 2026-09-19)

**Base:** `https://glassline-api.vercel.app`

`GET /docs/contract` + live POST:

| Call | Body | Response |
| --- | --- | --- |
| `POST /players` | `{}` | `{ playerId, token, marks }` — **keep `token`** |
| `POST /jobs` | `{ tier: 1\|2\|3 }` | `201` `{ jobId, matchId, playerId, seat: "a", joinToken, tier, name, snapshot }` |
| `GET /jobs/:id` | Bearer = job `joinToken` | `{ …job, snapshot }` |
| `POST /auth/dev` | `{ token }` | `{ playerId, marks }` durable wallet |

Names: T1 `Rooftop Rookie` · T2 `Warehouse Watch` · T3 `Night Contract`.  
Snapshot: `kind: "sp_job"`, `job: { jobId, tier, name, status }`, balance is **`you.marks`**.

`JobCreateSchema` is `{ tier }` only. Extra `clientJobId` is accepted (stripped) and does **not** make create idempotent — a replay POST mints a **new** `jobId` / match. Credit is ledger `(job, jobId, playerId)` at **match end**. Client still sends `clientJobId` (shop-shaped) so J4 can name the complete.

Bot drop (`src/bot.ts` `SP_BOT_HEX`): T1 `(8,6)` · T2 `(7,5)` · T3 `(8,5)`.

## J1–J5 mapping

| Gate | Client surface | Pass |
| --- | --- | --- |
| **J1** | Hideout row **T1 Rooftop Rookie ★10** → START → board → kill | LIVE `you.marks` **+10**. Mock `complete_job(1, clientJobId)` same bind. |
| **J2** | **T2 Warehouse Watch ★15** | LIVE **+15** on the same Bearer. |
| **J3** | **T3 Night Contract ★20** | LIVE **+20** on the same Bearer. |
| **J4** | Replay same complete (`GET /matches/:id`, `GET /jobs/:id`, re-attack ended job, POST `/jobs` same `clientJobId` without a second kill) | Wallet unchanged. Mock `complete_job` receipts are keyed by `clientJobId`. |
| **J5** | Three lobby-canon rows + post-T3 Marks chip | `artifacts/ux/sp_jobs_ladder.png` · `artifacts/ux/sp_job_t3_post_marks.png` |

## Client surfaces

| Surface | Behavior |
| --- | --- |
| JOBS panel | Three ARMORY-language rows (gold edge, cream name, ★ payout, orange START). ARMORY hides while the ladder is open. T1 stub stays; T2 + T3 added. |
| START | `POST /jobs` `{ tier, clientJobId }` + durable Bearer. New UUID every click. Then the board (no local grant). |
| Marks chip | `MARKS ★N` from snapshot `you.marks` / `MatchAPI.wallet()` only. Never `marks +=`. |
| Editor MOCK | Default. `MockMatchServer.create_job` / `complete_job` (capture + headless). F2 still toggles LIVE. |
| End overlay | Unchanged: SP `kill` → display `job`; table T1/T2/T3 copy from `job.tier`. |

## Smoke

```bash
GLASSLINE_API_BASE=https://glassline-api.vercel.app python3 tools/live_jobs_ladder_smoke.py
godot --headless --path . -s res://tools/headless_loop_test.gd   # HEADLESS_LOOP_OK
godot --resolution 1280x720 -- --capture-sp-jobs-ladder
godot --resolution 1280x720 -- --capture-sp-job-t3
```

Expect `LIVE_JOBS_LADDER_OK` and stacked **0→10→25→45** on one player. J4 stays **45**.

T1-only playthrough remains `tools/live_jobs_smoke.py` (`LIVE_JOBS_SMOKE_OK`).

## Out of this slice

Second cosmetic sink · IAP · combat reward changes · art pass · matchmaking.
