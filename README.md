# Glassline (Hex Sniper) — client spike

Godot **4.3+** 2D / GDScript. Hideout → 9×7 drop → toy optic. **`MockMatchServer` is the default** for editor Play. Optional **`LiveMatchClient`** speaks the locked Hono HTTPS + SSE API.

Canon plates live in `assets/canon/`.

## Open in Godot

1. Install [Godot 4.3+](https://godotengine.org/download) (standard build, **not** .NET).
2. Import this folder (`project.godot`).
3. Press Play. Main scene: `scenes/lobby/hideout_lobby.tscn`.

Headless contract check (mock, no network):

```bash
godot --headless --path . -s res://tools/headless_loop_test.gd
godot --headless --path . -s res://tools/headless_coach_test.gd
```

Expect `HEADLESS_LOOP_OK` and `HEADLESS_COACH_OK`.

## Mock vs live

| Switch | Default | How |
| --- | --- | --- |
| Editor | **Mock** | Lobby **MOCK / LIVE** button (session override) |
| Project setting | `glassline/use_live_api=false` | `project.godot` `[glassline]` |
| Env | unset | `GLASSLINE_USE_LIVE_API=1` and optional `GLASSLINE_API_BASE` |
| Export | off | custom feature tag `use_live_api` on the preset |

Priority: lobby override → env → export feature → project setting.

Default live base: **`https://glassline-api.vercel.app`** (`glassline/api_base_url`, or `GLASSLINE_API_BASE`). Mock stays the editor default (`use_live_api=false`). Local clone still works at `http://127.0.0.1:8787`.

Scenes call **`MatchAPI`** only. That facade forwards to `MockMatchServer` or `LiveMatchClient`. The client never treats a local crosshair as hit/terrain truth.

## Point at the live API (GitHub)

Do **not** rename or push the API repo. Clone it **outside** this client, local Postgres required.

```bash
git clone https://github.com/physikal/glassline-api.git /tmp/glassline-api
cd /tmp/glassline-api
cp .env.example .env   # DATABASE_URL=postgresql://glassline:glassline@127.0.0.1:5432/glassline
pnpm install && pnpm migrate && pnpm start   # http://127.0.0.1:8787
```

Public LIVE (Neon): **`https://glassline-api.vercel.app`**. Click **LIVE** on the hideout, or:

```bash
GLASSLINE_USE_LIVE_API=1 godot --path .
GLASSLINE_API_BASE=https://glassline-api.vercel.app python3 tools/live_http_smoke.py
GLASSLINE_API_BASE=https://glassline-api.vercel.app python3 tools/live_jobs_smoke.py   # POST /jobs T1 + you.marks +10 once
GLASSLINE_API_BASE=https://glassline-api.vercel.app python3 tools/live_jobs_ladder_smoke.py  # J1–J4 T1/T2/T3 + clientJobId replay
GLASSLINE_API_BASE=https://glassline-api.vercel.app python3 tools/live_a2_smoke.py     # A2 reconnect: server snapshot wins
GLASSLINE_USE_LIVE_API=1 godot --headless --path . res://tools/live_loop_test.tscn
GLASSLINE_API_BASE=https://glassline-api.vercel.app python3 tools/live_shop_smoke.py   # S1–S3 Marks sink (POST /players + two kill wins)
GLASSLINE_API_BASE=https://glassline-api.vercel.app python3 tools/live_shop_sink2_smoke.py  # S2.1–S2.3 bandana ★100 (pending if catalog lags)
GLASSLINE_API_BASE=https://glassline-api.vercel.app python3 tools/live_shop_sink3_smoke.py  # S3.1–S3.3 poster ★150 (pending if catalog lags)
GLASSLINE_API_BASE=https://glassline-api.vercel.app python3 tools/live_shop_equip_smoke.py  # E1/E4 equip (pending if /shop/equip 404)
GLASSLINE_API_BASE=https://glassline-api.vercel.app python3 tools/live_decoy_smoke.py      # D1–D5 decoy LIVE_DECOY_OK
GLASSLINE_API_BASE=https://glassline-api.vercel.app python3 tools/live_high_ground_smoke.py  # H1–H6 HIGH GROUND; PENDING if flag missing
GLASSLINE_API_BASE=https://glassline-api.vercel.app python3 tools/live_rematch_smoke.py    # R1–R5 rematch; curl first (404 → PENDING)
GLASSLINE_API_BASE=https://glassline-api.vercel.app python3 tools/live_lobby_smoke.py      # P1–P5 private lobby LIVE; curl first (bare 404 → PENDING)
GLASSLINE_API_BASE=https://glassline-api.vercel.app python3 tools/live_queue_smoke.py      # Q1–Q5 Quick Match LIVE_QUEUE_OK (61s Q4 TTL)
GLASSLINE_USE_LIVE_API=1 godot --headless --path . res://tools/live_shop_test.tscn
```

Spike checklist: `artifacts/SPIKE_ACCEPTANCE.md`. Reconnect = `GET /matches/:id` then `ClientSession.apply_snapshot` (replace, no merge). Client never invents terrain tags or `hit`.

Realtime: prefer `GET /matches/:id/events` (SSE, Bearer). If that stream dies (common on Vercel after the first tick), `LiveMatchClient` falls back to polling `GET /matches/:id`. Local `8787` override: `GLASSLINE_API_BASE=http://127.0.0.1:8787`.

Live contract deltas vs the older mock draft: **no `start`** (both `select_hex` auto-activates), `end_turn.move` not `hex`, attack miss does **not** reveal terrain, `you.placed` is omitted (infer from `you.hex`). `LiveMatchClient` no-ops `start` when already `active` and sends both `hex` and `move` on end_turn.

`LiveMatchClient` expects:

| Method | Path | Body / notes |
| --- | --- | --- |
| GET | `/health` | `{ ok: true }` — lobby Play pings this first |
| POST | `/players` | → `{ playerId, token, marks }` — durable identity. **Keep `token`.** |
| POST | `/matches` | Bearer **player** token binds seat A (else anonymous mint at 0) |
| POST | `/matches/:id/join` | `{ token }` + optional Bearer player token → `{ playerId, seat, snapshot }` |
| POST | `/matches/:id/actions` | intent → `{ ok, snapshot, result }` (Bearer = **join token**) |
| POST | `/matches/:id/abandon` | mid-match leave + join Bearer, **no body** → same forfeit path as 30s silence (`endReason: forfeit`, Marks +12/0). `ready`/`waiting` → 409 `match_not_active`. Already `ended` → 409 `match_already_ended` (no second grant). |
| POST | `/matches/:id/rematch` | `{ accept: true\|false }` + **join-token** Bearer (player token fallback). `waiting` / `ready { matchId, joinToken, snapshot }` / `declined` / `expired`. Ended snap `rematch: { status, youAccepted, opponentAccepted, expiresAt, newMatchId? }`. Curl first; 404 → mock. Prefer LIVE smoke once 200. |
| POST | `/lobbies` | Bearer **player** → **201** `{ lobbyId: lob_…, code, snapshot }` status `waiting`. 6-char, no `0O1I`. TTL 10 min. |
| POST | `/lobbies/join` | `{ code }` + player Bearer → seat B; both seated → `ready { matchId, joinToken, snapshot }` |
| GET | `/lobbies/:id` | Host poll. Ready returns this seat’s `joinToken`. |
| POST | `/lobbies/:id/cancel` | Waiting → hideout, **no** forfeit Marks. After ready → 409 `lobby_already_started`. |
| POST | `/queue` | Bearer **player** → **200** `{ status: queued, queuedAt, timeoutSec: 60, expiresAt }` or `{ status: matched, matchId, joinToken, seat, snapshot }`. Re-POST refreshes `expiresAt`. **409** `already_in_match` / `in_lobby`. |
| GET | `/queue` | Bearer **player** → `idle` \| `queued` + `secondsLeft` \| `matched` \| `expired` (once, then idle). |
| DELETE | `/queue` | Waiting → hideout, **Marks Δ0**. Always `{ status: idle }`. Matched row stays. |
| GET | `/matches/:id` | caller-scoped snapshot (reconnect / dummy seat) |
| GET | `/matches/:id/events` | SSE `{ event: snapshot\|your_turn, snapshot }` — on drop, poll `GET /matches/:id` |
| POST | `/jobs` | `{ tier: 1\|2\|3, clientJobId? }` + Bearer player token reuses that `playerId`. Credit is job **end**, not this POST. |
| GET | `/shop` | `{ items: [{ id, name, price, kind }] }` — LIVE `skin_hideout_stub` ★50 + `skin_bandana_stub` ★100 + `decor_poster_stub` ★150 when Coder +1 SKU (catalog-only, no `you.marks`). Mock always has all three. |
| GET | `/shop/me` | Bearer **player** token → `{ you: { marks, equippedSkinId, equippedDecorId }, owned }`. Hideout binds this — never invents the ids. |
| POST | `/shop/buy` | `{ itemId, clientBuyId }` + Bearer **player** token → `{ ok, you: { marks, equippedSkinId, equippedDecorId }, purchaseId, item }`. **402** `insufficient_marks`. Last buy auto-equips the matching slot only. |
| POST | `/shop/equip` | `{ itemId }` or `{ itemId: null, slot?: "skin"\|"decor" }` + Bearer **player** token → `{ ok, you: { marks, equippedSkinId, equippedDecorId } }`. **403** `not_owned`. Decor never overwrites skin. Marks untouched. |
| Auth | | Durable `POST /players` Bearer on create / join / jobs / shop. Match actions / snapshot / SSE use the join token. Dummy seat B stays anonymous. |

`PLAY` still joins **both** seats (you = `a`, local dummy = `b`) against the same server so the offline dummy loop works on live HTTPS. Dummy actions use token `b`; the UI SSE stream uses token `a`.

## Scene map

| Scene | Path | Role |
| --- | --- | --- |
| Hideout | `scenes/lobby/hideout_lobby.tscn` | Canon room, ARMORY three rows, PLAY, **QUICK MATCH**, **INVITE** (private lobby), JOBS, Marks chip |
| Match | `scenes/match/match_screen.tscn` | 9×7 axial, dummy `select_hex`, START, Attack/Recon/UAV/DECOY, END TURN, first-hunt coach chips |
| Optic | `scenes/optic/optic_overlay.gd` | Zoom / wobble stub + FIRE |
| Types | `types/` | Snapshot, ActionIntent, ActionResult (`{ ok, snapshot, result }`) |
| Mock | `autoload/mock_match_server.gd` | Local secret positions |
| Live | `autoload/live_match_client.gd` | HTTPClient POST + SSE |
| Facade | `autoload/match_api.gd` | Routes mock vs live |

## Offline / live loop

1. PLAY → `POST /matches` + join `a` and `b`.
2. Click hex → `select_hex`. Dummy also `select_hex`. Re-drop until START.
3. START → `active`, `whoseTurn: a`, exposure 50.
4. ATTACK miss → optic FIRE → server `result.hit == false`. END TURN.
5. Dummy recon + end_turn (or watch SSE `your_turn`).
6. UAV once → `enemy.visibleHex`. END TURN. **DECOY** once → server plants a toy doll on an adjacent empty hex (`you.decoyHex`); rival sees `enemy.decoySoftHex`. Attack on that hex is `hit:false` + `decoyCleared`. Expires next own `end_turn`. No Marks / no hit% buff.
7. ATTACK that hex → `hit` / `kill`. End overlay reads server `payout` (`marks`, `marksDelta`, `reason`) — never local `marks +=`.
8. Ended PvP: **PLAY AGAIN** / **DECLINE**. Marks already settled. Both accept → new `matchId` + salt, drop again. Decline or 30s → hideout. Notes: `artifacts/REMATCH_NOTES.md`.

Hideout **QUICK MATCH** is 1-tap `POST /queue` (60s TTL, no bot fill). Cozy “Finding a rival…” wartable — cancel or timeout returns hideout with Marks Δ0. Pair hands off the same drop / rematch / A4 path as private lobby. LIVE `https://glassline-api.vercel.app` (Coder `queue.ts`). Notes: `QUICK_MATCH_NOTES.md`.

Hideout **INVITE** is the private lobby: **CREATE LOBBY** shows a chunky copy-able code; **JOIN** takes a 6-char code. Cancel/leave returns to the hideout (no A4 forfeit). Ready uses the existing drop. Notes: `artifacts/PRIVATE_LOBBY_NOTES.md`.

First live (or mock) PvP hunt can show **first-hunt coach** chips (Attack / Recon / Doll / Decoy) until **GOT IT**. Persist is local `user://glassline_coach.cfg`. SP jobs skip. Notes: `FIRST_HUNT_COACH_NOTES.md`.

Hideout **JOBS** opens three SP rows (T1 ★10 / T2 ★15 / T3 ★20). START posts `POST /jobs` `{ tier, clientJobId }` on LIVE (mock uses the same shape) then the board. Marks chip binds snapshot `you.marks` only. Ability chrome is labeled **UAV** and still posts `{ type: "uav" }`. **DECOY** sits beside it and posts `{ type: "decoy" }` (mock + LIVE D1–D5). Ended PvP offers **PLAY AGAIN** / **DECLINE** — Marks already settled; both accept joins a new `matchId`. Earn table: `artifacts/MARKS_SP_NOTES.md`. Decoy notes: `artifacts/DECOY_NOTES.md`. Rematch: `artifacts/REMATCH_NOTES.md`. Ladder gates: `artifacts/SP_JOB_LADDER_NOTES.md`. Hideout **ARMORY** is three chrome-only Marks sinks (`skin_hideout_stub` ★50 + `skin_bandana_stub` ★100 + `decor_poster_stub` ★150, same `get_shop` / `buy_shop`, no combat / no IAP): `artifacts/MARKS_SINK_NOTES.md` · `artifacts/MARKS_SINK2_NOTES.md` · `artifacts/MARKS_SINK3_NOTES.md`. Owned rows **EQUIP / EQUIPPED** bind hideout + exposure doll to snapshot `you.equippedSkinId`. Poster binds `you.equippedDecorId` and can hang while a skin is worn. Notes: `artifacts/EQUIP_CHROME_NOTES.md`.

## Layout

```
autoload/     ClientSession, MockMatchServer, LiveMatchClient, MatchAPI
types/        contract-facing classes
docs/         API_CONTRACT.md (locked Notion)
assets/canon/ four plates
tools/        headless_loop_test.gd · live_decoy_smoke.py
```

No IAP, Steam, ranked, part tree, 3D, UDP, or NGO.
