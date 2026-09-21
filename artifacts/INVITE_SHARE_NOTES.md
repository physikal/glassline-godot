# Invite share (I1–I6)

Client-only. Private-lobby **wait** plate shares the code the create call already returned. Join / create / poll / cancel are unchanged. No deep link, QR, SMS, or new matchmaking.

## Gates

| Gate | Bar | How |
| --- | --- | --- |
| **I1** | Copy puts the 6-char code on the clipboard | `DisplayServer.clipboard_set` of the normalized code (no display space) |
| **I2** | Share opens an OS share sheet with the code + a short blurb | Blurb is `Hunt with me — code XXXXXX`. Android uses the engine `ACTION_SEND` chooser. Desktop copies that blurb and toasts |
| **I3** | Same existing lobby code | Share never calls `create_lobby` / `new_lobby_code` |
| **I4** | Private-lobby wait only | COPY and SHARE sit on the wait code row. Join home, queue, and practice do not |
| **I5** | No API / matchmaking change | `MatchAPI` and `LiveMatchClient` are untouched |
| **I6** | Wood/gold chips + toast | COPY is wood-dark / gold. SHARE is gold / ink. Toast **Code copied.** |

Headless: `godot --headless --path . -s res://tools/headless_loop_test.gd` → `HEADLESS_LOOP_OK`.

## Platform limits

Godot 4.3–4.6 `DisplayServer` has clipboard, not a share sheet. This client probes `DisplayServer.share_text` / `OS.share_text` and uses them if a later build adds them.

| Platform | Share |
| --- | --- |
| Android (export, Godot 4.4+) | `JavaClassWrapper` + `AndroidRuntime` start an `ACTION_SEND` / `createChooser` sheet. The extra text is the blurb only — no URI |
| Linux, macOS, Windows, web, iOS, headless | No built-in sheet. SHARE copies the blurb and the wait plate toasts **Code copied.** |
| `OS.shell_open` | Not used. It would open a URL or an `sms:` / `mailto:` handler |

iOS `UIActivityViewController` needs an export plugin. This slice does not ship one.

## Stills

```
/tmp/godot --path . --resolution 1280x720 -- --capture-lobby-create-wait
```

| Still | What |
| --- | --- |
| `artifacts/ux/lobby_create_wait.png` | Wait plate, COPY + SHARE beside the code |
| `artifacts/ux/lobby_invite_copied.png` | Same plate after COPY, toast **Code copied.** |

## Out

Deep links · QR · SMS CTA · mil-sim · new codes · matchmaking changes.
