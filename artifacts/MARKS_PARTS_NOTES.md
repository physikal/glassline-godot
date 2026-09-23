# Marks gun-part sinks — Optic / Stock / Barrel

Client half of [Slice ticket — Marks gun-part sinks](https://www.notion.so/3e44dabdb33981189443e51553699b0b).  
Same `/shop` spine as guns: `GET /shop` + `POST /shop/buy` `{ itemId, clientBuyId }` + `POST /shop/equip` `{ itemId }` / `{ itemId: null, slot }`. **Catalog part SKUs**, not a new endpoint family. T2 is three more `gun-part` ids on that spine.

Hard: **server owns feel** · **client never authors kill / spot / exposure / HG / SMOKE math** · **no IAP** · **no mil-sim art** · **practice Marks Δ0**.

Editor Play stays MOCK (`use_live_api=false`). LIVE `GET /shop` lists T1 `gun_part_optic` / `gun_part_stock` / `gun_part_barrel` and T2 `gun_part_optic_t2` / `gun_part_stock_t2` / `gun_part_barrel_t2` (`kind: gun-part`). ARMORY buys those ids on the shop spine. A catalog that omits one still shows the row and the buy posts.

## Feel (chrome only)

| Part | id | slot | price | juice |
| --- | --- | --- | --- | --- |
| OPTIC | `gun_part_optic` | `equippedOpticId` | ★75 | `shotWindowSec` 1.2 → 1.4 |
| OPTIC T2 | `gun_part_optic_t2` | `equippedOpticId` | ★150 | `shotWindowSec` 1.2 → 1.55 |
| STOCK | `gun_part_stock` | `equippedStockId` | ★100 | `wobbleScale` 0.8 |
| STOCK T2 | `gun_part_stock_t2` | `equippedStockId` | ★175 | `wobbleScale` 0.75 |
| BARREL | `gun_part_barrel` | `equippedBarrelId` | ★125 | `wobbleScale` 0.9 |
| BARREL T2 | `gun_part_barrel_t2` | `equippedBarrelId` | ★200 | `wobbleScale` 0.85 |

Stock + barrel stack floors at ×0.75. That cap holds for T1+T1, T2+T2, and mixed tiers. Optic does not change wobble. Stock and barrel do not change the window. One equipped id per slot. Buying or equipping T2 replaces T1 in that slot. Owning both is fine. T2 does not require T1.

LIVE publishes `you.shotWindowSec` and `you.wobbleScale` (T1 `b5ba339`, T2 `2608bd6`). Attack chrome reads those numbers only. A missing or null field stays the bare plate (1.2s, wobble 1). Equipped ids do not author the juice. Hit resolution stays the occupy formula. Kind is `gun-part`. ARMORY buys T1 and T2 on the shop spine.

## Bind

Snapshot keys: `you.equippedOpticId`, `you.equippedStockId`, `you.equippedBarrelId` (null = empty). Optional `you.ownedParts`. Buy auto-equips that slot only and does not clobber gun / skin / decor. Client never `marks -=`.

ARMORY third row under guns: the same PARTS wood plate, three slots, T1 then T2 on each slot. Wood chips, toy glyphs, ★ prices. T2 is the higher ★ on that slot (`OPTIC T2` ★150, `STOCK T2` ★175, `BARREL T2` ★200), not a new shop dialect. No hit% / spot% / exposure on the row. Equipped slots paint a green peg chip on the rack (the worn id, so T2 replaces the T1 chip) and a glyph peg on the exposure doll. Insufficient Marks is one shared wood toast (`Not enough Marks.`), not a line on each chip. A successful buy shows a clearing wood toast — Optic “Shot window looser”, Stock / Barrel “Wobble quieter” — then the plate hides itself. Attack chrome reads `you.shotWindowSec` / `you.wobbleScale` only. A missing feel field stays the bare plate even when a T2 id is equipped.

Headless `HEADLESS_LOOP_OK` and `PART_T2_OK`. Stills: `artifacts/ux/part_t2_rows.png`, `part_t2_equipped.png`, `part_t2_buy_toast.png`, `part_t2_insufficient.png`.

## Parity

Headless `HEADLESS_LOOP_OK`. Empty miss stays hit false / chance 0. Occupy kill stays the existing chance (HG +0.10, brush −0.10) and ★25. Practice kill is ★0 and does not grant. Parts are not a term in hit chance.
