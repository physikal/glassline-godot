# LIVE Marks + SP job — M1–M5 (+A4)

**Base:** `https://glassline-api.vercel.app`  
**Client PR:** https://github.com/physikal/glassline-godot/pull/2  
**API ledger:** idempotent on `(source_type, source_id, player_id)` — replay GET does not double-pay.

Hard rule: client **displays** `you.marks` only. No `marks +=`.

## Checklist

| Gate | Result | Evidence |
| --- | --- | --- |
| **M1** PvP kill +25 | **PASS LIVE** | `LIVE_HTTP_SMOKE_OK m_0e8ee5d22cd84be4b398c2d659a63e1d` — `you.marks 0→25`, `endReason=kill` |
| **M2** PvP standoff +8 | **PASS display** | Locked table + mock `HEADLESS_LOOP_OK`. LIVE turn-cap not re-waited. |
| **M3** SP T1 job +10 | **PASS LIVE** | `LIVE_JOBS_SMOKE_OK j_b168c483a11a427a96031e38124a9f97 marks 0->10` |
| **M4** replay no double-pay | **PASS LIVE** | Job replay GET `/matches/:id` + `/jobs/:id` stayed **10**. PvP replay stayed **25**. |
| **M5** UAV chrome | **PASS** | Slot **ABILITY**, button **UAV**, posts `{ type: "uav" }`. HIGHGROUND parked. |
| **A4** 30s forfeit | **PASS LIVE** | `LIVE_A4_SMOKE_OK j_26e30905934c4e52bbde019a39f0664c endReason=forfeit marks 0->0` |

Earlier same-base T1: `j_f4ce6783556f4df99265c33ad5c4bdbc`, `j_5838afbb4638437fb4b12a2f978632cd` also 0→10, replay 10.

Mock chrome: `HEADLESS_LOOP_OK` (`godot --headless --path . -s res://tools/headless_loop_test.gd`).

## HTTP commands

```bash
GLASSLINE_API_BASE=https://glassline-api.vercel.app python3 tools/live_jobs_smoke.py
GLASSLINE_API_BASE=https://glassline-api.vercel.app python3 tools/live_http_smoke.py
GLASSLINE_API_BASE=https://glassline-api.vercel.app python3 tools/live_a4_smoke.py
```

## UX stills (mock chrome after war-table merge)

Godot default is MOCK (`use_live_api=false`). Wallet stub **★24 → job +10 → ★34**. LIVE HTTP wallet is `you.marks` **0→10** (T1) / **0→25** (PvP). Same chrome binds both.

| Surface | Path | Raw |
| --- | --- | --- |
| Hideout Marks chip ★24 | `/opt/cursor/artifacts/hideout_marks_chip_wartable.png` | `file:///opt/cursor/artifacts/hideout_marks_chip_wartable.png` |
| SP job entry (JOBS) | `/opt/cursor/artifacts/hideout_sp_job_panel_wartable.png` | `file:///opt/cursor/artifacts/hideout_sp_job_panel_wartable.png` |
| UAV on war-table board | `/opt/cursor/artifacts/sp_job_uav_ability_wartable.png` | `file:///opt/cursor/artifacts/sp_job_uav_ability_wartable.png` |
| Post-match Marks delta | `/opt/cursor/artifacts/sp_job_end_marks_payout_wartable.png` | `file:///opt/cursor/artifacts/sp_job_end_marks_payout_wartable.png` |
| Hideout after job ★34 | `/opt/cursor/artifacts/hideout_marks_after_job_wartable.png` | `file:///opt/cursor/artifacts/hideout_marks_after_job_wartable.png` |
| Playthrough | `/opt/cursor/artifacts/sp_job_uav_marks_payout_wartable.mp4` | `file:///opt/cursor/artifacts/sp_job_uav_marks_payout_wartable.mp4` |

On-screen (mock): hideout `MARKS ★24` → JOBS `SP JOB vs BOT` / `START JOB` → board title `SP JOB`, rival `BOT`, ability **UAV** → overlay `JOB COMPLETE` / `+10 MARK · ★34` / `kill` → hideout `MARKS ★34` + last-hunt line.

## Client wiring

- Hideout `MARKS ★N` ← `you.marks` / `MatchAPI.wallet()` stub
- JOBS → `POST /jobs` `{ tier: 1 }` (LIVE) or mock `sp_job`
- End overlay ← `MarksPayout.end_overlay` (`marksDelta` or `table +N` + `★you.marks`)
- Soft A4 UI if `endReason` / `forfeit` / `disconnect` — timer is server 30s
- Heartbeat on LIVE poll (`POST /matches/:id/heartbeat`)

Details: `artifacts/MARKS_SP_NOTES.md`.
