# Production art pack — chrome swap

Josh-locked **pixel-cartoon / toy-spy** into existing Godot 4 2D slots.  
Canon homage: `assets/canon/` (`lobby-canon.jpg`, `lobby-ghillie.jpg`, `hex-map.jpg`, `optic-attack.jpg`). `/shared/glassline/` is not mounted in this environment — same plates live in-repo. Rifle silhouettes are in-fiction (Fieldbolt / Railframe / Crescent). **No OEM.**

**No** ballistics, Marks economy, combat, API, or gun SKU changes. No mil-sim / photoreal / rail salad.

Live chrome is procedural `CanvasItem` / `Image` textures (nearest filter) so atlas paths stay stable.

## Slots swapped

| Slot | Now |
| --- | --- |
| Hideout + ARMORY | Canon plates; wood `RIFLE RACK` wall hang; three cosmetic SKU rows |
| Dynamic rack | Fieldbolt owned+equipped (gold underline); Railframe + Crescent locked silhouettes |
| Hex terrain | OPEN sand specks / BRUSH leaf clump / HARD rock / UNKNOWN `?` |
| Operative + doll | Plate kid; exposure doll = teal hoodie / leafy ghillie |
| Attack optic | Full-bleed `optic-attack.jpg`; family chip; same equipped rifle family |
| UI chips | Marks star · first-hunt coach · queue wartable · end summary |

## Taste-gate stills (exactly these 6)

Raw GitHub (`cursor/production-art-pack-1a24`):

1. Hideout idle + ARMORY open  
   https://raw.githubusercontent.com/physikal/glassline-godot/cursor/production-art-pack-1a24/artifacts/ux/01_hideout_idle_armory.png
2. Dynamic rack — owned starter · locked silhouette ×2 · equipped highlight  
   https://raw.githubusercontent.com/physikal/glassline-godot/cursor/production-art-pack-1a24/artifacts/ux/02_dynamic_rack.png
3. Hex board OPEN / BRUSH / HARD / UNKNOWN  
   https://raw.githubusercontent.com/physikal/glassline-godot/cursor/production-art-pack-1a24/artifacts/ux/03_hex_open_brush_hard_unknown.png
4. Operative + exposure doll  
   https://raw.githubusercontent.com/physikal/glassline-godot/cursor/production-art-pack-1a24/artifacts/ux/04_operative_exposure_doll.png
5. Attack optic frame (Fieldbolt family)  
   https://raw.githubusercontent.com/physikal/glassline-godot/cursor/production-art-pack-1a24/artifacts/ux/05_attack_optic_fieldbolt.png
6. UI chips — Marks / coach / queue / end summary  
   https://raw.githubusercontent.com/physikal/glassline-godot/cursor/production-art-pack-1a24/artifacts/ux/06_ui_chips_marks_coach_queue_end.png

```bash
godot --headless --path . -s res://tools/headless_loop_test.gd   # HEADLESS_LOOP_OK
godot --resolution 1280x720 -- --capture-art-armory
godot --resolution 1280x720 -- --capture-art-hideout
godot --resolution 1280x720 -- --capture-art-hex
godot --resolution 1280x720 -- --capture-art-operative-doll
godot --resolution 1280x720 -- --capture-art-optic
godot --resolution 1280x720 -- --capture-art-ui-chips
```

## Out of this slice

Gun shop SKUs · Marks prices · ballistics / hit% · OEM marks · mil-sim / photoreal plates.
