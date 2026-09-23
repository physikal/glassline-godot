# Hideout operative XP plate

Client base `80c3e94`. Field names from Coder `20c1b2a`. Soft P2 ShopYou is LIVE at tip `7fbd884`.

Wood chip on the hideout: server `operativeLevel`, an XP bar of `xp % 100` toward 100, and a muted `SMOKE · L5` tip while the level is under 5. L5+ drops the tip. No rank chrome. The match SMOKE chip is unchanged and still ignores `xp`.

## Sources

| Source | Role |
| --- | --- |
| `GET /shop/me` `you` | **Primary.** Hideout calls this on every refresh. `you.xp`, `you.operativeLevel`, `you.exposureFloor` |
| `POST /players` | Fallback only when that shop field is absent |
| Match / ended `you` | Fallback only when that shop field is absent |

A missing shop key does not invent a total, a level, a floor, or Marks, and does not wipe a fallback card. Snake-case aliases are ignored. The chip needs both `xp` and `operativeLevel`. One without the other hides the plate. The label is the server level, not `1 + floor(xp / 100)` filled in locally. Toward-next has no server field: progress `xp % 100`, remaining `100 - (xp % 100)`.

`you.smokeAvailable` stays on the match snapshot. It is not on ShopYou and the plate does not read it.

## Soft P2

Tip `7fbd884` is LIVE. `GET /shop/me` `you` carries `xp`, `operativeLevel`, and `exposureFloor`. A fresh player on `https://glassline-api.vercel.app` is `0` / `1` / `50`. ShopYou does not include `smokeAvailable`.

## Practice

Practice still does not add XP or Marks. The plate shows the account totals the server already had.

## Proof

```bash
godot --headless --path . -s res://tools/headless_loop_test.gd
# HEADLESS_LOOP_OK
```

```bash
godot --path . --resolution 1280x720 -- --capture-xp-plate-tip
godot --path . --resolution 1280x720 -- --capture-xp-plate-l5
godot --path . --resolution 1280x720 -- --capture-xp-plate-progress
```

| Still | What |
| --- | --- |
| `artifacts/ux/xp_plate_l4_tip.png` | L4, 18/100, tip `SMOKE · L5` |
| `artifacts/ux/xp_plate_l5.png` | L5, 0/100, no tip |
| `artifacts/ux/xp_plate_progress.png` | L2, 64/100, bar filled, tip still up |

## Out

Curve changes · `xpToNext` · Marks buy · IAP · SMOKE rule changes.
