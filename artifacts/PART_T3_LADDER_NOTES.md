# T3 gun-part ladder — Optic / Stock / Barrel

Client half of [Slice ticket — T3 gun-part ladder](https://www.notion.so/3e44dabdb339812aa560ff63a480c9b9).  
Same three slots. Same `/shop` buy + equip. Same snapshot fields. Soft feel only.

## Tip dependency

Coder catalog tip checked 2026-09-23: `physikal/glassline-api` `src/shopCatalog.ts` (`3d297589`) lists T1 and T2 only. `GunPartTier` is `1 | 2`. No `gun_part_*_t3`.

Client ids follow that spine so the rows light when `GET /shop` returns `tier: 3`:

| Slot | id | price | solo feel from bare |
| --- | --- | --- | --- |
| Optic | `gun_part_optic_t3` | ★275 | `shotWindowSec` 1.2 → **1.70** (+0.50s) |
| Stock | `gun_part_stock_t3` | ★325 | `wobbleScale` **0.70** (−30%) |
| Barrel | `gun_part_barrel_t3` | ★375 | `wobbleScale` **0.80** (−20%) |

Kind stays `gun-part`. Names `OPTIC T3` / `STOCK T3` / `BARREL T3`. `tier: 3`. LIVE price and name win when the catalog lists the id. A catalog that omits one still shows the row (same gap-fill as T2).

## Feel

Attack chrome reads `you.shotWindowSec` and `you.wobbleScale` only. A missing or null field stays the bare plate (1.2s, wobble 1) even when a T3 id is equipped. Equipped ids do not author the juice.

Stock + barrel stack floor stays **0.75**. That holds for T3+T3 and every mixed pair. Solo T3 stock is 0.70; the pair does not go quieter than 0.75. Optic does not change wobble. Stock and barrel do not change the window.

If Coder reuses the live sum-then-cap (`Math.min(stockPct + barrelPct, 25)`) on a solo T3 stock, the snapshot may publish 0.75 instead of 0.70. The client shows that number. It does not override it.

## Plate

Same PARTS wood chips, toy glyphs, muted locked peg when unowned. Equip T3 replaces the lower tier in that slot. Owning T1 and T2 is fine. T3 does not require them. Insufficient Marks is the shared wood toast `Not enough Marks.` Buy-feel stays `Shot window looser` / `Wobble quieter`. Practice Marks stay Δ0. No hit% / spot% / exposure, no new slot, no IAP.

Headless `HEADLESS_LOOP_OK` and `PART_T3_OK`. Stills: `artifacts/ux/part_t3_rows.png`, `part_t3_insufficient.png`, `part_t3_buy_toast.png`, `part_t3_equipped.png`.
