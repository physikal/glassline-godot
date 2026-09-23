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
	return Contract.format_marks_delta(delta())


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


static func end_headline(payload: Dictionary, you_seat: String, job: bool, practice: bool = false) -> String:
	if practice or payload_is_practice(payload):
		if is_forfeit_payload(payload):
			var fwin: Variant = payload.get("winner", null)
			if fwin != null and str(fwin) == you_seat:
				return Contract.PRACTICE_SPY_LEFT
			return Contract.PRACTICE_LEFT
		var pwin: Variant = payload.get("winner", null)
		if pwin == Contract.WIN_DRAW or str(pwin) == Contract.WIN_DRAW:
			return "STANDOFF"
		if pwin != null and str(pwin) == you_seat:
			return Contract.PRACTICE_CLEAR
		return Contract.PRACTICE_OVER
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


static func payload_is_practice(payload: Dictionary, practice_hint: bool = false) -> bool:
	if practice_hint:
		return true
	var kind := str(payload.get("kind", payload.get("mode", payload.get("matchMode", "")))).to_lower()
	return kind == Contract.MODE_PRACTICE


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
	if payload_is_practice(payload):
		return "no marks"
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


static func table_reason(payload: Dictionary, job: bool = false, practice: bool = false) -> String:
	## Earn-table token from snapshot endReason + winner. Not payout.reason=loss.
	## Practice has no earn line — the overlay says so instead of kill / +32.
	if practice or payload_is_practice(payload):
		return "no marks"
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


static func _job_tier(payload: Dictionary) -> int:
	## `job.tier` when the bag has one. Otherwise top-level `jobTier`. Missing stays T1.
	var job_obj: Variant = payload.get("job", null)
	if job_obj is Dictionary and (job_obj as Dictionary).has("tier"):
		return int(job_obj.get("tier", 1))
	if payload.has("jobTier"):
		return int(payload.get("jobTier", 1))
	return 1


static func table_delta(payload: Dictionary, you_seat: String, job: bool = false, practice: bool = false) -> int:
	## Locked earn table. Display only — never `marks +=`.
	## Practice is Δ0 on every ending. The earn table does not apply.
	if practice or payload_is_practice(payload):
		return Contract.MARKS_PRACTICE
	var why := table_reason(payload, job, false)
	var win: Variant = payload.get("winner", null)
	var you_won := win != null and str(win) == you_seat
	var tier := _job_tier(payload)
	if why == Contract.END_KILL:
		return Contract.MARKS_PVP_WIN if you_won else Contract.MARKS_PVP_LOSS
	if why == Contract.END_STANDOFF:
		return Contract.MARKS_STANDOFF
	if why in Contract.FORFEIT_REASONS:
		return Contract.MARKS_FORFEIT_WIN if you_won else Contract.MARKS_FORFEIT_LOSS
	if why == Contract.END_JOB:
		return Contract.job_tier_delta(tier)
	if why == Contract.END_JOB_FAIL:
		return Contract.job_tier_fail_delta(tier)
	if why == Contract.END_LOSS:
		return Contract.MARKS_PVP_LOSS
	return 0


static func table_copy(end_reason: String, you_won: bool, job_tier: int = 1) -> String:
	## Display chrome only — never apply these as a local grant.
	## Not painted on the end plate. The number still uses the one Δ chip.
	var why := end_reason.to_lower()
	if why == Contract.END_KILL:
		var kill_n := Contract.MARKS_PVP_WIN if you_won else Contract.MARKS_PVP_LOSS
		return "table  %s" % Contract.format_marks_delta(kill_n)
	if why == Contract.END_STANDOFF:
		return "table  %s" % Contract.format_marks_delta(Contract.MARKS_STANDOFF)
	if why in Contract.FORFEIT_REASONS:
		var foil_n := Contract.MARKS_FORFEIT_WIN if you_won else Contract.MARKS_FORFEIT_LOSS
		return "table  %s" % Contract.format_marks_delta(foil_n)
	if why in [Contract.END_JOB, Contract.END_JOB_FAIL]:
		if you_won:
			return "table  T%d %s" % [job_tier, Contract.format_marks_delta(Contract.job_tier_delta(job_tier))]
		return "table  %s" % Contract.format_marks_delta(Contract.job_tier_fail_delta(job_tier))
	if why == Contract.END_LOSS:
		return "table  %s" % Contract.format_marks_delta(Contract.MARKS_PVP_LOSS)
	return ""


static func live_delta_drifts(payload: Dictionary, you_seat: String, job: bool = false, practice: bool = false) -> bool:
	## True only when a payload marksDelta exists and disagrees with the table.
	var payout = from_any(payload)
	if not payout.has_delta():
		return false
	return payout.delta() != table_delta(payload, you_seat, job, practice)


static func marks_line(payload: Dictionary, you_seat: String, job: bool = false, practice: bool = false) -> String:
	var n := table_delta(payload, you_seat, job, practice)
	var d := Contract.format_marks_delta(n)
	var payout = from_any(payload)
	if payout.has_marks():
		return "%s  ·  ★%d" % [d, payout.balance()]
	return d


static func overlay_parts(payload: Dictionary, you_seat: String, job: bool = false, practice: bool = false) -> Dictionary:
	var quiet := practice or payload_is_practice(payload)
	return {
		"headline": end_headline(payload, you_seat, job, quiet),
		"marks": marks_line(payload, you_seat, job, quiet),
		"reason": table_reason(payload, job, quiet),
		"delta": table_delta(payload, you_seat, job, quiet),
		"drift": live_delta_drifts(payload, you_seat, job, quiet),
	}


static func end_overlay(payload: Dictionary, you_seat: String, job: bool = false) -> String:
	## Headline · 0/+N/-N · ★you.marks · table reason. Δ is the earn table.
	var parts := overlay_parts(payload, you_seat, job)
	var lines: PackedStringArray = [str(parts.get("headline", ""))]
	var marks := str(parts.get("marks", ""))
	if marks != "":
		lines.append(marks)
	var why := str(parts.get("reason", ""))
	if why != "":
		lines.append(why)
	return "\n".join(lines)
