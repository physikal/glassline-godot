# Match-end XP line

Client chrome on the end wood plate, under the Marks Δ. No API change. No `xpGranted`. No XP bar — the hideout plate still owns `xp % 100`.

## Line

| Case | Plate |
| --- | --- |
| PvP grant | `+N XP  ·  L#` |
| Level ticked this match | `+N XP  ·  L# unlocked` |
| Practice | line omitted (Δ0), even if `you.xp` / `xpDelta` are present |
| Loss, standoff, leaver, SP job | line omitted (Δ0) |
| Missing ended `you.xp` or `you.operativeLevel` | line omitted |

The level number is exact `you.operativeLevel`. It is not `1 + floor(xp / 100)`.

## Where N comes from

1. **Server delta, if the ended payload already has one.** Exact `xpDelta` on the bags Marks already reads, first hit wins: `payout`, `result`, `lastAction`, the snapshot, then `you`. A present `0` stays `0` and does not fall through. `xpGranted` and `xp_delta` are ignored.
2. **Otherwise the same outcome fields as the Marks earn paint** (`endReason` / forfeit, `winner`, `you.seat`). Live grant from `xpForPvpOutcome`: PvP kill win **+100**, forfeit win **+50**, anything else **0**. This is not `ended.xp − session.xp`.

`unlocked` uses the ended absolute `you.xp` only as a boundary check: previous total `xp − N`, and only when `xp ≥ N`, the curve level rises, and `you.operativeLevel` equals that new curve level. A server level that does not match the curve is still the label, without `unlocked`.

Marks Δ stays the earn table (`+32` / `+15` / `0` …) plus `★you.marks`. This slice does not invent Marks.

## Proof

```bash
godot --headless --path . -s res://tools/headless_loop_test.gd
# HEADLESS_LOOP_OK
```

```bash
godot --path . --resolution 1280x720 -- --capture-end-xp
godot --path . --resolution 1280x720 -- --capture-end-xp-level
godot --path . --resolution 1280x720 -- --capture-end-xp-practice
```

| Still | What |
| --- | --- |
| `artifacts/ux/end_xp_pvp.png` | PvP forfeit win, `+50 XP  ·  L1`, no unlock |
| `artifacts/ux/end_xp_level.png` | PvP kill win, `+100 XP  ·  L2 unlocked` |
| `artifacts/ux/end_xp_practice.png` | Practice clear, Marks Δ0, no XP line |

## Out

Combat · Marks table · hideout plate · `xpGranted` · mil-sim art.
