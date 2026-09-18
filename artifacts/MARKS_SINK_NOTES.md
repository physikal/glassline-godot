# Marks sink stub — hideout ARMORY (client assumptions)

Client half of the hideout cosmetic shop. Godot **displays only**. The mock may simulate a Marks debit. LIVE remains source of truth once Coder ships `GET /shop` + `POST /shop/buy`.

Hard: **no P2W**, **no combat delta**, **no IAP**. Cosmetic chrome only.

Probed 2026-09-18 against `https://glassline-api.vercel.app`: **`GET /shop` 404**, **`POST /shop/buy` 404**. Editor default is MOCK. `LiveMatchClient.get_shop` / `buy_shop` / `equip_cosmetic` are ready for Coder.

## Hard rule

Never `marks -=` (or `marks +=`) on the client as truth. Hideout BUY posts `{ itemId, clientBuyId }` and rebinds `you.marks` from the returned snapshot only. `ClientSession.marks` is a display cache.

## GD stamped catalog (2026-09-18)

One stub SKU. Constant is `Contract.SHOP_STUB_PRICE` — swap here if GD restamps (Coder catalog locks the same number).

| Field | Value |
| --- | --- |
| `itemId` | `ghillie_recolor` |
| name | `GHILLIE RECOLOR` |
| kind | `recolor` (hideout plate only) |
| **price** | **★50 Marks** |
| combat | **false** — no hit / exposure / recon / UAV change |

Default mock wallet stays `MOCK_WALLET_STUB` **★24**, so first BUY is `insufficient_marks` until the player earns (or a capture/test seeds the mock ledger).

## Assumed LIVE shape (Coder)

| Method | Path | Body / notes |
| --- | --- | --- |
| GET | `/shop` | Catalog + `you.marks` + owned/equipped. No match required. |
| POST | `/shop/buy` | `{ itemId, clientBuyId? }` → snapshot with debited `you.marks` + owned/equipped. **Idempotent on `clientBuyId`.** |
| Reject | | `insufficient_marks` (also `already_owned` / `unknown_item`). Balance unchanged. |

Parsers accept `snapshot.you.marks` · top-level `marks` · `wallet.marks`, plus `owned` / `you.owned` / `you.cosmetics` and `equipped`.

Auth: client sends `Authorization: Bearer <join token>` when a match token exists. Hideout shop may later use an account token — Coder stamp.

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
| LIVE + catalog shipped | `LiveMatchClient.get_shop` / `buy_shop`. Bind `you.marks` from the response. |

## Demo (mock)

1. Hideout MOCK. Chip **MARKS ★24**. ARMORY row **GHILLIE RECOLOR ★50 BUY**.
2. BUY → reject `insufficient_marks`, chip still ★24.
3. Earn (or test seed). BUY with a new UUID → snapshot `you.marks` (e.g. 80→30). Chip **★30**. Ghillie plate on.
4. Replay same `clientBuyId` → same snapshot, still ★30.
5. EQUIPPED / click operative toggles the plate. Start a match: Attack / Recon / UAV math unchanged.

Headless: `godot --headless --path . -s res://tools/headless_loop_test.gd` → `HEADLESS_LOOP_OK` (`_shop_case`).

Captures: `godot --resolution 1280x720 -- --capture-shop` and `--capture-shop-buy`.

## Out of this slice

LIVE catalog implementation (Coder) · IAP / Chips · extra SKUs · combat skins · ranked.
