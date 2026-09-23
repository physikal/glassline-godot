# Chrome reconfirm — hideout rack + Attack optic landscape

Architect slice: [Polish Soft P2s](https://www.notion.so/3e44dabdb33981afb426e6e4fe7926d4). Chrome only. No new SKUs, no art-pack rebuild, SMOKE spent chip left as shipped.

## Hideout rack — drifted, then aligned

Lobby canon already paints the three bolts. Dynamic states stay:

| State | Chrome |
| --- | --- |
| Owned | Plate crop, 1:1 on that bolt |
| Locked | Same rect, washed silhouette |
| Equipped | Gold underline on that rect |

Fieldbolt (24, 192, 268×56) and Railframe (24, 252, 268×56) already sat on the paint. Crescent’s crop is 268×50 and matches the plate at **(24, 318)**, but the slot was a 268×56 box at y=312, so the wash sat 3px high and left a sliver of the painted teal bolt. Hands used a 228×88 box at (600, 320), which scaled the 192×52 bolt off the painted rifle. Both now use the plate rect. Copy is unchanged: no LOCKED / STOWED label. ARMORY stays EQUIP / EQUIPPED / `OWNED · visual only`.

## Attack optic — drifted, then landscape

`optic-attack.jpg` was already the full-screen plate (thumb stick over the D-pad, Fire a separate tap). Hex faces are z 1–2 and were drawing **through** the scope, so the landscape read as hex tiles. The plate now uses z 36 (`z_as_relative = false`), above the board and under the forfeit plate (z 50). No hex stamp is drawn inside the optic.

## Locked canon targets

| Surface | Compare to | Live |
| --- | --- | --- |
| Hideout rack | `lobby-canon.jpg` bolts + `match-board-canon.jpg` HUD | Fieldbolt **equipped** (gold underline) · Railframe **owned** (plate paint) · Crescent **locked** (wash). No new SKUs. |
| Attack optic | `optic-attack.jpg` + match-board plate | **Joystick** over the plate plus. The painted D-pad stays covered. Fire is still a separate tap. |

## Stills

- Before rack: `artifacts/ux/chrome_reconfirm_rack_before.png`
- After rack (Fieldbolt equipped · Railframe owned · Crescent locked): `artifacts/ux/chrome_reconfirm_rack_after.png`
- Before optic: `artifacts/ux/chrome_reconfirm_optic_before.png`
- After optic: `artifacts/ux/chrome_reconfirm_optic_after.png`
- Side-by-side rack vs lobby-canon + match-board: `artifacts/ux/chrome_reconfirm_sbs_rack.png`
- Side-by-side optic joystick vs optic-attack + match-board: `artifacts/ux/chrome_reconfirm_sbs_optic.png`

```bash
godot --headless --path . -s res://tools/headless_loop_test.gd   # HEADLESS_LOOP_OK
godot --resolution 1280x720 -- --capture-gun-rack-dynamic
godot --resolution 1280x720 -- --capture-art-optic
```
