# Rematch (R1–R6)

Slice ticket: [🔁 Slice ticket — Rematch](https://app.notion.com/p/3e04dabdb33981729fb2e79aba0d8ba0)
Arch stamp 2026-09-19. Client LIVE bind: [glassline-godot#19](https://github.com/physikal/glassline-godot/pull/19) (merged). LIVE route: Coder [glassline-api#9](https://github.com/physikal/glassline-api/pull/9) (merged).

**Hard:** same two durable seats · new `matchId` + terrain salt · Marks already settled on prior end · rematch never invents Marks · no ranked/ELO · cozy hideout language.

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
| Timeout | **30s from match end** (`expiresAt`) → `{ status: "expired" }`; same as decline |
| Marks | **No** grant/spend on rematch. Prior ledger is final |
| Seed | New `matchId` ⇒ new `hash(matchId,q,r,salt)` — never reuse prior reveals |
| Errors | 409 `match_not_ended` / `rematch_not_available` · 400 `invalid_rematch_body` |
| Aliases | Client maps `pending\|accepted_a\|accepted_b` → `waiting` |

## LIVE curl (2026-09-19) — route up

Public `https://glassline-api.vercel.app` · `GET /health` → `{ ok: true }`.

Non-ended match **`m_d465062d10224f728986d232e14adc05`** (join Bearer):

```
HTTP 409  { "error": "match is not ended", "code": "match_not_ended" }
```

That 409 is the route-up proof. Earlier probe on `m_de2830b71279419a953f161636178819` returned the same 409 with player Bearer too.

Ended snapshot already exposes the clock:

```
rematch: { status: "waiting", youAccepted: false, opponentAccepted: false,
           expiresAt: "2026-09-19T22:26:25.335Z" }
```

`python3 tools/live_rematch_smoke.py` → **`LIVE_REMATCH_OK`**. Log: `artifacts/live_rematch_smoke.txt`.

## LIVE R1–R5 (Coder clear)

Durable pair: **`p_619f35e7552d44a1a0821de1db634d2f`** (A) · **`p_27d82f48805e48a096b301b29bde85e3`** (B).

| Gate | Result | matchIds / deltas |
| --- | --- | --- |
| **R1** both accept → new matchId + fresh terrain | **PASS LIVE** | Ended `m_8592812b3fa24439a8b7f75e77a13a74` → ready `m_2e2a7e879a904b02a090447c13e97b1e` + per-seat `joinToken` + empty hex. 9-hex sample differs (old `2,2=brush` / `7,5=hard` → new `2,2=open` / `7,5=brush`). |
| **R2** same durable players | **PASS LIVE** | Join on the new match returns the same `playerId`s / seats. Player-token rematch replay still names `m_2e2a7e879a904b02a090447c13e97b1e`. |
| **R3** Marks unchanged by rematch | **PASS LIVE** | Kill already settled **A ★25 / B ★3**. Shop + snapshot after accept/replay/decline: **Δ0 / Δ0**. Rematch wrote no ledger. |
| **R4** one Decline → hideout | **PASS LIVE** | Ended `m_a6dab85e5bb048b18533f550a4855fd0` → `{ status: "declined" }`. No `newMatchId`. Later accept stays declined. |
| **R5** timeout → hideout | **PASS LIVE** | Ended `m_286fb28d769c4e6d9d1e0780cea9ddef`, `expiresAt=2026-09-19T22:26:32.911Z` (30s from end). After 31s GET + late accept → `{ status: "expired" }`. No new match. |
| **R6** Play again / Decline on ended | **PASS mock** | Wood/gold plate. Primary PLAY AGAIN, secondary DECLINE, “Marks already settled.” No ranked chrome. |

First manual both-accept (same shapes, not in the script table): ended `m_de2830b71279419a953f161636178819` → ready `m_5bb8b48da3784bf3be2de374d2f3ef95`.

Headless mock: `godot --headless --path . -s res://tools/headless_loop_test.gd` → **`HEADLESS_LOOP_OK`**.

## Client map

| Surface | Behavior |
| --- | --- |
| `MatchAPI.rematch(accept)` / `rematch_as` | Mock ledger or `POST /matches/:id/rematch` |
| `LiveMatchClient.rematch` | Join-token Bearer, then player. `404` → `rematch_unavailable` |
| `MatchAPI.bind_new_match` | Stop SSE, bind `matchId` + `joinToken`, apply posted snapshot or GET |
| `Snapshot.rematch_*` | Read `rematch` only; jobs → none; aliases → waiting |
| `MockMatchServer.rematch` | Waiting clock, accept pair → spawn LIVE-shaped payload |
| Ended overlay | PLAY AGAIN + DECLINE + settle copy. Jobs keep HIDEOUT |
| Ready START | Centered drop cue on the board (not under the P2 name) |
| Rival-accept via poll | Snapshot names `newMatchId` only — replay POST for this seat’s `joinToken` |
| Editor dummy | Dummy accepts, then replay human rematch so LIVE returns the caller `joinToken` |

## Stills

| Gate | File |
| --- | --- |
| R6 CTA | `artifacts/ux/rematch_ended_cta.png` |
| R6 new board | `artifacts/ux/rematch_ready_new_board.png` — centered **START** ready/drop cue |

Capture (mock, `DISPLAY=:1`):

```
/tmp/godot --path . --resolution 1280x720 -- --capture-rematch-ended
/tmp/godot --path . --resolution 1280x720 -- --capture-rematch-ready
```

## Out

Ranked / ELO · party invite · best-of-N · rematch Marks grant/spend · IAP.
