# Marks sink stub — hideout ARMORY

Client half of the hideout cosmetic shop. Godot **displays only**. Hard: **no P2W**, **no combat / spot / hit delta**, **no IAP**. Cosmetic chrome only. `itemId` **`skin_hideout_stub`**, price **★50**.

Editor Play stays MOCK (`use_live_api=false`). Smoke path wires `LiveMatchClient.get_shop` + `buy_shop` at `https://glassline-api.vercel.app`.

## LIVE S1–S3 (2026-09-19)

**Base:** `https://glassline-api.vercel.app`  
**Contract:** `/docs/contract` · GET `/shop` public catalog · POST `/shop/buy` `{ itemId, clientBuyId }` + `Authorization: Bearer <joinToken>`

Probed catalog:

```json
{"items":[{"id":"skin_hideout_stub","name":"Hideout Skin (stub)","price":50,"kind":"skin"}]}
```

`GET /shop` is **catalog-only** (no `you.marks`). Buy 200 shape is `{ ok, you: { marks }, purchaseId, item }`. 402 is `{ error, code: "insufficient_marks", you: { marks } }`. Client binds that `you.marks` — **never `marks -=`**.

| Gate | Result | Evidence |
| --- | --- | --- |
| **S1** buy OK · `you.marks` −50 | **FAIL LIVE** | After PvP kill `m_5593d016bd5c48d6ab208ceb3b9b5f8d` wallet **0→25**. `POST /shop/buy` `{ itemId: skin_hideout_stub, clientBuyId: 2a23c978-… }` → **HTTP 402** `{ code: insufficient_marks, you.marks: 25 }`. No debit. Coder priced ★50 as 2× kill, but each `POST /matches` / `POST /jobs` mints a **new `playerId` at 0**. Max one-token earn is **+25**. Client cannot invent Marks. |
| **S2** insufficient | **PASS LIVE** | Fresh join `you.marks=0`. Buy → **HTTP 402** `{ code: insufficient_marks, you.marks: 0 }`. Replay same `clientBuyId` `f1ff09f7-…` still **402 / 0**. Godot `LiveMatchClient.buy_shop` + `apply_shop`: polluted cache 999 → **0** (not 949). `LIVE_SHOP_LOOP_OK`. |
| **S3** same `clientBuyId` twice | **FAIL LIVE** (no first debit) | Replay of S1 id `2a23c978-…` → **402** `{ you.marks: 25 }` again. No `purchaseId`, no second (or first) ledger row. Mock + client-shape replay still one bind (headless). |

HTTP log: [`artifacts/live_shop_smoke.txt`](live_shop_smoke.txt)  
Godot bind: [`artifacts/live_shop_godot.txt`](live_shop_godot.txt) · `LIVE_SHOP_LOOP_OK`

```bash
GLASSLINE_API_BASE=https://glassline-api.vercel.app python3 tools/live_shop_smoke.py
GLASSLINE_USE_LIVE_API=1 godot --headless --path . res://tools/live_shop_test.tscn
godot --headless --path . -s res://tools/headless_loop_test.gd   # HEADLESS_LOOP_OK
```

**Coder unblock for S1/S3:** persist `playerId` / Marks across matches (or seed ≥50 on a join token) so one Bearer can hold ★50. Then the same smoke expects **200** `{ you.marks: N-50, purchaseId }` and a replay **200** with the same `purchaseId` / same balance.

## Hard rule

## Hard rule

Never `marks -=` (or `marks +=`) on the client as truth. Hideout BUY posts `{ itemId, clientBuyId }` and rebinds `you.marks` from the returned snapshot only. `ClientSession.marks` is a display cache.

## GD stamped catalog (2026-09-18)

One stub SKU. Constant is `Contract.SHOP_STUB_PRICE` — swap here if GD restamps (Coder catalog locks the same number).

| Field | Value |
| --- | --- |
| `itemId` | `skin_hideout_stub` (LIVE `id`; buy body `itemId`) |
| name | hideout chrome `GHILLIE RECOLOR` · LIVE catalog `Hideout Skin (stub)` |
| kind | `skin` (hideout plate only) |
| **price** | **★50 Marks** |
| combat | **false** — no hit / exposure / recon / UAV change |

Default mock wallet stays `MOCK_WALLET_STUB` **★24**, so first BUY is `insufficient_marks` until the player earns (or a capture/test seeds the mock ledger).

## LIVE shape (Coder lock 2026-09-19)

| Method | Path | Body / notes |
| --- | --- | --- |
| GET | `/shop` | `{ items: ShopItem[] }` public. `ShopItem = { id, name, price, kind }`. No `you.marks`. |
| POST | `/shop/buy` | `{ itemId, clientBuyId }` + Bearer joinToken → `{ ok, you: { marks }, purchaseId, item }`. **Idempotent on `(playerId, clientBuyId)`.** |
| 402 | | `{ error, code: "insufficient_marks", you: { marks } }` |
| 401 / 400 / 404 | | missing bearer · `invalid_buy_body` · `unknown_item` |

Parsers accept `snapshot.you.marks` · top-level `marks` · `wallet.marks`, plus buy `item.id` / `itemId`, `owned` / `you.owned` / `you.cosmetics` and `equipped`.

Auth: `Authorization: Bearer <join token>` from `POST /matches/:id/join` or `POST /jobs`. Dedicated out-of-match player token is deferred (Coder).

## S1–S5 mapping

| Gate | Client surface | Behavior |
| --- | --- | --- |
| **S1** Catalog + shop row | Hideout **ARMORY** row (lobby-canon language) | One stub: GHILLIE RECOLOR · ★50 · BUY. `GET /shop` when live; mock catalog + `Contract.SHOP_STUB_PRICE` when editor / LIVE 404. |
| **S2** Buy + Marks bind | BUY → `POST /shop/buy` | New UUID `clientBuyId` every click. Chip refreshes from snapshot `you.marks` only. Replay same id does not debit twice (mock receipts). |
| **S3** Insufficient | BUY at ★24 vs ★50 | Reject `insufficient_marks`. Toast + row copy. Chip stays ★24. |
| **S4** Equip | EQUIP / click operative | Visual only: `lobby-ghillie.jpg` vs `lobby-canon.jpg`. No match action, no exposure/hit/UAV change. Unequip returns teal jacket. |
| **S5** Stills | `artifacts/ux/` | `shop_row.png` (row + ★50 + MARKS chip). `shop_post_buy_marks.png` (mock seed ★80 → snapshot ★30 after buy, ghillie on). |

## Client surfaces

| Surface | Behavior |
| --- | --- |
| ARMORY row | Always on the hideout, above LOADOUT / PLAY / JOBS. LOADOUT focuses it. |
| Marks chip | `MARKS ★N` from `you.marks` / shop snapshot / mock wallet. Never local debit. |
| BUY | New `clientBuyId` UUID. Apply shop snapshot. |
| Insufficient | `Not enough Marks.` / `insufficient_marks`. Balance unchanged. |
| EQUIP / EQUIPPED | Owned only. Mock persists equipped; LIVE is local visual until Coder adds equip. |
| Operative click | Equip toggle if owned; else “Buy Ghillie Recolor in ARMORY”. |

## Mock vs LIVE

| Mode | Shop |
| --- | --- |
| Editor MOCK (`use_live_api=false`, default) | `MockMatchServer.get_shop` / `buy_shop` ledger. Price **50**. |
| LIVE + `/shop` 404 | Row still renders from `Contract.shop_catalog_stub`. BUY posts LIVE and shows `LIVE shop not ready`. No local debit. |
| LIVE smoke / F2 | `LiveMatchClient.get_shop` / `buy_shop`. Catalog `id` → `itemId`. Chip binds buy/402 `you.marks` only. |

## Demo (mock)

1. Hideout MOCK. Chip **MARKS ★24**. ARMORY row **GHILLIE RECOLOR ★50 BUY**.
2. BUY → reject `insufficient_marks`, chip still ★24.
3. Earn (or test seed). BUY with a new UUID → snapshot `you.marks` (e.g. 80→30). Chip **★30**. Ghillie plate on.
4. Replay same `clientBuyId` → same snapshot, still ★30.
5. EQUIPPED / click operative toggles the plate. Start a match: Attack / Recon / UAV math unchanged.

Headless: `godot --headless --path . -s res://tools/headless_loop_test.gd` → `HEADLESS_LOOP_OK` (`_shop_case`).

Captures: `godot --resolution 1280x720 -- --capture-shop` and `--capture-shop-buy`.

## Out of this slice

Persistent LIVE player token / wallet seed (Coder) · IAP / Chips · extra SKUs · combat skins · ranked.
