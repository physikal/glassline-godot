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
## If >= 0, rematch timeout uses this clock instead of Time.get_ticks_msec().
var test_now_ms: int = -1
## Display stub for hideout. Persists across matches; tests call reset_wallet().
var account_marks: int = Contract.MOCK_WALLET_STUB
## Cosmetic ledger (visual only). Never touches combat / hit / exposure.
var owned_cosmetics: Array = []
var equipped_cosmetic: String = ""
var equipped_decor: String = ""
var _shop_receipts: Dictionary = {}
## POST /jobs complete receipts keyed by clientJobId — replay does not grant again.
var _job_receipts: Dictionary = {}
## Private lobby invite. Cancel / expire never touches Marks.
var _lobbies: Dictionary = {}
var _lobby_by_code: Dictionary = {}
var _next_lobby: int = 1
## Quick Match queue. Pair two waiting players after a short delay. No bot fill.
var _queue: Dictionary = {}
var _queue_pairs: Array = []
var _queue_timed_out: Dictionary = {}
var queue_pair_delay_ms: int = 80

var _matches: Dictionary = {}
var _next_id: int = 1


func create_match(opts: Dictionary = {}) -> Dictionary:
	var match_id := "m_%d" % _next_id
	_next_id += 1
	var token_a := "tok_%s_a" % match_id
	var token_b := "tok_%s_b" % match_id
	var mode := _read_mode(opts)
	_matches[match_id] = {
		"matchId": match_id,
		"status": Contract.STATUS_WAITING,
		"turnIndex": 0,
		"turnCap": Contract.TURN_CAP,
		"whoseTurn": null,
		"phase": null,
		"winner": null,
		"lastAction": null,
		"mode": mode,
		"jobId": str(opts.get("jobId", match_id if mode == Contract.MODE_SP_JOB else "")),
		"jobTier": int(opts.get("jobTier", opts.get("tier", 1))),
		"endReason": null,
		"payoutSettled": false,
		"payouts": {Contract.SEAT_A: {}, Contract.SEAT_B: {}},
		"rematch": {},
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
		"mode": mode,
		"wallet": {"marks": account_marks},
	}


func wallet() -> Dictionary:
	return _shop_snapshot()


func reset_wallet(value: int = Contract.MOCK_WALLET_STUB) -> void:
	account_marks = value
	owned_cosmetics.clear()
	equipped_cosmetic = ""
	equipped_decor = ""
	_shop_receipts.clear()
	_job_receipts.clear()


func get_shop() -> Dictionary:
	return _shop_snapshot()


func buy_shop(item_id: String, client_buy_id: String = "") -> Dictionary:
	## Mock ledger. Client still binds you.marks from this payload — never marks -=.
	if client_buy_id != "" and _shop_receipts.has(client_buy_id):
		return (_shop_receipts[client_buy_id] as Dictionary).duplicate(true)
	item_id = Contract._canonical_shop_id(item_id)
	var listed: Dictionary = Contract.shop_item_by_id(item_id)
	if listed.is_empty():
		return _shop_reject(Contract.SHOP_ERR_UNKNOWN_ITEM)
	if owned_cosmetics.has(item_id):
		return _shop_reject(Contract.SHOP_ERR_ALREADY_OWNED)
	var price := int(listed.get("price", Contract.shop_item_price(item_id)))
	if account_marks < price:
		return _shop_reject(Contract.SHOP_ERR_INSUFFICIENT)
	account_marks -= price
	if not owned_cosmetics.has(item_id):
		owned_cosmetics.append(item_id)
	## Last buy auto-equips the matching slot only. Skin and decor coexist.
	if Contract.is_decor_chrome(item_id):
		equipped_decor = item_id
	else:
		equipped_cosmetic = item_id
	var bought := _shop_ok({"type": "buy", "itemId": item_id, "clientBuyId": client_buy_id})
	if client_buy_id != "":
		_shop_receipts[client_buy_id] = bought.duplicate(true)
	return bought


func equip_cosmetic(item_id: String, slot: String = "") -> Dictionary:
	## Visual only. Empty / null item_id unequips that slot. Unknown / unowned → reject.
	## Same id is a no-op (idempotent). Marks untouched. Decor never overwrites skin.
	var use_decor := slot == "decor" or Contract.is_decor_chrome(item_id)
	if item_id == "" and use_decor:
		equipped_decor = ""
		return _shop_ok({
			"type": "equip",
			"itemId": null,
			"slot": "decor",
			"equippedDecorId": null,
		})
	if item_id == "":
		equipped_cosmetic = ""
		return _shop_ok({
			"type": "equip",
			"itemId": null,
			"slot": "skin",
			"equipped": null,
			"equippedSkinId": null,
		})
	item_id = Contract._canonical_shop_id(item_id)
	var listed: Dictionary = Contract.shop_item_by_id(item_id)
	if listed.is_empty():
		return _shop_reject(Contract.SHOP_ERR_UNKNOWN_ITEM)
	if not owned_cosmetics.has(item_id):
		return _shop_reject(Contract.SHOP_ERR_NOT_OWNED)
	if use_decor:
		equipped_decor = item_id
		return _shop_ok({
			"type": "equip",
			"itemId": item_id,
			"slot": "decor",
			"equippedDecorId": item_id,
		})
	equipped_cosmetic = item_id
	return _shop_ok({
		"type": "equip",
		"itemId": item_id,
		"slot": "skin",
		"equipped": item_id,
		"equippedSkinId": item_id,
	})


func _shop_snapshot() -> Dictionary:
	var bag: Dictionary = Contract.shop_catalog_stub(
		account_marks, owned_cosmetics, equipped_cosmetic, equipped_decor
	)
	bag["source"] = "mock"
	bag["wallet"] = {"marks": account_marks}
	return bag


func _shop_ok(result: Dictionary = {}) -> Dictionary:
	var snap := _shop_snapshot()
	var skin: Variant = equipped_cosmetic if equipped_cosmetic != "" else null
	var decor: Variant = equipped_decor if equipped_decor != "" else null
	return {
		"ok": true,
		"error": "",
		"snapshot": snap,
		"you": snap.get("you", {}),
		"owned": owned_cosmetics.duplicate(),
		"equipped": skin,
		"equippedSkinId": skin,
		"equippedDecorId": decor,
		"marks": account_marks,
		"result": result,
	}


func _shop_reject(reason: String) -> Dictionary:
	var snap := _shop_snapshot()
	return {
		"ok": false,
		"error": reason,
		"reason": reason,
		"snapshot": snap,
		"you": snap.get("you", {}),
		"owned": owned_cosmetics.duplicate(),
		"equipped": equipped_cosmetic if equipped_cosmetic != "" else null,
		"equippedSkinId": equipped_cosmetic if equipped_cosmetic != "" else null,
		"equippedDecorId": equipped_decor if equipped_decor != "" else null,
		"marks": account_marks,
		"result": {"type": Contract.ACT_REJECT, "reason": reason},
	}


func create_job(tier: int = 1, client_job_id: String = "") -> Dictionary:
	var job_tier := clampi(tier, 1, 3)
	var created: Dictionary = create_match({
		"mode": Contract.MODE_SP_JOB,
		"job": true,
		"jobTier": job_tier,
		"clientJobId": client_job_id,
	})
	var match_id := str(created.get("matchId", ""))
	var tokens: Dictionary = created.get("joinTokens", {})
	var human: Dictionary = join(match_id, str(tokens.get("a", "")))
	var bot: Dictionary = join(match_id, str(tokens.get("b", "")))
	apply_action(match_id, str(bot.get("playerId", "")), {
		"type": Contract.ACT_SELECT_HEX,
		"hex": Contract.job_bot_hex(job_tier),
	})
	var snap: Dictionary = get_snapshot(match_id, str(human.get("playerId", "")))
	var bag := {
		"jobId": str(created.get("jobId", match_id)),
		"matchId": match_id,
		"playerId": str(human.get("playerId", "")),
		"seat": str(human.get("seat", Contract.SEAT_A)),
		"joinToken": str(tokens.get("a", "")),
		"dummyToken": str(tokens.get("b", "")),
		"dummyPlayerId": str(bot.get("playerId", "")),
		"tier": job_tier,
		"name": Contract.job_name(job_tier),
		"clientJobId": client_job_id,
		"snapshot": snap,
	}
	return bag


func complete_job(tier: int = 1, client_job_id: String = "") -> Dictionary:
	## Editor / J4 helper: play the stub kill, bind snapshot you.marks. Never marks +=.
	if client_job_id != "" and _job_receipts.has(client_job_id):
		return (_job_receipts[client_job_id] as Dictionary).duplicate(true)
	var created: Dictionary = create_job(tier, client_job_id)
	var match_id := str(created.get("matchId", ""))
	var pid := str(created.get("playerId", ""))
	if match_id == "" or pid == "":
		return {"ok": false, "error": str(created.get("error", "job_create_failed")), "snapshot": {}}
	apply_action(match_id, pid, {"type": Contract.ACT_SELECT_HEX, "hex": Contract.hex_dict(2, 2)})
	apply_action(match_id, pid, {"type": Contract.ACT_START})
	var bot: Dictionary = Contract.job_bot_hex(int(created.get("tier", tier)))
	var killed: ActionResult = apply_action(match_id, pid, {
		"type": Contract.ACT_ATTACK,
		"hex": bot,
	})
	var snap: Dictionary = killed.snapshot if not killed.snapshot.is_empty() else get_snapshot(match_id, pid)
	var you: Variant = snap.get("you", {})
	var bag := {
		"ok": bool(killed.ok),
		"error": str(killed.error),
		"jobId": str(created.get("jobId", "")),
		"matchId": match_id,
		"playerId": pid,
		"tier": int(created.get("tier", tier)),
		"name": str(created.get("name", Contract.job_name(tier))),
		"clientJobId": client_job_id,
		"snapshot": snap,
		"you": you if you is Dictionary else {},
		"marks": account_marks,
	}
	if client_job_id != "" and bool(killed.ok):
		_job_receipts[client_job_id] = bag.duplicate(true)
	return bag


func get_job(job_id: String) -> Dictionary:
	for match_id in _matches.keys():
		var match_state: Dictionary = _matches[match_id]
		if str(match_state.get("jobId", "")) == job_id or str(match_id) == job_id:
			var seat_a: Dictionary = match_state["seats"][Contract.SEAT_A]
			return {
				"jobId": str(match_state.get("jobId", match_id)),
				"matchId": str(match_id),
				"tier": int(match_state.get("jobTier", 1)),
				"name": Contract.job_name(int(match_state.get("jobTier", 1))),
				"playerId": str(seat_a.get("playerId", "")),
				"status": "won" if match_state.get("winner") == Contract.SEAT_A else ("failed" if match_state["status"] == Contract.STATUS_ENDED else "active"),
				"snapshot": _snapshot_for_seat(match_state, Contract.SEAT_A),
			}
	return {"error": "unknown_job"}


func create_lobby(player_id: String = "") -> Dictionary:
	## POST /lobbies → { lobbyId, code, snapshot } status waiting.
	if player_id == "":
		player_id = "p_mock"
	var code := _mint_lobby_code()
	var lobby_id := "lob_%d" % _next_lobby
	_next_lobby += 1
	var row := {
		"lobbyId": lobby_id,
		"code": code,
		"status": Contract.LOBBY_WAITING,
		"createdAtMs": _now_ms(),
		"hostPlayerId": player_id,
		"guestPlayerId": "",
		"matchId": "",
		"joinTokens": {},
	}
	_lobbies[lobby_id] = row
	_lobby_by_code[code] = lobby_id
	return _lobby_payload(row, player_id)


func join_lobby(code: String, player_id: String = "") -> Dictionary:
	## POST /lobbies/join { code } → seat B. Both seated → ready + matchId + joinToken.
	if player_id == "":
		player_id = "p_guest"
	var norm := Contract.normalize_lobby_code(code)
	if not Contract.is_lobby_code(norm):
		return _lobby_reject(Contract.LOBBY_ERR_INVALID)
	var lobby_id := str(_lobby_by_code.get(norm, ""))
	if lobby_id == "" or not _lobbies.has(lobby_id):
		return _lobby_reject(Contract.LOBBY_ERR_NOT_FOUND)
	var row: Dictionary = _lobbies[lobby_id]
	_touch_lobby(row)
	var st := str(row.get("status", ""))
	if st == Contract.LOBBY_EXPIRED:
		return _lobby_reject(Contract.LOBBY_ERR_EXPIRED)
	if st == Contract.LOBBY_CANCELLED:
		return _lobby_reject(Contract.LOBBY_ERR_CANCELLED)
	if player_id == str(row.get("hostPlayerId", "")):
		if st == Contract.LOBBY_READY:
			return _lobby_payload(row, player_id, true)
		return _lobby_reject(Contract.LOBBY_ERR_SELF)
	if st == Contract.LOBBY_READY:
		if player_id == str(row.get("guestPlayerId", "")):
			return _lobby_payload(row, player_id, true)
		return _lobby_reject(Contract.LOBBY_ERR_FULL)
	row["guestPlayerId"] = player_id
	_promote_lobby(row)
	return _lobby_payload(row, player_id, true)


func get_lobby(lobby_id: String, player_id: String = "") -> Dictionary:
	## GET /lobbies/:id — host poll. Ready returns this seat's joinToken.
	if not _lobbies.has(lobby_id):
		return _lobby_reject(Contract.LOBBY_ERR_NOT_FOUND)
	var row: Dictionary = _lobbies[lobby_id]
	_touch_lobby(row)
	if player_id == "":
		player_id = str(row.get("hostPlayerId", "p_mock"))
	var st := str(row.get("status", ""))
	if st == Contract.LOBBY_EXPIRED:
		return _lobby_reject(Contract.LOBBY_ERR_EXPIRED, row)
	if st == Contract.LOBBY_CANCELLED:
		return _lobby_payload(row, player_id)
	return _lobby_payload(row, player_id)


func enqueue(player_id: String = "") -> Dictionary:
	## POST /queue — idempotent re-queue refreshes TTL. No bot fill.
	if player_id == "":
		player_id = "p_mock"
	_expire_queue()
	_complete_queue_pairs()
	if _queue.has(player_id):
		var existing: Dictionary = _queue[player_id]
		if str(existing.get("status", "")) == Contract.QUEUE_MATCHED:
			return _queue_payload(player_id)
		existing["queuedAtMs"] = _now_ms()
		_try_schedule_queue_pair()
		_complete_queue_pairs()
		return _queue_payload(player_id)
	_queue[player_id] = {
		"playerId": player_id,
		"status": Contract.QUEUE_QUEUED,
		"queuedAtMs": _now_ms(),
		"matchId": "",
		"seat": "",
	}
	_try_schedule_queue_pair()
	_complete_queue_pairs()
	return _queue_payload(player_id)


func get_queue(player_id: String = "") -> Dictionary:
	## GET /queue — poll until matched { matchId, joinToken } or idle/timeout.
	if player_id == "":
		player_id = "p_mock"
	_expire_queue()
	_complete_queue_pairs()
	if _queue_timed_out.has(player_id):
		_queue_timed_out.erase(player_id)
		return _queue_idle(player_id, true)
	if not _queue.has(player_id):
		return _queue_idle(player_id, false)
	return _queue_payload(player_id)


func dequeue(player_id: String = "") -> Dictionary:
	## DELETE /queue — hideout. Marks Δ0. Already paired → 409.
	if player_id == "":
		player_id = "p_mock"
	_expire_queue()
	_complete_queue_pairs()
	if _queue.has(player_id) and str(_queue[player_id].get("status", "")) == Contract.QUEUE_MATCHED:
		return _queue_reject(Contract.QUEUE_ERR_MATCHED, player_id)
	_drop_queue_player(player_id)
	_queue_timed_out.erase(player_id)
	return _queue_idle(player_id, false)


func _try_schedule_queue_pair() -> void:
	var waiting: Array = []
	for pid in _queue.keys():
		var row: Dictionary = _queue[pid]
		if str(row.get("status", "")) != Contract.QUEUE_QUEUED:
			continue
		if _queue_player_pending(str(pid)):
			continue
		waiting.append(str(pid))
	while waiting.size() >= 2:
		var pid_a := str(waiting.pop_front())
		var pid_b := str(waiting.pop_front())
		_queue_pairs.append({
			"a": pid_a,
			"b": pid_b,
			"readyAtMs": _now_ms() + queue_pair_delay_ms,
			"matchId": "",
		})


func _queue_player_pending(player_id: String) -> bool:
	for pair in _queue_pairs:
		if not (pair is Dictionary):
			continue
		if str(pair.get("matchId", "")) != "":
			continue
		if str(pair.get("a", "")) == player_id or str(pair.get("b", "")) == player_id:
			return true
	return false


func _complete_queue_pairs() -> void:
	var now := _now_ms()
	for pair in _queue_pairs:
		if not (pair is Dictionary):
			continue
		if str(pair.get("matchId", "")) != "":
			continue
		if now < int(pair.get("readyAtMs", 0)):
			continue
		var pid_a := str(pair.get("a", ""))
		var pid_b := str(pair.get("b", ""))
		if not _queue.has(pid_a) or not _queue.has(pid_b):
			continue
		if str(_queue[pid_a].get("status", "")) != Contract.QUEUE_QUEUED:
			continue
		if str(_queue[pid_b].get("status", "")) != Contract.QUEUE_QUEUED:
			continue
		_promote_queue_pair(pid_a, pid_b, pair)


func _promote_queue_pair(pid_a: String, pid_b: String, pair: Dictionary) -> void:
	## Two waiting humans → existing PvP match. Never mint a bot seat (Q5).
	var created: Dictionary = create_match({"mode": Contract.MODE_PVP, "queue": true})
	var match_id := str(created.get("matchId", ""))
	if match_id == "" or not _matches.has(match_id):
		return
	var match_state: Dictionary = _matches[match_id]
	match_state["seats"][Contract.SEAT_A]["playerId"] = pid_a
	match_state["seats"][Contract.SEAT_B]["playerId"] = pid_b
	if _both_joined(match_state):
		match_state["status"] = Contract.STATUS_READY
	var tokens: Dictionary = match_state.get("tokens", {})
	_queue[pid_a]["status"] = Contract.QUEUE_MATCHED
	_queue[pid_a]["matchId"] = match_id
	_queue[pid_a]["seat"] = Contract.SEAT_A
	_queue[pid_a]["joinToken"] = str(tokens.get(Contract.SEAT_A, ""))
	_queue[pid_b]["status"] = Contract.QUEUE_MATCHED
	_queue[pid_b]["matchId"] = match_id
	_queue[pid_b]["seat"] = Contract.SEAT_B
	_queue[pid_b]["joinToken"] = str(tokens.get(Contract.SEAT_B, ""))
	pair["matchId"] = match_id


func _expire_queue() -> void:
	var now := _now_ms()
	var gone: Array = []
	for pid in _queue.keys():
		var row: Dictionary = _queue[pid]
		if str(row.get("status", "")) != Contract.QUEUE_QUEUED:
			continue
		if now - int(row.get("queuedAtMs", 0)) >= Contract.QUEUE_TTL_MS:
			gone.append(str(pid))
	for pid in gone:
		_drop_queue_player(str(pid))
		_queue_timed_out[str(pid)] = true


func _drop_queue_player(player_id: String) -> void:
	_queue.erase(player_id)
	var keep: Array = []
	for pair in _queue_pairs:
		if not (pair is Dictionary):
			continue
		if str(pair.get("matchId", "")) != "":
			keep.append(pair)
			continue
		if str(pair.get("a", "")) == player_id or str(pair.get("b", "")) == player_id:
			continue
		keep.append(pair)
	_queue_pairs = keep


func _queue_seconds_left(row: Dictionary) -> int:
	if str(row.get("status", "")) != Contract.QUEUE_QUEUED:
		return 0
	var age := _now_ms() - int(row.get("queuedAtMs", 0))
	return maxi(0, int(ceili(float(Contract.QUEUE_TTL_MS - age) / 1000.0)))


func _queue_queued_iso(row: Dictionary) -> String:
	var queued := int(row.get("queuedAtMs", _now_ms()))
	var ago_ms := maxi(0, _now_ms() - queued)
	var unix := int(Time.get_unix_time_from_system()) - int(ago_ms / 1000)
	return Time.get_datetime_string_from_unix_time(unix, true) + "Z"


func _queue_payload(player_id: String) -> Dictionary:
	if not _queue.has(player_id):
		return _queue_idle(player_id, false)
	var row: Dictionary = _queue[player_id]
	var st := str(row.get("status", Contract.QUEUE_QUEUED))
	var left := _queue_seconds_left(row)
	var q := {"status": st, "secondsLeft": left}
	var you := {
		"playerId": player_id,
		"seat": str(row.get("seat", "")),
		"marks": account_marks,
	}
	var bag := {
		"ok": true,
		"error": "",
		"status": st,
		"queuedAt": _queue_queued_iso(row),
		"timeoutSec": Contract.QUEUE_TTL_SEC,
		"secondsLeft": left,
		"queue": q,
		"playerId": player_id,
		"seat": str(row.get("seat", "")),
		"you": you,
		"marks": account_marks,
		"snapshot": {
			"kind": "queue",
			"status": st,
			"queue": q,
			"you": you,
		},
	}
	if st == Contract.QUEUE_MATCHED:
		var match_id := str(row.get("matchId", ""))
		var seat := str(row.get("seat", Contract.SEAT_A))
		var join := str(row.get("joinToken", ""))
		bag["matchId"] = match_id
		bag["joinToken"] = join
		bag["joinTokens"] = {}
		if match_id != "" and _matches.has(match_id):
			var tokens: Dictionary = _matches[match_id].get("tokens", {})
			bag["joinTokens"] = tokens.duplicate(true)
			if join == "":
				join = str(tokens.get(seat, ""))
				bag["joinToken"] = join
			bag["snapshot"] = _snapshot_for_seat(_matches[match_id], seat)
	return bag


func _queue_idle(player_id: String, timed_out: bool) -> Dictionary:
	var st := Contract.QUEUE_TIMEOUT if timed_out else Contract.QUEUE_IDLE
	var q := {"status": st, "secondsLeft": 0, "timedOut": timed_out}
	return {
		"ok": true,
		"error": "",
		"status": st,
		"timedOut": timed_out,
		"timeoutSec": Contract.QUEUE_TTL_SEC,
		"secondsLeft": 0,
		"queue": q,
		"playerId": player_id,
		"you": {"playerId": player_id, "marks": account_marks},
		"marks": account_marks,
		"snapshot": {
			"kind": "queue",
			"status": st,
			"queue": q,
			"you": {"playerId": player_id, "marks": account_marks},
		},
	}


func _queue_reject(reason: String, player_id: String = "") -> Dictionary:
	return {
		"ok": false,
		"error": reason,
		"code": reason,
		"status": Contract.QUEUE_MATCHED if reason == Contract.QUEUE_ERR_MATCHED else "",
		"httpStatus": 409 if reason == Contract.QUEUE_ERR_MATCHED else 400,
		"playerId": player_id,
		"you": {"marks": account_marks},
		"marks": account_marks,
		"snapshot": {"you": {"marks": account_marks}},
	}


func cancel_lobby(lobby_id: String, player_id: String = "") -> Dictionary:
	## POST /lobbies/:id/cancel — hideout. No forfeit Marks.
	if not _lobbies.has(lobby_id):
		return _lobby_reject(Contract.LOBBY_ERR_NOT_FOUND)
	var row: Dictionary = _lobbies[lobby_id]
	_touch_lobby(row)
	if player_id == "":
		player_id = str(row.get("hostPlayerId", "p_mock"))
	var st := str(row.get("status", ""))
	if st == Contract.LOBBY_READY:
		return _lobby_reject(Contract.LOBBY_ERR_STARTED, row)
	if st == Contract.LOBBY_EXPIRED:
		return _lobby_reject(Contract.LOBBY_ERR_EXPIRED, row)
	row["status"] = Contract.LOBBY_CANCELLED
	return _lobby_payload(row, player_id)


func _mint_lobby_code() -> String:
	for _try in 16:
		var code := Contract.new_lobby_code()
		if not _lobby_by_code.has(code):
			return code
	return "H7K3P2"


func _touch_lobby(row: Dictionary) -> void:
	if str(row.get("status", "")) != Contract.LOBBY_WAITING:
		return
	var age := _now_ms() - int(row.get("createdAtMs", 0))
	if age >= Contract.LOBBY_TTL_MS:
		row["status"] = Contract.LOBBY_EXPIRED


func _promote_lobby(row: Dictionary) -> void:
	## Reuse create+bind. Same PvP rules. No Marks grant.
	var created: Dictionary = create_match({"mode": Contract.MODE_PVP, "lobbyId": str(row.get("lobbyId", ""))})
	var match_id := str(created.get("matchId", ""))
	if match_id == "" or not _matches.has(match_id):
		return
	var match_state: Dictionary = _matches[match_id]
	match_state["seats"][Contract.SEAT_A]["playerId"] = str(row.get("hostPlayerId", ""))
	match_state["seats"][Contract.SEAT_B]["playerId"] = str(row.get("guestPlayerId", ""))
	if _both_joined(match_state):
		match_state["status"] = Contract.STATUS_READY
	row["matchId"] = match_id
	row["joinTokens"] = match_state.get("tokens", {})
	row["status"] = Contract.LOBBY_READY


func _lobby_seat_for(row: Dictionary, player_id: String) -> String:
	if player_id != "" and player_id == str(row.get("guestPlayerId", "")):
		return Contract.SEAT_B
	return Contract.SEAT_A


func _lobby_payload(row: Dictionary, player_id: String, include_match_snap: bool = false) -> Dictionary:
	## Join handoff may attach the match snap. GET / cancel keep a lobby snap (LIVE).
	var seat := _lobby_seat_for(row, player_id)
	var st := str(row.get("status", Contract.LOBBY_WAITING))
	var lobby_snap := {
		"kind": "lobby",
		"status": st,
		"lobbyId": str(row.get("lobbyId", "")),
		"code": str(row.get("code", "")),
		"seat": seat,
		"you": {"seat": seat, "playerId": player_id, "marks": account_marks},
		"opponent": null,
		"expiresAt": _lobby_expires_iso(row),
	}
	if st == Contract.LOBBY_READY and str(row.get("matchId", "")) != "":
		lobby_snap["matchId"] = str(row.get("matchId", ""))
	var bag := {
		"ok": true,
		"error": "",
		"status": st,
		"lobbyId": str(row.get("lobbyId", "")),
		"code": str(row.get("code", "")),
		"seat": seat,
		"playerId": player_id,
		"you": {"seat": seat, "playerId": player_id, "marks": account_marks},
		"marks": account_marks,
		"snapshot": lobby_snap,
		"expiresAt": _lobby_expires_iso(row),
	}
	if st == Contract.LOBBY_READY:
		var match_id := str(row.get("matchId", ""))
		var tokens: Dictionary = row.get("joinTokens", {})
		var join := str(tokens.get(seat, ""))
		bag["matchId"] = match_id
		bag["joinToken"] = join
		bag["joinTokens"] = tokens.duplicate(true)
		if include_match_snap and match_id != "" and _matches.has(match_id):
			bag["snapshot"] = _snapshot_for_seat(_matches[match_id], seat)
	return bag


func _lobby_http(reason: String) -> int:
	if reason in [Contract.LOBBY_ERR_BAD_CODE, Contract.LOBBY_ERR_INVALID, Contract.LOBBY_ERR_INVALID_BODY]:
		return 400
	if reason == Contract.LOBBY_ERR_NOT_FOUND:
		return 404
	if reason == Contract.LOBBY_ERR_FORBIDDEN:
		return 403
	return 409


func _lobby_reject(reason: String, row: Dictionary = {}) -> Dictionary:
	var st := ""
	if reason == Contract.LOBBY_ERR_EXPIRED:
		st = Contract.LOBBY_EXPIRED
	elif reason == Contract.LOBBY_ERR_CANCELLED:
		st = Contract.LOBBY_CANCELLED
	var snap := {
		"you": {"marks": account_marks},
	}
	if not row.is_empty():
		snap["lobbyId"] = str(row.get("lobbyId", ""))
		snap["code"] = str(row.get("code", ""))
		snap["status"] = st if st != "" else str(row.get("status", ""))
	return {
		"ok": false,
		"error": reason,
		"code": reason,
		"status": st,
		"httpStatus": _lobby_http(reason),
		"you": {"marks": account_marks},
		"marks": account_marks,
		"snapshot": snap,
	}


func _lobby_expires_iso(row: Dictionary) -> String:
	var created := int(row.get("createdAtMs", _now_ms()))
	var left_ms := maxi(0, created + Contract.LOBBY_TTL_MS - _now_ms())
	var exp_unix := int(Time.get_unix_time_from_system()) + int(left_ms / 1000)
	return Time.get_datetime_string_from_unix_time(exp_unix, true) + "Z"


func _read_mode(opts: Dictionary) -> String:
	var mode := str(opts.get("mode", opts.get("matchMode", "")))
	if mode in ["job", "sp", "spJob", "sp_job"]:
		return Contract.MODE_SP_JOB
	if bool(opts.get("job", false)) or bool(opts.get("sp", false)) or bool(opts.get("spJob", false)):
		return Contract.MODE_SP_JOB
	if str(opts.get("jobId", "")) != "":
		return Contract.MODE_SP_JOB
	if mode != "":
		return mode
	return Contract.MODE_PVP


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


func abandon(match_id: String, player_id: String) -> Dictionary:
	## POST /matches/:id/abandon + join Bearer. Same forfeit path as A4 timeout.
	var found := _find(match_id, player_id)
	if found.is_empty():
		return {"ok": false, "error": "unknown_player", "code": "unknown_player", "snapshot": {}}
	var match_state: Dictionary = found["match"]
	var seat: String = found["seat"]
	if match_state["status"] == Contract.STATUS_ENDED:
		var ended := _snapshot_for_seat(match_state, seat)
		return {
			"ok": true,
			"alreadyEnded": true,
			"snapshot": ended,
			"result": ended.get("lastAction", {"type": Contract.ACT_FORFEIT}),
		}
	if match_state["status"] != Contract.STATUS_ACTIVE:
		return {
			"ok": false,
			"error": "match is not active",
			"code": "match_not_active",
			"status": 409,
			"snapshot": _snapshot_for_seat(match_state, seat),
		}
	_end_forfeit(match_state, seat)
	_broadcast(match_state)
	var snap := _snapshot_for_seat(match_state, seat)
	return {
		"ok": true,
		"alreadyEnded": false,
		"snapshot": snap,
		"result": snap.get("lastAction", {"type": Contract.ACT_FORFEIT, "winner": match_state.get("winner")}),
	}


func mark_disconnected(match_id: String, player_id: String) -> Dictionary:
	## Soft A4: stamp disconnected_at. Snapshot exposes grace for the remaining seat.
	var found := _find(match_id, player_id)
	if found.is_empty():
		return {"ok": false, "error": "unknown_player"}
	var match_state: Dictionary = found["match"]
	var seat_state: Dictionary = match_state["seats"][found["seat"]]
	if int(seat_state.get("disconnectedAtMs", 0)) <= 0:
		seat_state["disconnectedAtMs"] = _now_ms()
	_reconcile_grace(match_state)
	_broadcast(match_state)
	return {"ok": true, "snapshot": _snapshot_for_seat(match_state, found["seat"])}


func force_standoff(match_id: String, player_id: String = "") -> Dictionary:
	## Capture / tests: settle turn-cap standoff without playing 16 turns.
	if not _matches.has(match_id):
		return {"ok": false, "error": "unknown_match"}
	var match_state: Dictionary = _matches[match_id]
	if match_state["status"] != Contract.STATUS_ENDED:
		match_state["status"] = Contract.STATUS_ENDED
		match_state["whoseTurn"] = null
		match_state["phase"] = null
		match_state["winner"] = Contract.WIN_DRAW
		_clear_all_decoys(match_state)
		_settle_payout(match_state, Contract.END_STANDOFF)
	var seat := Contract.SEAT_A
	if player_id != "":
		var found := _find(match_id, player_id)
		if not found.is_empty():
			seat = str(found.get("seat", Contract.SEAT_A))
	return {"ok": true, "snapshot": _snapshot_for_seat(match_state, seat)}


func start_grace(match_id: String, player_id: String, remaining_sec: float = 23.0) -> Dictionary:
	## Capture / tests: rival already in grace with a readable leftover clock.
	var found := _find(match_id, player_id)
	if found.is_empty():
		return {"ok": false, "error": "unknown_player"}
	var match_state: Dictionary = found["match"]
	var seat_state: Dictionary = match_state["seats"][found["seat"]]
	var left_ms := maxi(0, int(remaining_sec * 1000.0))
	seat_state["disconnectedAtMs"] = _now_ms() - (Contract.FORFEIT_GRACE_SEC * 1000 - left_ms)
	return {"ok": true, "snapshot": _snapshot_for_seat(match_state, Contract.other_seat(found["seat"]))}


func rematch(match_id: String, player_id: String, accept: bool) -> Dictionary:
	## POST /matches/:id/rematch { accept }. LIVE shape: waiting | ready | declined | expired.
	var found := _find(match_id, player_id)
	if found.is_empty():
		return {"ok": false, "error": "unknown_player", "code": "unknown_player", "rematch": {}, "snapshot": {}}
	var match_state: Dictionary = found["match"]
	var seat: String = found["seat"]
	var snap := _snapshot_for_seat(match_state, seat)
	if match_state["status"] != Contract.STATUS_ENDED:
		return {
			"ok": false,
			"error": "match is not ended",
			"code": Contract.REMATCH_ERR_NOT_ENDED,
			"status": 409,
			"rematch": {},
			"snapshot": snap,
		}
	if str(match_state.get("mode", Contract.MODE_PVP)) == Contract.MODE_SP_JOB:
		return {
			"ok": false,
			"error": "rematch is PvP only",
			"code": "rematch_not_available",
			"status": 409,
			"rematch": snap.get("rematch", {}),
			"snapshot": snap,
		}
	_touch_rematch(match_state)
	var rem: Dictionary = _rematch_state(match_state)
	var st := str(rem.get("status", Contract.REMATCH_NONE))
	if st in [Contract.REMATCH_READY, Contract.REMATCH_DECLINED, Contract.REMATCH_EXPIRED]:
		return _rematch_payload(match_state, seat)
	if not accept:
		rem["status"] = Contract.REMATCH_DECLINED
		rem["accepted"][seat] = false
		_broadcast(match_state)
		return _rematch_payload(match_state, seat)
	var accepted: Dictionary = rem.get("accepted", {})
	accepted[seat] = true
	rem["accepted"] = accepted
	var other := Contract.other_seat(seat)
	if bool(accepted.get(other, false)):
		var spawned: Dictionary = _spawn_rematch(match_state)
		rem["status"] = Contract.REMATCH_READY
		rem["newMatchId"] = str(spawned.get("matchId", ""))
		_broadcast(match_state)
		return _rematch_payload(match_state, seat)
	rem["status"] = Contract.REMATCH_WAITING
	_broadcast(match_state)
	return _rematch_payload(match_state, seat)


func terrain_fingerprint(match_id: String) -> String:
	if not _matches.has(match_id):
		return ""
	var match_state: Dictionary = _matches[match_id]
	var bits := PackedStringArray()
	for q in Contract.BOARD_Q:
		for r in Contract.BOARD_R:
			bits.append(str(_terrain_type(match_state, q, r)))
	return "|".join(bits)


func get_snapshot(match_id: String, player_id: String) -> Dictionary:
	var found := _find(match_id, player_id)
	if found.is_empty():
		return {}
	_reconcile_grace(found["match"])
	_touch_rematch(found["match"])
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
		Contract.ACT_DECOY:
			applied = _act_decoy(match_state, seat)
		Contract.ACT_END_TURN:
			applied = _act_end_turn(match_state, seat, action)
		_:
			applied = ActionResult.fail("unknown_action", snap)
	if applied.ok:
		_broadcast(match_state)
	return applied


func clear_all() -> void:
	_matches.clear()
	_lobbies.clear()
	_lobby_by_code.clear()
	_queue.clear()
	_queue_pairs.clear()
	_queue_timed_out.clear()
	queue_pair_delay_ms = 80
	test_recon_roll = -1.0
	test_now_ms = -1
	## Wallet stays — PLAY must not wipe hideout Marks. Tests call reset_wallet().


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
		"decoyAvailable": true,
		"decoyHex": null,
		"decoyJustPlaced": false,
		"disconnectedAtMs": 0,
		"lastSeenMs": 0,
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
	# Real kill path unchanged. Decoy hex is never a secret position at place-time.
	if hit:
		match_state["status"] = Contract.STATUS_ENDED
		match_state["whoseTurn"] = null
		match_state["phase"] = null
		match_state["winner"] = seat
		_clear_all_decoys(match_state)
		_settle_payout(match_state, Contract.END_KILL)
		var pay: Dictionary = match_state["payouts"][seat]
		_set_last(match_state, {
			"type": Contract.ACT_ATTACK,
			"seat": seat,
			"hex": hex,
			"hit": true,
			"kill": true,
			"decoyCleared": false,
			"marks": pay.get("marks", account_marks),
			"marksDelta": pay.get("marksDelta", 0),
			"reason": pay.get("reason", Contract.END_KILL),
		})
	else:
		var decoy_cleared := Contract.same_hex(hex, enemy.get("decoyHex", null))
		if decoy_cleared:
			_clear_seat_decoy(enemy)
		match_state["phase"] = Contract.PHASE_END_TURN
		_set_last(match_state, {
			"type": Contract.ACT_ATTACK,
			"seat": seat,
			"hex": hex,
			"hit": false,
			"kill": false,
			"decoyCleared": decoy_cleared,
		})
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
	var decoy_in_sector := false
	if bool(enemy["placed"]) and enemy["hex"] != null:
		var eq := int(enemy["hex"]["q"])
		var er := int(enemy["hex"]["r"])
		for cell in cells:
			if cell.x == eq and cell.y == er:
				in_sector = true
				break
	var decoy_hex: Variant = enemy.get("decoyHex", null)
	if decoy_hex is Dictionary:
		var dq := int(decoy_hex.get("q", -1))
		var dr := int(decoy_hex.get("r", -1))
		for cell in cells:
			if cell.x == dq and cell.y == dr:
				decoy_in_sector = true
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
	var recon_last := {
		"type": Contract.ACT_RECON,
		"seat": seat,
		"spotted": found,
		"found": found,
		"decoySpotted": decoy_in_sector,
	}
	if found:
		recon_last["hex"] = enemy["hex"].duplicate()
	if decoy_in_sector and decoy_hex is Dictionary:
		## Soft-mark the toy doll only — never promote it to real Hot / visibleHex.
		recon_last["decoyHex"] = (decoy_hex as Dictionary).duplicate()
	_set_last(match_state, recon_last)
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


func _act_decoy(match_state: Dictionary, seat: String) -> ActionResult:
	var gate := _need_own_action(match_state, seat)
	if gate != "":
		return _fail(match_state, seat, gate)
	var seat_state: Dictionary = match_state["seats"][seat]
	if not bool(seat_state.get("decoyAvailable", false)):
		return _fail(match_state, seat, "decoy_spent")
	var dest: Variant = _pick_decoy_hex(match_state, seat)
	if dest == null:
		return _fail(match_state, seat, "decoy_no_hex")
	seat_state["decoyAvailable"] = false
	seat_state["decoyHex"] = dest
	seat_state["decoyJustPlaced"] = true
	match_state["phase"] = Contract.PHASE_END_TURN
	_set_last(match_state, {
		"type": Contract.ACT_DECOY,
		"hex": dest,
	})
	return _ok(match_state, seat)


func _pick_decoy_hex(match_state: Dictionary, seat: String) -> Variant:
	## LIVE pickDecoyHex: DECOY_DIRS order, on-board, not either secret. Dolls are not occupants.
	var seat_state: Dictionary = match_state["seats"][seat]
	var here: Variant = seat_state.get("hex", null)
	if here == null or not (here is Dictionary):
		return null
	var occupied: Array = []
	for key in [Contract.SEAT_A, Contract.SEAT_B]:
		var other_hex: Variant = match_state["seats"][key].get("hex", null)
		if other_hex is Dictionary:
			occupied.append(other_hex)
	var oq := int(here["q"])
	var orow := int(here["r"])
	for dir in HexMath.DECOY_DIRS:
		var cand := Contract.hex_dict(oq + dir.x, orow + dir.y)
		if not Contract.on_board(int(cand["q"]), int(cand["r"])):
			continue
		var blocked := false
		for hex in occupied:
			if Contract.same_hex(cand, hex):
				blocked = true
				break
		if not blocked:
			return cand
	return null


func _clear_seat_decoy(seat_state: Dictionary) -> void:
	seat_state["decoyHex"] = null
	seat_state["decoyJustPlaced"] = false


func _clear_all_decoys(match_state: Dictionary) -> void:
	for key in [Contract.SEAT_A, Contract.SEAT_B]:
		_clear_seat_decoy(match_state["seats"][key])


func _decoy_hex_for_snap(seat_state: Dictionary, match_state: Dictionary) -> Variant:
	if str(match_state.get("status", "")) == Contract.STATUS_ENDED:
		return null
	var hex: Variant = seat_state.get("decoyHex", null)
	if hex is Dictionary:
		return hex.duplicate()
	return null


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
	## Expiry: the end_turn that completes the decoy turn keeps it live;
	## the caster's next own end_turn clears the toy doll.
	if seat_state.get("decoyHex", null) != null:
		if bool(seat_state.get("decoyJustPlaced", false)):
			seat_state["decoyJustPlaced"] = false
		else:
			_clear_seat_decoy(seat_state)
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
		_clear_all_decoys(match_state)
		_settle_payout(match_state, Contract.END_STANDOFF)
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


func _settle_payout(match_state: Dictionary, end_reason: String) -> void:
	if bool(match_state.get("payoutSettled", false)):
		return
	match_state["payoutSettled"] = true
	var job := str(match_state.get("mode", Contract.MODE_PVP)) == Contract.MODE_SP_JOB
	var job_tier := int(match_state.get("jobTier", 1))
	var winner: Variant = match_state.get("winner", null)
	if end_reason == Contract.END_KILL and job:
		end_reason = Contract.END_JOB
	match_state["endReason"] = end_reason
	for seat in [Contract.SEAT_A, Contract.SEAT_B]:
		var reason := end_reason
		var delta := 0
		if end_reason in [Contract.END_FORFEIT, Contract.END_DISCONNECT]:
			if winner != null and str(winner) == seat:
				delta = Contract.MARKS_FORFEIT_WIN
			else:
				delta = Contract.MARKS_FORFEIT_LOSS
				reason = Contract.END_FORFEIT
		elif winner == Contract.WIN_DRAW or str(winner) == Contract.WIN_DRAW:
			delta = Contract.MARKS_STANDOFF
			reason = Contract.END_STANDOFF
		elif winner != null and str(winner) == seat:
			delta = Contract.job_tier_delta(job_tier) if job else Contract.MARKS_PVP_WIN
			reason = Contract.END_JOB if job else Contract.END_KILL
		else:
			delta = Contract.MARKS_JOB_FAIL if job else Contract.MARKS_PVP_LOSS
			reason = Contract.END_JOB_FAIL if job else Contract.END_LOSS
		var balance := account_marks
		if seat == Contract.SEAT_A:
			account_marks += delta
			balance = account_marks
		else:
			var seat_state: Dictionary = match_state["seats"][seat]
			seat_state["marks"] = int(seat_state.get("marks", 0)) + delta
			balance = int(seat_state["marks"])
		match_state["payouts"][seat] = {
			"marks": balance,
			"marksDelta": delta,
			"reason": reason,
		}
	_open_rematch(match_state)


func _end_forfeit(match_state: Dictionary, loser_seat: String) -> void:
	## Same settle as a 30s silence timeout. Idempotent if already ended.
	if match_state["status"] == Contract.STATUS_ENDED:
		return
	var winner := Contract.other_seat(loser_seat)
	match_state["status"] = Contract.STATUS_ENDED
	match_state["whoseTurn"] = null
	match_state["phase"] = null
	match_state["winner"] = winner
	_set_last(match_state, {
		"type": Contract.ACT_FORFEIT,
		"winner": winner,
		"seat": loser_seat,
	})
	_settle_payout(match_state, Contract.END_FORFEIT)


func _reconcile_grace(match_state: Dictionary) -> void:
	if match_state["status"] != Contract.STATUS_ACTIVE:
		return
	var cutoff := _now_ms() - Contract.FORFEIT_GRACE_SEC * 1000
	var stale := ""
	var stale_at := 0
	for seat in [Contract.SEAT_A, Contract.SEAT_B]:
		var at := int(match_state["seats"][seat].get("disconnectedAtMs", 0))
		if at != 0 and at <= cutoff:
			if stale == "" or at < stale_at:
				stale = seat
				stale_at = at
	if stale != "":
		_end_forfeit(match_state, stale)


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
	var pay: Dictionary = {}
	var payouts: Variant = match_state.get("payouts", {})
	if payouts is Dictionary:
		var stored: Variant = payouts.get(seat, {})
		if stored is Dictionary:
			pay = stored.duplicate(true)
	var balance := account_marks if seat == Contract.SEAT_A else int(you.get("marks", 0))
	if pay.has("marks"):
		balance = int(pay.get("marks"))
	var snap := {
		"matchId": match_state["matchId"],
		"status": match_state["status"],
		"turnIndex": match_state["turnIndex"],
		"turnCap": match_state["turnCap"],
		"whoseTurn": match_state["whoseTurn"],
		"phase": match_state["phase"],
		"uavRemaining": int(you["uavRemaining"]),
		"uavAvailable": int(you["uavRemaining"]) > 0,
		"kind": str(match_state.get("mode", Contract.MODE_PVP)),
		"mode": str(match_state.get("mode", Contract.MODE_PVP)),
		"jobId": str(match_state.get("jobId", "")),
		"jobTier": int(match_state.get("jobTier", 1)),
		"you": {
			"seat": seat,
			"hex": you_hex,
			"placed": bool(you["placed"]),
			"marks": balance,
			"exposurePct": you["exposurePct"],
			"movedLastTurn": bool(you["movedLastTurn"]),
			"equippedSkinId": equipped_cosmetic if equipped_cosmetic != "" else null,
			"equipped": equipped_cosmetic if equipped_cosmetic != "" else null,
			"equippedDecorId": equipped_decor if equipped_decor != "" else null,
			"decoyAvailable": bool(you.get("decoyAvailable", false)),
			"decoyRemaining": 1 if bool(you.get("decoyAvailable", false)) else 0,
			"decoyHex": _decoy_hex_for_snap(you, match_state),
		},
		"enemy": {
			"seat": other,
			"visibleHex": visible,
			"softHotTurnsLeft": int(intel.get("softHotTurnsLeft", 0)),
			"decoySoftHex": _decoy_hex_for_snap(match_state["seats"][other], match_state),
			"disconnectedAt": _disconnected_iso(match_state["seats"][other]),
		},
		"terrain": terrain,
		"lastAction": last,
		"winner": match_state["winner"],
	}
	if str(match_state.get("mode", "")) == Contract.MODE_SP_JOB:
		snap["job"] = {
			"jobId": str(match_state.get("jobId", match_state.get("matchId", ""))),
			"tier": int(match_state.get("jobTier", 1)),
			"name": Contract.job_name(int(match_state.get("jobTier", 1))),
			"status": "active" if match_state["status"] != Contract.STATUS_ENDED else ("won" if match_state.get("winner") == seat else "failed"),
		}
	if match_state.get("endReason", null) != null:
		var ended := str(match_state.get("endReason"))
		if ended == Contract.END_JOB:
			ended = Contract.END_KILL
		elif ended == Contract.END_JOB_FAIL:
			ended = Contract.END_STANDOFF if match_state.get("winner") == Contract.WIN_DRAW else Contract.END_KILL
		## LIVE vocabulary: kill | standoff | forfeit. Keep job as extra reason on payout.
		if ended in [Contract.END_KILL, Contract.END_STANDOFF, Contract.END_FORFEIT, Contract.END_DISCONNECT]:
			snap["endReason"] = ended if ended != Contract.END_DISCONNECT else Contract.END_FORFEIT
		elif ended == Contract.END_LOSS:
			snap["endReason"] = Contract.END_KILL
		else:
			snap["endReason"] = match_state.get("endReason")
	if not pay.is_empty():
		snap["payout"] = pay
		snap["marks"] = balance
		snap["marksDelta"] = pay.get("marksDelta", 0)
		snap["reason"] = str(pay.get("reason", ""))
	else:
		snap["marks"] = balance
	if match_state["status"] == Contract.STATUS_ENDED:
		var rem_bag := _rematch_public(match_state, seat)
		if not rem_bag.is_empty():
			snap["rematch"] = rem_bag
	elif match_state["status"] == Contract.STATUS_ACTIVE:
		var grace := _grace_public(match_state, other)
		if not grace.is_empty():
			snap["graceEndsAt"] = grace.get("endsAt")
			snap["graceRemainingSec"] = grace.get("remainingSec")
			snap["grace"] = grace
	return snap


func _disconnected_iso(seat_state: Dictionary) -> Variant:
	var at := int(seat_state.get("disconnectedAtMs", 0))
	if at == 0:
		return null
	var unix := int(Time.get_unix_time_from_system()) - int((_now_ms() - at) / 1000)
	return Time.get_datetime_string_from_unix_time(maxi(0, unix), true) + "Z"


func _grace_public(match_state: Dictionary, disconnected_seat: String) -> Dictionary:
	var at := int(match_state["seats"][disconnected_seat].get("disconnectedAtMs", 0))
	if at == 0:
		return {}
	var ends := at + Contract.FORFEIT_GRACE_SEC * 1000
	var left := maxf(0.0, float(ends - _now_ms()) / 1000.0)
	return {
		"remainingSec": left,
		"endsAt": _disconnected_iso({
			"disconnectedAtMs": ends,
		}),
	}


func _now_ms() -> int:
	if test_now_ms >= 0:
		return test_now_ms
	return Time.get_ticks_msec()


func _open_rematch(match_state: Dictionary) -> void:
	if str(match_state.get("mode", Contract.MODE_PVP)) == Contract.MODE_SP_JOB:
		match_state["rematch"] = {"status": Contract.REMATCH_NONE}
		return
	match_state["rematch"] = {
		"status": Contract.REMATCH_WAITING,
		"openedAtMs": _now_ms(),
		"accepted": {Contract.SEAT_A: false, Contract.SEAT_B: false},
		"newMatchId": "",
	}


func _rematch_state(match_state: Dictionary) -> Dictionary:
	var rem: Variant = match_state.get("rematch", {})
	if rem is Dictionary and not rem.is_empty():
		return rem
	var empty := {
		"status": Contract.REMATCH_NONE,
		"openedAtMs": 0,
		"accepted": {Contract.SEAT_A: false, Contract.SEAT_B: false},
		"newMatchId": "",
	}
	match_state["rematch"] = empty
	return empty


func _touch_rematch(match_state: Dictionary) -> void:
	if match_state["status"] != Contract.STATUS_ENDED:
		return
	var rem := _rematch_state(match_state)
	var st := str(rem.get("status", Contract.REMATCH_NONE))
	if st in [Contract.REMATCH_READY, Contract.REMATCH_DECLINED, Contract.REMATCH_EXPIRED, Contract.REMATCH_NONE]:
		return
	var opened := int(rem.get("openedAtMs", 0))
	if opened > 0 and _now_ms() - opened >= Contract.REMATCH_TIMEOUT_MS:
		rem["status"] = Contract.REMATCH_EXPIRED


func _rematch_public(match_state: Dictionary, seat: String = Contract.SEAT_A) -> Dictionary:
	_touch_rematch(match_state)
	var rem := _rematch_state(match_state)
	var accepted: Dictionary = rem.get("accepted", {})
	var st := str(rem.get("status", Contract.REMATCH_NONE))
	if st in [Contract.REMATCH_PENDING, Contract.REMATCH_ACCEPTED_A, Contract.REMATCH_ACCEPTED_B]:
		st = Contract.REMATCH_WAITING
	var you_on := bool(accepted.get(seat, false)) or st == Contract.REMATCH_READY
	var opp_on := bool(accepted.get(Contract.other_seat(seat), false)) or st == Contract.REMATCH_READY
	var bag := {
		"status": st,
		"youAccepted": you_on,
		"opponentAccepted": opp_on,
		"expiresAt": _rematch_expires_iso(rem),
	}
	var new_id := str(rem.get("newMatchId", ""))
	if new_id != "" and st == Contract.REMATCH_READY:
		bag["newMatchId"] = new_id
		bag["matchId"] = new_id
	return bag


func _spawn_rematch(old: Dictionary) -> Dictionary:
	## New matchId + salt. Same two playerIds. No Marks grant/spend.
	var created: Dictionary = create_match({"mode": Contract.MODE_PVP})
	var new_id := str(created.get("matchId", ""))
	if new_id == "" or not _matches.has(new_id):
		return created
	var neu: Dictionary = _matches[new_id]
	neu["salt"] = "%s:%s:r" % [Contract.TERRAIN_SALT, new_id]
	neu["rematchOf"] = str(old.get("matchId", ""))
	for seat in [Contract.SEAT_A, Contract.SEAT_B]:
		var src: Dictionary = old["seats"][seat]
		neu["seats"][seat]["playerId"] = str(src.get("playerId", ""))
	if _both_joined(neu):
		neu["status"] = Contract.STATUS_READY
	return created


func _rematch_expires_iso(rem: Dictionary) -> String:
	var opened := int(rem.get("openedAtMs", _now_ms()))
	var left_ms := maxi(0, opened + Contract.REMATCH_TIMEOUT_MS - _now_ms())
	var exp_unix := int(Time.get_unix_time_from_system()) + int(left_ms / 1000)
	return Time.get_datetime_string_from_unix_time(exp_unix, true) + "Z"


func _rematch_payload(match_state: Dictionary, seat: String) -> Dictionary:
	var rem := _rematch_public(match_state, seat)
	var st := str(rem.get("status", Contract.REMATCH_NONE))
	if st == Contract.REMATCH_READY:
		var new_id := str(rem.get("newMatchId", ""))
		if new_id != "" and _matches.has(new_id):
			var neu: Dictionary = _matches[new_id]
			var tokens: Dictionary = neu.get("tokens", {})
			var join := str(tokens.get(seat, ""))
			var neu_snap := _snapshot_for_seat(neu, seat)
			return {
				"ok": true,
				"error": "",
				"status": Contract.REMATCH_READY,
				"matchId": new_id,
				"joinToken": join,
				"seat": seat,
				"snapshot": neu_snap,
				"rematch": rem,
				"newMatchId": new_id,
				"joinTokens": tokens.duplicate(true),
				"newMatch": {
					"matchId": new_id,
					"joinTokens": tokens.duplicate(true),
					"snapshot": neu_snap,
				},
			}
	if st in [Contract.REMATCH_DECLINED, Contract.REMATCH_EXPIRED]:
		return {
			"ok": true,
			"error": "",
			"status": st,
			"rematch": rem,
			"snapshot": _snapshot_for_seat(match_state, seat),
		}
	return {
		"ok": true,
		"error": "",
		"status": Contract.REMATCH_WAITING,
		"youAccepted": bool(rem.get("youAccepted", false)),
		"opponentAccepted": bool(rem.get("opponentAccepted", false)),
		"expiresAt": str(rem.get("expiresAt", "")),
		"rematch": rem,
		"snapshot": _snapshot_for_seat(match_state, seat),
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
