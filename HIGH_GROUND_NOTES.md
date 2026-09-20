# HIGH GROUND live (H1–H6)

Slice ticket: [⛰️ HIGH GROUND live](https://app.notion.com/p/3e14dabdb33981e69a7ed7c7ebf5e2aa)
Arch stamp 2026-09-20. Client chrome on `you.highGroundActive`.

**Hard:** attacker HARD → server hit **+0.10 absolute** (one stack, clamp 0–1) · chip truthful · zero Marks / guns / Decoy.

## Spine

| Piece | Choice |
| --- | --- |
| Bonus | Attacker cell `HARD` → hit chance **+0.10** absolute, one stack, clamp `[0, 1]` |
| Off | `OPEN` / `BRUSH` / unknown-to-self → **+0** |
| Who | **Attacker terrain only** (H5) — defender hex ignored |
| Guns / Decoy / Marks | Blind — no interaction |
| Chip | Binds `you.highGroundActive` — never invent from a local hex |
| Attack intent | Unchanged `{ type: "attack", hex }` |

## Contract

- Snapshot: `you.highGroundActive: boolean` (true iff your revealed cell is HARD).
- Attack result (preferred): `highGroundApplied: boolean` + final `hitChance`.
- Base hit chance when the target occupies the hex: **0.90**. Empty / decoy: **0**. HARD adds **+0.10** (clamp 0–1).
- Client chrome never computes the bonus. Missing flag → muted / false.

## Gates

| Gate | Mock | LIVE | Notes |
| --- | --- | --- | --- |
| **H1** HARD attacker +10% | **PASS** | **PASS** | Flag true on HARD. Empty miss `applied` false / `hitChance` 0. Occupy `applied` true / `hitChance` **1.0**. LIVE `m_56e82595873f4669a8915bbf8251c20c`. |
| **H2** OPEN / BRUSH / FoW +0 | **PASS** | **PASS** | Flag false. Occupy `applied` false / `hitChance` **0.90** (LIVE `BASE_HIT`). `m_96456040e499417ebec14f0f58a3313a`. |
| **H3** chip snapshot-only | **PASS** | n/a | Lit reads **+10%**. Muted does not. Missing flag never invents from local HARD terrain. |
| **H4** guns / Decoy / Marks blind | **PASS** | **PASS** | Miss Marks Δ0. Decoy charge untouched. HARD kill table **+25** (no extra). |
| **H5** defender ignored | **PASS** | **PASS** | A HARD / B brush → A lit. A OPEN / defender ignored → A muted. |
| **H6** attack intent unchanged | **PASS** | **PASS** | `{ type: "attack", hex }` only. No `highGround` on the intent. |

Headless: `godot --headless --path . -s res://tools/headless_loop_test.gd` → `HEADLESS_LOOP_OK`.

LIVE: `python3 tools/live_high_ground_smoke.py` → **`LIVE_HIGH_GROUND_OK`** (Coder `4720879`, occupy `BASE_HIT` 0.90). Missing flag still prints `LIVE_HIGH_GROUND_PENDING`.

## Client map

| Surface | Behavior |
| --- | --- |
| `Snapshot.you_high_ground_active()` | Reads `you.highGroundActive` only. Missing → false |
| `Chrome.high_ground_chip` / `paint_high_ground_chip` | Lit gold + “+10%” / muted plate, no +10% |
| `MockMatchServer` | Computes from revealed own HARD. `test_high_ground_active` forces stills |
| `LiveMatchClient` poll fp | Includes `you.highGroundActive` so SSE/poll refresh lights the chip |
| Match HUD | Same chunky plate chip over the 4th painted key. Not an action button |

## Stills

| Gate | File |
| --- | --- |
| H1 / H3 lit | `artifacts/ux/high_ground_lit_hard.png` |
| H2 / H3 muted | `artifacts/ux/high_ground_muted_open.png` |

Capture (mock, `DISPLAY=:1`):

```
/tmp/godot --path . --resolution 1280x720 -- --capture-high-ground-lit
/tmp/godot --path . --resolution 1280x720 -- --capture-high-ground-muted
```

Mock toggle `test_high_ground_active` drives those stills. Display truth is still the snapshot flag.

## Out

Elevation layers · stacking · paid high-ground · gun accuracy · defender mods · client-invented bonus.
