"""LIVE /matches create+join — single joinToken spine (API c71f113).

POST /matches → { matchId, joinToken, seat: "a" } (never both seats).
Seat B claims via POST /players + POST /matches/:id/join {}.
"""

from __future__ import annotations


def sit_created_pvp(req, player_token: str | None = None, guest_token: str | None = None) -> dict:
    status, created, _ = req("POST", "/matches", {}, player_token)
    if status not in (200, 201) or "matchId" not in created:
        return {
            "ok": False,
            "status": status,
            "created": created if isinstance(created, dict) else {},
            "error": (created or {}).get("error", "no matchId") if isinstance(created, dict) else "no matchId",
        }
    match_id = str(created.get("matchId", ""))
    token_a = str(created.get("joinToken") or (created.get("joinTokens") or {}).get("a") or "")
    _, join_a, _ = req("POST", f"/matches/{match_id}/join", {"token": token_a}, player_token)
    guest_tok = guest_token or ""
    if guest_tok == "":
        _, guest, _ = req("POST", "/players", {})
        guest_tok = str((guest or {}).get("token") or "")
    _, join_b, _ = req("POST", f"/matches/{match_id}/join", {}, guest_tok)
    token_b = str((join_b or {}).get("joinToken") or (created.get("joinTokens") or {}).get("b") or "")
    return {
        "ok": True,
        "status": status,
        "matchId": match_id,
        "token_a": token_a,
        "token_b": token_b,
        "seat": str(created.get("seat") or "a"),
        "created": created,
        "join_a": join_a if isinstance(join_a, dict) else {},
        "join_b": join_b if isinstance(join_b, dict) else {},
        "dual_tokens": "joinTokens" in created,
    }
