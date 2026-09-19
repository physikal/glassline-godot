# Ability #2 — DECOY (D1–D6)

Slice ticket: [🎭 Ability DECOY](https://app.notion.com/p/3e04dabdb33981b19510eaeaf9e92133)
Arch stamp 2026-09-19. Client half on `main` after #16.

**Hard:** server-auth · no Marks/IAP · no hit%/spot% buff · no mil-sim smoke.

## Contract

| Piece | Choice |
| --- | --- |
| Action | `{ type: "decoy" }` — **no hex arg**; server picks |
| Placement | First in-bounds axial neighbor of the caster that is not either secret hex (or the other doll). None legal → `decoy_no_hex` |
| Once/match | `you.decoyAvailable` like UAV — false after use |
| Turn | Consumes the action slot; required `end_turn` |
| Visibility | Owner: `you.decoyHex`. Enemy: `decoySoftHex` **always** while live (not real Hot) |
| Attack | Target == decoy → `hit: false`, `decoyCleared: true`. Real kill path unchanged |
| Recon | Sector may soft-mark the doll (`decoySpotted`) without promoting it to `visibleHex` |
| Expiry | Attack-clear · caster’s **next** own `end_turn` (the planting `end_turn` keeps it live) · match end |
| Economy | **No** Marks grant/spend. `RECON_BASE` 0.35 / PvP ★25 untouched |

## LIVE curl (2026-09-19)

Coder shipped `bec68abe` (`{ type: "decoy" }`, once/seat). Public `https://glassline-api.vercel.app` after both drops:

```
POST /matches/:id/actions  { "type": "decoy" }
HTTP 200  { ok: true, result: { type: "decoy", hex: { q: 3, r: 2 } } }
```

A at (2,2) → server pick `(3,2)` (locked neighbor table). Snapshot:

- `you.decoyAvailable: false`, `you.decoyRemaining: 0`, `you.decoyHex: {q:3,r:2}`
- `enemy.decoySoftHex` on the other seat while live
- `phase: await_end_turn` · UAV charge untouched · no Marks on the result

Mid-deploy join briefly 500 (`PostgresError: cached plan must not change result type` after `match_players` gained decoy columns). Recycle → 200.

Coder cleared join/actions (`prepare: false`). Re-smoke after LIVE CLEAR → **`LIVE_DECOY_OK`**.

Evidence (`m_05991e267e994d688b6991977111b430`): A(2,2) → `result.hex` / `you.decoyHex` `{q:3,r:2}`; B `enemy.decoySoftHex` `{q:3,r:2}` with `visibleHex` null; B attack that hex → `hit:false` `kill:false` `decoyCleared:true`; both hexes then null.

`python3 tools/live_decoy_smoke.py` (`artifacts/live_decoy_smoke.txt`).

## Gates

| Gate | Mock | LIVE | Notes |
| --- | --- | --- | --- |
| **D1** once + full turn | **PASS** | **PASS** | First decoy → `await_end_turn`. Second refused. Intent has no hex. |
| **D2** adjacent empty | **PASS** | **PASS** | A at (2,2) plants (3,2) — LIVE `DECOY_DIRS` / contract neighbor table. Enemy gets `decoySoftHex` while live. Examples (0,0)/(8,6)→(1,0) and (0,0)/(1,0)→(0,1). |
| **D3** Attack miss+clear | **PASS** | **PASS** | B attacks planted hex → `hit:false`, `kill:false`, `decoyCleared:true`. Both views clear. Match stays active. |
| **D4** expires next own end_turn | **PASS** | **PASS** | Planting `end_turn` keeps the doll. Next own action window still shows it. Next own `end_turn` clears owner + enemy soft blip. |
| **D5** no economy / buff | **PASS** | **PASS** | Decoy / decoy-miss / expiry do not change Marks. UAV charge and exposure 50 stay. `RECON_BASE` 0.35, PvP kill ★25. Real hex still kills. |
| **D6** dashed toy doll UX | **PASS mock** | n/a | HUD **DECOY** (slot `TOY DOLL`) beside Attack / Recon / UAV. Enabled when `decoyAvailable`, **DECOY SPENT** when used. Cozy stuffed-doll blip + dashed ring. No mil-sim smoke. |

Headless: `godot --headless --path . -s res://tools/headless_loop_test.gd` → `HEADLESS_LOOP_OK`.

## Client map

| Surface | Behavior |
| --- | --- |
| `ActionIntent.decoy()` | `{ type: "decoy" }` |
| `Snapshot.decoy_available()` / `you_decoy_hex()` / `enemy_decoy_soft_hex()` | Read snapshot only; null on `ended` |
| `MockMatchServer._act_decoy` | Place, spend, `await_end_turn` |
| `LiveMatchClient.apply_action` | POSTs the dict; poll fp includes decoy hexes |
| Match HUD | Caramel **DECOY** button, tooltip *Plant a toy doll on a neighbor hex…* |
| Hex board | Own `DOLL` dashed cream/teal; enemy soft `BLIP` peach. Cleared on `decoyCleared` / expiry / match end |

## Stills

| Gate | File |
| --- | --- |
| D6 HUD | `artifacts/ux/decoy_action_hud.png` |
| D6 dashed doll | `artifacts/ux/decoy_dashed_blip.png` |

Capture (mock, `DISPLAY=:1`):

```
/tmp/godot --path . --resolution 1280x720 -- --capture-decoy-hud
/tmp/godot --path . --resolution 1280x720 -- --capture-decoy-blip
```

## Out

Multi-charge · damaging decoys · shop unlock · mil-sim smoke · Marks spend/grant · hit%/spot% buff.
