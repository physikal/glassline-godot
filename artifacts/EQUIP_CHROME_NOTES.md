# Equip owned chrome

Client half of [Slice ticket — Equip owned chrome](https://www.notion.so/3e04dabdb3398112821bec3c778e5583).  
Completes the Marks sink fantasy: owned SKUs can **EQUIP** so hideout operative + exposure doll wear the same chrome. **Not** a new SKU or power.

Hard: **zero** Attack / Recon / UAV / hit / spot / exposure delta · **no** new SKUs · **no** IAP · **no** mil-sim.

Editor Play stays MOCK (`use_live_api=false`). LIVE hideout binds `GET /shop/me`. `LiveMatchClient.equip_cosmetic` posts `POST /shop/equip`.

## Spine

| Piece | Choice |
| --- | --- |
| State | Server `you.equippedSkinId` |
| API | `POST /shop/equip` `{ itemId }` \| `{ itemId: null }` + durable player Bearer. `GET /shop/me` wallet bind. |
| Snapshot | `you.equippedSkinId` — client never invents the id |
| Client | ARMORY OWNED → EQUIP / EQUIPPED; hideout + doll bind the same id |
| Combat | Unchanged |

Idempotent same-id equip = no-op OK. Marks untouched.

## LIVE smoke (2026-09-19) — **PASS** `LIVE_SHOP_EQUIP_OK`

**Base:** `https://glassline-api.vercel.app`  
**Player:** `p_de36446288d04e7fae37da98072e51c4`

| Call | Result |
| --- | --- |
| `GET /shop/me` empty | `{ you: { marks: 0, equippedSkinId: null }, owned: [] }` |
| `POST /shop/equip` unowned | **403** `{ error/code: not_owned, you.equippedSkinId: null }` |
| Buy ghillie | `{ ok, you: { marks: 0, equippedSkinId: "skin_hideout_stub" } }` |
| Equip ghillie | **200** `{ ok, you: { marks: 0, equippedSkinId: "skin_hideout_stub" } }` |
| `GET /shop/me` after equip | `{ you: { marks: 0, equippedSkinId: "skin_hideout_stub" }, owned: ["skin_hideout_stub"] }` |
| Same-id re-equip | **200** no-op, marks still 0 |
| Buy bandana | last-buy auto-equip `skin_bandana_stub` |
| Swap → ghillie | `equippedSkinId: "skin_hideout_stub"`, marks 0 |
| Unequip `null` | `equippedSkinId: null`, marks 0 |
| Re-equip bandana | `equippedSkinId: "skin_bandana_stub"`, owns both |

HTTP log: [`artifacts/live_shop_equip_smoke.txt`](live_shop_equip_smoke.txt)

## E1–E6

| Gate | Result | Evidence |
| --- | --- | --- |
| **E1** server set | **PASS LIVE** | Unowned 403 `not_owned`. Equip sets `you.equippedSkinId=skin_hideout_stub`. `/shop/me` agrees. Marks untouched. |
| **E2** hideout | **PASS mock** | Ghillie plate / bandana wash from snapshot id. Still [`ux/equip_owned_hideout.png`](ux/equip_owned_hideout.png). |
| **E3** doll | **PASS mock** | Exposure doll shirt / bandana wash uses the same id. [`ux/equip_exposure_doll.png`](ux/equip_exposure_doll.png). |
| **E4** swap / unequip | **PASS LIVE** | Swap ghillie → unequip null → re-equip bandana. Marks chip 0 throughout. Owns both SKUs. |
| **E5** combat parity | **PASS LIVE** | Bare `m_dd3010d155114a2392bd123276ce615c` vs worn `m_188d5e616d064554ae6da20ae8ea4b06` (`equippedSkinId=skin_hideout_stub`). Miss `hit=false` / no Hot. Kill `hit=true` `kill=true` `status=ended` `marks +25`. |
| **E6** UX copy | **PASS mock** | BUY vs EQUIP vs EQUIPPED. Status `OWNED · visual only` / `Wearing this · visual only`. |

```bash
GLASSLINE_API_BASE=https://glassline-api.vercel.app python3 tools/live_shop_equip_smoke.py
godot --headless --path . -s res://tools/headless_loop_test.gd   # HEADLESS_LOOP_OK
godot --resolution 1280x720 -- --capture-equip-hideout
godot --resolution 1280x720 -- --capture-equip-doll
```

## Field names (align to Coder)

| Wire | Client |
| --- | --- |
| `you.equippedSkinId` | Canonical. `Shop._read_equipped` / `Snapshot.you_equipped_skin_id` |
| `you.equipped` | Fallback (mock last-buy + older bags) |
| `itemId` on POST | `skin_hideout_stub` / `skin_bandana_stub` / `null` |
| `not_owned` | Unowned equip reject **403** |

Parsers also accept top-level `equippedSkinId` / `equipped` and `you.cosmetics`.

## ARMORY UX (cozy toy-spy)

| Row state | Button | Status |
| --- | --- | --- |
| Unowned, can buy | **BUY** (blue) | — |
| Unowned, ★ short | **BUY** disabled | `Not enough Marks.` |
| Owned, not wearing | **EQUIP** (teal) | `OWNED · visual only` |
| Wearing | **EQUIPPED** (gold) | `Wearing this · visual only` |

EQUIPPED click unequips. Operative click still cycles owned chrome (including off). One skin at a time. Copy stays hideout language — no stowed / rack / mil-sim.

## Bind

| Surface | Chrome |
| --- | --- |
| Hideout operative | `equippedSkinId == skin_hideout_stub` → `lobby-ghillie.jpg`. Bandana → canon plate + rust wash. Empty → canon plate. |
| Exposure doll | Same id: ghillie leafy shirt / bandana stripe / default teal. Exposure % is still server `you.exposurePct`. |
| Marks chip | `you.marks` only. Equip never debits. |

## Mock vs LIVE

| Mode | Equip |
| --- | --- |
| Editor MOCK | `MockMatchServer.equip_cosmetic`. Snapshot includes `you.equippedSkinId`. |
| LIVE | `GET /shop/me` + `POST /shop/equip`. Apply snapshot only. Never invent the id. |

Buy still auto-equips last SKU (Coder `shop_equipped` last-buy). Equip is the explicit swap / unequip.

## E5 combat table (LIVE, unchanged)

| Field | Bare `m_dd3010d155114a2392bd123276ce615c` | Ghillie `m_188d5e616d064554ae6da20ae8ea4b06` |
| --- | --- | --- |
| Attack miss `hit` | false | false |
| Attack miss invents Hot | no | no |
| Attack kill `hit` / `kill` | true / true | true / true |
| Match `status` | ended | ended |
| Wallet after kill | +25 | +25 |
| `RECON_BASE` | 0.35 | 0.35 |
| UAV / spot math | unchanged | unchanged |

## Out of this slice

New SKUs · IAP · combat gear floor · ranked.
