# Marks gun-part sinks — Optic / Stock / Barrel

Client half of [Slice ticket — Marks gun-part sinks](https://www.notion.so/3e44dabdb33981189443e51553699b0b).  
Same `/shop` spine as guns: `GET /shop` + `POST /shop/buy` `{ itemId, clientBuyId }` + `POST /shop/equip` `{ itemId }` / `{ itemId: null, slot }`. **Catalog +3 part SKUs**, not a new endpoint family.

Hard: **server owns feel** · **client never authors kill / spot / exposure / HG / SMOKE math** · **no IAP** · **no mil-sim art** · **practice Marks Δ0**.

Editor Play stays MOCK (`use_live_api=false`). Live catalog that omits a part keeps the row and mutes BUY (`pending`) so the client does not POST. When `/shop` lists the id, the row wires.

## Feel (chrome only)

| Part | id | slot | price | juice |
| --- | --- | --- | --- | --- |
| OPTIC | `part_optic` | `equippedOpticId` | ★75 | shot window 1.2s → 1.4s |
| STOCK | `part_stock` | `equippedStockId` | ★100 | wobble ×0.80 |
| BARREL | `part_barrel` | `equippedBarrelId` | ★125 | wobble ×0.90 |

Stock + barrel stack floors at ×0.75 (−25%). Optic does not change wobble. Stock and barrel do not change the window. One equipped id per slot.

`you.wobbleScale` / `you.shotWindowMs`, when they are numbers, win. Missing or null fields use the table above for Attack chrome only. Hit resolution stays the occupy formula.

## Bind

Snapshot keys: `you.equippedOpticId`, `you.equippedStockId`, `you.equippedBarrelId` (null = empty). Optional `you.ownedParts`. Buy auto-equips that slot only and does not clobber gun / skin / decor. Client never `marks -=`.

ARMORY third row under guns: wood chips, toy glyphs, ★ prices. No hit% / spot% / exposure on the row. Equipped slots paint a green peg chip on the rack and a glyph peg on the exposure doll. Buy toast: “Shot window looser” / “Wobble quieter”.

## Parity

Headless `HEADLESS_LOOP_OK`. Empty miss stays hit false / chance 0. Occupy kill stays the existing chance (HG +0.10, brush −0.10) and ★25. Practice kill is ★0 and does not grant. Parts are not a term in hit chance.
