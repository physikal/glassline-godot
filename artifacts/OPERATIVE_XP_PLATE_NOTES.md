# Hideout operative XP plate

Client base `80c3e94`. Coder field tip `20c1b2a`.

Wood chip on the hideout: server `operativeLevel`, an XP bar toward the next 100, and a muted `SMOKE · L5` tip while the level is under 5. L5+ drops the tip. No rank chrome. The match SMOKE chip is unchanged and still ignores `xp`.

## Sources

| Source | When |
| --- | --- |
| `POST /players` | `ClientSession.bind_player` — exact `xp`, `operativeLevel`, `exposureFloor` |
| Match / ended `you` | `apply_snapshot` — same keys on `you` |
| `GET /shop/me` ShopYou | Hideout refresh **prefers** these when the keys are present |

A missing key does not invent a total, a level, or Marks, and does not wipe a card already bound. Snake-case aliases are ignored. Level on the chip is the server `operativeLevel`, not `1 + floor(xp / 100)` computed in place of a missing field. That formula is the server curve only. Toward-next has no server field: progress `xp % 100`, remaining `100 - (xp % 100)`.

`you.smokeAvailable` stays on the match snapshot. It is not copied onto ShopYou and the plate does not read it.

## Soft P2 / ShopYou

The slice called ShopYou pending. Probed `https://glassline-api.vercel.app` on 2026-09-23: `GET /shop/me` `you` already includes `xp`, `operativeLevel`, and `exposureFloor` (fresh player `0` / `1` / `50`) and does **not** include `smokeAvailable`. `POST /players` returns the same three fields at the top level. A practice snapshot `you` returns them plus the match charge. Hideout refresh therefore prefers ShopYou today. If a payload omits the keys, the client keeps the last players or match card.

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
