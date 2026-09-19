# Soft A4 gap punch-list — notes

Slice: [Soft A4 gap punch-list](https://app.notion.com/p/3e04dabdb339813da9e2d6b641ede1ba). **No rebuild** of grace / heartbeat / forfeit ledger.

**Already LIVE (do not rebuild):** 30s grace · heartbeat / WS / SSE presence · `endReason: forfeit` · Marks +12 / 0 · rematch 409 until `ended`.

**LIVE curl (2026-09-19, Coder [glassline-api#10](https://github.com/physikal/glassline-api/pull/10) merged):** `GET /health` → `{ ok: true }`. `POST /matches/:id/abandon` is **up** (401 without Bearer; **no body**). `POST /matches/:id/rematch` exists (401 without Bearer; 409 while `active`).

## LIVE A4.1 — abandon smoke (Coder clear)

`python3 tools/live_a4_gaps_smoke.py` → **`LIVE_A4_GAPS_SMOKE_OK`**. Log: `artifacts/live_a4_gaps_smoke.txt`.

Durable pair: **`p_021afefcc0484e46b695da4c3e217a4c`** (A, leaver) · **`p_c6f07cd3018a491a92d079eabe018fa6`** (B, remaining).

| Gate | Result | matchIds / deltas |
| --- | --- | --- |
| Curl route-up | **PASS LIVE** | No Bearer → **401** `missing bearer token` (was 404). |
| Waiting abandon | **PASS LIVE** | `m_c0a9b4c1feab400fa5d5a89e591069af` → **409** `match_not_active`. |
| Ready abandon | **PASS LIVE** | `m_4d2f72372330405db8fa441667d5f3c3` → **409** `match_not_active`. |
| Rematch while `active` | **PASS LIVE** | Same as A4.4: **409** `match_not_ended`. |
| **A4.1** active → abandon → forfeit +12/0 | **PASS LIVE** | `m_38a667eafe8441f8902dfeab569812f6` · `status: ended` · `endReason: forfeit` · `winner: b` · `lastAction: { type: forfeit, winner: b }`. Snapshot `you.marks` **A 0 / B 12**. Shop `GET /shop/me` **A 0→0 (Δ0)** / **B 0→12 (Δ+12)**. |
| Idempotent if already ended | **PASS LIVE** | Second `POST /abandon` → **409** `match_already_ended`. Shop stays **0 / 12** (no second grant). Client GET-replays as `alreadyEnded`. |
| Rematch only after `ended` | **PASS LIVE** | After forfeit, `rematch.status: waiting`. Both accept → ready **`m_bf9394677290496caefb8d34425e26d4`**. |

First manual probe (same shapes, not the script table): ended `m_f96be1b145834e9e98f1dbb6187c1133` shop **Δ0 / Δ+12**, rematch ready `m_f974ae86853a4fc8ad8c13f25c1a90ea`. Waiting `m_e45ed2d7839b401eb556d3cf22297924` / ready `m_3d4886d0b66e40ec88335824cdd57174` were 409.

## Gaps shipped (client)

| # | Gap | Client |
| --- | --- | --- |
| 1 | Abandon CTA | Mid-match **ABANDON** (Decline weight: wood / cream). `MatchAPI.abandon` → `LiveMatchClient.abandon` `POST /matches/:id/abandon` + join Bearer, **no body**. Mock uses the same `_end_forfeit` settle as a 30s silence (`+12` remaining / `+0` leaver). LIVE already-ended is 409 `match_already_ended` (no second grant). |
| 2 | Grace countdown | Readable disconnect grace — **not** a turn clock. Rival drop: `Waiting on rival…  0:23`. Local poll GET failure: `Reconnect  0:23` (`LiveMatchClient.poll_failed_since_msec`). Keys off snapshot `disconnected_at` / `graceEndsAt` / `graceRemainingSec`. Does **not** start grace on Vercel SSE→poll (that close is normal). Duration stays **30s**. |
| 3 | Forfeit overlay | Reuses rematch chrome: `RIVAL FORFEIT` / `FORFEIT`, Marks settled **+12 / 0**, **Play again** / **Decline**. No mil-sim disconnect screen. Rematch buttons only after `ended`. |

No new Marks table. No grace-duration change.

## Gates

| ID | Result | Evidence |
| --- | --- | --- |
| **A4.1** Abandon → forfeit +12/0 | **PASS LIVE** | `LIVE_A4_GAPS_SMOKE_OK m_38a667eafe8441f8902dfeab569812f6` remaining **Δ+12** / leaver **Δ0**. Headless `_a4_gaps_case` still PASS mock. Stills `artifacts/ux/abandon_cta.png`, `forfeit_overlay.png`. |
| **A4.2** Disconnect 30s silence → same | **PASS LIVE (prior)** | `LIVE_A4_SMOKE_OK j_26e30905934c4e52bbde019a39f0664c endReason=forfeit marks 0->0`. Mock grace expire uses the same `_end_forfeit`. |
| **A4.3** Countdown UX readable + still | **PASS mock** | `artifacts/ux/grace_countdown.png` — `Waiting on rival…  0:23` (disconnect grace, not turn time). |
| **A4.4** Overlay Marks settled; rematch only after ended | **PASS LIVE** | Rematch while `active` is 409 `match_not_ended`. After A4.1 forfeit, rematch ready `m_bf9394677290496caefb8d34425e26d4`. Overlay settle line `Marks settled  ·  +12 / 0` + Play again / Decline (mock still). |

## Smoke

```bash
godot --headless --path . -s res://tools/headless_loop_test.gd
# HEADLESS_LOOP_OK (includes _a4_gaps_case)

GLASSLINE_API_BASE=https://glassline-api.vercel.app python3 tools/live_a4_gaps_smoke.py
# LIVE_A4_GAPS_SMOKE_OK m_38a667eafe8441f8902dfeab569812f6 forfeit remaining Δ+12 leaver Δ0
# rematch m_bf9394677290496caefb8d34425e26d4  (2026-09-19)

GLASSLINE_API_BASE=https://glassline-api.vercel.app python3 tools/live_a4_smoke.py
# A4.2 already LIVE
```

`artifacts/live_a4_gaps_smoke.txt` — waiting/ready **409**, rematch-while-active **409**, active abandon **200** forfeit +12/0, replay **409** no second grant, rematch after ended **200**.

Stills (mock, `DISPLAY=:1`, 1280×720):

| Still | Flag |
| --- | --- |
| `artifacts/ux/abandon_cta.png` | `--capture-abandon-cta` |
| `artifacts/ux/grace_countdown.png` | `--capture-grace-countdown` |
| `artifacts/ux/forfeit_overlay.png` | `--capture-forfeit-overlay` |

## UX HOLD (countdown copy)

`RIVAL  0:23` read as a turn clock. Copy is now disconnect/reconnect language: `Waiting on rival…  0:23` (their drop) / `Reconnect  0:23` (local poll HOLD). Abandon CTA + forfeit overlay unchanged. Duration still 30s. No mil-sim.

## Out

New Marks table · changing 30s · mil-sim disconnect chrome · rematch-during-grace (already 409) · forfeit core rebuild.
