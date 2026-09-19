extends Node
## LIVE shop through LiveMatchClient + durable POST /players token.
##   GLASSLINE_USE_LIVE_API=1 godot --headless --path . res://tools/live_shop_test.tscn
## Binds you.marks from the buy/402 payload only — never local marks -=.

const Contract := preload("res://types/contract.gd")
const Shop := preload("res://types/shop.gd")
const ActionIntent := preload("res://types/action_intent.gd")
const ActionResult := preload("res://types/action_result.gd")


func _ready() -> void:
	ClientSession.live_override = 1
	var code := _run()
	get_tree().quit(code)


func _run() -> int:
	var failed: PackedStringArray = []
	MatchAPI.clear_all()

	var health: Dictionary = MatchAPI.health()
	_expect(failed, bool(health.get("ok", false)), "health ok")

	var catalog: Dictionary = LiveMatchClient.get_shop()
	var listed = Shop.from_any(catalog)
	_expect(failed, listed.item_id() == "skin_hideout_stub", "get_shop itemId skin_hideout_stub")
	_expect(failed, listed.price() == Contract.SHOP_STUB_PRICE, "get_shop price 50")
	print("LIVE_SHOP_CATALOG ", JSON.stringify(catalog))

	## --- S2: fresh player at ★0 → 402, apply_shop binds you.marks (never 999-50) ---
	var s2: Dictionary = MatchAPI.ensure_player(true)
	_expect(failed, str(s2.get("token", "")) != "", "S2 POST /players token")
	_expect(failed, int(s2.get("marks", -1)) == 0, "S2 minted marks 0")
	var start_marks := int(s2.get("marks", 0))
	ClientSession.bind_marks(999)
	var buy_id_s2 := Contract.new_client_buy_id()
	var body_s2: Dictionary = LiveMatchClient.buy_shop(Contract.SHOP_STUB_ITEM_ID, buy_id_s2)
	var shop_s2 = Shop.from_any(body_s2)
	ClientSession.apply_shop(body_s2)
	print("LIVE_SHOP_S2 ", JSON.stringify(body_s2))
	_expect(failed, int(body_s2.get("status", 0)) == 402, "S2 status 402")
	_expect(failed, shop_s2.is_insufficient(), "S2 insufficient_marks")
	_expect(failed, ClientSession.marks != 949, "never local marks -= from 999")
	_expect(failed, ClientSession.marks == start_marks, "S2 apply_shop binds you.marks unchanged")
	print("LIVE_SHOP_S2_OK marks ", start_marks, "→", ClientSession.marks)

	## --- S1: same durable player, two kill wins ★25+★25, then buy ★50 ---
	var s1: Dictionary = MatchAPI.ensure_player(true)
	var player_id := str(s1.get("playerId", ""))
	_expect(failed, str(s1.get("token", "")) != "", "S1 POST /players token")
	var earned := 0
	var last_mid := ""
	for i in range(1, 3):
		var snap: Dictionary = _pvp_kill(failed, i)
		last_mid = str(snap.get("matchId", last_mid))
		var you: Variant = snap.get("you", {})
		var next_marks := int(you.get("marks", -1)) if you is Dictionary else -1
		_expect(failed, str(snap.get("status", "")) == Contract.STATUS_ENDED, "S1 kill %d ended" % i)
		_expect(failed, next_marks == earned + Contract.MARKS_PVP_WIN, "S1 kill %d marks %d→%d" % [i, earned, next_marks])
		_expect(failed, ClientSession.durable_player_id == player_id, "S1 kill %d same playerId" % i)
		earned = next_marks
	_expect(failed, earned >= Contract.SHOP_STUB_PRICE, "S1 earned ≥50 as same player")

	var buy_id := Contract.new_client_buy_id()
	ClientSession.bind_marks(999)
	var body: Dictionary = LiveMatchClient.buy_shop(Contract.SHOP_STUB_ITEM_ID, buy_id)
	var shop = Shop.from_any(body)
	ClientSession.apply_shop(body)
	print("LIVE_SHOP_BUY ", JSON.stringify(body))
	_expect(failed, int(body.get("status", 0)) == 200, "S1 buy HTTP 200")
	_expect(failed, shop.ok, "S1 buy ok")
	_expect(failed, shop.has_marks(), "S1 buy returned you.marks")
	_expect(failed, ClientSession.marks == shop.balance(), "S1 session marks from snapshot")
	_expect(failed, ClientSession.marks == earned - Contract.SHOP_STUB_PRICE, "S1 debit 50 from snapshot")
	_expect(failed, ClientSession.marks != 949, "S1 never local marks -= from 999")
	_expect(failed, shop.purchase_id != "", "S1 purchaseId")

	var replay: Dictionary = LiveMatchClient.buy_shop(Contract.SHOP_STUB_ITEM_ID, buy_id)
	var shop_r = Shop.from_any(replay)
	ClientSession.apply_shop(replay)
	print("LIVE_SHOP_REPLAY ", JSON.stringify(replay))
	_expect(failed, int(replay.get("status", 0)) == 200, "S3 replay HTTP 200")
	_expect(failed, ClientSession.marks == shop.balance(), "S3 replay no second debit")
	_expect(failed, shop_r.purchase_id == shop.purchase_id, "S3 same purchaseId")
	print(
		"LIVE_SHOP_S1_S3_OK marks ",
		earned,
		"→",
		ClientSession.marks,
		" purchase ",
		shop.purchase_id,
		" player ",
		player_id,
		" match ",
		last_mid
	)

	var catalog_ids: Array = []
	for entry in (catalog.get("items", []) as Array):
		if entry is Dictionary:
			catalog_ids.append(str(entry.get("id", "")))
	if catalog_ids.has(Contract.SHOP_BANDANA_ITEM_ID):
		print("LIVE_SHOP_SINK2_CATALOG_OK")
	else:
		print("LIVE_SHOP_SINK2_PENDING catalog missing ", Contract.SHOP_BANDANA_ITEM_ID)

	if failed.is_empty():
		print("LIVE_SHOP_LOOP_OK")
		return 0
	for line in failed:
		push_error(line)
		print("FAIL: ", line)
	print("LIVE_SHOP_LOOP_FAIL")
	return 1


func _pvp_kill(failed: PackedStringArray, idx: int) -> Dictionary:
	ClientSession.reset_match()
	var created: Dictionary = MatchAPI.create_match()
	_expect(failed, created.has("matchId"), "S1 create_match %d" % idx)
	var match_id := str(created.get("matchId", ""))
	var tokens: Dictionary = created.get("joinTokens", {})
	ClientSession.join_token = str(tokens.get("a", ""))
	ClientSession.dummy_token = str(tokens.get("b", ""))
	var join_a: Dictionary = MatchAPI.join(match_id, ClientSession.join_token)
	var join_b: Dictionary = MatchAPI.join(match_id, ClientSession.dummy_token)
	_expect(failed, str(join_a.get("playerId", "")) == ClientSession.durable_player_id, "S1 join A same player %d" % idx)
	ClientSession.match_id = match_id
	ClientSession.player_id = str(join_a.get("playerId", ""))
	ClientSession.dummy_player_id = str(join_b.get("playerId", ""))
	ClientSession.seat = "a"
	var pid := ClientSession.player_id
	var dummy := ClientSession.dummy_player_id
	MatchAPI.apply_action(match_id, pid, ActionIntent.select_hex(2, 2))
	MatchAPI.apply_action(match_id, dummy, ActionIntent.select_hex(7, 5))
	MatchAPI.apply_action(match_id, pid, ActionIntent.attack(0, 0))
	var end_a: ActionResult = MatchAPI.apply_action(match_id, pid, ActionIntent.end_turn(50))
	if not end_a.ok:
		MatchAPI.apply_action(match_id, pid, {"type": "end_turn", "exposurePct": 50})
	MatchAPI.apply_action(match_id, dummy, ActionIntent.recon(4, 3))
	MatchAPI.apply_action(match_id, dummy, ActionIntent.end_turn(40, {"q": 6, "r": 5}))
	var uav: ActionResult = MatchAPI.apply_action(match_id, pid, ActionIntent.uav())
	var vis: Variant = (uav.snapshot.get("enemy", {}) as Dictionary).get("visibleHex") if uav.snapshot.has("enemy") else null
	MatchAPI.apply_action(match_id, pid, ActionIntent.end_turn(50))
	MatchAPI.apply_action(match_id, dummy, ActionIntent.recon(1, 1))
	MatchAPI.apply_action(match_id, dummy, ActionIntent.end_turn(50))
	var kill: ActionResult
	if vis is Dictionary:
		kill = MatchAPI.apply_action(match_id, pid, ActionIntent.attack(int(vis.get("q", 6)), int(vis.get("r", 5))))
	else:
		kill = MatchAPI.apply_action(match_id, pid, ActionIntent.attack(6, 5))
	ClientSession.apply_snapshot(kill.snapshot)
	return kill.snapshot


func _expect(failed: PackedStringArray, cond: bool, label: String) -> void:
	if not cond:
		failed.append(label)
