# Marks sink stub — hideout ARMORY

Client half of the hideout cosmetic shop. Godot **displays only**. Hard: **no P2W**, **no combat / spot / hit delta**, **no IAP**. Cosmetic chrome only. `itemId` **`skin_hideout_stub`**, price **★50**.

Editor Play stays MOCK (`use_live_api=false`). Smoke path wires `LiveMatchClient.get_shop` + `buy_shop` at `https://glassline-api.vercel.app`.

## LIVE S1–S3 re-smoke after Coder persist (2026-09-19)

**Base:** `https://glassline-api.vercel.app`  
**Contract:** `/docs/contract` · `POST /players` durable token · GET `/shop` public catalog · POST `/shop/buy` `{ itemId, clientBuyId }` + `Authorization: Bearer <playerToken>`

Client: `LiveMatchClient.ensure_player` keeps the returned `token` and sends it on `POST /matches`, `POST /jobs`, join (seat A), and `POST /shop/buy`. Match actions still use the join token. Dummy seat B stays anonymous (same player cannot occupy both seats). Hideout + smoke **never `marks -=`**.

Probed catalog:

```json
{"items":[{"id":"skin_hideout_stub","name":"Hideout Skin (stub)","price":50,"kind":"skin"}]}
```

`GET /shop` is **catalog-only** (no `you.marks`). Buy 200 shape is `{ ok, you: { marks }, purchaseId, item }`. 402 is `{ error, code: "insufficient_marks", you: { marks } }`. Client binds that `you.marks`.

| Gate | Result | Evidence |
| --- | --- | --- |
| **S1** buy OK · `you.marks` −50 | **PASS LIVE** | Player `p_1822026a24804347865613062afbf9bf`. Kill `m_ad2f55e99f454ef68955f6b940a97d87` **0→25**, kill `m_9888c28cf8bb45ac8f314491b5f6b858` **25→50**. `POST /shop/buy` `{ itemId: skin_hideout_stub, clientBuyId: 3d16a2e7-… }` → **HTTP 200** `{ you.marks: 0, purchaseId: pur_ea8bc0eba29f448c837ef5ea80a0a023 }`. Godot same path: `p_d768ef548e24455cb79124914d7acb67` / `m_09e4ee9b33d041a68f0f1d93a3f51780` ★50→0 `pur_24ca77532bed4497ba6765a29b1eb726`. Polluted cache 999 rebound to **0** (not 949). |
| **S2** insufficient | **PASS LIVE** | Fresh `POST /players` `p_982ba30ce4fd41659f28b4a40ee7faa7` ★0. Buy → **HTTP 402** `{ code: insufficient_marks, you.marks: 0 }`. Replay `clientBuyId` `fc8fba57-…` still **402 / 0**. Godot `LIVE_SHOP_S2_OK marks 0→0`. |
| **S3** same `clientBuyId` twice | **PASS LIVE** | Replay `3d16a2e7-…` → **HTTP 200** same `purchaseId` `pur_ea8bc0eba29f448c837ef5ea80a0a023`, `you.marks` still **0**. Godot replay same `pur_24ca77532bed4497ba6765a29b1eb726`. |

HTTP log: [`artifacts/live_shop_smoke.txt`](live_shop_smoke.txt) · `LIVE_SHOP_SMOKE_OK`  
Godot bind: [`artifacts/live_shop_godot.txt`](live_shop_godot.txt) · `LIVE_SHOP_LOOP_OK`  
Mock: `HEADLESS_LOOP_OK` (price ★50, persist token survives `reset_match`, no local `marks -=`).

```bash
GLASSLINE_API_BASE=https://glassline-api.vercel.app python3 tools/live_shop_smoke.py
GLASSLINE_USE_LIVE_API=1 godot --headless --path . res://tools/live_shop_test.tscn
godot --headless --path . -s res://tools/headless_loop_test.gd   # HEADLESS_LOOP_OK
```

Previous fail (pre-persist, join-token wallets): each `POST /matches` minted a new `playerId` at 0, so one kill left ★25 and buy returned **402**. Reusing `POST /players` stacks two kill wins on one ledger.

## LIVE S1–S3 (2026-09-19, pre-persist — superseded)

**Base:** `https://glassline-api.vercel.app`  
**Contract (then):** GET `/shop` · POST `/shop/buy` + joinToken (no durable player)

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
| POST | `/players` | `{ }` → `{ playerId, token, marks }`. Persist `token`. |
| POST | `/shop/buy` | `{ itemId, clientBuyId }` + Bearer **player** token → `{ ok, you: { marks }, purchaseId, item }`. **Idempotent on `(playerId, clientBuyId)`.** Join token still maps the same `playerId` if one exists. |
| 402 | | `{ error, code: "insufficient_marks", you: { marks } }` |
| 401 / 400 / 404 | | missing bearer · `invalid_buy_body` · `unknown_item` |

Parsers accept `snapshot.you.marks` · top-level `marks` · `wallet.marks`, plus buy `item.id` / `itemId`, `owned` / `you.owned` / `you.cosmetics` and `equipped`.

Auth: prefer `Authorization: Bearer <player token>` from `POST /players` on create / join / jobs / shop. Match actions still use the join token. Dummy seat B is anonymous.

## S1–S5 mapping

| Gate | Client surface | Behavior |
| --- | --- | --- |
| **S1** Catalog + shop row | Hideout **ARMORY** row (lobby-canon language) | One stub: GHILLIE RECOLOR · ★50 · BUY. `GET /shop` when live; mock catalog + `Contract.SHOP_STUB_PRICE` when editor / LIVE 404. |
| **S2** Buy + Marks bind | BUY → `POST /shop/buy` | New UUID `clientBuyId` every click. Chip refreshes from snapshot `you.marks` only. Replay same id does not debit twice (mock receipts). |
| **S3** Insufficient | ★24 vs ★50 | Row BUY is **disabled / insufficient** (`Not enough Marks.`). If posted, reject `insufficient_marks`. Chip stays ★24. |
| **S4** Equip | OWNED / click operative | Visual only: `lobby-ghillie.jpg` vs `lobby-canon.jpg`. Copy is `OWNED · visual only` (no stowed / EQUIPPED split). No match action, no exposure/hit/UAV change. |
| **S5** Stills | `artifacts/ux/` | `shop_row.png` (disabled BUY at MARKS ★24 + ★50 stamp). `shop_post_buy_marks.png` (mock seed ★80 → snapshot ★30 after buy, ghillie on, OWNED). |

## Client surfaces

| Surface | Behavior |
| --- | --- |
| ARMORY row | Always on the hideout, above LOADOUT / PLAY / JOBS. LOADOUT focuses it. |
| Marks chip | `MARKS ★N` from `you.marks` / shop snapshot / mock wallet. Never local debit. |
| BUY | Enabled only when `you.marks` ≥ ★50. New `clientBuyId` UUID. Apply shop snapshot. |
| Insufficient | Disabled BUY + `Not enough Marks.` Server still rejects `insufficient_marks`. Balance unchanged. |
| OWNED | Owned chrome. Click toggles the plate. Mock persists equipped; LIVE is local visual until Coder adds equip. Copy is always `OWNED · visual only`. |
| Operative click | Plate toggle if owned; else “Buy Ghillie Recolor in ARMORY”. |

## Mock vs LIVE

| Mode | Shop |
| --- | --- |
| Editor MOCK (`use_live_api=false`, default) | `MockMatchServer.get_shop` / `buy_shop` ledger. Price **50**. |
| LIVE + `/shop` 404 | Row still renders from `Contract.shop_catalog_stub`. BUY posts LIVE and shows `LIVE shop not ready`. No local debit. |
| LIVE smoke / F2 | `LiveMatchClient.get_shop` / `buy_shop`. Catalog `id` → `itemId`. Chip binds buy/402 `you.marks` only. |

## Demo (mock)

1. Hideout MOCK. Chip **MARKS ★24**. ARMORY row **GHILLIE RECOLOR ★50** with **disabled / insufficient BUY**.
2. BUY is not an active CTA at ★24. If posted, reject `insufficient_marks`, chip still ★24.
3. Earn (or test seed). BUY with a new UUID → snapshot `you.marks` (e.g. 80→30). Chip **★30**. Ghillie plate on. Copy **OWNED · visual only**.
4. Replay same `clientBuyId` → same snapshot, still ★30.
5. OWNED / click operative toggles the plate. Start a match: Attack / Recon / UAV math unchanged.

Headless: `godot --headless --path . -s res://tools/headless_loop_test.gd` → `HEADLESS_LOOP_OK` (`_shop_case`).

Captures: `godot --resolution 1280x720 -- --capture-shop` and `--capture-shop-buy`.

## P2 UX (2026-09-19)

After S5 PASS: default mock ★24 vs stamped ★50 no longer shows an active blue BUY. `shop_row.png` is the insufficient state. Post-buy / toggle copy is the same `OWNED · visual only` line — no “stowed” vs EQUIPPED split. Price, snapshot Marks bind, and `LiveMatchClient.get_shop` / `buy_shop` unchanged. No combat delta.

## Out of this slice

IAP / Chips · extra SKUs · combat skins · ranked. LIVE player token is in-slice (`POST /players`).
