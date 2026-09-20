extends RefCounted
## Quick Match queue payload. Queued → matched { matchId, joinToken }.
## Cancel / timeout never invent Marks or a forfeit overlay.

const Contract := preload("res://types/contract.gd")

var ok: bool = false
var error: String = ""
var code_name: String = ""
var status: String = ""
var match_id: String = ""
var join_token: String = ""
var seat: String = ""
var player_id: String = ""
var queued_at: String = ""
var timeout_sec: int = Contract.QUEUE_TTL_SEC
var seconds_left: int = -1
var snapshot: Dictionary = {}
var marks: int = 0
var has_marks: bool = false
var timed_out: bool = false
var http_status: int = 0
var raw: Dictionary = {}


static func from_any(value: Variant) -> RefCounted:
	var parsed = new()
	if value is Dictionary:
		parsed._ingest(value)
	return parsed


func _ingest(bag: Dictionary) -> void:
	raw = bag.duplicate(true)
	http_status = int(bag.get("httpStatus", 0))
	error = str(bag.get("error", ""))
	code_name = str(bag.get("code", error))
	status = str(bag.get("status", ""))
	match_id = str(bag.get("matchId", bag.get("newMatchId", "")))
	join_token = str(bag.get("joinToken", ""))
	seat = str(bag.get("seat", ""))
	player_id = str(bag.get("playerId", ""))
	queued_at = str(bag.get("queuedAt", ""))
	timeout_sec = int(bag.get("timeoutSec", Contract.QUEUE_TTL_SEC))
	timed_out = bool(bag.get("timedOut", false))
	var q: Variant = bag.get("queue", {})
	if q is Dictionary:
		if status == "":
			status = str(q.get("status", ""))
		if q.has("secondsLeft"):
			seconds_left = int(q.get("secondsLeft"))
		if bool(q.get("timedOut", false)):
			timed_out = true
	if bag.has("secondsLeft"):
		seconds_left = int(bag.get("secondsLeft"))
	var snap: Variant = bag.get("snapshot", {})
	if snap is Dictionary:
		snapshot = snap
		if status == "" and str(snap.get("status", "")) != "":
			status = str(snap.get("status"))
		if match_id == "":
			match_id = str(snap.get("matchId", ""))
		if join_token == "":
			join_token = str(snap.get("joinToken", ""))
		if seat == "":
			seat = str(snap.get("seat", ""))
		if player_id == "":
			player_id = str(snap.get("playerId", ""))
		var q_snap: Variant = snap.get("queue", {})
		if q_snap is Dictionary:
			if status == "":
				status = str(q_snap.get("status", ""))
			if seconds_left < 0 and q_snap.has("secondsLeft"):
				seconds_left = int(q_snap.get("secondsLeft"))
		var you_snap: Variant = snap.get("you", {})
		if you_snap is Dictionary:
			if seat == "":
				seat = str(you_snap.get("seat", ""))
			if player_id == "" and str(you_snap.get("playerId", "")) != "":
				player_id = str(you_snap.get("playerId"))
			if you_snap.has("marks"):
				has_marks = true
				marks = int(you_snap.get("marks"))
	var you: Variant = bag.get("you", {})
	if you is Dictionary:
		if you.has("marks"):
			has_marks = true
			marks = int(you.get("marks"))
		if seat == "":
			seat = str(you.get("seat", ""))
		if player_id == "" and str(you.get("playerId", "")) != "":
			player_id = str(you.get("playerId"))
	if bag.has("marks"):
		has_marks = true
		marks = int(bag.get("marks"))
	if status == Contract.LOBBY_READY and match_id != "" and join_token != "":
		status = Contract.QUEUE_MATCHED
	if status == "" and match_id != "" and join_token != "":
		status = Contract.QUEUE_MATCHED
	if bag.has("ok"):
		ok = bool(bag.get("ok"))
	else:
		ok = error == "" and status != ""
	if is_unavailable():
		ok = false
	if is_reject() and not is_idle() and not is_timeout():
		ok = false


func is_queued() -> bool:
	return status == Contract.QUEUE_QUEUED


func is_matched() -> bool:
	return status == Contract.QUEUE_MATCHED and match_id != "" and join_token != ""


func is_idle() -> bool:
	return status == Contract.QUEUE_IDLE and not timed_out and not is_timeout()


func is_timeout() -> bool:
	if timed_out or status == Contract.QUEUE_TIMEOUT:
		return true
	if is_queued() and seconds_left == 0:
		return true
	return false


func is_unavailable() -> bool:
	return error == Contract.QUEUE_ERR_UNAVAILABLE or code_name == Contract.QUEUE_ERR_UNAVAILABLE


func is_reject() -> bool:
	if is_unavailable():
		return false
	if error == "" and code_name == "":
		return false
	return code_name in [
		Contract.QUEUE_ERR_MATCHED,
		Contract.QUEUE_ERR_FORBIDDEN,
		"already_in_queue",
		"queue_full",
	] or error != ""


func reject_copy() -> String:
	if is_unavailable():
		return Contract.QUEUE_UNAVAILABLE_COPY
	if is_timeout():
		return Contract.QUEUE_TIMEOUT_COPY
	return Contract.QUEUE_HIDEOUT_COPY
