# T3 gun-part ladder — Optic / Stock / Barrel

Client half of [Slice ticket — T3 gun-part ladder](https://www.notion.so/3e44dabdb339812aa560ff63a480c9b9).  
Same three slots. Same `/shop` buy + equip. Same snapshot fields. Soft feel only.

## LIVE catalog

Coder tip `fcd5fac` is on `https://glassline-api.vercel.app` (checked 2026-09-23). `GET /shop` lists the three SKUs. `GET /shop/me` publishes the same snapshot fields as T1/T2.

| Slot | id | ★ | solo feel from bare |
| --- | --- | --- | --- |
| Optic | `gun_part_optic_t3` | 275 | `shotWindowSec` 1.2 → **1.70** |
| Stock | `gun_part_stock_t3` | 325 | `wobbleScale` **0.70** |
| Barrel | `gun_part_barrel_t3` | 375 | `wobbleScale` **0.80** |

Kind `gun-part`. Names `OPTIC T3` / `STOCK T3` / `BARREL T3`. `tier: 3`. The plate uses the catalog `id` and `price`. LIVE price and name win when the row is present.

## Feel

Attack chrome reads `you.shotWindowSec` and `you.wobbleScale` only. A missing or null field stays the bare plate (1.2s, wobble 1) even when a T3 id is equipped. Equipped ids do not author the juice. The mock table matches the LIVE numbers so editor snapshots use the same fields; it does not override a server value.

Bare `GET /shop/me` on that deploy returned `shotWindowSec: 1.2` and `wobbleScale: 1` with null part ids.

Stock + barrel stack floor stays **0.75**. That holds for T3+T3 and every mixed pair. Solo T3 stock is 0.70. Solo T3 barrel is 0.80. Optic does not change wobble. Stock and barrel do not change the window.

## Plate

Same PARTS wood chips, toy glyphs, muted locked peg when unowned. Equip T3 replaces the lower tier in that slot. Owning T1 and T2 is fine. T3 does not require them. Insufficient Marks is the shared wood toast `Not enough Marks.` Buy-feel stays `Shot window looser` / `Wobble quieter`. Practice Marks stay Δ0. No hit% / spot% / exposure, no new slot, no IAP.

Headless `HEADLESS_LOOP_OK` and `PART_T3_OK`. Unowned T3 rows use the same locked peg mute as T1/T2.

ARMORY taste stills are on hold until Soft HUD H1–H4 clears. Existing `artifacts/ux/part_t3_*.png` shots are not a taste sign-off. HUD punch-list is a separate pass.
