# Production art pack — chrome swap

Josh-locked **pixel-cartoon / toy-spy** into existing Godot 4 2D slots.  
Taste ground truth is the attached plates (`lobby-canon.jpg`, `lobby-ghillie.jpg`, `hex-map.jpg`, `optic-attack.jpg`) — same language as `assets/canon/`.  
**No** ballistics, Marks economy, combat, API, or gun SKU changes. No mil-sim / photoreal / rail salad / OEM.

Live chrome is procedural `CanvasItem` / `Image` textures (nearest filter) so atlas paths stay stable.

## Slots swapped

| Slot | Was | Now |
| --- | --- | --- |
| Hideout room | Canon plate + stamped HUD/dock | Same plates; baked rifle rack stamped out so live chrome can bind |
| Rifle rack | Dark gold **RACK** card | Wall-hang — wood plank `RIFLE RACK`, plate-weight rifles on pegs, gold underline when equipped |
| ARMORY wartable | Three chrome rows | Same three SKUs + toy-spy row icons (leaf / bandana / poster). No gun rows |
| Hex terrain | Flat fills + busy stamps | Plate board: sandy OPEN specks, one leafy BRUSH clump, one HARD rock, dark `?` UNKNOWN |
| Operative | Plate kid + click-to-cycle suit | Plate + **held rifle** overlay matching equipped family (Fieldbolt stays on the plate) |
| Exposure doll | Stick dummy | Teal-hoodie kid / leafy ghillie hood (lobby-canon / lobby-ghillie) + gold frame |
| Attack optic | Flat ColorRect forest + 52px black housing | Full-bleed `optic-attack.jpg` housing; yellow ZOOM pills; circular FIRE; thin family ticks |
| UI chips | Marks / coach / queue / end summary | Marks star; chunky wartable chips; queue / end plates unchanged in copy |

## Rifle families (in-fiction names — Josh may rename)

Visual slots only. **Not** in `GET /shop` catalog. No OEM logos.

| Id | Name | Silhouette |
| --- | --- | --- |
| `gun_fieldbolt` | **FIELDBOLT** | Olive bolt classic — chunky stock, modest tube scope |
| `gun_railframe` | **RAILFRAME** | Teal chassis bolt — boxy frame, teal accent, no rail salad |
| `gun_crescent` | **CRESCENT** | Tan long cutout — thumbhole stock, long toy optic |

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

Taste gate — six stills. Raw GitHub (this branch):

1. Hideout idle + ARMORY open  
   https://raw.githubusercontent.com/physikal/glassline-godot/cursor/production-art-pack-1a24/artifacts/ux/art_01_hideout_armory.png
2. Dynamic rack (owned starter · locked ×2 · equipped highlight)  
   https://raw.githubusercontent.com/physikal/glassline-godot/cursor/production-art-pack-1a24/artifacts/ux/art_02_hideout_rack.png
3. Hex board OPEN / BRUSH / HARD / UNKNOWN  
   https://raw.githubusercontent.com/physikal/glassline-godot/cursor/production-art-pack-1a24/artifacts/ux/art_03_hex_terrain.png
4. Operative + exposure doll  
   https://raw.githubusercontent.com/physikal/glassline-godot/cursor/production-art-pack-1a24/artifacts/ux/art_04_operative_doll.png
5. Attack optic (same rifle family)  
   https://raw.githubusercontent.com/physikal/glassline-godot/cursor/production-art-pack-1a24/artifacts/ux/art_05_attack_optic.png
6. UI chips (Marks / coach / queue / end summary)  
   https://raw.githubusercontent.com/physikal/glassline-godot/cursor/production-art-pack-1a24/artifacts/ux/art_06_ui_chips.png

Aliases (same pixels): `art_armory_wartable.png`, `art_hideout_dynamic.png`, `art_hex_terrain.png`, `art_operative_doll.png`, `art_attack_optic.png`, `art_ui_chips.png`. Family plate: `art_rifle_families.png`.

```bash
godot --headless --path . -s res://tools/headless_loop_test.gd   # HEADLESS_LOOP_OK
godot --resolution 1280x720 -- --capture-art-armory
godot --resolution 1280x720 -- --capture-art-hideout
godot --resolution 1280x720 -- --capture-art-hex
godot --resolution 1280x720 -- --capture-art-operative-doll
godot --resolution 1280x720 -- --capture-art-optic
godot --resolution 1280x720 -- --capture-art-ui-chips
godot --resolution 1280x720 -- --capture-art-rifles
```

## Out of this slice

Gun shop SKUs · Marks prices · ballistics / hit% · OEM marks · mil-sim / photoreal plates.
