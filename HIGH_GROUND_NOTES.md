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
- Base hit chance when the target occupies the hex: **1.0**. Empty hex: **0**. HIGH GROUND is additive on that base.
- Client chrome never computes the bonus. Missing flag → muted / false.

## Gates

| Gate | Mock | LIVE | Notes |
| --- | --- | --- | --- |
| **H1** HARD attacker +10% | **PASS** | **HOLD** | Mock: `you.highGroundActive` true. Miss reports `highGroundApplied` + `hitChance` 0.10. Occupy-hex kill still 1.0 (clamp). LIVE GET omits the flag (`LIVE_HIGH_GROUND_PENDING`). |
| **H2** OPEN / BRUSH / FoW +0 | **PASS** | **HOLD** | Flag false. Miss `highGroundApplied` false, `hitChance` 0. Omitted flag stays false. |
| **H3** chip snapshot-only | **PASS** | n/a | Lit reads **+10%**. Muted does not. Missing flag never invents from local HARD terrain. |
| **H4** guns / Decoy / Marks blind | **PASS** | **HOLD** | Miss on HARD does not change Marks. UAV / Decoy charges untouched. No gun field on attack. |
| **H5** defender ignored | **PASS** | **HOLD** | A on HARD / B on OPEN → A lit. A on BRUSH / B on HARD → A muted. |
| **H6** attack intent unchanged | **PASS** | **HOLD** | `{ type: "attack", hex }` only. No `highGround` / `hitChance` on the intent. |

Headless: `godot --headless --path . -s res://tools/headless_loop_test.gd` → `HEADLESS_LOOP_OK`.

LIVE: `python3 tools/live_high_ground_smoke.py`. Hold until Coder ships `you.highGroundActive` (bare missing field → `LIVE_HIGH_GROUND_PENDING`). Mock stills are enough to merge chrome.

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
