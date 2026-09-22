# Exposure gear floor — client bind

Server owns `operativeLevel` and the percent. Snapshot field: `you.exposureFloor` (`50` / `40` / `30` / `20`). The client **reads** it. It never maps a level to a percent, never POSTs `exposureFloor`, and never treats cosmetics or Marks as a floor change.

`end_turn.exposurePct` stays the next-turn intent (the slider). The doll’s label is the floor, not that intent.

## Fail-closed

| Payload | Doll / band |
| --- | --- |
| `you.exposureFloor` `50` `40` `30` `20` | That percent |
| Field missing | **50** |
| `0`, or any other number | **50** (never show 0, never invent a lower step) |
| `operativeLevel` only | **50** |

Hideout self uses the same reader when `exposureFloor` is already on the player / shop payload (`exposureFloor`, `you.exposureFloor`, or `player.exposureFloor`). A shop payload that omits the field displays **50**.

## Gates

| ID | Rule | Result |
| --- | --- | --- |
| **E1** | Start 50%. Never 0 | **PASS mock · PASS LIVE** |
| **E2** | Steps 50→40→30→20 come from the server field | **PASS mock · PASS LIVE** |
| **E3** | Doll % = live floor. Recon/Attack keep their existing bands | **PASS mock · PASS LIVE** |
| **E4** | Cosmetics / Marks chrome never touch the floor | **PASS mock · PASS LIVE** |
| **E5** | No IAP. No client-authored % | **PASS mock · PASS LIVE** |

Recon/Attack **result** odds are unchanged (`RECON_BASE` 0.35, occupy `BASE_HIT` 0.90). They did not hardcode a 50% chance band. The end-turn slider is the exposure band for the next window: its **minimum** is `you.exposureFloor` (fail-closed 50), so the intent cannot drop under the floor or to 0.

## Soft tip

First time the displayed floor drops below the prior reading, a muted chip:

> Gear tightened — harder to spot

Local ConfigFile on the coach store (`exposureFloorTipSeen`). **GOT IT** / **X** dismisses forever. Chip body ignores the mouse. Hideout **RESET TIPS** clears it. No API.

## Smoke

```bash
godot --headless --path . -s res://tools/headless_loop_test.gd
# HEADLESS_LOOP_OK  (_exposure_floor_case)
```

Stills (mock, 1280×720). The 40% and tip stills stamp the mock field. LIVE sends `you.exposureFloor`. A Godot capture with `GLASSLINE_USE_LIVE_API=1` printed `LABEL Exposure 50%` / `FLOOR 50` (`artifacts/ux/exposure_floor_live_50.png`). The one-shot tip was not re-shot on a leveled account — there is no in-client level hook. The LIVE ladder did reach floor 20.

LIVE smoke (API `a66a8ac` on https://glassline-api.vercel.app, client `8ed38a5`):

```bash
python3 tools/live_exposure_floor_smoke.py
```

| Gate | LIVE |
| --- | --- |
| **E1** | **PASS** `POST /players` `{ xp: 0, operativeLevel: 1, exposureFloor: 50 }`. Snapshot `you.exposureFloor` **50**, `you.exposurePct` **50**. `end_turn { exposurePct: -1 }` → `exposurePct must be 0-100`, phase stays `await_end_turn`. `end_turn { exposurePct: 0 }` and `{ exposurePct: 10 }` both store **50**. Anonymous seat is **50**. |
| **E2** | **PASS** Forfeit wins +50 XP. `xp 350` L4 floor **50**, `xp 400` L5 floor **40**, `xp 850` L9 floor **40**, `xp 900` L10 floor **30**, `xp 1350` L14 floor **30**, `xp 1400` L15 floor **20**. Replay GET `xp 1450` twice, no second grant. |
| **E3** | **PASS** Doll reads `you.exposureFloor` (`Exposure 50%` at L1). Slider min is that floor. Bands: floor 50 recon `spotChance 35` / attack `0.80` with brush cover (base 0.90 − 0.10); floor 40 `30` / `0.75`; floor 30 `25` / `0.80`; floor 20 `20` / `0.85` (high ground). Empty shot `hitChance 0`. `RECON_BASE` 0.35 and `BASE_HIT_CHANCE` 0.90 unchanged. |
| **E4** | **PASS** Practice kill `m_d4f119d651e445e8afc78b4cc9523b5b` marks **3→3**, xp **0**, floor **50**. Fresh practice `end_turn { exposurePct: 37 }` stores **50** (`m_2c6e262efed74eda82a02c1833742fd3`). SP job kill marks **3→13** (+10), xp **0**, floor **50**. Ghillie buy+equip at xp 200: floor **50**, xp **200**, `equippedSkinId skin_hideout_stub`, Fieldbolt stays, marks **61→11**. |
| **E5** | **PASS** `ActionIntent.end_turn` posts `exposurePct` only. Injected `exposureFloor: 20` / `operativeLevel: 9` / `xp: 999` stored floor **50**, level **1**, xp **0**. No IAP path. |

Player `p_5100d0fcd5c24ab7bc462389a54f4c72`. Raw transcript: `artifacts/live_exposure_floor_smoke.txt`. The first script pass flagged E4/E5 on assertion shape (absolute marks, and the word `exposureFloor` in a comment). The snippets above are the rescored LIVE result. `live_practice_smoke.py` now expects the stored floor **50**, not the posted 37.

```bash
/tmp/godot --path . --resolution 1280x720 -- --capture-exposure-floor-50
/tmp/godot --path . --resolution 1280x720 -- --capture-exposure-floor-step
/tmp/godot --path . --resolution 1280x720 -- --capture-exposure-floor-tip
```

| Still | What |
| --- | --- |
| `artifacts/ux/exposure_floor_50.png` | Doll **Exposure 50%** (mock) |
| `artifacts/ux/exposure_floor_live_50.png` | Same label from a LIVE create (`GLASSLINE_USE_LIVE_API=1`, print `LABEL Exposure 50%` `FLOOR 50`) |
| `artifacts/ux/exposure_floor_40.png` | Doll **Exposure 40%** (server field, mock stamp) |
| `artifacts/ux/exposure_floor_tip.png` | Same drop, one-shot tip (mock). No in-client level hook; the LIVE ladder did reach floor 20. |

## Out

Client-side operative level curve · IAP · mil-sim kit art · writing `exposureFloor` · changing Recon/Attack odds · forfeit-overlay z-order (already on main, untouched).
