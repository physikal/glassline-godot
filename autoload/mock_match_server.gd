extends Node
## Local implementation of the locked Glassline match lifecycle.
## Live client should keep these method names and payload shapes:
##   create_match() -> { matchId, joinTokens }
##   join(match_id, token) -> { playerId, seat, snapshot }
##   post_action(match_id, player_id, action) -> ActionResult
##   get_snapshot(match_id, player_id) -> Dictionary
##   match_event(player_id, event, snapshot)  == SSE { event, snapshot }

const Contract := preload("res://types/contract.gd")
const HexMath := preload("res://scripts/hex_math.gd")
const ActionResult := preload("res://types/action_result.gd")

signal match_event(player_id: String, event_name: String, snapshot: Dictionary)

## If >= 0, recon uses this roll instead of randf() (headless tests).
var test_recon_roll: float = -1.0

var _matches: Dictionary = {}
var _next_id: int = 1


func create_match() -> Dictionary:
	var match_id := "m_%d" % _next_id
	_next_id += 1
	var token_a := "tok_%s_a" % match_id
	var token_b := "tok_%s_b" % match_id
	_matches[match_id] = {
		"matchId": match_id,
		"status": Contract.STATUS_WAITING,
		"turnIndex": 0,
		"turnCap": Contract.TURN_CAP,
		"whoseTurn": null,
		"phase": null,
		"winner": null,
		"lastAction": null,
		"salt": "%s:%s" % [Contract.TERRAIN_SALT, match_id],
		"tokens": {Contract.SEAT_A: token_a, Contract.SEAT_B: token_b},
		"seats": {
			Contract.SEAT_A: _empty_seat(token_a),
			Contract.SEAT_B: _empty_seat(token_b),
		},
		"revealed": {Contract.SEAT_A: {}, Contract.SEAT_B: {}},
		"intel": {
			Contract.SEAT_A: {"hex": null, "softHotTurnsLeft": 0},
			Contract.SEAT_B: {"hex": null, "softHotTurnsLeft": 0},
		},
	}
	return {
		"matchId": match_id,
		"joinTokens": {Contract.SEAT_A: token_a, Contract.SEAT_B: token_b},
	}


func join(match_id: String, token: String) -> Dictionary:
	if not _matches.has(match_id):
		return {"error": "unknown_match"}
	var match_state: Dictionary = _matches[match_id]
	var seat := ""
	for key in [Contract.SEAT_A, Contract.SEAT_B]:
		if str(match_state["tokens"][key]) == token:
			seat = key
			break
	if seat == "":
		return {"error": "bad_token"}
	var seat_state: Dictionary = match_state["seats"][seat]
	if str(seat_state["playerId"]) == "":
		seat_state["playerId"] = "p_%s_%s" % [match_id, seat]
	if _both_joined(match_state) and match_state["status"] == Contract.STATUS_WAITING:
		match_state["status"] = Contract.STATUS_READY
	var snap := _snapshot_for_seat(match_state, seat)
	_emit_for_player(str(seat_state["playerId"]), _event_name(match_state, seat), snap)
	return {
		"playerId": seat_state["playerId"],
		"seat": seat,
		"snapshot": snap,
	}


func get_snapshot(match_id: String, player_id: String) -> Dictionary:
	var found := _find(match_id, player_id)
	if found.is_empty():
		return {}
	return _snapshot_for_seat(found["match"], found["seat"])


func post_action(match_id: String, player_id: String, action: Dictionary) -> Dictionary:
	var result: ActionResult = apply_action(match_id, player_id, action)
	return result.to_dict()


func apply_action(match_id: String, player_id: String, action: Dictionary) -> ActionResult:
	var found := _find(match_id, player_id)
	if found.is_empty():
		return ActionResult.fail("unknown_player")
	var match_state: Dictionary = found["match"]
	var seat: String = found["seat"]
	var snap := _snapshot_for_seat(match_state, seat)
	if match_state["status"] == Contract.STATUS_ENDED:
		return ActionResult.fail("match_ended", snap)
	var kind := str(action.get("type", ""))
	var applied: ActionResult
	match kind:
		Contract.ACT_SELECT_HEX:
			applied = _act_select_hex(match_state, seat, action)
		Contract.ACT_START:
			applied = _act_start(match_state, seat)
		Contract.ACT_ATTACK:
			applied = _act_attack(match_state, seat, action)
		Contract.ACT_RECON:
			applied = _act_recon(match_state, seat, action)
		Contract.ACT_UAV:
			applied = _act_uav(match_state, seat)
		Contract.ACT_END_TURN:
			applied = _act_end_turn(match_state, seat, action)
		_:
			applied = ActionResult.fail("unknown_action", snap)
	if applied.ok:
		_broadcast(match_state)
	return applied


func clear_all() -> void:
	_matches.clear()
	test_recon_roll = -1.0


func _empty_seat(token: String) -> Dictionary:
	return {
		"playerId": "",
		"token": token,
		"hex": null,
		"placed": false,
		"marks": 0,
		"exposurePct": Contract.DEFAULT_EXPOSURE,
		"movedLastTurn": false,
		"uavRemaining": 1,
	}


func _both_joined(match_state: Dictionary) -> bool:
	return (
		str(match_state["seats"][Contract.SEAT_A]["playerId"]) != ""
		and str(match_state["seats"][Contract.SEAT_B]["playerId"]) != ""
	)


func _both_placed(match_state: Dictionary) -> bool:
	return (
		bool(match_state["seats"][Contract.SEAT_A]["placed"])
		and bool(match_state["seats"][Contract.SEAT_B]["placed"])
	)


func _find(match_id: String, player_id: String) -> Dictionary:
	if not _matches.has(match_id):
		return {}
	var match_state: Dictionary = _matches[match_id]
	for seat in [Contract.SEAT_A, Contract.SEAT_B]:
		if str(match_state["seats"][seat]["playerId"]) == player_id:
			return {"match": match_state, "seat": seat}
	return {}


func _read_hex(action: Dictionary) -> Variant:
	var hex: Variant = action.get("hex", null)
	if hex == null or not (hex is Dictionary):
		return null
	var q := int(hex.get("q", -1))
	var r := int(hex.get("r", -1))
	if not Contract.on_board(q, r):
		return null
	return Contract.hex_dict(q, r)


func _terrain_type(match_state: Dictionary, q: int, r: int) -> String:
	var material := "%s:%d:%d:%s" % [match_state["matchId"], q, r, match_state["salt"]]
	var hashed := absi(int(hash(material))) % 3
	match hashed:
		0:
			return Contract.TYPE_OPEN
		1:
			return Contract.TYPE_BRUSH
		_:
			return Contract.TYPE_HARD


func _reveal(match_state: Dictionary, seat: String, q: int, r: int) -> void:
	if not Contract.on_board(q, r):
		return
	var key := "%d,%d" % [q, r]
	match_state["revealed"][seat][key] = _terrain_type(match_state, q, r)


func _set_last(match_state: Dictionary, action: Dictionary) -> void:
	match_state["lastAction"] = action.duplicate(true)


func _ok(match_state: Dictionary, seat: String) -> ActionResult:
	var snap := _snapshot_for_seat(match_state, seat)
	return ActionResult.ok_result(snap, _event_name(match_state, seat))


func _fail(match_state: Dictionary, seat: String, code: String) -> ActionResult:
	return ActionResult.fail(code, _snapshot_for_seat(match_state, seat))


func _need_own_action(match_state: Dictionary, seat: String) -> String:
	if match_state["status"] != Contract.STATUS_ACTIVE:
		return "not_active"
	if str(match_state["whoseTurn"]) != seat:
		return "not_your_turn"
	if str(match_state["phase"]) != Contract.PHASE_ACTION:
		return "wrong_phase"
	return ""


func _act_select_hex(match_state: Dictionary, seat: String, action: Dictionary) -> ActionResult:
	if match_state["status"] != Contract.STATUS_READY:
		return _fail(match_state, seat, "wrong_phase")
	var hex: Variant = _read_hex(action)
	if hex == null:
		return _fail(match_state, seat, "invalid_hex")
	var seat_state: Dictionary = match_state["seats"][seat]
	seat_state["hex"] = hex
	seat_state["placed"] = true
	_reveal(match_state, seat, int(hex["q"]), int(hex["r"]))
	_set_last(match_state, {"type": Contract.ACT_SELECT_HEX, "seat": seat, "hex": hex})
	return _ok(match_state, seat)


func _act_start(match_state: Dictionary, seat: String) -> ActionResult:
	if match_state["status"] != Contract.STATUS_READY:
		return _fail(match_state, seat, "wrong_phase")
	if not _both_placed(match_state):
		return _fail(match_state, seat, "not_placed")
	match_state["status"] = Contract.STATUS_ACTIVE
	match_state["turnIndex"] = 0
	match_state["whoseTurn"] = Contract.SEAT_A
	match_state["phase"] = Contract.PHASE_ACTION
	match_state["winner"] = null
	for key in [Contract.SEAT_A, Contract.SEAT_B]:
		match_state["seats"][key]["exposurePct"] = Contract.DEFAULT_EXPOSURE
		match_state["seats"][key]["movedLastTurn"] = false
	_set_last(match_state, {"type": Contract.ACT_START, "seat": seat})
	return _ok(match_state, seat)


func _act_attack(match_state: Dictionary, seat: String, action: Dictionary) -> ActionResult:
	var gate := _need_own_action(match_state, seat)
	if gate != "":
		return _fail(match_state, seat, gate)
	var hex: Variant = _read_hex(action)
	if hex == null:
		return _fail(match_state, seat, "invalid_hex")
	_reveal(match_state, seat, int(hex["q"]), int(hex["r"]))
	var enemy: Dictionary = match_state["seats"][Contract.other_seat(seat)]
	var hit := bool(enemy["placed"]) and Contract.same_hex(hex, enemy["hex"])
	# Miss must not invent Hot / visibleHex.
	if hit:
		match_state["status"] = Contract.STATUS_ENDED
		match_state["whoseTurn"] = null
		match_state["phase"] = null
		match_state["winner"] = seat
		match_state["seats"][seat]["marks"] = int(match_state["seats"][seat]["marks"]) + 1
		_set_last(match_state, {"type": Contract.ACT_ATTACK, "seat": seat, "hex": hex, "hit": true})
	else:
		match_state["phase"] = Contract.PHASE_END_TURN
		_set_last(match_state, {"type": Contract.ACT_ATTACK, "seat": seat, "hex": hex, "hit": false})
	return _ok(match_state, seat)


func _act_recon(match_state: Dictionary, seat: String, action: Dictionary) -> ActionResult:
	var gate := _need_own_action(match_state, seat)
	if gate != "":
		return _fail(match_state, seat, gate)
	var hex: Variant = _read_hex(action)
	if hex == null:
		return _fail(match_state, seat, "invalid_hex")
	var cells: Array[Vector2i] = HexMath.sector(int(hex["q"]), int(hex["r"]))
	for cell in cells:
		_reveal(match_state, seat, cell.x, cell.y)
	var enemy: Dictionary = match_state["seats"][Contract.other_seat(seat)]
	var in_sector := false
	if bool(enemy["placed"]) and enemy["hex"] != null:
		var eq := int(enemy["hex"]["q"])
		var er := int(enemy["hex"]["r"])
		for cell in cells:
			if cell.x == eq and cell.y == er:
				in_sector = true
				break
	var chance := Contract.RECON_BASE
	if bool(enemy["movedLastTurn"]):
		chance += Contract.RECON_MOVED_BONUS
	var roll := test_recon_roll if test_recon_roll >= 0.0 else randf()
	var found := in_sector and roll < chance
	if found:
		match_state["intel"][seat] = {
			"hex": enemy["hex"].duplicate(),
			"softHotTurnsLeft": 2,
		}
	match_state["phase"] = Contract.PHASE_END_TURN
	_set_last(match_state, {
		"type": Contract.ACT_RECON,
		"seat": seat,
		"hex": hex,
		"found": found,
	})
	return _ok(match_state, seat)


func _act_uav(match_state: Dictionary, seat: String) -> ActionResult:
	var gate := _need_own_action(match_state, seat)
	if gate != "":
		return _fail(match_state, seat, gate)
	var seat_state: Dictionary = match_state["seats"][seat]
	if int(seat_state["uavRemaining"]) <= 0:
		return _fail(match_state, seat, "uav_spent")
	seat_state["uavRemaining"] = 0
	var enemy: Dictionary = match_state["seats"][Contract.other_seat(seat)]
	var revealed := bool(enemy["placed"]) and enemy["hex"] != null
	if revealed:
		var eh: Dictionary = enemy["hex"]
		_reveal(match_state, seat, int(eh["q"]), int(eh["r"]))
		match_state["intel"][seat] = {
			"hex": eh.duplicate(),
			"softHotTurnsLeft": 2,
		}
	match_state["phase"] = Contract.PHASE_END_TURN
	_set_last(match_state, {"type": Contract.ACT_UAV, "seat": seat, "revealed": revealed})
	return _ok(match_state, seat)


func _act_end_turn(match_state: Dictionary, seat: String, action: Dictionary) -> ActionResult:
	if match_state["status"] != Contract.STATUS_ACTIVE:
		return _fail(match_state, seat, "not_active")
	if str(match_state["whoseTurn"]) != seat:
		return _fail(match_state, seat, "not_your_turn")
	if str(match_state["phase"]) != Contract.PHASE_END_TURN:
		return _fail(match_state, seat, "wrong_phase")
	if not action.has("exposurePct"):
		return _fail(match_state, seat, "missing_exposure")
	var exposure := clampf(float(action.get("exposurePct", Contract.DEFAULT_EXPOSURE)), 0.0, 100.0)
	var seat_state: Dictionary = match_state["seats"][seat]
	seat_state["exposurePct"] = exposure
	var moved := false
	if action.has("hex") and action.get("hex", null) != null:
		var dest: Variant = _read_hex(action)
		if dest == null:
			return _fail(match_state, seat, "invalid_hex")
		var here: Variant = seat_state["hex"]
		if here == null or not (here is Dictionary):
			return _fail(match_state, seat, "not_placed")
		var dist := HexMath.distance(int(here["q"]), int(here["r"]), int(dest["q"]), int(dest["r"]))
		if dist > 1:
			return _fail(match_state, seat, "not_adjacent")
		if dist == 1:
			seat_state["hex"] = dest
			moved = true
			_reveal(match_state, seat, int(dest["q"]), int(dest["r"]))
	seat_state["movedLastTurn"] = moved
	for viewer in [Contract.SEAT_A, Contract.SEAT_B]:
		var intel: Dictionary = match_state["intel"][viewer]
		var left := int(intel.get("softHotTurnsLeft", 0))
		if left > 0:
			left -= 1
			intel["softHotTurnsLeft"] = left
			if left <= 0:
				intel["hex"] = null
	match_state["turnIndex"] = int(match_state["turnIndex"]) + 1
	if int(match_state["turnIndex"]) >= int(match_state["turnCap"]):
		match_state["status"] = Contract.STATUS_ENDED
		match_state["whoseTurn"] = null
		match_state["phase"] = null
		match_state["winner"] = Contract.WIN_DRAW
	else:
		match_state["whoseTurn"] = Contract.other_seat(seat)
		match_state["phase"] = Contract.PHASE_ACTION
	_set_last(match_state, {
		"type": Contract.ACT_END_TURN,
		"seat": seat,
		"exposurePct": exposure,
		"moved": moved,
		"hex": seat_state["hex"],
	})
	return _ok(match_state, seat)


func _event_name(match_state: Dictionary, seat: String) -> String:
	if (
		match_state["status"] == Contract.STATUS_ACTIVE
		and str(match_state["phase"]) == Contract.PHASE_ACTION
		and str(match_state["whoseTurn"]) == seat
	):
		return Contract.EVENT_YOUR_TURN
	return Contract.EVENT_SNAPSHOT


func _snapshot_for_seat(match_state: Dictionary, seat: String) -> Dictionary:
	var you: Dictionary = match_state["seats"][seat]
	var other: String = Contract.other_seat(seat)
	var intel: Dictionary = match_state["intel"][seat]
	var visible: Variant = intel.get("hex", null)
	if visible != null and visible is Dictionary:
		visible = visible.duplicate()
	var terrain: Array = []
	var revealed: Dictionary = match_state["revealed"][seat]
	for key in revealed.keys():
		var parts := str(key).split(",")
		if parts.size() != 2:
			continue
		terrain.append({
			"q": int(parts[0]),
			"r": int(parts[1]),
			"type": str(revealed[key]),
		})
	var you_hex: Variant = you["hex"]
	if you_hex != null and you_hex is Dictionary:
		you_hex = you_hex.duplicate()
	var last: Variant = match_state["lastAction"]
	if last != null and last is Dictionary:
		last = last.duplicate(true)
	return {
		"matchId": match_state["matchId"],
		"status": match_state["status"],
		"turnIndex": match_state["turnIndex"],
		"turnCap": match_state["turnCap"],
		"whoseTurn": match_state["whoseTurn"],
		"phase": match_state["phase"],
		"uavRemaining": int(you["uavRemaining"]),
		"you": {
			"seat": seat,
			"hex": you_hex,
			"placed": bool(you["placed"]),
			"marks": int(you["marks"]),
			"exposurePct": you["exposurePct"],
			"movedLastTurn": bool(you["movedLastTurn"]),
		},
		"enemy": {
			"seat": other,
			"visibleHex": visible,
			"softHotTurnsLeft": int(intel.get("softHotTurnsLeft", 0)),
		},
		"terrain": terrain,
		"lastAction": last,
		"winner": match_state["winner"],
	}


func _emit_for_player(player_id: String, event_name: String, snapshot: Dictionary) -> void:
	if player_id == "":
		return
	match_event.emit(player_id, event_name, snapshot.duplicate(true))


func _broadcast(match_state: Dictionary) -> void:
	for seat in [Contract.SEAT_A, Contract.SEAT_B]:
		var pid := str(match_state["seats"][seat]["playerId"])
		if pid == "":
			continue
		var snap := _snapshot_for_seat(match_state, seat)
		_emit_for_player(pid, _event_name(match_state, seat), snap)
