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
```

Expect `HEADLESS_LOOP_OK`.

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
GLASSLINE_API_BASE=https://glassline-api.vercel.app python3 tools/live_a2_smoke.py     # A2 reconnect: server snapshot wins
GLASSLINE_USE_LIVE_API=1 godot --headless --path . res://tools/live_loop_test.tscn
GLASSLINE_API_BASE=https://glassline-api.vercel.app python3 tools/live_shop_smoke.py   # S1–S3 Marks sink
GLASSLINE_USE_LIVE_API=1 godot --headless --path . res://tools/live_shop_test.tscn
```

Spike checklist: `artifacts/SPIKE_ACCEPTANCE.md`. Reconnect = `GET /matches/:id` then `ClientSession.apply_snapshot` (replace, no merge). Client never invents terrain tags or `hit`.

Realtime: prefer `GET /matches/:id/events` (SSE, Bearer). If that stream dies (common on Vercel after the first tick), `LiveMatchClient` falls back to polling `GET /matches/:id`. Local `8787` override: `GLASSLINE_API_BASE=http://127.0.0.1:8787`.

Live contract deltas vs the older mock draft: **no `start`** (both `select_hex` auto-activates), `end_turn.move` not `hex`, attack miss does **not** reveal terrain, `you.placed` is omitted (infer from `you.hex`). `LiveMatchClient` no-ops `start` when already `active` and sends both `hex` and `move` on end_turn.

`LiveMatchClient` expects:

| Method | Path | Body / notes |
| --- | --- | --- |
| GET | `/health` | `{ ok: true }` — lobby Play pings this first |
| POST | `/matches` | → `{ matchId, joinTokens: { a, b } }` |
| POST | `/matches/:id/join` | `{ token }` → `{ playerId, seat, snapshot }` |
| POST | `/matches/:id/actions` | intent → `{ ok, snapshot, result }` |
| GET | `/matches/:id` | caller-scoped snapshot (reconnect / dummy seat) |
| GET | `/matches/:id/events` | SSE `{ event: snapshot\|your_turn, snapshot }` — on drop, poll `GET /matches/:id` |
| GET | `/shop` | `{ items: [{ id, name, price, kind }] }` — LIVE catalog `skin_hideout_stub` ★50 (no `you.marks`) |
| POST | `/shop/buy` | `{ itemId, clientBuyId }` + Bearer joinToken → `{ ok, you.marks, purchaseId, item }`. **402** `insufficient_marks`. Idempotent on `clientBuyId` |
| Auth | | `Authorization: Bearer <join token>` |

`PLAY` still joins **both** seats (you = `a`, local dummy = `b`) against the same server so the offline dummy loop works on live HTTPS. Dummy actions use token `b`; the UI SSE stream uses token `a`.

## Scene map

| Scene | Path | Role |
| --- | --- | --- |
| Hideout | `scenes/lobby/hideout_lobby.tscn` | Canon room, ARMORY shop row (ghillie recolor ★50), PLAY, JOBS, Marks chip |
| Match | `scenes/match/match_screen.tscn` | 9×7 axial, dummy `select_hex`, START, Attack/Recon/UAV ability, END TURN |
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
6. UAV once → `enemy.visibleHex`. END TURN.
7. ATTACK that hex → `hit` / `kill`. End overlay reads server `payout` (`marks`, `marksDelta`, `reason`) — never local `marks +=`.

Hideout **JOBS → START JOB** calls `POST /jobs` `{ tier: 1|2|3 }` on LIVE (mock uses the same shape). Ability chrome is labeled **UAV** and still posts `{ type: "uav" }`. Balance is `you.marks`. Earn table + field names: `artifacts/MARKS_SP_NOTES.md`. Hideout **ARMORY** is the Marks sink stub (`itemId` **`skin_hideout_stub`**, **★50**, `LiveMatchClient.get_shop` / `buy_shop`, no combat / no IAP): `artifacts/MARKS_SINK_NOTES.md`.

## Layout

```
autoload/     ClientSession, MockMatchServer, LiveMatchClient, MatchAPI
types/        contract-facing classes
docs/         API_CONTRACT.md (locked Notion)
assets/canon/ four plates
tools/        headless_loop_test.gd
```

No IAP, Steam, ranked, part tree, 3D, UDP, or NGO.
