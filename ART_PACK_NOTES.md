# Production art pack — chrome swap

Josh-locked **pixel-cartoon / toy-spy** into existing Godot 4 2D slots.  
**No** ballistics, Marks economy, combat, API, or gun SKU changes.

Canon plates stay at `assets/canon/` (`lobby-canon.jpg`, `lobby-ghillie.jpg`, `hex-map.jpg`, `optic-attack.jpg`). Live chrome is procedural `CanvasItem` / `Image` textures (nearest filter) so atlas paths stay stable.

## Slots swapped

| Slot | Was | Now |
| --- | --- | --- |
| Hideout room | Canon plate + stamped HUD/dock | Same plates; baked rifle rack / held gun stamped out so live chrome can bind |
| ARMORY wartable | Three chrome rows | Same three SKUs + toy-spy row icons (leaf / bandana / poster). No gun rows |
| Hex terrain | Flat fills + simple stamps | Richer OPEN / BRUSH / HARD / UNKNOWN pixel stamps (sand grain, leaf clumps, rocks, `?`) |
| Operative | Plate kid + click-to-cycle suit | Plate + **held rifle** overlay matching equipped family |
| Exposure doll | Blocky dummy | Toy-spy operative (hoodie / bandana / leafy hood) + gold frame. Same `equippedSkinId` wash |
| Attack optic | Thin grey ring | Family housing (wood Fieldbolt / teal Railframe / crescent ticks) + `FIELDBOLT · TOY OPTIC` chip |
| UI chips | Marks / coach / queue / end summary | Marks star icon; chunkier coach wartable chips; queue / end plates unchanged in copy |

## Rifle families (in-fiction names — Josh may rename)

Visual slots only. **Not** in `GET /shop` catalog. No OEM logos.

| Id | Name | Silhouette |
| --- | --- | --- |
| `gun_fieldbolt` | **FIELDBOLT** | Bolt classic (Remington 700 / M24 family) — wood stock, modest tube scope |
| `gun_railframe` | **RAILFRAME** | Chassis bolt (AI AX / AWM-class) — boxy frame, teal accent, no rail salad |
| `gun_crescent` | **CRESCENT** | Long cutout (SVD / Dragunov-class) — thumbhole stock, long toy optic |

## Dynamic hideout bind

Rack / wall / held rifle / attack optic share one family id.

| Source | Behavior |
| --- | --- |
| Local stub (default) | Fieldbolt **owned + equipped**. Railframe + Crescent **locked** silhouettes + hooks |
| `GET /shop/me` when present | `you.equippedGunId` + `ownedGuns` / `ownedGunIds` (also `you.cosmetics.*`) |
| Unknown / unowned equip id | Fall back to Fieldbolt |
| Starter | Fieldbolt always owned-by-default even if the list omits it |
| Poster / skins | Unchanged. `equippedDecorId` poster coexists with skin **and** gun slots |

No ARMORY buy / equip for guns this pass. Locked slots are display-only (`LOCKED · gun SKU later`).

## Stills (`artifacts/ux/`)

Raw GitHub (this branch):

- https://raw.githubusercontent.com/physikal/glassline-godot/cursor/production-art-pack-1a24/artifacts/ux/art_hideout_dynamic.png
- https://raw.githubusercontent.com/physikal/glassline-godot/cursor/production-art-pack-1a24/artifacts/ux/art_armory_wartable.png
- https://raw.githubusercontent.com/physikal/glassline-godot/cursor/production-art-pack-1a24/artifacts/ux/art_hex_terrain.png
- https://raw.githubusercontent.com/physikal/glassline-godot/cursor/production-art-pack-1a24/artifacts/ux/art_attack_optic.png
- https://raw.githubusercontent.com/physikal/glassline-godot/cursor/production-art-pack-1a24/artifacts/ux/art_rifle_families.png
- https://raw.githubusercontent.com/physikal/glassline-godot/cursor/production-art-pack-1a24/artifacts/ux/art_operative_doll.png

```bash
godot --headless --path . -s res://tools/headless_loop_test.gd   # HEADLESS_LOOP_OK
godot --resolution 1280x720 -- --capture-art-hideout
godot --resolution 1280x720 -- --capture-art-armory
godot --resolution 1280x720 -- --capture-art-rifles
godot --resolution 1280x720 -- --capture-art-operative-doll
godot --resolution 1280x720 -- --capture-art-hex
godot --resolution 1280x720 -- --capture-art-optic
```

## Out of this slice

Gun shop SKUs · Marks prices · ballistics / hit% · OEM marks · mil-sim / photoreal plates.
