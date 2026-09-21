extends Node
## LIVE contract loop through LiveMatchClient (needs API on 127.0.0.1:8787).
##   GLASSLINE_USE_LIVE_API=1 godot --headless --path . res://tools/live_loop_test.tscn

const Contract := preload("res://types/contract.gd")
const ActionIntent := preload("res://types/action_intent.gd")
const ActionResult := preload("res://types/action_result.gd")
const Snapshot := preload("res://types/snapshot.gd")


func _ready() -> void:
	ClientSession.live_override = 1
	var code := _run()
	get_tree().quit(code)


func _run() -> int:
	var failed: PackedStringArray = []
	MatchAPI.clear_all()

	var health: Dictionary = MatchAPI.health()
	_expect(failed, bool(health.get("ok", false)), "health ok")

	var created: Dictionary = MatchAPI.create_match()
	_expect(failed, created.has("matchId"), "create_match.matchId")
	_expect(failed, not created.has("joinTokens"), "create never dual-seat")
	_expect(failed, str(created.get("joinToken", "")) != "", "create joinToken")
	_expect(failed, str(created.get("seat", "")) == "a", "create seat a")
	var match_id := str(created.get("matchId", ""))
	var seated: Dictionary = MatchAPI.sit_created_pvp(created)
	_expect(failed, not seated.has("error"), "sit created pvp")
	var join_a: Dictionary = seated.get("human", {})
	var join_b: Dictionary = seated.get("dummy", {})
	_expect(failed, str(join_a.get("seat", "")) == "a", "join a")
	_expect(failed, str(join_b.get("seat", "")) == "b", "join b")

	var r: ActionResult = MatchAPI.apply_action(match_id, ClientSession.player_id, ActionIntent.select_hex(2, 2))
	_expect(failed, r.ok, "a select_hex")
	r = MatchAPI.apply_action(match_id, ClientSession.dummy_player_id, ActionIntent.select_hex(7, 5))
	_expect(failed, r.ok, "b select_hex")
	var snap: Snapshot = Snapshot.from_dict(MatchAPI.get_snapshot(match_id, ClientSession.player_id))
	_expect(failed, snap.status() == Contract.STATUS_ACTIVE, "auto-active after both drops")
	_expect(failed, snap.you_placed(), "you_placed inferred from hex")

	r = MatchAPI.apply_action(match_id, ClientSession.player_id, ActionIntent.start())
	_expect(failed, r.ok, "start no-op when already active")
	_expect(failed, Snapshot.from_dict(r.snapshot).status() == Contract.STATUS_ACTIVE, "start no-op snapshot")

	r = MatchAPI.apply_action(match_id, ClientSession.player_id, ActionIntent.attack(0, 0))
	_expect(failed, r.ok, "attack miss")
	_expect(failed, r.result.get("hit") == false, "miss hit=false")
	snap = Snapshot.from_dict(r.snapshot)
	_expect(failed, snap.enemy_visible_hex() == null, "miss no Hot")
	_expect(failed, str(snap.phase()) == Contract.PHASE_END_TURN, "miss → end_turn")

	r = MatchAPI.apply_action(match_id, ClientSession.player_id, ActionIntent.end_turn(50))
	_expect(failed, r.ok, "a end_turn")
	_expect(failed, str(Snapshot.from_dict(r.snapshot).whose_turn()) == "b", "turn to b")

	r = MatchAPI.apply_action(match_id, ClientSession.dummy_player_id, ActionIntent.recon(4, 3))
	_expect(failed, r.ok, "b recon")
	r = MatchAPI.apply_action(match_id, ClientSession.dummy_player_id, ActionIntent.end_turn(40))
	_expect(failed, r.ok, "b end_turn")

	r = MatchAPI.apply_action(match_id, ClientSession.player_id, ActionIntent.uav())
	_expect(failed, r.ok, "uav")
	snap = Snapshot.from_dict(r.snapshot)
	_expect(failed, snap.uav_remaining() == 0, "uavRemaining 0")
	var vis: Variant = snap.enemy_visible_hex()
	_expect(failed, vis is Dictionary, "uav visibleHex")

	r = MatchAPI.apply_action(match_id, ClientSession.player_id, ActionIntent.end_turn(50))
	_expect(failed, r.ok, "a end after uav")
	r = MatchAPI.apply_action(match_id, ClientSession.dummy_player_id, ActionIntent.recon(1, 1))
	_expect(failed, r.ok, "b filler recon")
	r = MatchAPI.apply_action(match_id, ClientSession.dummy_player_id, ActionIntent.end_turn(50))
	_expect(failed, r.ok, "b filler end")

	if vis is Dictionary:
		r = MatchAPI.apply_action(match_id, ClientSession.player_id, ActionIntent.attack(int(vis["q"]), int(vis["r"])))
	else:
		r = MatchAPI.apply_action(match_id, ClientSession.player_id, ActionIntent.attack(7, 5))
	_expect(failed, r.ok, "attack kill")
	snap = Snapshot.from_dict(r.snapshot)
	_expect(failed, bool(r.result.get("kill", false)), "kill flag")
	_expect(failed, snap.status() == Contract.STATUS_ENDED, "ended")
	_expect(failed, str(snap.winner()) == "a", "winner a")
	_expect(failed, snap.you_marks() == 1, "marks +1")

	if failed.is_empty():
		print("LIVE_LOOP_OK ", match_id)
		return 0
	for line in failed:
		print("FAIL: ", line)
	return 1


func _expect(failed: PackedStringArray, cond: bool, label: String) -> void:
	if not cond:
		failed.append(label)
