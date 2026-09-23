# Next exposure floor — hideout XP plate

Wood chip under the hideout XP plate. Copy comes from `operativeLevel` on `GET /shop/me` `you` (the plate already binds that card). The chip does not read `you.exposureFloor` and does not paint a live percent.

| Level | Chip |
| --- | --- |
| L1–4 | Exposure floor · L5 · 40% |
| L5–9 | Exposure floor · L10 · 30% |
| L10–14 | Exposure floor · L15 · 20% |
| L15+ | omitted |
| `operativeLevel` missing | omitted (the plate hides) |

`SMOKE · L5` stays on the same plate while the level is under 5. Practice XP stays Δ0. No match header, no new SKU, no IAP.

```bash
godot --headless --path . -s res://tools/headless_loop_test.gd
# HEADLESS_LOOP_OK
```

```bash
godot --path . --resolution 1280x720 -- --capture-xp-plate-floor-l4
godot --path . --resolution 1280x720 -- --capture-xp-plate-floor-l5
godot --path . --resolution 1280x720 -- --capture-xp-plate-floor-l10
godot --path . --resolution 1280x720 -- --capture-xp-plate-floor-l15
```

| Still | What |
| --- | --- |
| `artifacts/ux/xp_plate_floor_l4.png` | L4, `18 / 100`, `SMOKE · L5`, `Exposure floor · L5 · 40%` |
| `artifacts/ux/xp_plate_floor_l5.png` | L5, `0 / 100`, smoke tip gone, `Exposure floor · L10 · 30%` |
| `artifacts/ux/xp_plate_floor_l10.png` | L10, `64 / 100`, `Exposure floor · L15 · 20%` |
| `artifacts/ux/xp_plate_floor_l15.png` | L15, `0 / 100`, floor tip omitted |
