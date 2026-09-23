extends SceneTree
## Offline contract loop: drop both seats, miss, UAV reveal, kill, marks +1.
## Run: godot --headless --path . -s res://tools/headless_loop_test.gd

const Contract := preload("res://types/contract.gd")
const ActionIntent := preload("res://types/action_intent.gd")
const ActionResult := preload("res://types/action_result.gd")
const Snapshot := preload("res://types/snapshot.gd")
const MarksPayout := preload("res://types/marks_payout.gd")
const Shop := preload("res://types/shop.gd")
const HexMath := preload("res://scripts/hex_math.gd")
const Chrome := preload("res://scripts/chrome.gd")
const Journal := preload("res://types/journal.gd")
const JournalPlate := preload("res://scenes/lobby/journal_plate.gd")
const GearStrip := preload("res://scenes/lobby/gear_strip.gd")
const MockScript := preload("res://autoload/mock_match_server.gd")
const SessionScript := preload("res://autoload/client_session.gd")
const JuiceScript := preload("res://autoload/audio_juice.gd")

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
	_expect(failed, snap.you_marks() == Contract.MARKS_PVP_WIN, "marks +32 wallet")
	_expect(failed, snap.marks_delta() == Contract.MARKS_PVP_WIN, "marksDelta +32 from server payout")
	_expect(failed, snap.end_reason() == Contract.END_KILL, "payout reason kill")
	_expect(failed, int(snap.payout().balance()) == Contract.MARKS_PVP_WIN, "payout.marks wallet")
	var loser: Snapshot = Snapshot.from_dict(server.get_snapshot(match_id, pid_b))
	_expect(failed, loser.marks_delta() == Contract.MARKS_PVP_LOSS, "loser +4")
	_expect(failed, loser.end_reason() == Contract.END_LOSS, "loser reason")
	var replay_wallet: int = server.account_marks
	var again: Dictionary = server.get_snapshot(match_id, pid_a)
	_expect(failed, server.account_marks == replay_wallet, "replay snapshot does not grant again")
	_expect(failed, Snapshot.from_dict(again).marks_delta() == Contract.MARKS_PVP_WIN, "settled payout stays")
	r = server.apply_action(match_id, pid_a, ActionIntent.attack(6, 5))
	_expect(failed, not r.ok, "replay end refused")
	_expect(failed, server.account_marks == replay_wallet, "refused replay does not double grant")

	_decoy_case(failed)
	_smoke_case(failed)
	_lobby_case(failed)
	_invite_share_case(failed)
	_paste_clipboard_case(failed)
	_queue_case(failed)
	_rematch_case(failed)
	_a4_gaps_case(failed)
	_end_summary_case(failed)
	_live_shape_case(failed)
	_payout_shape_case(failed)
	_job_case(failed)
	_a2_reconnect_case(failed)
	_shop_case(failed)
	_live_shop_shape_case(failed)
	_shop_sink2_case(failed)
	_shop_sink3_case(failed)
	_gun_chrome_case(failed)
	_part_sink_case(failed)
	_part_t2_case(failed)
	_part_peg_case(failed)
	_optic_joystick_case(failed)
	_chrome_reconfirm_case(failed)
	_match_board_chrome_case(failed)
	_high_ground_case(failed)
	_brush_cover_case(failed)
	_audio_juice_case(failed)
	_join_spine_case(failed)
	_equip_chrome_case(failed)
	_player_persist_case(failed)
	_first_hunt_coach_case(failed)
	_terrain_coach_case(failed)
	_gear_strip_case(failed)
	_exposure_floor_case(failed)
	_practice_case(failed)
	_journal_case(failed)

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


func _a2_reconnect_case(failed: PackedStringArray) -> void:
	## A2: polluted client cache (invented terrain + I-hit) is replaced by GET snapshot.
	server.clear_all()
	server.reset_wallet(0)
	var created: Dictionary = server.create_match()
	var mid := str(created["matchId"])
	var a: Dictionary = server.join(mid, created["joinTokens"]["a"])
	var b: Dictionary = server.join(mid, created["joinTokens"]["b"])
	var pid_a := str(a["playerId"])
	server.apply_action(mid, pid_a, ActionIntent.select_hex(2, 2))
	server.apply_action(mid, b["playerId"], ActionIntent.select_hex(7, 5))
	server.apply_action(mid, pid_a, ActionIntent.start())
	var noted: Dictionary = server.get_snapshot(mid, pid_a)
	var session = SessionScript.new()
	session.apply_snapshot(noted)
	_expect(failed, session.terrain_keys().has("2,2"), "A2 noted select terrain 2,2")
	_expect(failed, session.last_server_hit() == null, "A2 no invented hit after drop")
	var dirty: Dictionary = session.last_snapshot.duplicate(true)
	var rows: Array = dirty.get("terrain", [])
	if not (rows is Array):
		rows = []
	rows = rows.duplicate()
	rows.append({"q": 8, "r": 6, "type": "hard"})
	dirty["terrain"] = rows
	dirty["lastAction"] = {"type": "attack", "hit": true, "kill": true}
	dirty["status"] = "ended"
	dirty["turnIndex"] = 99
	var you_dirty: Dictionary = dirty.get("you", {})
	if not (you_dirty is Dictionary):
		you_dirty = {}
	you_dirty = you_dirty.duplicate(true)
	you_dirty["hex"] = {"q": 0, "r": 0}
	you_dirty["exposurePct"] = 99
	you_dirty["marks"] = 999
	dirty["you"] = you_dirty
	session.last_snapshot = dirty
	session.bind_marks(999)
	_expect(failed, session.terrain_keys().has("8,6"), "A2 dirty invented terrain present")
	_expect(failed, session.last_server_hit() == true, "A2 dirty invented hit")
	_expect(failed, session.marks == 999, "A2 dirty invented wallet")
	var fresh: Dictionary = server.get_snapshot(mid, pid_a)
	session.apply_snapshot(fresh)
	var snap: Snapshot = session.typed_snapshot()
	_expect(failed, snap.match_id() == mid, "A2 reconnect matchId")
	_expect(failed, snap.status() == str(noted.get("status", "")), "A2 status from server")
	_expect(failed, str(snap.whose_turn()) == str(noted.get("whoseTurn", "")), "A2 whoseTurn from server")
	_expect(failed, snap.turn_index() == int(noted.get("turnIndex", 0)), "A2 turnIndex from server")
	_expect(failed, not session.terrain_keys().has("8,6"), "A2 invented terrain wiped")
	_expect(failed, session.terrain_keys().has("2,2"), "A2 select terrain kept from server")
	_expect(failed, session.last_server_hit() != true, "A2 invented I-hit wiped")
	_expect(failed, snap.you_exposure() == 50, "A2 exposure 50 from server")
	_expect(failed, Contract.same_hex(snap.you_hex(), Contract.hex_dict(2, 2)), "A2 you.hex from server")
	var noted_you: Variant = noted.get("you", {})
	var noted_marks := 0
	if noted_you is Dictionary:
		noted_marks = int(noted_you.get("marks", 0))
	_expect(failed, snap.you_marks() == noted_marks, "A2 you.marks from server")
	_expect(failed, session.marks == snap.you_marks(), "A2 wallet bind replaced invented 999")
	session.free()


func _smoke_case(failed: PackedStringArray) -> void:
	## Once/match puff. Snapshot flags only. No Attack +0.10. Fail closed if unnamed.
	var intent := ActionIntent.smoke()
	_expect(failed, str(intent.get("type", "")) == Contract.ACT_SMOKE, "S0 type smoke")
	_expect(failed, not intent.has("hex"), "S0 intent has no hex")
	_expect(failed, not intent.has("highGround"), "S0 intent has no highGround")
	_expect(failed, not intent.has("hitChance"), "S0 intent has no hitChance")
	_expect(failed, str(ActionIntent.ability().get("type", "")) == Contract.ACT_UAV, "S0 UAV ability path untouched")
	var bare: Snapshot = Snapshot.from_dict({"status": Contract.STATUS_ACTIVE, "you": {"seat": "a", "hex": {"q": 1, "r": 1}}})
	_expect(failed, not bare.smoke_available(), "S0 missing smokeAvailable is not a charge")
	_expect(failed, not bare.smoke_active(), "S0 missing smokeActive does not tint")
	_expect(failed, not bare.smoke_fields_present(), "S0 missing fields fail closed")
	var snake: Snapshot = Snapshot.from_dict({"you": {"smoke_available": true, "smoke_active": 1}})
	_expect(failed, snake.smoke_available() and snake.smoke_active(), "S0 snake_case + turns remaining")
	var camel: Snapshot = Snapshot.from_dict({"you": {"SmokeAvailable": false, "SmokeActive": "0"}})
	_expect(failed, camel.smoke_fields_present() and not camel.smoke_available(), "S0 camelCase false stays spent")
	_expect(failed, not camel.smoke_active(), "S0 SmokeActive 0 is not live")
	var ended: Snapshot = Snapshot.from_dict({
		"status": Contract.STATUS_ENDED,
		"you": {"smokeAvailable": false, "smokeActive": true},
	})
	_expect(failed, not ended.smoke_active(), "S0 ended clears the tint")
	var chip: Button = Chrome.smoke_chip()
	Chrome.paint_smoke_chip(chip, true)
	_expect(failed, bool(chip.get_meta("smoke_lit")), "S0 lit chip when available")
	_expect(failed, chip.text == Contract.SMOKE_LABEL, "S0 chip reads SMOKE")
	_expect(failed, chip.tooltip_text == Contract.SMOKE_COPY, "S0 available tooltip unchanged")
	var lit_box := chip.get_theme_stylebox("normal") as StyleBoxFlat
	_expect(failed, lit_box != null and lit_box.bg_color.is_equal_approx(Chrome.ABILITY_PURPLE), "S0 available chip stays hot purple")
	var lit_puff: Color = chip.get_theme_color("icon_normal_color")
	_expect(failed, lit_puff.is_equal_approx(Color.WHITE), "S0 available puff stays white")
	Chrome.paint_smoke_chip(chip, false)
	_expect(failed, not bool(chip.get_meta("smoke_lit")), "S0 muted chip when spent")
	_expect(failed, chip.text == Contract.SMOKE_LABEL, "S0 spent chip label unchanged")
	_expect(failed, chip.tooltip_text == Contract.SMOKE_SPENT_COPY, "S0 spent tooltip unchanged")
	var spent_box := chip.get_theme_stylebox("disabled") as StyleBoxFlat
	_expect(failed, spent_box != null and spent_box.bg_color.r > spent_box.bg_color.b + 0.04, "S0 spent chip is grey wood, not purple")
	_expect(failed, spent_box.bg_color.is_equal_approx(Chrome.SMOKE_SPENT), "S0 spent plate is the muted wood")
	var spent_puff: Color = chip.get_theme_color("icon_disabled_color")
	_expect(failed, spent_puff.r > spent_puff.b and not spent_puff.is_equal_approx(Color.WHITE), "S0 spent puff is grey, not purple or white")
	chip.free()
	var toast := Chrome.describe_last_action({"type": Contract.ACT_SMOKE, "active": true})
	_expect(failed, toast == Contract.SMOKE_TOAST, "S0 toast copy")
	_expect(failed, toast.find("IN COVER") < 0, "S0 toast has no cover badge")
	_expect(failed, toast.find("+0.10") < 0 and toast.find("+10%") < 0, "S0 toast has no attack bonus")

	server.clear_all()
	server.reset_wallet(Contract.MOCK_WALLET_STUB)
	var created: Dictionary = server.create_match()
	var mid := str(created["matchId"])
	var a: Dictionary = server.join(mid, created["joinTokens"]["a"])
	var b: Dictionary = server.join(mid, created["joinTokens"]["b"])
	var pid_a := str(a["playerId"])
	var pid_b := str(b["playerId"])
	var open_a: Dictionary = server.find_hex_of_type(mid, Contract.TYPE_OPEN)
	var open_b: Dictionary = server.find_hex_of_type(mid, Contract.TYPE_OPEN, open_a)
	_expect(failed, not open_a.is_empty() and not open_b.is_empty(), "S1 two OPEN hexes")
	var parked: ActionResult = server.apply_action(mid, pid_a, ActionIntent.smoke())
	_expect(failed, not parked.ok and str(parked.result.get("reason", "")) == "match is not active", "S1 inactive smoke refused")
	server.apply_action(mid, pid_a, ActionIntent.select_hex(int(open_a["q"]), int(open_a["r"])))
	server.apply_action(mid, pid_b, ActionIntent.select_hex(int(open_b["q"]), int(open_b["r"])))
	server.apply_action(mid, pid_a, ActionIntent.start())
	var before: int = server.account_marks
	var snap: Snapshot = Snapshot.from_dict(server.get_snapshot(mid, pid_a))
	_expect(failed, snap.smoke_available(), "S1 smokeAvailable true at start")
	_expect(failed, not snap.smoke_active(), "S1 smokeActive false before use")
	_expect(failed, not snap.you_high_ground_active(), "S1 OPEN is not HIGH GROUND")
	_expect(failed, int(snap.you_exposure_floor()) == 50, "S5 doll floor 50 before smoke")
	var early: ActionResult = server.apply_action(mid, pid_b, ActionIntent.smoke())
	_expect(failed, not early.ok and str(early.result.get("reason", "")) == "not your turn", "S1 rival smoke refused off-turn")

	var smoked := ActionIntent.smoke()
	smoked["hex"] = Contract.hex_dict(0, 0)
	var r: ActionResult = server.apply_action(mid, pid_a, smoked)
	_expect(failed, r.ok, "S1 smoke ok")
	snap = Snapshot.from_dict(r.snapshot)
	var cast: Dictionary = snap.last_action()
	_expect(failed, cast.get("type") == Contract.ACT_SMOKE, "S1 result type smoke")
	_expect(failed, cast.size() == 1, "S1 result is exactly { type: smoke }")
	_expect(failed, str(snap.phase()) == Contract.PHASE_END_TURN, "S1 consumes the action")
	_expect(failed, not snap.smoke_available(), "S1 smokeAvailable false after use")
	_expect(failed, snap.smoke_active(), "S1 smokeActive for the enemy turn")
	_expect(failed, not snap.you_high_ground_active(), "S1 smoke does not light HIGH GROUND")
	_expect(failed, snap.you().has("highGroundActive") and snap.you().get("highGroundActive") == false, "S1 HG flag stays false")
	_expect(failed, snap.uav_remaining() == 1, "S4 UAV charge untouched")
	_expect(failed, snap.decoy_available(), "S4 decoy charge untouched")
	_expect(failed, snap.you_marks() == before, "S4 no Marks spend")
	_expect(failed, server.account_marks == before, "S4 ledger unchanged")
	_expect(failed, int(snap.you_exposure()) == 50, "S5 exposurePct stays 50")
	_expect(failed, int(snap.you_exposure_floor()) == 50, "S5 doll floor stays 50")
	_expect(failed, not cast.has("hitChance"), "S3 result has no hitChance")
	_expect(failed, not cast.has("highGroundApplied"), "S3 result has no highGroundApplied")
	var rival: Snapshot = Snapshot.from_dict(server.get_snapshot(mid, pid_b))
	_expect(failed, rival.enemy_smoke_active(), "S1 enemy.smokeActive")
	_expect(failed, rival.smoke_available(), "S4 rival smoke charge untouched")
	_expect(failed, rival.enemy_visible_hex() == null, "S1 smoke does not reveal a hex")
	r = server.apply_action(mid, pid_a, ActionIntent.smoke())
	_expect(failed, not r.ok and str(r.result.get("reason", "")) == "awaiting end_turn", "S1 second smoke waits for end_turn")
	r = server.apply_action(mid, pid_a, ActionIntent.end_turn(50))
	_expect(failed, r.ok, "S2 planting end_turn")
	snap = Snapshot.from_dict(server.get_snapshot(mid, pid_a))
	_expect(failed, snap.smoke_active(), "S2 planting end keeps the puff")
	_expect(failed, not snap.smoke_available(), "S2 still spent")
	var miss := _smoke_empty_hex(open_a, open_b)
	r = server.apply_action(mid, pid_b, ActionIntent.attack(int(miss["q"]), int(miss["r"])))
	_expect(failed, r.ok, "S2 enemy action while smoked")
	r = server.apply_action(mid, pid_b, ActionIntent.end_turn(50))
	_expect(failed, r.ok, "S2 enemy end_turn")
	snap = Snapshot.from_dict(server.get_snapshot(mid, pid_a))
	_expect(failed, snap.smoke_active(), "S2 still live after the enemy turn")
	_expect(failed, str(snap.whose_turn()) == Contract.SEAT_A, "S2 caster's next window")
	_expect(failed, str(snap.phase()) == Contract.PHASE_ACTION, "S2 caster can act")
	r = server.apply_action(mid, pid_a, ActionIntent.attack(int(miss["q"]), int(miss["r"])))
	snap = Snapshot.from_dict(r.snapshot)
	_expect(failed, snap.smoke_active(), "S2 still live on the caster's next action")
	r = server.apply_action(mid, pid_a, ActionIntent.end_turn(50))
	snap = Snapshot.from_dict(server.get_snapshot(mid, pid_a))
	_expect(failed, not snap.smoke_active(), "S2 cleared on the caster's next end_turn")
	_expect(failed, not snap.smoke_available(), "S2 charge stays spent")
	_expect(failed, int(snap.you_exposure_floor()) == 50, "S5 floor still 50 after expiry")
	r = server.apply_action(mid, pid_b, ActionIntent.attack(int(miss["q"]), int(miss["r"])))
	r = server.apply_action(mid, pid_b, ActionIntent.end_turn(50))
	r = server.apply_action(mid, pid_a, ActionIntent.smoke())
	_expect(failed, not r.ok and str(r.result.get("reason", "")) == "smoke already used", "S1 smoke already used")

	_smoke_occupy_case(failed, "S3")
	_smoke_hard_case(failed)

	var lone: Snapshot = Snapshot.from_dict({
		"status": Contract.STATUS_ACTIVE,
		"you": {"smokeActive": true},
		"enemy": {},
	})
	_expect(failed, lone.smoke_active() and not lone.enemy_smoke_active(), "S1 you.smokeActive is not the enemy flag")
	var foe: Snapshot = Snapshot.from_dict({
		"status": Contract.STATUS_ACTIVE,
		"enemy": {"smoke_active": true},
	})
	_expect(failed, foe.enemy_smoke_active() and not foe.smoke_active(), "S1 enemy flag does not toast you")
	var Board := load("res://scenes/match/hex_board.gd")
	var board = Board.new()
	board.apply_snapshot(Snapshot.from_dict({
		"status": Contract.STATUS_ACTIVE,
		"you": {"hex": {"q": 2, "r": 2}, "smokeActive": true, "smokeAvailable": false, "highGroundActive": false},
		"enemy": {"smokeActive": true},
	}))
	_expect(failed, board.smoke_tint_active(), "S2 soft tint while you.smokeActive")
	_expect(failed, not board.enemy_smoke_tint_active(), "S1 enemy smoke does not invent a hex")
	board.apply_snapshot(Snapshot.from_dict({
		"status": Contract.STATUS_ACTIVE,
		"you": {"hex": {"q": 2, "r": 2}, "highGroundActive": true},
		"enemy": {"smokeActive": true, "visibleHex": {"q": 4, "r": 4}},
	}))
	_expect(failed, not board.smoke_tint_active(), "S2 missing you.smokeActive does not tint")
	_expect(failed, board.enemy_smoke_tint_active(), "S1 known visibleHex can take the rival wash")
	board.apply_snapshot(Snapshot.from_dict({
		"status": Contract.STATUS_ENDED,
		"you": {"hex": {"q": 2, "r": 2}, "smokeActive": true},
		"enemy": {"smokeActive": true, "visibleHex": {"q": 4, "r": 4}},
	}))
	_expect(failed, not board.smoke_tint_active() and not board.enemy_smoke_tint_active(), "S2 ended clears both tints")
	board.free()
	_smoke_l5_case(failed)


func _smoke_l5_case(failed: PackedStringArray) -> void:
	## U1–U5. Level and the charge are server fields. xp never unlocks the puff.
	var below: Snapshot = Snapshot.from_dict({
		"status": Contract.STATUS_ACTIVE,
		"you": {"operativeLevel": 4, "smokeAvailable": true, "xp": 9999},
	})
	_expect(failed, below.operative_level() == 4, "U3 client reads operativeLevel")
	_expect(failed, below.smoke_chrome() == Contract.SMOKE_CHROME_LOCKED, "U1 level 4 stays locked with a charge")
	_expect(failed, below.smoke_lock_toast() == Contract.SMOKE_LOCKED_TOAST, "U2 default lock line")
	var at_level: Snapshot = Snapshot.from_dict({
		"status": Contract.STATUS_ACTIVE,
		"you": {"operativeLevel": 5, "smokeAvailable": true},
	})
	_expect(failed, at_level.smoke_chrome() == Contract.SMOKE_CHROME_AVAILABLE, "U1 exact L5 plus smokeAvailable unlocks")
	var alias: Snapshot = Snapshot.from_dict({
		"status": Contract.STATUS_ACTIVE,
		"you": {"operative_level": "5", "smoke_available": true, "xp": 9999},
	})
	_expect(failed, not alias.operative_level_present(), "U1 snake_case operative_level is not the field")
	_expect(failed, alias.smoke_chrome() == Contract.SMOKE_CHROME_ABSENT, "U1 aliases do not unlock")
	var live_l1: Snapshot = Snapshot.from_dict({
		"status": Contract.STATUS_READY,
		"you": {"operativeLevel": 1, "smokeAvailable": false, "smokeActive": false, "xp": 0, "marks": 0},
	})
	_expect(failed, live_l1.smoke_chrome() == Contract.SMOKE_CHROME_LOCKED, "U1 live L1 shape is locked")
	_expect(failed, live_l1.smoke_lock_toast() == Contract.SMOKE_LOCKED_TOAST, "U2 lock line is Reach operative L5")
	var spent: Snapshot = Snapshot.from_dict({
		"status": Contract.STATUS_ACTIVE,
		"you": {"operativeLevel": 6, "smokeAvailable": false},
	})
	_expect(failed, spent.smoke_chrome() == Contract.SMOKE_CHROME_SPENT, "U4 spent stays spent once unlocked")
	var missing_level: Snapshot = Snapshot.from_dict({
		"status": Contract.STATUS_ACTIVE,
		"you": {"smokeAvailable": true, "xp": 5000},
	})
	_expect(failed, not missing_level.operative_level_present(), "U3 xp is not a level")
	_expect(failed, missing_level.smoke_chrome() == Contract.SMOKE_CHROME_LOCKED, "U1 missing operativeLevel fail-closes")
	var missing_both: Snapshot = Snapshot.from_dict({
		"status": Contract.STATUS_ACTIVE,
		"you": {"xp": 9000, "exposureFloor": 20},
	})
	_expect(failed, missing_both.smoke_chrome() == Contract.SMOKE_CHROME_ABSENT, "U1 missing charge and level stay absent")
	var enemy_level: Snapshot = Snapshot.from_dict({
		"you": {"smokeAvailable": true},
		"enemy": {"operativeLevel": 9},
	})
	_expect(failed, enemy_level.smoke_chrome() == Contract.SMOKE_CHROME_LOCKED, "U3 enemy level does not unlock you")
	var ignored: Snapshot = Snapshot.from_dict({
		"you": {"operativeLevel": 8, "smokeAvailable": false, "smokeLockReason": "Puff waits until L5.", "smokeLocked": true},
	})
	_expect(failed, ignored.smoke_chrome() == Contract.SMOKE_CHROME_SPENT, "U4 a lock-reason alias does not replace spent")
	_expect(failed, ignored.smoke_lock_toast() == Contract.SMOKE_LOCKED_TOAST, "U2 toast stays the contract line")
	_expect(failed, Contract.MARKS_PRACTICE == 0, "U3 practice earn is Δ0")
	var practice_low: Snapshot = Snapshot.from_dict({
		"mode": Contract.MODE_PRACTICE,
		"you": {"operativeLevel": 1, "xp": 4000, "smokeAvailable": true},
	})
	_expect(failed, practice_low.is_practice() and practice_low.smoke_chrome() == Contract.SMOKE_CHROME_LOCKED, "U3 practice XP does not unlock")
	var practice_l5: Snapshot = Snapshot.from_dict({
		"mode": Contract.MODE_PRACTICE,
		"you": {"operativeLevel": 5, "smokeAvailable": true},
	})
	_expect(failed, practice_l5.smoke_chrome() == Contract.SMOKE_CHROME_AVAILABLE, "U3 an L5 operative keeps SMOKE in practice")
	var locked_chip: Button = Chrome.smoke_chip()
	Chrome.paint_smoke_chip(locked_chip, false, true)
	_expect(failed, bool(locked_chip.get_meta("smoke_locked")) and not bool(locked_chip.get_meta("smoke_lit")), "U2 locked chip is visible wood, not lit")
	_expect(failed, locked_chip.text == Contract.SMOKE_LABEL, "U2 chip still reads SMOKE")
	_expect(failed, locked_chip.tooltip_text == Contract.SMOKE_LOCKED_TOAST, "U2 locked tooltip")
	var locked_box := locked_chip.get_theme_stylebox("normal") as StyleBoxFlat
	_expect(failed, locked_box != null and locked_box.bg_color.is_equal_approx(Chrome.SMOKE_SPENT), "U2 locked plate is the spent wood")
	Chrome.paint_smoke_chip(locked_chip, false, false)
	var spent_box := locked_chip.get_theme_stylebox("disabled") as StyleBoxFlat
	_expect(failed, spent_box != null and locked_box.bg_color.is_equal_approx(spent_box.bg_color), "U4 spent dialect matches locked wood")
	_expect(failed, locked_chip.tooltip_text == Contract.SMOKE_SPENT_COPY, "U4 spent tooltip unchanged")
	locked_chip.free()
	var intent := ActionIntent.smoke()
	_expect(failed, not intent.has("marks") and not intent.has("price") and not intent.has("iap"), "U5 intent has no Marks or IAP")
	for entry in Contract.shop_catalog_items():
		_expect(failed, str(entry.get("id", "")).to_lower().find("smoke") < 0, "U5 catalog has no smoke SKU")

	server.clear_all()
	server.reset_wallet(11)
	server.operative_level = 3
	var created: Dictionary = server.create_match({"mode": Contract.MODE_PRACTICE})
	var mid := str(created.get("matchId", ""))
	var join_a: Dictionary = server.join(mid, Contract.create_join_token(created))
	var pid := str(join_a.get("playerId", ""))
	var snap: Snapshot = Snapshot.from_dict(join_a.get("snapshot", {}))
	_expect(failed, snap.is_practice() and snap.operative_level() == 3, "U3 practice publishes the server level")
	_expect(failed, snap.you().has("operativeLevel") and snap.you().has("smokeAvailable"), "U1 mock uses the exact keys")
	_expect(failed, not snap.you().has("smokeLocked") and not snap.you().has("smokeLockReason"), "U1 mock does not invent a lock field")
	_expect(failed, snap.smoke_chrome() == Contract.SMOKE_CHROME_LOCKED, "U1 practice below L5 is locked")
	var before := int(server.account_marks)
	server.apply_action(mid, pid, ActionIntent.select_hex(2, 2))
	server.apply_action(mid, pid, ActionIntent.start())
	var refused: ActionResult = server.apply_action(mid, pid, ActionIntent.smoke())
	_expect(failed, not refused.ok and str(refused.result.get("reason", "")) == "operative level", "U1 server refuses below L5")
	snap = Snapshot.from_dict(server.get_snapshot(mid, pid))
	_expect(failed, snap.operative_level() == 3, "U3 practice did not level")
	_expect(failed, server.account_marks == before and snap.you_marks() == before, "U5 lock does not spend Marks")
	server.operative_level = Contract.SMOKE_UNLOCK_LEVEL
	snap = Snapshot.from_dict(server.get_snapshot(mid, pid))
	_expect(failed, snap.smoke_available() and snap.smoke_chrome() == Contract.SMOKE_CHROME_AVAILABLE, "U5 the lock did not spend the puff")
	var cast: ActionResult = server.apply_action(mid, pid, ActionIntent.smoke())
	var cast_snap: Snapshot = Snapshot.from_dict(cast.snapshot)
	_expect(failed, cast.ok and cast_snap.you_marks() == before, "U4 L5 smoke still posts with no Marks")
	var again: ActionResult = server.apply_action(mid, pid, ActionIntent.smoke())
	_expect(failed, not again.ok, "U5 no second smoke charge")
	server.test_omit_operative_level = true
	var omitted: Snapshot = Snapshot.from_dict(server.get_snapshot(mid, pid))
	_expect(failed, not omitted.operative_level_present(), "omit drops operativeLevel")
	_expect(failed, omitted.smoke_chrome() != Contract.SMOKE_CHROME_AVAILABLE, "missing level is not available")
	server.clear_all()
	server.operative_level = 4
	var pvp: Dictionary = server.create_match()
	var pvp_id := str(pvp.get("matchId", ""))
	var seated: Dictionary = server.join(pvp_id, pvp["joinTokens"]["a"])
	server.join(pvp_id, pvp["joinTokens"]["b"])
	var body := ActionIntent.smoke()
	body["operativeLevel"] = 9
	body["xp"] = 9999
	body["marks"] = 50
	var injected: ActionResult = server.apply_action(pvp_id, str(seated.get("playerId", "")), body)
	_expect(failed, not injected.ok, "U5 client fields cannot buy smoke")
	var after: Snapshot = Snapshot.from_dict(server.get_snapshot(pvp_id, str(seated.get("playerId", ""))))
	_expect(failed, after.operative_level() == 4, "U3 action cannot write operativeLevel")
	_expect(failed, not after.you().has("xp"), "U3 client does not invent xp")
	server.clear_all()


func _smoke_empty_hex(a: Dictionary, b: Dictionary) -> Dictionary:
	for q in Contract.BOARD_Q:
		for r in Contract.BOARD_R:
			var cand := Contract.hex_dict(q, r)
			if Contract.same_hex(cand, a) or Contract.same_hex(cand, b):
				continue
			return cand
	return Contract.hex_dict(0, 0)


func _smoke_occupy_case(failed: PackedStringArray, tag: String) -> void:
	## OPEN smoker occupies the rival. Mock kills; chance stays 0.90 with no HG.
	server.clear_all()
	server.reset_wallet(0)
	var created: Dictionary = server.create_match()
	var mid := str(created["matchId"])
	var a: Dictionary = server.join(mid, created["joinTokens"]["a"])
	var b: Dictionary = server.join(mid, created["joinTokens"]["b"])
	var pid_a := str(a["playerId"])
	var pid_b := str(b["playerId"])
	var open_a: Dictionary = server.find_hex_of_type(mid, Contract.TYPE_OPEN)
	var open_b: Dictionary = server.find_hex_of_type(mid, Contract.TYPE_OPEN, open_a)
	server.apply_action(mid, pid_a, ActionIntent.select_hex(int(open_a["q"]), int(open_a["r"])))
	server.apply_action(mid, pid_b, ActionIntent.select_hex(int(open_b["q"]), int(open_b["r"])))
	server.apply_action(mid, pid_a, ActionIntent.start())
	var r: ActionResult = server.apply_action(mid, pid_a, ActionIntent.smoke())
	r = server.apply_action(mid, pid_a, ActionIntent.end_turn(50))
	var miss := _smoke_empty_hex(open_a, open_b)
	r = server.apply_action(mid, pid_b, ActionIntent.attack(int(miss["q"]), int(miss["r"])))
	r = server.apply_action(mid, pid_b, ActionIntent.end_turn(50))
	var live: Snapshot = Snapshot.from_dict(server.get_snapshot(mid, pid_a))
	_expect(failed, live.smoke_active(), tag + " puff still live for the occupy")
	_expect(failed, not live.you_high_ground_active(), tag + " OPEN smoker is not HIGH GROUND")
	r = server.apply_action(mid, pid_a, ActionIntent.attack(int(open_b["q"]), int(open_b["r"])))
	var last: Dictionary = r.snapshot.get("lastAction", {})
	_expect(failed, r.ok and bool(last.get("hit", false)), tag + " occupy hits")
	_expect(failed, is_equal_approx(float(last.get("hitChance", -1.0)), Contract.BASE_HIT_CHANCE), tag + " no Attack +0.10 from smoke")
	_expect(failed, last.get("highGroundApplied") == false, tag + " highGroundApplied false")
	_expect(failed, last.get("coverApplied") == false, tag + " coverApplied false on OPEN")
	_expect(failed, Contract.HIGH_GROUND_HIT == 0.10, tag + " HIGH GROUND table unchanged")


func _smoke_hard_case(failed: PackedStringArray) -> void:
	server.clear_all()
	server.reset_wallet(0)
	var created: Dictionary = server.create_match()
	var mid := str(created["matchId"])
	var a: Dictionary = server.join(mid, created["joinTokens"]["a"])
	var b: Dictionary = server.join(mid, created["joinTokens"]["b"])
	var pid_a := str(a["playerId"])
	var pid_b := str(b["playerId"])
	var open_b: Dictionary = server.find_hex_of_type(mid, Contract.TYPE_OPEN)
	var hard: Dictionary = server.find_hex_of_type(mid, Contract.TYPE_HARD, open_b)
	_expect(failed, not hard.is_empty(), "S3 board has HARD")
	server.apply_action(mid, pid_a, ActionIntent.select_hex(int(hard["q"]), int(hard["r"])))
	server.apply_action(mid, pid_b, ActionIntent.select_hex(int(open_b["q"]), int(open_b["r"])))
	server.apply_action(mid, pid_a, ActionIntent.start())
	_expect(failed, Snapshot.from_dict(server.get_snapshot(mid, pid_a)).you_high_ground_active(), "S3 real HARD lights HG before smoke")
	var shot: ActionResult = server.apply_action(mid, pid_a, ActionIntent.attack(int(open_b["q"]), int(open_b["r"])))
	var real: Dictionary = shot.snapshot.get("lastAction", {})
	_expect(failed, is_equal_approx(float(real.get("hitChance", -1.0)), 1.0), "S3 real HARD occupy hitChance 1")
	_expect(failed, real.get("highGroundApplied") == true, "S3 real HARD sets highGroundApplied")
	var ended: Snapshot = Snapshot.from_dict(shot.snapshot)
	_expect(failed, not ended.smoke_active(), "S3 real HARD shot did not invent smoke")

	server.clear_all()
	created = server.create_match()
	mid = str(created["matchId"])
	a = server.join(mid, created["joinTokens"]["a"])
	b = server.join(mid, created["joinTokens"]["b"])
	pid_a = str(a["playerId"])
	pid_b = str(b["playerId"])
	open_b = server.find_hex_of_type(mid, Contract.TYPE_OPEN)
	hard = server.find_hex_of_type(mid, Contract.TYPE_HARD, open_b)
	server.apply_action(mid, pid_a, ActionIntent.select_hex(int(hard["q"]), int(hard["r"])))
	server.apply_action(mid, pid_b, ActionIntent.select_hex(int(open_b["q"]), int(open_b["r"])))
	server.apply_action(mid, pid_a, ActionIntent.start())
	var r: ActionResult = server.apply_action(mid, pid_a, ActionIntent.smoke())
	var snap: Snapshot = Snapshot.from_dict(r.snapshot)
	_expect(failed, snap.you_high_ground_active(), "S3 real HARD stays HG under smoke")
	_expect(failed, snap.smoke_active(), "S2 smoke still active on HARD")
	_expect(failed, snap.uav_remaining() == 1 and snap.decoy_available(), "S4 UAV and Decoy still charged on HARD")
	_expect(failed, int(snap.you_exposure_floor()) == 50, "S5 floor untouched on HARD smoke")
	r = server.apply_action(mid, pid_a, ActionIntent.end_turn(50))
	var miss := _smoke_empty_hex(hard, open_b)
	r = server.apply_action(mid, pid_b, ActionIntent.recon(int(miss["q"]), int(miss["r"])))
	r = server.apply_action(mid, pid_b, ActionIntent.end_turn(50))
	snap = Snapshot.from_dict(server.get_snapshot(mid, pid_a))
	_expect(failed, snap.smoke_active(), "S2 HARD puff survives the enemy turn")
	_expect(failed, snap.you_high_ground_active(), "S3 HG still the real HARD hex")
	_expect(failed, snap.decoy_available(), "S4 decoy still available after the enemy turn")
	r = server.apply_action(mid, pid_a, ActionIntent.attack(int(miss["q"]), int(miss["r"])))
	r = server.apply_action(mid, pid_a, ActionIntent.end_turn(50))
	snap = Snapshot.from_dict(server.get_snapshot(mid, pid_a))
	_expect(failed, not snap.smoke_active(), "S2 HARD puff clears on the next own end_turn")
	_expect(failed, not snap.smoke_available(), "S1 HARD charge stays spent")
	r = server.apply_action(mid, pid_b, ActionIntent.attack(int(miss["q"]), int(miss["r"])))
	r = server.apply_action(mid, pid_b, ActionIntent.end_turn(50))
	r = server.apply_action(mid, pid_a, ActionIntent.smoke())
	_expect(failed, not r.ok and str(r.result.get("reason", "")) == "smoke already used", "S1 HARD smoke already used")


func _decoy_pick(aq: int, ar: int, bq: int, br: int) -> Vector2i:
	## Mirror LIVE pickDecoyHex / HexMath.DECOY_DIRS.
	var occupied := [Vector2i(aq, ar), Vector2i(bq, br)]
	for dir in HexMath.DECOY_DIRS:
		var cand := Vector2i(aq + dir.x, ar + dir.y)
		if not Contract.on_board(cand.x, cand.y):
			continue
		if cand in occupied:
			continue
		return cand
	return Vector2i(-1, -1)


func _decoy_case(failed: PackedStringArray) -> void:
	## D1–D5: once + full turn, adjacent empty, attack miss+clear, expiry, no economy/buff.
	server.clear_all()
	server.reset_wallet(Contract.MOCK_WALLET_STUB)
	var created: Dictionary = server.create_match()
	var mid := str(created["matchId"])
	var a: Dictionary = server.join(mid, created["joinTokens"]["a"])
	var b: Dictionary = server.join(mid, created["joinTokens"]["b"])
	var pid_a := str(a["playerId"])
	var pid_b := str(b["playerId"])
	server.apply_action(mid, pid_a, ActionIntent.select_hex(2, 2))
	server.apply_action(mid, pid_b, ActionIntent.select_hex(7, 5))
	server.apply_action(mid, pid_a, ActionIntent.start())
	var before_marks: int = server.account_marks
	var snap: Snapshot = Snapshot.from_dict(server.get_snapshot(mid, pid_a))
	_expect(failed, snap.decoy_available(), "D1 decoyAvailable true at start")
	_expect(failed, snap.you_decoy_hex() == null, "D1 no decoyHex yet")
	_expect(failed, snap.enemy_decoy_soft_hex() == null, "D1 no enemy soft blip")
	_expect(failed, ActionIntent.decoy().get("hex", null) == null, "D1 intent has no hex arg")
	_expect(failed, str(ActionIntent.decoy().get("type", "")) == Contract.ACT_DECOY, "D1 type decoy")

	var r: ActionResult = server.apply_action(mid, pid_a, ActionIntent.decoy())
	_expect(failed, r.ok, "D1 decoy ok")
	snap = Snapshot.from_dict(r.snapshot)
	_expect(failed, str(snap.phase()) == Contract.PHASE_END_TURN, "D1 consumes turn → await_end_turn")
	_expect(failed, not snap.decoy_available(), "D1 decoyAvailable false after use")
	var planted: Variant = snap.you_decoy_hex()
	_expect(failed, planted is Dictionary, "D2 decoyHex set")
	_expect(failed, HexMath.distance(2, 2, int(planted.get("q", -9)), int(planted.get("r", -9))) == 1, "D2 adjacent to caster")
	_expect(failed, Contract.on_board(int(planted.get("q", -9)), int(planted.get("r", -9))), "D2 in-bounds")
	_expect(failed, not Contract.same_hex(planted, Contract.hex_dict(2, 2)), "D2 not caster secret")
	_expect(failed, not Contract.same_hex(planted, Contract.hex_dict(7, 5)), "D2 not rival secret")
	_expect(failed, Contract.same_hex(planted, Contract.hex_dict(3, 2)), "D2 first empty neighbor (3,2)")
	_expect(failed, _decoy_pick(0, 0, 8, 6) == Vector2i(1, 0), "D2 LIVE example A(0,0) B(8,6) → (1,0)")
	_expect(failed, _decoy_pick(0, 0, 1, 0) == Vector2i(0, 1), "D2 LIVE example A(0,0) B(1,0) → (0,1)")
	_expect(failed, str(snap.last_action().get("type", "")) == Contract.ACT_DECOY, "D1 lastAction decoy")
	_expect(failed, not snap.last_action().has("marksDelta"), "D5 decoy result has no marksDelta")
	_expect(failed, snap.you_marks() == before_marks, "D5 decoy does not grant/spend Marks")
	_expect(failed, server.account_marks == before_marks, "D5 mock ledger unchanged on decoy")
	_expect(failed, snap.uav_remaining() == 1, "D5 UAV charge untouched")
	_expect(failed, int(snap.you_exposure()) == 50, "D5 exposure unchanged")
	_expect(failed, Contract.RECON_BASE == 0.35, "D5 RECON_BASE still 0.35")
	_expect(failed, Contract.MARKS_PVP_WIN == 32, "D5 PvP kill table still ★32")

	r = server.apply_action(mid, pid_a, ActionIntent.decoy())
	_expect(failed, not r.ok, "D1 second decoy refused (phase)")
	r = server.apply_action(mid, pid_a, ActionIntent.end_turn(50))
	_expect(failed, r.ok, "D1 end_turn after decoy")
	snap = Snapshot.from_dict(r.snapshot)
	_expect(failed, str(snap.whose_turn()) == "b", "D1 turn passed after decoy")
	_expect(failed, Contract.same_hex(Snapshot.from_dict(server.get_snapshot(mid, pid_a)).you_decoy_hex(), planted), "D4 still live after planting end_turn")
	var b_snap: Snapshot = Snapshot.from_dict(server.get_snapshot(mid, pid_b))
	_expect(failed, Contract.same_hex(b_snap.enemy_decoy_soft_hex(), planted), "D2 enemy always sees decoySoftHex while live")
	_expect(failed, b_snap.you_decoy_hex() == null, "D2 enemy does not own the doll")

	r = server.apply_action(mid, pid_b, ActionIntent.attack(int(planted["q"]), int(planted["r"])))
	_expect(failed, r.ok, "D3 attack decoy ok")
	snap = Snapshot.from_dict(r.snapshot)
	var last: Variant = snap.last_action()
	_expect(failed, last is Dictionary and last.get("hit") == false, "D3 hit:false")
	_expect(failed, last is Dictionary and last.get("kill") == false, "D3 kill:false")
	_expect(failed, last is Dictionary and last.get("decoyCleared") == true, "D3 decoyCleared:true")
	_expect(failed, snap.status() != Contract.STATUS_ENDED, "D3 miss does not end match")
	_expect(failed, snap.you_decoy_hex() == null, "D3 owner hex cleared")
	_expect(failed, Snapshot.from_dict(server.get_snapshot(mid, pid_a)).you_decoy_hex() == null, "D3 A decoyHex cleared")
	_expect(failed, Snapshot.from_dict(server.get_snapshot(mid, pid_b)).enemy_decoy_soft_hex() == null, "D3 B soft blip cleared")
	_expect(failed, server.account_marks == before_marks, "D5 attack-on-decoy no Marks")
	_expect(failed, snap.you_marks() == 0, "D5 seat B Marks unchanged on decoy miss")

	## Fresh match: expiry on next own end_turn, plus once-spent after cycle.
	server.clear_all()
	server.reset_wallet(Contract.MOCK_WALLET_STUB)
	created = server.create_match()
	mid = str(created["matchId"])
	a = server.join(mid, created["joinTokens"]["a"])
	b = server.join(mid, created["joinTokens"]["b"])
	pid_a = str(a["playerId"])
	pid_b = str(b["playerId"])
	server.apply_action(mid, pid_a, ActionIntent.select_hex(2, 2))
	server.apply_action(mid, pid_b, ActionIntent.select_hex(7, 5))
	server.apply_action(mid, pid_a, ActionIntent.start())
	r = server.apply_action(mid, pid_a, ActionIntent.decoy())
	planted = Snapshot.from_dict(r.snapshot).you_decoy_hex()
	server.apply_action(mid, pid_a, ActionIntent.end_turn(50))
	server.apply_action(mid, pid_b, ActionIntent.recon(4, 3))
	server.apply_action(mid, pid_b, ActionIntent.end_turn(50))
	snap = Snapshot.from_dict(server.get_snapshot(mid, pid_a))
	_expect(failed, Contract.same_hex(snap.you_decoy_hex(), planted), "D4 still live on next own action window")
	_expect(failed, not snap.decoy_available(), "D1 still spent on next own turn")
	r = server.apply_action(mid, pid_a, ActionIntent.decoy())
	_expect(failed, not r.ok, "D1 second decoy refused (spent)")
	r = server.apply_action(mid, pid_a, ActionIntent.attack(0, 0))
	_expect(failed, r.ok and r.snapshot.get("lastAction", {}).get("hit") == false, "D5 miss path unchanged with live decoy")
	r = server.apply_action(mid, pid_a, ActionIntent.end_turn(50))
	_expect(failed, r.ok, "D4 next own end_turn")
	snap = Snapshot.from_dict(r.snapshot)
	_expect(failed, snap.you_decoy_hex() == null, "D4 expired on next own end_turn")
	_expect(failed, Snapshot.from_dict(server.get_snapshot(mid, pid_b)).enemy_decoy_soft_hex() == null, "D4 enemy soft blip expired")
	_expect(failed, server.account_marks == Contract.MOCK_WALLET_STUB, "D5 expiry does not touch Marks")

	## Kill path still hex-equality while a decoy is live elsewhere.
	server.clear_all()
	server.reset_wallet(0)
	created = server.create_match()
	mid = str(created["matchId"])
	a = server.join(mid, created["joinTokens"]["a"])
	b = server.join(mid, created["joinTokens"]["b"])
	pid_a = str(a["playerId"])
	pid_b = str(b["playerId"])
	server.apply_action(mid, pid_a, ActionIntent.select_hex(2, 2))
	server.apply_action(mid, pid_b, ActionIntent.select_hex(7, 5))
	server.apply_action(mid, pid_a, ActionIntent.start())
	server.apply_action(mid, pid_a, ActionIntent.decoy())
	server.apply_action(mid, pid_a, ActionIntent.end_turn(50))
	r = server.apply_action(mid, pid_b, ActionIntent.attack(2, 2))
	snap = Snapshot.from_dict(r.snapshot)
	_expect(failed, bool(r.ok) and snap.status() == Contract.STATUS_ENDED, "D5 real kill still works")
	_expect(failed, snap.last_action().get("hit") == true, "D5 real hex is still a hit")
	_expect(failed, snap.you_decoy_hex() == null, "D5 match end clears decoy")
	_expect(failed, snap.enemy_decoy_soft_hex() == null, "D5 match end clears soft blip")
	_expect(failed, snap.marks_delta() == Contract.MARKS_PVP_WIN, "D5 kill Marks table unchanged")


func _lobby_case(failed: PackedStringArray) -> void:
	## P1–P5 mock: create/wait, join→ready, same rules, bad code, cancel no forfeit.
	var LobbyScript := load("res://types/lobby.gd")
	_expect(failed, Contract.LOBBY_CODE_LEN == 6, "P lobby code length 6")
	_expect(failed, Contract.LOBBY_CODE_ALPHABET.find("0") < 0, "P no 0 in alphabet")
	_expect(failed, Contract.LOBBY_CODE_ALPHABET.find("O") < 0, "P no O in alphabet")
	_expect(failed, Contract.LOBBY_CODE_ALPHABET.find("1") < 0, "P no 1 in alphabet")
	_expect(failed, Contract.LOBBY_CODE_ALPHABET.find("I") < 0, "P no I in alphabet")
	_expect(failed, Contract.is_lobby_code("H7K3P2"), "P sample code valid")
	_expect(failed, Contract.is_lobby_code("ABCDEF"), "P ABCDEF charset ok")
	_expect(failed, not Contract.is_lobby_code("ABC10O"), "P reject 1/0/O")
	_expect(failed, Contract.lobby_code_display("H7K3P2") == "H7K 3P2", "P display spacing")
	_expect(failed, Contract.LOBBY_REJECT_COPY.find("expired or wrong") >= 0, "P reject copy")
	_expect(failed, Contract.LOBBY_WAIT_COPY.find("countdown") < 0, "P no countdown copy")
	_expect(failed, Contract.LOBBY_HEADING.find("RANK") < 0, "P no ranked chrome")

	server.clear_all()
	server.reset_wallet(24)
	var host: Dictionary = server.create_lobby("p_host")
	var parsed = LobbyScript.from_any(host)
	_expect(failed, bool(host.get("ok", false)), "P1 create ok")
	_expect(failed, str(host.get("status", "")) == Contract.LOBBY_WAITING, "P1 status waiting")
	_expect(failed, str(host.get("lobbyId", "")).begins_with("lob_"), "P1 lobbyId lob_")
	_expect(failed, Contract.is_lobby_code(str(host.get("code", ""))), "P1 6-char code")
	_expect(failed, str(host.get("matchId", "")) == "", "P1 no match yet")
	_expect(failed, int(host.get("marks", -1)) == 24, "P1 Marks unchanged on create")
	_expect(failed, parsed.is_waiting(), "P1 parser waiting")
	_expect(failed, str(host.get("snapshot", {}).get("kind", "")) == "lobby", "P1 create lobby snap")
	var code := str(host.get("code", ""))
	var lid := str(host.get("lobbyId", ""))
	var poll: Dictionary = server.get_lobby(lid, "p_host")
	_expect(failed, str(poll.get("status", "")) == Contract.LOBBY_WAITING, "P1 poll still waiting")

	## P4 — bad / expired / self.
	var bad: Dictionary = server.join_lobby("NOPE!!", "p_guest")
	_expect(failed, not bool(bad.get("ok", true)), "P4 junk rejected")
	_expect(failed, str(bad.get("code", "")) == Contract.LOBBY_ERR_INVALID, "P4 invalid_lobby_code")
	_expect(failed, int(bad.get("marks", -1)) == 24, "P4 reject Marks frozen")
	var missing: Dictionary = server.join_lobby("ABCDEF", "p_guest")
	_expect(failed, str(missing.get("code", "")) == Contract.LOBBY_ERR_NOT_FOUND, "P4 lobby_not_found")
	var missing_parsed = LobbyScript.from_any(missing)
	_expect(failed, missing_parsed.is_reject() and not missing_parsed.is_unavailable(), "P4 404 not_found is reject")
	var self_join: Dictionary = server.join_lobby(code, "p_host")
	_expect(failed, str(self_join.get("code", "")) == Contract.LOBBY_ERR_SELF, "P4 already_in_lobby")
	_expect(failed, server.account_marks == 24, "P4 self-join Marks frozen")
	var route_gap = LobbyScript.from_any({
		"ok": false,
		"error": Contract.LOBBY_ERR_UNAVAILABLE,
		"code": Contract.LOBBY_ERR_UNAVAILABLE,
		"httpStatus": 404,
	})
	_expect(failed, route_gap.is_unavailable(), "P route-missing 404 is unavailable")

	## P2 — guest sits B → ready match + joinToken.
	var guest: Dictionary = server.join_lobby(code, "p_guest")
	_expect(failed, bool(guest.get("ok", false)), "P2 join ok")
	_expect(failed, str(guest.get("status", "")) == Contract.LOBBY_READY, "P2 status ready")
	_expect(failed, str(guest.get("matchId", "")) != "", "P2 matchId")
	_expect(failed, str(guest.get("joinToken", "")) != "", "P2 joinToken")
	_expect(failed, str(guest.get("seat", "")) == Contract.SEAT_B, "P2 seat B")
	_expect(failed, str(guest.get("snapshot", {}).get("status", "")) == Contract.STATUS_READY, "P2 match ready")
	var replay_host: Dictionary = server.get_lobby(lid, "p_host")
	_expect(failed, str(replay_host.get("status", "")) == Contract.LOBBY_READY, "P2 host poll ready")
	_expect(failed, str(replay_host.get("matchId", "")) == str(guest.get("matchId", "")), "P2 same matchId")
	_expect(failed, str(replay_host.get("joinToken", "")) != "", "P2 host joinToken")
	_expect(failed, str(replay_host.get("joinToken", "")) != str(guest.get("joinToken", "")), "P2 seats get own tokens")
	_expect(failed, str(replay_host.get("seat", "")) == Contract.SEAT_A, "P2 host seat A")
	_expect(failed, str(replay_host.get("snapshot", {}).get("kind", "")) == "lobby", "P2 GET keeps lobby snap")
	_expect(failed, not Contract.is_match_snapshot(replay_host.get("snapshot", {}), str(guest.get("matchId", ""))), "P2 GET snap is not match")
	_expect(failed, Contract.is_match_snapshot(guest.get("snapshot", {}), str(guest.get("matchId", ""))), "P2 join snap is match")
	_expect(failed, server.account_marks == 24, "P2 join Marks frozen")
	var started: Dictionary = server.cancel_lobby(lid, "p_host")
	_expect(failed, str(started.get("code", "")) == Contract.LOBBY_ERR_STARTED, "P5 cancel after ready 409")
	_expect(failed, server.account_marks == 24, "P5 started-cancel Marks frozen")
	var mid := str(guest.get("matchId", ""))
	var pid_a := "p_host"
	var pid_b := "p_guest"
	var snap_a: Snapshot = Snapshot.from_dict(server.get_snapshot(mid, pid_a))
	var snap_b: Snapshot = Snapshot.from_dict(server.get_snapshot(mid, pid_b))
	_expect(failed, snap_a.status() == Contract.STATUS_READY, "P2 A ready to drop")
	_expect(failed, snap_b.status() == Contract.STATUS_READY, "P2 B ready to drop")
	_expect(failed, snap_a.you_seat() == Contract.SEAT_A and snap_b.you_seat() == Contract.SEAT_B, "P2 seats")
	_expect(failed, snap_a.you_marks() == 24, "P2 A wallet from snapshot")

	## P3 — same hunt rules + Marks table.
	server.apply_action(mid, pid_a, ActionIntent.select_hex(2, 2))
	server.apply_action(mid, pid_b, ActionIntent.select_hex(7, 5))
	server.apply_action(mid, pid_a, ActionIntent.start())
	var miss: ActionResult = server.apply_action(mid, pid_a, ActionIntent.attack(0, 0))
	var miss_snap: Snapshot = Snapshot.from_dict(miss.snapshot)
	_expect(failed, bool(miss.ok) and miss_snap.last_action().get("hit") == false, "P3 miss hit=false")
	_expect(failed, miss_snap.enemy_visible_hex() == null, "P3 miss no invented Hot")
	server.apply_action(mid, pid_a, ActionIntent.end_turn(50))
	var kill: ActionResult = server.apply_action(mid, pid_b, ActionIntent.attack(2, 2))
	var kill_snap: Snapshot = Snapshot.from_dict(kill.snapshot)
	_expect(failed, kill_snap.status() == Contract.STATUS_ENDED, "P3 kill ended")
	_expect(failed, kill_snap.marks_delta() == Contract.MARKS_PVP_WIN, "P3 winner ★32")
	_expect(failed, kill_snap.end_reason() == Contract.END_KILL, "P3 reason kill")
	var loser: Snapshot = Snapshot.from_dict(server.get_snapshot(mid, pid_a))
	_expect(failed, loser.marks_delta() == Contract.MARKS_PVP_LOSS, "P3 loser ★4")
	_expect(failed, loser.rematch_offered(), "P3 rematch still offered")
	_expect(failed, Contract.RECON_BASE == 0.35 and Contract.MARKS_PVP_WIN == 32, "P3 combat table ★32")

	## P5 — cancel / leave → hideout, no forfeit Marks.
	server.clear_all()
	server.reset_wallet(24)
	host = server.create_lobby("p_host")
	lid = str(host.get("lobbyId", ""))
	var before_ids: Array = server._matches.keys()
	var left: Dictionary = server.cancel_lobby(lid, "p_host")
	_expect(failed, bool(left.get("ok", false)), "P5 cancel ok")
	_expect(failed, str(left.get("status", "")) == Contract.LOBBY_CANCELLED, "P5 cancelled")
	_expect(failed, server.account_marks == 24, "P5 cancel Marks frozen")
	_expect(failed, server._matches.keys() == before_ids, "P5 cancel minted no match")
	var late: Dictionary = server.join_lobby(str(host.get("code", "")), "p_guest")
	_expect(failed, not bool(late.get("ok", true)), "P5 join after cancel rejected")
	_expect(failed, str(late.get("code", "")) == Contract.LOBBY_ERR_CANCELLED, "P5 cancelled code")
	_expect(failed, server.account_marks == 24, "P5 late join Marks frozen")
	_expect(failed, not server._matches.has(str(late.get("matchId", "nope"))), "P5 no forfeit match")

	## TTL expire — still a reject, not a forfeit overlay.
	server.clear_all()
	server.reset_wallet(18)
	server.test_now_ms = 1000
	host = server.create_lobby("p_host")
	lid = str(host.get("lobbyId", ""))
	code = str(host.get("code", ""))
	server.test_now_ms = 1000 + Contract.LOBBY_TTL_MS + 50
	var aged: Dictionary = server.get_lobby(lid, "p_host")
	_expect(failed, str(aged.get("code", aged.get("error", ""))) == Contract.LOBBY_ERR_EXPIRED, "P5 TTL expired")
	_expect(failed, server.account_marks == 18, "P5 expire Marks frozen")
	var stale: Dictionary = server.join_lobby(code, "p_guest")
	_expect(failed, str(stale.get("code", "")) == Contract.LOBBY_ERR_EXPIRED, "P4 expired join")
	_expect(failed, server.account_marks == 18, "P4 expired Marks frozen")
	server.test_now_ms = -1


func _invite_share_case(failed: PackedStringArray) -> void:
	## I1–I6: copy / share the existing 6-char code. Wait plate only. No API.
	var InviteShare := load("res://scripts/invite_share.gd")
	_expect(failed, Contract.LOBBY_SHARE_BLURB == "Hunt with me — code %s", "I2 blurb template")
	_expect(failed, Contract.LOBBY_COPIED_COPY.find("Code copied") >= 0, "I6 toast copy")
	_expect(failed, Contract.LOBBY_SHARE_BLURB.find("http") < 0, "I2 blurb has no link")
	_expect(failed, Contract.LOBBY_SHARE_BLURB.to_lower().find("sms") < 0, "I2 blurb has no SMS")
	_expect(failed, InviteShare.blurb_for("h7k 3p2") == "Hunt with me — code H7K3P2", "I2 blurb uses the code")
	_expect(failed, not InviteShare.copy_code("NOPE"), "I1 reject a non-code")
	_expect(failed, InviteShare.share_code("") == InviteShare.RESULT_NONE, "I2 empty share is a no-op")
	_expect(failed, not InviteShare.open_share_sheet(""), "I2 empty sheet stays closed")
	_expect(failed, not DisplayServer.has_method("share_text"), "I2 this Godot build has no share_text")
	_expect(failed, not OS.has_method("share_text"), "I2 OS has no share_text")

	server.clear_all()
	server.reset_wallet(24)
	var host: Dictionary = server.create_lobby("p_host")
	var code := str(host.get("code", ""))
	var lid := str(host.get("lobbyId", ""))
	var lobby_count: int = server._lobby_by_code.size()
	_expect(failed, Contract.is_lobby_code(code), "I3 create still mints one code")
	_expect(failed, InviteShare.copy_code(code), "I1 copy accepts the lobby code")
	if DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):
		_expect(failed, DisplayServer.clipboard_get() == code, "I1 clipboard is the 6-char code")
		_expect(failed, DisplayServer.clipboard_get().length() == Contract.LOBBY_CODE_LEN, "I1 clipboard length 6")
		_expect(failed, DisplayServer.clipboard_get().find(" ") < 0, "I1 clipboard has no display space")
	var mode: String = InviteShare.share_code(code)
	_expect(failed, mode == InviteShare.RESULT_CLIPBOARD, "I2 desktop share is copy-only")
	_expect(failed, InviteShare.blurb_for(code) == "Hunt with me — code %s" % code, "I2 blurb keeps this code")
	if DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):
		_expect(failed, DisplayServer.clipboard_get() == InviteShare.blurb_for(code), "I2 fallback clipboard is the blurb")
		_expect(failed, DisplayServer.clipboard_get().find(code) >= 0, "I2 blurb contains the same code")
	var again: Dictionary = server.get_lobby(lid, "p_host")
	_expect(failed, str(again.get("code", "")) == code, "I3 share did not mint a code")
	_expect(failed, str(again.get("lobbyId", "")) == lid, "I3 same lobby id")
	_expect(failed, str(again.get("status", "")) == Contract.LOBBY_WAITING, "I3 still waiting")
	_expect(failed, server._lobby_by_code.size() == lobby_count, "I3 lobby count unchanged")
	_expect(failed, int(again.get("marks", -1)) == 24, "I5 share does not touch Marks")

	var share_src := FileAccess.get_file_as_string("res://scripts/invite_share.gd")
	var hud_src := FileAccess.get_file_as_string("res://scenes/lobby/hideout_lobby.gd")
	var api_src := FileAccess.get_file_as_string("res://autoload/match_api.gd")
	var live_src := FileAccess.get_file_as_string("res://autoload/live_match_client.gd")
	_expect(failed, share_src.find("clipboard_set") >= 0, "I1 copy uses clipboard_set")
	_expect(failed, share_src.find("MatchAPI") < 0, "I5 share script does not call MatchAPI")
	_expect(failed, share_src.find("create_lobby") < 0, "I3 share does not create a lobby")
	_expect(failed, share_src.find("new_lobby_code") < 0, "I3 share does not mint a code")
	_expect(failed, share_src.find("/lobbies") < 0, "I5 no lobby route in share")
	_expect(failed, share_src.find("shell_open") < 0, "I2 no shell_open link handoff")
	_expect(failed, share_src.to_lower().find("sms:") < 0, "I2 no SMS CTA")
	_expect(failed, share_src.to_lower().find("mailto") < 0, "I2 no mail CTA")
	_expect(failed, share_src.to_lower().find("qr") < 0, "I2 no QR")
	_expect(failed, share_src.find("ACTION_SEND") >= 0, "I2 Android share sheet is ACTION_SEND")
	_expect(failed, api_src.find("invite_share") < 0, "I5 match API unchanged")
	_expect(failed, live_src.find("invite_share") < 0, "I5 live client unchanged")
	_expect(failed, api_src.find("ACTION_SEND") < 0, "I5 no share intent on the API")
	_expect(failed, hud_src.find("_invite_wait.add_child(code_row)") >= 0, "I4 chips live on the wait plate")
	_expect(failed, hud_src.find("code_row.add_child(wait_share)") >= 0, "I4 share chip is on the code row")
	_expect(failed, hud_src.find("code_row.add_child(wait_copy)") >= 0, "I4 copy chip is on the code row")
	_expect(failed, hud_src.find("_invite_home.add_child(wait_share)") < 0, "I4 join home has no share chip")
	_expect(failed, hud_src.find("Chrome.chunk_button(Contract.LOBBY_COPY_CODE, Chrome.WOOD_DARK, Chrome.HIGH_GOLD") >= 0, "I6 copy chip is wood/gold")
	_expect(failed, hud_src.find("Chrome.chunk_button(Contract.LOBBY_SHARE_CODE, Chrome.HIGH_GOLD, Chrome.INK") >= 0, "I6 share chip is gold")
	_expect(failed, hud_src.find("Contract.LOBBY_COPIED_COPY") >= 0, "I6 toast uses Code copied")
	_expect(failed, hud_src.find("_on_share_lobby_code") >= 0, "I4 share handler exists")


func _paste_clipboard_case(failed: PackedStringArray) -> void:
	## C1–C6: one clipboard peek on the join plate. Tap fills. Join API stays put.
	var LobbyPaste := load("res://scripts/lobby_paste.gd")
	var InviteShare := load("res://scripts/invite_share.gd")
	_expect(failed, Contract.LOBBY_PASTE_CODE == "PASTE", "C6 paste label")
	_expect(failed, Contract.LOBBY_PASTED_COPY == "Pasted.", "C6 toast copy")
	_expect(failed, LobbyPaste.code_from_text("H7K3P2") == "H7K3P2", "C1 bare code")
	_expect(failed, LobbyPaste.code_from_text("h7k 3p2") == "H7K3P2", "C1 spaced display form")
	_expect(failed, LobbyPaste.code_from_text("H7K-3P2") == "H7K3P2", "C1 dashed code")
	_expect(failed, LobbyPaste.code_from_text("  h7k3p2  ") == "H7K3P2", "C1 trimmed code")
	_expect(failed, LobbyPaste.code_from_text("") == "", "C3 empty clipboard")
	_expect(failed, LobbyPaste.code_from_text("   ") == "", "C3 blank clipboard")
	_expect(failed, LobbyPaste.code_from_text("NOPE") == "", "C3 short text")
	_expect(failed, LobbyPaste.code_from_text("ABC10O") == "", "C3 ambiguous charset")
	_expect(failed, LobbyPaste.code_from_text("H7K3P2X") == "", "C3 seven chars")
	_expect(failed, LobbyPaste.code_from_text(InviteShare.blurb_for("H7K3P2")) == "", "C5 blurb is not a code")
	_expect(failed, LobbyPaste.code_from_text("https://glassline.dev/H7K3P2") == "", "C5 no link scrape")
	_expect(failed, LobbyPaste.code_from_text("glassline://join/H7K3P2") == "", "C5 no deep link")
	_expect(failed, LobbyPaste.code_from_text("sms:H7K3P2") == "", "C5 no SMS scrape")
	_expect(failed, LobbyPaste.fill_text("KEEP", "H7K3P2") == "H7K3P2", "C2 paste fills the field")
	_expect(failed, LobbyPaste.fill_text("", "h7k 3p2") == "H7K3P2", "C2 paste normalizes")
	_expect(failed, LobbyPaste.fill_text("KEEP", "") == "KEEP", "C3 empty peek is a no-op")
	_expect(failed, LobbyPaste.fill_text("KEEP", "NOPE") == "KEEP", "C3 invalid peek is a no-op")
	_expect(failed, LobbyPaste.fill_text("AB", "ABC10O") == "AB", "C3 bad alphabet is a no-op")
	_expect(failed, LobbyPaste.fill_text("KEEP", InviteShare.blurb_for("H7K3P2")) == "KEEP", "C5 blurb does not fill")

	DisplayServer.clipboard_set("H7K3P2")
	if DisplayServer.clipboard_get() == "H7K3P2":
		_expect(failed, LobbyPaste.peek_code() == "H7K3P2", "C1 peek reads the clipboard")
		DisplayServer.clipboard_set("")
		_expect(failed, LobbyPaste.peek_code() == "", "C3 empty clipboard peek")
		DisplayServer.clipboard_set(InviteShare.blurb_for("H7K3P2"))
		_expect(failed, LobbyPaste.peek_code() == "", "C5 peek ignores the share blurb")
		DisplayServer.clipboard_set("glassline://join/H7K3P2")
		_expect(failed, LobbyPaste.peek_code() == "", "C5 peek ignores a deep link")
		DisplayServer.clipboard_set("")

	var paste_src := FileAccess.get_file_as_string("res://scripts/lobby_paste.gd")
	var hud_src := FileAccess.get_file_as_string("res://scenes/lobby/hideout_lobby.gd")
	var api_src := FileAccess.get_file_as_string("res://autoload/match_api.gd")
	var live_src := FileAccess.get_file_as_string("res://autoload/live_match_client.gd")
	_expect(failed, paste_src.find("clipboard_get") >= 0, "C1 peek uses clipboard_get")
	_expect(failed, paste_src.find("clipboard_set") < 0, "C1 peek does not write the clipboard")
	_expect(failed, paste_src.find("MatchAPI") < 0, "C4 paste script does not call MatchAPI")
	_expect(failed, paste_src.find("join_lobby") < 0, "C4 paste script does not join")
	_expect(failed, paste_src.find("create_lobby") < 0, "C4 paste script does not create")
	_expect(failed, paste_src.find("new_lobby_code") < 0, "C4 paste script does not mint a code")
	_expect(failed, paste_src.find("_process") < 0, "C5 paste script has no process loop")
	_expect(failed, paste_src.find("shell_open") < 0, "C5 no shell_open")
	_expect(failed, paste_src.to_lower().find("sms:") < 0, "C5 paste script has no SMS CTA")
	_expect(failed, paste_src.to_lower().find("qr") < 0, "C5 paste script has no QR")
	_expect(failed, api_src.find("func join_lobby(code: String)") >= 0, "C4 join_lobby signature")
	_expect(failed, api_src.find("LiveMatchClient.join_lobby(code)") >= 0, "C4 live join path")
	_expect(failed, api_src.find("MockMatchServer.join_lobby(code, pid)") >= 0, "C4 mock join path")
	_expect(failed, api_src.find("clipboard") < 0, "C4 match API has no clipboard")
	_expect(failed, api_src.find("lobby_paste") < 0, "C4 match API has no paste")
	_expect(failed, live_src.find("clipboard") < 0, "C4 live client has no clipboard")
	_expect(failed, live_src.find("lobby_paste") < 0, "C4 live client has no paste")
	_expect(failed, hud_src.find("clipboard_get") < 0, "C5 join plate reads through LobbyPaste")
	_expect(failed, hud_src.find("clipboard_set") >= 0, "C6 captures can seed the clipboard")
	var process_body := _fn_body(hud_src, "_process")
	_expect(failed, process_body.find("clipboard") < 0, "C5 process does not touch the clipboard")
	_expect(failed, process_body.find("LobbyPaste") < 0, "C5 process does not peek")
	_expect(failed, process_body.find("_peek_join_clipboard") < 0, "C5 no paste poll")
	var peek_body := _fn_body(hud_src, "_peek_join_clipboard")
	_expect(failed, peek_body.find("LobbyPaste.peek_code") >= 0, "C1 open/focus calls peek_code")
	_expect(failed, peek_body.find("_join_edit.text") < 0, "C2 peek does not fill the field")
	_expect(failed, peek_body.find("join_lobby") < 0, "C4 peek does not join")
	var paste_body := _fn_body(hud_src, "_on_paste_lobby_code")
	_expect(failed, paste_body.find("LobbyPaste.fill_text") >= 0, "C2 paste uses fill_text")
	_expect(failed, paste_body.find("_join_edit.text = filled") >= 0, "C2 paste writes the field")
	_expect(failed, paste_body.find("join_lobby") < 0, "C4 paste tap does not join")
	_expect(failed, paste_body.find("MatchAPI") < 0, "C4 paste tap does not call the API")
	_expect(failed, paste_body.find("Contract.LOBBY_PASTED_COPY") >= 0, "C6 toast uses Pasted.")
	var note_body := _fn_body(hud_src, "_notification")
	_expect(failed, note_body.find("NOTIFICATION_WM_WINDOW_FOCUS_IN") >= 0, "C1 window focus peeks")
	_expect(failed, note_body.find("NOTIFICATION_APPLICATION_FOCUS_IN") >= 0, "C1 app focus peeks")
	_expect(failed, note_body.find("_join_form_open") >= 0, "C5 focus peek only while the join form is open")
	_expect(failed, hud_src.find("_join_edit.focus_entered.connect(_peek_join_clipboard)") >= 0, "C1 field focus peeks")
	_expect(failed, hud_src.find("_show_invite_home") >= 0, "C1 join home exists")
	var home_body := _fn_body(hud_src, "_show_invite_home")
	_expect(failed, home_body.find("_peek_join_clipboard()") >= 0, "C1 opening the join form peeks once")
	var edit_at := hud_src.find("join_row.add_child(_join_edit)")
	var paste_at := hud_src.find("join_row.add_child(_join_paste)")
	var join_at := hud_src.find("join_row.add_child(join_btn)")
	_expect(failed, edit_at >= 0 and paste_at > edit_at and join_at > paste_at, "C6 Paste sits between the code field and Join")
	_expect(failed, hud_src.find("Chrome.chunk_button(Contract.LOBBY_PASTE_CODE, Chrome.WOOD_DARK, Chrome.HIGH_GOLD") >= 0, "C6 paste chip is wood/gold")
	_expect(failed, hud_src.find("code_row.add_child(_join_paste)") < 0, "C6 paste is not on the wait plate")
	_expect(failed, hud_src.find("_invite_wait.add_child(_join_paste)") < 0, "C6 wait plate has no paste chip")
	_expect(failed, hud_src.find("MatchAPI.join_lobby(typed)") >= 0, "C4 join still posts the field")
	var clear_body := _fn_body(hud_src, "_clear_pasted_toast")
	_expect(failed, clear_body.find("_set_pasted_note(false)") >= 0, "P2 clear hides the Pasted note")
	_expect(failed, clear_body.find("Contract.LOBBY_PASTED_COPY") >= 0, "P2 clear only drops the Pasted toast")
	_expect(failed, home_body.find("_clear_pasted_toast()") >= 0, "P2 opening join clears Pasted")
	_expect(failed, home_body.find("_set_pasted_note(true)") < 0, "P2 opening join does not show Pasted")
	var close_body := _fn_body(hud_src, "_close_invite")
	_expect(failed, close_body.find("_clear_pasted_toast()") >= 0, "P2 leaving join clears Pasted")
	var offer_body := _fn_body(hud_src, "_set_paste_offer")
	_expect(failed, offer_body.find("if not offered:") >= 0 and offer_body.find("_clear_pasted_toast()") >= 0, "P2 hidden paste chip clears Pasted")
	_expect(failed, peek_body.find("if not Contract.is_lobby_code(code):") >= 0, "P2 empty peek notices a missing code")
	_expect(failed, peek_body.find("_clear_pasted_toast()") >= 0, "P2 empty peek clears Pasted")
	_expect(failed, peek_body.find("_set_pasted_note(true)") < 0, "P2 peek does not show Pasted")
	_expect(failed, peek_body.find("_join_edit.text") < 0, "C2 peek still does not fill the field")
	var wait_body := _fn_body(hud_src, "_show_invite_wait")
	_expect(failed, wait_body.find("_clear_pasted_toast()") >= 0, "P2 leaving the join form clears Pasted")


func _fn_body(src: String, name: String) -> String:
	var token := "func %s(" % name
	var at := src.find(token)
	if at < 0:
		return ""
	var nxt := src.find("\nfunc ", at + token.length())
	if nxt < 0:
		return src.substr(at)
	return src.substr(at, nxt - at)


func _queue_case(failed: PackedStringArray) -> void:
	## Q1–Q5 mock: 1-tap queue, pair → same hunt, cancel/timeout Marks Δ0, no bot fill.
	var QueueScript := load("res://types/queue.gd")
	_expect(failed, Contract.QUEUE_TTL_SEC == 60, "Q TTL 60s")
	_expect(failed, Contract.QUEUE_HEADING.find("RIVAL") >= 0, "Q6 finding a rival")
	_expect(failed, Contract.QUEUE_WAIT_COPY.find("Finding a rival") >= 0, "Q6 wait copy")
	_expect(failed, Contract.QUEUE_CTA == "QUICK MATCH", "Q1 CTA")
	_expect(failed, Contract.QUEUE_HEADING.find("RANK") < 0, "Q6 no ranked heading")
	_expect(failed, Contract.QUEUE_BLURB.find("MMR") < 0, "Q6 no MMR")
	_expect(failed, Contract.QUEUE_WAIT_COPY.find("countdown") < 0, "Q6 no countdown copy")
	_expect(failed, Contract.QUEUE_BLURB.find("ELO") < 0, "Q6 no ELO")

	## Q1 — one tap enqueue, still waiting, Marks frozen, no match yet.
	server.clear_all()
	server.reset_wallet(24)
	server.queue_pair_delay_ms = 80
	server.test_now_ms = 1000
	var one: Dictionary = server.enqueue("p_host")
	var parsed = QueueScript.from_any(one)
	_expect(failed, bool(one.get("ok", false)), "Q1 enqueue ok")
	_expect(failed, str(one.get("status", "")) == Contract.QUEUE_QUEUED, "Q1 status queued")
	_expect(failed, int(one.get("timeoutSec", 0)) == 60, "Q1 timeoutSec 60")
	_expect(failed, str(one.get("expiresAt", "")) != "", "Q1 expiresAt")
	_expect(failed, str(one.get("matchId", "")) == "", "Q1 no match yet")
	_expect(failed, int(one.get("marks", -1)) == 24, "Q1 Marks unchanged")
	_expect(failed, parsed.is_queued(), "Q1 parser queued")
	_expect(failed, str(one.get("snapshot", {}).get("kind", "")) == "queue", "Q1 queue snap")
	_expect(failed, server._matches.is_empty(), "Q1 minted no match")

	## Idempotent re-queue refreshes TTL (Coder pick, documented).
	server.test_now_ms = 20000
	var again: Dictionary = server.enqueue("p_host")
	_expect(failed, str(again.get("status", "")) == Contract.QUEUE_QUEUED, "Q1 requeue still queued")
	_expect(failed, int(again.get("secondsLeft", 0)) >= 50, "Q1 requeue refresh TTL")
	_expect(failed, server.account_marks == 24, "Q1 requeue Marks frozen")

	## Q5 — pair delay elapses with one player: still queued. No bot fill.
	server.test_now_ms = 20000 + 200
	var lonely: Dictionary = server.get_queue("p_host")
	_expect(failed, str(lonely.get("status", "")) == Contract.QUEUE_QUEUED, "Q5 still queued after delay")
	_expect(failed, str(lonely.get("matchId", "")) == "", "Q5 no bot matchId")
	_expect(failed, server._matches.is_empty(), "Q5 no bot match minted")
	_expect(failed, server.account_marks == 24, "Q5 lonely Marks frozen")

	## Q2 — second human sits → pair after delay → same rules / Marks / rematch.
	server.queue_pair_delay_ms = 80
	server.test_now_ms = 30000
	var guest: Dictionary = server.enqueue("p_guest")
	_expect(failed, str(guest.get("status", "")) == Contract.QUEUE_QUEUED, "Q2 guest queued before delay")
	_expect(failed, str(guest.get("matchId", "")) == "", "Q2 no match during delay")
	server.test_now_ms = 30000 + 80
	var host_ready: Dictionary = server.get_queue("p_host")
	var guest_ready: Dictionary = server.get_queue("p_guest")
	_expect(failed, str(host_ready.get("status", "")) == Contract.QUEUE_MATCHED, "Q2 host matched")
	_expect(failed, str(guest_ready.get("status", "")) == Contract.QUEUE_MATCHED, "Q2 guest matched")
	_expect(failed, str(host_ready.get("matchId", "")) != "", "Q2 matchId")
	_expect(failed, str(host_ready.get("joinToken", "")) != "", "Q2 host joinToken")
	_expect(failed, str(guest_ready.get("joinToken", "")) != "", "Q2 guest joinToken")
	_expect(failed, str(host_ready.get("joinToken", "")) != str(guest_ready.get("joinToken", "")), "Q2 own tokens")
	_expect(failed, str(host_ready.get("seat", "")) == Contract.SEAT_A, "Q2 host seat A")
	_expect(failed, str(guest_ready.get("seat", "")) == Contract.SEAT_B, "Q2 guest seat B")
	_expect(failed, Contract.is_match_snapshot(host_ready.get("snapshot", {}), str(host_ready.get("matchId", ""))), "Q2 match snap")
	_expect(failed, server.account_marks == 24, "Q2 pair Marks frozen")
	var started: Dictionary = server.dequeue("p_host")
	_expect(failed, str(started.get("status", "")) == Contract.QUEUE_IDLE, "Q2 DELETE after pair idle")
	_expect(failed, str(server.get_queue("p_host").get("status", "")) == Contract.QUEUE_MATCHED, "Q2 matched row stays")
	_expect(failed, server.account_marks == 24, "Q2 started-dequeue Marks frozen")
	var mid := str(host_ready.get("matchId", ""))
	var pid_a := "p_host"
	var pid_b := "p_guest"
	var snap_a: Snapshot = Snapshot.from_dict(server.get_snapshot(mid, pid_a))
	var snap_b: Snapshot = Snapshot.from_dict(server.get_snapshot(mid, pid_b))
	_expect(failed, snap_a.status() == Contract.STATUS_READY, "Q2 A ready to drop")
	_expect(failed, snap_b.status() == Contract.STATUS_READY, "Q2 B ready to drop")
	server.apply_action(mid, pid_a, ActionIntent.select_hex(2, 2))
	server.apply_action(mid, pid_b, ActionIntent.select_hex(7, 5))
	server.apply_action(mid, pid_a, ActionIntent.start())
	var miss: ActionResult = server.apply_action(mid, pid_a, ActionIntent.attack(0, 0))
	var miss_snap: Snapshot = Snapshot.from_dict(miss.snapshot)
	_expect(failed, bool(miss.ok) and miss_snap.last_action().get("hit") == false, "Q2 miss hit=false")
	server.apply_action(mid, pid_a, ActionIntent.end_turn(50))
	var kill: ActionResult = server.apply_action(mid, pid_b, ActionIntent.attack(2, 2))
	var kill_snap: Snapshot = Snapshot.from_dict(kill.snapshot)
	_expect(failed, kill_snap.status() == Contract.STATUS_ENDED, "Q2 kill ended")
	_expect(failed, kill_snap.marks_delta() == Contract.MARKS_PVP_WIN, "Q2 winner ★32")
	var loser: Snapshot = Snapshot.from_dict(server.get_snapshot(mid, pid_a))
	_expect(failed, loser.marks_delta() == Contract.MARKS_PVP_LOSS, "Q2 loser ★4")
	_expect(failed, loser.rematch_offered(), "Q2 rematch still offered")
	_expect(failed, Contract.RECON_BASE == 0.35 and Contract.MARKS_PVP_WIN == 32, "Q2 combat table ★32")

	## Q3 — cancel → hideout, Marks Δ0, no match.
	server.clear_all()
	server.reset_wallet(24)
	server.test_now_ms = 1000
	one = server.enqueue("p_host")
	var before_ids: Array = server._matches.keys()
	var left: Dictionary = server.dequeue("p_host")
	_expect(failed, bool(left.get("ok", false)), "Q3 cancel ok")
	_expect(failed, str(left.get("status", "")) == Contract.QUEUE_IDLE, "Q3 idle")
	_expect(failed, server.account_marks == 24, "Q3 cancel Marks frozen")
	_expect(failed, server._matches.keys() == before_ids, "Q3 cancel minted no match")
	var idle: Dictionary = server.get_queue("p_host")
	_expect(failed, str(idle.get("status", "")) == Contract.QUEUE_IDLE, "Q3 poll idle")
	_expect(failed, server.account_marks == 24, "Q3 idle Marks frozen")

	## Q4 — 60s TTL → hideout, Marks Δ0, no forfeit overlay / match.
	server.clear_all()
	server.reset_wallet(18)
	server.test_now_ms = 1000
	one = server.enqueue("p_host")
	before_ids = server._matches.keys()
	server.test_now_ms = 1000 + Contract.QUEUE_TTL_MS + 50
	var aged: Dictionary = server.get_queue("p_host")
	_expect(failed, str(aged.get("status", "")) == Contract.QUEUE_EXPIRED, "Q4 TTL expired")
	_expect(failed, bool(aged.get("timedOut", false)), "Q4 timedOut flag")
	_expect(failed, server.account_marks == 18, "Q4 timeout Marks frozen")
	_expect(failed, server._matches.keys() == before_ids, "Q4 timeout minted no match")
	var after: Dictionary = server.get_queue("p_host")
	_expect(failed, str(after.get("status", "")) == Contract.QUEUE_IDLE, "Q4 next poll idle")
	_expect(failed, server.account_marks == 18, "Q4 idle after timeout Marks frozen")
	server.test_now_ms = -1


func _play_pvp_kill() -> Dictionary:
	var created: Dictionary = server.create_match()
	var mid := str(created["matchId"])
	var a: Dictionary = server.join(mid, created["joinTokens"]["a"])
	var b: Dictionary = server.join(mid, created["joinTokens"]["b"])
	var pid_a := str(a["playerId"])
	var pid_b := str(b["playerId"])
	server.apply_action(mid, pid_a, ActionIntent.select_hex(2, 2))
	server.apply_action(mid, pid_b, ActionIntent.select_hex(7, 5))
	server.apply_action(mid, pid_a, ActionIntent.start())
	server.apply_action(mid, pid_a, ActionIntent.attack(7, 5))
	return {
		"matchId": mid,
		"pidA": pid_a,
		"pidB": pid_b,
		"tokens": created.get("joinTokens", {}),
		"fp": server.terrain_fingerprint(mid),
	}


func _rematch_case(failed: PackedStringArray) -> void:
	## R1–R5 mock: both accept + fresh terrain; same durable seats; Marks frozen; decline / timeout hideout.
	server.clear_all()
	server.reset_wallet(0)
	var hunt: Dictionary = _play_pvp_kill()
	var mid := str(hunt["matchId"])
	var pid_a := str(hunt["pidA"])
	var pid_b := str(hunt["pidB"])
	var ended: Snapshot = Snapshot.from_dict(server.get_snapshot(mid, pid_a))
	_expect(failed, ended.status() == Contract.STATUS_ENDED, "R rematch starts ended")
	_expect(failed, ended.rematch_status() == Contract.REMATCH_WAITING, "R waiting on ended")
	_expect(failed, ended.rematch_offered(), "R CTA offered")
	_expect(failed, not ended.rematch_you_accepted(), "R neither accepted yet")
	_expect(failed, ended.you_marks() == Contract.MARKS_PVP_WIN, "R kill already settled")
	var wallet: int = server.account_marks
	var old_fp := str(hunt["fp"])

	var one: Dictionary = server.rematch(mid, pid_a, true)
	_expect(failed, bool(one.get("ok", false)), "R accept A ok")
	_expect(failed, str(one.get("status", "")) == Contract.REMATCH_WAITING, "R LIVE waiting after A")
	_expect(failed, bool(one.get("youAccepted", false)), "R youAccepted A")
	_expect(failed, not bool(one.get("opponentAccepted", true)), "R opponent not yet")
	_expect(failed, str(one.get("rematch", {}).get("newMatchId", "")) == "", "R no match yet")
	_expect(failed, server.account_marks == wallet, "R3 accept A Marks frozen")

	var both: Dictionary = server.rematch(mid, pid_b, true)
	var rem: Variant = both.get("rematch", {})
	_expect(failed, bool(both.get("ok", false)), "R1 both accept ok")
	_expect(failed, str(both.get("status", "")) == Contract.REMATCH_READY, "R1 LIVE status ready")
	_expect(failed, rem is Dictionary and str(rem.get("status", "")) == Contract.REMATCH_READY, "R1 rematch ready")
	var new_id := str(both.get("matchId", rem.get("newMatchId", both.get("newMatchId", ""))))
	_expect(failed, new_id != "" and new_id != mid, "R1 new matchId")
	_expect(failed, str(both.get("joinToken", "")) != "", "R1 caller joinToken")
	_expect(failed, both.has("snapshot") and str(both.get("snapshot", {}).get("status", "")) == Contract.STATUS_READY, "R1 ready snapshot")
	var replay_a: Dictionary = server.rematch(mid, pid_a, true)
	_expect(failed, str(replay_a.get("status", "")) == Contract.REMATCH_READY, "R1 replay A ready")
	_expect(failed, str(replay_a.get("joinToken", "")) != "", "R1 replay A joinToken")
	_expect(failed, str(replay_a.get("matchId", "")) == new_id, "R1 replay same matchId")
	_expect(failed, server.account_marks == wallet, "R3 rematch create Marks frozen")

	var neu_a: Snapshot = Snapshot.from_dict(server.get_snapshot(new_id, pid_a))
	var neu_b: Snapshot = Snapshot.from_dict(server.get_snapshot(new_id, pid_b))
	_expect(failed, neu_a.status() == Contract.STATUS_READY, "R1 A ready to drop")
	_expect(failed, neu_b.status() == Contract.STATUS_READY, "R1 B ready to drop")
	_expect(failed, neu_a.you_seat() == Contract.SEAT_A and neu_b.you_seat() == Contract.SEAT_B, "R2 same seats")
	_expect(failed, not neu_a.you_placed() and not neu_b.you_placed(), "R1 fresh drop")
	_expect(failed, neu_a.you_marks() == wallet, "R3 new snap wallet unchanged")
	var new_fp: String = server.terrain_fingerprint(new_id)
	_expect(failed, new_fp != "" and new_fp != old_fp, "R1 terrain salt differs")
	var neu_row: Dictionary = server._matches[new_id]
	_expect(failed, str(neu_row["seats"][Contract.SEAT_A]["playerId"]) == pid_a, "R2 durable player A")
	_expect(failed, str(neu_row["seats"][Contract.SEAT_B]["playerId"]) == pid_b, "R2 durable player B")

	## R4 — one decline, no new match.
	server.clear_all()
	server.reset_wallet(wallet)
	hunt = _play_pvp_kill()
	mid = str(hunt["matchId"])
	pid_a = str(hunt["pidA"])
	pid_b = str(hunt["pidB"])
	wallet = server.account_marks
	var before_ids: Array = server._matches.keys()
	var no: Dictionary = server.rematch(mid, pid_b, false)
	_expect(failed, bool(no.get("ok", false)), "R4 decline ok")
	_expect(failed, str(no.get("rematch", {}).get("status", "")) == Contract.REMATCH_DECLINED, "R4 declined")
	_expect(failed, str(no.get("rematch", {}).get("newMatchId", "")) == "", "R4 no newMatchId")
	_expect(failed, server._matches.keys() == before_ids, "R4 no new match row")
	_expect(failed, server.account_marks == wallet, "R3 decline Marks frozen")
	var later: Dictionary = server.rematch(mid, pid_a, true)
	_expect(failed, str(later.get("rematch", {}).get("status", "")) == Contract.REMATCH_DECLINED, "R4 accept after decline stays declined")
	_expect(failed, server._matches.keys() == before_ids, "R4 still no new match")

	## R5 — 30s timeout == decline.
	server.clear_all()
	server.reset_wallet(0)
	server.test_now_ms = 1000
	hunt = _play_pvp_kill()
	mid = str(hunt["matchId"])
	pid_a = str(hunt["pidA"])
	wallet = server.account_marks
	before_ids = server._matches.keys()
	server.test_now_ms = 1000 + Contract.REMATCH_TIMEOUT_MS + 50
	var aged: Snapshot = Snapshot.from_dict(server.get_snapshot(mid, pid_a))
	_expect(failed, aged.rematch_status() == Contract.REMATCH_EXPIRED, "R5 snapshot expires")
	_expect(failed, aged.rematch_leave(), "R5 leave hideout")
	var late: Dictionary = server.rematch(mid, pid_a, true)
	_expect(failed, str(late.get("rematch", {}).get("status", "")) == Contract.REMATCH_EXPIRED, "R5 accept after expiry refused")
	_expect(failed, str(late.get("newMatchId", "")) == "", "R5 no new match")
	_expect(failed, server._matches.keys() == before_ids, "R5 no match spawned")
	_expect(failed, server.account_marks == wallet, "R3 timeout Marks frozen")

	## Jobs do not offer rematch.
	server.clear_all()
	server.reset_wallet(0)
	var job: Dictionary = server.create_job(1)
	var jid := str(job.get("matchId", ""))
	var jpid := str(job.get("playerId", ""))
	server.apply_action(jid, jpid, ActionIntent.select_hex(2, 2))
	server.apply_action(jid, jpid, ActionIntent.start())
	server.apply_action(jid, jpid, ActionIntent.attack(int(Contract.job_bot_hex(1).get("q", 8)), int(Contract.job_bot_hex(1).get("r", 6))))
	var job_snap: Snapshot = Snapshot.from_dict(server.get_snapshot(jid, jpid))
	_expect(failed, job_snap.rematch_status() == Contract.REMATCH_NONE, "R job rematch none")
	_expect(failed, not job_snap.rematch_offered(), "R job no CTA")
	var job_try: Dictionary = server.rematch(jid, jpid, true)
	_expect(failed, not bool(job_try.get("ok", true)), "R job rematch refused")
	_expect(failed, str(job_try.get("code", job_try.get("error", ""))) in [Contract.REMATCH_ERR_NOT_PVP, "rematch_not_available"], "R job rematch_not_available")


func _a4_gaps_case(failed: PackedStringArray) -> void:
	## A4.1 abandon → forfeit +15/0. Same settle as timeout. Rematch only after ended.
	server.clear_all()
	server.reset_wallet(24)
	var created: Dictionary = server.create_match()
	var mid := str(created["matchId"])
	var a: Dictionary = server.join(mid, created["joinTokens"]["a"])
	var b: Dictionary = server.join(mid, created["joinTokens"]["b"])
	var pid_a := str(a["playerId"])
	var pid_b := str(b["playerId"])
	server.apply_action(mid, pid_a, ActionIntent.select_hex(2, 2))
	server.apply_action(mid, pid_b, ActionIntent.select_hex(7, 5))
	server.apply_action(mid, pid_a, ActionIntent.start())
	var early: Dictionary = server.rematch(mid, pid_a, true)
	_expect(failed, not bool(early.get("ok", true)), "A4.4 rematch blocked while active")
	_expect(failed, str(early.get("code", "")) == Contract.REMATCH_ERR_NOT_ENDED, "A4.4 rematch 409 match_not_ended")
	var left: Dictionary = server.abandon(mid, pid_a)
	_expect(failed, bool(left.get("ok", false)), "A4.1 abandon ok")
	var loser: Snapshot = Snapshot.from_dict(left.get("snapshot", {}))
	_expect(failed, loser.status() == Contract.STATUS_ENDED, "A4.1 status ended")
	_expect(failed, loser.end_reason() == Contract.END_FORFEIT or loser.is_forfeit(), "A4.1 endReason forfeit")
	_expect(failed, str(loser.winner()) == "b", "A4.1 remaining seat wins")
	_expect(failed, loser.you_marks() == 24, "A4.1 leaver Marks +0 (24)")
	_expect(failed, loser.marks_delta() == Contract.MARKS_FORFEIT_LOSS, "A4.1 leaver marksDelta 0")
	var winner_snap: Snapshot = Snapshot.from_dict(server.get_snapshot(mid, pid_b))
	_expect(failed, winner_snap.you_marks() == Contract.MARKS_FORFEIT_WIN, "A4.1 remaining +15")
	_expect(failed, winner_snap.marks_delta() == Contract.MARKS_FORFEIT_WIN, "A4.1 remaining marksDelta +15")
	_expect(failed, winner_snap.rematch_offered(), "A4.4 rematch CTA after ended")
	var again: Dictionary = server.abandon(mid, pid_a)
	_expect(failed, bool(again.get("ok", false)), "A4.1 abandon idempotent")
	_expect(failed, bool(again.get("alreadyEnded", false)), "A4.1 alreadyEnded")
	_expect(failed, server.account_marks == 24, "A4.1 replay abandon no second grant")
	var foil := MarksPayout.end_overlay(winner_snap.raw, "b", false)
	_expect(failed, foil.find("RIVAL FORFEIT") >= 0, "A4.4 overlay winner chrome")
	_expect(failed, foil.find("+15") >= 0 or foil.find("table  +15") >= 0, "A4.4 overlay +15")
	_expect(failed, Contract.FORFEIT_HINT_COPY.find("stays put") < 0, "P2 forfeit hint is not stays-put")
	_expect(failed, Contract.FORFEIT_HINT_COPY.to_lower().find("settled") >= 0, "P2 forfeit hint settled wallet")
	var screen_src := FileAccess.get_file_as_string("res://scenes/match/match_screen.gd")
	_expect(failed, screen_src.find("FORFEIT_HINT_COPY") >= 0, "P2 forfeit overlay uses settled hint")
	_expect(failed, screen_src.find("STATUS %s") < 0 and screen_src.find("PHASE %s") < 0, "P2 no STATUS/PHASE ribbon")
	_expect(failed, screen_src.find("_over.z_index = 50") >= 0, "P2 forfeit plate above hex board")
	_expect(failed, screen_src.find("_over.z_as_relative = false") >= 0, "P2 forfeit plate absolute canvas z")

	## A4.2 / A4.3 — disconnect_at + 30s uses the same forfeit path. Countdown readable.
	server.clear_all()
	server.reset_wallet(10)
	created = server.create_match()
	mid = str(created["matchId"])
	a = server.join(mid, created["joinTokens"]["a"])
	b = server.join(mid, created["joinTokens"]["b"])
	pid_a = str(a["playerId"])
	pid_b = str(b["playerId"])
	server.apply_action(mid, pid_a, ActionIntent.select_hex(1, 1))
	server.apply_action(mid, pid_b, ActionIntent.select_hex(8, 6))
	server.apply_action(mid, pid_a, ActionIntent.start())
	server.test_now_ms = 100000
	var grace: Dictionary = server.start_grace(mid, pid_b, 23.0)
	var grace_snap: Snapshot = Snapshot.from_dict(server.get_snapshot(mid, pid_a))
	_expect(failed, grace_snap.in_grace(), "A4.3 snapshot in_grace")
	_expect(failed, grace_snap.grace_remaining_sec() >= 22.0 and grace_snap.grace_remaining_sec() <= 23.0, "A4.3 remaining ~23s")
	_expect(failed, Contract.format_grace_clock(23) == "0:23", "A4.3 clock 0:23")
	var rival_line := Contract.GRACE_RIVAL_COPY % "0:23"
	_expect(failed, rival_line.find("Waiting on rival") >= 0, "A4.3 waiting-on-rival copy")
	_expect(failed, rival_line.find("0:23") >= 0, "A4.3 countdown in rival copy")
	_expect(failed, rival_line.find("RIVAL  ") < 0, "A4.3 not turn-clock RIVAL")
	var hold_line := Contract.GRACE_HOLD_COPY % "0:23"
	_expect(failed, hold_line.find("Reconnect") >= 0, "A4.3 local HOLD is reconnect")
	_expect(failed, hold_line.find("HOLD  ") < 0, "A4.3 not turn-clock HOLD")
	server.test_now_ms = 100000 + Contract.FORFEIT_GRACE_SEC * 1000 + 50
	var after: Snapshot = Snapshot.from_dict(server.get_snapshot(mid, pid_a))
	_expect(failed, after.status() == Contract.STATUS_ENDED, "A4.2 grace silence ended")
	_expect(failed, after.is_forfeit(), "A4.2 endReason forfeit")
	_expect(failed, str(after.winner()) == "a", "A4.2 remaining wins")
	_expect(failed, after.you_marks() == 10 + Contract.MARKS_FORFEIT_WIN, "A4.2 remaining +15")
	_expect(failed, after.rematch_offered(), "A4.4 rematch after timeout forfeit")
	_expect(failed, bool(grace.get("ok", false)), "A4.3 start_grace ok")


func _end_summary_case(failed: PackedStringArray) -> void:
	## M.1–M.3: kill / forfeit / standoff chrome + table Δ + rematch still offered.
	var kill_win := {
		"status": "ended",
		"winner": "a",
		"endReason": "kill",
		"kind": "pvp",
		"you": {"seat": "a", "marks": 32},
		"rematch": {"status": "waiting", "youAccepted": false, "opponentAccepted": false},
	}
	var kill_lose := {
		"status": "ended",
		"winner": "a",
		"endReason": "kill",
		"kind": "pvp",
		"you": {"seat": "b", "marks": 4},
		"rematch": {"status": "waiting"},
	}
	var stand_a := {
		"status": "ended",
		"winner": "draw",
		"endReason": "standoff",
		"kind": "pvp",
		"you": {"seat": "a", "marks": 10},
		"rematch": {"status": "waiting"},
	}
	var stand_b := {
		"status": "ended",
		"winner": "draw",
		"endReason": "standoff",
		"kind": "pvp",
		"you": {"seat": "b", "marks": 10},
	}
	var foil_win := {
		"status": "ended",
		"winner": "b",
		"endReason": "forfeit",
		"kind": "pvp",
		"you": {"seat": "b", "marks": 15},
		"rematch": {"status": "waiting"},
	}
	var foil_leave := {
		"status": "ended",
		"winner": "b",
		"endReason": "forfeit",
		"kind": "pvp",
		"you": {"seat": "a", "marks": 0},
	}
	_expect(failed, MarksPayout.table_delta(kill_win, "a") == 32, "M.2 kill winner +32")
	_expect(failed, MarksPayout.table_delta(kill_lose, "b") == 4, "M.2 kill loser +4")
	_expect(failed, MarksPayout.table_delta(stand_a, "a") == 10, "M.2 standoff A +10")
	_expect(failed, MarksPayout.table_delta(stand_b, "b") == 10, "M.2 standoff B +10")
	_expect(failed, MarksPayout.table_delta(foil_win, "b") == 15, "M.2 forfeit remaining +15")
	_expect(failed, MarksPayout.table_delta(foil_leave, "a") == 0, "M.2 forfeit leaver 0")
	var ow := MarksPayout.end_overlay(kill_win, "a", false)
	_expect(failed, ow.find("MARK CONFIRMED") >= 0, "M.1 kill winner headline")
	_expect(failed, ow.find("+32  ·  ★32") >= 0, "M.1 kill winner marks line")
	_expect(failed, ow.find("+25 MARK") < 0 and ow.find("Δ+") < 0 and ow.find("0+") < 0, "M.1 no glued delta")
	_expect(failed, ow.find("\nkill") >= 0, "M.1 kill winner reason")
	var ol := MarksPayout.end_overlay(kill_lose, "b", false)
	_expect(failed, ol.find("ELIMINATED") >= 0, "M.1 kill loser headline")
	_expect(failed, ol.find("+4  ·  ★4") >= 0, "M.1 kill loser marks line")
	_expect(failed, ol.find("\nkill") >= 0, "M.1 kill loser reason is kill not loss")
	var os := MarksPayout.end_overlay(stand_a, "a", false)
	_expect(failed, os.find("STANDOFF") >= 0, "M.1 standoff headline")
	_expect(failed, os.find("+10  ·  ★10") >= 0, "M.1 standoff marks line")
	_expect(failed, os.find("\nstandoff") >= 0, "M.1 standoff reason")
	_expect(failed, MarksPayout.end_overlay(stand_b, "b", false).find("+10  ·  ★10") >= 0, "M.1 standoff both seats")
	var of := MarksPayout.end_overlay(foil_win, "b", false)
	_expect(failed, of.find("RIVAL FORFEIT") >= 0, "M.1 remaining headline")
	_expect(failed, of.find("+15  ·  ★15") >= 0, "M.1 remaining marks line")
	_expect(failed, of.find("\nforfeit") >= 0, "M.1 remaining reason")
	var ox := MarksPayout.end_overlay(foil_leave, "a", false)
	_expect(failed, ox.find("FORFEIT") >= 0 and ox.find("RIVAL") < 0, "M.1 leaver headline")
	_expect(failed, ox.find("0  ·  ★0") >= 0 and ox.find("+0") < 0, "M.1 leaver chip is 0")
	_expect(failed, Snapshot.from_dict(kill_win).rematch_offered(), "M.3 kill rematch offered")
	_expect(failed, Snapshot.from_dict(foil_win).rematch_offered(), "M.3 forfeit rematch offered")
	_expect(failed, Snapshot.from_dict(stand_a).rematch_offered(), "M.3 standoff rematch offered")
	_expect(failed, Contract.REMATCH_PLAY_COPY == "PLAY AGAIN", "M.3 Play again copy")
	_expect(failed, Contract.REMATCH_DECLINE_COPY == "DECLINE", "M.3 Decline copy")
	_expect(failed, Contract.REMATCH_SETTLED_COPY == "Marks already settled.", "M.3 settled copy")

	## Mock settle: both seats + rematch still works after overlay Δ.
	server.clear_all()
	server.reset_wallet(0)
	var hunt: Dictionary = _play_pvp_kill()
	var mid := str(hunt["matchId"])
	var winner_snap: Snapshot = Snapshot.from_dict(server.get_snapshot(mid, hunt["pidA"]))
	var loser_snap: Snapshot = Snapshot.from_dict(server.get_snapshot(mid, hunt["pidB"]))
	_expect(failed, winner_snap.table_marks_delta() == 32, "M.2 mock kill winner table")
	_expect(failed, loser_snap.table_marks_delta() == 4, "M.2 mock kill loser table")
	_expect(failed, winner_snap.rematch_offered() and loser_snap.rematch_offered(), "M.3 rematch after kill")
	var accept: Dictionary = server.rematch(mid, str(hunt["pidA"]), true)
	_expect(failed, bool(accept.get("ok", false)), "M.3 Play again still posts")
	_expect(failed, str(accept.get("status", "")) == Contract.REMATCH_WAITING, "M.3 rematch waiting")
	var no: Dictionary = server.rematch(mid, str(hunt["pidB"]), false)
	_expect(failed, str(no.get("rematch", {}).get("status", "")) == Contract.REMATCH_DECLINED, "M.3 Decline still hideout")

	server.clear_all()
	server.reset_wallet(0)
	var created: Dictionary = server.create_match()
	mid = str(created["matchId"])
	var a: Dictionary = server.join(mid, created["joinTokens"]["a"])
	var b: Dictionary = server.join(mid, created["joinTokens"]["b"])
	server.apply_action(mid, a["playerId"], ActionIntent.select_hex(2, 2))
	server.apply_action(mid, b["playerId"], ActionIntent.select_hex(7, 5))
	server.apply_action(mid, a["playerId"], ActionIntent.start())
	var stand: Dictionary = server.force_standoff(mid, a["playerId"])
	var stand_snap: Snapshot = Snapshot.from_dict(stand.get("snapshot", {}))
	_expect(failed, stand_snap.status() == Contract.STATUS_ENDED, "M.1 force standoff ended")
	_expect(failed, stand_snap.table_marks_delta() == 10, "M.2 force standoff +10")
	_expect(failed, MarksPayout.end_overlay(stand_snap.raw, "a", false).find("STANDOFF") >= 0, "M.1 force standoff chrome")
	_expect(failed, stand_snap.rematch_offered(), "M.3 standoff rematch")
	var hide: Dictionary = server.rematch(mid, a["playerId"], false)
	_expect(failed, str(hide.get("rematch", {}).get("status", "")) == Contract.REMATCH_DECLINED, "M.3 standoff Decline")


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
	_expect(failed, overlay.find("+32  ·  ★12") >= 0 and overlay.find("+1") < 0, "end overlay table Δ not payload 1")
	_expect(failed, overlay.find("★12") >= 0, "end overlay balance")
	_expect(failed, MarksPayout.live_delta_drifts(live_body["snapshot"], "a", false), "payload 1 drifts vs table +32")
	var forfeit_snap := {
		"status": "ended",
		"winner": "a",
		"endReason": "forfeit",
		"you": {"seat": "a", "marks": 8},
		"payout": {"marks": 8, "marksDelta": 1, "reason": "forfeit"},
	}
	var foil := MarksPayout.end_overlay(forfeit_snap, "a", false)
	_expect(failed, foil.find("RIVAL FORFEIT") >= 0, "forfeit winner chrome")
	_expect(failed, foil.find("+15  ·  ★8") >= 0, "forfeit plate +15 not payload 1")
	var old_forfeit := {
		"status": "ended",
		"winner": "a",
		"endReason": "forfeit",
		"you": {"seat": "a", "marks": 12},
		"payout": {"marks": 12, "marksDelta": 12, "reason": "forfeit"},
	}
	var old_plate := MarksPayout.end_overlay(old_forfeit, "a", false)
	_expect(failed, old_plate.find("RIVAL FORFEIT") >= 0, "old forfeit still rival forfeit")
	_expect(failed, old_plate.find("+15  ·  ★12") >= 0, "forfeit plate +15 when payload still +12")
	_expect(failed, old_plate.find("+12") < 0, "forfeit plate does not paint old +12")
	var you_forfeit := MarksPayout.end_overlay({"endReason": "disconnect", "winner": "b", "you": {"seat": "a", "marks": 7}}, "a", false)
	_expect(failed, you_forfeit.find("FORFEIT") >= 0, "disconnect loser chrome")
	var job_win := MarksPayout.end_overlay({"winner": "a", "payout": {"marks": 5, "marksDelta": 1, "reason": "job"}}, "a", true)
	_expect(failed, job_win.find("JOB COMPLETE") >= 0, "job win chrome")
	_expect(failed, job_win.find("job") >= 0, "job win reason")
	var live_ended := {
		"status": "ended",
		"winner": "a",
		"kind": "pvp",
		"endReason": "kill",
		"you": {"seat": "a", "marks": 32},
	}
	var live_copy := MarksPayout.end_overlay(live_ended, "a", false)
	_expect(failed, live_copy.find("MARK CONFIRMED") >= 0, "live endReason kill")
	_expect(failed, live_copy.find("★32") >= 0, "live you.marks balance")
	_expect(failed, live_copy.find("+32  ·  ★32") >= 0, "table Δ when marksDelta omitted")
	_expect(failed, live_copy.find("table  +") < 0, "no table +N chrome")
	_expect(failed, live_copy.find("kill") >= 0, "pvp keeps kill")
	_expect(failed, not MarksPayout.live_delta_drifts(live_ended, "a", false), "LIVE omit marksDelta is not drift")
	var sp_live_kill := {
		"status": "ended",
		"winner": "a",
		"kind": "sp_job",
		"endReason": "kill",
		"job": {"jobId": "j_x", "tier": 1, "name": "Rooftop Rookie"},
		"you": {"seat": "a", "marks": 12},
	}
	var sp_copy := MarksPayout.end_overlay(sp_live_kill, "a", true)
	_expect(failed, sp_copy.find("JOB COMPLETE") >= 0, "sp kill maps headline")
	_expect(failed, sp_copy.find("job") >= 0, "sp kill displays reason job")
	_expect(failed, sp_copy.find("kill") < 0, "sp kill not shown as kill")
	_expect(failed, sp_copy.find("★12") >= 0, "sp overlay uses you.marks")
	_expect(failed, sp_copy.find("+12  ·  ★12") >= 0, "sp table Δ uses job row")
	_expect(failed, MarksPayout.display_reason(sp_live_kill, true) == Contract.END_JOB, "display_reason kill->job")
	var sp_delta := {
		"status": "ended",
		"winner": "a",
		"kind": "sp_job",
		"endReason": "kill",
		"you": {"seat": "a", "marks": 34},
		"payout": {"marks": 34, "marksDelta": 10, "reason": "kill"},
	}
	var sp_delta_copy := MarksPayout.end_overlay(sp_delta, "a", true)
	_expect(failed, sp_delta_copy.find("+12  ·  ★34") >= 0, "sp delta from you.marks envelope")
	_expect(failed, sp_delta_copy.find("★34") >= 0, "sp delta balance you.marks")
	_expect(failed, sp_delta_copy.find("\njob") >= 0, "sp delta reason job")
	_expect(failed, sp_delta_copy.find("kill") < 0, "sp delta not kill")
	var sp_loss := {
		"status": "ended",
		"winner": "b",
		"kind": "sp_job",
		"endReason": "kill",
		"you": {"seat": "a", "marks": 24},
	}
	_expect(failed, MarksPayout.display_reason(sp_loss, true) == Contract.END_JOB_FAIL, "sp loss kill->job_fail")
	_expect(failed, MarksPayout.table_delta(sp_loss, "a", true) == 2, "sp loss T1 fail +2")
	_expect(failed, MarksPayout.end_overlay(sp_loss, "a", true).find("+2  ·  ★24") >= 0, "sp loss chip +2")
	var sp_fail_t2 := {
		"status": "ended",
		"winner": "b",
		"kind": "sp_job",
		"endReason": "kill",
		"job": {"tier": 2},
		"you": {"seat": "a", "marks": 3},
	}
	var sp_fail_t3 := {
		"status": "ended",
		"winner": "b",
		"kind": "sp_job",
		"endReason": "kill",
		"jobTier": 3,
		"you": {"seat": "a", "marks": 3},
	}
	_expect(failed, MarksPayout.table_delta(sp_fail_t2, "a", true) == 3, "sp loss T2 fail +3")
	_expect(failed, MarksPayout.end_overlay(sp_fail_t2, "a", true).find("+3  ·  ★3") >= 0, "sp loss T2 chip +3")
	_expect(failed, MarksPayout.table_delta(sp_fail_t3, "a", true) == 3, "sp loss T3 fail +3")
	_expect(failed, MarksPayout.end_overlay(sp_fail_t3, "a", true).find("+3  ·  ★3") >= 0, "sp loss T3 chip +3")


func _job_case(failed: PackedStringArray) -> void:
	server.clear_all()
	server.reset_wallet(10)
	var job: Dictionary = server.create_job(1)
	_expect(failed, str(job.get("name", "")) == Contract.JOB_NAME_T1, "job T1 name")
	_expect(failed, str(job.get("snapshot", {}).get("kind", "")) == Contract.MODE_SP_JOB, "job snapshot.kind")
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
	_expect(failed, snap.marks_delta() == Contract.MARKS_JOB_T1, "job T1 marksDelta +12")
	_expect(failed, snap.you_marks() == 22, "job wallet from server")
	_expect(failed, server.account_marks == 22, "mock ledger not client +=")
	server.clear_all()
	server.reset_wallet(0)
	created = server.create_match({"mode": "sp_job", "jobTier": 3})
	mid = str(created["matchId"])
	a = server.join(mid, created["joinTokens"]["a"])
	b = server.join(mid, created["joinTokens"]["b"])
	server.apply_action(mid, a["playerId"], ActionIntent.select_hex(2, 2))
	server.apply_action(mid, b["playerId"], ActionIntent.select_hex(7, 5))
	server.apply_action(mid, a["playerId"], ActionIntent.start())
	r = server.apply_action(mid, a["playerId"], ActionIntent.attack(7, 5))
	snap = Snapshot.from_dict(r.snapshot)
	_expect(failed, snap.marks_delta() == Contract.MARKS_JOB_T3, "job T3 marksDelta +24")
	_job_ladder_case(failed)


func _job_ladder_case(failed: PackedStringArray) -> void:
	## J1–J4 mock: T1/T2/T3 complete bind you.marks; same clientJobId does not grant again.
	_expect(failed, Contract.job_row_label(1) == "T1  Rooftop Rookie", "J5 T1 row label")
	_expect(failed, Contract.job_row_label(2) == "T2  Warehouse Watch", "J5 T2 row label")
	_expect(failed, Contract.job_row_label(3) == "T3  Night Contract", "J5 T3 row label")
	_expect(failed, Contract.job_tier_delta(1) == 12, "J1 table T1 ★12")
	_expect(failed, Contract.job_tier_delta(2) == 18, "J2 table T2 ★18")
	_expect(failed, Contract.job_tier_delta(3) == 24, "J3 table T3 ★24")
	_expect(failed, Contract.job_tier_fail_delta(1) == 2, "J1 fail T1 +2")
	_expect(failed, Contract.job_tier_fail_delta(2) == 3, "J2 fail T2 +3")
	_expect(failed, Contract.job_tier_fail_delta(3) == 3, "J3 fail T3 +3")
	_expect(failed, Contract.MARKS_JOB_T3 < Contract.MARKS_PVP_WIN, "SP max win under PvP kill")
	_expect(failed, Contract.MARKS_PRACTICE == 0, "Practice Δ0")
	server.clear_all()
	server.reset_wallet(0)
	var session = SessionScript.new()
	session.bind_marks(999)
	var j1: Dictionary = server.complete_job(1, "job-j1")
	session.apply_snapshot(j1.get("snapshot", {}))
	_expect(failed, session.marks == 12, "J1 snapshot you.marks 0→12 (not 999+)")
	_expect(failed, server.account_marks == 12, "J1 mock ledger +12")
	var j2: Dictionary = server.complete_job(2, "job-j2")
	session.apply_snapshot(j2.get("snapshot", {}))
	_expect(failed, session.marks == 30, "J2 snapshot you.marks 12→30")
	var j3: Dictionary = server.complete_job(3, "job-j3")
	session.apply_snapshot(j3.get("snapshot", {}))
	_expect(failed, session.marks == 54, "J3 snapshot you.marks 30→54")
	var replay: Dictionary = server.complete_job(3, "job-j3")
	session.bind_marks(999)
	session.apply_snapshot(replay.get("snapshot", {}))
	_expect(failed, server.account_marks == 54, "J4 same clientJobId no second grant")
	_expect(failed, session.marks == 54, "J4 replay binds snapshot 54 (never marks +=)")
	_expect(failed, str(replay.get("jobId", "")) == str(j3.get("jobId", "")), "J4 replay same jobId")
	for tier in [1, 2, 3]:
		var expect_n := Contract.job_tier_fail_delta(tier)
		server.clear_all()
		server.reset_wallet(0)
		var fail_job: Dictionary = server.create_job(tier)
		var fail_end: Dictionary = server.force_end(str(fail_job.get("matchId", "")), Contract.SEAT_B, Contract.END_KILL)
		var fail_snap: Snapshot = Snapshot.from_dict(fail_end.get("snapshot", {}))
		_expect(failed, fail_snap.marks_delta() == expect_n, "mock T%d fail marksDelta" % tier)
		_expect(failed, fail_snap.you_marks() == expect_n, "mock T%d fail wallet" % tier)
		_expect(failed, MarksPayout.table_delta(fail_snap.raw, Contract.SEAT_A, true) == expect_n, "mock T%d fail table" % tier)
		var fail_chip := MarksPayout.marks_line(fail_snap.raw, Contract.SEAT_A, true)
		_expect(failed, fail_chip == "%s  ·  ★%d" % [Contract.format_marks_delta(expect_n), expect_n], "mock T%d fail chip" % tier)
		var fail_row: Dictionary = server.get_journal(str(fail_job.get("playerId", "")))["entries"][0]
		_expect(failed, int(fail_row.get("marksDelta", -1)) == expect_n, "mock T%d fail journal Δ" % tier)
		_expect(failed, Journal.marks_text(fail_row) == Contract.format_marks_delta(expect_n), "mock T%d fail journal chip" % tier)
	session.free()


func _shop_case(failed: PackedStringArray) -> void:
	## S1–S4: catalog, buy snapshot bind, insufficient reject, visual equip. No combat delta.
	server.clear_all()
	server.reset_wallet(Contract.MOCK_WALLET_STUB)
	var catalog: Dictionary = server.get_shop()
	var listed = Shop.from_any(catalog)
	_expect(failed, listed.item_id() == Contract.SHOP_STUB_ITEM_ID, "S1 shop stub itemId")
	_expect(failed, listed.price() == Contract.SHOP_STUB_PRICE, "S1 GD price 50")
	_expect(failed, listed.price() == 50, "S1 catalog price is 50 not 40")
	_expect(failed, listed.has_item(Contract.SHOP_BANDANA_ITEM_ID), "S1 catalog includes bandana")
	_expect(failed, listed.price_of(Contract.SHOP_BANDANA_ITEM_ID) == Contract.SHOP_BANDANA_PRICE, "S1 bandana ★100")
	_expect(failed, listed.has_item(Contract.SHOP_POSTER_ITEM_ID), "S1 catalog includes poster")
	_expect(failed, listed.price_of(Contract.SHOP_POSTER_ITEM_ID) == Contract.SHOP_POSTER_PRICE, "S1 poster ★150")
	_expect(failed, listed.balance() == Contract.MOCK_WALLET_STUB, "S1 you.marks stub 24")
	_expect(failed, not listed.owns_stub(), "S1 not owned yet")
	_expect(failed, not listed.can_afford(), "S3 ★24 cannot afford ★50")
	_expect(failed, Shop.row_action_text(false) == "BUY", "P2 unaffordable action is BUY")
	_expect(failed, Shop.row_status_text(false, false) == Contract.SHOP_INSUFFICIENT_COPY, "P2 BUY status insufficient")
	_expect(failed, not Shop.row_buy_enabled(false, false), "P2 BUY disabled when Marks < price")
	_expect(failed, Shop.row_action_text(true) == "EQUIP", "P2 owned action is EQUIP")
	_expect(failed, Shop.row_action_text(true, true) == "EQUIPPED", "P2 wearing action is EQUIPPED")
	_expect(failed, Shop.row_status_text(true, true) == Contract.SHOP_OWNED_COPY, "P2 owned copy visual only")
	_expect(failed, Shop.row_status_text(true, true, true) == Contract.SHOP_EQUIPPED_COPY, "P2 wearing copy")
	_expect(failed, not Contract.SHOP_EQUIPPED_COPY.begins_with("Bought"), "P2 wearing line is not Bought stack")
	_expect(failed, Shop.row_buy_enabled(true, false), "P2 OWNED stays clickable to toggle plate")
	_expect(failed, Contract.RECON_BASE == 0.35 and Contract.MARKS_PVP_WIN == 32, "S4 combat table ★32")

	var session = SessionScript.new()
	session.apply_shop(catalog)
	_expect(failed, session.marks == 24, "S1 session binds you.marks")
	var before: int = session.marks
	var poor: Dictionary = server.buy_shop(Contract.SHOP_STUB_ITEM_ID, Contract.new_client_buy_id())
	var poor_shop = Shop.from_any(poor)
	_expect(failed, not bool(poor.get("ok", true)), "S3 buy rejected")
	_expect(failed, poor_shop.is_insufficient(), "S3 insufficient_marks")
	_expect(failed, server.account_marks == before, "S3 mock ledger unchanged")
	session.bind_marks(999)
	session.apply_shop(poor)
	_expect(failed, session.marks == before, "S3 apply_shop replaces 999 with snapshot 24")
	_expect(failed, session.marks == server.account_marks, "S3 never marks -= on client")

	var buy_id := "00000000-0000-4000-8000-0000000000aa"
	server.reset_wallet(80)
	session.apply_shop(server.get_shop())
	_expect(failed, session.marks == 80, "S2 seeded wallet from snapshot")
	var bought: Dictionary = server.buy_shop(Contract.SHOP_STUB_ITEM_ID, buy_id)
	_expect(failed, bool(bought.get("ok", false)), "S2 buy ok")
	session.bind_marks(80)
	session.apply_shop(bought)
	_expect(failed, session.marks == 30, "S2 you.marks 80-50 from snapshot")
	_expect(failed, server.account_marks == 30, "S2 mock ledger debited once")
	_expect(failed, session.owns_cosmetic(Contract.SHOP_STUB_ITEM_ID), "S2 owned")
	_expect(failed, session.is_equipped(Contract.SHOP_STUB_ITEM_ID), "S2 auto-equipped")
	_expect(failed, session.ghillie, "S4 ghillie visual flag from equipped")
	var replay: Dictionary = server.buy_shop(Contract.SHOP_STUB_ITEM_ID, buy_id)
	_expect(failed, bool(replay.get("ok", false)), "S2 clientBuyId idempotent ok")
	_expect(failed, server.account_marks == 30, "S2 replay does not debit again")
	session.apply_shop(replay)
	_expect(failed, session.marks == 30, "S2 replay snapshot still 30")
	var second: Dictionary = server.buy_shop(Contract.SHOP_STUB_ITEM_ID, Contract.new_client_buy_id())
	_expect(failed, str(second.get("error", "")) == Contract.SHOP_ERR_ALREADY_OWNED, "S2 second id already_owned")
	_expect(failed, server.account_marks == 30, "S2 already_owned no debit")

	var unequip: Dictionary = server.equip_cosmetic("")
	session.apply_shop(unequip)
	_expect(failed, session.owns_cosmetic(Contract.SHOP_STUB_ITEM_ID), "S4 still owned")
	_expect(failed, not session.ghillie, "S4 unequip teal jacket")
	var equip: Dictionary = server.equip_cosmetic(Contract.SHOP_STUB_ITEM_ID)
	session.apply_shop(equip)
	_expect(failed, session.ghillie, "S4 re-equip ghillie recolor")
	_expect(failed, session.marks == 30, "S4 equip does not touch marks")
	session.free()


func _live_shop_shape_case(failed: PackedStringArray) -> void:
	## LIVE Coder shape (2026-09-19): catalog `id`, buy `{ ok, you.marks, purchaseId, item }`.
	## Client binds snapshot you.marks only — never local marks -=.
	var catalog = Shop.from_any({
		"items": [{"id": "skin_hideout_stub", "name": "Hideout Skin (stub)", "price": 50, "kind": "skin"}],
	})
	_expect(failed, catalog.item_id() == Contract.SHOP_STUB_ITEM_ID, "LIVE catalog id → itemId")
	_expect(failed, catalog.item_id() == "skin_hideout_stub", "LIVE itemId skin_hideout_stub")
	_expect(failed, catalog.price() == Contract.SHOP_STUB_PRICE, "LIVE catalog price 50")
	_expect(failed, not catalog.has_marks(), "LIVE GET /shop has no you.marks")

	var session = SessionScript.new()
	session.bind_marks(999)
	session.apply_shop({
		"error": Contract.SHOP_ERR_INSUFFICIENT,
		"code": Contract.SHOP_ERR_INSUFFICIENT,
		"you": {"marks": 24},
		"status": 402,
	})
	_expect(failed, session.marks == 24, "S2 LIVE 402 binds you.marks (replaces 999)")
	_expect(failed, session.marks != 949, "S2 never local marks -= on 402")
	_expect(failed, not session.owns_cosmetic(Contract.SHOP_STUB_ITEM_ID), "S2 402 does not grant owned")

	session.bind_marks(80)
	session.apply_shop({
		"ok": true,
		"you": {"marks": 30},
		"purchaseId": "pur_shape",
		"item": {"id": "skin_hideout_stub", "name": "Hideout Skin (stub)", "price": 50, "kind": "skin"},
		"status": 200,
	})
	_expect(failed, session.marks == 30, "S1 LIVE buy binds you.marks 80→30 from snapshot")
	_expect(failed, session.owns_cosmetic("skin_hideout_stub"), "S1 owned from item.id")
	_expect(failed, session.ghillie, "S1 last buy auto-equips visual")
	session.bind_marks(999)
	session.apply_shop({
		"ok": true,
		"you": {"marks": 30},
		"purchaseId": "pur_shape",
		"item": {"id": "skin_hideout_stub", "price": 50, "kind": "skin"},
		"status": 200,
	})
	_expect(failed, session.marks == 30, "S3 replay snapshot still 30 (no second debit locally)")
	session.free()


func _shop_sink2_case(failed: PackedStringArray) -> void:
	## S2.1–S2.4: BANDANA RECOLOR ★100, same spine as ghillie. No combat delta.
	server.clear_all()
	server.reset_wallet(Contract.MOCK_WALLET_STUB)
	var catalog: Dictionary = server.get_shop()
	var listed = Shop.from_any(catalog)
	_expect(failed, listed.has_item(Contract.SHOP_STUB_ITEM_ID), "S2.1 catalog still has ghillie")
	_expect(failed, listed.has_item(Contract.SHOP_BANDANA_ITEM_ID), "S2.1 catalog has bandana")
	_expect(failed, listed.price_of(Contract.SHOP_BANDANA_ITEM_ID) == 100, "S2.1 GD price 100")
	_expect(failed, listed.name_of(Contract.SHOP_BANDANA_ITEM_ID) == Contract.SHOP_BANDANA_ITEM_NAME, "S2.1 name BANDANA RECOLOR")
	_expect(failed, not listed.can_afford() or listed.balance() < 100, "S2.2 ★24 cannot afford ★100")
	_expect(failed, not Shop.row_buy_enabled(false, listed.balance() >= 100), "S2.2 BUY disabled when Marks < 100")
	_expect(failed, Contract.RECON_BASE == 0.35 and Contract.MARKS_PVP_WIN == 32, "S2.4 combat table ★32")

	var lagged = Shop.from_any(Contract.merge_live_shop_catalog({
		"items": [{"id": "skin_hideout_stub", "name": "Hideout Skin (stub)", "price": 50, "kind": "skin"}],
	}))
	_expect(failed, lagged.has_item(Contract.SHOP_BANDANA_ITEM_ID), "LIVE lag merge appends bandana")
	_expect(failed, lagged.price_of(Contract.SHOP_STUB_ITEM_ID) == 50, "LIVE lag keeps Coder ghillie price")
	var live_two = Shop.from_any(Contract.merge_live_shop_catalog({
		"items": [
			{"id": "skin_hideout_stub", "name": "Hideout Skin (stub)", "price": 50, "kind": "skin"},
			{"id": "skin_bandana_stub", "name": "Bandana Skin (stub)", "price": 100, "kind": "skin"},
		],
	}))
	_expect(failed, live_two.name_of(Contract.SHOP_BANDANA_ITEM_ID) == "Bandana Skin (stub)", "prefer LIVE bandana name")
	_expect(failed, live_two.has_item(Contract.SHOP_POSTER_ITEM_ID), "LIVE two-SKU merge appends poster")
	_expect(failed, live_two.has_item(Contract.GUN_RAILFRAME), "LIVE two-SKU merge appends gun SKUs")
	_expect(failed, live_two.items.size() == 12, "LIVE two-SKU merge keeps skins, guns, and T1+T2 parts")

	var session = SessionScript.new()
	session.apply_shop(catalog)
	_expect(failed, session.marks == 24, "S2.2 session binds you.marks")
	var before: int = session.marks
	var poor: Dictionary = server.buy_shop(Contract.SHOP_BANDANA_ITEM_ID, Contract.new_client_buy_id())
	var poor_shop = Shop.from_any(poor)
	_expect(failed, not bool(poor.get("ok", true)), "S2.2 buy rejected")
	_expect(failed, poor_shop.is_insufficient(), "S2.2 insufficient_marks")
	_expect(failed, server.account_marks == before, "S2.2 mock ledger unchanged")
	session.bind_marks(999)
	session.apply_shop(poor)
	_expect(failed, session.marks == before, "S2.2 apply_shop replaces 999 with snapshot 24")
	_expect(failed, session.marks == server.account_marks, "S2.2 never marks -= on client")

	var buy_id := "00000000-0000-4000-8000-0000000000bb"
	server.reset_wallet(180)
	session.apply_shop(server.get_shop())
	_expect(failed, session.marks == 180, "S2.1 seeded wallet from snapshot")
	var bought: Dictionary = server.buy_shop(Contract.SHOP_BANDANA_ITEM_ID, buy_id)
	_expect(failed, bool(bought.get("ok", false)), "S2.1 buy ok")
	session.bind_marks(180)
	session.apply_shop(bought)
	_expect(failed, session.marks == 80, "S2.1 you.marks 180-100 from snapshot")
	_expect(failed, server.account_marks == 80, "S2.1 mock ledger debited once")
	_expect(failed, session.owns_cosmetic(Contract.SHOP_BANDANA_ITEM_ID), "S2.1 owned bandana")
	_expect(failed, session.is_equipped(Contract.SHOP_BANDANA_ITEM_ID), "S2.1 auto-equipped")
	_expect(failed, session.bandana, "S2.4 bandana visual flag from equipped")
	_expect(failed, not session.ghillie, "S2.4 ghillie off when bandana equipped")
	var replay: Dictionary = server.buy_shop(Contract.SHOP_BANDANA_ITEM_ID, buy_id)
	_expect(failed, bool(replay.get("ok", false)), "S2.3 clientBuyId idempotent ok")
	_expect(failed, server.account_marks == 80, "S2.3 replay does not debit again")
	session.apply_shop(replay)
	_expect(failed, session.marks == 80, "S2.3 replay snapshot still 80")
	var second: Dictionary = server.buy_shop(Contract.SHOP_BANDANA_ITEM_ID, Contract.new_client_buy_id())
	_expect(failed, str(second.get("error", "")) == Contract.SHOP_ERR_ALREADY_OWNED, "S2.3 second id already_owned")
	_expect(failed, server.account_marks == 80, "S2.3 already_owned no debit")

	var ghillie: Dictionary = server.buy_shop(Contract.SHOP_STUB_ITEM_ID, Contract.new_client_buy_id())
	_expect(failed, bool(ghillie.get("ok", false)), "S2.1 still can buy ghillie after bandana")
	session.apply_shop(ghillie)
	_expect(failed, session.marks == 30, "S2.1 80-50 ghillie from snapshot")
	_expect(failed, session.owns_cosmetic(Contract.SHOP_STUB_ITEM_ID), "S2.1 owns both")
	_expect(failed, session.owns_cosmetic(Contract.SHOP_BANDANA_ITEM_ID), "S2.1 bandana still owned")
	_expect(failed, session.ghillie, "S2.4 last buy auto-equips ghillie")
	_expect(failed, not session.bandana, "S2.4 one equipped at a time")

	var unequip: Dictionary = server.equip_cosmetic("")
	session.apply_shop(unequip)
	_expect(failed, session.owns_cosmetic(Contract.SHOP_BANDANA_ITEM_ID), "S2.4 still owned")
	_expect(failed, not session.bandana and not session.ghillie, "S2.4 unequip chrome")
	var equip: Dictionary = server.equip_cosmetic(Contract.SHOP_BANDANA_ITEM_ID)
	session.apply_shop(equip)
	_expect(failed, session.bandana, "S2.4 re-equip bandana chrome")
	_expect(failed, session.marks == 30, "S2.4 equip does not touch marks")
	_expect(failed, not session.ghillie, "S2.4 bandana plate not ghillie")

	## LIVE 200 infers item.id — merge owned, never wipe the other SKU.
	session.bind_marks(130)
	session.apply_shop({
		"ok": true,
		"you": {"marks": 30},
		"purchaseId": "pur_bandana",
		"item": {"id": "skin_bandana_stub", "name": "BANDANA RECOLOR", "price": 100, "kind": "skin"},
		"status": 200,
	})
	_expect(failed, session.marks == 30, "S2.1 LIVE buy binds you.marks 130→30")
	_expect(failed, session.owns_cosmetic(Contract.SHOP_BANDANA_ITEM_ID), "S2.1 LIVE owned from item.id")
	_expect(failed, session.owns_cosmetic(Contract.SHOP_STUB_ITEM_ID), "S2.1 LIVE buy does not wipe ghillie")
	_expect(failed, session.bandana, "S2.4 LIVE last buy auto-equips bandana")
	session.free()


func _shop_sink3_case(failed: PackedStringArray) -> void:
	## S3.1–S3.5: HIDEOUT POSTER ★150, same spine as ghillie / bandana. No combat delta.
	server.clear_all()
	server.reset_wallet(Contract.MOCK_WALLET_STUB)
	var catalog: Dictionary = server.get_shop()
	var listed = Shop.from_any(catalog)
	_expect(failed, listed.has_item(Contract.SHOP_STUB_ITEM_ID), "S3.1 catalog still has ghillie")
	_expect(failed, listed.has_item(Contract.SHOP_BANDANA_ITEM_ID), "S3.1 catalog still has bandana")
	_expect(failed, listed.has_item(Contract.SHOP_POSTER_ITEM_ID), "S3.1 catalog has poster")
	_expect(failed, listed.price_of(Contract.SHOP_POSTER_ITEM_ID) == 150, "S3.1 GD price 150")
	_expect(failed, listed.name_of(Contract.SHOP_POSTER_ITEM_ID) == Contract.SHOP_POSTER_ITEM_NAME, "S3.1 name HIDEOUT POSTER")
	_expect(failed, listed.items.size() == 12, "S3.6 catalog rows (skins + poster + guns + T1/T2 parts)")
	_expect(failed, listed.has_item(Contract.GUN_FIELDBOLT), "S3.6 Fieldbolt catalog row")
	_expect(failed, listed.balance() < 150, "S3.3 ★24 cannot afford ★150")
	_expect(failed, not Shop.row_buy_enabled(false, listed.balance() >= 150), "S3.3 BUY disabled when Marks < 150")
	_expect(failed, Contract.RECON_BASE == 0.35 and Contract.MARKS_PVP_WIN == 32, "S3.5 combat table ★32")

	var lagged = Shop.from_any(Contract.merge_live_shop_catalog({
		"items": [
			{"id": "skin_hideout_stub", "name": "Hideout Skin (stub)", "price": 50, "kind": "skin"},
			{"id": "skin_bandana_stub", "name": "BANDANA RECOLOR", "price": 100, "kind": "skin"},
		],
	}))
	_expect(failed, lagged.has_item(Contract.SHOP_POSTER_ITEM_ID), "LIVE lag merge appends poster")
	_expect(failed, lagged.price_of(Contract.SHOP_BANDANA_ITEM_ID) == 100, "LIVE lag keeps Coder bandana price")
	var live_three = Shop.from_any(Contract.merge_live_shop_catalog({
		"items": [
			{"id": "skin_hideout_stub", "name": "Hideout Skin (stub)", "price": 50, "kind": "skin"},
			{"id": "skin_bandana_stub", "name": "Bandana Skin (stub)", "price": 100, "kind": "skin"},
			{"id": "decor_poster_stub", "name": "Hideout Poster (stub)", "price": 150, "kind": "decor"},
		],
	}))
	_expect(failed, live_three.name_of(Contract.SHOP_POSTER_ITEM_ID) == "Hideout Poster (stub)", "prefer LIVE poster name")
	_expect(failed, live_three.has_item(Contract.GUN_CRESCENT), "LIVE three-SKU merge appends gun SKUs")
	_expect(failed, live_three.items.size() == 12, "prefer LIVE names; append missing gun and T1/T2 part SKUs")

	var session = SessionScript.new()
	session.apply_shop(catalog)
	_expect(failed, session.marks == 24, "S3.3 session binds you.marks")
	var before: int = session.marks
	var poor: Dictionary = server.buy_shop(Contract.SHOP_POSTER_ITEM_ID, Contract.new_client_buy_id())
	var poor_shop = Shop.from_any(poor)
	_expect(failed, not bool(poor.get("ok", true)), "S3.3 buy rejected")
	_expect(failed, poor_shop.is_insufficient(), "S3.3 insufficient_marks")
	_expect(failed, server.account_marks == before, "S3.3 mock ledger unchanged")
	session.bind_marks(999)
	session.apply_shop(poor)
	_expect(failed, session.marks == before, "S3.3 apply_shop replaces 999 with snapshot 24")
	_expect(failed, session.marks == server.account_marks, "S3.3 never marks -= on client")
	_expect(failed, not session.poster, "S3.3 402 does not hang poster")

	var buy_id := "00000000-0000-4000-8000-0000000000cc"
	server.reset_wallet(200)
	session.apply_shop(server.get_shop())
	_expect(failed, session.marks == 200, "S3.2 seeded wallet from snapshot")
	var bought: Dictionary = server.buy_shop(Contract.SHOP_POSTER_ITEM_ID, buy_id)
	_expect(failed, bool(bought.get("ok", false)), "S3.2 buy ok")
	session.bind_marks(200)
	session.apply_shop(bought)
	_expect(failed, session.marks == 50, "S3.2 you.marks 200-150 from snapshot")
	_expect(failed, server.account_marks == 50, "S3.2 mock ledger debited once")
	_expect(failed, session.owns_cosmetic(Contract.SHOP_POSTER_ITEM_ID), "S3.2 owned poster")
	_expect(failed, session.is_equipped(Contract.SHOP_POSTER_ITEM_ID), "S3.2 auto-equippedDecorId")
	_expect(failed, session.equipped_decor == Contract.SHOP_POSTER_ITEM_ID, "S3.2 equippedDecorId poster")
	_expect(failed, session.equipped_cosmetic == "", "S3.2 poster buy does not write skin slot")
	_expect(failed, session.poster, "S3.4 poster wall flag from equippedDecorId")
	_expect(failed, not session.ghillie and not session.bandana, "S3.4 no suit until a skin is bought")
	var replay: Dictionary = server.buy_shop(Contract.SHOP_POSTER_ITEM_ID, buy_id)
	_expect(failed, bool(replay.get("ok", false)), "S3.2 clientBuyId idempotent ok")
	_expect(failed, server.account_marks == 50, "S3.2 replay does not debit again")
	session.apply_shop(replay)
	_expect(failed, session.marks == 50, "S3.2 replay snapshot still 50")
	var second: Dictionary = server.buy_shop(Contract.SHOP_POSTER_ITEM_ID, Contract.new_client_buy_id())
	_expect(failed, str(second.get("error", "")) == Contract.SHOP_ERR_ALREADY_OWNED, "S3.2 second id already_owned")
	_expect(failed, server.account_marks == 50, "S3.2 already_owned no debit")

	var ghillie: Dictionary = server.buy_shop(Contract.SHOP_STUB_ITEM_ID, Contract.new_client_buy_id())
	_expect(failed, bool(ghillie.get("ok", false)), "S3.2 still can buy ghillie after poster")
	session.apply_shop(ghillie)
	_expect(failed, session.marks == 0, "S3.2 50-50 ghillie from snapshot")
	_expect(failed, session.owns_cosmetic(Contract.SHOP_STUB_ITEM_ID), "S3.2 owns suit + poster")
	_expect(failed, session.owns_cosmetic(Contract.SHOP_POSTER_ITEM_ID), "S3.4 poster still owned")
	_expect(failed, session.poster, "S3.4 wall art stays when ghillie equipped")
	_expect(failed, session.ghillie, "S3.4 last skin buy auto-equips ghillie")
	_expect(failed, session.is_equipped(Contract.SHOP_POSTER_ITEM_ID), "S3.4 both slots: poster still equipped")
	_expect(failed, session.is_equipped(Contract.SHOP_STUB_ITEM_ID), "S3.4 both slots: ghillie equipped")

	var unequip_skin: Dictionary = server.equip_cosmetic("", "skin")
	session.apply_shop(unequip_skin)
	_expect(failed, session.owns_cosmetic(Contract.SHOP_POSTER_ITEM_ID), "S3.4 still owned after skin unequip")
	_expect(failed, session.poster, "S3.4 unequip skin leaves poster up")
	_expect(failed, not session.ghillie, "S3.4 skin slot cleared")
	_expect(failed, session.marks == 0, "S3.4 equip does not touch marks")
	var equip_skin: Dictionary = server.equip_cosmetic(Contract.SHOP_STUB_ITEM_ID, "skin")
	session.apply_shop(equip_skin)
	_expect(failed, session.ghillie and session.poster, "S3.4 re-equip skin keeps poster")
	var unequip_decor: Dictionary = server.equip_cosmetic("", "decor")
	session.apply_shop(unequip_decor)
	_expect(failed, session.ghillie and not session.poster, "S3.4 unequip decor leaves skin")
	_expect(failed, session.marks == 0, "S3.4 decor unequip marks unchanged")
	var equip_decor: Dictionary = server.equip_cosmetic(Contract.SHOP_POSTER_ITEM_ID, "decor")
	session.apply_shop(equip_decor)
	_expect(failed, session.is_equipped(Contract.SHOP_POSTER_ITEM_ID), "S3.4 re-equip poster chrome")
	_expect(failed, session.ghillie, "S3.4 poster equip does not overwrite skin")
	_expect(failed, session.marks == 0, "S3.4 re-equip marks unchanged")

	var parsed = Shop.from_any({
		"ok": true,
		"you": {
			"marks": 0,
			"equippedSkinId": Contract.SHOP_STUB_ITEM_ID,
			"equippedDecorId": Contract.SHOP_POSTER_ITEM_ID,
		},
	})
	_expect(failed, parsed.equipped == Contract.SHOP_STUB_ITEM_ID, "S3.4 parser reads equippedSkinId")
	_expect(failed, parsed.equipped_decor == Contract.SHOP_POSTER_ITEM_ID, "S3.4 parser reads equippedDecorId")
	_expect(failed, parsed.equipped_decor_present, "S3.4 equippedDecorId is present")
	var snap: Snapshot = Snapshot.from_dict({
		"you": {
			"seat": "a",
			"marks": 0,
			"equippedSkinId": Contract.SHOP_STUB_ITEM_ID,
			"equippedDecorId": Contract.SHOP_POSTER_ITEM_ID,
		},
	})
	_expect(failed, snap.you_equipped_skin_id() == Contract.SHOP_STUB_ITEM_ID, "S3.4 snapshot skin")
	_expect(failed, snap.you_equipped_decor_id() == Contract.SHOP_POSTER_ITEM_ID, "S3.4 snapshot decor")

	## LIVE 200 infers item.id — merge owned, decor slot only, never wipe skin.
	session.bind_marks(180)
	session.apply_shop({
		"ok": true,
		"you": {"marks": 30, "equippedSkinId": Contract.SHOP_STUB_ITEM_ID},
		"purchaseId": "pur_poster",
		"item": {"id": "decor_poster_stub", "name": "HIDEOUT POSTER", "price": 150, "kind": "decor"},
		"status": 200,
	})
	_expect(failed, session.marks == 30, "S3.2 LIVE buy binds you.marks 180→30")
	_expect(failed, session.owns_cosmetic(Contract.SHOP_POSTER_ITEM_ID), "S3.2 LIVE owned from item.id")
	_expect(failed, session.owns_cosmetic(Contract.SHOP_STUB_ITEM_ID), "S3.2 LIVE buy does not wipe ghillie")
	_expect(failed, session.ghillie, "S3.4 LIVE poster buy keeps equippedSkinId")
	_expect(failed, session.poster, "S3.4 LIVE infer hangs poster on equippedDecorId")
	_expect(failed, Contract.is_suit_chrome(Contract.SHOP_STUB_ITEM_ID), "S3.5 ghillie stays suit chrome")
	_expect(failed, not Contract.is_suit_chrome(Contract.SHOP_POSTER_ITEM_ID), "S3.5 poster is not suit chrome")
	_expect(failed, Contract.is_decor_chrome(Contract.SHOP_POSTER_ITEM_ID), "S3.5 poster is decor chrome")
	session.free()


func _gun_chrome_case(failed: PackedStringArray) -> void:
	## kind: gun SKUs on the same /shop spine. Chrome only — zero combat.
	server.clear_all()
	server.reset_wallet(80)
	var catalog: Dictionary = server.get_shop()
	var listed = Shop.from_any(catalog)
	_expect(failed, listed.items.size() == 12, "G1 catalog rows (skins + poster + guns + T1/T2 parts)")
	_expect(failed, listed.has_item(Contract.GUN_FIELDBOLT), "G1 Fieldbolt catalog row")
	_expect(failed, listed.has_item(Contract.GUN_RAILFRAME), "G1 Railframe catalog row")
	_expect(failed, listed.has_item(Contract.GUN_CRESCENT), "G1 Crescent catalog row")
	_expect(failed, listed.price_of(Contract.GUN_FIELDBOLT) == 0, "G1 Fieldbolt STARTER ★0")
	_expect(failed, listed.price_of(Contract.GUN_RAILFRAME) == 125, "G1 Railframe ★125")
	_expect(failed, listed.price_of(Contract.GUN_CRESCENT) == 200, "G1 Crescent ★200")
	_expect(failed, listed.name_of(Contract.GUN_FIELDBOLT) == Contract.GUN_FIELDBOLT_NAME, "G1 name FIELDBOLT")
	_expect(failed, Contract.gun_family_name(Contract.GUN_FIELDBOLT) == "FIELDBOLT", "in-fiction Fieldbolt")
	_expect(failed, Contract.gun_family_name("railframe") == "RAILFRAME", "alias Railframe")
	_expect(failed, Contract.is_gun_chrome(Contract.GUN_CRESCENT), "Crescent is gun chrome")
	_expect(failed, not Contract.is_suit_chrome(Contract.GUN_FIELDBOLT), "gun is not suit chrome")
	_expect(failed, not Contract.is_decor_chrome(Contract.GUN_RAILFRAME), "gun is not decor chrome")
	_expect(failed, Contract.GUN_VISUAL_COPY.find("visual") >= 0, "G6 zero-combat copy")
	_expect(failed, Shop.row_status_text(true, true, true).find("visual") >= 0, "G6 EQUIPPED copy visual only")
	_expect(failed, not Chrome.debug_status_ribbons(), "P2 ARMORY/RACK debug ribbons off by default")
	_expect(failed, Chrome.armory_debug_ribbon().find("Fieldbolt owned") >= 0, "P2 ARMORY debug ribbon copy stays gated")
	_expect(failed, Chrome.rack_debug_ribbon().find("Fieldbolt equipped") >= 0, "P2 RACK debug ribbon copy stays gated")

	var session = SessionScript.new()
	session.apply_shop(catalog)
	_expect(failed, session.owns_gun(Contract.GUN_FIELDBOLT), "G1 starter bolt owned by default")
	_expect(failed, session.equipped_gun_id() == Contract.GUN_FIELDBOLT, "G1 starter bolt default equipped")
	_expect(failed, session.is_equipped(Contract.GUN_FIELDBOLT), "G1 Fieldbolt wearing")
	_expect(failed, not session.owns_gun(Contract.GUN_RAILFRAME), "G1 Railframe locked until buy")
	_expect(failed, not session.owns_gun(Contract.GUN_CRESCENT), "G1 Crescent locked until buy")
	_expect(failed, session.gun_slot_state(Contract.GUN_FIELDBOLT) == "equipped", "G4 Fieldbolt slot equipped")
	_expect(failed, session.gun_slot_state(Contract.GUN_RAILFRAME) == "locked", "G4 Railframe slot locked")
	_expect(failed, session.marks == 80, "G1 stub binds you.marks 80")

	## Coder: Fieldbolt buy is 200 no-op — no debit, no re-equip.
	var starter_buy: Dictionary = server.buy_shop(Contract.GUN_FIELDBOLT, "gun-fieldbolt-noop")
	_expect(failed, bool(starter_buy.get("ok", false)), "G1 Fieldbolt buy 200 no-op")
	_expect(failed, server.account_marks == 80, "G1 Fieldbolt buy does not debit")
	session.apply_shop(starter_buy)
	_expect(failed, session.marks == 80, "G1 Fieldbolt buy snapshot still 80")
	_expect(failed, session.is_equipped(Contract.GUN_FIELDBOLT), "G1 Fieldbolt buy does not change equip")
	var off_gun: Dictionary = server.equip_cosmetic("", Contract.GUN_SLOT)
	session.apply_shop(off_gun)
	_expect(failed, session.equipped_gun == "", "G1 unequip before starter buy")
	var starter_again: Dictionary = server.buy_shop(Contract.GUN_FIELDBOLT, "gun-fieldbolt-noop-2")
	session.apply_shop(starter_again)
	_expect(failed, session.equipped_gun == "", "G1 Fieldbolt buy does not re-equip after unequip")
	_expect(failed, session.marks == 80, "G1 starter no-op marks unchanged")
	var back_on: Dictionary = server.equip_cosmetic(Contract.GUN_FIELDBOLT, Contract.GUN_SLOT)
	session.apply_shop(back_on)
	_expect(failed, session.is_equipped(Contract.GUN_FIELDBOLT), "G1 re-equip Fieldbolt after no-op")

	## G3 — 402 insufficient (Crescent ★200 vs ★80). Never marks -=.
	var before: int = session.marks
	var poor: Dictionary = server.buy_shop(Contract.GUN_CRESCENT, Contract.new_client_buy_id())
	var poor_shop = Shop.from_any(poor)
	_expect(failed, not bool(poor.get("ok", true)), "G3 Crescent buy rejected")
	_expect(failed, poor_shop.is_insufficient(), "G3 insufficient_marks")
	_expect(failed, server.account_marks == before, "G3 mock ledger unchanged")
	session.bind_marks(999)
	session.apply_shop(poor)
	_expect(failed, session.marks == before, "G3 apply_shop replaces 999 with snapshot 80")
	_expect(failed, session.marks == server.account_marks, "G3 never marks -= on client")
	_expect(failed, not session.owns_gun(Contract.GUN_CRESCENT), "G3 402 does not grant Crescent")

	## G2 — buy Railframe ★125, clientBuyId idempotent, auto-equip gun slot only.
	var buy_id := "00000000-0000-4000-8000-0000000000gg"
	server.reset_wallet(200)
	session.apply_shop(server.get_shop())
	_expect(failed, session.marks == 200, "G2 seeded wallet from snapshot")
	var bought: Dictionary = server.buy_shop(Contract.GUN_RAILFRAME, buy_id)
	_expect(failed, bool(bought.get("ok", false)), "G2 Railframe buy ok")
	session.bind_marks(200)
	session.apply_shop(bought)
	_expect(failed, session.marks == 75, "G2 you.marks 200-125 from snapshot")
	_expect(failed, server.account_marks == 75, "G2 mock ledger debited once")
	_expect(failed, session.owns_gun(Contract.GUN_RAILFRAME), "G2 owned Railframe")
	_expect(failed, session.is_equipped(Contract.GUN_RAILFRAME), "G2 last-buy auto-equip gun")
	_expect(failed, session.equipped_gun_id() == Contract.GUN_RAILFRAME, "G2 equippedGunId railframe")
	_expect(failed, session.owns_gun(Contract.GUN_FIELDBOLT), "G2 starter still owned")
	_expect(failed, session.equipped_cosmetic == "", "G2 gun buy does not write skin slot")
	_expect(failed, session.equipped_decor == "", "G2 gun buy does not write decor slot")
	var replay: Dictionary = server.buy_shop(Contract.GUN_RAILFRAME, buy_id)
	_expect(failed, bool(replay.get("ok", false)), "G2 clientBuyId idempotent ok")
	_expect(failed, server.account_marks == 75, "G2 replay does not debit again")
	session.apply_shop(replay)
	_expect(failed, session.marks == 75, "G2 replay snapshot still 75")
	var second: Dictionary = server.buy_shop(Contract.GUN_RAILFRAME, Contract.new_client_buy_id())
	_expect(failed, str(second.get("error", "")) == Contract.SHOP_ERR_ALREADY_OWNED, "G2 second id already_owned")
	_expect(failed, server.account_marks == 75, "G2 already_owned no debit")
	session.free()

	## G2 — coexist: buy Railframe + poster + ghillie; slots never clobber.
	server.reset_wallet(400)
	session = SessionScript.new()
	session.apply_shop(server.get_shop())
	session.apply_shop(server.buy_shop(Contract.GUN_RAILFRAME, "gun-coexist-r"))
	session.apply_shop(server.buy_shop(Contract.SHOP_POSTER_ITEM_ID, "gun-coexist-p"))
	session.apply_shop(server.buy_shop(Contract.SHOP_STUB_ITEM_ID, "gun-coexist-g"))
	_expect(failed, session.marks == 75, "G2 400-125-150-50 from snapshot")
	_expect(failed, session.is_equipped(Contract.GUN_RAILFRAME), "G2 gun slot after skin/decor buys")
	_expect(failed, session.is_equipped(Contract.SHOP_POSTER_ITEM_ID), "G2 decor slot after gun")
	_expect(failed, session.is_equipped(Contract.SHOP_STUB_ITEM_ID), "G2 skin slot after gun")
	_expect(failed, session.ghillie and session.poster, "G2 three slots coexist")

	## G2 — equip / unequip gun without clobber.
	var swap: Dictionary = server.equip_cosmetic(Contract.GUN_FIELDBOLT, Contract.GUN_SLOT)
	session.apply_shop(swap)
	_expect(failed, session.is_equipped(Contract.GUN_FIELDBOLT), "G2 swap Fieldbolt")
	_expect(failed, session.gun_slot_state(Contract.GUN_RAILFRAME) == "owned", "G4 Railframe owned painted")
	_expect(failed, session.ghillie and session.poster, "G2 gun swap leaves skin + poster")
	_expect(failed, session.marks == 75, "G2 gun equip does not touch marks")
	var unequip: Dictionary = server.equip_cosmetic("", Contract.GUN_SLOT)
	session.apply_shop(unequip)
	_expect(failed, session.equipped_gun == "", "G2 unequip gun stays empty")
	_expect(failed, not session.is_equipped(Contract.GUN_FIELDBOLT), "G2 unequip clears wearing")
	_expect(failed, session.gun_slot_state(Contract.GUN_FIELDBOLT) == "owned", "G4 unequip Fieldbolt owned, not highlighted")
	_expect(failed, session.equipped_gun_id() == Contract.GUN_FIELDBOLT, "G5 hands/optic fall back to Fieldbolt")
	_expect(failed, session.ghillie and session.poster, "G2 unequip gun leaves skin + poster")
	_expect(failed, session.marks == 75, "G2 unequip gun marks unchanged")
	var refuse: Dictionary = server.equip_cosmetic(Contract.GUN_CRESCENT, Contract.GUN_SLOT)
	_expect(failed, str(refuse.get("error", "")) == Contract.SHOP_ERR_NOT_OWNED, "G2 unowned Crescent rejected")
	session.apply_shop(refuse)
	_expect(failed, session.equipped_gun == "", "G2 reject keeps empty gun slot")

	## LIVE /shop/me parser + unowned fallback.
	var me = Shop.from_any({
		"you": {
			"marks": 75,
			"equippedSkinId": Contract.SHOP_STUB_ITEM_ID,
			"equippedDecorId": Contract.SHOP_POSTER_ITEM_ID,
			"equippedGunId": "gun_railframe",
			"ownedGuns": ["gun_fieldbolt", "gun_railframe"],
		},
		"owned": [Contract.SHOP_STUB_ITEM_ID, Contract.SHOP_POSTER_ITEM_ID],
	})
	_expect(failed, me.equipped_gun_present, "/shop/me equippedGunId present")
	_expect(failed, me.owned_guns_present, "/shop/me ownedGuns present")
	_expect(failed, me.equipped_gun == Contract.GUN_RAILFRAME, "parser reads equippedGunId")
	_expect(failed, me.owned_guns.has(Contract.GUN_RAILFRAME), "parser reads ownedGuns")
	session.apply_shop({
		"you": {
			"marks": 75,
			"equippedGunId": "gun_crescent",
		},
	})
	_expect(failed, session.equipped_gun_id() == Contract.GUN_FIELDBOLT, "unowned Crescent falls back to starter")
	var unknown = Shop.from_any({"you": {"equippedGunId": "not_a_gun"}})
	_expect(failed, unknown.equipped_gun == "", "unknown equippedGunId is empty")

	var snap: Snapshot = Snapshot.from_dict({
		"you": {
			"seat": "a",
			"marks": 75,
			"equippedSkinId": Contract.SHOP_STUB_ITEM_ID,
			"equippedDecorId": Contract.SHOP_POSTER_ITEM_ID,
			"equippedGunId": Contract.GUN_RAILFRAME,
		},
	})
	_expect(failed, snap.you_equipped_gun_id() == Contract.GUN_RAILFRAME, "G2 snapshot equippedGunId")
	_expect(failed, snap.you_equipped_skin_id() == Contract.SHOP_STUB_ITEM_ID, "G2 snapshot skin untouched")
	_expect(failed, snap.you_equipped_decor_id() == Contract.SHOP_POSTER_ITEM_ID, "G2 snapshot decor untouched")

	## LIVE buy 200 infers item.id — merge ownedGuns, gun slot only.
	session.apply_shop({
		"ok": true,
		"you": {"marks": 50, "equippedSkinId": Contract.SHOP_STUB_ITEM_ID},
		"purchaseId": "pur_rail",
		"item": {"id": "gun_railframe", "name": "RAILFRAME", "price": 125, "kind": "gun"},
		"status": 200,
	})
	_expect(failed, session.marks == 50, "G2 LIVE buy binds you.marks")
	_expect(failed, session.owns_gun(Contract.GUN_RAILFRAME), "G2 LIVE owned from item.id")
	_expect(failed, session.is_equipped(Contract.GUN_RAILFRAME), "G2 LIVE infer equips gun slot")
	_expect(failed, session.ghillie, "G2 LIVE gun buy keeps equippedSkinId")
	session.free()
	_gun_combat_parity_case(failed)


func _gun_combat_parity_case(failed: PackedStringArray) -> void:
	## G5: Attack miss/kill path identical across Fieldbolt / Railframe / Crescent.
	var bolt: Dictionary = _gun_combat_run(Contract.GUN_FIELDBOLT)
	var rail: Dictionary = _gun_combat_run(Contract.GUN_RAILFRAME)
	var cres: Dictionary = _gun_combat_run(Contract.GUN_CRESCENT)
	_expect(failed, bool(bolt.get("ok", false)) and bool(rail.get("ok", false)) and bool(cres.get("ok", false)), "G5 three loops ok")
	for key in ["miss_hit", "miss_kill", "miss_phase", "miss_hot", "miss_exposure", "kill_hit", "kill_kill", "kill_delta", "recon_base", "pvp_win"]:
		_expect(failed, bolt.get(key) == rail.get(key), "G5 Fieldbolt vs Railframe %s identical" % key)
		_expect(failed, bolt.get(key) == cres.get(key), "G5 Fieldbolt vs Crescent %s identical" % key)
	_expect(failed, Contract.RECON_BASE == 0.35, "G5 RECON_BASE 0.35")
	_expect(failed, Contract.MARKS_PVP_WIN == 32, "G5 PvP kill ★32")
	_expect(failed, int(bolt.get("kill_delta", -1)) == Contract.MARKS_PVP_WIN, "G5 kill marksDelta +32")
	_expect(failed, str(bolt.get("snap_gun", "")) == Contract.GUN_FIELDBOLT, "G5 snapshot names Fieldbolt")
	_expect(failed, str(rail.get("snap_gun", "")) == Contract.GUN_RAILFRAME, "G5 snapshot names Railframe")
	_expect(failed, str(cres.get("snap_gun", "")) == Contract.GUN_CRESCENT, "G5 snapshot names Crescent")


func _gun_combat_run(gun_id: String) -> Dictionary:
	server.clear_all()
	server.reset_wallet(400)
	if gun_id != Contract.GUN_FIELDBOLT:
		server.buy_shop(gun_id, "gun-e5-%s" % gun_id)
		server.equip_cosmetic(gun_id, Contract.GUN_SLOT)
	var created: Dictionary = server.create_match()
	var mid := str(created["matchId"])
	var a: Dictionary = server.join(mid, created["joinTokens"]["a"])
	var b: Dictionary = server.join(mid, created["joinTokens"]["b"])
	server.apply_action(mid, a["playerId"], ActionIntent.select_hex(2, 2))
	server.apply_action(mid, b["playerId"], ActionIntent.select_hex(7, 5))
	server.apply_action(mid, a["playerId"], ActionIntent.start())
	var miss: ActionResult = server.apply_action(mid, a["playerId"], ActionIntent.attack(0, 0))
	var miss_snap: Snapshot = Snapshot.from_dict(miss.snapshot)
	var miss_last: Variant = miss_snap.last_action()
	server.apply_action(mid, a["playerId"], ActionIntent.end_turn(50))
	server.apply_action(mid, b["playerId"], ActionIntent.recon(4, 3))
	server.apply_action(mid, b["playerId"], ActionIntent.end_turn(40))
	var kill: ActionResult = server.apply_action(mid, a["playerId"], ActionIntent.attack(7, 5))
	var kill_snap: Snapshot = Snapshot.from_dict(kill.snapshot)
	var kill_last: Variant = kill_snap.last_action()
	var last_clean := true
	if miss_last is Dictionary:
		last_clean = (not miss_last.has("gunId")) and (not miss_last.has("equippedGunId"))
	return {
		"ok": bool(miss.ok) and bool(kill.ok) and last_clean,
		"miss_hit": miss_last is Dictionary and miss_last.get("hit") == false,
		"miss_kill": miss_last is Dictionary and miss_last.get("kill") == false,
		"miss_phase": str(miss_snap.phase()),
		"miss_hot": miss_snap.enemy_visible_hex() == null,
		"miss_exposure": int(miss_snap.you_exposure()),
		"kill_hit": kill_last is Dictionary and kill_last.get("hit") == true,
		"kill_kill": kill_last is Dictionary and kill_last.get("kill") == true,
		"kill_delta": kill_snap.marks_delta(),
		"recon_base": Contract.RECON_BASE,
		"pvp_win": Contract.MARKS_PVP_WIN,
		"snap_gun": miss_snap.you_equipped_gun_id(),
	}


func _part_sink_case(failed: PackedStringArray) -> void:
	## Optic / Stock / Barrel on the shop spine. Feel is chrome. Kill math stays put.
	server.clear_all()
	server.reset_wallet(Contract.MOCK_WALLET_STUB)
	var listed = Shop.from_any(server.get_shop())
	_expect(failed, listed.has_item(Contract.PART_OPTIC), "P optic catalog row")
	_expect(failed, listed.has_item(Contract.PART_STOCK), "P stock catalog row")
	_expect(failed, listed.has_item(Contract.PART_BARREL), "P barrel catalog row")
	_expect(failed, listed.price_of(Contract.PART_OPTIC) == 75, "P optic ★75")
	_expect(failed, listed.price_of(Contract.PART_STOCK) == 100, "P stock ★100")
	_expect(failed, listed.price_of(Contract.PART_BARREL) == 125, "P barrel ★125")
	_expect(failed, listed.name_of(Contract.PART_OPTIC) == "OPTIC", "P optic name")
	_expect(failed, not Shop.row_buy_enabled(false, listed.balance() >= 75), "P ★24 cannot buy optic")
	var row_copy := Contract.part_row_status(true, true, true) + Contract.part_row_status(true, true, false) + Contract.part_row_status(false, false, false) + Contract.PART_TOAST_WINDOW + Contract.PART_TOAST_WOBBLE
	var banned := row_copy.to_lower()
	_expect(failed, banned.find("hit") < 0 and banned.find("spot") < 0 and banned.find("exposure") < 0 and banned.find("%") < 0, "P row copy has no combat percents")
	_expect(failed, is_equal_approx(Contract.local_wobble_scale(true, false), 0.80), "P stock wobble −20%")
	_expect(failed, is_equal_approx(Contract.local_wobble_scale(false, true), 0.90), "P barrel wobble −10%")
	_expect(failed, is_equal_approx(Contract.local_wobble_scale(true, true), 0.75), "P stack wobble cap −25%")
	_expect(failed, is_equal_approx(Contract.local_shot_window_sec(false), 1.2), "P base window 1.2s")
	_expect(failed, is_equal_approx(Contract.local_shot_window_sec(true), 1.4), "P optic window 1.4s")
	_expect(failed, Contract.PART_OPTIC == "gun_part_optic" and Contract.PART_KIND == "gun-part", "P live part ids")
	_expect(failed, is_equal_approx(Contract.local_wobble_scale(false, false), 1.0), "P bare wobble")
	_expect(failed, Contract.part_buy_toast(Contract.PART_OPTIC) == Contract.PART_TOAST_WINDOW, "P optic toast")
	_expect(failed, Contract.part_buy_toast(Contract.PART_STOCK) == Contract.PART_TOAST_WOBBLE, "P stock toast")
	_expect(failed, Contract.part_buy_toast(Contract.PART_BARREL) == Contract.PART_TOAST_WOBBLE, "P barrel toast")
	_expect(failed, Contract.part_row_status(false, false, false) == "", "P insufficient is not a per-row line")
	_expect(failed, Contract.SHOP_INSUFFICIENT_COPY == "Not enough Marks.", "P shared insufficient copy")
	var feel_copy := Contract.PART_TOAST_WINDOW + Contract.PART_TOAST_WOBBLE
	_expect(failed, feel_copy.find("%") < 0 and feel_copy.find("1.4") < 0 and feel_copy.find("0.8") < 0, "P buy toast has no combat stats")
	_expect(failed, Contract.PART_TOAST_HOLD_SEC > 0.0, "P buy toast hold is set")
	var part_hud := FileAccess.get_file_as_string("res://scenes/lobby/hideout_lobby.gd")
	var wood_toast := _fn_body(part_hud, "_build_part_wood_toast")
	_expect(failed, wood_toast.find("PartWoodToast") >= 0 and wood_toast.find("make_wood_texture") >= 0, "P one shared wood toast plate")
	var show_toast := _fn_body(part_hud, "_show_part_wood_toast")
	_expect(failed, show_toast.find("create_timer(Contract.PART_TOAST_HOLD_SEC)") >= 0, "P buy toast clears on its own")
	var buy_body := _fn_body(part_hud, "_on_shop_primary")
	_expect(failed, buy_body.find("_show_part_wood_toast(Contract.SHOP_INSUFFICIENT_COPY, false)") >= 0, "P insufficient uses the shared toast")
	_expect(failed, buy_body.find("_show_part_wood_toast(Contract.part_buy_toast(item_id), true)") >= 0, "P buy feel uses the clearing toast")
	var sync_body := _fn_body(part_hud, "_sync_part_marks_toast")
	_expect(failed, sync_body.find("Contract.SHOP_INSUFFICIENT_COPY") >= 0 and sync_body.find("_part_toast_clearing") >= 0, "P insufficient toast yields to the clearing buy line")

	var lagged = Shop.from_any(Contract.merge_live_shop_catalog({
		"items": [{"id": "skin_hideout_stub", "name": "Hideout Skin (stub)", "price": 50, "kind": "skin"}],
	}))
	_expect(failed, lagged.has_item(Contract.PART_OPTIC), "P lag still shows optic row")
	_expect(failed, not lagged.catalog_pending(Contract.PART_OPTIC), "P omitted optic stays buyable")
	_expect(failed, not lagged.catalog_pending(Contract.PART_BARREL), "P omitted barrel stays buyable")
	_expect(failed, not lagged.catalog_pending(Contract.GUN_RAILFRAME), "P gun lag stays buyable")
	var live_parts = Shop.from_any(Contract.merge_live_shop_catalog({
		"items": [
			{"id": "gun_part_optic", "name": "OPTIC", "price": 75, "kind": "gun-part"},
			{"id": "gun_part_stock", "name": "STOCK", "price": 100, "kind": "gun-part"},
			{"id": "gun_part_barrel", "name": "BARREL", "price": 125, "kind": "gun-part"},
		],
	}))
	_expect(failed, not live_parts.catalog_pending(Contract.PART_OPTIC), "P live optic is wired")
	_expect(failed, live_parts.name_of(Contract.PART_OPTIC) == "OPTIC", "P prefer LIVE optic name")
	_expect(failed, live_parts.price_of(Contract.PART_OPTIC) == 75, "P live optic price")
	_expect(failed, str(live_parts.item_for(Contract.PART_OPTIC).get("kind", "")) == "gun-part", "P live kind gun-part")

	var session = SessionScript.new()
	session.apply_shop(server.get_shop())
	_expect(failed, session.equipped_optic_id() == "", "P default optic empty")
	_expect(failed, is_equal_approx(session.attack_wobble_scale(), 1.0), "P default wobble 1")
	_expect(failed, is_equal_approx(session.feel_shot_window_sec, 1.2), "P default window from server 1.2")
	_expect(failed, session.feel_wobble_from_server, "P mock snapshot names wobbleScale")
	var poor: Dictionary = server.buy_shop(Contract.PART_OPTIC, Contract.new_client_buy_id())
	_expect(failed, str(poor.get("error", "")) == Contract.SHOP_ERR_INSUFFICIENT, "P insufficient optic")
	_expect(failed, server.account_marks == 24, "P 402 does not debit")
	session.bind_marks(999)
	session.apply_shop(poor)
	_expect(failed, session.marks == 24, "P 402 rebinds snapshot marks")
	_expect(failed, not session.owns_part(Contract.PART_OPTIC), "P 402 does not grant optic")

	server.reset_wallet(400)
	session.apply_shop(server.get_shop())
	var optic_id := "00000000-0000-4000-8000-0000000000p1"
	var bought: Dictionary = server.buy_shop(Contract.PART_OPTIC, optic_id)
	session.bind_marks(400)
	session.apply_shop(bought)
	_expect(failed, session.marks == 325, "P optic 400-75 from snapshot")
	_expect(failed, session.owns_part(Contract.PART_OPTIC), "P owns optic")
	_expect(failed, session.is_equipped(Contract.PART_OPTIC), "P optic auto-equip")
	_expect(failed, is_equal_approx(session.feel_shot_window_sec, 1.4), "P server window 1.4")
	_expect(failed, is_equal_approx(session.attack_wobble_scale(), 1.0), "P optic does not change wobble")
	var replay: Dictionary = server.buy_shop(Contract.PART_OPTIC, optic_id)
	_expect(failed, bool(replay.get("ok", false)) and server.account_marks == 325, "P optic clientBuyId idempotent")
	session.apply_shop(server.buy_shop(Contract.PART_STOCK, "part-stock"))
	session.apply_shop(server.buy_shop(Contract.PART_BARREL, "part-barrel"))
	_expect(failed, session.marks == 100, "P 325-100-125 from snapshot")
	_expect(failed, session.is_equipped(Contract.PART_STOCK) and session.is_equipped(Contract.PART_BARREL), "P stock and barrel equipped")
	_expect(failed, session.is_equipped(Contract.PART_OPTIC), "P optic slot survives stock buy")
	_expect(failed, is_equal_approx(session.attack_wobble_scale(), 0.75), "P server stack wobble 0.75")
	_expect(failed, is_equal_approx(session.feel_shot_window_sec, 1.4), "P barrel does not change window")
	_expect(failed, session.equipped_gun_id() == Contract.GUN_FIELDBOLT, "P parts do not clobber gun")
	var off: Dictionary = server.equip_cosmetic("", Contract.PART_SLOT_STOCK)
	session.apply_shop(off)
	_expect(failed, session.equipped_stock_id() == "", "P unequip stock")
	_expect(failed, session.is_equipped(Contract.PART_BARREL) and session.is_equipped(Contract.PART_OPTIC), "P other slots stay")
	_expect(failed, is_equal_approx(session.attack_wobble_scale(), 0.90), "P barrel-only wobble 0.90")
	_expect(failed, session.marks == 100, "P equip does not touch marks")
	var refuse: Dictionary = server.equip_cosmetic(Contract.PART_STOCK, Contract.PART_SLOT_STOCK)
	_expect(failed, bool(refuse.get("ok", false)), "P re-equip stock")
	server.owned_parts.erase(Contract.PART_STOCK)
	server.owned_cosmetics.erase(Contract.PART_STOCK)
	var denied: Dictionary = server.equip_cosmetic(Contract.PART_STOCK, Contract.PART_SLOT_STOCK)
	_expect(failed, str(denied.get("error", "")) == Contract.SHOP_ERR_NOT_OWNED, "P unowned stock rejected")

	## C2: omitted feel stays bare. Equipped ids do not author window or wobble.
	var local = SessionScript.new()
	local.owned_parts = [Contract.PART_OPTIC, Contract.PART_STOCK, Contract.PART_BARREL]
	local.equipped_optic = Contract.PART_OPTIC
	local.equipped_stock = Contract.PART_STOCK
	local.equipped_barrel = Contract.PART_BARREL
	local.apply_shop({"you": {"marks": 10, "equippedOpticId": Contract.PART_OPTIC, "equippedStockId": Contract.PART_STOCK, "equippedBarrelId": Contract.PART_BARREL}})
	_expect(failed, not local.feel_wobble_from_server and not local.feel_window_from_server, "C2 omitted feel is not server")
	_expect(failed, is_equal_approx(local.attack_wobble_scale(), 1.0), "C2 omitted wobble stays 1")
	_expect(failed, is_equal_approx(local.feel_shot_window_sec, 1.2), "C2 omitted window stays 1.2")
	var session_src := FileAccess.get_file_as_string("res://autoload/client_session.gd")
	var optic_src := FileAccess.get_file_as_string("res://scenes/optic/optic_overlay.gd")
	_expect(failed, session_src.find("local_wobble_scale") < 0 and session_src.find("local_shot_window_sec") < 0, "C2 session does not author feel")
	_expect(failed, optic_src.find("local_wobble_scale") < 0 and optic_src.find("local_shot_window_sec") < 0, "C2 optic does not author feel")
	local.apply_shop({"you": {"marks": 10, "wobbleScale": 0.55, "shotWindowSec": 0.9, "equippedOpticId": null, "equippedStockId": null, "equippedBarrelId": null}})
	_expect(failed, local.feel_wobble_from_server and is_equal_approx(local.attack_wobble_scale(), 0.55), "P server wobble wins")
	_expect(failed, local.feel_window_from_server and is_equal_approx(local.feel_shot_window_sec, 0.9), "P server window wins")
	_expect(failed, local.equipped_optic_id() == "", "P null optic id is default")
	var bare: Snapshot = Snapshot.from_dict({"you": {"seat": "a", "marks": 0}})
	_expect(failed, bare.you_equipped_optic_id() == "" and bare.you_wobble_scale() == null and bare.you_shot_window_sec() == null, "P missing snapshot fields fail closed")
	var named: Snapshot = Snapshot.from_dict({"you": {"equippedOpticId": "gun_part_optic", "equippedStockId": null, "wobbleScale": 0.8, "shotWindowSec": 1.4}})
	_expect(failed, named.you_equipped_optic_id() == Contract.PART_OPTIC, "P snapshot optic id")
	_expect(failed, named.you_equipped_stock_id() == "", "P snapshot null stock")
	_expect(failed, is_equal_approx(float(named.you_wobble_scale()), 0.8), "P snapshot wobbleScale")
	_expect(failed, is_equal_approx(float(named.you_shot_window_sec()), 1.4), "P snapshot shotWindowSec")
	local.free()

	## Combat parity: parts do not move hit / spot / exposure / practice Marks.
	var plain: Dictionary = _part_combat_run(false)
	var kitted: Dictionary = _part_combat_run(true)
	var practice: Dictionary = _part_practice_run()
	_expect(failed, bool(plain.get("ok", false)) and bool(kitted.get("ok", false)) and bool(practice.get("ok", false)), "P combat loops ok")
	for key in ["miss_hit", "miss_chance", "kill_hit", "kill_delta", "spotted", "exposure_floor"]:
		_expect(failed, plain.get(key) == kitted.get(key), "P parity %s" % key)
	_expect(failed, bool(plain.get("chance_formula", false)) and bool(kitted.get("chance_formula", false)), "P hitChance is the occupy formula")
	_expect(failed, _part_delta(kitted.get("kill_delta")) == Contract.MARKS_PVP_WIN, "P PvP kill still ★32")
	_expect(failed, _part_delta(practice.get("kill_delta")) == Contract.MARKS_PRACTICE, "P practice Marks Δ0")
	_expect(failed, bool(practice.get("wallet_held", false)), "P practice does not grant")
	_expect(failed, bool(practice.get("feel_window", false)), "C4 practice window 1.4")
	_expect(failed, bool(practice.get("feel_wobble", false)), "C4 practice wobble 0.75")
	_expect(failed, bool(practice.get("chance_formula", false)), "P practice hitChance ignores parts")
	_expect(failed, Contract.BASE_HIT_CHANCE == 0.90 and Contract.RECON_BASE == 0.35 and Contract.BRUSH_COVER_HIT == 0.10, "P hit and spot constants unchanged")
	server.reset_wallet(Contract.MOCK_WALLET_STUB)
	session.free()


func _part_t2_case(failed: PackedStringArray) -> void:
	## T2 ladder on the same gun-part spine. Equip replaces T1. Attack reads server feel.
	var before := failed.size()
	server.clear_all()
	server.reset_wallet(Contract.MOCK_WALLET_STUB)
	var listed = Shop.from_any(server.get_shop())
	_expect(failed, listed.has_item(Contract.PART_OPTIC_T2), "T2 optic catalog row")
	_expect(failed, listed.has_item(Contract.PART_STOCK_T2), "T2 stock catalog row")
	_expect(failed, listed.has_item(Contract.PART_BARREL_T2), "T2 barrel catalog row")
	_expect(failed, listed.price_of(Contract.PART_OPTIC) == 75, "T2 leaves optic T1 at ★75")
	_expect(failed, listed.price_of(Contract.PART_STOCK) == 100, "T2 leaves stock T1 at ★100")
	_expect(failed, listed.price_of(Contract.PART_BARREL) == 125, "T2 leaves barrel T1 at ★125")
	_expect(failed, listed.price_of(Contract.PART_OPTIC_T2) == 150, "T2 optic ★150")
	_expect(failed, listed.price_of(Contract.PART_STOCK_T2) == 175, "T2 stock ★175")
	_expect(failed, listed.price_of(Contract.PART_BARREL_T2) == 200, "T2 barrel ★200")
	_expect(failed, listed.name_of(Contract.PART_OPTIC_T2) == "OPTIC T2", "T2 optic name")
	_expect(failed, listed.name_of(Contract.PART_STOCK_T2) == "STOCK T2", "T2 stock name")
	_expect(failed, listed.name_of(Contract.PART_BARREL_T2) == "BARREL T2", "T2 barrel name")
	_expect(failed, str(listed.item_for(Contract.PART_OPTIC_T2).get("kind", "")) == "gun-part", "T2 kind gun-part")
	_expect(failed, int(listed.item_for(Contract.PART_BARREL_T2).get("tier", 0)) == 2, "T2 tier field")
	_expect(failed, Contract.canonical_part_id(Contract.PART_OPTIC_T2) == Contract.PART_OPTIC_T2, "T2 optic id stays distinct")
	_expect(failed, Contract.canonical_part_id(Contract.PART_OPTIC) == Contract.PART_OPTIC, "T1 optic id stays distinct")
	_expect(failed, Contract.part_slot(Contract.PART_OPTIC_T2) == Contract.PART_SLOT_OPTIC, "T2 optic shares the optic slot")
	_expect(failed, Contract.part_slot(Contract.PART_STOCK_T2) == Contract.part_slot(Contract.PART_STOCK), "T2 stock shares the stock slot")
	_expect(failed, Contract.part_buy_toast(Contract.PART_OPTIC_T2) == Contract.PART_TOAST_WINDOW, "T2 optic toast is the window line")
	_expect(failed, Contract.part_buy_toast(Contract.PART_STOCK_T2) == Contract.PART_TOAST_WOBBLE, "T2 stock toast is the wobble line")
	_expect(failed, Contract.part_buy_toast(Contract.PART_BARREL_T2) == Contract.PART_TOAST_WOBBLE, "T2 barrel toast is the wobble line")
	var row_copy := Contract.part_name(Contract.PART_OPTIC_T2) + Contract.part_name(Contract.PART_STOCK_T2) + Contract.part_name(Contract.PART_BARREL_T2) + Contract.part_buy_toast(Contract.PART_OPTIC_T2) + Contract.part_row_status(true, true, true) + Contract.part_row_status(false, false, false)
	var banned := row_copy.to_lower()
	_expect(failed, banned.find("hit") < 0 and banned.find("spot") < 0 and banned.find("exposure") < 0 and banned.find("%") < 0, "T2 row copy has no combat percents")
	_expect(failed, is_equal_approx(Contract.local_shot_window_sec(Contract.PART_OPTIC_T2), 1.55), "T2 optic window 1.55")
	_expect(failed, is_equal_approx(Contract.local_shot_window_sec(Contract.PART_OPTIC), 1.4), "T1 optic window stays 1.4")
	_expect(failed, is_equal_approx(Contract.local_wobble_scale(Contract.PART_STOCK_T2, ""), 0.75), "T2 stock wobble 0.75")
	_expect(failed, is_equal_approx(Contract.local_wobble_scale("", Contract.PART_BARREL_T2), 0.85), "T2 barrel wobble 0.85")
	_expect(failed, is_equal_approx(Contract.local_wobble_scale(Contract.PART_STOCK_T2, Contract.PART_BARREL_T2), 0.75), "T2 stack cap 0.75")
	_expect(failed, is_equal_approx(Contract.local_wobble_scale(Contract.PART_STOCK, Contract.PART_BARREL_T2), 0.75), "T1 stock + T2 barrel cap 0.75")
	_expect(failed, is_equal_approx(Contract.local_wobble_scale(Contract.PART_STOCK_T2, Contract.PART_BARREL), 0.75), "T2 stock + T1 barrel cap 0.75")
	_expect(failed, is_equal_approx(Contract.local_wobble_scale(true, false), 0.80), "T1 bool stock wobble stays 0.80")

	var lagged = Shop.from_any(Contract.merge_live_shop_catalog({
		"items": [{"id": "gun_part_optic", "name": "OPTIC", "price": 75, "kind": "gun-part", "tier": 1}],
	}))
	_expect(failed, lagged.has_item(Contract.PART_OPTIC_T2), "T2 lag still shows optic T2 row")
	_expect(failed, not lagged.catalog_pending(Contract.PART_STOCK_T2), "omitted T2 stock stays buyable")
	var live_t2 = Shop.from_any(Contract.merge_live_shop_catalog({
		"items": [
			{"id": "gun_part_optic_t2", "name": "OPTIC T2", "price": 150, "kind": "gun-part", "tier": 2},
			{"id": "gun_part_stock_t2", "name": "STOCK T2", "price": 175, "kind": "gun-part", "tier": 2},
			{"id": "gun_part_barrel_t2", "name": "BARREL T2", "price": 200, "kind": "gun-part", "tier": 2},
		],
	}))
	_expect(failed, live_t2.price_of(Contract.PART_OPTIC_T2) == 150, "T2 prefer LIVE optic price")
	_expect(failed, live_t2.name_of(Contract.PART_STOCK_T2) == "STOCK T2", "T2 prefer LIVE stock name")
	_expect(failed, str(live_t2.item_for(Contract.PART_BARREL_T2).get("kind", "")) == "gun-part", "T2 live kind gun-part")

	var session = SessionScript.new()
	session.apply_shop(server.get_shop())
	var poor: Dictionary = server.buy_shop(Contract.PART_OPTIC_T2, Contract.new_client_buy_id())
	_expect(failed, str(poor.get("error", "")) == Contract.SHOP_ERR_INSUFFICIENT, "T2 insufficient optic")
	session.bind_marks(999)
	session.apply_shop(poor)
	_expect(failed, session.marks == 24, "T2 402 rebinds snapshot marks")
	_expect(failed, not session.owns_part(Contract.PART_OPTIC_T2), "T2 402 does not grant optic")

	server.reset_wallet(900)
	session.apply_shop(server.get_shop())
	session.apply_shop(server.buy_shop(Contract.PART_OPTIC, "t2-optic-t1"))
	_expect(failed, session.is_equipped(Contract.PART_OPTIC), "T2 setup wears T1 optic")
	_expect(failed, is_equal_approx(session.feel_shot_window_sec, 1.4), "T2 setup server window is T1 1.4")
	var optic_id := "00000000-0000-4000-8000-0000000000t2"
	var bought: Dictionary = server.buy_shop(Contract.PART_OPTIC_T2, optic_id)
	session.apply_shop(bought)
	_expect(failed, session.marks == 675, "T2 optic 900-75-150 from snapshot")
	_expect(failed, session.owns_part(Contract.PART_OPTIC) and session.owns_part(Contract.PART_OPTIC_T2), "T2 own both optic tiers")
	_expect(failed, session.is_equipped(Contract.PART_OPTIC_T2), "T2 optic replaces T1")
	_expect(failed, not session.is_equipped(Contract.PART_OPTIC), "T1 optic stays owned, not worn")
	_expect(failed, is_equal_approx(session.feel_shot_window_sec, 1.55), "T2 server window 1.55")
	_expect(failed, is_equal_approx(session.attack_wobble_scale(), 1.0), "T2 optic does not change wobble")
	var replay: Dictionary = server.buy_shop(Contract.PART_OPTIC_T2, optic_id)
	_expect(failed, bool(replay.get("ok", false)) and server.account_marks == 675, "T2 optic clientBuyId idempotent")
	var back: Dictionary = server.equip_cosmetic(Contract.PART_OPTIC, Contract.PART_SLOT_OPTIC)
	session.apply_shop(back)
	_expect(failed, session.is_equipped(Contract.PART_OPTIC) and not session.is_equipped(Contract.PART_OPTIC_T2), "T2 re-equip T1 optic")
	_expect(failed, is_equal_approx(session.feel_shot_window_sec, 1.4), "T2 worn id picks T1 window")
	_expect(failed, session.marks == 675, "T2 equip does not touch marks")
	session.apply_shop(server.equip_cosmetic(Contract.PART_OPTIC_T2, Contract.PART_SLOT_OPTIC))
	_expect(failed, session.is_equipped(Contract.PART_OPTIC_T2), "T2 equip wears optic T2 again")
	_expect(failed, is_equal_approx(session.feel_shot_window_sec, 1.55), "T2 re-equip window 1.55")

	server.clear_all()
	server.reset_wallet(200)
	session.apply_shop(server.get_shop())
	session.apply_shop(server.buy_shop(Contract.PART_BARREL_T2, "t2-barrel-only"))
	_expect(failed, session.owns_part(Contract.PART_BARREL_T2) and not session.owns_part(Contract.PART_BARREL), "T2 barrel without T1")
	_expect(failed, session.is_equipped(Contract.PART_BARREL_T2), "T2 barrel auto-equip")
	_expect(failed, is_equal_approx(session.attack_wobble_scale(), 0.85), "T2 barrel-only wobble 0.85")
	_expect(failed, is_equal_approx(session.feel_shot_window_sec, 1.2), "T2 barrel does not change window")
	server.reset_wallet(500)
	session.apply_shop(server.get_shop())
	session.apply_shop(server.buy_shop(Contract.PART_STOCK_T2, "t2-stock-only"))
	_expect(failed, not session.owns_part(Contract.PART_STOCK), "T2 stock without T1")
	_expect(failed, is_equal_approx(session.attack_wobble_scale(), 0.75), "T2 stock wobble 0.75")
	session.apply_shop(server.buy_shop(Contract.PART_BARREL, "t2-barrel-t1"))
	_expect(failed, session.is_equipped(Contract.PART_STOCK_T2) and session.is_equipped(Contract.PART_BARREL), "T2 stock stays when T1 barrel equips")
	_expect(failed, is_equal_approx(session.attack_wobble_scale(), 0.75), "T2 stock + T1 barrel cap 0.75")
	session.apply_shop(server.buy_shop(Contract.PART_BARREL_T2, "t2-barrel-up"))
	_expect(failed, session.is_equipped(Contract.PART_BARREL_T2) and session.owns_part(Contract.PART_BARREL), "T2 barrel replaces T1 barrel")
	_expect(failed, is_equal_approx(session.attack_wobble_scale(), 0.75), "T2 stock + T2 barrel stays 0.75")
	_expect(failed, session.equipped_gun_id() == Contract.GUN_FIELDBOLT, "T2 parts do not clobber gun")

	var local = SessionScript.new()
	local.owned_parts = [Contract.PART_OPTIC_T2, Contract.PART_STOCK_T2, Contract.PART_BARREL_T2]
	local.equipped_optic = Contract.PART_OPTIC_T2
	local.equipped_stock = Contract.PART_STOCK_T2
	local.equipped_barrel = Contract.PART_BARREL_T2
	local.apply_shop({"you": {"marks": 10, "equippedOpticId": Contract.PART_OPTIC_T2, "equippedStockId": Contract.PART_STOCK_T2, "equippedBarrelId": Contract.PART_BARREL_T2}})
	_expect(failed, local.equipped_optic_id() == Contract.PART_OPTIC_T2, "T2 omitted feel keeps the equipped id")
	_expect(failed, not local.feel_wobble_from_server and not local.feel_window_from_server, "T2 omitted feel is not server")
	_expect(failed, is_equal_approx(local.attack_wobble_scale(), 1.0), "T2 omitted wobble stays 1")
	_expect(failed, is_equal_approx(local.feel_shot_window_sec, 1.2), "T2 omitted window stays 1.2")
	local.apply_shop({"you": {"marks": 10, "wobbleScale": 0.75, "shotWindowSec": 1.55, "equippedOpticId": Contract.PART_OPTIC_T2, "equippedStockId": Contract.PART_STOCK_T2, "equippedBarrelId": Contract.PART_BARREL_T2}})
	_expect(failed, local.feel_window_from_server and is_equal_approx(local.attack_shot_window_sec(), 1.55), "T2 attack window is server 1.55")
	_expect(failed, local.feel_wobble_from_server and is_equal_approx(local.attack_wobble_scale(), 0.75), "T2 attack wobble is server 0.75")
	var named: Snapshot = Snapshot.from_dict({"you": {"equippedOpticId": "gun_part_optic_t2", "equippedStockId": "gun_part_stock_t2", "equippedBarrelId": null, "wobbleScale": 0.75, "shotWindowSec": 1.55}})
	_expect(failed, named.you_equipped_optic_id() == Contract.PART_OPTIC_T2, "T2 snapshot optic id")
	_expect(failed, named.you_equipped_stock_id() == Contract.PART_STOCK_T2, "T2 snapshot stock id")
	_expect(failed, named.you_equipped_barrel_id() == "", "T2 snapshot null barrel")
	_expect(failed, is_equal_approx(float(named.you_shot_window_sec()), 1.55), "T2 snapshot shotWindowSec")
	_expect(failed, is_equal_approx(float(named.you_wobble_scale()), 0.75), "T2 snapshot wobbleScale")
	var session_src := FileAccess.get_file_as_string("res://autoload/client_session.gd")
	var optic_src := FileAccess.get_file_as_string("res://scenes/optic/optic_overlay.gd")
	var match_src := FileAccess.get_file_as_string("res://scenes/match/match_screen.gd")
	var lobby_src := FileAccess.get_file_as_string("res://scenes/lobby/hideout_lobby.gd")
	for src in [session_src, optic_src, match_src, lobby_src]:
		_expect(failed, src.find("local_wobble_scale") < 0 and src.find("local_shot_window_sec") < 0, "T2 client does not author feel")
		_expect(failed, src.find("SHOT_WINDOW_OPTIC_T2") < 0 and src.find("WOBBLE_STOCK_T2") < 0 and src.find("WOBBLE_BARREL_T2") < 0, "T2 client does not bake ladder juice")
	local.free()

	var practice: Dictionary = _part_practice_run(2)
	_expect(failed, bool(practice.get("ok", false)), "T2 practice loop ok")
	_expect(failed, _part_delta(practice.get("kill_delta")) == Contract.MARKS_PRACTICE, "T2 practice Marks Δ0")
	_expect(failed, bool(practice.get("wallet_held", false)), "T2 practice does not grant")
	_expect(failed, bool(practice.get("feel_window", false)), "T2 practice window 1.55")
	_expect(failed, bool(practice.get("feel_wobble", false)), "T2 practice wobble 0.75")
	_expect(failed, bool(practice.get("chance_formula", false)), "T2 practice hitChance ignores parts")
	server.reset_wallet(Contract.MOCK_WALLET_STUB)
	session.free()
	if failed.size() == before:
		print("PART_T2_OK")


func _part_peg_case(failed: PackedStringArray) -> void:
	## Unowned PARTS rows use the locked mute. Owned and equipped stay the bright pegs.
	var before := failed.size()
	var Chrome := load("res://scripts/chrome.gd")
	var unowned_state: String = Chrome.part_row_peg_state(false, false)
	var owned_state: String = Chrome.part_row_peg_state(true, false)
	var equipped_state: String = Chrome.part_row_peg_state(true, true)
	_expect(failed, unowned_state == "locked", "unowned PART peg is the locked mute")
	_expect(failed, owned_state == "owned", "owned PART peg stays the mid green")
	_expect(failed, equipped_state == "equipped", "equipped PART peg stays the lit leaf")
	var unowned_peg: Color = Chrome.rack_peg_color(unowned_state)
	var owned_peg: Color = Chrome.rack_peg_color(owned_state)
	var equipped_peg: Color = Chrome.rack_peg_color(equipped_state)
	_expect(failed, unowned_peg == Chrome.RACK_PEG_LOCKED, "unowned PART peg reuses the locked mute")
	_expect(failed, owned_peg == Chrome.RACK_PEG_OWNED and equipped_peg == Chrome.RACK_PEG_EQUIPPED, "owned and equipped PART pegs stay bright")
	_expect(failed, equipped_peg.g > owned_peg.g and owned_peg.g > unowned_peg.g, "PART peg greens read equipped > owned > unowned")
	_expect(failed, unowned_peg != Chrome.HIGH_GOLD and owned_peg != Chrome.HIGH_GOLD and equipped_peg != Chrome.HIGH_GOLD, "PART pegs are not gold strips")
	var peg: Panel = Chrome.rack_peg(unowned_state)
	_expect(failed, str(peg.get_meta("rack_peg_state", "")) == "locked", "unowned peg meta is locked")
	Chrome.paint_rack_peg(peg, equipped_state)
	_expect(failed, str(peg.get_meta("rack_peg_state", "")) == "equipped", "paint lifts a peg to equipped")
	peg.free()
	var lobby_src := FileAccess.get_file_as_string("res://scenes/lobby/hideout_lobby.gd")
	var refresh_at := lobby_src.find("func _refresh_shop")
	var refresh_fn := lobby_src.substr(refresh_at, lobby_src.find("func _ensure_shop_lines") - refresh_at)
	_expect(failed, refresh_fn.find("part_row_peg_state") >= 0, "PARTS refresh paints the row peg")
	_expect(failed, refresh_fn.find("\"EQUIPPED\"") < 0 and refresh_fn.find("\"LOCKED\"") < 0, "PARTS refresh has no gold state strips")
	var line_at := lobby_src.find("func _make_shop_line")
	var line_fn := lobby_src.substr(line_at, lobby_src.find("func _build_gun_rack") - line_at)
	_expect(failed, line_fn.find("rack_peg(\"locked\")") >= 0, "PARTS rows start on the muted peg")
	_expect(failed, line_fn.find("\"EQUIPPED\"") < 0 and line_fn.find("\"LOCKED\"") < 0, "PARTS rows have no gold state strips")
	if failed.size() == before:
		print("PART_PEG_OK")


func _part_delta(value: Variant) -> int:
	if value == null:
		return -999
	return int(value)


func _part_chance_ok(last: Variant) -> bool:
	if not (last is Dictionary):
		return false
	var high := bool(last.get("highGroundApplied", false))
	var cover := bool(last.get("coverApplied", false))
	var hit := bool(last.get("hit", false))
	var base := Contract.BASE_HIT_CHANCE if hit else 0.0
	var expect := clampf(
		base + (Contract.HIGH_GROUND_HIT if high else 0.0) - (Contract.BRUSH_COVER_HIT if cover else 0.0),
		0.0,
		1.0
	)
	return is_equal_approx(float(last.get("hitChance", -1.0)), expect)


func _part_combat_run(kitted: bool, tier: int = 1) -> Dictionary:
	server.clear_all()
	server.reset_wallet(800 if tier >= 2 else 400)
	if kitted and tier >= 2:
		server.buy_shop(Contract.PART_OPTIC_T2, "part-run-o2")
		server.buy_shop(Contract.PART_STOCK_T2, "part-run-s2")
		server.buy_shop(Contract.PART_BARREL_T2, "part-run-b2")
	elif kitted:
		server.buy_shop(Contract.PART_OPTIC, "part-run-o")
		server.buy_shop(Contract.PART_STOCK, "part-run-s")
		server.buy_shop(Contract.PART_BARREL, "part-run-b")
	var created: Dictionary = server.create_match()
	var mid := str(created.get("matchId", ""))
	var tokens: Dictionary = created.get("joinTokens", {})
	var join_a: Dictionary = server.join(mid, str(tokens.get("a", "")))
	var join_b: Dictionary = server.join(mid, str(tokens.get("b", "")))
	var pid_a := str(join_a.get("playerId", ""))
	var pid_b := str(join_b.get("playerId", ""))
	server.apply_action(mid, pid_a, ActionIntent.select_hex(2, 2))
	server.apply_action(mid, pid_b, ActionIntent.select_hex(7, 5))
	server.apply_action(mid, pid_a, ActionIntent.start())
	server.test_recon_roll = 0.1
	var recon: ActionResult = server.apply_action(mid, pid_a, ActionIntent.recon(7, 5))
	var recon_last: Variant = Snapshot.from_dict(recon.snapshot).last_action()
	server.apply_action(mid, pid_a, ActionIntent.end_turn(50))
	## B must spend the action phase before end_turn. Empty recon — rival stays on (7, 5).
	server.apply_action(mid, pid_b, ActionIntent.recon(0, 0))
	server.apply_action(mid, pid_b, ActionIntent.end_turn(40))
	var miss: ActionResult = server.apply_action(mid, pid_a, ActionIntent.attack(0, 0))
	var miss_snap: Snapshot = Snapshot.from_dict(miss.snapshot)
	var miss_last: Variant = miss_snap.last_action()
	server.apply_action(mid, pid_a, ActionIntent.end_turn(50))
	server.apply_action(mid, pid_b, ActionIntent.recon(1, 0))
	server.apply_action(mid, pid_b, ActionIntent.end_turn(40))
	var kill: ActionResult = server.apply_action(mid, pid_a, ActionIntent.attack(7, 5))
	var kill_snap: Snapshot = Snapshot.from_dict(kill.snapshot)
	var kill_last: Variant = kill_snap.last_action()
	return {
		"ok": bool(miss.ok) and bool(kill.ok) and bool(recon.ok),
		"miss_hit": miss_last is Dictionary and miss_last.get("hit") == false,
		"miss_chance": miss_last.get("hitChance", null) if miss_last is Dictionary else null,
		"kill_hit": kill_last is Dictionary and kill_last.get("hit") == true,
		"kill_delta": kill_snap.marks_delta(),
		"spotted": recon_last is Dictionary and bool(recon_last.get("spotted", false)),
		"exposure_floor": int(miss_snap.you_exposure_floor()),
		"chance_formula": _part_chance_ok(miss_last) and _part_chance_ok(kill_last),
	}


func _part_practice_run(tier: int = 1) -> Dictionary:
	server.clear_all()
	server.reset_wallet(800 if tier >= 2 else 400)
	if tier >= 2:
		server.buy_shop(Contract.PART_OPTIC_T2, "part-prac-o2")
		server.buy_shop(Contract.PART_STOCK_T2, "part-prac-s2")
		server.buy_shop(Contract.PART_BARREL_T2, "part-prac-b2")
	else:
		server.buy_shop(Contract.PART_OPTIC, "part-prac-o")
		server.buy_shop(Contract.PART_STOCK, "part-prac-s")
		server.buy_shop(Contract.PART_BARREL, "part-prac-b")
	var created: Dictionary = server.create_match({"mode": Contract.MODE_PRACTICE})
	var mid := str(created.get("matchId", ""))
	var join_a: Dictionary = server.join(mid, Contract.create_join_token(created))
	var pid_a := str(join_a.get("playerId", ""))
	var wallet_before := int(server.account_marks)
	server.apply_action(mid, pid_a, ActionIntent.select_hex(2, 2))
	server.apply_action(mid, pid_a, ActionIntent.start())
	var kill: ActionResult = server.apply_action(mid, pid_a, ActionIntent.attack(6, 1))
	var kill_snap: Snapshot = Snapshot.from_dict(kill.snapshot)
	var kill_last: Variant = kill_snap.last_action()
	return {
		"ok": bool(kill.ok),
		"kill_delta": kill_snap.marks_delta(),
		"wallet_held": int(server.account_marks) == wallet_before,
		"feel_window": kill_snap.you_shot_window_sec() != null and is_equal_approx(float(kill_snap.you_shot_window_sec()), 1.55 if tier >= 2 else 1.4),
		"feel_wobble": kill_snap.you_wobble_scale() != null and is_equal_approx(float(kill_snap.you_wobble_scale()), 0.75),
		"chance_formula": _part_chance_ok(kill_last),
	}


func _optic_joystick_case(failed: PackedStringArray) -> void:
	## Chrome only: circular thumb replaces the plate D-pad. Fire stays a tap.
	## Overlay needs ClientSession autoload — stick class + intent are the contract.
	var Chrome := load("res://scripts/chrome.gd")
	var well: Texture2D = Chrome.make_optic_stick_well(64)
	var knob: Texture2D = Chrome.make_optic_stick_knob(32)
	_expect(failed, well != null and well.get_width() == 64, "stick well texture")
	_expect(failed, knob != null and knob.get_width() == 32, "stick knob texture")
	var Joy := load("res://scenes/optic/optic_joystick.gd")
	var stick = Joy.new()
	var moved := [Vector2.ZERO]
	stick.stick_changed.connect(func(v: Vector2) -> void: moved[0] = v)
	stick.pose(Vector2(0.62, -0.38))
	_expect(failed, moved[0].length() > 0.4, "posing the thumb emits offset")
	_expect(failed, ActionIntent.attack(0, 0).get("type") == Contract.ACT_ATTACK, "attack intent unchanged")
	_expect(failed, not ActionIntent.attack(4, 3).has("stick"), "stick is not an attack field")
	stick.free()


func _chrome_reconfirm_case(failed: PackedStringArray) -> void:
	## Rack crops sit on the painted bolts. Optic is the landscape plate, above hex faces.
	var Art := load("res://scripts/art_pack.gd")
	_expect(failed, Art.rack_position("gun_fieldbolt") == Vector2(24, 192), "Fieldbolt hang")
	_expect(failed, Art.rack_size("gun_fieldbolt") == Vector2(268, 56), "Fieldbolt hang size")
	_expect(failed, Art.rack_position("gun_railframe") == Vector2(24, 252), "Railframe hang")
	_expect(failed, Art.rack_position("gun_crescent") == Vector2(24, 318), "Crescent sits on the painted body")
	_expect(failed, Art.rack_size("gun_crescent") == Vector2(268, 50), "Crescent crop is 268×50")
	var cres: Texture2D = Art.rifle_texture("gun_crescent", "owned")
	var cres_lock: Texture2D = Art.rifle_texture("gun_crescent", "locked")
	_expect(failed, cres != null and cres.get_width() == 268 and cres.get_height() == 50, "Crescent owned crop matches hang")
	_expect(failed, cres_lock != null and cres_lock.get_width() == 268 and cres_lock.get_height() == 50, "Crescent locked wash matches hang")
	_expect(failed, Art.HELD_POS == Vector2(628, 348), "hands sit on the painted bolt")
	_expect(failed, Art.HELD_SIZE == Vector2(192, 52), "hands crop is the plate bolt")
	var held: Texture2D = Art.rifle_held_texture()
	_expect(failed, held != null and held.get_width() == 192 and held.get_height() == 52, "held texture matches the bolt")
	var optic_src := FileAccess.get_file_as_string("res://scenes/optic/optic_overlay.gd")
	_expect(failed, optic_src.find("optic-attack.jpg") >= 0, "Attack optic uses the landscape plate")
	_expect(failed, optic_src.find("z_index = 36") >= 0, "landscape plate draws above hex faces")
	_expect(failed, optic_src.find("hex_tile") < 0 and optic_src.find("hex_stamp") < 0, "optic does not stamp a hex through the scope")
	## Soft P2: rack state is painted green pegs. No gold EQUIPPED / OWNED / LOCKED strips.
	var hud_src := FileAccess.get_file_as_string("res://scenes/lobby/hideout_lobby.gd")
	var rack_at := hud_src.find("func _refresh_gun_rack")
	var rack_fn := hud_src.substr(rack_at, hud_src.find("func _on_rack_stamp_input") - rack_at)
	_expect(failed, rack_fn.find("HIGH_GOLD") < 0, "rack refresh has no gold strip")
	_expect(failed, rack_fn.find("\"EQUIPPED\"") < 0 and rack_fn.find("\"OWNED\"") < 0 and rack_fn.find("\"LOCKED\"") < 0, "rack has no state text strips")
	_expect(failed, rack_fn.find("rack_peg") >= 0, "rack paints a state peg")
	_expect(failed, rack_fn.find("rifle_texture(gid, \"owned\")") >= 0, "rack keeps the painted bolt")
	_expect(failed, rack_fn.find("\"locked\" if state") < 0, "rack does not swap in the grey wash")
	var equipped_peg: Color = Chrome.rack_peg_color("equipped")
	var owned_peg: Color = Chrome.rack_peg_color("owned")
	var locked_peg: Color = Chrome.rack_peg_color("locked")
	_expect(failed, equipped_peg.g > equipped_peg.r and equipped_peg.g > equipped_peg.b, "equipped peg is painted green")
	_expect(failed, owned_peg.g > owned_peg.r and owned_peg.g > owned_peg.b, "owned peg is painted green")
	_expect(failed, locked_peg.g > locked_peg.r and locked_peg.g > locked_peg.b, "locked peg is painted green")
	_expect(failed, equipped_peg.g > owned_peg.g and owned_peg.g > locked_peg.g, "peg greens read equipped > owned > locked")
	_expect(failed, equipped_peg != Chrome.HIGH_GOLD and owned_peg != Chrome.HIGH_GOLD and locked_peg != Chrome.HIGH_GOLD, "pegs are not gold strips")
	var locked_mod: Color = Chrome.rack_bolt_modulate("locked")
	_expect(failed, locked_mod.g > locked_mod.r and locked_mod.g >= locked_mod.b, "locked bolt modulate stays green")
	_expect(failed, Chrome.rack_bolt_modulate("owned") == Color.WHITE, "owned bolt keeps the plate paint")


func _match_board_chrome_case(failed: PackedStringArray) -> void:
	## Stamps come from the snapshot. HIGH GROUND is display-only.
	var Board := load("res://scenes/match/hex_board.gd")
	var board = Board.new()
	_expect(failed, board.cell_kind(2, 2) == "unknown", "unrevealed hex is FoW")
	board._terrain["2,2"] = Contract.TYPE_BRUSH
	_expect(failed, board.cell_kind(2, 2) == Contract.TYPE_BRUSH, "revealed stamp from snapshot")
	_expect(failed, board.cell_kind(0, 0) == "unknown", "rim stays unknown until snapshot")
	_expect(failed, not ActionIntent.attack(4, 3).has("highGround"), "HIGH GROUND is not an attack field")
	_expect(failed, Contract.HIGH_GROUND_SUB.find("10%") >= 0, "HIGH GROUND copy names +10%")
	var created: Dictionary = server.create_match()
	var mid := str(created.get("matchId", ""))
	var tokens: Dictionary = created.get("joinTokens", {})
	var join_a: Dictionary = server.join(mid, str(tokens.get("a", "")))
	server.join(mid, str(tokens.get("b", "")))
	server.reveal_inner_for_art(mid)
	var raw: Dictionary = server.get_snapshot(mid, str(join_a.get("playerId", "")))
	var snap: Snapshot = Snapshot.from_dict(raw)
	_expect(failed, snap.terrain_map().size() >= 20, "art reveal ships inner stamps")
	_expect(failed, not snap.terrain_map().has("0,0"), "art reveal leaves rim unknown")
	board.free()

	server.clear_all()
	var fresh: Dictionary = server.create_match()
	var fid := str(fresh.get("matchId", ""))
	var ftok: Dictionary = fresh.get("joinTokens", {})
	var fa: Dictionary = server.join(fid, str(ftok.get("a", "")))
	server.join(fid, str(ftok.get("b", "")))
	var pid := str(fa.get("playerId", ""))
	var empty: Snapshot = Snapshot.from_dict(server.get_snapshot(fid, pid))
	_expect(failed, empty.terrain_map().is_empty(), "no stamps before first select")
	var drop: ActionResult = server.apply_action(fid, pid, ActionIntent.select_hex(2, 2))
	_expect(failed, drop.ok, "first select ok")
	var after: Snapshot = Snapshot.from_dict(drop.snapshot)
	var mapped: Dictionary = after.terrain_map()
	_expect(failed, mapped.size() == 1, "snapshot ships only the selected stamp")
	_expect(failed, mapped.has("2,2"), "first select materializes 2,2")
	var kind := str(mapped.get("2,2", ""))
	_expect(failed, kind == Contract.TYPE_OPEN or kind == Contract.TYPE_BRUSH or kind == Contract.TYPE_HARD, "hash type is open/brush/hard")
	_expect(failed, not mapped.has("4,3"), "unselected hex is not in snapshot")
	var again: ActionResult = server.apply_action(fid, pid, ActionIntent.select_hex(2, 2))
	_expect(failed, again.ok, "re-drop same hex ok")
	_expect(failed, str(Snapshot.from_dict(again.snapshot).terrain_map().get("2,2", "")) == kind, "first-select type is stable")
	var fog: Snapshot = Snapshot.from_dict({"terrain": [{"q": 1, "r": 1, "type": "unknown"}, {"q": 1, "r": 2}]})
	_expect(failed, fog.terrain_map().is_empty(), "unknown / typeless rows stay FoW")
	var Art := load("res://scripts/art_pack.gd")
	var face_a: Texture2D = Art.hex_tile(Contract.TYPE_BRUSH, 0)
	var face_b: Texture2D = Art.hex_tile(Contract.TYPE_BRUSH, 99)
	_expect(failed, face_a != null and face_b != null, "brush stamp loads")
	_expect(failed, face_a.get_image().get_data() == face_b.get_image().get_data(), "stamp is tileable, not a unique map face")
	var plate: Texture2D = Art.match_board_plate()
	_expect(failed, plate != null and plate.get_width() >= 1200, "match-board plate loads")
	var Chrome := load("res://scripts/chrome.gd")
	var hot: Button = Chrome.plate_hotspot(Vector2(284, 104))
	_expect(failed, hot.custom_minimum_size.x == 284, "plate key hotspot matches painted button")
	hot.free()
	var chip: Control = Chrome.high_ground_chip(false)
	_expect(failed, chip != null and not (chip is Button), "HIGH GROUND is a chip, not an action key")
	chip.free()


func _high_ground_case(failed: PackedStringArray) -> void:
	## H1–H6: snapshot you.highGroundActive · chip bind · never invent · attack unchanged.
	server.clear_all()
	server.reset_wallet(0)
	var created: Dictionary = server.create_match()
	var mid := str(created.get("matchId", ""))
	var tokens: Dictionary = created.get("joinTokens", {})
	var join_a: Dictionary = server.join(mid, str(tokens.get("a", "")))
	var join_b: Dictionary = server.join(mid, str(tokens.get("b", "")))
	var pid_a := str(join_a.get("playerId", ""))
	var pid_b := str(join_b.get("playerId", ""))
	var hard: Dictionary = server.find_hex_of_type(mid, Contract.TYPE_HARD)
	var open_hex: Dictionary = server.find_hex_of_type(mid, Contract.TYPE_OPEN)
	_expect(failed, not hard.is_empty(), "H1 board has a HARD hex")
	_expect(failed, not open_hex.is_empty(), "H2 board has an OPEN hex")
	_expect(failed, not server.find_hex_of_type(mid, Contract.TYPE_BRUSH).is_empty(), "H2 board has a BRUSH hex")

	var r: ActionResult = server.apply_action(mid, pid_a, ActionIntent.select_hex(int(hard.get("q", 0)), int(hard.get("r", 0))))
	_expect(failed, r.ok, "H1 A drop HARD")
	var snap: Snapshot = Snapshot.from_dict(r.snapshot)
	_expect(failed, snap.you_high_ground_active(), "H1 HARD → you.highGroundActive true")
	_expect(failed, snap.you().has("highGroundActive"), "H1 snapshot names the flag")
	r = server.apply_action(mid, pid_b, ActionIntent.select_hex(int(open_hex.get("q", 1)), int(open_hex.get("r", 0))))
	_expect(failed, r.ok, "H2 B drop OPEN")
	var b_snap: Snapshot = Snapshot.from_dict(server.get_snapshot(mid, pid_b))
	_expect(failed, not b_snap.you_high_ground_active(), "H2 OPEN → false")
	_expect(failed, Snapshot.from_dict(server.get_snapshot(mid, pid_a)).you_high_ground_active(), "H5 attacker HARD ignores defender OPEN")

	r = server.apply_action(mid, pid_a, ActionIntent.start())
	_expect(failed, r.ok, "H1 start")
	var empty := Contract.hex_dict(0, 0)
	for rr in Contract.BOARD_R:
		for qq in Contract.BOARD_Q:
			if Contract.same_hex(Contract.hex_dict(qq, rr), hard):
				continue
			if Contract.same_hex(Contract.hex_dict(qq, rr), open_hex):
				continue
			empty = Contract.hex_dict(qq, rr)
			break
		if not Contract.same_hex(empty, hard) and not Contract.same_hex(empty, open_hex):
			break
	var intent := ActionIntent.attack(int(empty.get("q", 0)), int(empty.get("r", 0)))
	_expect(failed, intent.get("type") == Contract.ACT_ATTACK, "H6 type attack")
	_expect(failed, intent.has("hex"), "H6 hex present")
	_expect(failed, not intent.has("highGround"), "H6 no highGround field")
	_expect(failed, not intent.has("highGroundActive"), "H6 no highGroundActive field")
	_expect(failed, not intent.has("hitChance"), "H6 no hitChance on intent")
	var marks_before: int = Snapshot.from_dict(server.get_snapshot(mid, pid_a)).you_marks()
	r = server.apply_action(mid, pid_a, intent)
	_expect(failed, r.ok, "H1 attack from HARD")
	snap = Snapshot.from_dict(r.snapshot)
	var last: Variant = snap.last_action()
	_expect(failed, snap.you_high_ground_active(), "H1 miss snapshot flag still true")
	_expect(failed, last is Dictionary and last.get("highGroundApplied") == false, "H1 empty miss does not apply")
	_expect(failed, last is Dictionary and is_equal_approx(float(last.get("hitChance", -1)), 0.0), "H1 empty miss hitChance 0")
	_expect(failed, last is Dictionary and last.get("hit") == false, "H1 miss still miss")
	_expect(failed, snap.you_marks() == marks_before, "H4 miss does not change Marks")
	_expect(failed, snap.decoy_available(), "H4 decoy charge untouched")
	_expect(failed, snap.uav_remaining() == 1, "H4 UAV charge untouched")
	server.apply_action(mid, pid_a, ActionIntent.end_turn(50))
	server.apply_action(mid, pid_b, ActionIntent.recon(4, 3))
	server.apply_action(mid, pid_b, ActionIntent.end_turn(50))
	r = server.apply_action(mid, pid_a, ActionIntent.attack(int(open_hex.get("q", 1)), int(open_hex.get("r", 0))))
	last = Snapshot.from_dict(r.snapshot).last_action()
	_expect(failed, last is Dictionary and last.get("hit") == true, "H1 HARD occupy hits")
	_expect(failed, last is Dictionary and last.get("highGroundApplied") == true, "H1 HARD occupy applied")
	_expect(failed, last is Dictionary and is_equal_approx(float(last.get("hitChance", -1)), 1.0), "H1 HARD occupy hitChance 1.0")

	## Client never invents from a local HARD hex when the flag is omitted.
	var invented: Snapshot = Snapshot.from_dict({
		"you": {"hex": hard, "seat": "a"},
		"terrain": [{"q": int(hard.get("q", 0)), "r": int(hard.get("r", 0)), "type": Contract.TYPE_HARD}],
	})
	_expect(failed, not invented.you_high_ground_active(), "H3 missing flag stays false")
	_expect(failed, invented.terrain_map().has("%d,%d" % [int(hard.get("q", 0)), int(hard.get("r", 0))]), "H3 terrain parse still works")

	server.clear_all()
	var fresh: Dictionary = server.create_match()
	var fid := str(fresh.get("matchId", ""))
	var ftok: Dictionary = fresh.get("joinTokens", {})
	var fa: Dictionary = server.join(fid, str(ftok.get("a", "")))
	var fb: Dictionary = server.join(fid, str(ftok.get("b", "")))
	var pa := str(fa.get("playerId", ""))
	var pb := str(fb.get("playerId", ""))
	var open2: Dictionary = server.find_hex_of_type(fid, Contract.TYPE_OPEN)
	var hard2: Dictionary = server.find_hex_of_type(fid, Contract.TYPE_HARD)
	server.apply_action(fid, pa, ActionIntent.select_hex(int(open2.get("q", 0)), int(open2.get("r", 0))))
	server.apply_action(fid, pb, ActionIntent.select_hex(int(hard2.get("q", 1)), int(hard2.get("r", 0))))
	_expect(failed, not Snapshot.from_dict(server.get_snapshot(fid, pa)).you_high_ground_active(), "H2 A OPEN muted")
	_expect(failed, Snapshot.from_dict(server.get_snapshot(fid, pb)).you_high_ground_active(), "H5 B HARD not from A OPEN")
	server.apply_action(fid, pa, ActionIntent.start())
	var empty2 := Contract.hex_dict(0, 0)
	for rr2 in Contract.BOARD_R:
		for qq2 in Contract.BOARD_Q:
			if Contract.same_hex(Contract.hex_dict(qq2, rr2), open2) or Contract.same_hex(Contract.hex_dict(qq2, rr2), hard2):
				continue
			empty2 = Contract.hex_dict(qq2, rr2)
			break
		if not Contract.same_hex(empty2, open2) and not Contract.same_hex(empty2, hard2):
			break
	r = server.apply_action(fid, pa, ActionIntent.attack(int(empty2.get("q", 0)), int(empty2.get("r", 0))))
	last = Snapshot.from_dict(r.snapshot).last_action()
	_expect(failed, last is Dictionary and last.get("highGroundApplied") == false, "H2 OPEN highGroundApplied false")
	_expect(failed, last is Dictionary and is_equal_approx(float(last.get("hitChance", -1)), 0.0), "H2 OPEN miss hitChance 0")
	server.apply_action(fid, pa, ActionIntent.end_turn(50))
	server.apply_action(fid, pb, ActionIntent.recon(4, 3))
	server.apply_action(fid, pb, ActionIntent.end_turn(50))
	r = server.apply_action(fid, pa, ActionIntent.attack(int(hard2.get("q", 1)), int(hard2.get("r", 0))))
	last = Snapshot.from_dict(r.snapshot).last_action()
	_expect(failed, last is Dictionary and last.get("hit") == true, "H2 OPEN occupy still hits (mock deterministic)")
	_expect(failed, last is Dictionary and last.get("highGroundApplied") == false, "H2 OPEN occupy not applied")
	_expect(failed, last is Dictionary and is_equal_approx(float(last.get("hitChance", -1)), Contract.BASE_HIT_CHANCE), "H2 OPEN occupy hitChance 0.90")

	## Brush drop. Fresh match for BRUSH attacker.
	server.clear_all()
	var third: Dictionary = server.create_match()
	var tid := str(third.get("matchId", ""))
	var ttok: Dictionary = third.get("joinTokens", {})
	var ta: Dictionary = server.join(tid, str(ttok.get("a", "")))
	var tb: Dictionary = server.join(tid, str(ttok.get("b", "")))
	var tpa := str(ta.get("playerId", ""))
	var tpb := str(tb.get("playerId", ""))
	var brush3: Dictionary = server.find_hex_of_type(tid, Contract.TYPE_BRUSH)
	var hard3: Dictionary = server.find_hex_of_type(tid, Contract.TYPE_HARD)
	server.apply_action(tid, tpa, ActionIntent.select_hex(int(brush3.get("q", 0)), int(brush3.get("r", 0))))
	server.apply_action(tid, tpb, ActionIntent.select_hex(int(hard3.get("q", 1)), int(hard3.get("r", 0))))
	_expect(failed, not Snapshot.from_dict(server.get_snapshot(tid, tpa)).you_high_ground_active(), "H2 BRUSH → false")
	_expect(failed, Snapshot.from_dict(server.get_snapshot(tid, tpb)).you_high_ground_active(), "H5 defender HARD ignored for attacker BRUSH")

	var fog: Snapshot = Snapshot.from_dict({"you": {"hex": {"q": 4, "r": 3}}})
	_expect(failed, not fog.you_high_ground_active(), "H2 FoW / omitted flag is false")
	var bare_atk: Snapshot = Snapshot.from_dict({"lastAction": {"type": Contract.ACT_ATTACK, "hit": false}})
	_expect(failed, bare_atk.last_high_ground_applied() == null, "H3 omitted highGroundApplied is null")
	_expect(failed, bare_atk.last_hit_chance() == null, "H3 omitted hitChance is null")
	var named_atk: Snapshot = Snapshot.from_dict({
		"lastAction": {"type": Contract.ACT_ATTACK, "hit": true, "highGroundApplied": true, "hitChance": 1.0},
	})
	_expect(failed, named_atk.last_high_ground_applied() == true, "H3 reads server highGroundApplied")
	_expect(failed, is_equal_approx(float(named_atk.last_hit_chance()), 1.0), "H3 reads server hitChance")

	var Chrome := load("res://scripts/chrome.gd")
	var muted: Control = Chrome.high_ground_chip(false)
	var lit: Control = Chrome.high_ground_chip(true)
	_expect(failed, muted != null and not (muted is Button), "H3 muted chip is not a key")
	_expect(failed, lit != null and not (lit is Button), "H3 lit chip is not a key")
	var muted_lbl: Label = muted.get_meta("high_label")
	var lit_lbl: Label = lit.get_meta("high_label")
	_expect(failed, muted_lbl != null and muted_lbl.text.find("+10") < 0, "H3 muted does not read +10%")
	_expect(failed, lit_lbl != null and lit_lbl.text.find("+10") >= 0, "H3 lit reads +10%")
	Chrome.paint_high_ground_chip(muted, true)
	_expect(failed, muted_lbl.text.find("+10") >= 0, "H3 paint lights from snapshot true")
	Chrome.paint_high_ground_chip(muted, false)
	_expect(failed, muted_lbl.text.find("+10") < 0, "H3 paint mutes from snapshot false")
	muted.free()
	lit.free()

	## Mock stills toggle — never a client-invented bonus.
	server.clear_all()
	var tog: Dictionary = server.create_match()
	var tmid := str(tog.get("matchId", ""))
	var tjoin: Dictionary = server.join(tmid, str(tog.get("joinTokens", {}).get("a", "")))
	server.join(tmid, str(tog.get("joinTokens", {}).get("b", "")))
	var tpid := str(tjoin.get("playerId", ""))
	var open_t: Dictionary = server.find_hex_of_type(tmid, Contract.TYPE_OPEN)
	server.apply_action(tmid, tpid, ActionIntent.select_hex(int(open_t.get("q", 0)), int(open_t.get("r", 0))))
	_expect(failed, not Snapshot.from_dict(server.get_snapshot(tmid, tpid)).you_high_ground_active(), "toggle off default OPEN")
	server.test_high_ground_active = true
	_expect(failed, Snapshot.from_dict(server.get_snapshot(tmid, tpid)).you_high_ground_active(), "stills toggle forces lit")
	server.test_high_ground_active = false
	var hard_t: Dictionary = server.find_hex_of_type(tmid, Contract.TYPE_HARD)
	server.apply_action(tmid, tpid, ActionIntent.select_hex(int(hard_t.get("q", 0)), int(hard_t.get("r", 0))))
	_expect(failed, not Snapshot.from_dict(server.get_snapshot(tmid, tpid)).you_high_ground_active(), "stills toggle forces muted on HARD")
	server.test_high_ground_active = null


func _brush_cover_case(failed: PackedStringArray) -> void:
	## B1–B6: target BRUSH −0.10 · stacks with HIGH GROUND · no IN COVER chip.
	server.clear_all()
	server.reset_wallet(0)
	var chrome_src := FileAccess.get_file_as_string("res://scripts/chrome.gd")
	var hud_src := FileAccess.get_file_as_string("res://scenes/match/match_screen.gd")
	_expect(failed, chrome_src.find("func cover_chip") < 0, "B5 no cover_chip")
	_expect(failed, chrome_src.find("func paint_cover_chip") < 0, "B5 no paint_cover_chip")
	_expect(failed, chrome_src.find("\"IN COVER\"") < 0, "B5 chrome has no IN COVER label")
	_expect(failed, hud_src.find("\"IN COVER\"") < 0, "B5 match HUD has no IN COVER label")
	var intent := ActionIntent.attack(4, 3)
	_expect(failed, intent.get("type") == Contract.ACT_ATTACK, "intent type attack")
	_expect(failed, intent.has("hex"), "intent hex present")
	_expect(failed, not intent.has("cover"), "intent has no cover")
	_expect(failed, not intent.has("coverApplied"), "intent has no coverApplied")
	_expect(failed, not intent.has("hitChance"), "intent has no hitChance")

	var bare: Snapshot = Snapshot.from_dict({"lastAction": {"type": Contract.ACT_ATTACK, "hit": true}})
	_expect(failed, bare.last_cover_applied() == null, "B2 omitted coverApplied is null")
	_expect(failed, bare.last_hit_chance() == null, "B2 omitted hitChance is null")
	var fog_line := Chrome.describe_attack_result({"type": Contract.ACT_ATTACK, "hit": true})
	_expect(failed, fog_line.find("Brush cover") < 0, "B2 FoW toast does not invent cover")
	_expect(failed, fog_line.find("IN COVER") < 0, "B5 toast never says IN COVER")
	_expect(failed, fog_line.find("(server)") < 0, "A5 hit toast has no (server)")
	var named: Snapshot = Snapshot.from_dict({
		"lastAction": {
			"type": Contract.ACT_ATTACK,
			"hit": true,
			"coverApplied": true,
			"highGroundApplied": false,
			"hitChance": 0.80,
		},
	})
	_expect(failed, named.last_cover_applied() == true, "B5 reads server coverApplied")
	_expect(failed, named.last_high_ground_applied() == false, "B5 reads server highGroundApplied")
	_expect(failed, is_equal_approx(float(named.last_hit_chance()), 0.80), "B5 reads server hitChance 0.80")
	var plate := Chrome.describe_attack_result(named.last_action())
	_expect(failed, plate.find("80%") >= 0, "B5 toast names chance")
	_expect(failed, plate.find(Contract.COVER_APPLIED_COPY) >= 0, "B5 toast names brush cover")
	_expect(failed, plate.find(Contract.HIGH_GROUND_SKIPPED_COPY) >= 0, "B5 toast names no high ground")
	_expect(failed, plate.find("IN COVER") < 0, "B5 plate copy is not IN COVER")
	_expect(failed, plate.find("defilade") < 0 and plate.find("concealment") < 0, "B5 plate language not mil-sim")
	_expect(failed, plate.find("(server)") < 0, "A5 plate toast has no (server)")
	var invented: Snapshot = Snapshot.from_dict({
		"you": {"hex": {"q": 1, "r": 0}, "seat": "a"},
		"enemy": {"visibleHex": {"q": 0, "r": 0}},
		"terrain": [{"q": 0, "r": 0, "type": Contract.TYPE_BRUSH}],
		"lastAction": {"type": Contract.ACT_ATTACK, "hit": true},
	})
	_expect(failed, invented.last_cover_applied() == null, "never invent cover from local BRUSH")
	_expect(failed, invented.terrain_map().has("0,0"), "terrain parse still works")

	## B1 / B4 / B6: OPEN → BRUSH occupy 0.80. Empty and decoy stay miss 0.
	var created: Dictionary = server.create_match()
	var mid := str(created.get("matchId", ""))
	var tokens: Dictionary = created.get("joinTokens", {})
	var join_a: Dictionary = server.join(mid, str(tokens.get("a", "")))
	var join_b: Dictionary = server.join(mid, str(tokens.get("b", "")))
	var pid_a := str(join_a.get("playerId", ""))
	var pid_b := str(join_b.get("playerId", ""))
	var open_hex: Dictionary = server.find_hex_of_type(mid, Contract.TYPE_OPEN)
	var brush_hex: Dictionary = server.find_hex_of_type(mid, Contract.TYPE_BRUSH)
	_expect(failed, not open_hex.is_empty(), "B1 board has OPEN")
	_expect(failed, not brush_hex.is_empty(), "B1 board has BRUSH")
	server.equipped_gun = Contract.GUN_RAILFRAME
	var r: ActionResult = server.apply_action(mid, pid_a, ActionIntent.select_hex(int(open_hex.get("q", 0)), int(open_hex.get("r", 0))))
	_expect(failed, r.ok, "B1 A drop OPEN")
	r = server.apply_action(mid, pid_b, ActionIntent.select_hex(int(brush_hex.get("q", 1)), int(brush_hex.get("r", 0))))
	_expect(failed, r.ok, "B1 B drop BRUSH")
	r = server.apply_action(mid, pid_a, ActionIntent.start())
	_expect(failed, r.ok, "B1 start")
	var empty := Contract.hex_dict(0, 0)
	for rr in Contract.BOARD_R:
		for qq in Contract.BOARD_Q:
			var cell := Contract.hex_dict(qq, rr)
			if Contract.same_hex(cell, open_hex) or Contract.same_hex(cell, brush_hex):
				continue
			empty = cell
			break
		if not Contract.same_hex(empty, open_hex) and not Contract.same_hex(empty, brush_hex):
			break
	var marks_before: int = Snapshot.from_dict(server.get_snapshot(mid, pid_a)).you_marks()
	r = server.apply_action(mid, pid_a, ActionIntent.attack(int(empty.get("q", 0)), int(empty.get("r", 0))))
	_expect(failed, r.ok, "B4 empty miss ok")
	var snap: Snapshot = Snapshot.from_dict(r.snapshot)
	var last: Variant = snap.last_action()
	_expect(failed, last is Dictionary and last.get("hit") == false, "B4 empty miss")
	_expect(failed, last is Dictionary and last.get("coverApplied") == false, "B4 empty coverApplied false")
	_expect(failed, last is Dictionary and last.get("highGroundApplied") == false, "B4 empty highGroundApplied false")
	_expect(failed, last is Dictionary and is_equal_approx(float(last.get("hitChance", -1)), 0.0), "B4 empty hitChance 0")
	_expect(failed, snap.you_marks() == marks_before, "B6 miss Marks Δ0")
	_expect(failed, snap.decoy_available(), "B6 decoy charge untouched")
	_expect(failed, snap.uav_remaining() == 1, "B6 UAV charge untouched")
	_expect(failed, snap.you_equipped_gun_id() == Contract.GUN_RAILFRAME, "B6 gun chrome still equipped")
	server.apply_action(mid, pid_a, ActionIntent.end_turn(50))
	r = server.apply_action(mid, pid_b, ActionIntent.decoy())
	_expect(failed, r.ok, "B4 B plants doll")
	var doll: Variant = Snapshot.from_dict(r.snapshot).you_decoy_hex()
	_expect(failed, doll is Dictionary, "B4 doll hex")
	server.apply_action(mid, pid_b, ActionIntent.end_turn(50))
	r = server.apply_action(mid, pid_a, ActionIntent.attack(int(doll.get("q", 0)), int(doll.get("r", 0))))
	last = Snapshot.from_dict(r.snapshot).last_action()
	_expect(failed, last is Dictionary and last.get("hit") == false, "B4 decoy still miss")
	_expect(failed, last is Dictionary and last.get("decoyCleared") == true, "B4 decoy cleared")
	_expect(failed, last is Dictionary and last.get("coverApplied") == false, "B4 decoy coverApplied false")
	_expect(failed, last is Dictionary and is_equal_approx(float(last.get("hitChance", -1)), 0.0), "B4 decoy hitChance 0")
	_expect(failed, Chrome.describe_attack_result(last).find("Toy doll") >= 0, "B4 doll toast")
	_expect(failed, Snapshot.from_dict(r.snapshot).you_marks() == marks_before, "B6 decoy miss Marks Δ0")
	server.apply_action(mid, pid_a, ActionIntent.end_turn(50))
	server.apply_action(mid, pid_b, ActionIntent.recon(4, 3))
	server.apply_action(mid, pid_b, ActionIntent.end_turn(50))
	r = server.apply_action(mid, pid_a, ActionIntent.attack(int(brush_hex.get("q", 1)), int(brush_hex.get("r", 0))))
	snap = Snapshot.from_dict(r.snapshot)
	last = snap.last_action()
	_expect(failed, last is Dictionary and last.get("hit") == true, "B1 OPEN→BRUSH occupy hits")
	_expect(failed, last is Dictionary and last.get("coverApplied") == true, "B1 coverApplied true")
	_expect(failed, last is Dictionary and last.get("highGroundApplied") == false, "B3 OPEN no high ground")
	_expect(failed, last is Dictionary and is_equal_approx(float(last.get("hitChance", -1)), 0.80), "B3 OPEN→BRUSH 0.80")
	_expect(failed, snap.you_marks() == Contract.MARKS_PVP_WIN, "B6 kill table +32 not extra")
	_expect(failed, Chrome.describe_attack_result(last).find("80%") >= 0, "B1 toast chance 80%")

	## B3 HARD → BRUSH = 0.90
	server.clear_all()
	server.reset_wallet(0)
	server.equipped_gun = Contract.GUN_CRESCENT
	var stack: Dictionary = server.create_match()
	var sid := str(stack.get("matchId", ""))
	var stok: Dictionary = stack.get("joinTokens", {})
	var sa: Dictionary = server.join(sid, str(stok.get("a", "")))
	var sb: Dictionary = server.join(sid, str(stok.get("b", "")))
	var spa := str(sa.get("playerId", ""))
	var spb := str(sb.get("playerId", ""))
	var hard_hex: Dictionary = server.find_hex_of_type(sid, Contract.TYPE_HARD)
	var brush2: Dictionary = server.find_hex_of_type(sid, Contract.TYPE_BRUSH)
	server.apply_action(sid, spa, ActionIntent.select_hex(int(hard_hex.get("q", 0)), int(hard_hex.get("r", 0))))
	server.apply_action(sid, spb, ActionIntent.select_hex(int(brush2.get("q", 1)), int(brush2.get("r", 0))))
	server.apply_action(sid, spa, ActionIntent.start())
	r = server.apply_action(sid, spa, ActionIntent.attack(int(brush2.get("q", 1)), int(brush2.get("r", 0))))
	last = Snapshot.from_dict(r.snapshot).last_action()
	_expect(failed, last is Dictionary and last.get("coverApplied") == true, "B3 HARD→BRUSH cover")
	_expect(failed, last is Dictionary and last.get("highGroundApplied") == true, "B3 HARD→BRUSH high ground")
	_expect(failed, last is Dictionary and is_equal_approx(float(last.get("hitChance", -1)), 0.90), "B3 HARD→BRUSH 0.90")
	_expect(failed, Snapshot.from_dict(r.snapshot).you_marks() == Contract.MARKS_PVP_WIN, "B6 stacked kill still +32")
	_expect(failed, Snapshot.from_dict(r.snapshot).you_equipped_gun_id() == Contract.GUN_CRESCENT, "B6 crescent chrome-blind")

	## B2 target OPEN / HARD → no cover mod
	server.clear_all()
	server.reset_wallet(0)
	var off: Dictionary = server.create_match()
	var oid := str(off.get("matchId", ""))
	var otok: Dictionary = off.get("joinTokens", {})
	var oa: Dictionary = server.join(oid, str(otok.get("a", "")))
	var ob: Dictionary = server.join(oid, str(otok.get("b", "")))
	var opa := str(oa.get("playerId", ""))
	var opb := str(ob.get("playerId", ""))
	var open2: Dictionary = server.find_hex_of_type(oid, Contract.TYPE_OPEN)
	var hard2: Dictionary = server.find_hex_of_type(oid, Contract.TYPE_HARD)
	server.apply_action(oid, opa, ActionIntent.select_hex(int(open2.get("q", 0)), int(open2.get("r", 0))))
	server.apply_action(oid, opb, ActionIntent.select_hex(int(hard2.get("q", 1)), int(hard2.get("r", 0))))
	server.apply_action(oid, opa, ActionIntent.start())
	r = server.apply_action(oid, opa, ActionIntent.attack(int(hard2.get("q", 1)), int(hard2.get("r", 0))))
	last = Snapshot.from_dict(r.snapshot).last_action()
	_expect(failed, last is Dictionary and last.get("coverApplied") == false, "B2 OPEN→HARD no cover")
	_expect(failed, last is Dictionary and last.get("highGroundApplied") == false, "B2 OPEN no high ground")
	_expect(failed, last is Dictionary and is_equal_approx(float(last.get("hitChance", -1)), Contract.BASE_HIT_CHANCE), "B2 OPEN→HARD 0.90")

	server.clear_all()
	var hard_open: Dictionary = server.create_match()
	var hid := str(hard_open.get("matchId", ""))
	var htok: Dictionary = hard_open.get("joinTokens", {})
	var ha: Dictionary = server.join(hid, str(htok.get("a", "")))
	var hb: Dictionary = server.join(hid, str(htok.get("b", "")))
	var hpa := str(ha.get("playerId", ""))
	var hpb := str(hb.get("playerId", ""))
	var hard3: Dictionary = server.find_hex_of_type(hid, Contract.TYPE_HARD)
	var open3: Dictionary = server.find_hex_of_type(hid, Contract.TYPE_OPEN)
	server.apply_action(hid, hpa, ActionIntent.select_hex(int(hard3.get("q", 0)), int(hard3.get("r", 0))))
	server.apply_action(hid, hpb, ActionIntent.select_hex(int(open3.get("q", 1)), int(open3.get("r", 0))))
	server.apply_action(hid, hpa, ActionIntent.start())
	r = server.apply_action(hid, hpa, ActionIntent.attack(int(open3.get("q", 1)), int(open3.get("r", 0))))
	last = Snapshot.from_dict(r.snapshot).last_action()
	_expect(failed, last is Dictionary and last.get("coverApplied") == false, "B2 HARD→OPEN no cover")
	_expect(failed, last is Dictionary and last.get("highGroundApplied") == true, "B2 HARD still high ground")
	_expect(failed, last is Dictionary and is_equal_approx(float(last.get("hitChance", -1)), 1.0), "B2 HARD→OPEN 1.0")
	server.equipped_gun = Contract.GUN_FIELDBOLT


func _equip_chrome_case(failed: PackedStringArray) -> void:
	## E1–E5: POST /shop/equip snapshot you.equippedSkinId. Zero combat delta.
	server.clear_all()
	server.reset_wallet(180)
	var session = SessionScript.new()
	session.apply_shop(server.get_shop())
	_expect(failed, session.marks == 180, "E1 seeded marks from snapshot")
	var bought_g: Dictionary = server.buy_shop(Contract.SHOP_STUB_ITEM_ID, "equip-e1-g")
	session.apply_shop(bought_g)
	var bought_b: Dictionary = server.buy_shop(Contract.SHOP_BANDANA_ITEM_ID, "equip-e1-b")
	session.apply_shop(bought_b)
	_expect(failed, session.marks == 30, "E1 180-50-100 from snapshot")
	_expect(failed, session.owns_cosmetic(Contract.SHOP_STUB_ITEM_ID), "E1 owns ghillie")
	_expect(failed, session.owns_cosmetic(Contract.SHOP_BANDANA_ITEM_ID), "E1 owns bandana")

	var bare = Shop.from_any({
		"ok": true,
		"you": {"marks": 30, "owned": [Contract.SHOP_STUB_ITEM_ID], "equippedSkinId": Contract.SHOP_STUB_ITEM_ID},
	})
	_expect(failed, bare.equipped == Contract.SHOP_STUB_ITEM_ID, "E1 parser reads you.equippedSkinId")
	_expect(failed, bare.equipped_present, "E1 equippedSkinId is present")

	var same: Dictionary = server.equip_cosmetic(Contract.SHOP_BANDANA_ITEM_ID)
	session.apply_shop(same)
	_expect(failed, bool(same.get("ok", false)), "E1 equip ok")
	_expect(failed, session.is_equipped(Contract.SHOP_BANDANA_ITEM_ID), "E1 equippedSkinId bandana")
	_expect(failed, session.bandana and not session.ghillie, "E2 hideout bandana wash")
	_expect(failed, session.marks == 30, "E1 equip does not touch marks")
	var replay: Dictionary = server.equip_cosmetic(Contract.SHOP_BANDANA_ITEM_ID)
	session.apply_shop(replay)
	_expect(failed, bool(replay.get("ok", false)), "E1 same-id equip is no-op ok")
	_expect(failed, session.marks == 30, "E1 idempotent equip marks unchanged")
	_expect(failed, session.is_equipped(Contract.SHOP_BANDANA_ITEM_ID), "E1 still bandana")

	var refused: Dictionary = server.equip_cosmetic("skin_does_not_exist")
	_expect(failed, not bool(refused.get("ok", true)), "E1 unknown item rejected")
	session.apply_shop(refused)
	_expect(failed, session.is_equipped(Contract.SHOP_BANDANA_ITEM_ID), "E1 reject keeps snapshot skin")
	_expect(failed, session.marks == 30, "E1 reject marks unchanged")

	server.reset_wallet(24)
	server.owned_cosmetics.clear()
	server.equipped_cosmetic = ""
	var not_owned: Dictionary = server.equip_cosmetic(Contract.SHOP_STUB_ITEM_ID)
	_expect(failed, str(not_owned.get("error", "")) == Contract.SHOP_ERR_NOT_OWNED, "E1 unowned rejected")

	server.reset_wallet(30)
	server.owned_cosmetics = [Contract.SHOP_STUB_ITEM_ID, Contract.SHOP_BANDANA_ITEM_ID]
	server.equipped_cosmetic = Contract.SHOP_BANDANA_ITEM_ID
	session.apply_shop(server.get_shop())
	var swapped: Dictionary = server.equip_cosmetic(Contract.SHOP_STUB_ITEM_ID)
	session.apply_shop(swapped)
	_expect(failed, session.ghillie and not session.bandana, "E4 swap to ghillie")
	_expect(failed, session.marks == 30, "E4 swap marks unchanged")
	var snap: Snapshot = Snapshot.from_dict({
		"you": {
			"seat": "a",
			"marks": 30,
			"exposurePct": 50,
			"equippedSkinId": Contract.SHOP_STUB_ITEM_ID,
		},
	})
	_expect(failed, snap.you_equipped_skin_id() == Contract.SHOP_STUB_ITEM_ID, "E2 snapshot equippedSkinId")
	var unequip: Dictionary = server.equip_cosmetic("")
	session.apply_shop(unequip)
	_expect(failed, session.equipped_cosmetic == "", "E4 unequip clears id")
	_expect(failed, not session.ghillie and not session.bandana, "E4 teal jacket")
	_expect(failed, session.owns_cosmetic(Contract.SHOP_STUB_ITEM_ID), "E4 still owned")
	_expect(failed, session.marks == 30, "E4 unequip marks unchanged")
	var null_bag = Shop.from_any({"ok": true, "you": {"marks": 30, "equippedSkinId": null}})
	_expect(failed, null_bag.equipped_present and null_bag.equipped == "", "E4 null equippedSkinId unequips")
	_expect(failed, Shop.row_action_text(true, false) == "EQUIP", "E6 owned affordance EQUIP")
	_expect(failed, Shop.row_action_text(true, true) == "EQUIPPED", "E6 wearing affordance EQUIPPED")
	session.free()
	_equip_combat_parity_case(failed)


func _equip_combat_parity_case(failed: PackedStringArray) -> void:
	## E5: Attack miss/kill path identical with/without equipped chrome.
	var bare: Dictionary = _equip_combat_run(false)
	var worn: Dictionary = _equip_combat_run(true)
	_expect(failed, bare.get("ok", false) and worn.get("ok", false), "E5 both loops ok")
	for key in ["miss_hit", "miss_kill", "miss_phase", "miss_hot", "miss_exposure", "kill_hit", "kill_kill", "kill_delta", "recon_base", "pvp_win"]:
		_expect(failed, bare.get(key) == worn.get(key), "E5 %s identical" % key)
	_expect(failed, Contract.RECON_BASE == 0.35, "E5 RECON_BASE 0.35")
	_expect(failed, Contract.MARKS_PVP_WIN == 32, "E5 PvP kill ★32")
	_expect(failed, int(bare.get("kill_delta", -1)) == Contract.MARKS_PVP_WIN, "E5 kill marksDelta +32")


func _equip_combat_run(wear_ghillie: bool) -> Dictionary:
	server.clear_all()
	server.reset_wallet(80)
	if wear_ghillie:
		server.buy_shop(Contract.SHOP_STUB_ITEM_ID, "equip-e5-buy")
		server.equip_cosmetic(Contract.SHOP_STUB_ITEM_ID)
	var created: Dictionary = server.create_match()
	var mid := str(created["matchId"])
	var a: Dictionary = server.join(mid, created["joinTokens"]["a"])
	var b: Dictionary = server.join(mid, created["joinTokens"]["b"])
	server.apply_action(mid, a["playerId"], ActionIntent.select_hex(2, 2))
	server.apply_action(mid, b["playerId"], ActionIntent.select_hex(7, 5))
	server.apply_action(mid, a["playerId"], ActionIntent.start())
	var miss: ActionResult = server.apply_action(mid, a["playerId"], ActionIntent.attack(0, 0))
	var miss_snap: Snapshot = Snapshot.from_dict(miss.snapshot)
	var miss_last: Variant = miss_snap.last_action()
	server.apply_action(mid, a["playerId"], ActionIntent.end_turn(50))
	server.apply_action(mid, b["playerId"], ActionIntent.recon(4, 3))
	server.apply_action(mid, b["playerId"], ActionIntent.end_turn(40))
	var kill: ActionResult = server.apply_action(mid, a["playerId"], ActionIntent.attack(7, 5))
	var kill_snap: Snapshot = Snapshot.from_dict(kill.snapshot)
	var kill_last: Variant = kill_snap.last_action()
	return {
		"ok": bool(miss.ok) and bool(kill.ok),
		"miss_hit": miss_last is Dictionary and miss_last.get("hit") == false,
		"miss_kill": miss_last is Dictionary and miss_last.get("kill") == false,
		"miss_phase": str(miss_snap.phase()),
		"miss_hot": miss_snap.enemy_visible_hex() == null,
		"miss_exposure": int(miss_snap.you_exposure()),
		"kill_hit": kill_last is Dictionary and kill_last.get("hit") == true,
		"kill_kill": kill_last is Dictionary and kill_last.get("kill") == true,
		"kill_delta": kill_snap.marks_delta(),
		"recon_base": Contract.RECON_BASE,
		"pvp_win": Contract.MARKS_PVP_WIN,
		"equipped": server.equipped_cosmetic,
	}


func _player_persist_case(failed: PackedStringArray) -> void:
	## Durable POST /players token survives reset_match. Marks bind is snapshot-only.
	var session = SessionScript.new()
	session.bind_player({"playerId": "p_persist", "token": "tok_persist", "marks": 50})
	_expect(failed, session.player_token == "tok_persist", "player token stored")
	_expect(failed, session.durable_player_id == "p_persist", "durable playerId stored")
	_expect(failed, session.marks == 50, "bind_player marks from payload")
	session.join_token = "join_a"
	session.reset_match()
	_expect(failed, session.player_token == "tok_persist", "reset_match keeps player token")
	_expect(failed, session.durable_player_id == "p_persist", "reset_match keeps durable playerId")
	_expect(failed, session.marks == 50, "reset_match keeps display marks")
	_expect(failed, session.join_token == "", "reset_match clears join token")
	session.free()


func _first_hunt_coach_case(failed: PackedStringArray) -> void:
	## C1–C5: chips on first live PvP when unseen, gone after dismiss, ConfigFile persists.
	var Coach := load("res://scenes/match/first_hunt_coach.gd")
	Coach.reset_store_for_test()
	_expect(failed, not Coach.is_seen(), "C5 unseen when flag clear")
	var coach = Coach.new()
	coach.present(false, true)
	_expect(failed, coach.is_showing(), "C1 chips when unseen + live")
	var titles: PackedStringArray = coach.visible_titles()
	_expect(failed, titles.has("ATTACK") and titles.has("RECON"), "C2 Attack + Recon chips")
	_expect(failed, titles.has("DOLL") and titles.has("DECOY"), "C2 Doll + Decoy chips")
	_expect(failed, titles.size() == 4, "C2 four tips")
	_expect(failed, coach.passthrough_ok(), "C3 chips ignore mouse / no modal")
	_expect(failed, Contract.COACH_ATTACK.find("optic") >= 0, "C2 Attack cozy copy")
	_expect(failed, Contract.COACH_RECON.find("Scout") >= 0, "C2 Recon cozy copy")
	_expect(failed, Contract.COACH_DOLL.find("doll") >= 0, "C2 Doll cozy copy")
	_expect(failed, Contract.COACH_DECOY.find("blip") >= 0, "C2 Decoy cozy copy")
	_expect(failed, Contract.RECON_BASE == 0.35 and Contract.MARKS_PVP_WIN == 32, "C4 combat table ★32")
	coach.dismiss()
	_expect(failed, not coach.is_showing(), "C3 gone after Got it")
	_expect(failed, Coach.is_seen(), "C5 seen after dismiss")
	var cfg := ConfigFile.new()
	_expect(failed, cfg.load(Coach.store_path) == OK, "C5 ConfigFile exists")
	_expect(failed, bool(cfg.get_value(Contract.COACH_SECTION, Contract.COACH_SEEN_KEY, false)), "C5 coachSeen true")
	var again = Coach.new()
	again.present(false, true)
	_expect(failed, not again.is_showing(), "C1 never again after dismiss")
	Coach.clear_seen()
	var job = Coach.new()
	job.present(true, true)
	_expect(failed, not job.is_showing(), "C1 SP job skips")
	Coach.clear_seen()
	var drop = Coach.new()
	drop.present(false, false)
	_expect(failed, not drop.is_showing(), "C1 hidden until live after drop")
	coach.free()
	again.free()
	job.free()
	drop.free()
	Coach.restore_store()


func _terrain_coach_case(failed: PackedStringArray) -> void:
	## C1–C6: HIGH GROUND + BRUSH once, dismiss forever, board stays live.
	var Coach := load("res://scenes/match/terrain_coach.gd")
	Coach.reset_store_for_test()
	Coach.suppressed = false
	_expect(failed, not Coach.is_kind_seen(Contract.COACH_TERRAIN_HIGH), "terrain C1 high unseen")
	_expect(failed, not Coach.is_kind_seen(Contract.COACH_TERRAIN_BRUSH), "terrain C1 brush unseen")
	var coach = Coach.new()
	coach.present(false, false)
	_expect(failed, not coach.is_showing(), "terrain C1 quiet until relevant")
	coach.present(true, false)
	_expect(failed, coach.is_showing(), "terrain C1 high chip when the hard hex is lit")
	var titles: PackedStringArray = coach.visible_titles()
	_expect(failed, titles.has(Contract.COACH_TERRAIN_HIGH_TITLE), "terrain C1 HIGH GROUND title")
	_expect(failed, not titles.has(Contract.COACH_TERRAIN_BRUSH_TITLE), "terrain C1 brush stays down")
	_expect(failed, titles.size() == 1, "terrain C1 one chip at a time")
	_expect(failed, coach.passthrough_ok(), "terrain C3 chips ignore mouse")
	_expect(failed, Contract.COACH_TERRAIN_HIGH_COPY.find("shoot better") >= 0, "terrain C5 high copy")
	_expect(failed, Contract.COACH_TERRAIN_BRUSH_COPY.find("softens") >= 0, "terrain C6 brush copy")
	_expect(failed, Contract.COACH_TERRAIN_HIGH_COPY.find("IN COVER") < 0, "terrain C6 high copy has no cover badge")
	_expect(failed, Contract.COACH_TERRAIN_BRUSH_COPY.find("IN COVER") < 0, "terrain C6 brush copy has no cover badge")
	coach.present(false, false)
	_expect(failed, coach.is_showing(), "terrain C1 stays up until dismiss")
	_expect(failed, coach.visible_titles().has(Contract.COACH_TERRAIN_HIGH_TITLE), "terrain C1 latch holds high")
	coach.dismiss()
	_expect(failed, not coach.is_showing(), "terrain C2 gone after GOT IT")
	_expect(failed, Coach.is_kind_seen(Contract.COACH_TERRAIN_HIGH), "terrain C2 high remembered")
	_expect(failed, not Coach.is_kind_seen(Contract.COACH_TERRAIN_BRUSH), "terrain C2 brush still open")
	var again = Coach.new()
	again.present(true, false)
	_expect(failed, not again.is_showing(), "terrain C2 high never again")
	again.present(false, true)
	_expect(failed, again.is_showing(), "terrain C1 brush chip when leafy cover lands")
	_expect(failed, again.visible_titles().has(Contract.COACH_TERRAIN_BRUSH_TITLE), "terrain C1 BRUSH title")
	_expect(failed, not again.visible_titles().has(Contract.COACH_TERRAIN_HIGH_TITLE), "terrain C2 high stays dismissed")
	again.present(false, false)
	_expect(failed, again.is_showing(), "terrain C1 brush latch")
	again.dismiss()
	_expect(failed, not again.is_showing(), "terrain C2 brush gone")
	_expect(failed, Coach.is_kind_seen(Contract.COACH_TERRAIN_BRUSH), "terrain C2 brush remembered")
	var done = Coach.new()
	done.present(true, true)
	_expect(failed, not done.is_showing(), "terrain C2 both stay dismissed")
	var cfg := ConfigFile.new()
	_expect(failed, cfg.load(Coach.store_path) == OK, "terrain C2 ConfigFile exists")
	var raw := str(cfg.get_value(Contract.COACH_SECTION, Contract.COACH_TERRAIN_SEEN_KEY, ""))
	_expect(failed, raw.find(Contract.COACH_TERRAIN_HIGH) >= 0 and raw.find(Contract.COACH_TERRAIN_BRUSH) >= 0, "terrain C2 coachTerrainSeen")
	Coach.clear_seen()
	var held = Coach.new()
	Coach.suppressed = true
	held.present(true, true)
	_expect(failed, not held.is_showing(), "terrain C3 other plates can hide the chips")
	_expect(failed, not Coach.is_kind_seen(Contract.COACH_TERRAIN_HIGH), "terrain C3 hide does not dismiss")
	Coach.suppressed = false
	held.present(true, false)
	_expect(failed, held.is_showing(), "terrain C1 returns on the live board")
	_expect(failed, Contract.RECON_BASE == 0.35, "terrain C4 RECON_BASE")
	_expect(failed, Contract.MARKS_PVP_WIN == 32, "terrain C4 PvP win table")
	_expect(failed, Contract.HIGH_GROUND_HIT == 0.10, "terrain C4 high-ground table")
	var src := FileAccess.get_file_as_string("res://scenes/match/terrain_coach.gd")
	var hud := FileAccess.get_file_as_string("res://scenes/match/match_screen.gd")
	var chrome_src := FileAccess.get_file_as_string("res://scripts/chrome.gd")
	_expect(failed, src.find("MatchAPI") < 0, "terrain C4 no API")
	_expect(failed, src.find("marksDelta") < 0 and src.find("MARKS_") < 0, "terrain C4 no Marks")
	_expect(failed, src.find("IN COVER") < 0, "terrain C6 script has no cover badge")
	_expect(failed, hud.find("\"IN COVER\"") < 0, "terrain C6 HUD has no cover badge")
	_expect(failed, chrome_src.find("\"IN COVER\"") < 0, "terrain C6 chrome has no cover badge")
	_expect(failed, src.find("MOUSE_FILTER_IGNORE") >= 0, "terrain C3 mouse ignore")
	_expect(failed, src.find("chunk_button") >= 0 and src.find("COACH_GOT_IT") >= 0, "terrain C5 same GOT IT chrome")
	_expect(failed, src.find("Chrome.flat") >= 0, "terrain C5 wood plate")
	_expect(failed, src.find("plate_accent := Chrome.HIGH_GOLD") >= 0, "terrain C5 shared gold wood plate")
	_expect(failed, src.find("Chrome.BRUSH") < 0, "terrain C5 brush plate is not legend green")
	_expect(failed, hud.find("_sync_terrain_coach") >= 0, "terrain C1 wired to the board")
	_expect(failed, hud.find("last_cover_applied") >= 0, "terrain C1 reads coverApplied")
	_expect(failed, hud.find("MOUSE_FILTER_IGNORE") >= 0, "terrain C3 HUD does not lock input")
	coach.free()
	again.free()
	done.free()
	held.free()
	Coach.restore_store()


func _gear_strip_case(failed: PackedStringArray) -> void:
	## S1–S6: hideout gear strip. Mute persists and silences juice. Coach reset confirms first.
	## Terrain seen is the landed comma list (high,brush), not a bool.
	var Coach := load("res://scenes/match/first_hunt_coach.gd")
	var Terrain := load("res://scenes/match/terrain_coach.gd")
	var store := "user://glassline_coach_gear_test.cfg"
	Coach.reset_store_for_test(store)
	Terrain.store_path = store
	Coach.mark_seen()
	Terrain.mark_kind(Contract.COACH_TERRAIN_HIGH)
	Terrain.mark_kind(Contract.COACH_TERRAIN_BRUSH)
	_expect(failed, Coach.is_seen(), "S3 coachSeen starts dismissed")
	_expect(failed, Terrain.is_kind_seen(Contract.COACH_TERRAIN_HIGH), "S3 high starts dismissed")
	_expect(failed, Terrain.is_kind_seen(Contract.COACH_TERRAIN_BRUSH), "S3 brush starts dismissed")

	var juice = JuiceScript.new()
	juice.store_path = "user://glassline_settings_gear_test.json"
	juice.set_muted(false)
	var strip = GearStrip.new()
	strip.audio = juice
	strip._build()
	_expect(failed, strip.uses_wood(), "S6 wood plate")
	_expect(failed, strip.mute_text() == Contract.GEAR_MUTE_LIVE, "S1 live label")
	_expect(failed, strip.mute_icon_kind() == "speaker", "S1 speaker icon")
	_expect(failed, strip.mouse_filter == Control.MOUSE_FILTER_IGNORE, "S2 strip does not cover the room")
	_expect(failed, not strip.is_confirming(), "S4 confirm starts closed")

	strip.press_mute()
	_expect(failed, juice.muted, "S1 mute toggles juice")
	_expect(failed, strip.mute_text() == Contract.GEAR_MUTE_MUTED, "S1 muted label")
	_expect(failed, strip.mute_icon_kind() == "speaker_off", "S1 muted speaker")
	juice.notice_last_action({
		"type": Contract.ACT_ATTACK,
		"hit": true,
		"highGroundApplied": true,
		"coverApplied": true,
	})
	_expect(failed, juice.last_played.is_empty(), "S2 muted plays nothing")
	_expect(failed, juice.last_cues.has(Contract.CUE_HIT), "S2 silent hunt still names the cue")
	_expect(failed, juice.last_cues.has(Contract.CUE_HIGH) and juice.last_cues.has(Contract.CUE_BRUSH), "S2 mute kills every stinger")
	var toast := Chrome.describe_attack_result({
		"type": Contract.ACT_ATTACK,
		"hit": true,
		"hitChance": 0.9,
	})
	_expect(failed, toast.find("Shot hit") >= 0, "S2 result toast still readable")
	var again = JuiceScript.new()
	again.store_path = juice.store_path
	again._load()
	_expect(failed, again.muted, "S1 mute survives restart")
	var raw := FileAccess.get_file_as_string(juice.store_path)
	_expect(failed, raw.find("http") < 0 and raw.find("token") < 0, "S5 settings file is local mute only")

	strip.press_confirm()
	_expect(failed, Coach.is_seen(), "S4 confirm without ask keeps coachSeen")
	_expect(failed, Terrain.is_kind_seen(Contract.COACH_TERRAIN_HIGH), "S4 confirm without ask keeps high")
	_expect(failed, Terrain.is_kind_seen(Contract.COACH_TERRAIN_BRUSH), "S4 confirm without ask keeps brush")
	strip.press_reset()
	_expect(failed, strip.is_confirming(), "S4 confirm opens")
	_expect(failed, strip.confirm_copy().to_lower().find("tips will show again") >= 0, "S4 tips will show again")
	_expect(failed, Coach.is_seen(), "S4 opening confirm leaves coachSeen")
	_expect(failed, Terrain.is_kind_seen(Contract.COACH_TERRAIN_HIGH) and Terrain.is_kind_seen(Contract.COACH_TERRAIN_BRUSH), "S4 opening confirm leaves terrain dismissed")
	strip.press_cancel()
	_expect(failed, not strip.is_confirming(), "S4 cancel closes")
	_expect(failed, Coach.is_seen(), "S4 cancel leaves coachSeen")
	_expect(failed, Terrain.is_kind_seen(Contract.COACH_TERRAIN_HIGH) and Terrain.is_kind_seen(Contract.COACH_TERRAIN_BRUSH), "S4 cancel leaves terrain dismissed")
	strip.press_reset()
	strip.press_confirm()
	_expect(failed, not strip.is_confirming(), "S3 confirm closes after clear")
	_expect(failed, not Coach.is_seen(), "S3 coachSeen cleared")
	_expect(failed, not Terrain.is_kind_seen(Contract.COACH_TERRAIN_HIGH), "S3 high cleared")
	_expect(failed, not Terrain.is_kind_seen(Contract.COACH_TERRAIN_BRUSH), "S3 brush cleared")
	var cfg := ConfigFile.new()
	_expect(failed, cfg.load(Coach.store_path) == OK, "S3 coach file saved")
	_expect(failed, cfg.get_value(Contract.COACH_SECTION, Contract.COACH_SEEN_KEY, true) == false, "S3 coachSeen false")
	_expect(failed, str(cfg.get_value(Contract.COACH_SECTION, Contract.COACH_TERRAIN_SEEN_KEY, "x")) == "", "S3 terrain list cleared")

	var copy := strip.plate_copy().to_lower()
	_expect(failed, copy.find("live") >= 0 or strip.mute_text() == Contract.GEAR_MUTE_MUTED, "S1 readable mute state")
	strip.press_mute()
	_expect(failed, not juice.muted, "S1 unmute restores juice")
	_expect(failed, strip.mute_text() == Contract.GEAR_MUTE_LIVE, "S1 live again")
	var gear_src := FileAccess.get_file_as_string("res://scenes/lobby/gear_strip.gd")
	var coach_src := FileAccess.get_file_as_string("res://scenes/match/first_hunt_coach.gd")
	_expect(failed, gear_src.find("make_wood_texture") >= 0, "S6 wood grain")
	_expect(failed, gear_src.find("chunk_button") >= 0, "S6 chunky chips")
	_expect(failed, gear_src.find("AudioJuice") >= 0, "S1 same mute as juice autoload")
	_expect(failed, gear_src.find("reset_tips") >= 0, "S3 strip calls reset_tips")
	_expect(failed, gear_src.find("MatchAPI") < 0 and gear_src.find("HTTPRequest") < 0, "S5 no API client")
	_expect(failed, gear_src.to_lower().find("marks") < 0, "S5 no Marks")
	_expect(failed, gear_src.find("GRAPHICS") < 0 and gear_src.to_lower().find("keybind") < 0, "S6 no graphics or keybinds")
	_expect(failed, gear_src.find("ACCOUNT") < 0 and gear_src.find("OPTIONS") < 0, "S6 not an Options app")
	_expect(failed, coach_src.find("func reset_tips") >= 0, "S3 reset_tips exists")
	_expect(failed, coach_src.find("MatchAPI") < 0, "S5 coach reset has no API")
	var hideout_src := FileAccess.get_file_as_string("res://scenes/lobby/hideout_lobby.gd")
	_expect(failed, hideout_src.find("_build_gear_strip") >= 0, "S1 hideout builds the strip")
	_expect(failed, hideout_src.find("tips_reset.connect") >= 0, "S3 hideout hears the reset")
	var plate := strip.plate_copy().to_lower()
	_expect(failed, plate.find("ranked") < 0 and plate.find("ladder") < 0, "S6 no ladder chrome")
	_expect(failed, plate.find("account") < 0, "S6 no account chrome")
	juice.free()
	again.free()
	strip.free()
	Coach.restore_store()
	Terrain.restore_store()


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
	_expect(failed, snap.you_marks() == 4 + Contract.MARKS_STANDOFF, "standoff +10 wallet")
	_expect(failed, snap.marks_delta() == Contract.MARKS_STANDOFF, "standoff marksDelta +10")
	_expect(failed, snap.end_reason() == Contract.END_STANDOFF, "standoff reason")
	_expect(failed, server.account_marks == 4 + Contract.MARKS_STANDOFF, "standoff uses GD table")


func _audio_juice_case(failed: PackedStringArray) -> void:
	## A1–A4: toy-spy stingers from attack flags. Mute is silent. No combat delta.
	var juice = JuiceScript.new()
	juice.muted = true
	var miss := juice.cues_for({"type": Contract.ACT_ATTACK, "hit": false})
	_expect(failed, miss.size() == 1 and miss[0] == Contract.CUE_MISS, "A1 miss → glass_click")
	var hit := juice.cues_for({"type": Contract.ACT_ATTACK, "hit": true})
	_expect(failed, hit.size() == 1 and hit[0] == Contract.CUE_HIT, "A1 hit → glass_ping")
	var stacked := juice.cues_for({
		"type": Contract.ACT_ATTACK,
		"hit": true,
		"highGroundApplied": true,
		"coverApplied": true,
	})
	_expect(failed, stacked.has(Contract.CUE_HIT), "A1 stacked includes hit")
	_expect(failed, stacked.has(Contract.CUE_HIGH), "A1 HG flag → high_chime")
	_expect(failed, stacked.has(Contract.CUE_BRUSH), "A1 brush flag → brush_hush")
	var doll := juice.cues_for({"type": Contract.ACT_ATTACK, "hit": false, "decoyCleared": true})
	_expect(failed, doll.has(Contract.CUE_MISS) and not doll.has(Contract.CUE_HIT), "A1 doll miss click")
	var recon := juice.cues_for({"type": Contract.ACT_RECON, "spotted": true})
	_expect(failed, recon.is_empty(), "A1 recon is not an attack stinger")
	var skipped := juice.cues_for({
		"type": Contract.ACT_ATTACK,
		"hit": true,
		"highGroundApplied": false,
		"coverApplied": false,
	})
	_expect(failed, not skipped.has(Contract.CUE_HIGH), "A1 skipped HG is not a chime")
	_expect(failed, not skipped.has(Contract.CUE_BRUSH), "A1 skipped cover is not a hush")
	juice.notice_last_action({"type": Contract.ACT_ATTACK, "hit": true, "highGroundApplied": true})
	_expect(failed, juice.last_played.is_empty(), "A3 muted plays nothing")
	_expect(failed, juice.last_cues.has(Contract.CUE_HIT), "A3 mute still names the cue")
	juice.free()

	var juice_src := FileAccess.get_file_as_string("res://autoload/audio_juice.gd")
	var chrome_src := FileAccess.get_file_as_string("res://scripts/chrome.gd")
	var hud_src := FileAccess.get_file_as_string("res://scenes/match/match_screen.gd")
	_expect(failed, juice_src.find("gunshot") < 0 and juice_src.find("killstreak") < 0, "A2 no mil-sim gunshot/killstreak")
	_expect(failed, chrome_src.find("gunshot") < 0 and hud_src.find("killstreak") < 0, "A2 chrome/hud not mil-sim")
	_expect(failed, juice_src.find("marks") < 0 and juice_src.find("MatchAPI") < 0, "A4 juice has no Marks / API")
	_expect(failed, juice_src.find("hitChance") >= 0 or juice_src.find("coverApplied") >= 0, "A4 juice reads result flags")
	_expect(failed, Chrome.mute_button_text(true) == "MUTE", "A3 mute label")
	_expect(failed, Chrome.mute_button_text(false) == "SOUND", "A3 sound label")
	var recon_line := Chrome.describe_last_action({"type": Contract.ACT_RECON, "spotted": true})
	var uav_line := Chrome.describe_last_action({"type": Contract.ACT_UAV, "revealed": true})
	var decoy_line := Chrome.describe_last_action({"type": Contract.ACT_DECOY, "hex": {"q": 2, "r": 3}})
	_expect(failed, recon_line.find("(server)") < 0, "A5 recon toast has no (server)")
	_expect(failed, uav_line.find("(server)") < 0, "A5 uav toast has no (server)")
	_expect(failed, decoy_line.find("(server)") < 0, "A5 decoy toast has no (server)")
	_expect(failed, decoy_line.find("toy doll") >= 0, "A5 decoy keeps toy-doll copy")


func _join_spine_case(failed: PackedStringArray) -> void:
	## LIVE create is one joinToken + seat a. Seat B is never on the create bag.
	var live_shape := {"matchId": "m_live", "joinToken": "tok_a_only", "seat": "a"}
	_expect(failed, not live_shape.has("joinTokens"), "spine create has no joinTokens")
	_expect(failed, Contract.create_join_token(live_shape) == "tok_a_only", "spine A uses joinToken")
	_expect(failed, Contract.create_seat(live_shape) == "a", "spine seat a")
	_expect(failed, Contract.create_dummy_token(live_shape) == "", "spine create has no seat B token")
	var fallback := Contract.create_join_token({"joinTokens": {"a": "tok_legacy_a", "b": "tok_legacy_b"}})
	_expect(failed, fallback == "tok_legacy_a", "mock fallback still reads joinTokens.a")
	_expect(failed, Contract.create_dummy_token({"joinTokens": {"a": "tok_legacy_a", "b": "tok_legacy_b"}}) == "tok_legacy_b", "mock dummy still reads joinTokens.b")
	server.clear_all()
	var created: Dictionary = server.create_match()
	_expect(failed, str(created.get("joinToken", "")) != "", "mock also stamps caller joinToken")
	_expect(failed, str(created.get("seat", "")) == "a", "mock seat a")
	_expect(failed, created.has("joinTokens"), "mock keeps dummy joinTokens for editor")
	_expect(failed, Contract.create_join_token(created) == str(created.get("joinToken", "")), "caller helper prefers joinToken")
	var hideout_src := FileAccess.get_file_as_string("res://scenes/lobby/hideout_lobby.gd")
	var live_src := FileAccess.get_file_as_string("res://autoload/live_match_client.gd")
	_expect(failed, hideout_src.find("sit_created_pvp") >= 0, "hideout sits via spine helper")
	_expect(failed, hideout_src.find("tokens.is_empty()") < 0, "hideout PLAY does not require joinTokens")
	_expect(failed, live_src.find("body.erase(\"joinTokens\")") >= 0, "LIVE create strips dual tokens")
	_expect(failed, live_src.find("func claim_open_seat") >= 0, "LIVE claim empty seat B")


func _practice_case(failed: PackedStringArray) -> void:
	## P1–P6: practice create is seat A only, bot is server-side, Marks stay Δ0, rematch stays practice.
	server.clear_all()
	server.reset_wallet(24)
	var created: Dictionary = server.create_match({"mode": Contract.MODE_PRACTICE})
	_expect(failed, Contract.practice_create_ok(created), "practice create ok")
	_expect(failed, str(created.get("mode", "")) == Contract.MODE_PRACTICE, "practice create mode")
	_expect(failed, str(created.get("seat", "")) == Contract.SEAT_A, "practice seat a")
	_expect(failed, not created.has("joinTokens"), "practice create has no seat B token")
	_expect(failed, Contract.create_dummy_token(created) == "", "practice dummy helper empty")
	var mid := str(created.get("matchId", ""))
	var join_a: Dictionary = server.join(mid, Contract.create_join_token(created))
	_expect(failed, str(join_a.get("seat", "")) == Contract.SEAT_A, "practice join seat a")
	var pid := str(join_a.get("playerId", ""))
	var snap: Snapshot = Snapshot.from_dict(join_a.get("snapshot", {}))
	_expect(failed, snap.status() == Contract.STATUS_READY, "practice ready when you sit")
	_expect(failed, snap.is_practice(), "practice snapshot mode")
	_expect(failed, snap.enemy_is_bot(), "practice enemy.isBot")
	_expect(failed, snap.enemy_placed(), "practice bot already placed")
	_expect(failed, not snap.is_job(), "practice is not a job")
	var stolen: Dictionary = server.join(mid, "tok_%s_b" % mid)
	_expect(failed, str(stolen.get("error", "")) == "bot_seat", "practice bot seat rejects join")
	var wallet_before := int(server.account_marks)
	var r: ActionResult = server.apply_action(mid, pid, ActionIntent.select_hex(2, 2))
	_expect(failed, r.ok, "practice drop")
	r = server.apply_action(mid, pid, ActionIntent.start())
	_expect(failed, r.ok, "practice start")
	snap = Snapshot.from_dict(r.snapshot)
	_expect(failed, snap.status() == Contract.STATUS_ACTIVE, "practice active")
	_expect(failed, str(snap.whose_turn()) == Contract.SEAT_A, "practice you start")
	r = server.apply_action(mid, pid, ActionIntent.recon(4, 4))
	_expect(failed, r.ok, "practice recon")
	r = server.apply_action(mid, pid, ActionIntent.end_turn(40))
	_expect(failed, r.ok, "practice end turn")
	snap = Snapshot.from_dict(r.snapshot)
	_expect(failed, str(snap.whose_turn()) == Contract.SEAT_A, "practice bot turn is server-side")
	_expect(failed, snap.turn_index() >= 2, "practice bot consumed a turn")
	_expect(failed, snap.is_practice() and snap.enemy_is_bot(), "practice chrome flags survive the turn")
	var bot_hex: Dictionary = {}
	var match_state: Dictionary = server._matches[mid]
	var bot_seat: Dictionary = match_state["seats"][Contract.SEAT_B]
	if bot_seat.get("hex") is Dictionary:
		bot_hex = bot_seat["hex"]
	r = server.apply_action(mid, pid, ActionIntent.attack(int(bot_hex.get("q", -1)), int(bot_hex.get("r", -1))))
	_expect(failed, r.ok, "practice occupy still resolves")
	snap = Snapshot.from_dict(r.snapshot)
	var last: Variant = snap.last_action()
	_expect(failed, last is Dictionary and last.get("hit") == true, "practice kill hit=true")
	_expect(failed, snap.status() == Contract.STATUS_ENDED, "practice ended")
	_expect(failed, str(snap.winner()) == Contract.SEAT_A, "practice winner")
	_expect(failed, snap.marks_delta() == Contract.MARKS_PRACTICE, "practice marksDelta 0")
	_expect(failed, int(server.account_marks) == wallet_before, "practice wallet unchanged")
	_expect(failed, snap.you_marks() == wallet_before, "practice you.marks unchanged")
	_expect(failed, snap.end_reason() == "no marks", "practice hides earn reason")
	var parts: Dictionary = MarksPayout.overlay_parts(snap.raw, Contract.SEAT_A, false, true)
	_expect(failed, int(parts.get("delta", -1)) == 0, "practice overlay Δ0")
	_expect(failed, str(parts.get("headline", "")) == Contract.PRACTICE_CLEAR, "practice clear headline")
	_expect(failed, str(parts.get("marks", "")).begins_with("0"), "practice marks chip is 0")
	_expect(failed, str(parts.get("marks", "")).find("+") < 0, "practice chip has no plus")
	_expect(failed, str(parts.get("marks", "")).find("Δ") < 0, "practice chip has no delta glyph")
	_expect(failed, str(parts.get("reason", "")) == "no marks", "practice no earn chrome")
	var poisoned := snap.raw.duplicate(true)
	poisoned["marksDelta"] = Contract.MARKS_PVP_WIN
	if poisoned.get("payout") is Dictionary:
		poisoned["payout"]["marksDelta"] = Contract.MARKS_PVP_WIN
	_expect(failed, MarksPayout.table_delta(poisoned, Contract.SEAT_A) == 0, "practice table ignores +32")
	_expect(failed, snap.rematch_offered(), "practice rematch offered")
	var again: Dictionary = server.rematch(mid, pid, true)
	_expect(failed, str(again.get("status", "")) == Contract.REMATCH_READY, "practice rematch ready on one accept")
	_expect(failed, str(again.get("mode", "")) == Contract.MODE_PRACTICE, "practice rematch stays practice")
	_expect(failed, not again.has("joinTokens"), "practice rematch has no seat B token")
	var neu: Snapshot = Snapshot.from_dict(again.get("snapshot", {}))
	_expect(failed, neu.is_practice() and neu.enemy_is_bot(), "practice rematch snapshot is bot hunt")
	_expect(failed, int(server.account_marks) == wallet_before, "practice rematch did not grant")
	var quiet: Dictionary = server.create_match({"mode": Contract.MODE_PRACTICE})
	var qid := str(quiet.get("matchId", ""))
	var qjoin: Dictionary = server.join(qid, Contract.create_join_token(quiet))
	var qpid := str(qjoin.get("playerId", ""))
	server.apply_action(qid, qpid, ActionIntent.select_hex(1, 1))
	server.apply_action(qid, qpid, ActionIntent.start())
	var left: Dictionary = server.abandon(qid, qpid)
	var left_snap: Snapshot = Snapshot.from_dict(left.get("snapshot", {}))
	_expect(failed, left_snap.is_forfeit(), "practice abandon is forfeit")
	_expect(failed, left_snap.marks_delta() == 0, "practice forfeit Δ0")
	_expect(failed, int(server.account_marks) == wallet_before, "practice forfeit wallet unchanged")
	var stand: Dictionary = server.create_match({"mode": Contract.MODE_PRACTICE})
	var sid := str(stand.get("matchId", ""))
	var sjoin: Dictionary = server.join(sid, Contract.create_join_token(stand))
	server.force_standoff(sid, str(sjoin.get("playerId", "")))
	var draw: Snapshot = Snapshot.from_dict(server.get_snapshot(sid, str(sjoin.get("playerId", ""))))
	_expect(failed, str(draw.winner()) == Contract.WIN_DRAW, "practice standoff")
	_expect(failed, draw.marks_delta() == 0, "practice standoff Δ0")
	_expect(failed, int(server.account_marks) == wallet_before, "practice standoff wallet unchanged")
	var pvp: Dictionary = server.create_match()
	_expect(failed, pvp.has("joinTokens"), "pvp create still has dummy tokens")
	var hideout_src := FileAccess.get_file_as_string("res://scenes/lobby/hideout_lobby.gd")
	var hud_src := FileAccess.get_file_as_string("res://scenes/match/match_screen.gd")
	_expect(failed, hideout_src.find("MODE_PRACTICE") >= 0, "hideout posts practice mode")
	_expect(failed, hideout_src.find("sit_created_pvp(created, false)") >= 0, "practice sits seat A only")
	_expect(failed, hideout_src.find("practice_snapshot_ok") >= 0, "hideout confirms snapshot before the hunt")
	_expect(failed, hideout_src.find("PRACTICE_NO_MARKS") >= 0, "hideout shows no-marks copy")
	_expect(failed, hud_src.find("PRACTICE_CHIP") >= 0, "match HUD practice chip")
	_expect(failed, hud_src.find("PRACTICE_SETTLED_COPY") >= 0, "practice end says Δ0")
	var start_line := Chrome.describe_last_action({"type": Contract.ACT_START})
	_expect(failed, start_line == "", "P2 start debug line scrubbed")
	_expect(failed, start_line.find("lastAction") < 0, "P2 start toast is not a debug line")
	var chrome_src := FileAccess.get_file_as_string("res://scripts/chrome.gd")
	_expect(failed, chrome_src.find("lastAction start") < 0, "P2 chrome has no lastAction start copy")
	_expect(failed, hideout_src.find("\"practice\"") >= 0, "P2 practice dock icon")
	var live_body := {"matchId": "m_live", "joinToken": "tok_live", "seat": "a"}
	_expect(failed, Contract.practice_envelope_ok(live_body), "LIVE envelope is seat A only")
	_expect(failed, not Contract.practice_create_ok(live_body), "omitted mode is not sit-ok")
	var echoed := {"matchId": "m_live", "joinToken": "tok_live", "seat": "a", "mode": "practice"}
	_expect(failed, Contract.practice_create_ok(echoed), "LIVE practice echoes mode")
	_expect(failed, not Contract.practice_create_ok({"matchId": "m_live", "joinToken": "tok_live", "seat": "a", "mode": "pvp"}), "echoed pvp is not practice")
	var live_snap := {"kind": "practice", "mode": "practice", "enemy": {"isBot": true}}
	_expect(failed, Contract.practice_snapshot_ok(live_snap), "LIVE snapshot practice + bot")
	_expect(failed, not Contract.practice_snapshot_ok({"kind": "pvp", "mode": "pvp", "enemy": {"isBot": false}}), "pvp snapshot refused")
	_expect(failed, not Contract.practice_snapshot_ok({"kind": "practice", "mode": "practice", "enemy": {}}), "missing isBot refused")
	_expect(failed, not Contract.practice_snapshot_ok({"kind": "practice", "mode": "pvp", "enemy": {"isBot": true}}), "kind/mode clash refused")
	var kind_only: Snapshot = Snapshot.from_dict({"kind": "practice", "you": {"seat": "a"}, "enemy": {"isBot": true}})
	_expect(failed, kind_only.is_practice(), "kind practice does not fall through to pvp")
	var clash: Snapshot = Snapshot.from_dict({"kind": "practice", "mode": "pvp", "enemy": {"isBot": true}})
	_expect(failed, not clash.is_practice(), "kind/mode clash is not practice")


func _journal_case(failed: PackedStringArray) -> void:
	## J1–J6: ledger rows only, practice Δ0, rematch gated, practice-again is a practice create.
	server.clear_all()
	server.reset_wallet(24)
	server.test_now_ms = -1
	var empty: Dictionary = server.get_journal("")
	_expect(failed, Journal.is_empty(empty), "J5 empty ledger")
	_expect(failed, (empty.get("entries", []) as Array).size() == 0, "J5 no invented rows")
	var invented: Dictionary = Journal.payload({"marksDelta": 25, "result": "win"})
	_expect(failed, Journal.is_empty(invented), "J1 payload without entries invents nothing")

	var practice: Dictionary = _journal_end(Contract.MODE_PRACTICE, Contract.SEAT_A, Contract.END_KILL)
	var pmid := str(practice.get("matchId", ""))
	var pbag: Dictionary = server.get_journal("")
	_expect(failed, (pbag.get("entries", []) as Array).size() == 1, "practice journal one row")
	var prow: Dictionary = pbag["entries"][0]
	_expect(failed, str(prow.get("matchId", "")) == pmid, "practice row matchId")
	_expect(failed, str(prow.get("mode", "")) == Contract.MODE_PRACTICE, "practice row mode")
	_expect(failed, int(prow.get("marksDelta", -1)) == 0, "J2 practice marks Δ0")
	_expect(failed, str(prow.get("result", "")) == "win", "practice win result")
	var prival: Dictionary = prow.get("rival", {})
	_expect(failed, bool(prival.get("isBot", false)), "practice rival is bot")
	_expect(failed, bool(prow.get("rematchAvailable", false)), "fresh practice rematch available")
	_expect(failed, Journal.action_for(prow) == "practice", "J4 practice again is practice create")
	_expect(failed, Journal.cta_text(prow) == Contract.JOURNAL_PRACTICE_AGAIN, "J4 practice CTA")
	_expect(failed, Journal.marks_text(Journal.normalize({
		"matchId": "m_poison",
		"mode": Contract.MODE_PRACTICE,
		"marksDelta": Contract.MARKS_PVP_WIN,
		"result": "win",
		"rematchAvailable": true,
	})) == "0", "J2 poisoned practice still 0")
	_expect(failed, Contract.format_marks_delta(0) == "0", "P2 delta chip 0")
	_expect(failed, Contract.format_marks_delta(32) == "+32", "P2 delta chip +N")
	_expect(failed, Contract.format_marks_delta(-4) == "−4", "P2 delta chip −N")
	_expect(failed, Contract.format_marks_delta(-4) != "-4", "P2 minus is not a hyphen")
	_expect(failed, Contract.format_marks_delta(32) != "0+32" and Contract.format_marks_delta(32) != "Δ+32", "P2 no glued delta")
	_expect(failed, Journal.marks_text(Journal.normalize({
		"matchId": "m_neg",
		"mode": Contract.MODE_PVP,
		"marksDelta": -4,
	})) == "−4", "unclassified journal delta stays −N")
	_expect(failed, Journal.marks_text(Journal.normalize({
		"matchId": "m_loss",
		"mode": Contract.MODE_PVP,
		"marksDelta": 3,
		"result": "loss",
	})) == "+4", "journal loss chip is table +4")
	var old_foil := Journal.normalize({
		"matchId": "m_old_foil",
		"mode": Contract.MODE_PVP,
		"result": "win",
		"marksDelta": 12,
		"endReason": "forfeit",
	})
	_expect(failed, int(old_foil.get("marksDelta", 0)) == 12, "journal keeps ledger forfeit Δ")
	_expect(failed, Journal.marks_text(old_foil) == "+15", "journal forfeit chip +15 not ledger +12")
	_expect(failed, Journal.marks_text(Journal.normalize({
		"matchId": "m_old_kill",
		"mode": Contract.MODE_PVP,
		"result": "win",
		"marksDelta": 25,
	})) == "+32", "journal old kill paints +32")
	_expect(failed, Journal.marks_text(Journal.normalize({
		"matchId": "m_old_stand",
		"mode": Contract.MODE_PVP,
		"result": "draw",
		"marksDelta": 8,
	})) == "+10", "journal old standoff paints +10")
	_expect(failed, Journal.marks_text(Journal.normalize({
		"matchId": "m_old_t1",
		"mode": Contract.MODE_SP_JOB,
		"result": "win",
		"marksDelta": 10,
	})) == "+12", "journal old T1 paints +12")
	_expect(failed, Journal.marks_text(Journal.normalize({
		"matchId": "m_old_t2",
		"mode": Contract.MODE_SP_JOB,
		"result": "win",
		"marksDelta": 15,
	})) == "+18", "journal old T2 paints +18")
	_expect(failed, Journal.marks_text(Journal.normalize({
		"matchId": "m_old_t3",
		"mode": Contract.MODE_SP_JOB,
		"result": "win",
		"marksDelta": 20,
	})) == "+24", "journal old T3 paints +24")
	_expect(failed, Journal.marks_text(Journal.normalize({
		"matchId": "m_old_fail",
		"mode": Contract.MODE_SP_JOB,
		"result": "loss",
		"marksDelta": 0,
	})) == "+2", "journal old T1 fail paints +2")
	_expect(failed, Journal.marks_text(Journal.normalize({
		"matchId": "m_fail3",
		"mode": Contract.MODE_SP_JOB,
		"result": "loss",
		"marksDelta": 0,
		"jobTier": 3,
	})) == "+3", "journal T3 fail paints +3")

	server.clear_all()
	server.reset_wallet(0)
	var created: Dictionary = server.create_match()
	var mid := str(created.get("matchId", ""))
	var tokens: Dictionary = created.get("joinTokens", {})
	var join_a: Dictionary = server.join(mid, str(tokens.get("a", "")))
	var join_b: Dictionary = server.join(mid, str(tokens.get("b", "")))
	server.force_end(mid, Contract.SEAT_A, Contract.END_KILL)
	var pid_a := str(join_a.get("playerId", ""))
	var pid_b := str(join_b.get("playerId", ""))
	var win_row: Dictionary = server.get_journal(pid_a)["entries"][0]
	var loss_row: Dictionary = server.get_journal(pid_b)["entries"][0]
	_expect(failed, int(win_row.get("marksDelta", 0)) == Contract.MARKS_PVP_WIN, "pvp journal win Δ")
	_expect(failed, str(win_row.get("result", "")) == "win", "pvp journal win")
	_expect(failed, int(loss_row.get("marksDelta", -1)) == Contract.MARKS_PVP_LOSS, "pvp journal loss Δ")
	_expect(failed, str(loss_row.get("result", "")) == "loss", "pvp journal loss")
	_expect(failed, Journal.mode_tag(win_row) == Contract.JOURNAL_TAG_QUICK, "pvp tag QUICK")
	_expect(failed, bool(win_row.get("rematchAvailable", false)), "J3 fresh pvp rematch available")
	_expect(failed, Journal.action_for(win_row) == "rematch", "J3 rematch action")

	server.test_now_ms = 1000 + Contract.REMATCH_TIMEOUT_MS + 20
	var expired: Dictionary = server.get_journal(pid_a)["entries"][0]
	_expect(failed, not bool(expired.get("rematchAvailable", true)), "J3 expired rematch unavailable")
	_expect(failed, Journal.action_for(expired) == "", "J3 muted rematch has no action")
	server.test_now_ms = -1

	var job: Dictionary = server.create_job(2)
	server.force_end(str(job.get("matchId", "")), Contract.SEAT_A, Contract.END_KILL)
	var job_row: Dictionary = server.get_journal(str(job.get("playerId", "")))["entries"][0]
	_expect(failed, str(job_row.get("mode", "")) == Contract.MODE_SP_JOB, "job row mode")
	_expect(failed, not bool(job_row.get("rematchAvailable", true)), "job rematch unavailable")
	_expect(failed, Journal.action_for(job_row) == "", "job is not a rematch")
	_expect(failed, Journal.mode_tag(job_row) == Contract.JOURNAL_TAG_JOB, "job tag is not a quick hunt")
	_expect(failed, not job_row.has("mmr") and not job_row.has("elo"), "journal row has no rating fields")

	server.clear_all()
	server.reset_wallet(0)
	var foil_end: Dictionary = _journal_end(Contract.MODE_PVP, Contract.SEAT_A, Contract.END_FORFEIT)
	var foil_row: Dictionary = server.get_journal("")["entries"][0]
	_expect(failed, str(foil_row.get("matchId", "")) == str(foil_end.get("matchId", "")), "forfeit journal row")
	_expect(failed, int(foil_row.get("marksDelta", 0)) == Contract.MARKS_FORFEIT_WIN, "forfeit journal ledger +15")
	_expect(failed, Journal.marks_text(foil_row) == "+15", "forfeit journal chip +15")
	_expect(failed, str(foil_row.get("result", "")) == "win", "forfeit win result stays WIN")
	var leave_end: Dictionary = _journal_end(Contract.MODE_PVP, Contract.SEAT_B, Contract.END_FORFEIT)
	var leave_row: Dictionary = server.get_journal("")["entries"][0]
	_expect(failed, str(leave_row.get("matchId", "")) == str(leave_end.get("matchId", "")), "forfeit leaver journal row")
	_expect(failed, int(leave_row.get("marksDelta", -1)) == 0, "forfeit leaver ledger 0")
	_expect(failed, Journal.marks_text(leave_row) == "0", "forfeit leaver chip 0")
	_journal_end(Contract.MODE_PVP, Contract.WIN_DRAW, Contract.END_STANDOFF)
	var stand_row: Dictionary = server.get_journal("")["entries"][0]
	_expect(failed, Journal.marks_text(stand_row) == "+10", "standoff journal chip +10")
	for tier in [1, 2, 3]:
		var job_win: Dictionary = server.create_job(tier)
		server.force_end(str(job_win.get("matchId", "")), Contract.SEAT_A, Contract.END_KILL)
		var job_chip: Dictionary = server.get_journal(str(job_win.get("playerId", "")))["entries"][0]
		var expect_win := Contract.job_tier_delta(tier)
		_expect(failed, Journal.marks_text(job_chip) == Contract.format_marks_delta(expect_win), "journal T%d win chip" % tier)
		_expect(failed, int(job_chip.get("marksDelta", -1)) == expect_win, "journal T%d win ledger untouched" % tier)
	server.clear_all()
	server.reset_wallet(0)
	var ids: PackedStringArray = []
	for _i in 11:
		var ended: Dictionary = _journal_end(Contract.MODE_PVP, Contract.SEAT_A, Contract.END_KILL)
		ids.append(str(ended.get("matchId", "")))
	var capped: Array = server.get_journal("")["entries"]
	_expect(failed, capped.size() == Contract.JOURNAL_LIMIT, "J1 ledger caps at 10")
	_expect(failed, str(capped[0].get("matchId", "")) == ids[10], "J1 newest row first")
	var seen := {}
	for row in capped:
		seen[str(row.get("matchId", ""))] = true
	_expect(failed, not seen.has(ids[0]), "J1 oldest dropped")

	var dozen: Array = []
	for i in 12:
		dozen.append({
			"matchId": "m_%d" % i,
			"mode": Contract.MODE_PVP,
			"result": "win",
			"marksDelta": 1,
			"rematchAvailable": true,
			"rival": {"displayName": "RIVAL", "isBot": false},
		})
	var trimmed: Dictionary = Journal.payload({"entries": dozen})
	_expect(failed, (trimmed.get("entries", []) as Array).size() == 10, "J1 client trims to 10")
	var missing: Dictionary = Journal.from_http(404, {"error": "not_found"})
	_expect(failed, str(missing.get("error", "")) == Contract.JOURNAL_ERR_UNAVAILABLE, "404 journal unavailable")
	_expect(failed, Journal.is_empty(missing), "404 does not invent rows")
	var live_ok: Dictionary = Journal.from_http(200, {"entries": dozen})
	_expect(failed, (Journal.payload(live_ok).get("entries", []) as Array).size() == 10, "200 still caps at 10")

	var plate = JournalPlate.new()
	plate._build()
	plate.bind({})
	_expect(failed, plate.row_count() == 0, "J5 plate has no rows")
	_expect(failed, plate.empty_visible(), "J5 empty plate visible")
	_expect(failed, plate.empty_headline() == Contract.JOURNAL_EMPTY, "J5 cozy empty copy")
	_expect(failed, plate.uses_wood(), "J6 wood plate")
	var shown: Array = []
	shown.append({
		"matchId": "m_prac",
		"mode": Contract.MODE_PRACTICE,
		"result": "win",
		"marksDelta": 25,
		"rematchAvailable": true,
		"rival": {"displayName": Contract.PRACTICE_RIVAL, "isBot": true},
	})
	shown.append({
		"matchId": "m_open",
		"mode": Contract.MODE_PVP,
		"result": "win",
		"marksDelta": 32,
		"rematchAvailable": true,
		"rival": {"displayName": "RIVAL", "isBot": false},
	})
	shown.append({
		"matchId": "m_shut",
		"mode": Contract.MODE_PVP,
		"result": "loss",
		"marksDelta": 4,
		"rematchAvailable": false,
		"rival": {"displayName": "RIVAL", "isBot": false},
	})
	plate.bind({"entries": shown})
	_expect(failed, plate.row_count() == 3, "J1 plate shows server rows")
	_expect(failed, plate.row_marks(0) == "0", "J2 plate practice 0")
	_expect(failed, plate.row_marks(1) == "+32", "journal win chip +32")
	_expect(failed, plate.row_marks(2) == "+4", "journal loss chip +4")
	_expect(failed, plate.row_tag(0) == Contract.JOURNAL_TAG_PRACTICE, "practice tag")
	_expect(failed, plate.row_cta_text(0) == Contract.JOURNAL_PRACTICE_AGAIN, "practice again label")
	_expect(failed, not plate.row_cta_disabled(0), "practice again enabled")
	_expect(failed, plate.row_tag(1) == Contract.JOURNAL_TAG_QUICK, "quick tag")
	_expect(failed, not plate.row_cta_disabled(1), "J3 rematch enabled")
	_expect(failed, plate.row_cta_disabled(2), "J3 rematch muted")
	plate.press_row(2)
	_expect(failed, plate.rematch_presses == 0 and plate.practice_presses == 0, "J3 muted press does nothing")
	plate.press_row(0)
	_expect(failed, plate.practice_presses == 1 and plate.rematch_presses == 0, "J4 press is practice again")
	plate.press_row(1)
	_expect(failed, plate.rematch_presses == 1, "J3 press is rematch")
	var copy := plate.plate_copy().to_lower()
	_expect(failed, copy.find("mmr") < 0 and copy.find("elo") < 0, "J6 no rating chrome")
	_expect(failed, copy.find("ranked") < 0 and copy.find("ladder") < 0 and copy.find("replay") < 0, "J6 no ladder or replay")
	var plate_src := FileAccess.get_file_as_string("res://scenes/lobby/journal_plate.gd")
	_expect(failed, plate_src.find("make_wood_texture") >= 0, "J6 wood grain helper")
	_expect(failed, plate_src.find("chunk_button") >= 0, "J6 chunky CTA")
	_expect(failed, plate_src.to_lower().find("replay") < 0, "J6 plate has no replay")
	var hideout_src := FileAccess.get_file_as_string("res://scenes/lobby/hideout_lobby.gd")
	_expect(failed, hideout_src.find("practice_again.connect(_start_practice)") >= 0, "J4 practice again uses practice create")
	_expect(failed, hideout_src.find("rematch_match.connect(_journal_rematch)") >= 0, "J3 rematch uses rematch path")
	_expect(failed, hideout_src.find("MatchAPI.get_journal()") >= 0, "hideout binds journal payload")
	var live_src := FileAccess.get_file_as_string("res://autoload/live_match_client.gd")
	_expect(failed, live_src.find("\"/journal\"") >= 0, "LIVE GET /journal")
	_expect(failed, live_src.find("player_bearer") >= 0, "journal uses Bearer")
	var api_src := FileAccess.get_file_as_string("res://autoload/match_api.gd")
	_expect(failed, api_src.find("JOURNAL_ERR_UNAVAILABLE") >= 0, "404 falls back until the route lands")
	_expect(failed, api_src.find("func rematch_match") >= 0, "rematch_match reuses rematch")
	var lock_rows: Array = [
		{"matchId": "m_foil", "mode": Contract.MODE_PVP, "result": "win", "marksDelta": 12, "endReason": "forfeit", "rival": {"displayName": "RIVAL", "isBot": false}},
		{"matchId": "m_stand", "mode": Contract.MODE_PVP, "result": "draw", "marksDelta": 8, "rival": {"displayName": "RIVAL", "isBot": false}},
		{"matchId": "m_t2", "mode": Contract.MODE_SP_JOB, "result": "win", "marksDelta": 15, "jobTier": 2, "rival": {"displayName": "BOT", "isBot": true}},
		{"matchId": "m_t3f", "mode": Contract.MODE_SP_JOB, "result": "loss", "marksDelta": 0, "jobTier": 3, "rival": {"displayName": "BOT", "isBot": true}},
	]
	plate.bind({"entries": lock_rows})
	_expect(failed, plate.row_marks(0) == "+15", "journal forfeit row +15")
	_expect(failed, plate.row_marks(1) == "+10", "journal standoff row +10")
	_expect(failed, plate.row_marks(2) == "+18", "journal T2 row +18")
	_expect(failed, plate.row_marks(3) == "+3", "journal T3 fail row +3")
	_expect(failed, plate.uses_wood(), "journal lock rows stay on wood")
	plate.free()
	server.test_now_ms = -1


func _exposure_floor_case(failed: PackedStringArray) -> void:
	## E1–E5: doll and the end-turn band read you.exposureFloor. Missing → 50.
	## Client never maps operativeLevel, never writes the %, cosmetics stay blind.
	var bare: Snapshot = Snapshot.from_dict({"you": {"exposurePct": 80, "operativeLevel": 4}})
	_expect(failed, not bare.you_exposure_floor_present(), "E1 floor field absent")
	_expect(failed, bare.you_exposure_floor() == 50, "E1 missing floor fail-closes to 50")
	_expect(failed, int(bare.you_exposure()) == 80, "E1 exposurePct stays the intent")
	var zero: Snapshot = Snapshot.from_dict({"you": {"exposureFloor": 0}})
	_expect(failed, zero.you_exposure_floor() == 50, "E1 never show 0")
	var junk: Snapshot = Snapshot.from_dict({"you": {"exposureFloor": 15}})
	_expect(failed, junk.you_exposure_floor() == 50, "E2 unknown percent fail-closes to 50")
	var high: Snapshot = Snapshot.from_dict({"you": {"exposureFloor": 99}})
	_expect(failed, high.you_exposure_floor() == 50, "E2 above the steps fail-closes to 50")
	for step in [50, 40, 30, 20]:
		var stepped: Snapshot = Snapshot.from_dict({"you": {"exposureFloor": step, "operativeLevel": 9}})
		_expect(failed, stepped.you_exposure_floor() == step, "E2 server step %d" % step)
	var level_only := {"operativeLevel": 9, "equippedSkinId": Contract.SHOP_STUB_ITEM_ID}
	_expect(failed, Contract.exposure_floor_from_payload(level_only) == 50, "E4 level + skin do not author a floor")
	_expect(failed, Contract.exposure_floor_from_payload({"you": {"exposureFloor": 20}}) == 20, "E3 you.exposureFloor 20")
	_expect(failed, Contract.exposure_floor_from_payload({"player": {"exposureFloor": 30}}) == 30, "hideout player.exposureFloor 30")
	_expect(failed, int(Contract.clamp_exposure_intent(50, 0.0)) == 50, "E1 band never 0")
	_expect(failed, int(Contract.clamp_exposure_intent(40, 80.0)) == 80, "E3 band allows above the floor")
	_expect(failed, int(Contract.clamp_exposure_intent(20, 10.0)) == 20, "E3 band cannot undercut the floor")
	var intent := ActionIntent.end_turn(50.0)
	_expect(failed, intent.has("exposurePct") and not intent.has("exposureFloor"), "E5 intent does not write the floor")
	_expect(failed, not intent.has("operativeLevel"), "E5 intent does not write operativeLevel")

	var Doll := load("res://scenes/match/exposure_doll.gd")
	var doll = Doll.new()
	doll.bind_floor(40)
	_expect(failed, doll.displayed_floor() == 40, "E3 doll shows 40")
	_expect(failed, doll.exposure_label() == "Exposure 40%", "E3 doll label Exposure 40%")
	var next40: Dictionary = Contract.snap_next_exposure(40, 50.0, 50.0, false)
	_expect(failed, int(next40["value"]) == 40 and int(next40["min"]) == 40, "floor 40 snaps stale NEXT 50 to 40")
	_expect(failed, "NEXT  %d%%" % int(next40["value"]) == "NEXT  40%", "floor 40 NEXT label 40%")
	var raised: Dictionary = Contract.snap_next_exposure(40, 70.0, float(next40["baseline"]), true)
	_expect(failed, int(raised["value"]) == 70 and bool(raised["player_raised"]), "player raise above floor 40 stays")
	var raised_50: Dictionary = Contract.snap_next_exposure(40, 50.0, float(next40["baseline"]), true)
	_expect(failed, int(raised_50["value"]) == 50, "player-raised 50 is above the floor")
	var stale: Dictionary = Contract.snap_next_exposure(40, 50.0, float(next40["baseline"]), false)
	_expect(failed, int(stale["value"]) == 40, "stale NEXT 50 snaps while floor is 40")
	var tracked: Dictionary = Contract.snap_next_exposure(30, 40.0, 40.0, false)
	_expect(failed, int(tracked["value"]) == 30, "untouched NEXT tracks a lower floor")
	var under: Dictionary = Contract.snap_next_exposure(20, 10.0, 50.0, true)
	_expect(failed, int(under["value"]) == 20 and not bool(under["player_raised"]), "NEXT cannot undercut the floor")
	doll.bind_floor(50)
	_expect(failed, doll.displayed_floor() == 50, "floor 50 doll shows 50")
	_expect(failed, doll.exposure_label() == "Exposure 50%", "floor 50 doll label Exposure 50%")
	var next50: Dictionary = Contract.snap_next_exposure(50, 50.0, 50.0, false)
	_expect(failed, int(next50["value"]) == 50 and int(next50["min"]) == 50, "floor 50 NEXT stays 50")
	_expect(failed, "NEXT  %d%%" % int(next50["value"]) == "NEXT  50%", "floor 50 NEXT label 50%")
	doll.bind_floor(0)
	_expect(failed, doll.displayed_floor() == 50, "E1 doll 0 fail-closes to 50")
	_expect(failed, doll.exposure_label() == "Exposure 50%", "E3 doll label Exposure 50%")
	doll.bind_equipped(Contract.SHOP_STUB_ITEM_ID)
	_expect(failed, doll.displayed_floor() == 50, "E4 skin wash does not move the floor")
	doll.free()

	var Tip := load("res://scenes/match/exposure_floor_tip.gd")
	Tip.reset_store_for_test()
	Tip.suppressed = false
	_expect(failed, not Tip.is_seen(), "E3 tip unseen")
	var tip = Tip.new()
	tip.observe(50)
	_expect(failed, not tip.is_showing(), "E3 first floor is not a drop")
	tip.observe(40)
	_expect(failed, tip.is_showing(), "E3 tip on the first drop")
	_expect(failed, tip.body_text() == Contract.EXPOSURE_FLOOR_TIP, "E3 tip copy")
	_expect(failed, tip.passthrough_ok(), "E3 tip body ignores the mouse")
	tip.observe(40)
	_expect(failed, tip.is_showing(), "E3 tip stays until dismiss")
	tip.dismiss()
	_expect(failed, not tip.is_showing(), "E3 tip dismissed")
	_expect(failed, Tip.is_seen(), "E3 tip seen forever")
	tip.observe(30)
	_expect(failed, not tip.is_showing(), "E3 no second tip")
	var Coach := load("res://scenes/match/first_hunt_coach.gd")
	var saved_coach: String = Coach.store_path
	Coach.store_path = Tip.store_path
	Coach.reset_tips()
	_expect(failed, not Tip.is_seen(), "E3 reset tips clears the floor flag")
	_expect(failed, Tip.stored_prior() == 50, "E3 reset restores the tip baseline to 50")
	tip.seed_prior(50)
	tip.observe(30)
	_expect(failed, tip.is_showing(), "E3 tip can show again after reset")
	tip.free()
	Coach.store_path = saved_coach
	Tip.restore_store()

	server.clear_all()
	server.reset_wallet(0)
	var created: Dictionary = server.create_match()
	var mid := str(created["matchId"])
	var a: Dictionary = server.join(mid, created["joinTokens"]["a"])
	var b: Dictionary = server.join(mid, created["joinTokens"]["b"])
	var pid_a := str(a["playerId"])
	var joined: Snapshot = Snapshot.from_dict(a["snapshot"])
	_expect(failed, joined.you_exposure_floor_present(), "mock publishes exposureFloor 50")
	_expect(failed, joined.you_exposure_floor() == 50, "E1 mock start floor 50")
	server.test_omit_exposure_floor = true
	var omitted: Snapshot = Snapshot.from_dict(server.get_snapshot(mid, pid_a))
	_expect(failed, not omitted.you_exposure_floor_present(), "omit leaves the field off")
	_expect(failed, omitted.you_exposure_floor() == 50, "E1 omitted field still reads 50")
	server.test_omit_exposure_floor = false
	server.test_exposure_floor = 40
	server.equipped_cosmetic = Contract.SHOP_STUB_ITEM_ID
	var worn: Snapshot = Snapshot.from_dict(server.get_snapshot(mid, pid_a))
	_expect(failed, worn.you_exposure_floor() == 40, "E2 mock step 40")
	_expect(failed, worn.you_equipped_skin_id() == Contract.SHOP_STUB_ITEM_ID, "E4 skin still equips")
	_expect(failed, worn.you_exposure_floor() == 40, "E4 skin does not change the floor")
	server.equipped_cosmetic = ""
	server.apply_action(mid, pid_a, ActionIntent.select_hex(2, 2))
	server.apply_action(mid, b["playerId"], ActionIntent.select_hex(7, 5))
	server.apply_action(mid, pid_a, ActionIntent.start())
	server.apply_action(mid, pid_a, ActionIntent.attack(0, 0))
	var body := ActionIntent.end_turn(10.0)
	body["exposureFloor"] = 20
	body["operativeLevel"] = 8
	var ended: ActionResult = server.apply_action(mid, pid_a, body)
	_expect(failed, ended.ok, "end_turn still accepts exposurePct")
	var after: Snapshot = Snapshot.from_dict(ended.snapshot)
	_expect(failed, int(after.you_exposure()) == 10, "E5 exposurePct intent is stored")
	_expect(failed, after.you_exposure_floor() == 40, "E5 action cannot write the floor")
	_expect(failed, int(after.operative_level()) == Contract.SMOKE_UNLOCK_LEVEL, "E5 action cannot write operativeLevel")
	_expect(failed, int(after.you().get("operativeLevel")) != 8, "E5 injected operativeLevel is ignored")
	_expect(failed, Contract.RECON_BASE == 0.35, "E3 RECON_BASE unchanged")
	_expect(failed, Contract.BASE_HIT_CHANCE == 0.90, "E3 attack band unchanged")
	_expect(failed, Contract.MARKS_PVP_WIN == 32, "E4 Marks table ★32")
	var screen_src := FileAccess.get_file_as_string("res://scenes/match/match_screen.gd")
	_expect(failed, screen_src.find("you_exposure_floor()") >= 0, "doll bind reads you.exposureFloor")
	_expect(failed, screen_src.find("clamp_exposure_intent") >= 0, "Recon/Attack band min reads the floor")
	_expect(failed, screen_src.find("snap_next_exposure") >= 0, "NEXT label and slider snap to the server floor")
	_expect(failed, screen_src.find("min_value = 0") < 0, "exposure slider is not hardcoded to 0")
	var session = SessionScript.new()
	session.bind_player({"playerId": "p_floor", "token": "tok_floor", "operativeLevel": 6, "marks": 4})
	_expect(failed, session.exposure_floor == 50, "hideout self without the field stays 50")
	session.bind_player({"playerId": "p_floor", "token": "tok_floor", "exposureFloor": 40, "marks": 4})
	_expect(failed, session.exposure_floor == 40, "hideout self exposureFloor 40")
	session.apply_shop({"marks": 4, "equipped": Contract.SHOP_BANDANA_ITEM_ID})
	_expect(failed, session.exposure_floor == 50, "shop payload without the field fail-closes to 50")
	session.apply_snapshot({"you": {"marks": 4, "exposureFloor": 30, "equippedSkinId": Contract.SHOP_BANDANA_ITEM_ID}})
	_expect(failed, session.exposure_floor == 30, "snapshot you.exposureFloor 30")
	_expect(failed, session.bandana, "E4 bandana still equips beside the floor")
	session.free()
	server.test_exposure_floor = null
	server.test_omit_exposure_floor = false
	server.equipped_cosmetic = ""


func _journal_end(mode: String, winner: String, reason: String) -> Dictionary:
	var created: Dictionary = server.create_match({"mode": mode})
	var mid := str(created.get("matchId", ""))
	if mode == Contract.MODE_PRACTICE:
		server.join(mid, Contract.create_join_token(created))
	else:
		var tokens: Dictionary = created.get("joinTokens", {})
		server.join(mid, str(tokens.get("a", "")))
		server.join(mid, str(tokens.get("b", "")))
	server.force_end(mid, winner, reason)
	created["matchId"] = mid
	return created


func _expect(failed: PackedStringArray, cond: bool, label: String) -> void:
	if not cond:
		failed.append(label)
