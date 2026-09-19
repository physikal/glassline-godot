# Match end summary — notes

Slice: [📋 Slice ticket — Match end summary](https://app.notion.com/p/3e04dabdb3398105968bd7ec50e712d7). Arch stamp 2026-09-19. **Client chrome only — no API change.**

**Hard:** derive Marks Δ from snapshot `endReason` + winner vs seat · no `you.marksDelta` field · Rematch / Hideout still work (M.3) · keep forfeit/kill language already passed · cozy toy-spy, no mil-sim.

## Earn table (display)

| `endReason` · seat | Δ | Headline |
| --- | --- | --- |
| kill + winner | **+25** | `MARK CONFIRMED` |
| kill + loser | **+3** | `ELIMINATED` |
| standoff (both) | **+8** | `STANDOFF` |
| forfeit + remaining | **+12** | `RIVAL FORFEIT` |
| forfeit + leaver | **0** | `FORFEIT` |

SP jobs keep the existing job / `job_fail` map (LIVE `endReason=kill` → display `job`). Overlay never `marks +=`.

## Chrome (UX bar)

1. **Headline** — outcome only (language above).
2. **Marks line** — `+N MARK · ★you.marks` from the table, not payload `marksDelta` and not `table +N`.
3. **Reason** — table token underneath (`kill` / `standoff` / `forfeit`). Kill loser stays `kill`, not invented `loss`.
4. **Rematch CTA** — `PLAY AGAIN` / `DECLINE` + `Marks already settled.` (copy unchanged). Jobs still Hideout-only.

`MarksPayout.live_delta_drifts` is true only when a payload `marksDelta` exists and disagrees with the table. Default: no Coder field. This slice did not see LIVE drift.

## Gates

| ID | Result | Evidence |
| --- | --- | --- |
| **M.1** Kill / forfeit / standoff copy | **PASS mock** | Headless `_end_summary_case`. Stills `end_summary_kill.png` / `end_summary_forfeit.png` / `end_summary_standoff.png`. Both seats asserted in overlay strings. |
| **M.2** Δ matches earn table | **PASS mock** | `table_delta` + mock settle: kill 25/3 · standoff 8/8 · forfeit 12/0. LIVE omit `marksDelta` still paints `+25 MARK · ★25`. |
| **M.3** Rematch / Hideout still work | **PASS mock** | After overlay, `rematch_offered` · Play again → waiting · Decline → declined. Jobs stay Hideout. Existing `_rematch_case` / `_a4_gaps_case` unchanged. |
| **M.4** UX taste vs end overlay | **PASS mock stills** | Gold marks line under a bigger headline, cream reason, then settled rematch plate. No mil-sim. |

## Client map

| Surface | Behavior |
| --- | --- |
| `MarksPayout.table_delta` / `table_reason` | `endReason` + winner vs seat. Forfeit / draw short-circuit. |
| `MarksPayout.overlay_parts` / `end_overlay` | Headline · `+N MARK · ★balance` · reason. |
| `Snapshot.table_marks_delta` | Same table, display only. |
| `MatchScreen._show_ended` | Split labels, then rematch buttons. Settled copy is always `Marks already settled.` |
| `MockMatchServer.force_standoff` | Capture / tests: settle turn-cap without 16 turns. |

## Smoke

```bash
godot --headless --path . -s res://tools/headless_loop_test.gd
# HEADLESS_LOOP_OK (includes _end_summary_case)

/tmp/godot --path . --resolution 1280x720 -- --capture-end-summary-kill
/tmp/godot --path . --resolution 1280x720 -- --capture-end-summary-forfeit
/tmp/godot --path . --resolution 1280x720 -- --capture-end-summary-standoff
```

LIVE smoke optional: ended snapshots already settle Marks (`you.marks` + `endReason`). No new field. Prior kill/forfeit/standoff smokes in `LIVE_MARKS_SMOKE.md` / rematch notes still apply.

## Stills

| Gate | File |
| --- | --- |
| M.1 kill winner | `artifacts/ux/end_summary_kill.png` |
| M.1 remaining | `artifacts/ux/end_summary_forfeit.png` |
| M.1 standoff | `artifacts/ux/end_summary_standoff.png` |

Capture (mock, `DISPLAY=:1`, wallet reset to 0 so ★ is the table grant).

## Out

`you.marksDelta` API · ranked / ELO · inventing Δ · changing Rematch copy · mil-sim disconnect chrome.
