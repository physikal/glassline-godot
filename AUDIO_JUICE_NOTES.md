# Audio juice + Soft P2 toasts (A1–A5)

Design gates locked 2026-09-21. Chrome only — **no API / Marks / combat delta**.

## Gates

| Gate | Bar | Result |
| --- | --- | --- |
| **A1** | Hit / miss / HG / brush stingers from attack result flags | `AudioJuice.cues_for` reads `hit` / `decoyCleared` / `highGroundApplied` / `coverApplied` only |
| **A2** | Toy-spy tone — no mil-sim gunshot / killstreak | Cue ids `glass_click` / `glass_ping` / `high_chime` / `brush_hush`. Short synthesized tones |
| **A3** | Mute/settings: game fully readable silent | Hideout + match **SOUND / MUTE**. Persist `user://glassline_settings.json`. `GLASSLINE_MUTE=1` |
| **A4** | No API / Marks / combat delta | Juice never posts, never `marks -=`, never invents hit |
| **A5** | Soft P2: no `(server)` in toasts | `Chrome.describe_attack_result` / `describe_last_action` drop the debug suffix |

Headless: `godot --headless --path . -s res://tools/headless_loop_test.gd` → `HEADLESS_LOOP_OK`.

## UX taste (sample paths)

| Path | Copy / cue |
| --- | --- |
| Miss | `Shot missed.` → `glass_click` |
| Hit | `Shot hit.` → `glass_ping` |
| Hit + HG + brush | `Shot hit. Chance 90%. High ground · Brush cover.` → `glass_ping` + `high_chime` + `brush_hush` |
| Doll | `Toy doll gone.` → `glass_click` |
| Mute | Button **MUTE**. Toasts / chips / optic still read |

BRUSH cover math unchanged (`948f04a` formula). Missing flags omit that stinger.

## Out

New mechanics · paid stingers · mil-sim gunshot / killstreak VO · client-side hit math.
