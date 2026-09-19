# Marks sink 2 — BANDANA RECOLOR

Client half of [Slice ticket — Second Marks sink](https://www.notion.so/3e04dabdb33981af946ff84cbeca5d03).  
Same spine as ghillie ★50: `GET /shop` + `POST /shop/buy` `{ itemId, clientBuyId }` + durable player Bearer. **Catalog +1 SKU**, not a new endpoint family.

Hard: **no P2W** · **no second currency** · **no combat / spot / hit delta** · **no mil-sim art** · **no IAP**. Cosmetic chrome only.

Editor Play stays MOCK (`use_live_api=false`). Smoke path wires `LiveMatchClient.get_shop` + `buy_shop` at `https://glassline-api.vercel.app`.

## GD stamped catalog (2026-09-19)

| Field | Sink 1 | Sink 2 |
| --- | --- | --- |
| `itemId` | `skin_hideout_stub` | **`skin_bandana_stub`** |
| name | GHILLIE RECOLOR | **BANDANA RECOLOR** |
| kind | `skin` | `skin` |
| **price** | ★50 | **★100** (2× first sink) |
| combat | false | **false** |

Constants: `Contract.SHOP_BANDANA_ITEM_ID` / `SHOP_BANDANA_PRICE`. Swap here if GD restamps (Coder catalog locks the same number).

## LIVE catalog (probed 2026-09-19)

**Base:** `https://glassline-api.vercel.app`

```json
{"items":[{"id":"skin_hideout_stub","name":"Hideout Skin (stub)","price":50,"kind":"skin"}]}
```

LIVE still has **one** SKU. Client **prefers LIVE when Coder lists +1** (`skin_bandana_stub`). Until then `MatchAPI.get_shop` merges the mock bandana row so ARMORY always shows two lines. BUY for bandana still posts LIVE (`unknown_item` until Coder lands the SKU). Hideout + smoke **never `marks -=`**.

| Gate | Result | Evidence |
| --- | --- | --- |
| **S2.1** buy OK · `you.marks` −100 | **PENDING LIVE** | Catalog missing `skin_bandana_stub`. Mock: seed ★180 → buy → snapshot ★80 `HEADLESS_LOOP_OK` `_shop_sink2_case`. |
| **S2.2** insufficient | **PENDING LIVE** | Same. Mock ★24 vs ★100 → `insufficient_marks`, chip stays ★24. BUY disabled. |
| **S2.3** same `clientBuyId` twice | **PENDING LIVE** | Mock receipt keyed by `clientBuyId` — one debit. |
| **S2.4** equip chrome-only | **PASS mock** | Bandana wash on canon plate. Attack / Recon / UAV table unchanged (`RECON_BASE` 0.35, PvP kill ★25). |
| **S2.5** stills | **PASS mock** | [`ux/armory_two_row.png`](ux/armory_two_row.png) · [`ux/armory_bandana_post_buy.png`](ux/armory_bandana_post_buy.png) |

```bash
GLASSLINE_API_BASE=https://glassline-api.vercel.app python3 tools/live_shop_sink2_smoke.py
# expect LIVE_SHOP_SINK2_PENDING until Coder adds skin_bandana_stub ★100
godot --headless --path . -s res://tools/headless_loop_test.gd   # HEADLESS_LOOP_OK
godot --resolution 1280x720 -- --capture-armory-two-row
godot --resolution 1280x720 -- --capture-armory-bandana-buy
```

**Coder unblock for S2.1–S2.3:** add `{ id: "skin_bandana_stub", name: "BANDANA RECOLOR", price: 100, kind: "skin" }` to `GET /shop`. Same `POST /shop/buy` + durable Bearer. Then the smoke earns ★100 (four PvP kills) and expects **200** `{ you.marks: N-100, purchaseId }` and a replay **200** with the same `purchaseId`.

## Hard rule

Never `marks -=` (or `marks +=`) on the client as truth. Hideout BUY posts `{ itemId, clientBuyId }` and rebinds `you.marks` from the returned snapshot only. `ClientSession.marks` is a display cache. A LIVE 200 that only returns `item` **merges** that id into `owned` — it does not wipe ghillie.

## LIVE shape (same as sink 1)

| Method | Path | Body / notes |
| --- | --- | --- |
| GET | `/shop` | `{ items: ShopItem[] }` public. Prefer LIVE when bandana is present. |
| POST | `/players` | `{ }` → `{ playerId, token, marks }`. Persist `token`. |
| POST | `/shop/buy` | `{ itemId, clientBuyId }` + Bearer **player** token → `{ ok, you: { marks }, purchaseId, item }`. **Idempotent on `(playerId, clientBuyId)`.** |
| 402 | | `{ error, code: "insufficient_marks", you: { marks } }` |

## S2.1–S2.5 mapping

| Gate | Client surface | Behavior |
| --- | --- | --- |
| **S2.1** Buy at ★100 | ARMORY row 2 · BANDANA RECOLOR | New UUID `clientBuyId`. Chip refreshes from snapshot `you.marks` only (e.g. 180→80). |
| **S2.2** Insufficient | ★24 vs ★100 | Row BUY **disabled / Not enough Marks.** If posted, reject `insufficient_marks`. Chip unchanged. |
| **S2.3** Replay | same `clientBuyId` | One debit. Mock receipts + LIVE `(playerId, clientBuyId)`. |
| **S2.4** Equip | OWNED / click operative | Chrome only: rust wash on the canon plate (`Chrome.BANDANA_WASH`). No new texture. Copy `OWNED · visual only`. No match action. |
| **S2.5** Stills | `artifacts/ux/` | `armory_two_row.png` (both rows at ★24). `armory_bandana_post_buy.png` (seed ★180 → snapshot ★80, bandana OWNED). |

## Client surfaces

| Surface | Behavior |
| --- | --- |
| ARMORY | Two rows above LOADOUT / PLAY / JOBS. LOADOUT focuses it. JOBS still hides ARMORY. |
| Row 1 | GHILLIE RECOLOR ★50 — unchanged first sink. |
| Row 2 | BANDANA RECOLOR ★100 — same BUY / insufficient / OWNED states. |
| Marks chip | `MARKS ★N` from `you.marks` / shop snapshot / mock wallet. Never local debit. |
| BUY | Enabled only when `you.marks` ≥ that row's price. New `clientBuyId` UUID. |
| OWNED | Visual toggle for that SKU. One equipped at a time. Operative click cycles owned chrome. |
| Equip | Ghillie → `lobby-ghillie.jpg`. Bandana → canon plate + wash. Neither → canon plate. |

## Mock vs LIVE

| Mode | Shop |
| --- | --- |
| Editor MOCK | `MockMatchServer.get_shop` / `buy_shop` ledger. Both SKUs. Prices 50 / 100. |
| LIVE + catalog lags | Merge appends mock bandana so the second row still renders. BUY posts LIVE. |
| LIVE + Coder +1 SKU | Prefer LIVE items (name / price from catalog). |

## Demo (mock)

1. Hideout MOCK. Chip **MARKS ★24**. Both ARMORY BUY buttons **disabled / insufficient**.
2. Seed ★180. BUY bandana → snapshot ★80. Copy **OWNED · visual only**. Rust wash on.
3. Replay same `clientBuyId` → still ★80.
4. BUY ghillie → snapshot ★30. Both owned. Equip is chrome only — start a match: Attack / Recon / UAV math unchanged.

## Out of this slice

IAP / Chips · third sink · combat skins · art pass · ranked. LIVE player token is in-slice (`POST /players`).
