# Private lobby invite (P1–P6)

Slice ticket: [🔐 Slice ticket — Private lobby invite](https://app.notion.com/p/3e04dabdb33981a38629e1958fedf1f7)
Arch stamp 2026-09-19. Client + LIVE (Coder glassline-api #11, 2026-09-20).

**Hard:** same match rules · durable players · Marks table unchanged · cancel is **not** a forfeit · no ranked.

## Contract

| Piece | Choice |
| --- | --- |
| Create | `POST /lobbies` Bearer **player** → **201** `{ lobbyId: lob_…, code, status: waiting, expiresAt, snapshot }` |
| Code | **6** uppercase, alphabet `23456789ABCDEFGHJKLMNPQRSTUVWXYZ` (no `0O1I`) |
| TTL | **10 min** idle / until match starts. No mil-sim countdown chrome. |
| Join | `POST /lobbies/join` `{ code }` Bearer → seat B; both seated → **200** `ready` `{ matchId, joinToken, snapshot }` (match snap) |
| Poll | `GET /lobbies/:id` — host wait. Ready keeps a **lobby** snap + top-level `matchId` / this seat’s `joinToken` |
| Cancel | Waiting → **200** `{ ok, status: cancelled }` hideout. After handoff → **409** `lobby_already_started`. **No** forfeit Marks. |
| Match | Existing drop / actions / rematch / A4. Client never invents seats. |
| Errors | **400** `invalid_lobby_code` / `invalid_join_body` · **404** `lobby_not_found` · **409** `lobby_expired` / `lobby_full` / `already_in_lobby` / `lobby_cancelled` / `lobby_already_started` · **401** · **403** `not_member` · `lobby_unavailable` only when the route itself is missing |

Prefer lobby→match handoff returns `matchId` + `joinToken` so the client does not invent seats. `bind_lobby_match` ignores a lobby snap and GETs the match.

## LIVE curl (2026-09-20) — routes up

Public `https://glassline-api.vercel.app` · `GET /health` → `{ ok: true }`.

```
POST /lobbies (no auth) → 401
POST /lobbies + player  → 201 { lobbyId: lob_…, code, status: waiting, expiresAt }
POST /lobbies/join      → 200 { status: ready, matchId, joinToken, seat: b }
GET  /lobbies/:id       → 200 lobby snap + matchId/joinToken when ready
POST /lobbies/:id/cancel waiting → 200 { ok, status: cancelled }
POST /lobbies/:id/cancel ready   → 409 lobby_already_started
POST /lobbies/join ABCDEF        → 404 lobby_not_found
POST /lobbies/join 10O1II        → 400 invalid_lobby_code
```

`python3 tools/live_lobby_smoke.py` → **`LIVE_LOBBY_OK`** (42 checks). Log: `artifacts/live_lobby_smoke.txt`.

| LIVE smoke | Value |
| --- | --- |
| host / guest | `p_8260535092704737a47af9ced79adc01` / `p_50b7eb9321804fa79d3d418829192df5` |
| create | **201** `lob_461e26857b6441b884ddc32acc625288` code `V8VFY6` waiting |
| join | **200** `m_5c0affb666df4e98863edda34dac60d3` seat `b` + joinToken |
| P3 | both `select_hex` 200 · attack miss `hit=false` |
| P4 | self-join **409** `already_in_lobby` · `ABCDEF` **404** `lobby_not_found` · `10O1II` **400** `invalid_lobby_code` |
| P5 cancel waiting | **200** `{ ok, status: cancelled }` · Marks **0 → 0** (no forfeit) |
| P5 after ready | **409** `lobby_already_started` · Marks frozen |

## Gates P1–P6

| Gate | Result | Evidence |
| --- | --- | --- |
| **P1** Create / wait | **PASS LIVE + mock** | 201 `lob_461e…` / `V8VFY6` waiting, no match, Marks 0 |
| **P2** Join code → seated | **PASS LIVE + mock** | Guest seat B; ready `m_5c0affb6…` + per-seat tokens. GET keeps lobby snap. |
| **P3** Same rules / Marks / rematch | **PASS LIVE + mock** | LIVE miss `hit=false`. Mock kill ★25 / ★3 + rematch. |
| **P4** Bad / expired code | **PASS LIVE + mock** | `invalid_lobby_code` / `lobby_not_found` / `already_in_lobby`. Mock TTL too. |
| **P5** Cancel / leave → hideout | **PASS LIVE + mock** | Waiting cancelled, wallet 0→0, no forfeit. Ready → `lobby_already_started`. |
| **P6** UX cozy wartable | **PASS mock** | Stills below. Gold INVITE, chunky code, no ranked / countdown chrome. |

Headless: `godot --headless --path . -s res://tools/headless_loop_test.gd` → **`HEADLESS_LOOP_OK`**.

## Client map

| Surface | Behavior |
| --- | --- |
| Hideout **INVITE** | Wartable panel (JOBS / ARMORY language). CREATE LOBBY + JOIN code. PLAY stays dummy both-seats. |
| Host wait | Chunky `ABC DEF` code, COPY, “Waiting on your rival…”. Poll `GET /lobbies/:id`. No TTL clock. |
| Join | 6-char field. Bad/expired/`lobby_not_found` → “That code is expired or wrong.” No soft lock. Route-missing only → “LIVE invite not ready”. |
| Cancel | Hideout. Toast “Back at the hideout.” Marks chip rebound from snapshot only. Never abandon / A4. |
| Ready | `MatchAPI.bind_lobby_match` — `matchId` + `joinToken`. Skips lobby snap; GETs the match. |
| Mock | `MockMatchServer` `lob_` ids, LIVE error codes, join attaches match snap, GET keeps lobby snap. |
| LIVE | `LiveMatchClient` posts the locked body. 404 + `lobby_not_found` is reject. Bare 404 → `lobby_unavailable`. F2 still toggles. |

## Stills

| Gate | File |
| --- | --- |
| P6 create / wait | `artifacts/ux/lobby_create_wait.png` |
| P6 join | `artifacts/ux/lobby_join.png` |
| P6 bad code | `artifacts/ux/lobby_bad_code.png` |
| P6 cancel → hideout | `artifacts/ux/lobby_cancel_hideout.png` |

Capture (mock, `DISPLAY=:1`):

```
/tmp/godot --path . --resolution 1280x720 -- --capture-lobby-create-wait
/tmp/godot --path . --resolution 1280x720 -- --capture-lobby-join
/tmp/godot --path . --resolution 1280x720 -- --capture-lobby-bad-code
/tmp/godot --path . --resolution 1280x720 -- --capture-lobby-cancel-hideout
```

## Out

Voice · parties > 2 · ranked / ELO · public queue · cross-region matchmaking · mil-sim lobby countdown · forfeit Marks on cancel.
