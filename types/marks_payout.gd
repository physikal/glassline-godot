extends RefCounted
## Server-owned Marks payout. Client displays only — never `marks +=`.
## Assumed result fields (Coder ledger TBD): marks, marksDelta, reason.
## LIVE still sends endReason=kill on SP bot elimination; display chrome maps that to `job`.

const Contract := preload("res://types/contract.gd")

var marks: Variant = null
var marks_delta: Variant = null
var reason: String = ""
var raw: Dictionary = {}


static func from_any(payload: Dictionary):
	var parsed = new()
	parsed.raw = payload.duplicate(true)
	var bag := _bag(payload)
	if bag.has("marks") and bag.get("marks") != null and not (bag.get("marks") is Dictionary):
		parsed.marks = int(bag.get("marks"))
	if bag.has("marksDelta") and bag.get("marksDelta") != null:
		parsed.marks_delta = int(bag.get("marksDelta"))
	elif bag.has("marks_delta") and bag.get("marks_delta") != null:
		parsed.marks_delta = int(bag.get("marks_delta"))
	parsed.reason = _first_reason(bag, payload)
	if parsed.marks == null:
		var you: Variant = payload.get("you", {})
		if you is Dictionary and you.has("marks"):
			parsed.marks = int(you.get("marks"))
		var wallet: Variant = payload.get("wallet", {})
		if parsed.marks == null and wallet is Dictionary and wallet.has("marks"):
			parsed.marks = int(wallet.get("marks"))
	return parsed


static func _bag(payload: Dictionary) -> Dictionary:
	var bag := {}
	var payout: Variant = payload.get("payout", null)
	if payout is Dictionary:
		for key in payout.keys():
			bag[key] = payout[key]
	var result: Variant = payload.get("result", null)
	if result is Dictionary:
		for key in ["marks", "marksDelta", "marks_delta", "reason"]:
			if result.has(key) and not bag.has(key):
				bag[key] = result[key]
	var last: Variant = payload.get("lastAction", null)
	if last is Dictionary:
		for key in ["marks", "marksDelta", "marks_delta", "reason"]:
			if last.has(key) and not bag.has(key):
				bag[key] = last[key]
	for key in ["marks", "marksDelta", "marks_delta", "reason", "endReason"]:
		if payload.has(key) and not bag.has(key):
			bag[key] = payload[key]
	return bag


static func _first_reason(bag: Dictionary, payload: Dictionary) -> String:
	for key in ["reason", "endReason"]:
		if str(bag.get(key, "")) != "":
			return str(bag.get(key, ""))
	if str(payload.get("endReason", "")) != "":
		return str(payload.get("endReason", ""))
	if str(payload.get("reason", "")) != "":
		return str(payload.get("reason", ""))
	return ""


func has_marks() -> bool:
	return marks != null


func has_delta() -> bool:
	return marks_delta != null


func balance() -> int:
	return int(marks) if has_marks() else 0


func delta() -> int:
	return int(marks_delta) if has_delta() else 0


func delta_line() -> String:
	if not has_delta():
		return ""
	var n := delta()
	if n > 0:
		return "+%d MARK" % n
	if n < 0:
		return "%d MARK" % n
	return "+0 MARK"


func balance_line() -> String:
	if not has_marks():
		return ""
	return "★%d" % balance()


func payout_line() -> String:
	var bits: PackedStringArray = []
	var d := delta_line()
	var b := balance_line()
	if d != "":
		bits.append(d)
	if b != "":
		bits.append(b)
	return "  ·  ".join(bits)


static func is_forfeit_payload(payload: Dictionary) -> bool:
	if bool(payload.get("forfeit", false)) or bool(payload.get("disconnected", false)):
		return true
	var reason := str(payload.get("endReason", payload.get("reason", ""))).to_lower()
	if reason in Contract.FORFEIT_REASONS:
		return true
	var payout: Variant = payload.get("payout", {})
	if payout is Dictionary:
		var pr := str(payout.get("reason", "")).to_lower()
		if pr in Contract.FORFEIT_REASONS:
			return true
	var last: Variant = payload.get("lastAction", {})
	if last is Dictionary:
		var kind := str(last.get("type", "")).to_lower()
		if kind in Contract.FORFEIT_REASONS or bool(last.get("forfeit", false)):
			return true
		var ev := str(last.get("event", "")).to_lower()
		if ev in Contract.FORFEIT_REASONS:
			return true
	return false


static func end_headline(payload: Dictionary, you_seat: String, job: bool) -> String:
	if is_forfeit_payload(payload):
		var win: Variant = payload.get("winner", null)
		if win != null and str(win) == you_seat:
			return "RIVAL FORFEIT"
		return "FORFEIT"
	var win2: Variant = payload.get("winner", null)
	if win2 == Contract.WIN_DRAW or str(win2) == Contract.WIN_DRAW:
		return "STANDOFF"
	if win2 != null and str(win2) == you_seat:
		return "JOB COMPLETE" if job else "MARK CONFIRMED"
	return "JOB FAILED" if job else "ELIMINATED"


static func payload_is_job(payload: Dictionary, job_hint: bool = false) -> bool:
	if job_hint:
		return true
	var kind := str(payload.get("kind", payload.get("mode", payload.get("matchMode", "")))).to_lower()
	if kind in ["sp_job", "job", "sp", "spjob"]:
		return true
	var job_obj: Variant = payload.get("job", null)
	if job_obj is Dictionary and not job_obj.is_empty():
		return true
	if bool(payload.get("spJob", false)) or bool(payload.get("sp", false)):
		return true
	if str(payload.get("jobId", "")) != "":
		return true
	return false


static func display_reason(payload: Dictionary, job_hint: bool = false) -> String:
	var payout = from_any(payload)
	## Prefer the payout bag (winner `kill` / loser `loss` / SP `job`) over LIVE `endReason`.
	var why: String = str(payout.reason).to_lower()
	if why == "":
		why = str(payload.get("endReason", payload.get("reason", ""))).to_lower()
	if why == "":
		return ""
	if not payload_is_job(payload, job_hint):
		return why
	## LIVE still sends endReason=kill (and sometimes payout.reason=kill) for SP bot elimination.
	if why == Contract.END_KILL:
		var win: Variant = payload.get("winner", null)
		var you: Variant = payload.get("you", {})
		var you_seat := str(you.get("seat", "")) if you is Dictionary else ""
		if win != null and you_seat != "" and str(win) != you_seat and str(win) != Contract.WIN_DRAW:
			return Contract.END_JOB_FAIL
		return Contract.END_JOB
	return why


static func table_reason(payload: Dictionary, job: bool = false) -> String:
	## Earn-table token from snapshot endReason + winner. Not payout.reason=loss.
	if payload_is_job(payload, job):
		return display_reason(payload, true)
	if is_forfeit_payload(payload):
		return Contract.END_FORFEIT
	var win: Variant = payload.get("winner", null)
	if win == Contract.WIN_DRAW or str(win) == Contract.WIN_DRAW:
		return Contract.END_STANDOFF
	var er := str(payload.get("endReason", payload.get("reason", ""))).to_lower()
	if er in Contract.FORFEIT_REASONS:
		return Contract.END_FORFEIT
	if er == Contract.END_STANDOFF:
		return Contract.END_STANDOFF
	if er == Contract.END_KILL or er == Contract.END_LOSS:
		return Contract.END_KILL
	if win != null and str(win) != "":
		return Contract.END_KILL
	return display_reason(payload, job)


static func table_delta(payload: Dictionary, you_seat: String, job: bool = false) -> int:
	## Locked earn table. Display only — never `marks +=`.
	var why := table_reason(payload, job)
	var win: Variant = payload.get("winner", null)
	var you_won := win != null and str(win) == you_seat
	var job_obj: Variant = payload.get("job", {})
	var tier := 1
	if job_obj is Dictionary:
		tier = int(job_obj.get("tier", 1))
	elif payload.has("jobTier"):
		tier = int(payload.get("jobTier", 1))
	if why == Contract.END_KILL:
		return Contract.MARKS_PVP_WIN if you_won else Contract.MARKS_PVP_LOSS
	if why == Contract.END_STANDOFF:
		return Contract.MARKS_STANDOFF
	if why in Contract.FORFEIT_REASONS:
		return Contract.MARKS_FORFEIT_WIN if you_won else Contract.MARKS_FORFEIT_LOSS
	if why == Contract.END_JOB:
		return Contract.job_tier_delta(tier)
	if why == Contract.END_JOB_FAIL:
		return Contract.MARKS_JOB_FAIL
	if why == Contract.END_LOSS:
		return Contract.MARKS_PVP_LOSS
	return 0


static func table_copy(end_reason: String, you_won: bool, job_tier: int = 1) -> String:
	## Display chrome only — never apply these as a local grant.
	var why := end_reason.to_lower()
	if why == Contract.END_KILL:
		return "table  +%d" % (Contract.MARKS_PVP_WIN if you_won else Contract.MARKS_PVP_LOSS)
	if why == Contract.END_STANDOFF:
		return "table  +%d" % Contract.MARKS_STANDOFF
	if why in Contract.FORFEIT_REASONS:
		return "table  +%d" % (Contract.MARKS_FORFEIT_WIN if you_won else Contract.MARKS_FORFEIT_LOSS)
	if why in [Contract.END_JOB, Contract.END_JOB_FAIL]:
		if you_won:
			return "table  T%d +%d" % [job_tier, Contract.job_tier_delta(job_tier)]
		return "table  +0"
	if why == Contract.END_LOSS:
		return "table  +%d" % Contract.MARKS_PVP_LOSS
	return ""


static func live_delta_drifts(payload: Dictionary, you_seat: String, job: bool = false) -> bool:
	## True only when a payload marksDelta exists and disagrees with the table.
	var payout = from_any(payload)
	if not payout.has_delta():
		return false
	return payout.delta() != table_delta(payload, you_seat, job)


static func marks_line(payload: Dictionary, you_seat: String, job: bool = false) -> String:
	var n := table_delta(payload, you_seat, job)
	var d := "+%d MARK" % n if n >= 0 else "%d MARK" % n
	var payout = from_any(payload)
	if payout.has_marks():
		return "%s  ·  ★%d" % [d, payout.balance()]
	return d


static func overlay_parts(payload: Dictionary, you_seat: String, job: bool = false) -> Dictionary:
	return {
		"headline": end_headline(payload, you_seat, job),
		"marks": marks_line(payload, you_seat, job),
		"reason": table_reason(payload, job),
		"delta": table_delta(payload, you_seat, job),
		"drift": live_delta_drifts(payload, you_seat, job),
	}


static func end_overlay(payload: Dictionary, you_seat: String, job: bool = false) -> String:
	## Headline · +N MARK · ★you.marks · table reason. Δ is the earn table.
	var parts := overlay_parts(payload, you_seat, job)
	var lines: PackedStringArray = [str(parts.get("headline", ""))]
	var marks := str(parts.get("marks", ""))
	if marks != "":
		lines.append(marks)
	var why := str(parts.get("reason", ""))
	if why != "":
		lines.append(why)
	return "\n".join(lines)
