# Quick Match (Q1–Q6)

Slice ticket: [⚡ Slice ticket — Quick Match](https://app.notion.com/p/3e14dabdb33981a9a30dec89460094e3)
Arch stamp 2026-09-20. Client + mock + **LIVE `/queue` (Coder PR #13, `queue.ts`)**.

**Hard:** 1-tap hideout queue · same match once found · **no bot fill** · cancel/timeout Marks **Δ0** · no ranked / MMR chrome.

## Contract

| Piece | Choice |
| --- | --- |
| Entry | Hideout **QUICK MATCH** → `POST /queue` Bearer **player** → `{ status: queued, queuedAt, timeoutSec: 60, expiresAt }` |
| Poll | `GET /queue` — `idle` \| `queued` + `secondsLeft` \| `matched` \| **`expired`** (once, then idle) |
| Cancel | `DELETE /queue` → `{ status: idle }` hideout. **Marks Δ0**. Waiting rows only. After pair → idle response, **matched row stays** |
| Timeout | **60s** TTL (server `expiresAt` + client mirror) → first GET `expired`, next GET `idle`. Hideout. **Marks Δ0**. No forfeit overlay |
| Pair | Two waiting humans → existing `createReadyPvpMatch` / drop / rematch / A4. Guest POST can return `matched` immediately. Client never invents seats |
| Bot fill | **Out** (Q5). Third waiter stays `queued` |
| Re-queue | Idempotent POST while queued **refreshes `expiresAt`**, keeps `queuedAt` |
| Errors | **401** missing bearer · **409** `already_in_match` / `in_lobby`. Bare 404 → `queue_unavailable` + mock toast |

Prefer queue→match handoff returns `matchId` + `joinToken` + `seat` + match snapshot (`ready`). `bind_queue_match` reuses `bind_lobby_match` (skips queue snap; GETs the match).

## Gates Q1–Q6

| Gate | Result | Evidence |
| --- | --- | --- |
| **Q1** Hideout 1-tap → queue | **PASS mock + LIVE** | `POST /queue` queued, `timeoutSec` 60, `expiresAt`, GET `secondsLeft`, no match |
| **Q2** Match found → same rules / Marks / A4 / Rematch | **PASS mock + LIVE** | Two humans pair. Seats A/B + own `joinToken`. Snapshot `ready` / `pvp`. Miss `hit=false`. Kill ★25 / ★3 + rematch offered (mock). LIVE drop `select_hex` still match path |
| **Q3** Cancel → hideout, Marks Δ0 | **PASS mock + LIVE** | `DELETE /queue` idle, wallet 0→0 (LIVE) / 24→24 (mock), no match minted. Re-DELETE idle |
| **Q4** 60s timeout → hideout, Marks Δ0 | **PASS mock + LIVE** | First GET after TTL → `expired`, next → `idle`. Wallet unchanged. No forfeit match |
| **Q5** No bot fill | **PASS mock + LIVE** | One queued player stays queued. Third LIVE waiter stays `queued` with no `matchId` |
| **Q6** Cozy Finding a rival… | **PASS mock stills** | Stills below. Teal wartable, no MMR / ranked / countdown chrome |

Headless: `godot --headless --path . -s res://tools/headless_loop_test.gd` → **`HEADLESS_LOOP_OK`**.

LIVE: `python3 tools/live_queue_smoke.py` → **`LIVE_QUEUE_OK`**. Public `https://glassline-api.vercel.app`. `GET /health` `{ ok: true }`. Bare `POST /queue` (no auth) → **401**. Real Q4 waits 61s (`GLASSLINE_QUEUE_SKIP_TTL=1` skips).

## Client map

| Surface | Behavior |
| --- | --- |
| Hideout **QUICK MATCH** | 1-tap dock (teal, binoculars). Alongside PLAY (dummy both-seats) + INVITE Create/Join |
| Queue UI | Wartable modal: **FINDING A RIVAL…** / “Scouting the hideouts. Same hunt when they sit.” Chip + **CANCEL**. No timer-as-ranked |
| Cancel | Hideout. Toast “Back at the hideout.” Marks chip rebound from snapshot only |
| Timeout | GET `expired` treated as timeout. Same hideout as cancel. Toast “No rival yet. Back at the hideout.” Never abandon / A4 |
| 409 | `already_in_match` → “Already in a hunt.” · `in_lobby` → “Finish the invite first.” |
| Ready | `MatchAPI.bind_queue_match` — `matchId` + `joinToken`. Existing drop |
| Mock | `MockMatchServer.enqueue` / `get_queue` / `dequeue`. Pair after `queue_pair_delay_ms` (80). Expire uses `expiresAtMs`. First TTL poll `expired`. DELETE after pair returns idle and leaves matched row |
| LIVE | `LiveMatchClient` POST/GET/DELETE `/queue` + player Bearer. Bare 404 → `queue_unavailable`. F2 still toggles |

## Stills

| Gate | File |
| --- | --- |
| Q6 finding | `artifacts/ux/queue_finding_rival.png` |
| Q3 cancel → hideout | `artifacts/ux/queue_cancel_hideout.png` |
| Q4 timeout → hideout | `artifacts/ux/queue_timeout_hideout.png` |
| Q2 matched board | `artifacts/ux/queue_matched_board.png` |

Raw GitHub:

- https://raw.githubusercontent.com/physikal/glassline-godot/cursor/quick-match-queue-eb14/artifacts/ux/queue_finding_rival.png
- https://raw.githubusercontent.com/physikal/glassline-godot/cursor/quick-match-queue-eb14/artifacts/ux/queue_cancel_hideout.png
- https://raw.githubusercontent.com/physikal/glassline-godot/cursor/quick-match-queue-eb14/artifacts/ux/queue_timeout_hideout.png
- https://raw.githubusercontent.com/physikal/glassline-godot/cursor/quick-match-queue-eb14/artifacts/ux/queue_matched_board.png

Capture (mock, `DISPLAY=:1`):

```
/tmp/godot --path . --resolution 1280x720 -- --capture-queue-finding-rival
/tmp/godot --path . --resolution 1280x720 -- --capture-queue-cancel-hideout
/tmp/godot --path . --resolution 1280x720 -- --capture-queue-timeout-hideout
/tmp/godot --path . --resolution 1280x720 -- --capture-queue-matched-board
```

## LIVE (Coder PR #13)

Public `https://glassline-api.vercel.app` · `GET /health` → `{ ok: true }`.

```
POST /queue (no auth)            → 401 missing bearer
POST /queue + player (alone)     → 200 queued { queuedAt, timeoutSec: 60, expiresAt }
GET  /queue (queued)             → 200 queued + secondsLeft
POST /queue (second human)       → 200 matched { matchId, joinToken, seat: b, snapshot ready pvp }
GET  /queue (first human)        → 200 matched { matchId, joinToken, seat: a }
DELETE /queue (waiting)          → 200 idle
GET  /queue (after 60s TTL)      → 200 expired once, then idle
```

No bot fill. Cancel/timeout Marks Δ0. Pair uses existing match join/actions.

## Out

Skill rating / MMR · party queue · paid skip · bot fill · ranked chrome · countdown-as-ranked · forfeit Marks on cancel/timeout.
