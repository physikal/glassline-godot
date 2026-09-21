# BRUSH cover (B1–B6)

Slice ticket: [🌿 BRUSH cover](https://app.notion.com/p/3e14dabdb339811aad8ffef8956ba6f6)
Arch stamp 2026-09-20. Result chrome only — **no IN COVER chip**.

**Hard:** target BRUSH → server hit **−0.10 absolute** (one stack, clamp 0–1) · stacks with HIGH GROUND · zero Marks / guns / Decoy.

## Spine

| Piece | Choice |
| --- | --- |
| Penalty | Target cell `BRUSH` → hit chance **−0.10** absolute, one stack, clamp `[0, 1]` |
| Off | Target `OPEN` / `HARD` / unknown-to-self (FoW) → **−0** |
| Who | **Target terrain only** on an occupy roll |
| Stack | HARD→BRUSH **0.90** · OPEN→BRUSH **0.80** · HARD→OPEN/HARD **1.0** · OPEN→OPEN/HARD **0.90** |
| Guns / Decoy / Marks | Blind — no interaction |
| Chip | **None this slice** — no IN COVER chrome |
| Attack intent | Unchanged `{ type: "attack", hex }` |

## Contract

- Attack result: `coverApplied: boolean` + existing `highGroundApplied` / `hitChance`.
- Base hit chance when the target occupies the hex: **0.90**. Empty / decoy: **0**.
- Target on BRUSH subtracts **0.10**. Attacker HARD still adds **0.10**. Clamp `[0, 1]`.
- Client chrome never computes the penalty. Missing field → omit from the toast.

## Gates

| Gate | Mock | LIVE | Notes |
| --- | --- | --- | --- |
| **B1** target BRUSH −10% | **PASS** | pending Coder | Occupy `coverApplied` true / `hitChance` **0.80** from OPEN. |
| **B2** OPEN / HARD / FoW +0 | **PASS** | pending Coder | Occupy off-brush `coverApplied` false / **0.90**. Omitted field stays null. |
| **B3** stacks with HIGH GROUND | **PASS** | pending Coder | HARD→BRUSH **0.90**. OPEN→BRUSH **0.80**. |
| **B4** wrong hex / decoy miss | **PASS** | pending Coder | Empty + doll: `hit` false, `coverApplied` false, `hitChance` **0**. |
| **B5** no IN COVER chip | **PASS** | n/a | Toast reads server fields. Plate copy, not mil-sim. |
| **B6** guns / Marks blind | **PASS** | pending Coder | Railframe / Crescent do not change chance. Kill table **+25**. |

Headless: `godot --headless --path . -s res://tools/headless_loop_test.gd` → `HEADLESS_LOOP_OK`.

LIVE: `python3 tools/live_brush_cover_smoke.py` → **`LIVE_BRUSH_COVER_OK`** once Coder ships `coverApplied`. Missing field prints `LIVE_BRUSH_COVER_PENDING`.

## Client map

| Surface | Behavior |
| --- | --- |
| `Snapshot.last_cover_applied()` | Reads `lastAction.coverApplied` only. Missing → null |
| `Chrome.describe_attack_result` | Plate toast: chance + cover / high-ground when the server named them |
| `MockMatchServer` | Occupy formula `clamp(0.90 + HARD?0.10 − BRUSH?0.10, 0, 1)` |
| `LiveMatchClient` poll fp | Includes `coverApplied` / `hitChance` so the toast refreshes |
| Match HUD | Result line only. HIGH GROUND chip unchanged. No IN COVER chip |

## Stills

| Gate | File |
| --- | --- |
| B1 / B5 toast | `artifacts/ux/brush_cover_toast.png` |

Capture (mock, `DISPLAY=:1`):

```
/tmp/godot --path . --resolution 1280x720 -- --capture-brush-cover-toast
```

Toast binds `lastAction.coverApplied` / `hitChance` only.

## Out

IN COVER chip · stacking beyond ±0.10 · paid cover · client-side math.
