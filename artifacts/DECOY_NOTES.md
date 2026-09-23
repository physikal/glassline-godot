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

## L3 unlock

Slice mirrors SMOKE L5. LIVE tip `662dba7` on `https://glassline-api.vercel.app`. Exact `you.operativeLevel` and exact `you.decoyAvailable`. `decoyAvailable` is true only when `operativeLevel >= 3` and the charge remains. Below L3 the wire reads `decoyAvailable: false` and `decoyRemaining: 0` while the charge stays unspent. Reject reason is `reach operative L3`.

| Gate | Client |
| --- | --- |
| D1 | Chip lights only when exact `operativeLevel >= 3` and exact `decoyAvailable` is true |
| D2 | Below L3 the chip stays visible on the Soft P2 spent-wood plate, in the ability rail under ABILITY. Tap toasts `Reach operative L3` (toast only — not a sticky header or legend plate). Tooltip still reads `DECOY · L3` |
| D3 | `xp` is ignored. Practice does not level and practice Marks stay Δ0. An L3 snapshot stays unlocked in practice |
| D4 | Once unlocked, once/match, adjacent empty, miss+clear, and expiry are unchanged |
| D5 | No Marks, no IAP, no catalog SKU, no second charge. A locked tap does not spend the doll |

Fail closed: a charge with no exact `operativeLevel` stays locked and does not POST. Snake-case aliases and `decoyRemaining` alone do not unlock. A missing charge with no level stays the absent chip. Mock accounts start at L5 so the existing harness stays the unlocked path; `operative_level = 2` publishes `decoyAvailable` false and refuses with `reach operative L3`.

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
| Match HUD | Caramel **DECOY** chip in the ability rail under **ABILITY**, beside UAV and SMOKE. Tooltip *Plant a toy doll on a neighbor hex…* |
| Hex board | Own `DOLL` dashed cream/teal; enemy soft `BLIP` peach. Cleared on `decoyCleared` / expiry / match end |

## Stills

| Gate | File |
| --- | --- |
| D6 HUD | `artifacts/ux/decoy_action_hud.png` |
| D6 dashed doll | `artifacts/ux/decoy_dashed_blip.png` |
| Locked L2, tip visible | `artifacts/ux/decoy_chip_locked.png` |
| Unlocked L3 | `artifacts/ux/decoy_chip_unlocked.png` |
| Lock toast | `artifacts/ux/decoy_lock_toast.png` |

Capture (mock, `DISPLAY=:1`):

```
/tmp/godot --path . --resolution 1280x720 -- --capture-decoy-hud
/tmp/godot --path . --resolution 1280x720 -- --capture-decoy-blip
/tmp/godot --path . --resolution 1280x720 -- --capture-decoy-locked
/tmp/godot --path . --resolution 1280x720 -- --capture-decoy-unlocked
/tmp/godot --path . --resolution 1280x720 -- --capture-decoy-lock-toast
```

## Out

Multi-charge · damaging decoys · Marks/IAP buy · mil-sim smoke · Marks spend/grant · hit%/spot% buff. Hideout XP plate stays `SMOKE · L5` under L5. Practice XP stays Δ0.
