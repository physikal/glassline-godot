# Paste from clipboard (C1–C6)

Client-only. The private-hunt **join** plate reads the clipboard **once** when the form opens and when that form gains focus. A chunky **PASTE** chip shows when the clipboard is a 6-char lobby code. The tap fills the code field. Join is still the JOIN button. No deep link, QR, or SMS scrape.

## Gates

| Gate | Bar | How |
| --- | --- | --- |
| **C1** | Join reads clipboard for a 6-char lobby code | `LobbyPaste.peek_code` on join-home open, line-edit focus, and window focus while that form is up |
| **C2** | Paste chip fills the field | Tap writes the peeked code into the field. Peek itself does not |
| **C3** | Invalid / empty is muted or a no-op | Chip stays hidden. Tap with no code does not change the field |
| **C4** | Join API unchanged | `MatchAPI.join_lobby` / `LiveMatchClient.join_lobby` untouched. Paste does not call them |
| **C5** | No deep links / background clipboard spam | No timer, no `_process` read, no link opener. A blurb or URL is not a code |
| **C6** | Chunky Paste beside Join | Wood-dark / gold, same family as COPY. Gold line **Pasted.** on the join plate |

Headless: `godot --headless --path . -s res://tools/headless_loop_test.gd` → `HEADLESS_LOOP_OK`.

## Read rule

One `clipboard_get` per open and per focus of the join form. The hideout, the wait plate, quick match, and practice do not read. Paste does not watch the clipboard on a timer.

COPY still puts the raw 6-char code on the clipboard. `H7K 3P2` and `H7K-3P2` count. `Hunt with me — code H7K3P2`, a URL, and `ABC10O` do not.

## Stills

```
/tmp/godot --path . --resolution 1280x720 -- --capture-lobby-paste
```

| Still | What |
| --- | --- |
| `artifacts/ux/lobby_paste.png` | Join plate, clipboard `H7K3P2`, PASTE beside the field |
| `artifacts/ux/lobby_pasted.png` | After the chip tap — field filled, toast **Pasted.** |
| `artifacts/ux/lobby_paste_empty.png` | Clipboard empty — PASTE hidden |

## Out

Deep links · QR · SMS scrape · always-on clipboard watcher · mil-sim · join / create / poll / cancel changes.
