# Gun SKUs — chrome only

Client half of [Slice ticket — Gun SKUs](https://www.notion.so/3e14dabdb339819bbf45c94cfa4cd796).  
Same `/shop` spine as ghillie ★50 / bandana ★100 / poster ★150: `GET /shop` + `POST /shop/buy` `{ itemId, clientBuyId }` + `POST /shop/equip` `{ itemId }` / `{ itemId: null, slot: "gun" }`. **Catalog +3 SKUs**, not a new endpoint family.

Hard: **chrome only** · **zero combat / ballistics / accuracy** · **no IAP** · **no fourth gun** · **no mil-sim / OEM art**. Copy may say “visual only”.

Editor Play stays MOCK (`use_live_api=false`). Smoke path wires `LiveMatchClient.get_shop` + `buy_shop` + `equip_cosmetic` at `https://glassline-api.vercel.app`. LIVE catalog missing guns → client merge-appends mock rows.

## GD stamped catalog (2026-09-20)

| Field | Starter | Sink A | Sink B |
| --- | --- | --- | --- |
| `itemId` | **`gun_fieldbolt`** | **`gun_railframe`** | **`gun_crescent`** |
| name | FIELDBOLT | RAILFRAME | CRESCENT |
| kind | `gun` | `gun` | `gun` |
| equip slot | `equippedGunId` | `equippedGunId` | `equippedGunId` |
| **price** | ★0 STARTER (owned-by-default) | **★125** | **★200** |
| combat | false | false | false |

Constants: `Contract.GUN_FIELDBOLT` / `GUN_RAILFRAME` / `GUN_CRESCENT`. Slots **coexist** with `equippedSkinId` + `equippedDecorId` — a gun buy / equip never clobbers skin or poster.

## LIVE G1–G6 (2026-09-20) — **PENDING** Coder catalog

**Base:** `https://glassline-api.vercel.app`  
**Contract:** `/docs/contract` · `POST /players` durable token · GET `/shop` public catalog · POST `/shop/buy` `{ itemId, clientBuyId }` + `Authorization: Bearer <playerToken>` · POST `/shop/equip` `{ itemId }` / `{ itemId: null, slot: "gun" }`

Probed catalog (Coder guns **not** landed at smoke time):

```json
{"items":[{"id":"skin_hideout_stub","name":"Hideout Skin (stub)","price":50,"kind":"skin"},{"id":"skin_bandana_stub","name":"BANDANA RECOLOR","price":100,"kind":"skin"},{"id":"decor_poster_stub","name":"HIDEOUT POSTER","price":150,"kind":"decor"}]}
```

`GET /shop` is **catalog-only** (no `you.marks`). Client `merge_live_shop_catalog` appends the three gun stubs so ARMORY still shows Fieldbolt / Railframe / Crescent. Buy 200 is `{ ok, you: { marks, equippedSkinId, equippedDecorId, equippedGunId? }, purchaseId, item }`. 402 is `{ error, code: "insufficient_marks", you: { marks } }`. Client binds that `you.marks`. Hideout + smoke **never `marks -=`**.

| Gate | Result | Evidence |
| --- | --- | --- |
| **G1** catalog `kind: gun` · Fieldbolt owned-by-default | **PASS mock · PENDING LIVE** | Mock `GET /shop` lists six SKUs. Fieldbolt ★0 STARTER owned+equipped. LIVE catalog still three skins/poster — merge-appends guns. |
| **G2** buy Railframe ★125 + `clientBuyId` idempotent + equip slot | **PASS mock · PENDING LIVE** | Mock `200→75`, replay same id stays ★75. Auto-equip `equippedGunId=gun_railframe`. Skin / decor untouched. Unequip `{ itemId: null, slot: "gun" }` clears highlight; hands/optic fall back to Fieldbolt. |
| **G3** 402 insufficient in UI | **PASS mock · PENDING LIVE** | ★80 vs Crescent ★200 → `insufficient_marks`. Replay still 402. Chip unchanged. |
| **G4** dynamic rack | **PASS mock** | Owned painted plate-crop · locked wash silhouette · equipped gold underline. Still [`ux/gun_rack_dynamic.png`](ux/gun_rack_dynamic.png). |
| **G5** zero combat delta | **PASS mock · PENDING LIVE** | Fieldbolt / Railframe / Crescent miss `hit=false` / no Hot / kill `hit=true` `marksDelta +25`. `RECON_BASE` 0.35. `lastAction` has no gun field. |
| **G6** UX three gun rows + visual-only copy | **PASS mock** | [`ux/gun_armory_three_row.png`](ux/gun_armory_three_row.png) (Fieldbolt EQUIPPED · Railframe ★125 · Crescent ★200). [`ux/gun_equipped_optic.png`](ux/gun_equipped_optic.png) (`RAILFRAME · visual only`). |

HTTP log: [`artifacts/live_shop_gun_smoke.txt`](live_shop_gun_smoke.txt) · `LIVE_SHOP_GUN_PENDING` until Coder lists `gun_*`.  
Mock: `HEADLESS_LOOP_OK` (`_gun_chrome_case`).

Raw stills (this branch):

- https://raw.githubusercontent.com/physikal/glassline-godot/cursor/gun-skus-c671/artifacts/ux/gun_armory_three_row.png
- https://raw.githubusercontent.com/physikal/glassline-godot/cursor/gun-skus-c671/artifacts/ux/gun_rack_dynamic.png
- https://raw.githubusercontent.com/physikal/glassline-godot/cursor/gun-skus-c671/artifacts/ux/gun_equipped_optic.png

```bash
GLASSLINE_API_BASE=https://glassline-api.vercel.app python3 tools/live_shop_gun_smoke.py
godot --headless --path . -s res://tools/headless_loop_test.gd   # HEADLESS_LOOP_OK
godot --resolution 1280x720 -- --capture-gun-armory-three-row
godot --resolution 1280x720 -- --capture-gun-rack-dynamic
godot --resolution 1280x720 -- --capture-gun-equipped-optic
```

## Hard rule

Never `marks -=` (or `marks +=`) on the client as truth. Hideout BUY posts `{ itemId, clientBuyId }` and rebinds `you.marks` from the returned snapshot only. `ClientSession.marks` is a display cache. A LIVE 200 that only returns `item` **merges** that id into `ownedGuns` — it does not wipe skin / poster / Fieldbolt.

Unequip empty `equippedGunId` stays empty (no gold rack highlight). Hands + Attack optic **visually** fall back to Fieldbolt. Unowned ids also fall back to Fieldbolt. Never invent a fourth family.

## LIVE shape (same as sink 1 / 2 / 3)

| Method | Path | Body / notes |
| --- | --- | --- |
| GET | `/shop` | `{ items: ShopItem[] }` public. Prefer LIVE when guns are present; merge-append otherwise. |
| POST | `/players` | `{ }` → `{ playerId, token, marks }`. Persist `token`. |
| POST | `/shop/buy` | `{ itemId, clientBuyId }` + Bearer **player** token → `{ ok, you: { marks, equippedSkinId, equippedDecorId, equippedGunId }, purchaseId, item }`. Last buy auto-equips **that slot only**. |
| POST | `/shop/equip` | `{ itemId }` or `{ itemId: null, slot?: "skin"\|"decor"\|"gun" }`. Gun never overwrites skin / decor. |
| GET | `/shop/me` | `{ you: { marks, equippedSkinId, equippedDecorId, equippedGunId }, owned, ownedGuns? }` |
| 402 | | `{ error, code: "insufficient_marks", you: { marks } }` |

## G1–G6 mapping

| Gate | Client surface | Behavior |
| --- | --- | --- |
| **G1** Catalog + starter | ARMORY GUNS band | Fieldbolt STARTER owned. Railframe ★125. Crescent ★200. |
| **G2** Buy + equip | ARMORY BUY / EQUIP / EQUIPPED | Idempotent `clientBuyId`. `equippedGunId` only. |
| **G3** 402 | Row status `Not enough Marks.` | Snapshot marks rebound. No grant. |
| **G4** Rack | Hideout wall overlays | Painted owned · locked silhouette · gold equipped underline. |
| **G5** Combat | Attack / Recon / UAV | Unchanged. Optic family stamp is chrome. |
| **G6** Copy | ARMORY + optic | `visual only` / `STARTER`. No accuracy / ballistics claim. |

## Bind

| Surface | Chrome |
| --- | --- |
| Hideout rack | Plate-cropped `assets/art_v2/rifle_*_plate.png` at hang points (24, 192/252/312). Locked wash for unowned. |
| Hideout hands | `rifle_held_plate.png` + family accent modulate (olive / brass / teal). |
| Attack optic | Locked `optic-attack.jpg` + family stamp + `FIELDBOLT · visual only` (or Railframe / Crescent). |
| Marks chip | `you.marks` only. Equip never debits. |

Josh-locked paint from `assets/canon` / match-board / lobby plates. No new dialect. No mil-sim.

## Mock vs LIVE

| Mode | Shop / equip |
| --- | --- |
| Editor MOCK | `MockMatchServer.get_shop` / `buy_shop` / `equip_cosmetic`. Snapshot includes `you.equippedGunId`. |
| LIVE | `GET /shop` (merge-append guns if Coder lags) + `GET /shop/me` + `POST /shop/buy` + `POST /shop/equip`. Apply snapshot only. |

## Out of this slice

Ballistics · accuracy buffs · IAP · fourth gun · mil-sim / OEM art.
