# Glassline API contract LOCKED v0 (2026-09-18)

Client spike types in `types/` and `MockMatchServer` follow this shape so a live HTTPS+SSE swap does not rewrite payloads.

## Principles
- Server owns secret positions, turn index, terrain, spot/UAV/kill.
- Client sends intents only — never hit/terrain as truth.
- Reconnect = caller-scoped snapshot. Client never invents terrain or "I hit."
- Attack miss ≠ invent Hot.

## Board
- 9×7 axial (q,r) — 0≤q<9, 0≤r<7
- Terrain on first select: open | brush | hard via hash(match_id,q,r,salt)

## Lifecycle
1. POST /matches → { matchId, joinTokens: { a, b } }
2. POST /matches/:id/join { token } → { playerId, seat, snapshot }
3. Drop: both select_hex while ready; re-drop OK until start
4. start once both placed → active, whoseTurn a, turnIndex 0, exposurePct 50
5. Turns: exactly one of attack|recon|uav|decoy, then required end_turn
6. turnCap 16 total (8 each) → draw if no kill
7. Kill → Marks +1 winner

## Snapshot (caller-scoped)
```
{
  matchId, status: waiting|ready|active|ended,
  turnIndex, turnCap: 16, whoseTurn: a|b|null,
  phase: await_action|await_end_turn|null,
  uavRemaining: 0|1,
  you: { seat, hex, placed, marks, exposurePct, movedLastTurn },
  enemy: { seat, visibleHex, softHotTurnsLeft },
  terrain: [{ q, r, type }],
  lastAction, winner: a|b|draw|null,
  rematch?: { status: none|pending|accepted_a|accepted_b|ready|declined|expired, newMatchId? }
}
```

## Actions POST /matches/:id/actions
- { type: "select_hex", hex: {q,r} }
- { type: "start" }
- { type: "attack", hex: {q,r} }
- { type: "recon", hex: {q,r} }  // sector = center + 6 neighbors
- { type: "uav" }
- { type: "decoy" }  // no hex; server picks adjacent empty. LIVE pending Coder.
- { type: "end_turn", exposurePct: number, hex?: {q,r} }

## ActionResult (spike + live-shaped)
```
{ ok, error, snapshot, event: snapshot|your_turn }
```

## Realtime
SSE default GET /matches/:id/events → { event: snapshot|your_turn, snapshot }
WS later same payload. Auth: Bearer from join.
