# Exposure gear floor — client bind

Server owns `operativeLevel` and the percent. Snapshot field: `you.exposureFloor` (`50` / `40` / `30` / `20`). The client **reads** it. It never maps a level to a percent, never POSTs `exposureFloor`, and never treats cosmetics or Marks as a floor change.

`end_turn.exposurePct` stays the next-turn intent (the slider). The doll’s label is the floor, not that intent.

## Fail-closed

| Payload | Doll / band |
| --- | --- |
| `you.exposureFloor` `50` `40` `30` `20` | That percent |
| Field missing (API not LIVE yet) | **50** |
| `0`, or any other number | **50** (never show 0, never invent a lower step) |
| `operativeLevel` only | **50** |

Hideout self uses the same reader when `exposureFloor` is already on the player / shop payload (`exposureFloor`, `you.exposureFloor`, or `player.exposureFloor`). A shop payload that omits the field displays **50**.

## Gates

| ID | Rule | Result |
| --- | --- | --- |
| **E1** | Start 50%. Never 0 | **PASS mock** |
| **E2** | Steps 50→40→30→20 come from the server field | **PASS mock** (step still stamps the mock field; client does not compute it) |
| **E3** | Doll % = live floor. Recon/Attack keep their existing bands | **PASS mock** |
| **E4** | Cosmetics / Marks chrome never touch the floor | **PASS mock** |
| **E5** | No IAP. No client-authored % | **PASS mock** |

Recon/Attack **result** odds are unchanged (`RECON_BASE` 0.35, occupy `BASE_HIT` 0.90). They did not hardcode a 50% chance band. The end-turn slider is the exposure band for the next window: its **minimum** is `you.exposureFloor` (fail-closed 50), so the intent cannot drop under the floor or to 0.

## Soft tip

First time the displayed floor drops below the prior reading, a muted chip:

> Gear tightened — harder to spot

Local ConfigFile on the coach store (`exposureFloorTipSeen`). **GOT IT** / **X** dismisses forever. Chip body ignores the mouse. Hideout **RESET TIPS** clears it. No API.

## Smoke

```bash
godot --headless --path . -s res://tools/headless_loop_test.gd
# HEADLESS_LOOP_OK  (_exposure_floor_case)
```

Stills (mock, 1280×720). The 40% and tip stills set the mock server field because LIVE does not send `you.exposureFloor` yet.

```bash
/tmp/godot --path . --resolution 1280x720 -- --capture-exposure-floor-50
/tmp/godot --path . --resolution 1280x720 -- --capture-exposure-floor-step
/tmp/godot --path . --resolution 1280x720 -- --capture-exposure-floor-tip
```

| Still | What |
| --- | --- |
| `artifacts/ux/exposure_floor_50.png` | Doll **Exposure 50%** |
| `artifacts/ux/exposure_floor_40.png` | Doll **Exposure 40%** (server field) |
| `artifacts/ux/exposure_floor_tip.png` | Same drop, one-shot tip |

## Out

Client-side operative level curve · IAP · mil-sim kit art · writing `exposureFloor` · changing Recon/Attack odds · forfeit-overlay z-order (already on main, untouched).
