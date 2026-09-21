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
| Soft P2 | PRACTICE dock icon matches Quick Match / Invite. Match toast does not print `lastAction start…` |

## Mock

`create_match({ mode: "practice" })` returns `{ matchId, joinToken, seat: "a", mode: "practice" }` and no `joinTokens`. Snapshot `enemy.isBot` / `enemy.placed`. Win, loss, forfeit, and standoff leave the wallet alone. One rematch accept (the bot is not a second client) spawns another practice match.

## LIVE

`python3 tools/live_practice_smoke.py` against `https://glassline-api.vercel.app`.

Create envelope is `{ matchId, joinToken, seat: "a" }` — no `mode`. The snapshot carries `mode` / `kind: practice` and `enemy.isBot`. The hideout peeks that snapshot **before** join and refuses anything that is not practice + bot, so a PvP create cannot fall through to Marks.

API tip `ca28069`. Client bind on this branch. Evidence: `artifacts/live_practice_smoke.txt`.

| Gate | Result | Evidence |
| --- | --- | --- |
| P1 | PASS | `POST /matches` 201, join 200 seat A, snapshot `mode: practice` |
| P2 | PASS | terrain open/brush/hard, recon, decoy, exposure 37, UAV, occupy `hitChance` 0.9 with `highGroundApplied` + `coverApplied`. Empty shot `hitChance` 0 |
| P3 | PASS | kill `endReason: kill`, `you.marks` 0 and `GET /shop/me` 0 (PvP win would be +25) |
| P4 | PASS | `enemy.isBot` true through the end. Empty-seat claim 409 |
| P5 | PASS | Rematch 200 `ready` + new practice match + bot. Forfeit then decline `declined` (hideout), wallet still 0 |
| P6 | PASS | Hideout Practice CTA and “No Marks… Δ0” confirm before start |

## Stills

```
/tmp/godot --path . --resolution 1280x720 -- --capture-practice-cta
/tmp/godot --path . --resolution 1280x720 -- --capture-practice-no-marks
/tmp/godot --path . --resolution 1280x720 -- --capture-practice-bot
```

`artifacts/ux/practice_cta.png` · `practice_no_marks.png` · `practice_vs_bot.png`
