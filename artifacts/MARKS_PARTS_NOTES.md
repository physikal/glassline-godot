# Marks gun-part sinks — Optic / Stock / Barrel

Client half of [Slice ticket — Marks gun-part sinks](https://www.notion.so/3e44dabdb33981189443e51553699b0b).  
Same `/shop` spine as guns: `GET /shop` + `POST /shop/buy` `{ itemId, clientBuyId }` + `POST /shop/equip` `{ itemId }` / `{ itemId: null, slot }`. **Catalog +3 part SKUs**, not a new endpoint family.

Hard: **server owns feel** · **client never authors kill / spot / exposure / HG / SMOKE math** · **no IAP** · **no mil-sim art** · **practice Marks Δ0**.

Editor Play stays MOCK (`use_live_api=false`). LIVE `GET /shop` lists `gun_part_optic` / `gun_part_stock` / `gun_part_barrel` (`kind: gun-part`). ARMORY buys those ids on the shop spine. A catalog that omits one still shows the row and the buy posts.

## Feel (chrome only)

| Part | id | slot | price | juice |
| --- | --- | --- | --- | --- |
| OPTIC | `gun_part_optic` | `equippedOpticId` | ★75 | `shotWindowSec` 1.2 → 1.4 |
| STOCK | `gun_part_stock` | `equippedStockId` | ★100 | `wobbleScale` 0.8 |
| BARREL | `gun_part_barrel` | `equippedBarrelId` | ★125 | `wobbleScale` 0.9 |

Stock + barrel stack floors at ×0.75 (−25%). Optic does not change wobble. Stock and barrel do not change the window. One equipped id per slot.

LIVE `b5ba339` publishes `you.shotWindowSec` and `you.wobbleScale`. Attack chrome reads those numbers only. A missing or null field stays the bare plate (1.2s, wobble 1). Equipped ids do not author the juice. Hit resolution stays the occupy formula. Kind is `gun-part`. ARMORY buys the three ids on the shop spine.

## Bind

Snapshot keys: `you.equippedOpticId`, `you.equippedStockId`, `you.equippedBarrelId` (null = empty). Optional `you.ownedParts`. Buy auto-equips that slot only and does not clobber gun / skin / decor. Client never `marks -=`.

ARMORY third row under guns: wood chips, toy glyphs, ★ prices. No hit% / spot% / exposure on the row. Equipped slots paint a green peg chip on the rack and a glyph peg on the exposure doll. Buy toast: “Shot window looser” / “Wobble quieter”.

## Parity

Headless `HEADLESS_LOOP_OK`. Empty miss stays hit false / chance 0. Occupy kill stays the existing chance (HG +0.10, brush −0.10) and ★25. Practice kill is ★0 and does not grant. Parts are not a term in hit chance.
