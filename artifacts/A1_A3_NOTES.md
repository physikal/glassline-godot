# A1 / A3 design gate — mock only

Godot 4.3, `DISPLAY=:1`, `project.godot` with **MOCK** (no `GLASSLINE_USE_LIVE_API`). All actions went through `MatchAPI` → `MockMatchServer`.

## A1 — lobby → Play

1. Boot: `/tmp/godot --path /workspace --resolution 1280x720`
2. Confirm hideout: wood room, operative front-center, rifle rack, intel desk, **PLAY** CTA. Top-right shows **MOCK**.
3. Click green **PLAY** (bottom center). Do not click LIVE.
4. Drop board is the toy war-table (not a black fog stub): walnut desk chrome, **P1 Specter7 / P2 RivalSniper**, printed Open / Brush / Hard stamps with unknown rim, Attack / Recon / **Ability** icons. Board is **9×7 axial** (9 cols × 7 rows, 63 hexes). v0 actions are Attack / Recon / UAV only — no HIGHGROUND buff chrome. Ability still posts MatchAPI `uav`. Placeholder table terrain is visual only.

Stills: `a1-lobby.png`, `a1-after-play.png`.

### After-Play HOLD (2026-09-18)

`artifacts/a1-after-play.png` was a black unknown stub and failed the hex-map plate. Match screen now draws desk wood, hex legend swatches, chunky terrain stamps, P1/P2 tokens, and Ability (UAV) on a **9×7 axial** board (9 cols × 7 rows). HIGHGROUND buff chrome parked (P2). A3 miss/kill stills left as-is.

## A3 — miss then kill (same match)

1. Click a left-center hex (drop). Wait ~0.5s for dummy `select_hex`.
2. Click **START**.
3. **ATTACK** → click an empty hex (not your teal token, not enemy) → optic **FIRE**.
4. Server toast: `lastAction attack hit=false (server)`. End-turn panel at exposure 50. Still: `a3-attack-miss.png`.
5. **END TURN**. Wait “Rival is lining up…” then your action.
6. **UAV** → orange/revealed enemy hex. `lastAction uav revealed=true (server)`.
7. **END TURN**. Wait rival cycle.
8. **ATTACK** the revealed hex → **FIRE**.
9. Overlay: **MARK CONFIRMED / Marks +1**, `lastAction attack hit=true (server)`, `STATUS ended`. Still: `a3-attack-kill.png`.

No mil-sim chrome in frame. No live API.
