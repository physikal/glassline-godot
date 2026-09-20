# Quick Match (Q1–Q6)

Slice ticket: [⚡ Slice ticket — Quick Match](https://app.notion.com/p/3e14dabdb33981a9a30dec89460094e3)
Arch stamp 2026-09-20. Client + mock. **LIVE `/queue` 404 — Coder blocker.**

**Hard:** 1-tap hideout queue · same match once found · **no bot fill** · cancel/timeout Marks **Δ0** · no ranked / MMR chrome.

## Contract

| Piece | Choice |
| --- | --- |
| Entry | Hideout **QUICK MATCH** → `POST /queue` Bearer **player** → `{ status: queued, queuedAt, timeoutSec: 60 }` |
| Poll | `GET /queue` — `queue: { status, secondsLeft }` while waiting. Found → `matched` + `matchId` + `joinToken` |
| Cancel | `DELETE /queue` → `{ status: idle }` hideout. **Marks Δ0**. After handoff → **409** `queue_already_matched` |
| Timeout | **60s** TTL (server + client mirror) → dequeue + hideout. **Marks Δ0**. No forfeit overlay |
| Pair | Two waiting humans → existing `create_match` / drop / rematch / A4. Client never invents seats |
| Bot fill | **Out** (Q5) |
| Re-queue | Idempotent POST while queued **refreshes TTL** (mock pick; Coder may no-op — document) |
| LIVE 404 | Bare `POST /queue` 404 → `queue_unavailable`. Mock + stills. Toast “LIVE queue not ready” |

Prefer queue→match handoff returns `matchId` + `joinToken`. `bind_queue_match` reuses `bind_lobby_match` (skips queue snap; GETs the match).

## Gates Q1–Q6

| Gate | Result | Evidence |
| --- | --- | --- |
| **Q1** Hideout 1-tap → queue | **PASS mock** | `POST /queue` queued, timeoutSec 60, no match, Marks 24. Hideout **QUICK MATCH** |
| **Q2** Match found → same rules / Marks / A4 / Rematch | **PASS mock** | Pair after 80ms delay. Seats A/B + tokens. Miss `hit=false`. Kill ★25 / ★3 + rematch offered |
| **Q3** Cancel → hideout, Marks Δ0 | **PASS mock** | `DELETE /queue` idle, wallet 24→24, no match minted |
| **Q4** 60s timeout → hideout, Marks Δ0 | **PASS mock** | TTL +50ms → `timeout` / `timedOut`, wallet 18→18, no forfeit match |
| **Q5** No bot fill | **PASS mock** | One queued player after pair-delay still queued; `_matches` empty |
| **Q6** Cozy Finding a rival… | **PASS mock** | Stills below. Teal wartable, no MMR / ranked / countdown chrome |

Headless: `godot --headless --path . -s res://tools/headless_loop_test.gd` → **`HEADLESS_LOOP_OK`**.

LIVE: `python3 tools/live_queue_smoke.py` → **`LIVE_QUEUE_PENDING POST /queue 404`**. Retry when Coder ships the route.

## Client map

| Surface | Behavior |
| --- | --- |
| Hideout **QUICK MATCH** | 1-tap dock (teal, binoculars). Alongside PLAY (dummy both-seats) + INVITE Create/Join |
| Queue UI | Wartable modal: **FINDING A RIVAL…** / “Scouting the hideouts. Same hunt when they sit.” Chip + **CANCEL**. No timer-as-ranked |
| Cancel | Hideout. Toast “Back at the hideout.” Marks chip rebound from snapshot only |
| Timeout | Same hideout as cancel. Toast “No rival yet. Back at the hideout.” Never abandon / A4 |
| Ready | `MatchAPI.bind_queue_match` — `matchId` + `joinToken`. Existing drop |
| Mock | `MockMatchServer.enqueue` / `get_queue` / `dequeue`. Pair after `queue_pair_delay_ms` (80). No bot seat |
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

## Coder blocker

Public `https://glassline-api.vercel.app` · `GET /health` → `{ ok: true }`.

```
POST /queue (no auth) → 404
POST /queue + player  → 404
GET  /queue           → 404
DELETE /queue         → 404
```

Ship:

```
POST   /queue  Bearer player → 200/201 { status: queued, queuedAt, timeoutSec: 60 }
GET    /queue  Bearer player → 200 queued \| matched { matchId, joinToken }
DELETE /queue  Bearer player → 200 { status: idle }
```

No bot fill. Cancel/timeout Marks Δ0. Then `python3 tools/live_queue_smoke.py` → `LIVE_QUEUE_OK`.

## Out

Skill rating / MMR · party queue · paid skip · bot fill · ranked chrome · countdown-as-ranked · forfeit Marks on cancel/timeout.
