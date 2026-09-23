extends RefCounted
## Server journal rows only. Never builds a hunt the payload did not list.

const Contract := preload("res://types/contract.gd")
const MarksPayout := preload("res://types/marks_payout.gd")


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
	var row := {
		"matchId": str(entry.get("matchId", entry.get("match_id", ""))),
		"mode": mode,
		"result": _result_token(str(entry.get("result", ""))),
		"rival": rival,
		"marksDelta": delta,
		"endedAt": str(entry.get("endedAt", entry.get("ended_at", ""))),
		"rematchAvailable": available,
	}
	## Display hints only. The ledger number above is not rewritten.
	var why := str(entry.get("endReason", entry.get("reason", ""))).to_lower()
	if why != "":
		row["endReason"] = why
	var tier := _stated_tier(entry)
	if tier >= 1:
		row["jobTier"] = tier
	return row


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
	## Wood chip. Locked earn table, not the ledger number.
	## Practice is always 0. Does not write marksDelta or the wallet.
	return Contract.format_marks_delta(display_delta(entry))


static func display_delta(entry: Dictionary) -> int:
	var mode := _mode_of(entry)
	if mode == Contract.MODE_PRACTICE:
		return Contract.MARKS_PRACTICE
	var payload := _table_payload(entry, mode)
	if payload.is_empty():
		return int(entry.get("marksDelta", entry.get("marks_delta", 0)))
	var job := mode == Contract.MODE_SP_JOB
	return MarksPayout.table_delta(payload, Contract.SEAT_A, job, false)


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


static func _mode_of(entry: Dictionary) -> String:
	var mode := str(entry.get("mode", entry.get("kind", ""))).to_lower()
	if mode in ["job", "sp", "spjob"]:
		return Contract.MODE_SP_JOB
	return mode


static func _stated_tier(entry: Dictionary) -> int:
	var job_obj: Variant = entry.get("job", null)
	if job_obj is Dictionary and (job_obj as Dictionary).has("tier"):
		var from_job := int((job_obj as Dictionary).get("tier", 0))
		if from_job >= 1:
			return from_job
	if entry.has("jobTier") and int(entry.get("jobTier", 0)) >= 1:
		return int(entry.get("jobTier"))
	if entry.has("tier") and int(entry.get("tier", 0)) >= 1:
		return int(entry.get("tier"))
	return 0


static func _entry_tier(entry: Dictionary, raw: int, result: String, job: bool) -> int:
	var stated := _stated_tier(entry)
	if stated >= 1:
		return stated
	if not job:
		return 1
	if result == "win":
		if raw == Contract.MARKS_JOB_T3 or raw == 20:
			return 3
		## Previous T2 grant was +15. New T2 is +18. Both paint ★18.
		if raw == Contract.MARKS_JOB_T2 or raw == 15:
			return 2
		return 1
	if raw == Contract.MARKS_JOB_FAIL_T2 or raw == Contract.MARKS_JOB_FAIL_T3:
		return 2
	return 1


static func _infer_reason(result: String, job: bool, raw: int) -> String:
	## Rows that only carry the old ledger number still paint the lock.
	if result in ["draw", "standoff"]:
		return Contract.END_STANDOFF
	if result == "forfeit":
		return Contract.END_FORFEIT
	if job and result == "win":
		return Contract.END_JOB
	if job and result == "loss":
		return Contract.END_JOB_FAIL
	if result == "win":
		## Previous forfeit win was +12. The lock is +15. Kill stays +32.
		if raw == 12 or raw == Contract.MARKS_FORFEIT_WIN:
			return Contract.END_FORFEIT
		return Contract.END_KILL
	if result == "loss":
		return Contract.END_LOSS
	return ""


static func _table_payload(entry: Dictionary, mode: String) -> Dictionary:
	var result := _result_token(str(entry.get("result", "")))
	var why := str(entry.get("endReason", entry.get("reason", ""))).to_lower()
	var raw := int(entry.get("marksDelta", entry.get("marks_delta", 0)))
	var job := mode == Contract.MODE_SP_JOB
	if why == "":
		why = _infer_reason(result, job, raw)
	if why == "":
		return {}
	var winner := Contract.SEAT_A
	if result in ["draw", "standoff"] or why == Contract.END_STANDOFF:
		winner = Contract.WIN_DRAW
	elif result in ["loss", "forfeit"] or why in [Contract.END_JOB_FAIL, Contract.END_LOSS]:
		winner = Contract.SEAT_B
	elif why in Contract.FORFEIT_REASONS and result != "win":
		winner = Contract.SEAT_B
	var payload := {
		"mode": mode,
		"kind": mode,
		"endReason": why,
		"winner": winner,
		"you": {"seat": Contract.SEAT_A},
	}
	if job:
		var tier := _entry_tier(entry, raw, result, true)
		payload["job"] = {"tier": tier}
		payload["jobTier"] = tier
	return payload


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
