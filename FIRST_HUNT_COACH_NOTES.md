# First-hunt coach — notes

Client-only tip chips on the **first PvP / private live (or mock) match**. No API. No Marks / combat delta. No forced tutorial match.

**Hard:** chips, not a modal wall · never dim the board · never steal `select_hex` / Attack / Recon / UAV / Decoy / End turn · persist `coachSeen` in `user://` · SP jobs skip.

## Behavior

| When | What |
| --- | --- |
| First `active` PvP / private hunt, `coachSeen=false` | Four tip chips + **GOT IT** / **X** |
| SP job | Skip (same flag, no spam) |
| Drop / ready / ended | Hidden |
| GOT IT or X | `coachSeen=true` in ConfigFile — never again |

Store: `user://glassline_coach.cfg`

```
[coach]
coachSeen=true
```

## Copy (cozy toy-spy)

| Chip | Line |
| --- | --- |
| ATTACK | Peek the optic — tap a hex. |
| RECON | Scout a hex — no shot fired. |
| DOLL | They peek — the doll lights up. |
| DECOY | Once a hunt — drop a fake blip. |

## Gates

| ID | Bar | Result |
| --- | --- | --- |
| **C1** | First live match, or until dismissed forever. SP jobs skip. | **PASS mock** |
| **C2** | Attack · Recon · Exposure doll · Decoy | **PASS mock** |
| **C3** | Dismiss / Got it — no modal lock | **PASS mock** |
| **C4** | No Marks / no combat delta | **PASS mock** (`RECON_BASE` 0.35 · PvP ★25) |
| **C5** | Persist `coachSeen` via ConfigFile | **PASS mock** |
| **C6** | Tip chips, hideout chrome, no mil-sim wall | **PASS mock stills** |

## Client map

| Surface | Behavior |
| --- | --- |
| `scenes/match/first_hunt_coach.gd` | Chips + ConfigFile. Root / chip bodies `MOUSE_FILTER_IGNORE`. |
| `MatchScreen._sync_coach` | Present only when `status=active` and not a job. |
| `Contract.COACH_*` | Copy + store keys. No wire fields. |

## Smoke

```bash
godot --headless --path . -s res://tools/headless_coach_test.gd
# HEADLESS_COACH_OK

godot --headless --path . -s res://tools/headless_loop_test.gd
# HEADLESS_LOOP_OK  (includes _first_hunt_coach_case)
```

Stills (mock, `DISPLAY=:1`, 1280×720):

| Still | Flag | Raw |
| --- | --- | --- |
| `artifacts/ux/coach_tips_first_match.png` | `--capture-coach-tips` | chips on the match HUD |
| `artifacts/ux/coach_dismissed.png` | `--capture-coach-dismissed` | after Got it, board interactive |
| `artifacts/ux/coach_chip_closeup.png` | `--capture-coach-chip` | Attack chip crop |

```
/tmp/godot --path . --resolution 1280x720 -- --capture-coach-tips
/tmp/godot --path . --resolution 1280x720 -- --capture-coach-dismissed
/tmp/godot --path . --resolution 1280x720 -- --capture-coach-chip
```

LIVE not required (no API).

## Out

Forced tutorial match · video · tip spam every hunt · server/API work · Marks grant/spend · mil-sim tutorial wall.
