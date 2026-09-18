# LIVE Marks + SP job — M1–M5 (+A4)

**Base:** `https://glassline-api.vercel.app`  
**Client PR:** https://github.com/physikal/glassline-godot/pull/2  
**API:** Coder ledger is idempotent on `(source_type, source_id, player_id)` — replay GET must not double-pay.

Hard rule: client **displays** `you.marks` only. No `marks +=`.

## Checklist

| Gate | Result | Evidence |
| --- | --- | --- |
| **M1** PvP kill +25 | pending LIVE HTTP | `tools/live_http_smoke.py` now asserts `you.marks +25` + replay |
| **M2** PvP standoff +8 | PASS display | Table copy + mock headless; LIVE turn-cap not re-waited |
| **M3** SP T1 job +10 | **PASS LIVE** | `LIVE_JOBS_SMOKE_OK j_b168c483a11a427a96031e38124a9f97 marks 0->10` |
| **M4** replay no double-pay | **PASS LIVE** | replay GET `/matches/:id` + `/jobs/:id` stayed **10** |
| **M5** UAV chrome | **PASS** | Ability slot caption **ABILITY**, button **UAV**, posts `{ type: "uav" }` |
| **A4** 30s forfeit | pending LIVE HTTP | `tools/live_a4_smoke.py` (silent 32s → `endReason: forfeit`, +0) |

Earlier same-base T1: `j_f4ce6783556f4df99265c33ad5c4bdbc` and `j_5838afbb4638437fb4b12a2f978632cd` also 0→10, replay 10.

## HTTP commands

```bash
GLASSLINE_API_BASE=https://glassline-api.vercel.app python3 tools/live_jobs_smoke.py
GLASSLINE_API_BASE=https://glassline-api.vercel.app python3 tools/live_http_smoke.py
GLASSLINE_API_BASE=https://glassline-api.vercel.app python3 tools/live_a4_smoke.py
```

## UX stills (mock chrome; wallet stub 24 → job +10 → ★34)

Godot editor default is MOCK (`use_live_api=false`). LIVE wallet is `you.marks` (this smoke: 0→10). Same chrome binds both.

| Surface | Path | Raw |
| --- | --- | --- |
| Hideout Marks chip | `/opt/cursor/artifacts/hideout_marks_chip.png` | `file:///opt/cursor/artifacts/hideout_marks_chip.png` |
| SP job entry (JOBS) | `/opt/cursor/artifacts/hideout_sp_job_panel.png` | `file:///opt/cursor/artifacts/hideout_sp_job_panel.png` |
| UAV on board | `/opt/cursor/artifacts/sp_job_uav_ability.png` | `file:///opt/cursor/artifacts/sp_job_uav_ability.png` |
| Post-match Marks delta | `/opt/cursor/artifacts/sp_job_end_marks_payout.png` | `file:///opt/cursor/artifacts/sp_job_end_marks_payout.png` |
| Hideout after job | `/opt/cursor/artifacts/hideout_marks_after_job.png` | `file:///opt/cursor/artifacts/hideout_marks_after_job.png` |
| Playthrough | `/opt/cursor/artifacts/sp_job_uav_kill_marks_payout.mp4` | `file:///opt/cursor/artifacts/sp_job_uav_kill_marks_payout.mp4` |

Stills were captured before merging main’s war-table / parked-HIGHGROUND chrome. Recapture after merge if the board plate must match A1 HOLD.

## Client wiring

- Hideout `MARKS ★N` ← `you.marks` / `MatchAPI.wallet()` stub
- JOBS → `POST /jobs` `{ tier: 1 }` (LIVE) or mock `sp_job`
- End overlay ← `MarksPayout.end_overlay` (`marksDelta` or `table +N` + `★you.marks`)
- Soft A4 UI if `endReason` / `forfeit` / `disconnect` — timer is server 30s
- Heartbeat on LIVE poll (`POST /matches/:id/heartbeat`)

Details: `artifacts/MARKS_SP_NOTES.md`.
