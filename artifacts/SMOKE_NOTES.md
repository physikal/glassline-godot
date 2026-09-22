# Ability SMOKE

Slice ticket: [Ability SMOKE](https://app.notion.com/p/3e34dabdb33981e08d98e025fcb18768)

Once per match. Your hex counts as **HARD for exposure + spot only** for one enemy turn. No Marks, no IAP, no Attack +0.10, no IN COVER chip. UAV, Decoy, and HIGH GROUND stay on their own fields.

Spot / exposure math is server-owned (API tip ~`a66a8ac`, shipping in parallel). This client binds snapshot flags and posts the intent.

## Bind

| Surface | Behavior |
| --- | --- |
| `ActionIntent.smoke()` | `{ type: "smoke" }` — no hex. Same `POST /matches/:id/actions` path as UAV / Decoy |
| `ActionIntent.ability()` | Still `{ type: "uav" }` |
| `Snapshot.smoke_available()` | `you.smokeAvailable`, or `smoke_available`, or any casing. Missing → **false** |
| `Snapshot.smoke_active()` | `you.smokeActive` bool or turns-remaining `> 0`. Same casing tolerance. Missing or match ended → **false** |
| Match HUD | Purple **SMOKE** chip (toy puff) above the painted ABILITY key. Lit when available. Muted when spent or when the field is absent |
| Click | Posts only when `smoke_available()`. Otherwise no-op |
| Active | Toast `Smoke — hex is Hard this turn` and a soft HARD wash on **your** hex. HIGH GROUND chip is not lit by smoke |

Poll fingerprint includes `smokeAvailable` / `smokeActive` so a live flip refreshes the board.

## Fail closed

If the snapshot does not name `smokeAvailable`, the chip stays muted and the press does not POST. If it does not name `smokeActive`, there is no toast and no hex tint. The client does not invent a charge, a tint, or an attack bonus.

Mock snapshots always include both fields so headless play can light the chip. A hand-built snapshot without them stays dark.

## Stills

| State | File |
| --- | --- |
| Chip available | `artifacts/ux/smoke_chip_available.png` |
| Chip spent / muted | `artifacts/ux/smoke_chip_spent.png` |
| Active toast + tint | `artifacts/ux/smoke_active_toast.png` |

```
/tmp/godot --path . --resolution 1280x720 -- --capture-smoke-available
/tmp/godot --path . --resolution 1280x720 -- --capture-smoke-spent
/tmp/godot --path . --resolution 1280x720 -- --capture-smoke-active
```

Headless: `godot --headless --path . -s res://tools/headless_loop_test.gd` → `HEADLESS_LOOP_OK`.
