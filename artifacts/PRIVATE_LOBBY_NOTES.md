# Private lobby invite (P1–P6)

Slice ticket: [🔐 Slice ticket — Private lobby invite](https://app.notion.com/p/3e04dabdb33981a38629e1958fedf1f7)
Arch stamp 2026-09-19. Client: this PR. LIVE routes: Coder pending (curl first).

**Hard:** same match rules · durable players · Marks table unchanged · cancel is **not** a forfeit · no ranked.

## Contract

| Piece | Choice |
| --- | --- |
| Create | `POST /lobbies` Bearer **player** → `{ lobbyId, code, snapshot }` status `waiting` |
| Code | **6** uppercase alphanumeric, exclude ambiguous `0O1I` |
| TTL | **10 min** idle / until match starts. No mil-sim countdown chrome. |
| Join | `POST /lobbies/join` `{ code }` Bearer → seat B; both seated → `ready` `{ matchId, joinToken, snapshot }` |
| Poll | `GET /lobbies/:id` — host wait until ready (this seat’s `joinToken`) |
| Cancel | `POST /lobbies/:id/cancel` → hideout. **No** forfeit Marks. |
| Match | Existing drop / actions / rematch / A4. Client never invents seats. |
| Errors | `bad_code` · `lobby_expired` · `lobby_cancelled` · `lobby_full` · `same_player` · `lobby_unavailable` (404) |

Prefer lobby→match handoff returns `matchId` + `joinToken` so the client does not invent seats.

## LIVE curl (2026-09-20) — route pending

Public `https://glassline-api.vercel.app` · `GET /health` → `{ ok: true }`.

```
POST /lobbies        → HTTP 404
POST /lobbies/join   → HTTP 404
GET  /lobbies        → HTTP 404
```

`python3 tools/live_lobby_smoke.py` → **`LIVE_LOBBY_PENDING lobbies_404`**.

Minted players `p_c9e6f03c7918477c907b451e7dbc9c4e` / `p_6880fc8bfae947de87748260f5647e9e` then `POST /lobbies` **404**. Log: `artifacts/live_lobby_smoke.txt`. Re-run when Coder lands the routes; prefer LIVE P1–P5 once 200.

## Gates P1–P6

| Gate | Result | Evidence |
| --- | --- | --- |
| **P1** Create / wait | **PASS mock** | `HEADLESS_LOOP_OK` — `waiting`, 6-char code, no match yet, Marks frozen |
| **P2** Join code → seated | **PASS mock** | Guest seat B; both seated → `ready` + `matchId` + per-seat `joinToken` |
| **P3** Same rules / Marks / rematch | **PASS mock** | Miss no invented Hot. Kill ★25 / ★3. Rematch still offered. |
| **P4** Bad / expired code | **PASS mock** | Junk / unknown / `0O1I` / TTL → reject. Field stays editable. |
| **P5** Cancel / leave → hideout | **PASS mock** | `cancelled`. Wallet frozen. No match row. No A4 forfeit overlay. |
| **P6** UX cozy wartable | **PASS mock** | Stills below. Gold INVITE, chunky code, no ranked / countdown chrome. |

Headless: `godot --headless --path . -s res://tools/headless_loop_test.gd` → **`HEADLESS_LOOP_OK`**.

## Client map

| Surface | Behavior |
| --- | --- |
| Hideout **INVITE** | Wartable panel (JOBS / ARMORY language). CREATE LOBBY + JOIN code. PLAY stays dummy both-seats. |
| Host wait | Chunky `ABC DEF` code, COPY, “Waiting on your rival…”. Poll `GET /lobbies/:id`. No TTL clock. |
| Join | 6-char field. Bad/expired → “That code is expired or wrong.” No soft lock. |
| Cancel | Hideout. Toast “Back at the hideout.” Marks chip rebound from snapshot only. Never abandon / A4. |
| Ready | `MatchAPI.bind_lobby_match` — `matchId` + `joinToken` → existing drop. |
| Mock | `MockMatchServer.create_lobby` / `join_lobby` / `cancel_lobby` / `get_lobby`. Editor default. |
| LIVE | `LiveMatchClient` posts the locked body. `404` → `lobby_unavailable`. F2 still toggles. |

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
