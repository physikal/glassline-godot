extends Node
## Facade: MockMatchServer (default) or LiveMatchClient.
## Scenes call only these methods so the live swap is drop-in.

signal match_event(player_id: String, event_name: String, snapshot: Dictionary)

const ActionResult := preload("res://types/action_result.gd")
const Contract := preload("res://types/contract.gd")


func _ready() -> void:
	MockMatchServer.match_event.connect(_relay)
	LiveMatchClient.match_event.connect(_relay)


func _relay(player_id: String, event_name: String, snapshot: Dictionary) -> void:
	match_event.emit(player_id, event_name, snapshot)


func using_live() -> bool:
	return ClientSession.use_live_api()


func create_player() -> Dictionary:
	if using_live():
		return LiveMatchClient.create_player()
	return {"playerId": "p_mock", "token": "tok_mock", "marks": MockMatchServer.account_marks}


func ensure_player(force_new: bool = false) -> Dictionary:
	## LIVE: POST /players once, reuse Bearer. Mock: no-op wallet.
	if using_live():
		return LiveMatchClient.ensure_player(force_new)
	return MockMatchServer.wallet()


func create_match(opts: Dictionary = {}) -> Dictionary:
	if using_live():
		return LiveMatchClient.create_match(opts)
	return MockMatchServer.create_match(opts)


func wallet() -> Dictionary:
	if using_live():
		return LiveMatchClient.wallet()
	return MockMatchServer.wallet()


func get_shop_me() -> Dictionary:
	if using_live():
		return LiveMatchClient.get_shop_me()
	return MockMatchServer.get_shop()


func get_shop() -> Dictionary:
	if using_live():
		var body: Dictionary = LiveMatchClient.get_shop()
		if _shop_live_missing(body):
			## LIVE /shop missing — keep catalog stub rows visible; buy still posts LIVE.
			body = Contract.shop_catalog_stub(ClientSession.marks)
		else:
			body = Contract.merge_live_shop_catalog(body)
		var me: Dictionary = LiveMatchClient.get_shop_me()
		if str(me.get("error", "")) == "" and (me.has("you") or me.has("owned")):
			var you: Variant = me.get("you", {})
			if you is Dictionary:
				body["you"] = you
				if you.has("marks"):
					body["marks"] = you.get("marks")
				if you.has("equippedSkinId"):
					body["equippedSkinId"] = you.get("equippedSkinId")
					body["equipped"] = you.get("equippedSkinId")
				if you.has("equippedDecorId"):
					body["equippedDecorId"] = you.get("equippedDecorId")
			if me.has("owned"):
				body["owned"] = me.get("owned")
		return body
	return MockMatchServer.get_shop()


func buy_shop(item_id: String, client_buy_id: String = "") -> Dictionary:
	if using_live():
		return LiveMatchClient.buy_shop(item_id, client_buy_id)
	return MockMatchServer.buy_shop(item_id, client_buy_id)


func equip_cosmetic(item_id: String, slot: String = "") -> Dictionary:
	if using_live():
		return LiveMatchClient.equip_cosmetic(item_id, slot)
	return MockMatchServer.equip_cosmetic(item_id, slot)


func _shop_live_missing(body: Dictionary) -> bool:
	var err := str(body.get("error", ""))
	return err in [Contract.SHOP_ERR_UNAVAILABLE, "http_404", "bad_json"] or int(body.get("status", 0)) == 404


func create_job(tier: int = 1, client_job_id: String = "") -> Dictionary:
	if using_live():
		return LiveMatchClient.create_job(tier, client_job_id)
	return MockMatchServer.create_job(tier, client_job_id)


func complete_job(tier: int = 1, client_job_id: String = "") -> Dictionary:
	## Editor / capture helper. LIVE smoke plays the board; this stays mock-only.
	if using_live():
		return LiveMatchClient.create_job(tier, client_job_id)
	return MockMatchServer.complete_job(tier, client_job_id)


func get_job(job_id: String) -> Dictionary:
	if using_live():
		return LiveMatchClient.get_job(job_id)
	return MockMatchServer.get_job(job_id)


func heartbeat() -> Dictionary:
	if using_live():
		return LiveMatchClient.heartbeat()
	return {"ok": true, "mock": true}


func create_lobby() -> Dictionary:
	if using_live():
		return LiveMatchClient.create_lobby()
	var pid := ClientSession.durable_player_id
	if pid == "":
		pid = "p_mock"
	return MockMatchServer.create_lobby(pid)


func join_lobby(code: String) -> Dictionary:
	if using_live():
		return LiveMatchClient.join_lobby(code)
	var pid := ClientSession.durable_player_id
	if pid == "" or pid == "p_mock":
		pid = "p_guest"
	return MockMatchServer.join_lobby(code, pid)


func get_lobby(lobby_id: String) -> Dictionary:
	if using_live():
		return LiveMatchClient.get_lobby(lobby_id)
	var pid := ClientSession.durable_player_id
	if pid == "":
		pid = "p_mock"
	return MockMatchServer.get_lobby(lobby_id, pid)


func cancel_lobby(lobby_id: String) -> Dictionary:
	if using_live():
		return LiveMatchClient.cancel_lobby(lobby_id)
	var pid := ClientSession.durable_player_id
	if pid == "":
		pid = "p_mock"
	return MockMatchServer.cancel_lobby(lobby_id, pid)


func enqueue() -> Dictionary:
	if using_live():
		return LiveMatchClient.enqueue()
	var pid := ClientSession.durable_player_id
	if pid == "":
		pid = "p_mock"
	return MockMatchServer.enqueue(pid)


func get_queue() -> Dictionary:
	if using_live():
		return LiveMatchClient.get_queue()
	var pid := ClientSession.durable_player_id
	if pid == "":
		pid = "p_mock"
	return MockMatchServer.get_queue(pid)


func dequeue() -> Dictionary:
	if using_live():
		return LiveMatchClient.dequeue()
	var pid := ClientSession.durable_player_id
	if pid == "":
		pid = "p_mock"
	return MockMatchServer.dequeue(pid)


func bind_queue_match(body: Dictionary) -> Dictionary:
	## Same seat join as private lobby ready handoff.
	return bind_lobby_match(body)


func bind_lobby_match(body: Dictionary) -> Dictionary:
	## Prefer posted matchId + joinToken. Client never invents seats.
	var mid := str(body.get("matchId", body.get("newMatchId", "")))
	var tok := str(body.get("joinToken", ""))
	if mid == "":
		return {}
	stop_events()
	ClientSession.reset_match()
	ClientSession.match_mode = Contract.MODE_PVP
	ClientSession.match_id = mid
	if tok != "":
		ClientSession.join_token = tok
	var pid := str(body.get("playerId", ""))
	if pid != "":
		ClientSession.player_id = pid
	var seat := str(body.get("seat", ""))
	if seat != "":
		ClientSession.seat = seat
	var snap: Dictionary = {}
	var posted: Variant = body.get("snapshot", {})
	## Join returns a match snap. GET /lobbies/:id keeps a lobby snap even when ready.
	if posted is Dictionary and Contract.is_match_snapshot(posted, mid):
		snap = posted
	if snap.is_empty():
		snap = get_snapshot(mid, ClientSession.player_id)
	if not snap.is_empty():
		ClientSession.apply_snapshot(snap)
		if ClientSession.player_id == "" and str(snap.get("you", {}).get("playerId", "")) != "":
			ClientSession.player_id = str(snap.get("you", {}).get("playerId", ""))
		if ClientSession.seat == "":
			var you: Variant = snap.get("you", {})
			if you is Dictionary:
				ClientSession.seat = str(you.get("seat", Contract.SEAT_A))
	start_events()
	return snap


func join(match_id: String, token: String) -> Dictionary:
	if using_live():
		return LiveMatchClient.join(match_id, token)
	return MockMatchServer.join(match_id, token)


func get_snapshot(match_id: String, player_id: String) -> Dictionary:
	if using_live():
		return LiveMatchClient.get_snapshot(match_id, player_id)
	return MockMatchServer.get_snapshot(match_id, player_id)


func reconnect() -> Dictionary:
	## A2: re-GET the caller snapshot and replace client state. No local merge.
	if ClientSession.match_id == "" or ClientSession.player_id == "":
		return {}
	var fresh: Dictionary = get_snapshot(ClientSession.match_id, ClientSession.player_id)
	if not fresh.is_empty():
		ClientSession.apply_snapshot(fresh)
	return fresh


func abandon() -> Dictionary:
	return abandon_as(ClientSession.player_id)


func abandon_as(player_id: String) -> Dictionary:
	## POST /matches/:id/abandon + join Bearer. Idempotent if already ended.
	if using_live():
		var token := ClientSession.token_for(player_id)
		if token == "":
			token = ClientSession.player_bearer()
		return LiveMatchClient.abandon(ClientSession.match_id, token)
	return MockMatchServer.abandon(ClientSession.match_id, player_id)


func rematch(accept: bool) -> Dictionary:
	return rematch_as(ClientSession.player_id, accept)


func rematch_as(player_id: String, accept: bool) -> Dictionary:
	## POST /matches/:id/rematch { accept }. LIVE prefers the seat join token.
	if using_live():
		var token := ClientSession.token_for(player_id)
		if token == "":
			token = ClientSession.player_bearer()
		return LiveMatchClient.rematch(ClientSession.match_id, accept, token)
	return MockMatchServer.rematch(ClientSession.match_id, player_id, accept)


func bind_new_match(body: Dictionary) -> Dictionary:
	## Leave the ended match. LIVE ready: { matchId, joinToken, snapshot }.
	## Snapshot may be omitted — GET the new match with the posted joinToken.
	var rem: Variant = body.get("rematch", {})
	if not (rem is Dictionary):
		rem = {}
	var neu: Variant = body.get("newMatch", {})
	if not (neu is Dictionary):
		neu = {}
	var new_id := str(rem.get("newMatchId", body.get("newMatchId", body.get("matchId", ""))))
	if new_id == "":
		new_id = str(neu.get("matchId", ""))
	if new_id == "":
		return {}
	stop_events()
	var caller_join := str(body.get("joinToken", ""))
	if caller_join != "":
		ClientSession.join_token = caller_join
	var tokens: Variant = neu.get("joinTokens", body.get("joinTokens", {}))
	if not (tokens is Dictionary):
		tokens = {}
	ClientSession.match_id = new_id
	if not tokens.is_empty():
		var tok_a := str(tokens.get("a", tokens.get(Contract.SEAT_A, "")))
		var tok_b := str(tokens.get("b", tokens.get(Contract.SEAT_B, "")))
		if tok_a != "" and caller_join == "":
			ClientSession.join_token = tok_a
		if tok_b != "":
			ClientSession.dummy_token = tok_b
		if ClientSession.join_token != "":
			var human: Dictionary = join(new_id, ClientSession.join_token)
			if human.has("playerId"):
				ClientSession.player_id = str(human.get("playerId"))
				ClientSession.seat = str(human.get("seat", ClientSession.seat))
		if ClientSession.dummy_token != "":
			var dummy: Dictionary = join(new_id, ClientSession.dummy_token)
			if dummy.has("playerId"):
				ClientSession.dummy_player_id = str(dummy.get("playerId"))
	var snap: Dictionary = {}
	var posted: Variant = body.get("snapshot", {})
	if posted is Dictionary and str(posted.get("matchId", "")) == new_id \
			and str(posted.get("status", "")) != Contract.STATUS_ENDED:
		snap = posted
	if snap.is_empty():
		snap = get_snapshot(new_id, ClientSession.player_id)
	if snap.is_empty() and neu.has("snapshot") and neu.get("snapshot") is Dictionary:
		snap = neu.get("snapshot")
	if not snap.is_empty():
		ClientSession.apply_snapshot(snap)
	start_events()
	return snap


func apply_action(match_id: String, player_id: String, action: Dictionary) -> ActionResult:
	if using_live():
		return LiveMatchClient.apply_action(match_id, player_id, action)
	return MockMatchServer.apply_action(match_id, player_id, action)


func clear_all() -> void:
	LiveMatchClient.clear_all()
	MockMatchServer.clear_all()


func start_events() -> void:
	if using_live() and ClientSession.match_id != "" and ClientSession.join_token != "":
		LiveMatchClient.start_events(ClientSession.match_id, ClientSession.join_token)


func stop_events() -> void:
	LiveMatchClient.stop_events()


func health() -> Dictionary:
	if using_live():
		return LiveMatchClient.health()
	return {"ok": true, "mock": true}
