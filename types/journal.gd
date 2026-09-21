extends RefCounted
## Server journal rows only. Never builds a hunt the payload did not list.

const Contract := preload("res://types/contract.gd")


static func from_http(status: int, body: Variant) -> Dictionary:
	## GET /journal shape. 404 stays empty so the client can mock until the route exists.
	var js: Dictionary = body if body is Dictionary else {}
	if status == 0:
		var net := str(js.get("error", "not_connected"))
		return {"ok": false, "error": net, "status": 0, "entries": []}
	if status == 404 or str(js.get("error", "")) == Contract.JOURNAL_ERR_UNAVAILABLE:
		return {
			"ok": false,
			"error": Contract.JOURNAL_ERR_UNAVAILABLE,
			"status": 404 if status == 0 else status,
			"entries": [],
		}
	if status == 401 or str(js.get("error", "")) == Contract.JOURNAL_ERR_MISSING:
		return {
			"ok": false,
			"error": Contract.JOURNAL_ERR_MISSING,
			"status": 401,
			"entries": [],
		}
	if status >= 400:
		var err := str(js.get("error", "http_%s" % status))
		return {"ok": false, "error": err, "status": status, "entries": []}
	var raw: Variant = js.get("entries", [])
	if not (raw is Array):
		raw = []
	return {"ok": true, "error": "", "status": status, "entries": raw}


static func payload(body: Dictionary) -> Dictionary:
	## Keep server order (newest first). Cap at 10. Drop blank rows. Practice Δ stays 0.
	var raw: Variant = body.get("entries", [])
	var rows: Array = []
	if raw is Array:
		for item in raw:
			if not (item is Dictionary):
				continue
			var row := normalize(item)
			if str(row.get("matchId", "")) == "":
				continue
			rows.append(row)
			if rows.size() >= Contract.JOURNAL_LIMIT:
				break
	return {
		"ok": bool(body.get("ok", true)) and str(body.get("error", "")) == "",
		"error": str(body.get("error", "")),
		"status": int(body.get("status", 200)),
		"entries": rows,
	}


static func normalize(entry: Dictionary) -> Dictionary:
	var mode := str(entry.get("mode", entry.get("kind", ""))).to_lower()
	if mode in ["job", "sp", "spjob"]:
		mode = Contract.MODE_SP_JOB
	var practice := mode == Contract.MODE_PRACTICE
	var delta := 0 if practice else int(entry.get("marksDelta", entry.get("marks_delta", 0)))
	var rival := _rival(entry)
	var available := bool(entry.get("rematchAvailable", entry.get("rematch_available", false)))
	if mode == Contract.MODE_SP_JOB:
		available = false
	return {
		"matchId": str(entry.get("matchId", entry.get("match_id", ""))),
		"mode": mode,
		"result": _result_token(str(entry.get("result", ""))),
		"rival": rival,
		"marksDelta": delta,
		"endedAt": str(entry.get("endedAt", entry.get("ended_at", ""))),
		"rematchAvailable": available,
	}


static func is_empty(body: Dictionary) -> bool:
	var entries: Variant = body.get("entries", [])
	return not (entries is Array) or (entries as Array).is_empty()


static func action_for(entry: Dictionary) -> String:
	## PvP rematch only when the ledger says so. Practice again is a practice create.
	if not bool(entry.get("rematchAvailable", false)):
		return ""
	var mode := str(entry.get("mode", ""))
	if mode == Contract.MODE_PRACTICE:
		return "practice"
	if mode == Contract.MODE_SP_JOB:
		return ""
	return "rematch"


static func cta_enabled(entry: Dictionary) -> bool:
	return action_for(entry) != ""


static func cta_text(entry: Dictionary) -> String:
	if str(entry.get("mode", "")) == Contract.MODE_PRACTICE:
		return Contract.JOURNAL_PRACTICE_AGAIN
	return Contract.JOURNAL_REMATCH


static func mode_tag(entry: Dictionary) -> String:
	var mode := str(entry.get("mode", ""))
	if mode == Contract.MODE_PRACTICE:
		return Contract.JOURNAL_TAG_PRACTICE
	if mode == Contract.MODE_SP_JOB:
		return Contract.JOURNAL_TAG_JOB
	return Contract.JOURNAL_TAG_QUICK


static func result_text(entry: Dictionary) -> String:
	match str(entry.get("result", "")):
		"win":
			return Contract.JOURNAL_RESULT_WIN
		"loss":
			return Contract.JOURNAL_RESULT_LOSS
		"forfeit":
			return Contract.JOURNAL_RESULT_FORFEIT
		"draw", "standoff":
			return Contract.JOURNAL_RESULT_DRAW
		_:
			return str(entry.get("result", "")).to_upper()


static func marks_text(entry: Dictionary) -> String:
	var n := int(entry.get("marksDelta", 0))
	if str(entry.get("mode", "")) == Contract.MODE_PRACTICE:
		n = 0
	return Contract.format_marks_delta(n)


static func rival_text(entry: Dictionary) -> String:
	var rival: Variant = entry.get("rival", {})
	if rival is Dictionary:
		var name := str(rival.get("displayName", rival.get("name", "")))
		if name != "":
			return name
		if bool(rival.get("isBot", false)):
			return Contract.PRACTICE_RIVAL
	elif rival is String and str(rival) != "":
		return str(rival)
	return "RIVAL"


static func _rival(entry: Dictionary) -> Dictionary:
	var raw: Variant = entry.get("rival", entry.get("opponent", {}))
	if raw is String:
		return {"displayName": str(raw), "isBot": false}
	if not (raw is Dictionary):
		raw = {}
	var bag: Dictionary = raw
	var name := str(bag.get("displayName", bag.get("name", "")))
	var bot := bool(bag.get("isBot", bag.get("bot", false)))
	return {"displayName": name, "isBot": bot}


static func _result_token(raw: String) -> String:
	var token := raw.to_lower()
	if token in ["win", "won", "victory"]:
		return "win"
	if token in ["loss", "lose", "lost", "defeat"]:
		return "loss"
	if token in ["forfeit", "disconnect", "disconnected"]:
		return "forfeit"
	if token in ["draw", "standoff"]:
		return "draw"
	return token
