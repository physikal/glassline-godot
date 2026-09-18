# Glassline (Hex Sniper) — client spike

Godot **4.3+** 2D / GDScript offline slice. The hideout, 9×7 axial drop, and toy optic talk to **`MockMatchServer`** using the locked v0 HTTPS+SSE shapes so a live swap does not rewrite types.

Canon plates (chunk language, not mil-sim) live in `assets/canon/`.

## Open in Godot

1. Install [Godot 4.3 or newer](https://godotengine.org/download) (standard build, **not** .NET / C#).
2. Import this folder (`project.godot`).
3. Press Play. Main scene: `scenes/lobby/hideout_lobby.tscn`.

Headless contract check (same binary):

```bash
godot --headless --path . -s res://tools/headless_loop_test.gd
```

Expect `HEADLESS_LOOP_OK`.

## Scene map

| Scene | Path | Role |
| --- | --- | --- |
| Hideout lobby | `scenes/lobby/hideout_lobby.tscn` | Operative room (canon plates), **PLAY** creates a mock match and joins both seats |
| Match / drop | `scenes/match/match_screen.tscn` | 9×7 axial board, dummy `select_hex`, **START**, Attack / Recon / UAV, required **END TURN** |
| Toy optic | `scenes/optic/optic_overlay.gd` | Zoom / wobble stub + **FIRE** — hit/miss is never local |
| Types | `types/` | `Snapshot`, `ActionIntent`, `ActionResult`, `HexCoord`, `Contract` |
| Mock server | `autoload/mock_match_server.gd` | Secret positions, terrain hash, recon/UAV/kill, turnCap 16 |

`SUIT` on the lobby swaps `lobby-canon.jpg` / `lobby-ghillie.jpg`. Loadout and Jobs are stubs.

## Offline loop (this slice)

1. **PLAY** → `create_match` + join token `a` (you) and `b` (dummy).
2. Click a hex → `select_hex`. Dummy also `select_hex` (re-drop yours until **START**).
3. **START** → `active`, `whoseTurn: a`, `exposurePct: 50`.
4. **ATTACK** a wrong hex → optic **FIRE** → server `hit: false` (no invented Hot). **END TURN** (exposure slider default 50, optional adjacent move).
5. Dummy takes recon + end_turn.
6. **UAV** (once) writes `enemy.visibleHex` on *your* snapshot. End turn, dummy cycles.
7. **ATTACK** the revealed hex → server `hit: true`, `winner: a`, **Marks +1**.

All buttons call `MockMatchServer.apply_action`. The client never treats a local crosshair as truth.

## MockMatchServer → future live API

| Mock method | Live |
| --- | --- |
| `create_match()` | `POST /matches` → `{ matchId, joinTokens }` |
| `join(match_id, token)` | `POST /matches/:id/join` `{ token }` → `{ playerId, seat, snapshot }` |
| `apply_action` / `post_action` | `POST /matches/:id/actions` + `ActionResult { ok, error, snapshot, event }` |
| `get_snapshot` | caller-scoped GET / reconnect body |
| `match_event(player_id, event, snapshot)` | `GET /matches/:id/events` SSE `{ event: snapshot\|your_turn, snapshot }` |

Payload keys stay camelCase (`matchId`, `exposurePct`, `visibleHex`, …). Swap the autoload for an HTTPS client that returns the same dictionaries; scenes keep using `ActionIntent.*` and `Snapshot.from_dict`.

Rules the mock already enforces:

- Terrain `open|brush|hard` from `hash(match_id,q,r,salt)` on first select (drop / attack / recon sector / UAV hex).
- Attack hits **iff** target hex == enemy secret. Miss does not set intel.
- Recon sector = center + 6 neighbors; find chance 35%, +25% if `movedLastTurn`.
- UAV once per seat (`uavRemaining` 0\|1).
- `turnCap` 16 total end_turns → `winner: draw`.
- Kill → winner Marks +1.

## Layout

```
autoload/     MockMatchServer, ClientSession
types/        contract-facing classes
scenes/       lobby, match, optic
assets/canon/ lobby-canon.jpg, lobby-ghillie.jpg, hex-map.jpg, optic-attack.jpg
docs/         API_CONTRACT_LOCKED.md
tools/        headless_loop_test.gd
```

No IAP, Steam, ranked, part tree, 3D, UDP, or NGO in this slice.
