extends SceneTree
## Offline contract loop: drop both seats, miss, UAV reveal, kill, marks +1.
## Run: godot --headless --path . -s res://tools/headless_loop_test.gd

const Contract := preload("res://types/contract.gd")
const ActionIntent := preload("res://types/action_intent.gd")
const ActionResult := preload("res://types/action_result.gd")
const Snapshot := preload("res://types/snapshot.gd")
const MarksPayout := preload("res://types/marks_payout.gd")
const MockScript := preload("res://autoload/mock_match_server.gd")

var server


func _init() -> void:
	server = MockScript.new()
	var code := _run()
	quit(code)


func _run() -> int:
	var failed: PackedStringArray = []
	server.clear_all()
	server.reset_wallet(0)

	var created: Dictionary = server.create_match()
	_expect(failed, created.has("matchId"), "create_match.matchId")
	_expect(failed, created.has("joinTokens"), "create_match.joinTokens")
	var match_id := str(created["matchId"])
	var tokens: Dictionary = created["joinTokens"]

	var join_a: Dictionary = server.join(match_id, str(tokens["a"]))
	var join_b: Dictionary = server.join(match_id, str(tokens["b"]))
	_expect(failed, str(join_a.get("seat", "")) == "a", "join a seat")
	_expect(failed, str(join_b.get("seat", "")) == "b", "join b seat")
	var pid_a := str(join_a["playerId"])
	var pid_b := str(join_b["playerId"])
	var snap: Snapshot = Snapshot.from_dict(join_b["snapshot"])
	_expect(failed, snap.status() == Contract.STATUS_READY, "both joined -> ready")

	var r: ActionResult = server.apply_action(match_id, pid_a, ActionIntent.select_hex(1, 1))
	_expect(failed, r.ok, "a select_hex")
	_expect(failed, Snapshot.from_dict(r.snapshot).you_placed(), "a placed")

	# Re-drop allowed until start.
	r = server.apply_action(match_id, pid_a, ActionIntent.select_hex(2, 2))
	_expect(failed, r.ok, "a re-drop")
	_expect(failed, Contract.same_hex(Snapshot.from_dict(r.snapshot).you_hex(), Contract.hex_dict(2, 2)), "a hex 2,2")

	r = server.apply_action(match_id, pid_b, ActionIntent.select_hex(7, 5))
	_expect(failed, r.ok, "b select_hex")

	r = server.apply_action(match_id, pid_a, ActionIntent.start())
	_expect(failed, r.ok, "start")
	snap = Snapshot.from_dict(r.snapshot)
	_expect(failed, snap.status() == Contract.STATUS_ACTIVE, "active")
	_expect(failed, str(snap.whose_turn()) == "a", "whoseTurn a")
	_expect(failed, str(snap.phase()) == Contract.PHASE_ACTION, "await_action")
	_expect(failed, int(snap.you_exposure()) == 50, "exposure 50")
	_expect(failed, snap.enemy_visible_hex() == null, "no free intel")

	# Attack miss — empty hex, must not invent Hot.
	r = server.apply_action(match_id, pid_a, ActionIntent.attack(0, 0))
	_expect(failed, r.ok, "attack miss ok")
	snap = Snapshot.from_dict(r.snapshot)
	var last: Variant = snap.last_action()
	_expect(failed, last is Dictionary and last.get("hit") == false, "miss hit=false")
	_expect(failed, snap.enemy_visible_hex() == null, "miss does not invent Hot")
	_expect(failed, str(snap.phase()) == Contract.PHASE_END_TURN, "miss -> end_turn")
	# Terrain revealed only for the attacked hex on first select.
	var tmap: Dictionary = snap.terrain_map()
	_expect(failed, tmap.has("0,0"), "miss reveals target terrain")

	r = server.apply_action(match_id, pid_a, ActionIntent.end_turn(50))
	_expect(failed, r.ok, "a end_turn after miss")
	_expect(failed, str(Snapshot.from_dict(r.snapshot).whose_turn()) == "b", "turn passed to b")

	r = server.apply_action(match_id, pid_b, ActionIntent.recon(4, 3))
	_expect(failed, r.ok, "b recon")
	r = server.apply_action(match_id, pid_b, ActionIntent.end_turn(40, Contract.hex_dict(6, 5)))
	_expect(failed, r.ok, "b end_turn optional adjacent move")
	snap = Snapshot.from_dict(server.get_snapshot(match_id, pid_b))
	_expect(failed, snap.you_moved_last_turn(), "b movedLastTurn")

	# UAV once — deterministic reveal of enemy hex to caller snapshot only.
	r = server.apply_action(match_id, pid_a, ActionIntent.uav())
	_expect(failed, r.ok, "uav")
	snap = Snapshot.from_dict(r.snapshot)
	_expect(failed, snap.uav_remaining() == 0, "uavRemaining 0")
	_expect(failed, Contract.same_hex(snap.enemy_visible_hex(), Contract.hex_dict(6, 5)), "uav visibleHex is b")
	r = server.apply_action(match_id, pid_a, ActionIntent.uav())
	_expect(failed, not r.ok, "second uav refused (phase or spent)")

	r = server.apply_action(match_id, pid_a, ActionIntent.end_turn(50))
	_expect(failed, r.ok, "a end after uav")
	r = server.apply_action(match_id, pid_b, ActionIntent.recon(1, 1))
	_expect(failed, r.ok, "b filler recon")
	r = server.apply_action(match_id, pid_b, ActionIntent.end_turn(50))
	_expect(failed, r.ok, "b filler end")

	# Attack kill via server — hex == enemy secret.
	r = server.apply_action(match_id, pid_a, ActionIntent.attack(6, 5))
	_expect(failed, r.ok, "attack kill ok")
	snap = Snapshot.from_dict(r.snapshot)
	last = snap.last_action()
	_expect(failed, last is Dictionary and last.get("hit") == true, "kill hit=true")
	_expect(failed, last is Dictionary and last.get("kill") == true, "kill flag")
	_expect(failed, snap.status() == Contract.STATUS_ENDED, "ended")
	_expect(failed, str(snap.winner()) == "a", "winner a")
	_expect(failed, snap.you_marks() == 1, "marks +1")
	_expect(failed, snap.marks_delta() == 1, "marksDelta +1 from server payout")
	_expect(failed, snap.end_reason() == Contract.END_KILL, "payout reason kill")
	_expect(failed, int(snap.payout().balance()) == 1, "payout.marks wallet")
	var replay_wallet: int = server.account_marks
	var again: Dictionary = server.get_snapshot(match_id, pid_a)
	_expect(failed, server.account_marks == replay_wallet, "replay snapshot does not grant again")
	_expect(failed, Snapshot.from_dict(again).marks_delta() == 1, "settled payout stays")
	r = server.apply_action(match_id, pid_a, ActionIntent.attack(6, 5))
	_expect(failed, not r.ok, "replay end refused")
	_expect(failed, server.account_marks == replay_wallet, "refused replay does not double grant")

	_live_shape_case(failed)
	_payout_shape_case(failed)
	_job_case(failed)

	# Recon odds: in-sector + forced roll.
	_recon_case(failed)

	# Turn cap draw.
	_draw_case(failed)

	if failed.is_empty():
		print("HEADLESS_LOOP_OK")
		return 0
	for line in failed:
		push_error(line)
		print("FAIL: ", line)
	return 1


func _live_shape_case(failed: PackedStringArray) -> void:
	var hit_body := {
		"ok": true,
		"snapshot": {"matchId": "m_x", "status": "ended", "lastAction": {"type": "attack", "hit": true, "kill": true}},
		"result": {"type": "attack", "hit": true, "kill": true},
	}
	var parsed: ActionResult = ActionResult.from_http(200, hit_body)
	_expect(failed, parsed.ok, "live action ok")
	_expect(failed, bool(parsed.result.get("kill", false)), "live result.kill")
	var reject_body := {"ok": false, "snapshot": {}, "result": {"type": "reject", "reason": "not_your_turn"}}
	parsed = ActionResult.from_http(400, reject_body)
	_expect(failed, not parsed.ok and parsed.error == "not_your_turn", "live reject")


func _payout_shape_case(failed: PackedStringArray) -> void:
	var live_body := {
		"ok": true,
		"snapshot": {
			"matchId": "m_pay",
			"status": "ended",
			"winner": "a",
			"you": {"seat": "a", "marks": 12},
			"payout": {"marks": 12, "marksDelta": 1, "reason": "kill"},
		},
		"result": {"type": "attack", "hit": true, "kill": true, "marks": 12, "marksDelta": 1, "reason": "kill"},
	}
	var parsed: ActionResult = ActionResult.from_http(200, live_body)
	var pay = parsed.payout()
	_expect(failed, pay.has_marks() and pay.balance() == 12, "result payout.marks")
	_expect(failed, pay.has_delta() and pay.delta() == 1, "result payout.marksDelta")
	_expect(failed, pay.reason == "kill", "result payout.reason")
	var overlay := MarksPayout.end_overlay(live_body["snapshot"], "a", false)
	_expect(failed, overlay.find("MARK CONFIRMED") >= 0, "end overlay win")
	_expect(failed, overlay.find("+1 MARK") >= 0, "end overlay delta")
	_expect(failed, overlay.find("★12") >= 0, "end overlay balance")
	var forfeit_snap := {
		"status": "ended",
		"winner": "a",
		"endReason": "forfeit",
		"you": {"seat": "a", "marks": 8},
		"payout": {"marks": 8, "marksDelta": 1, "reason": "forfeit"},
	}
	var foil := MarksPayout.end_overlay(forfeit_snap, "a", false)
	_expect(failed, foil.find("RIVAL FORFEIT") >= 0, "forfeit winner chrome")
	var you_forfeit := MarksPayout.end_overlay({"endReason": "disconnect", "winner": "b", "you": {"seat": "a", "marks": 7}}, "a", false)
	_expect(failed, you_forfeit.find("FORFEIT") >= 0, "disconnect loser chrome")
	var job_win := MarksPayout.end_overlay({"winner": "a", "payout": {"marks": 5, "marksDelta": 1, "reason": "job"}}, "a", true)
	_expect(failed, job_win.find("JOB COMPLETE") >= 0, "job win chrome")


func _job_case(failed: PackedStringArray) -> void:
	server.clear_all()
	server.reset_wallet(10)
	var created: Dictionary = server.create_match({"mode": "sp_job"})
	_expect(failed, str(created.get("mode", "")) == Contract.MODE_SP_JOB, "create_match mode sp_job")
	var mid := str(created["matchId"])
	var a: Dictionary = server.join(mid, created["joinTokens"]["a"])
	var b: Dictionary = server.join(mid, created["joinTokens"]["b"])
	var snap: Snapshot = Snapshot.from_dict(a["snapshot"])
	_expect(failed, snap.is_job(), "join snapshot mode job")
	_expect(failed, snap.you_marks() == 10, "job stub wallet on drop")
	server.apply_action(mid, a["playerId"], ActionIntent.select_hex(2, 2))
	server.apply_action(mid, b["playerId"], ActionIntent.select_hex(7, 5))
	server.apply_action(mid, a["playerId"], ActionIntent.start())
	var r: ActionResult = server.apply_action(mid, a["playerId"], ActionIntent.attack(7, 5))
	snap = Snapshot.from_dict(r.snapshot)
	_expect(failed, r.ok and snap.status() == Contract.STATUS_ENDED, "job kill ends")
	_expect(failed, snap.end_reason() == Contract.END_JOB, "job payout reason")
	_expect(failed, snap.marks_delta() == 1, "job marksDelta")
	_expect(failed, snap.you_marks() == 11, "job wallet from server")
	_expect(failed, server.account_marks == 11, "mock ledger not client +=")


func _recon_case(failed: PackedStringArray) -> void:
	server.clear_all()
	server.reset_wallet(0)
	server.test_recon_roll = 0.0
	var created: Dictionary = server.create_match()
	var mid := str(created["matchId"])
	var a: Dictionary = server.join(mid, created["joinTokens"]["a"])
	var b: Dictionary = server.join(mid, created["joinTokens"]["b"])
	server.apply_action(mid, a["playerId"], ActionIntent.select_hex(4, 3))
	server.apply_action(mid, b["playerId"], ActionIntent.select_hex(4, 4))
	server.apply_action(mid, a["playerId"], ActionIntent.start())
	var r: ActionResult = server.apply_action(mid, a["playerId"], ActionIntent.recon(4, 3))
	_expect(failed, r.ok, "recon apply")
	var snap: Snapshot = Snapshot.from_dict(r.snapshot)
	_expect(failed, bool(snap.last_action().get("spotted", false)), "recon spotted at roll 0")
	_expect(failed, Contract.same_hex(snap.enemy_visible_hex(), Contract.hex_dict(4, 4)), "recon intel")
	server.test_recon_roll = 1.0
	# Need a fresh action window — skip, already used action.
	# Second match for miss-in-sector.
	server.clear_all()
	server.test_recon_roll = 1.0
	created = server.create_match()
	mid = str(created["matchId"])
	a = server.join(mid, created["joinTokens"]["a"])
	b = server.join(mid, created["joinTokens"]["b"])
	server.apply_action(mid, a["playerId"], ActionIntent.select_hex(4, 3))
	server.apply_action(mid, b["playerId"], ActionIntent.select_hex(4, 4))
	server.apply_action(mid, a["playerId"], ActionIntent.start())
	r = server.apply_action(mid, a["playerId"], ActionIntent.recon(4, 3))
	snap = Snapshot.from_dict(r.snapshot)
	_expect(failed, snap.last_action().get("spotted", true) == false, "recon miss at roll 1")
	_expect(failed, snap.enemy_visible_hex() == null, "recon miss no intel")


func _draw_case(failed: PackedStringArray) -> void:
	server.clear_all()
	server.reset_wallet(4)
	var created: Dictionary = server.create_match()
	var mid := str(created["matchId"])
	var a: Dictionary = server.join(mid, created["joinTokens"]["a"])
	var b: Dictionary = server.join(mid, created["joinTokens"]["b"])
	server.apply_action(mid, a["playerId"], ActionIntent.select_hex(0, 0))
	server.apply_action(mid, b["playerId"], ActionIntent.select_hex(8, 6))
	server.apply_action(mid, a["playerId"], ActionIntent.start())
	var whose := "a"
	for _i in Contract.TURN_CAP:
		var pid: String = a["playerId"] if whose == "a" else b["playerId"]
		var r: ActionResult = server.apply_action(mid, pid, ActionIntent.recon(3, 3))
		_expect(failed, r.ok, "draw loop recon %s" % whose)
		r = server.apply_action(mid, pid, ActionIntent.end_turn(50))
		_expect(failed, r.ok, "draw loop end %s" % whose)
		whose = "b" if whose == "a" else "a"
	var snap: Snapshot = Snapshot.from_dict(server.get_snapshot(mid, a["playerId"]))
	_expect(failed, snap.status() == Contract.STATUS_ENDED, "cap ended")
	_expect(failed, str(snap.winner()) == Contract.WIN_DRAW, "cap draw")
	_expect(failed, snap.you_marks() == 4, "draw keeps wallet")
	_expect(failed, snap.marks_delta() == 0, "standoff marksDelta 0")
	_expect(failed, snap.end_reason() == Contract.END_STANDOFF, "standoff reason")
	_expect(failed, server.account_marks == 4, "standoff does not invent +1")


func _expect(failed: PackedStringArray, cond: bool, label: String) -> void:
	if not cond:
		failed.append(label)
