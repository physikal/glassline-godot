# Terrain coach — notes

One-shot tip chips for **HIGH GROUND** and **BRUSH**. Same wood-plate chrome as the first-hunt coach. Client-only. No API, no Marks, no combat table change. The board stays live.

**Hard:** show once when that tip is relevant · dismiss forever · chip bodies ignore the mouse · never a cover badge · SP jobs skip.

## Behavior

| When | What |
| --- | --- |
| Live hunt, hard hex lights `you.highGroundActive`, high not seen | HIGH GROUND chip + **GOT IT** / **X** |
| Live hunt, `lastAction.coverApplied == true`, brush not seen | BRUSH chip |
| The flag drops before dismiss | Chip stays until **GOT IT** / **X** |
| Dismiss | That kind only is written to `coachTerrainSeen` |
| SP job, ready, or ended | Hidden |
| Other plate captures | `suppressed` hides the chips without marking them seen |

Store: `user://glassline_coach.cfg` (same file as first-hunt, separate key)

```
[coach]
coachTerrainSeen="high,brush"
```

Seeing one tip does not eat the other.

## Copy (toy-spy)

| Chip | Line |
| --- | --- |
| HIGH GROUND | Hard hex lights the chip. You shoot better from up there. |
| BRUSH | Leafy cover softens shots at you. |

## Gates

| ID | Bar | Result |
| --- | --- | --- |
| **C1** | Show once when relevant. Latch until dismiss. | **PASS mock** |
| **C2** | Dismiss forever, per kind (`coachTerrainSeen`) | **PASS mock** |
| **C3** | Board stays interactive. No modal lock. | **PASS mock** |
| **C4** | No API / Marks / combat (`RECON_BASE` 0.35 · ★25 · high-ground +0.10) | **PASS mock** |
| **C5** | Same wood plate, pixel labels, **GOT IT** | **PASS mock** |
| **C6** | Brush uses toast language. No cover badge. | **PASS mock** |
