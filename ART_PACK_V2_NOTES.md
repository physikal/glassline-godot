# Art pack v2 — canon-faithful reshoot

PR #30 failed Josh / UX taste. This pack **does not revive that dialect**.
Rifles, hex stamps, and the exposure doll are **cropped from Josh-locked plates**
in `assets/canon/` (`lobby-canon.jpg`, `lobby-ghillie.jpg`, `hex-map.jpg`,
`optic-attack.jpg`). No rectangle guns. No circle/rect legend icons on the board.

Chrome only. **No** ballistics, Marks economy, combat, API, or gun SKUs.
FAR / MID / NEAR stay display-only. Leave this PR open for UX re-taste —
**do not squash-merge**.

## Punch list

| # | Fail | v2 fix |
| --- | --- | --- |
| 1 | Rifle rack was abstract color bars | Olive **Fieldbolt** / tan **Railframe** / teal **Crescent** cropped from the hideout wall. Real sniper silhouettes at thumbnail. |
| 2 | Hands + optic ≠ rack | One Fieldbolt family: plate-held bolt stays; Attack sits on `optic-attack.jpg`. |
| 3 | Hex used flat circle/rect icons | Board faces are **Sprite2D hex-map tiles** (sand / painted brush clumps / rock piles / `?`). Ban `draw_texture_rect` 26px white squares. |
| 4 | Mixed fidelity (smooth face / mushy blocks) | Same warm painted toy-spy crop language everywhere. |
| 5 | Doll was a blocky avatar | Paper-doll is the hideout operative crop (teal / ghillie). |
| 6 | Gold / gem on stills | Marks ★ only. Baked gold/gem wood-stamped off the plate. |
| P2 | FAR/MID/NEAR | Display-only hotspots on the optic plate. No new loops. |

## Taste-gate stills (`artifacts/ux/`)

1. `01_hideout_idle_armory.png`
2. `02_dynamic_rack.png` — owned starter Fieldbolt + equipped underline · locked Railframe / Crescent
3. `03_hex_open_brush_hard_unknown.png`
4. `04_operative_exposure_doll.png`
5. `05_attack_optic_fieldbolt.png`
6. `06_ui_chips_marks_coach_queue_end.png` — Marks ★ / coach / queue / end

Side-by-side vs canon: `side_by_side_hideout.png`, `side_by_side_hex.png`,
`side_by_side_optic.png`, `side_by_side_ghillie.png`.

```bash
godot --headless --path . -s res://tools/headless_loop_test.gd   # HEADLESS_LOOP_OK
godot --resolution 1280x720 -- --capture-art-armory
godot --resolution 1280x720 -- --capture-art-hideout
godot --resolution 1280x720 -- --capture-art-hex
godot --resolution 1280x720 -- --capture-art-operative-doll
godot --resolution 1280x720 -- --capture-art-optic
python3 tools/compose_art_pack_v2.py
```

## Out of this slice

Gun shop SKUs · Marks prices · ballistics / hit% · OEM marks · merging #30.
