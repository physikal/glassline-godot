# Equip owned chrome

Client half of [Slice ticket — Equip owned chrome](https://www.notion.so/3e04dabdb3398112821bec3c778e5583).  
Completes the Marks sink fantasy: owned SKUs can **EQUIP** so hideout operative + exposure doll wear the same chrome. **Not** a new SKU or power.

Hard: **zero** Attack / Recon / UAV / hit / spot / exposure delta · **no** new SKUs · **no** IAP · **no** mil-sim.

Editor Play stays MOCK (`use_live_api=false`). `LiveMatchClient.equip_cosmetic` posts `POST /shop/equip` when LIVE.

## Spine

| Piece | Choice |
| --- | --- |
| State | Server `you.equippedSkinId` (Coder `shop_equipped.item_id` last-buy stub already exists) |
| API | `POST /shop/equip` `{ itemId }` + durable player Bearer → snapshot. `itemId: null` unequips. Reject if not owned. |
| Snapshot | `you.equippedSkinId` — client never invents the id |
| Client | ARMORY OWNED → EQUIP / EQUIPPED; hideout + doll bind the same id |
| Combat | Unchanged |

Idempotent same-id equip = no-op OK. Marks untouched.

## LIVE probe (2026-09-19)

**Base:** `https://glassline-api.vercel.app`

```
POST /shop/equip  { "itemId": "skin_hideout_stub" }  Authorization: Bearer <playerToken>
→ HTTP 404 text/plain
```

Coder already writes `shop_equipped` on buy (last-buy). There is **no** public equip route and match snapshots do **not** yet include `you.equippedSkinId`.

**Coder unblock:** `POST /shop/equip` `{ itemId }` \| `{ itemId: null }` + player Bearer → `{ ok, you: { marks, owned, equippedSkinId } }`. Reject `not_owned`. Same id = 200 no-op. Marks unchanged.

Until then: mock persists equip; LIVE 404 falls back to local chrome with toast `LIVE /shop/equip pending Coder`. Client method is ready.

## E1–E6

| Gate | Result | Evidence |
| --- | --- | --- |
| **E1** server set | **PASS mock** · **LIVE pending** | Mock `equip_cosmetic` returns `you.equippedSkinId`. Same-id no-op. Unowned → `not_owned`. LIVE `POST /shop/equip` **404**. |
| **E2** hideout | **PASS mock** | Ghillie plate / bandana wash from snapshot id. Still [`ux/equip_owned_hideout.png`](ux/equip_owned_hideout.png). |
| **E3** doll | **PASS mock** | Exposure doll shirt / bandana wash uses the same id. [`ux/equip_exposure_doll.png`](ux/equip_exposure_doll.png). |
| **E4** swap / unequip | **PASS mock** | EQUIP other owned SKU; EQUIPPED click unequips (`itemId` empty / null). Marks chip unchanged. |
| **E5** combat parity | **PASS mock** | Miss `hit=false` + kill `marksDelta +25` identical with/without equip. `RECON_BASE` 0.35. |
| **E6** UX copy | **PASS mock** | BUY vs EQUIP vs EQUIPPED. Status `OWNED · visual only` / `Wearing this · visual only`. |

HTTP log: [`artifacts/live_shop_equip_smoke.txt`](live_shop_equip_smoke.txt) · `LIVE_SHOP_EQUIP_PENDING`  
Mock: `HEADLESS_LOOP_OK` (`_equip_chrome_case`).

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
| `not_owned` | Unowned equip reject |

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
| Editor MOCK | `MockMatchServer.equip_cosmetic`. Snapshot includes `you.equippedSkinId`. Match snapshots carry the same field for the doll. |
| LIVE + `/shop/equip` 200 | Apply snapshot only. Never invent the id. |
| LIVE + `/shop/equip` 404 | Method ready. Local chrome fallback + Coder blocker toast. |

Buy still auto-equips last SKU (Coder `shop_equipped` last-buy stub). Equip is the explicit swap / unequip.

## E5 combat table (unchanged)

| Field | Bare | Ghillie equipped |
| --- | --- | --- |
| Attack miss `hit` | false | false |
| Attack miss invents Hot | no | no |
| Attack kill `marksDelta` | +25 | +25 |
| `you.exposurePct` after start | 50 | 50 |
| `RECON_BASE` | 0.35 | 0.35 |
| UAV / spot math | unchanged | unchanged |

## Out of this slice

New SKUs · IAP · combat gear floor · ranked · Coder `/shop/equip` implementation (blocked, method ready).
