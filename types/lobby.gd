extends RefCounted
## Private lobby invite payload. Waiting → ready { matchId, joinToken }.
## Cancel / expired / bad code never invent Marks or a forfeit overlay.

const Contract := preload("res://types/contract.gd")

var ok: bool = false
var error: String = ""
var code_name: String = ""
var status: String = ""
var lobby_id: String = ""
var code: String = ""
var match_id: String = ""
var join_token: String = ""
var seat: String = ""
var player_id: String = ""
var snapshot: Dictionary = {}
var marks: int = 0
var has_marks: bool = false
var http_status: int = 0
var raw: Dictionary = {}


static func from_any(value: Variant) -> RefCounted:
	var parsed = new()
	if value is Dictionary:
		parsed._ingest(value)
	return parsed


func _ingest(bag: Dictionary) -> void:
	raw = bag.duplicate(true)
	http_status = int(bag.get("httpStatus", bag.get("status", 0)))
	if http_status > 0 and http_status < 100:
		## Mock/LIVE sometimes put lobby status in `status` (waiting|ready).
		if str(bag.get("status", "")) in [
			Contract.LOBBY_WAITING,
			Contract.LOBBY_READY,
			Contract.LOBBY_CANCELLED,
			Contract.LOBBY_EXPIRED,
		]:
			http_status = int(bag.get("httpStatus", 0))
	error = str(bag.get("error", ""))
	var raw_code := str(bag.get("code", ""))
	if error != "":
		code_name = raw_code if raw_code != "" else error
	elif raw_code != "" and not Contract.is_lobby_code(raw_code) and raw_code.find("_") >= 0:
		code_name = raw_code
	else:
		code_name = error
	status = str(bag.get("status", ""))
	lobby_id = str(bag.get("lobbyId", bag.get("id", "")))
	var invite := str(bag.get("inviteCode", ""))
	if invite == "" and Contract.is_lobby_code(raw_code):
		invite = raw_code
	code = Contract.normalize_lobby_code(invite)
	match_id = str(bag.get("matchId", bag.get("newMatchId", "")))
	join_token = str(bag.get("joinToken", ""))
	seat = str(bag.get("seat", ""))
	player_id = str(bag.get("playerId", ""))
	var snap: Variant = bag.get("snapshot", {})
	if snap is Dictionary:
		snapshot = snap
		if status == "" and str(snap.get("status", "")) != "":
			status = str(snap.get("status"))
		if lobby_id == "":
			lobby_id = str(snap.get("lobbyId", ""))
		if code == "":
			code = Contract.normalize_lobby_code(str(snap.get("code", "")))
		if match_id == "":
			match_id = str(snap.get("matchId", ""))
		if join_token == "":
			join_token = str(snap.get("joinToken", ""))
		if seat == "":
			seat = str(snap.get("seat", ""))
		if player_id == "":
			player_id = str(snap.get("playerId", ""))
		var you_snap: Variant = snap.get("you", {})
		if you_snap is Dictionary:
			if seat == "":
				seat = str(you_snap.get("seat", ""))
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
	if status == "" and match_id != "" and join_token != "":
		status = Contract.LOBBY_READY
	if bag.has("ok"):
		ok = bool(bag.get("ok"))
	else:
		ok = error == "" and status != ""
	if is_unavailable():
		ok = false
	if is_reject() and status != Contract.LOBBY_CANCELLED:
		ok = false


func is_waiting() -> bool:
	return status == Contract.LOBBY_WAITING


func is_ready() -> bool:
	return status == Contract.LOBBY_READY and match_id != "" and join_token != ""


func is_cancelled() -> bool:
	return status == Contract.LOBBY_CANCELLED or code_name == Contract.LOBBY_ERR_CANCELLED


func is_expired() -> bool:
	return status == Contract.LOBBY_EXPIRED or code_name == Contract.LOBBY_ERR_EXPIRED


func is_unavailable() -> bool:
	## Route missing only. LIVE 404 lobby_not_found is a reject, not "invite not ready".
	return error == Contract.LOBBY_ERR_UNAVAILABLE or code_name == Contract.LOBBY_ERR_UNAVAILABLE


func is_reject() -> bool:
	if is_unavailable():
		return false
	if error == "" and code_name == "":
		return false
	return code_name in [
		Contract.LOBBY_ERR_BAD_CODE,
		Contract.LOBBY_ERR_NOT_FOUND,
		Contract.LOBBY_ERR_EXPIRED,
		Contract.LOBBY_ERR_CANCELLED,
		Contract.LOBBY_ERR_FULL,
		Contract.LOBBY_ERR_SELF,
		Contract.LOBBY_ERR_INVALID,
		Contract.LOBBY_ERR_INVALID_BODY,
		Contract.LOBBY_ERR_STARTED,
		Contract.LOBBY_ERR_FORBIDDEN,
		"unknown_lobby",
		"same_player",
		"bad_code",
		"lobby_already_ready",
	] or error != ""


func reject_copy() -> String:
	if is_unavailable():
		return Contract.LOBBY_UNAVAILABLE_COPY
	return Contract.LOBBY_REJECT_COPY
