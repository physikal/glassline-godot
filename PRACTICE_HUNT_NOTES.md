# Practice hunt — client

Hideout **PRACTICE** opens a cozy confirm (“No Marks… Δ0”), then `POST /matches` `{ mode: "practice" }`. Seat A uses the create `joinToken`. Seat B is the server bot — the client never claims it and never drives bot AI.

## Gates

| Gate | Client |
| --- | --- |
| P1 | Hideout Practice → confirm → create + sit A |
| P2 | Same match HUD (terrain, optic, decoy, exposure, HG/brush). Combat untouched |
| P3 | End overlay **+0 MARK** / **No Marks · Δ0**. Earn table is not shown. A payload `marksDelta` of +25 still displays 0 |
| P4 | Mock bot is server-internal, soft script (recon / decoy / UAV / a fixed hex). Not a Marks farm, not ranked |
| P5 | End can return to hideout. **PLAY AGAIN** stays `mode: practice` (still Δ0) |
| P6 | Paper Practice CTA, no-Marks copy before start, same hunt HUD plus a toy-spy chip |

## Mock

`create_match({ mode: "practice" })` returns `{ matchId, joinToken, seat: "a", mode: "practice" }` and no `joinTokens`. Snapshot `enemy.isBot` / `enemy.placed`. Win, loss, forfeit, and standoff leave the wallet alone. One rematch accept (the bot is not a second client) spawns another practice match.

## LIVE

`python3 tools/live_practice_smoke.py`

If Coder has not shipped `mode: "practice"`, the script prints `LIVE_PRACTICE_PENDING` and the hideout toasts **LIVE practice not ready**. The client will not sit a create that comes back as PvP.

## Stills

```
/tmp/godot --path . --resolution 1280x720 -- --capture-practice-cta
/tmp/godot --path . --resolution 1280x720 -- --capture-practice-no-marks
/tmp/godot --path . --resolution 1280x720 -- --capture-practice-bot
```

`artifacts/ux/practice_cta.png` · `practice_no_marks.png` · `practice_vs_bot.png`
