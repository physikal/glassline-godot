# Marks sink 3 — HIDEOUT POSTER

Client half of [Slice ticket — Third Marks sink](https://www.notion.so/3e14dabdb339811f8423edbc4720536a).  
Same spine as ghillie ★50 / bandana ★100: `GET /shop` + `POST /shop/buy` `{ itemId, clientBuyId }` + durable player Bearer. **Catalog +1 SKU**, not a new endpoint family.

Hard: **no P2W** · **no second currency** · **no combat / spot / hit delta** · **no mil-sim art** · **no IAP** · **no fourth sink**. Cosmetic chrome only.

Editor Play stays MOCK (`use_live_api=false`). Smoke path wires `LiveMatchClient.get_shop` + `buy_shop` at `https://glassline-api.vercel.app`.

## GD stamped catalog (2026-09-20)

| Field | Sink 1 | Sink 2 | Sink 3 |
| --- | --- | --- | --- |
| `itemId` | `skin_hideout_stub` | `skin_bandana_stub` | **`decor_poster_stub`** |
| name | GHILLIE RECOLOR | BANDANA RECOLOR | **HIDEOUT POSTER** |
| kind | `skin` | `skin` | **`decor`** (LIVE may stamp `skin` / `part`) |
| **price** | ★50 | ★100 | **★150** |
| combat | false | false | **false** |

Constants: `Contract.SHOP_POSTER_ITEM_ID` / `SHOP_POSTER_PRICE`. Swap here if GD restamps (Coder catalog locks the same number).

## LIVE S3.1–S3.5 (2026-09-20)

**Base:** `https://glassline-api.vercel.app`  
**Contract:** `/docs/contract` · `POST /players` durable token · GET `/shop` public catalog · POST `/shop/buy` `{ itemId, clientBuyId }` + `Authorization: Bearer <playerToken>`

Probed catalog (Coder still two SKUs at client land — mock + merge append poster):

```json
{"items":[{"id":"skin_hideout_stub","name":"Hideout Skin (stub)","price":50,"kind":"skin"},{"id":"skin_bandana_stub","name":"BANDANA RECOLOR","price":100,"kind":"skin"}]}
```

`GET /shop` is **catalog-only** (no `you.marks`). Buy 200 shape is `{ ok, you: { marks }, purchaseId, item }`. 402 is `{ error, code: "insufficient_marks", you: { marks } }`. Client binds that `you.marks`. Hideout + smoke **never `marks -=`**.

| Gate | Result | Evidence |
| --- | --- | --- |
| **S3.1** catalog SKU `decor_poster_stub` ★150 | **PASS mock · LIVE PENDING** | Mock catalog three rows. LIVE `GET /shop` still two SKUs — `Contract.merge_live_shop_catalog` appends poster so ARMORY renders three. Coder: add `decor_poster_stub` ★150. |
| **S3.2** buy debit + `clientBuyId` idempotent | **PASS mock · LIVE PENDING** | Mock seed ★200 → snapshot ★50, `purchase` once. Replay same `clientBuyId` still ★50. LIVE buy blocked until Coder +1 SKU. |
| **S3.3** 402 insufficient in UI | **PASS mock · LIVE PENDING** | Default ★24 vs ★150: BUY disabled / `Not enough Marks.` Mock post → `insufficient_marks`, chip stays ★24. |
| **S3.4** hideout poster when owned/equipped | **PASS mock** | Wall stamp after buy (auto-equip). Suit swap keeps the poster (owned wall art). Still [`ux/hideout_poster_equipped.png`](ux/hideout_poster_equipped.png). |
| **S3.5** zero combat delta | **PASS mock** | `RECON_BASE` 0.35 · PvP kill ★25. Exposure doll ignores poster (not suit chrome). |
| **S3.6** UX three-row ARMORY | **PASS mock** | [`ux/armory_three_row.png`](ux/armory_three_row.png) (Ghillie / Bandana / Poster, ★24, disabled BUY). [`ux/armory_poster_post_buy.png`](ux/armory_poster_post_buy.png) (seed ★200 → snapshot ★50, poster OWNED). |

HTTP log: [`artifacts/live_shop_sink3_smoke.txt`](live_shop_sink3_smoke.txt) · `LIVE_SHOP_SINK3_PENDING` until Coder lands the SKU.  
Mock: `HEADLESS_LOOP_OK` (`_shop_sink3_case`).

Raw stills (this branch):

- https://raw.githubusercontent.com/physikal/glassline-godot/cursor/marks-sink3-poster-ddd3/artifacts/ux/armory_three_row.png
- https://raw.githubusercontent.com/physikal/glassline-godot/cursor/marks-sink3-poster-ddd3/artifacts/ux/armory_poster_post_buy.png
- https://raw.githubusercontent.com/physikal/glassline-godot/cursor/marks-sink3-poster-ddd3/artifacts/ux/hideout_poster_equipped.png

```bash
GLASSLINE_API_BASE=https://glassline-api.vercel.app python3 tools/live_shop_sink3_smoke.py
godot --headless --path . -s res://tools/headless_loop_test.gd   # HEADLESS_LOOP_OK
godot --resolution 1280x720 -- --capture-armory-three-row
godot --resolution 1280x720 -- --capture-armory-poster-buy
godot --resolution 1280x720 -- --capture-hideout-poster
```

## Hard rule

Never `marks -=` (or `marks +=`) on the client as truth. Hideout BUY posts `{ itemId, clientBuyId }` and rebinds `you.marks` from the returned snapshot only. `ClientSession.marks` is a display cache. A LIVE 200 that only returns `item` **merges** that id into `owned` — it does not wipe ghillie / bandana.

## LIVE shape (same as sink 1 / 2)

| Method | Path | Body / notes |
| --- | --- | --- |
| GET | `/shop` | `{ items: ShopItem[] }` public. Prefer LIVE when poster is present. |
| POST | `/players` | `{ }` → `{ playerId, token, marks }`. Persist `token`. |
| POST | `/shop/buy` | `{ itemId, clientBuyId }` + Bearer **player** token → `{ ok, you: { marks }, purchaseId, item }`. **Idempotent on `(playerId, clientBuyId)`.** |
| 402 | | `{ error, code: "insufficient_marks", you: { marks } }` |

## S3.1–S3.6 mapping

| Gate | Client surface | Behavior |
| --- | --- | --- |
| **S3.1** Catalog + shop row | ARMORY row 3 · HIDEOUT POSTER | Catalog-driven rows from `GET /shop` (merge-append if LIVE lags). ★150. |
| **S3.2** Buy at ★150 | BUY → `POST /shop/buy` | New UUID `clientBuyId`. Chip refreshes from snapshot `you.marks` only (e.g. 200→50). Replay same id does not debit twice. |
| **S3.3** Insufficient | ★24 vs ★150 | Row BUY **disabled / Not enough Marks.** If posted, reject `insufficient_marks`. Chip unchanged. |
| **S3.4** Hideout wall | owned / auto-equip | Chunky pixel toy-spy poster (gold frame, cream paper, goggles). Not a mil-sim ops board. Suit swap does not take it down. |
| **S3.5** Combat | — | Attack / Recon / UAV table unchanged. Doll ignores poster id. |
| **S3.6** Stills | `artifacts/ux/` | `armory_three_row.png` · `armory_poster_post_buy.png` · `hideout_poster_equipped.png`. |

## Client surfaces

| Surface | Behavior |
| --- | --- |
| ARMORY | Three catalog rows above LOADOUT / PLAY / INVITE / JOBS. LOADOUT focuses it. JOBS still hides ARMORY. |
| Row 1 | GHILLIE RECOLOR ★50 — unchanged first sink. |
| Row 2 | BANDANA RECOLOR ★100 — unchanged second sink. |
| Row 3 | HIDEOUT POSTER ★150 — same BUY / insufficient / OWNED / EQUIP states. |
| Marks chip | `MARKS ★N` from `you.marks` / shop snapshot / mock wallet. Never local debit. |
| BUY | Enabled only when `you.marks` ≥ that row's price. New `clientBuyId` UUID. |
| OWNED | Visual toggle for suit SKUs. Poster is wall art when owned (buy auto-equips). |
| Equip | Poster uses existing `POST /shop/equip`. Not suit chrome — operative click skips it. |

## Mock vs LIVE

| Mode | Shop |
| --- | --- |
| Editor MOCK | `MockMatchServer.get_shop` / `buy_shop` ledger. Three SKUs. Prices 50 / 100 / 150. |
| LIVE + catalog lags | Merge appends mock poster so the third row still renders. BUY posts LIVE (`unknown_item` until Coder +1). |
| LIVE + Coder +1 SKU | Prefer LIVE items (name / price from catalog). |

## Demo (mock)

1. Hideout MOCK. Chip **MARKS ★24**. All three ARMORY BUY buttons **disabled / insufficient**.
2. Seed ★200. BUY poster → snapshot ★50. Copy **OWNED · visual only** / **Wearing this · visual only**. Toy-spy poster on the wall.
3. Replay same `clientBuyId` → still ★50.
4. BUY ghillie → snapshot ★0. Poster stays on the wall. Equip is chrome only — start a match: Attack / Recon / UAV math unchanged.

## Out of this slice

IAP / Chips · fourth sink · combat skins · art pass · ranked. LIVE player token is in-slice (`POST /players`).

## Coder blocker

LIVE `GET /shop` (2026-09-20) still lists only `skin_hideout_stub` + `skin_bandana_stub`. Add `decor_poster_stub` · HIDEOUT POSTER · ★150 · kind `decor` (or `part` / `skin`) so S3.1–S3.3 can PASS LIVE. Client merge + mock already ship the third row.
