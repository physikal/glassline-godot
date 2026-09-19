# Rematch (R1–R6)

Slice ticket: [🔁 Slice ticket — Rematch](https://app.notion.com/p/3e04dabdb33981729fb2e79aba0d8ba0)
Arch stamp 2026-09-19. Client half on `main` after #17 DECOY. LIVE route: Coder [glassline-api#9](https://github.com/physikal/glassline-api/pull/9).

**Hard:** same two durable seats · new `matchId` + terrain salt · Marks already settled on prior end · no ranked/ELO · cozy hideout language.

## Contract

| Piece | Choice |
| --- | --- |
| Trigger | Ended **PvP** snapshot. Both seats see Play again / Decline. Jobs stay hideout-only. |
| API | `POST /matches/:id/rematch` `{ accept: true\|false }` · Bearer **join token** (durable player token of a seated `playerId` also OK) |
| Snapshot | `rematch: { status: none\|waiting\|ready\|declined\|expired, youAccepted?, opponentAccepted?, expiresAt?, newMatchId? }` |
| POST waiting | `{ status: "waiting", youAccepted, opponentAccepted, expiresAt }` |
| POST ready | `{ status: "ready", matchId, joinToken, snapshot }` — replay the other seat for its token |
| Both accept | New match, same two `playerId`s / seats, new salt, status `ready` — drop again |
| One decline | `{ status: "declined" }`; no new match; client → hideout |
| Timeout | **30s from match end** → `{ status: "expired" }`; same as decline |
| Marks | **No** grant/spend on rematch. Prior ledger is final |
| Seed | New `matchId` ⇒ new `hash(matchId,q,r,salt)` — never reuse prior reveals |
| Errors | 409 `match_not_ended` / `rematch_not_available` · 400 `invalid_rematch_body` · 404 until LIVE ships |
| Aliases | Client maps `pending\|accepted_a\|accepted_b` → `waiting` |

## LIVE curl (2026-09-19)

Public `https://glassline-api.vercel.app`:

```
POST /matches/:id/rematch  { "accept": true }
```

Probe first. **404** → `LIVE_REMATCH_PENDING` (mock + client stay ready). **200** → prefer LIVE for R1–R5 (`python3 tools/live_rematch_smoke.py`).

`artifacts/live_rematch_smoke.txt` is the last probe.

Ended kill on LIVE still works (`status: ended`) even while rematch is 404.

## Gates

| Gate | Mock | LIVE | Notes |
| --- | --- | --- | --- |
| **R1** both accept → new match, both ready to drop | **PASS** | curl first | Same `playerId`s / seats. `ready` + `joinToken` + empty hex. Replay A after B. |
| **R2** terrain differs | **PASS** | curl first | New `matchId` + salt. 9×7 fingerprint differs. |
| **R3** one decline → hideout; no new match | **PASS** | curl first | `declined`. Later accept stays closed. |
| **R4** Marks unchanged | **PASS** | curl first | Wallet after kill stays put across accept / decline / expiry. |
| **R5** timeout → same as decline | **PASS** | curl first | Mock clock +30s → `expired`. LIVE waits 31s. |
| **R6** Play again / Decline on ended | **PASS mock** | n/a | Wood/gold plate. Primary PLAY AGAIN, secondary DECLINE, “Marks already settled.” No ranked chrome. |

Headless: `godot --headless --path . -s res://tools/headless_loop_test.gd` → **`HEADLESS_LOOP_OK`**.

## Client map

| Surface | Behavior |
| --- | --- |
| `MatchAPI.rematch(accept)` / `rematch_as` | Mock ledger or `POST /matches/:id/rematch` |
| `LiveMatchClient.rematch` | Join-token Bearer, then player. `404` → `rematch_unavailable` |
| `MatchAPI.bind_new_match` | Stop SSE, bind `matchId` + `joinToken`, apply posted snapshot or GET |
| `Snapshot.rematch_*` | Read `rematch` only; jobs → none; aliases → waiting |
| `MockMatchServer.rematch` | Waiting clock, accept pair → spawn LIVE-shaped payload |
| Ended overlay | PLAY AGAIN + DECLINE + settle copy. Jobs keep HIDEOUT |
| Rival-accept via poll | Snapshot names `newMatchId` only — replay POST for this seat’s `joinToken` |
| Editor dummy | Dummy accepts, then replay human rematch so LIVE returns the caller `joinToken` |

## Stills

| Gate | File |
| --- | --- |
| R6 CTA | `artifacts/ux/rematch_ended_cta.png` |
| R6 new board | `artifacts/ux/rematch_ready_new_board.png` |

Capture (mock, `DISPLAY=:1`):

```
/tmp/godot --path . --resolution 1280x720 -- --capture-rematch-ended
/tmp/godot --path . --resolution 1280x720 -- --capture-rematch-ready
```

## Out

Ranked / ELO · party invite · best-of-N · rematch Marks grant/spend · IAP.
