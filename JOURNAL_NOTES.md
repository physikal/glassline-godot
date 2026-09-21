# Match journal — client

Hideout **JOURNAL** opens a wood plate of the last **10** ended hunts. Rows come from `GET /journal` only. The client does not invent a hunt from local history, and there is no replay.

## Row

`matchId` · `mode` · `result` (win / loss / forfeit / draw) · `rival` `{ displayName, isBot }` · `marksDelta` · `endedAt` · `rematchAvailable`

| Chip | Rule |
| --- | --- |
| Result pill | WIN / LOSS / FORFEIT / DRAW |
| Rival | Server `displayName`. Practice bot reads **TOY SPY** |
| Marks | Server Δ. Practice is always **Δ0**, even if a payload says +25 |
| Tag | PRACTICE or QUICK. A job row is JOB — no tier, no rating |
| CTA | PvP + `rematchAvailable` → existing `POST /matches/:id/rematch`. Practice → **PRACTICE AGAIN** (`mode: practice` create). Muted when the ledger says no |

Empty plate: **No hunts yet.** / **The table is quiet.**

## Gates

| Gate | Bar | Result |
| --- | --- | --- |
| J1 | ≤10 server rows, newest first | **PASS** mock |
| J2 | Practice Marks Δ0 | **PASS** mock (poison +25 still displays Δ0) |
| J3 | Rematch only when `rematchAvailable` | **PASS** mock. Expired row stays muted |
| J4 | Practice again → practice create | **PASS** mock. Signal calls `_start_practice` |
| J5 | Empty state cozy | **PASS** still `artifacts/ux/journal_empty.png` |
| J6 | Wood / chunky plate, no ladder / MMR / replay | **PASS** stills |

`godot --headless --path . -s res://tools/headless_loop_test.gd` → **HEADLESS_LOOP_OK** (`_journal_case`).

## LIVE

`GET /journal` with the durable Bearer. `{ entries: [...] }`.

404 `journal_unavailable` keeps the mock ledger until Coder lands the route. A live 200 binds those entries and still caps at 10. Practice Δ is forced to 0 on the client too.

## Stills

```
/tmp/godot --path . --resolution 1280x720 -- --capture-journal-empty
/tmp/godot --path . --resolution 1280x720 -- --capture-journal-rows
/tmp/godot --path . --resolution 1280x720 -- --capture-journal-muted
```

`artifacts/ux/journal_empty.png` · `journal_rows.png` · `journal_muted.png`

Tip this slice is built on: `d8842da`.
