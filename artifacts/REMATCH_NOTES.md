# Rematch (R1–R6)

Slice ticket: [🔁 Slice ticket — Rematch](https://app.notion.com/p/3e04dabdb33981729fb2e79aba0d8ba0)
Arch stamp 2026-09-19. Client half on `main` after #17 DECOY.

**Hard:** same two durable seats · new `matchId` + terrain salt · Marks already settled on prior end · no ranked/ELO · cozy hideout language.

## Contract

| Piece | Choice |
| --- | --- |
| Trigger | Ended **PvP** snapshot. Both seats see Play again / Decline. Jobs stay hideout-only. |
| API | `POST /matches/:id/rematch` `{ accept: true\|false }` + durable Bearer |
| Snapshot | `rematch: { status: none\|pending\|accepted_a\|accepted_b\|ready\|declined\|expired, newMatchId? }` |
| Both accept | Server (mock) creates a **new** match, same two `playerId`s, new salt, status `ready` — drop again |
| One decline | `declined`; no new match; client → hideout |
| Timeout | **30s** → `expired`; same as decline |
| Marks | **No** grant/spend on rematch. Prior ledger is final |
| Seed | New `matchId` ⇒ new `hash(matchId,q,r,salt)` — never reuse prior reveals |
| LIVE 404 | Coder pending. `LiveMatchClient.rematch` posts the locked body; editor uses mock |

## LIVE curl (2026-09-19)

Public `https://glassline-api.vercel.app`:

```
POST /matches/:id/rematch  { "accept": true }
HTTP 404  Not Found
```

No rematch field on ended snapshots yet. Client method is ready; mock covers R1–R5.

`python3 tools/live_rematch_smoke.py` → **`LIVE_REMATCH_PENDING`** (`artifacts/live_rematch_smoke.txt`).

Ended kill on LIVE still works (`status: ended`); rematch route is the missing piece.

## Gates

| Gate | Mock | LIVE | Notes |
| --- | --- | --- | --- |
| **R1** both accept → new match, both ready to drop | **PASS** | pending 404 | Same `playerId`s / seats. Status `ready`, hexes empty. |
| **R2** terrain differs | **PASS** | pending 404 | New `matchId` + salt suffix `:r`. 9×7 fingerprint differs. |
| **R3** one decline → hideout; no new match | **PASS** | pending 404 | `declined`. Later accept stays closed. |
| **R4** Marks unchanged | **PASS** | pending 404 | Wallet after kill stays put across accept / decline / expiry. Capture still ★49 after rematch. |
| **R5** timeout → same as decline | **PASS** | pending 404 | Mock clock +30s → `expired`. No new row. |
| **R6** Play again / Decline on ended | **PASS mock** | n/a | Primary PLAY AGAIN, secondary DECLINE, “Marks already settled.” No ranked chrome. |

Headless: `godot --headless --path . -s res://tools/headless_loop_test.gd` → **`HEADLESS_LOOP_OK`**.

## Client map

| Surface | Behavior |
| --- | --- |
| `MatchAPI.rematch(accept)` / `rematch_as` | Mock ledger or `POST /matches/:id/rematch` |
| `LiveMatchClient.rematch` | Durable Bearer. `404` → `rematch_unavailable` |
| `MatchAPI.bind_new_match` | Stop SSE, join new tokens, apply ready snapshot |
| `Snapshot.rematch_*` | Read `rematch` only; jobs → none |
| `MockMatchServer.rematch` | Pending clock, accept pair → spawn, decline / expire |
| Ended overlay | PLAY AGAIN + DECLINE + settle copy. Jobs keep HIDEOUT |
| Editor dummy | Play again also accepts seat B so the local rival drops again |

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
