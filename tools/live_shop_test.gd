extends Node
## LIVE shop through LiveMatchClient.get_shop + buy_shop.
##   GLASSLINE_USE_LIVE_API=1 godot --headless --path . res://tools/live_shop_test.tscn
## Binds you.marks from the buy/402 payload only — never local marks -=.

const Contract := preload("res://types/contract.gd")
const Shop := preload("res://types/shop.gd")


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

	var created: Dictionary = MatchAPI.create_match()
	_expect(failed, created.has("matchId"), "create_match.matchId")
	var tokens: Dictionary = created.get("joinTokens", {})
	ClientSession.join_token = str(tokens.get("a", ""))
	ClientSession.dummy_token = str(tokens.get("b", ""))
	var join_a: Dictionary = MatchAPI.join(str(created.get("matchId", "")), ClientSession.join_token)
	MatchAPI.join(str(created.get("matchId", "")), ClientSession.dummy_token)
	ClientSession.match_id = str(created.get("matchId", ""))
	ClientSession.player_id = str(join_a.get("playerId", ""))
	var start_marks := 0
	var snap: Variant = join_a.get("snapshot", {})
	if snap is Dictionary:
		var you: Variant = snap.get("you", {})
		if you is Dictionary:
			start_marks = int(you.get("marks", 0))
	ClientSession.bind_marks(start_marks)

	var buy_id := Contract.new_client_buy_id()
	ClientSession.bind_marks(999)
	var body: Dictionary = LiveMatchClient.buy_shop(Contract.SHOP_STUB_ITEM_ID, buy_id)
	var shop = Shop.from_any(body)
	## Sole truth = payload you.marks. A local debit would land on 999-50=949.
	ClientSession.apply_shop(body)
	print("LIVE_SHOP_BUY ", JSON.stringify(body))
	_expect(failed, int(body.get("status", 0)) in [200, 402], "buy_shop HTTP 200 or 402")
	_expect(failed, ClientSession.marks != 949, "never local marks -= from 999")
	if shop.is_insufficient():
		_expect(failed, ClientSession.marks == start_marks, "S2 apply_shop binds you.marks unchanged")
		_expect(failed, int(body.get("status", 0)) == 402, "S2 status 402")
		print("LIVE_SHOP_S2_OK marks ", start_marks, "→", ClientSession.marks)
	elif shop.ok:
		_expect(failed, shop.has_marks(), "S1 buy returned you.marks")
		_expect(failed, ClientSession.marks == shop.balance(), "S1 session marks from snapshot")
		_expect(failed, ClientSession.marks == start_marks - Contract.SHOP_STUB_PRICE, "S1 debit 50 from snapshot")
		var replay: Dictionary = LiveMatchClient.buy_shop(Contract.SHOP_STUB_ITEM_ID, buy_id)
		ClientSession.apply_shop(replay)
		_expect(failed, ClientSession.marks == shop.balance(), "S3 replay no second debit")
		print("LIVE_SHOP_S1_S3_OK marks ", start_marks, "→", ClientSession.marks, " purchase ", shop.purchase_id)
	else:
		_expect(failed, false, "buy_shop unexpected %s" % shop.error)

	if failed.is_empty():
		print("LIVE_SHOP_LOOP_OK")
		return 0
	for line in failed:
		push_error(line)
		print("FAIL: ", line)
	print("LIVE_SHOP_LOOP_FAIL")
	return 1


func _expect(failed: PackedStringArray, cond: bool, label: String) -> void:
	if not cond:
		failed.append(label)
