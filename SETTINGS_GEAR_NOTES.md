# Hideout gear strip — mute + coach reset

Client-local only. Wood plate + chunky chips on the hideout. Not an Options menu. No API / Marks / account / graphics / keybinds.

## Gates

| Gate | Bar | Result |
| --- | --- | --- |
| **S1** | Gear strip master mute | Speaker chip **LIVE** / **MUTED**. Same `AudioJuice` flag as match **SOUND / MUTE**. Persists `user://glassline_settings.json` |
| **S2** | Mute kills all juice; hunt stays readable | Muted `notice_last_action` plays nothing. Toasts still read. Strip does not cover the room |
| **S3** | Reset clears first-hunt + terrain seen | Confirm calls `reset_tips()` → `coachSeen=false` and `coachTerrainSeen=false` |
| **S4** | Confirm before reset | Copy **Tips will show again.** Cancel leaves both flags dismissed |
| **S5** | Local only | Strip never calls MatchAPI. Settings file is `{ muted }` |
| **S6** | Wood plate chips | `make_wood_texture` + `chunk_button`. No ladder / account chrome |

Headless: `godot --headless --path . -s res://tools/headless_loop_test.gd` → `HEADLESS_LOOP_OK`.

## Store

`user://glassline_coach.cfg`

```
[coach]
coachSeen=false
coachTerrainSeen=
```

`coachTerrainSeen` is the terrain coach's comma list (`high,brush`). Reset writes it empty so both chips can show again. This strip does not draw those chips.

## Stills

```
/tmp/godot --path . --resolution 1280x720 -- --capture-gear-strip
/tmp/godot --path . --resolution 1280x720 -- --capture-gear-muted
/tmp/godot --path . --resolution 1280x720 -- --capture-gear-confirm
```

| Still | Flag |
| --- | --- |
| `artifacts/ux/gear_strip_live.png` | `--capture-gear-strip` |
| `artifacts/ux/gear_strip_muted.png` | `--capture-gear-muted` |
| `artifacts/ux/gear_strip_confirm.png` | `--capture-gear-confirm` |

## Out

Full options menu · graphics · keybinds · account · cloud sync · Marks.
