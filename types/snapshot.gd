extends RefCounted
## Caller-scoped snapshot. Wrap a contract dictionary; do not invent fields.

const Contract := preload("res://types/contract.gd")

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
	return int(raw.get("uavRemaining", 0))


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


func winner() -> Variant:
	return raw.get("winner", null)


func you_hex() -> Variant:
	return you().get("hex", null)


func you_placed() -> bool:
	return bool(you().get("placed", false))


func you_seat() -> String:
	return str(you().get("seat", ""))


func you_marks() -> int:
	return int(you().get("marks", 0))


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
