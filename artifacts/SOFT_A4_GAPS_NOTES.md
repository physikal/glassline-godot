# Soft A4 gap punch-list — notes

Slice: [Soft A4 gap punch-list](https://app.notion.com/p/3e04dabdb339813da9e2d6b641ede1ba). **No rebuild** of grace / heartbeat / forfeit ledger.

**Already LIVE (do not rebuild):** 30s grace · heartbeat / WS / SSE presence · `endReason: forfeit` · Marks +12 / 0 · rematch 409 until `ended`.

**LIVE curl (2026-09-19):** `GET /health` → `{ ok: true }`. `POST /matches/:id/abandon` → **404** (Coder pending). `POST /matches/:id/rematch` exists (401 without Bearer; 409 while `active`).

## Gaps shipped (client)

| # | Gap | Client |
| --- | --- | --- |
| 1 | Abandon CTA | Mid-match **ABANDON** (Decline weight: wood / cream). `MatchAPI.abandon` → `LiveMatchClient.abandon` `POST /matches/:id/abandon` + join Bearer. Mock uses the same `_end_forfeit` settle as a 30s silence (`+12` remaining / `+0` leaver). Idempotent if already `ended`. |
| 2 | Grace countdown | Readable `RIVAL  0:23` (clock + gold). Keys off snapshot `disconnected_at` / `graceEndsAt` / `graceRemainingSec`. Local poll GET failure uses `LiveMatchClient.poll_failed_since_msec` (`HOLD  0:23`). Does **not** start grace on Vercel SSE→poll (that close is normal). Duration stays **30s**. |
| 3 | Forfeit overlay | Reuses rematch chrome: `RIVAL FORFEIT` / `FORFEIT`, Marks settled **+12 / 0**, **Play again** / **Decline**. No mil-sim disconnect screen. Rematch buttons only after `ended`. |

No new Marks table. No grace-duration change.

## Gates

| ID | Result | Evidence |
| --- | --- | --- |
| **A4.1** Abandon → forfeit +12/0 | **PASS mock** · LIVE pending 404 | Headless `_a4_gaps_case`. Stills `artifacts/ux/abandon_cta.png`, `forfeit_overlay.png`. |
| **A4.2** Disconnect 30s silence → same | **PASS LIVE (prior)** | `LIVE_A4_SMOKE_OK j_26e30905934c4e52bbde019a39f0664c endReason=forfeit marks 0->0`. Mock grace expire uses the same `_end_forfeit`. |
| **A4.3** Countdown UX readable + still | **PASS mock** | `artifacts/ux/grace_countdown.png` — `RIVAL  0:23`. |
| **A4.4** Overlay Marks settled; rematch only after ended | **PASS mock** | Overlay settle line `Marks settled  ·  +12 / 0` + Play again / Decline. Rematch while `active` is 409 `match_not_ended`. |

## Smoke

```bash
godot --headless --path . -s res://tools/headless_loop_test.gd
# HEADLESS_LOOP_OK (includes _a4_gaps_case)

GLASSLINE_API_BASE=https://glassline-api.vercel.app python3 tools/live_a4_gaps_smoke.py
# LIVE_A4_GAPS_SMOKE_PENDING abandon_404 (2026-09-19)

GLASSLINE_API_BASE=https://glassline-api.vercel.app python3 tools/live_a4_smoke.py
# A4.2 already LIVE
```

`artifacts/live_a4_gaps_smoke.txt` — rematch-while-active **409** (A4.4). `/abandon` 404.

Stills (mock, `DISPLAY=:1`, 1280×720):

| Still | Flag |
| --- | --- |
| `artifacts/ux/abandon_cta.png` | `--capture-abandon-cta` |
| `artifacts/ux/grace_countdown.png` | `--capture-grace-countdown` |
| `artifacts/ux/forfeit_overlay.png` | `--capture-forfeit-overlay` |

## Out

New Marks table · changing 30s · mil-sim disconnect chrome · rematch-during-grace (already 409).
