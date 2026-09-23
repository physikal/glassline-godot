# Ability SMOKE

Slice ticket: [Ability SMOKE](https://app.notion.com/p/3e34dabdb33981e08d98e025fcb18768)

Once per match. Your hex counts as **HARD for spot and exposure only**, on the decoy clock (one enemy turn, then your next action, cleared on your following end turn). No Marks, no IAP, no Attack +0.10, no IN COVER chip. UAV, Decoy, HIGH GROUND, and the doll exposure floor stay on their own fields.

LIVE source of truth: API tip `fa7285ba` on `https://glassline-api.vercel.app`.

## Bind

| Surface | Behavior |
| --- | --- |
| `ActionIntent.smoke()` | `{ type: "smoke" }` — no hex. Same `POST /matches/:id/actions` path as UAV / Decoy. An extra hex is ignored |
| `ActionIntent.ability()` | Still `{ type: "uav" }` |
| Success result | Exactly `{ type: "smoke" }` |
| `Snapshot.smoke_available()` | `you.smokeAvailable`, or `smoke_available`, or any casing. Missing → **false** |
| `Snapshot.smoke_active()` | `you.smokeActive` bool or turns-remaining `> 0`. Same casing tolerance. Missing or match ended → **false** |
| `Snapshot.enemy_smoke_active()` | `enemy.smokeActive` only. Does not read `you.*` and does not invent `visibleHex` |
| Match HUD | **SMOKE** chip (same toy puff) above the painted ABILITY key. Available is lit hot purple. Locked (below L5) and spent share the grey muted wood plate |
| Click | Posts only when `smoke_chrome()` is available (L5 and a named charge). Locked tap toasts. Spent / absent do not POST |
| Your puff | Toast `Smoke — hex is Hard this turn` and a soft HARD wash on **your** hex |
| Rival puff | Wash only if `enemy.smokeActive` and `enemy.visibleHex` are both already set. No toast |

Poll fingerprint includes exact `you.smokeAvailable`, `you.smokeActive`, exact `you.operativeLevel`, and `enemy.smokeActive` so a live flip refreshes the board.

## L5 unlock

Slice: [SMOKE L5 unlock](https://www.notion.so/3e44dabdb33981a2b27ff27e4bdcba91). Coder field names are exact `you.operativeLevel` and exact `you.smokeAvailable`. `smokeAvailable` is true only when `operativeLevel >= 5` and the charge remains. Deployed `https://glassline-api.vercel.app` already returns those keys (level 1 → `smokeAvailable` false, no lock-reason field). No API git tip was readable from this repo.

| Gate | Client |
| --- | --- |
| U1 | Chip lights only when exact `operativeLevel >= 5` and exact `smokeAvailable` is true |
| U2 | Below L5 the chip stays visible on the Soft P2 spent-wood plate. Tap toasts `Reach operative L5` |
| U3 | `xp` is ignored. Practice does not level and practice Marks stay Δ0. An L5 snapshot stays unlocked in practice |
| U4 | Once unlocked, the once/match puff, HARD spot/exposure, no Attack +0.10, and the decoy clock are unchanged |
| U5 | No Marks, no IAP, no catalog SKU, no second charge. A locked tap does not spend the puff |

Fail closed: a charge with no exact `operativeLevel` stays locked and does not POST. Snake-case aliases do not unlock. A missing charge with no level stays the absent chip. Mock accounts start at L5 so the existing harness stays the unlocked path; `operative_level = 4` publishes `smokeAvailable` false and refuses with `operative level`.

## Decoy clock

1. Cast → `smokeAvailable` false, `smokeActive` true, phase `await_end_turn`.
2. Your planting `end_turn` keeps the puff.
3. The enemy's action + `end_turn` keeps the puff.
4. Your next action window still has it.
5. Your next own `end_turn` clears `smokeActive`. The charge stays spent (`smoke already used`).

Rejects: `match is not active`, `not your turn`, `awaiting end_turn`, `smoke already used`.

## Design gates

| Gate | Client proof |
| --- | --- |
| S1 once/match | Chip posts once. Second cast refused. Mock + LIVE |
| S2 hex is HARD for spot/exposure, one enemy turn | Toast + soft tint from `you.smokeActive` for the decoy clock. Spot −20 (35 → 15, no stack on real HARD) is server-owned; LIVE script reads `spotChance` |
| S3 no Attack +0.10 / no HG | Smoke never sets `you.highGroundActive` or `highGroundApplied`. OPEN occupy stays `hitChance` 0.90. Real HARD occupy is still 1.0 |
| S4 Marks / UAV / Decoy unchanged | Those fields are not written by the smoke action. Brush cover stays −0.10 on its own |
| S5 doll floor untouched | `you.exposureFloor` / `you.exposurePct` stay 50. No client write |

## Fail closed

If the snapshot does not name `smokeAvailable`, the chip stays muted and the press does not POST. If it does not name `you.smokeActive`, there is no toast and no hex tint. If it does not name `enemy.smokeActive`, the rival hex is not washed. The client does not invent a charge, a secret hex, or an attack bonus.

## Stills

| State | File |
| --- | --- |
| Chip available | `artifacts/ux/smoke_chip_available.png` |
| Chip spent / muted | `artifacts/ux/smoke_chip_spent.png` |
| Active toast + tint | `artifacts/ux/smoke_active_toast.png` |
| Chip locked below L5 | `artifacts/ux/smoke_chip_locked.png` |
| Lock toast | `artifacts/ux/smoke_lock_toast.png` |

```
/tmp/godot --path . --resolution 1280x720 -- --capture-smoke-available
/tmp/godot --path . --resolution 1280x720 -- --capture-smoke-spent
/tmp/godot --path . --resolution 1280x720 -- --capture-smoke-active
/tmp/godot --path . --resolution 1280x720 -- --capture-smoke-locked
/tmp/godot --path . --resolution 1280x720 -- --capture-smoke-lock-toast
```

Headless: `godot --headless --path . -s res://tools/headless_loop_test.gd` → `HEADLESS_LOOP_OK`.

LIVE: `python3 tools/live_ability_smoke.py` → `LIVE_SMOKE_ABILITY_OK`.
