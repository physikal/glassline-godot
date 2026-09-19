extends RefCounted
## Caller-scoped snapshot. Wrap a contract dictionary; do not invent fields.

const Contract := preload("res://types/contract.gd")
const MarksPayout := preload("res://types/marks_payout.gd")

var raw: Dictionary = {}


static func from_dict(d: Dictionary):
	var snap = new()
	snap.raw = d.duplicate(true)
	return snap


func to_dict() -> Dictionary:
	return raw.duplicate(true)


func match_id() -> String:
	return str(raw.get("matchId", ""))


func status() -> String:
	return str(raw.get("status", ""))


func turn_index() -> int:
	return int(raw.get("turnIndex", 0))


func turn_cap() -> int:
	return int(raw.get("turnCap", Contract.TURN_CAP))


func whose_turn() -> Variant:
	return raw.get("whoseTurn", null)


func phase() -> Variant:
	return raw.get("phase", null)


func uav_remaining() -> int:
	if raw.has("uavRemaining"):
		return int(raw.get("uavRemaining", 0))
	if raw.has("uavAvailable"):
		return 1 if bool(raw.get("uavAvailable", false)) else 0
	return 0


func kind() -> String:
	var value := str(raw.get("kind", ""))
	if value != "":
		return Contract.MODE_SP_JOB if value in ["sp_job", "job"] else value
	return mode()


func mode() -> String:
	var kind_value := str(raw.get("kind", ""))
	if kind_value in ["sp_job", "job"]:
		return Contract.MODE_SP_JOB
	if kind_value == Contract.MODE_PVP:
		return Contract.MODE_PVP
	var value := str(raw.get("mode", raw.get("matchMode", "")))
	if value == "":
		var job_obj: Variant = raw.get("job", null)
		if job_obj is Dictionary and not job_obj.is_empty():
			return Contract.MODE_SP_JOB
		if bool(raw.get("spJob", false)) or str(raw.get("jobId", "")) != "":
			return Contract.MODE_SP_JOB
		return Contract.MODE_PVP
	if value in ["job", "sp", "spJob", "sp_job"]:
		return Contract.MODE_SP_JOB
	return value


func is_job() -> bool:
	return mode() == Contract.MODE_SP_JOB


func job() -> Dictionary:
	var value: Variant = raw.get("job", {})
	return value if value is Dictionary else {}


func job_tier() -> int:
	var bag := job()
	if bag.has("tier"):
		return int(bag.get("tier", 1))
	return int(raw.get("jobTier", raw.get("tier", 1)))


func payout():
	return MarksPayout.from_any(raw)


func marks_delta() -> Variant:
	var pay = MarksPayout.from_any(raw)
	return pay.marks_delta


func end_reason() -> String:
	var why: String = MarksPayout.display_reason(raw, is_job())
	if why != "":
		return why
	var pay = MarksPayout.from_any(raw)
	if str(pay.reason) != "":
		return str(pay.reason)
	return str(raw.get("endReason", raw.get("reason", "")))


func is_forfeit() -> bool:
	return MarksPayout.is_forfeit_payload(raw)


func you() -> Dictionary:
	var value: Variant = raw.get("you", {})
	return value if value is Dictionary else {}


func enemy() -> Dictionary:
	var value: Variant = raw.get("enemy", {})
	return value if value is Dictionary else {}


func terrain() -> Array:
	var value: Variant = raw.get("terrain", [])
	return value if value is Array else []


func last_action() -> Variant:
	return raw.get("lastAction", null)


func last_hit() -> Variant:
	## Server lastAction.hit only. Null if the snapshot did not say hit.
	var last: Variant = last_action()
	if last is Dictionary and last.has("hit"):
		return last.get("hit")
	return null


func winner() -> Variant:
	return raw.get("winner", null)


func you_hex() -> Variant:
	return you().get("hex", null)


func you_placed() -> bool:
	var you_state := you()
	if you_state.has("placed"):
		return bool(you_state.get("placed", false))
	return you_state.get("hex", null) != null


func you_seat() -> String:
	return str(you().get("seat", ""))


func you_marks() -> int:
	return int(you().get("marks", 0))


func you_equipped_skin_id() -> String:
	## Caller-scoped chrome id. Empty unless the snapshot named it. Never invent.
	var you_state := you()
	for key in ["equippedSkinId", "equipped"]:
		if you_state.has(key):
			var value: Variant = you_state.get(key)
			if value == null:
				return ""
			if value is Dictionary:
				return str(value.get("itemId", value.get("id", "")))
			return str(value)
	var cosmetics: Variant = you_state.get("cosmetics", {})
	if cosmetics is Dictionary and cosmetics.has("equipped"):
		var worn: Variant = cosmetics.get("equipped")
		if worn == null:
			return ""
		return str(worn)
	return ""


func you_exposure() -> float:
	return float(you().get("exposurePct", Contract.DEFAULT_EXPOSURE))


func you_moved_last_turn() -> bool:
	return bool(you().get("movedLastTurn", false))


func enemy_visible_hex() -> Variant:
	return enemy().get("visibleHex", null)


func enemy_soft_hot() -> int:
	return int(enemy().get("softHotTurnsLeft", 0))


func is_your_turn() -> bool:
	return status() == Contract.STATUS_ACTIVE and str(whose_turn()) == you_seat()


func terrain_map() -> Dictionary:
	var mapped := {}
	for entry in terrain():
		if entry is Dictionary:
			mapped[Contract.hex_key(entry)] = str(entry.get("type", Contract.TYPE_OPEN))
	return mapped
