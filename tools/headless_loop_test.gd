extends SceneTree
## Offline contract loop: drop both seats, miss, UAV reveal, kill, marks +1.
## Run: godot --headless --path . -s res://tools/headless_loop_test.gd

const Contract := preload("res://types/contract.gd")
const ActionIntent := preload("res://types/action_intent.gd")
const ActionResult := preload("res://types/action_result.gd")
const Snapshot := preload("res://types/snapshot.gd")
const MarksPayout := preload("res://types/marks_payout.gd")
const Shop := preload("res://types/shop.gd")
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

	_live_shape_case(failed)
	_payout_shape_case(failed)
	_job_case(failed)
	_a2_reconnect_case(failed)
	_shop_case(failed)
	_live_shop_shape_case(failed)
	_player_persist_case(failed)

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
	_expect(failed, live_copy.find("table  +25") >= 0, "table copy when delta omitted")
	_expect(failed, live_copy.find("kill") >= 0, "pvp keeps kill")
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
	_expect(failed, sp_copy.find("table  T1 +10") >= 0, "sp table copy uses job row")
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


func _shop_case(failed: PackedStringArray) -> void:
	## S1–S4: catalog, buy snapshot bind, insufficient reject, visual equip. No combat delta.
	server.clear_all()
	server.reset_wallet(Contract.MOCK_WALLET_STUB)
	var catalog: Dictionary = server.get_shop()
	var listed = Shop.from_any(catalog)
	_expect(failed, listed.item_id() == Contract.SHOP_STUB_ITEM_ID, "S1 shop stub itemId")
	_expect(failed, listed.price() == Contract.SHOP_STUB_PRICE, "S1 GD price 50")
	_expect(failed, listed.price() == 50, "S1 catalog price is 50 not 40")
	_expect(failed, listed.balance() == Contract.MOCK_WALLET_STUB, "S1 you.marks stub 24")
	_expect(failed, not listed.owns_stub(), "S1 not owned yet")
	_expect(failed, not listed.can_afford(), "S3 ★24 cannot afford ★50")
	_expect(failed, Shop.row_action_text(false) == "BUY", "P2 unaffordable action is BUY")
	_expect(failed, Shop.row_status_text(false, false) == Contract.SHOP_INSUFFICIENT_COPY, "P2 BUY status insufficient")
	_expect(failed, not Shop.row_buy_enabled(false, false), "P2 BUY disabled when Marks < price")
	_expect(failed, Shop.row_action_text(true) == "OWNED", "P2 owned action is OWNED not EQUIPPED")
	_expect(failed, Shop.row_status_text(true, true) == Contract.SHOP_OWNED_COPY, "P2 owned copy visual only")
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
