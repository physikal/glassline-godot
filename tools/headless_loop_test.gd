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
const MockScript := preload("res://autoload/mock_match_server.gd")
const SessionScript := preload("res://autoload/client_session.gd")

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
	_expect(failed, snap.you_marks() == Contract.MARKS_PVP_WIN, "marks +25 wallet")
	_expect(failed, snap.marks_delta() == Contract.MARKS_PVP_WIN, "marksDelta +25 from server payout")
	_expect(failed, snap.end_reason() == Contract.END_KILL, "payout reason kill")
	_expect(failed, int(snap.payout().balance()) == Contract.MARKS_PVP_WIN, "payout.marks wallet")
	var loser: Snapshot = Snapshot.from_dict(server.get_snapshot(match_id, pid_b))
	_expect(failed, loser.marks_delta() == Contract.MARKS_PVP_LOSS, "loser +3")
	_expect(failed, loser.end_reason() == Contract.END_LOSS, "loser reason")
	var replay_wallet: int = server.account_marks
	var again: Dictionary = server.get_snapshot(match_id, pid_a)
	_expect(failed, server.account_marks == replay_wallet, "replay snapshot does not grant again")
	_expect(failed, Snapshot.from_dict(again).marks_delta() == Contract.MARKS_PVP_WIN, "settled payout stays")
	r = server.apply_action(match_id, pid_a, ActionIntent.attack(6, 5))
	_expect(failed, not r.ok, "replay end refused")
	_expect(failed, server.account_marks == replay_wallet, "refused replay does not double grant")

	_decoy_case(failed)
	_lobby_case(failed)
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
	_equip_chrome_case(failed)
	_player_persist_case(failed)
	_first_hunt_coach_case(failed)

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
	_expect(failed, Contract.MARKS_PVP_WIN == 25, "D5 PvP kill table still ★25")

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
	_expect(failed, kill_snap.marks_delta() == Contract.MARKS_PVP_WIN, "P3 winner ★25")
	_expect(failed, kill_snap.end_reason() == Contract.END_KILL, "P3 reason kill")
	var loser: Snapshot = Snapshot.from_dict(server.get_snapshot(mid, pid_a))
	_expect(failed, loser.marks_delta() == Contract.MARKS_PVP_LOSS, "P3 loser ★3")
	_expect(failed, loser.rematch_offered(), "P3 rematch still offered")
	_expect(failed, Contract.RECON_BASE == 0.35 and Contract.MARKS_PVP_WIN == 25, "P3 combat table unchanged")

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
	## A4.1 abandon → forfeit +12/0. Same settle as timeout. Rematch only after ended.
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
	_expect(failed, winner_snap.you_marks() == Contract.MARKS_FORFEIT_WIN, "A4.1 remaining +12")
	_expect(failed, winner_snap.marks_delta() == Contract.MARKS_FORFEIT_WIN, "A4.1 remaining marksDelta +12")
	_expect(failed, winner_snap.rematch_offered(), "A4.4 rematch CTA after ended")
	var again: Dictionary = server.abandon(mid, pid_a)
	_expect(failed, bool(again.get("ok", false)), "A4.1 abandon idempotent")
	_expect(failed, bool(again.get("alreadyEnded", false)), "A4.1 alreadyEnded")
	_expect(failed, server.account_marks == 24, "A4.1 replay abandon no second grant")
	var foil := MarksPayout.end_overlay(winner_snap.raw, "b", false)
	_expect(failed, foil.find("RIVAL FORFEIT") >= 0, "A4.4 overlay winner chrome")
	_expect(failed, foil.find("+12") >= 0 or foil.find("table  +12") >= 0, "A4.4 overlay +12")

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
	_expect(failed, after.you_marks() == 10 + Contract.MARKS_FORFEIT_WIN, "A4.2 remaining +12")
	_expect(failed, after.rematch_offered(), "A4.4 rematch after timeout forfeit")
	_expect(failed, bool(grace.get("ok", false)), "A4.3 start_grace ok")


func _end_summary_case(failed: PackedStringArray) -> void:
	## M.1–M.3: kill / forfeit / standoff chrome + table Δ + rematch still offered.
	var kill_win := {
		"status": "ended",
		"winner": "a",
		"endReason": "kill",
		"kind": "pvp",
		"you": {"seat": "a", "marks": 25},
		"rematch": {"status": "waiting", "youAccepted": false, "opponentAccepted": false},
	}
	var kill_lose := {
		"status": "ended",
		"winner": "a",
		"endReason": "kill",
		"kind": "pvp",
		"you": {"seat": "b", "marks": 3},
		"rematch": {"status": "waiting"},
	}
	var stand_a := {
		"status": "ended",
		"winner": "draw",
		"endReason": "standoff",
		"kind": "pvp",
		"you": {"seat": "a", "marks": 8},
		"rematch": {"status": "waiting"},
	}
	var stand_b := {
		"status": "ended",
		"winner": "draw",
		"endReason": "standoff",
		"kind": "pvp",
		"you": {"seat": "b", "marks": 8},
	}
	var foil_win := {
		"status": "ended",
		"winner": "b",
		"endReason": "forfeit",
		"kind": "pvp",
		"you": {"seat": "b", "marks": 12},
		"rematch": {"status": "waiting"},
	}
	var foil_leave := {
		"status": "ended",
		"winner": "b",
		"endReason": "forfeit",
		"kind": "pvp",
		"you": {"seat": "a", "marks": 0},
	}
	_expect(failed, MarksPayout.table_delta(kill_win, "a") == 25, "M.2 kill winner +25")
	_expect(failed, MarksPayout.table_delta(kill_lose, "b") == 3, "M.2 kill loser +3")
	_expect(failed, MarksPayout.table_delta(stand_a, "a") == 8, "M.2 standoff A +8")
	_expect(failed, MarksPayout.table_delta(stand_b, "b") == 8, "M.2 standoff B +8")
	_expect(failed, MarksPayout.table_delta(foil_win, "b") == 12, "M.2 forfeit remaining +12")
	_expect(failed, MarksPayout.table_delta(foil_leave, "a") == 0, "M.2 forfeit leaver 0")
	var ow := MarksPayout.end_overlay(kill_win, "a", false)
	_expect(failed, ow.find("MARK CONFIRMED") >= 0, "M.1 kill winner headline")
	_expect(failed, ow.find("+25 MARK") >= 0 and ow.find("★25") >= 0, "M.1 kill winner marks line")
	_expect(failed, ow.find("\nkill") >= 0, "M.1 kill winner reason")
	var ol := MarksPayout.end_overlay(kill_lose, "b", false)
	_expect(failed, ol.find("ELIMINATED") >= 0, "M.1 kill loser headline")
	_expect(failed, ol.find("+3 MARK") >= 0 and ol.find("★3") >= 0, "M.1 kill loser marks line")
	_expect(failed, ol.find("\nkill") >= 0, "M.1 kill loser reason is kill not loss")
	var os := MarksPayout.end_overlay(stand_a, "a", false)
	_expect(failed, os.find("STANDOFF") >= 0, "M.1 standoff headline")
	_expect(failed, os.find("+8 MARK") >= 0 and os.find("★8") >= 0, "M.1 standoff marks line")
	_expect(failed, os.find("\nstandoff") >= 0, "M.1 standoff reason")
	_expect(failed, MarksPayout.end_overlay(stand_b, "b", false).find("+8 MARK") >= 0, "M.1 standoff both seats")
	var of := MarksPayout.end_overlay(foil_win, "b", false)
	_expect(failed, of.find("RIVAL FORFEIT") >= 0, "M.1 remaining headline")
	_expect(failed, of.find("+12 MARK") >= 0 and of.find("★12") >= 0, "M.1 remaining marks line")
	_expect(failed, of.find("\nforfeit") >= 0, "M.1 remaining reason")
	var ox := MarksPayout.end_overlay(foil_leave, "a", false)
	_expect(failed, ox.find("FORFEIT") >= 0 and ox.find("RIVAL") < 0, "M.1 leaver headline")
	_expect(failed, ox.find("+0 MARK") >= 0, "M.1 leaver +0 MARK")
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
	_expect(failed, winner_snap.table_marks_delta() == 25, "M.2 mock kill winner table")
	_expect(failed, loser_snap.table_marks_delta() == 3, "M.2 mock kill loser table")
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
	_expect(failed, stand_snap.table_marks_delta() == 8, "M.2 force standoff +8")
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
	_expect(failed, overlay.find("+25 MARK") >= 0, "end overlay table Δ not payload 1")
	_expect(failed, overlay.find("★12") >= 0, "end overlay balance")
	_expect(failed, MarksPayout.live_delta_drifts(live_body["snapshot"], "a", false), "payload 1 drifts vs table +25")
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
	_expect(failed, job_win.find("job") >= 0, "job win reason")
	var live_ended := {
		"status": "ended",
		"winner": "a",
		"kind": "pvp",
		"endReason": "kill",
		"you": {"seat": "a", "marks": 25},
	}
	var live_copy := MarksPayout.end_overlay(live_ended, "a", false)
	_expect(failed, live_copy.find("MARK CONFIRMED") >= 0, "live endReason kill")
	_expect(failed, live_copy.find("★25") >= 0, "live you.marks balance")
	_expect(failed, live_copy.find("+25 MARK") >= 0, "table Δ when marksDelta omitted")
	_expect(failed, live_copy.find("table  +") < 0, "no table +N chrome")
	_expect(failed, live_copy.find("kill") >= 0, "pvp keeps kill")
	_expect(failed, not MarksPayout.live_delta_drifts(live_ended, "a", false), "LIVE omit marksDelta is not drift")
	var sp_live_kill := {
		"status": "ended",
		"winner": "a",
		"kind": "sp_job",
		"endReason": "kill",
		"job": {"jobId": "j_x", "tier": 1, "name": "Rooftop Rookie"},
		"you": {"seat": "a", "marks": 10},
	}
	var sp_copy := MarksPayout.end_overlay(sp_live_kill, "a", true)
	_expect(failed, sp_copy.find("JOB COMPLETE") >= 0, "sp kill maps headline")
	_expect(failed, sp_copy.find("job") >= 0, "sp kill displays reason job")
	_expect(failed, sp_copy.find("kill") < 0, "sp kill not shown as kill")
	_expect(failed, sp_copy.find("★10") >= 0, "sp overlay uses you.marks")
	_expect(failed, sp_copy.find("+10 MARK") >= 0, "sp table Δ uses job row")
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
	_expect(failed, sp_delta_copy.find("+10 MARK") >= 0, "sp delta from you.marks envelope")
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
	_expect(failed, snap.marks_delta() == Contract.MARKS_JOB_T1, "job T1 marksDelta +10")
	_expect(failed, snap.you_marks() == 20, "job wallet from server")
	_expect(failed, server.account_marks == 20, "mock ledger not client +=")
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
	_expect(failed, snap.marks_delta() == Contract.MARKS_JOB_T3, "job T3 marksDelta +20")
	_job_ladder_case(failed)


func _job_ladder_case(failed: PackedStringArray) -> void:
	## J1–J4 mock: T1/T2/T3 complete bind you.marks; same clientJobId does not grant again.
	_expect(failed, Contract.job_row_label(1) == "T1  Rooftop Rookie", "J5 T1 row label")
	_expect(failed, Contract.job_row_label(2) == "T2  Warehouse Watch", "J5 T2 row label")
	_expect(failed, Contract.job_row_label(3) == "T3  Night Contract", "J5 T3 row label")
	_expect(failed, Contract.job_tier_delta(1) == 10, "J1 table T1 ★10")
	_expect(failed, Contract.job_tier_delta(2) == 15, "J2 table T2 ★15")
	_expect(failed, Contract.job_tier_delta(3) == 20, "J3 table T3 ★20")
	server.clear_all()
	server.reset_wallet(0)
	var session = SessionScript.new()
	session.bind_marks(999)
	var j1: Dictionary = server.complete_job(1, "job-j1")
	session.apply_snapshot(j1.get("snapshot", {}))
	_expect(failed, session.marks == 10, "J1 snapshot you.marks 0→10 (not 999+)")
	_expect(failed, server.account_marks == 10, "J1 mock ledger +10")
	var j2: Dictionary = server.complete_job(2, "job-j2")
	session.apply_snapshot(j2.get("snapshot", {}))
	_expect(failed, session.marks == 25, "J2 snapshot you.marks 10→25")
	var j3: Dictionary = server.complete_job(3, "job-j3")
	session.apply_snapshot(j3.get("snapshot", {}))
	_expect(failed, session.marks == 45, "J3 snapshot you.marks 25→45")
	var replay: Dictionary = server.complete_job(3, "job-j3")
	session.bind_marks(999)
	session.apply_snapshot(replay.get("snapshot", {}))
	_expect(failed, server.account_marks == 45, "J4 same clientJobId no second grant")
	_expect(failed, session.marks == 45, "J4 replay binds snapshot 45 (never marks +=)")
	_expect(failed, str(replay.get("jobId", "")) == str(j3.get("jobId", "")), "J4 replay same jobId")
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
	_expect(failed, Contract.RECON_BASE == 0.35 and Contract.MARKS_PVP_WIN == 25, "S4 combat table unchanged")

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
	_expect(failed, Contract.RECON_BASE == 0.35 and Contract.MARKS_PVP_WIN == 25, "S2.4 combat table unchanged")

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
	_expect(failed, live_two.items.size() == 3, "LIVE two-SKU merge is three ARMORY rows")

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
	_expect(failed, listed.items.size() == 3, "S3.6 three catalog rows")
	_expect(failed, listed.balance() < 150, "S3.3 ★24 cannot afford ★150")
	_expect(failed, not Shop.row_buy_enabled(false, listed.balance() >= 150), "S3.3 BUY disabled when Marks < 150")
	_expect(failed, Contract.RECON_BASE == 0.35 and Contract.MARKS_PVP_WIN == 25, "S3.5 combat table unchanged")

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
	_expect(failed, live_three.items.size() == 3, "prefer LIVE catalog size when +1 poster SKU")

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
	_expect(failed, Contract.MARKS_PVP_WIN == 25, "E5 PvP kill ★25")
	_expect(failed, int(bare.get("kill_delta", -1)) == Contract.MARKS_PVP_WIN, "E5 kill marksDelta +25")


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
	_expect(failed, Contract.RECON_BASE == 0.35 and Contract.MARKS_PVP_WIN == 25, "C4 combat table unchanged")
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
	_expect(failed, snap.you_marks() == 4 + Contract.MARKS_STANDOFF, "standoff +8 wallet")
	_expect(failed, snap.marks_delta() == Contract.MARKS_STANDOFF, "standoff marksDelta +8")
	_expect(failed, snap.end_reason() == Contract.END_STANDOFF, "standoff reason")
	_expect(failed, server.account_marks == 4 + Contract.MARKS_STANDOFF, "standoff uses GD table")


func _expect(failed: PackedStringArray, cond: bool, label: String) -> void:
	if not cond:
		failed.append(label)
