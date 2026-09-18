extends Control

const Chrome := preload("res://scripts/chrome.gd")
const Contract := preload("res://types/contract.gd")
const MarksPayout := preload("res://types/marks_payout.gd")

var _bg: TextureRect
var _toast: Label
var _marks: Label
var _last_pay: Label
var _mode_lbl: Label
var _mode_btn: Button
var _jobs_panel: PanelContainer


func _ready() -> void:
	set_anchors_preset(PRESET_FULL_RECT)
	_build()
	_refresh_bg()
	_bind_wallet()
	_refresh_marks()
	if "--capture-a1" in OS.get_cmdline_user_args():
		await get_tree().process_frame
		_on_play()
	elif "--capture-sp-end" in OS.get_cmdline_user_args():
		await get_tree().process_frame
		_on_start_job()


func _build() -> void:
	_bg = TextureRect.new()
	_bg.set_anchors_preset(PRESET_FULL_RECT)
	_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg)

	var top := ColorRect.new()
	top.color = Color(0.08, 0.06, 0.05, 0.82)
	top.set_anchors_and_offsets_preset(PRESET_TOP_WIDE)
	top.offset_bottom = 86
	add_child(top)

	var chip := Label.new()
	chip.text = ClientSession.HANDLE
	chip.position = Vector2(24, 18)
	Chrome.apply_label(chip, 12, Chrome.CREAM, true)
	add_child(chip)

	_marks = Label.new()
	_marks.position = Vector2(24, 44)
	_marks.size = Vector2(420, 22)
	Chrome.apply_label(_marks, 10, Chrome.HIGH_GOLD, true)
	add_child(_marks)

	_last_pay = Label.new()
	_last_pay.position = Vector2(24, 66)
	_last_pay.size = Vector2(520, 16)
	Chrome.apply_label(_last_pay, 8, Color("d8c48a"), true)
	add_child(_last_pay)

	var title := Label.new()
	title.text = "GLASSLINE"
	title.position = Vector2(0, 16)
	title.size = Vector2(1280, 48)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	Chrome.apply_label(title, 28, Color.WHITE, true)
	add_child(title)

	_mode_lbl = Label.new()
	_mode_lbl.position = Vector2(900, 18)
	_mode_lbl.size = Vector2(360, 20)
	_mode_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	Chrome.apply_label(_mode_lbl, 8, Chrome.TEAL, true)
	add_child(_mode_lbl)

	_mode_btn = Chrome.chunk_button("MOCK", Chrome.INK, Chrome.CREAM, Vector2(140, 36))
	_mode_btn.position = Vector2(1120, 42)
	_mode_btn.pressed.connect(_toggle_live)
	add_child(_mode_btn)
	_refresh_mode()

	var bottom := ColorRect.new()
	bottom.color = Color(0.08, 0.06, 0.05, 0.88)
	bottom.set_anchors_and_offsets_preset(PRESET_BOTTOM_WIDE)
	bottom.offset_top = -110
	add_child(bottom)

	var row := HBoxContainer.new()
	row.set_anchors_preset(PRESET_BOTTOM_WIDE)
	row.offset_top = -96
	row.offset_bottom = -20
	row.offset_left = 80
	row.offset_right = -80
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 28)
	add_child(row)

	var loadout := Chrome.chunk_button("  LOADOUT", Chrome.LOADOUT_BLUE, Color.WHITE, Vector2(260, 68))
	loadout.pressed.connect(_toast_msg.bind("Slice 1: loadout stays in the hideout."))
	row.add_child(loadout)

	var play := Chrome.chunk_button("  PLAY", Chrome.PLAY_GREEN, Color.WHITE, Vector2(300, 72))
	play.pressed.connect(_on_play)
	row.add_child(play)

	var jobs := Chrome.chunk_button("  JOBS", Chrome.JOBS_WHITE, Chrome.INK, Vector2(260, 68))
	jobs.pressed.connect(_toggle_jobs)
	row.add_child(jobs)

	var ghillie := Chrome.chunk_button("SUIT", Chrome.TEAL, Color.WHITE, Vector2(120, 44))
	ghillie.position = Vector2(24, 600)
	ghillie.pressed.connect(_toggle_suit)
	add_child(ghillie)

	_toast = Label.new()
	_toast.position = Vector2(200, 540)
	_toast.size = Vector2(880, 36)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	Chrome.apply_label(_toast, 10, Color("f0e3b0"), true)
	add_child(_toast)

	_build_jobs_panel()


func _build_jobs_panel() -> void:
	_jobs_panel = PanelContainer.new()
	_jobs_panel.visible = false
	_jobs_panel.position = Vector2(360, 150)
	_jobs_panel.custom_minimum_size = Vector2(560, 320)
	var box := Chrome.flat(Color(0.12, 0.09, 0.07, 0.96), 18, Chrome.HIGH_GOLD, 3)
	_jobs_panel.add_theme_stylebox_override("panel", box)
	add_child(_jobs_panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	_jobs_panel.add_child(col)

	var kicker := Label.new()
	kicker.text = "BLACK-MARKET"
	Chrome.apply_label(kicker, 8, Chrome.HIGH_GOLD, true)
	col.add_child(kicker)

	var heading := Label.new()
	heading.text = "SP JOB  vs BOT"
	Chrome.apply_label(heading, 16, Chrome.CREAM, true)
	col.add_child(heading)

	var blurb := Label.new()
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.custom_minimum_size = Vector2(500, 80)
	blurb.text = "T1 Rooftop Rookie  +10   ·   T2 +15   ·   T3 +20\nSame Attack / Recon / UAV vs a scripted seat."
	Chrome.apply_label(blurb, 8, Chrome.CREAM)
	col.add_child(blurb)

	var start := Chrome.chunk_button("START JOB", Chrome.ABILITY_PURPLE, Color.WHITE, Vector2(280, 56))
	start.pressed.connect(_on_start_job)
	col.add_child(start)

	var cancel := Chrome.chunk_button("BACK", Chrome.INK, Chrome.CREAM, Vector2(160, 40))
	cancel.pressed.connect(_toggle_jobs)
	col.add_child(cancel)


func _bind_wallet() -> void:
	var wallet: Dictionary = MatchAPI.wallet()
	if wallet.has("marks"):
		ClientSession.bind_marks(int(wallet.get("marks")))


func _refresh_marks() -> void:
	if _marks:
		_marks.text = Chrome.marks_chip_text(ClientSession.marks)
	if _last_pay:
		if ClientSession.last_payout.is_empty():
			_last_pay.text = ""
		else:
			var pay = MarksPayout.from_any(ClientSession.last_payout)
			var line: String = pay.payout_line()
			var why: String = str(pay.reason)
			if line != "" and why != "":
				_last_pay.text = "Last hunt  %s  ·  %s" % [line, why]
			elif line != "":
				_last_pay.text = "Last hunt  %s" % line
			else:
				_last_pay.text = "Last hunt  %s" % why


func _refresh_bg() -> void:
	var path := "res://assets/canon/lobby-ghillie.jpg" if ClientSession.ghillie else "res://assets/canon/lobby-canon.jpg"
	_bg.texture = load(path)


func _toggle_suit() -> void:
	ClientSession.ghillie = not ClientSession.ghillie
	_refresh_bg()


func _toast_msg(text: String) -> void:
	_toast.text = text


func _toggle_jobs() -> void:
	_jobs_panel.visible = not _jobs_panel.visible
	if _jobs_panel.visible:
		_toast_msg("Hunt a bot — same Attack / Recon / UAV.")


func _toggle_live() -> void:
	ClientSession.live_override = 0 if ClientSession.use_live_api() else 1
	_refresh_mode()
	_bind_wallet()
	_refresh_marks()


func _refresh_mode() -> void:
	if ClientSession.use_live_api():
		_mode_lbl.text = "LIVE  %s" % ClientSession.api_base_url()
		_mode_btn.text = "LIVE"
	else:
		_mode_lbl.text = "OFFLINE MOCK"
		_mode_btn.text = "MOCK"


func _on_play() -> void:
	_start_match(Contract.MODE_PVP)


func _on_start_job() -> void:
	_jobs_panel.visible = false
	_start_job(1)


func _start_match(mode: String) -> void:
	MatchAPI.clear_all()
	ClientSession.reset_match()
	ClientSession.match_mode = mode
	if ClientSession.use_live_api():
		var health: Dictionary = MatchAPI.health()
		if not bool(health.get("ok", false)):
			_toast_msg("Live API down at %s  (GET /health)" % ClientSession.api_base_url())
			return
	var created: Dictionary = MatchAPI.create_match({
		"mode": mode,
		"job": mode == Contract.MODE_SP_JOB,
		"sp": mode == Contract.MODE_SP_JOB,
		"jobTier": 1,
	})
	var match_id := str(created.get("matchId", ""))
	var tokens: Dictionary = created.get("joinTokens", {})
	if match_id == "" or tokens.is_empty():
		_toast_msg("Create failed: %s" % str(created.get("error", "no matchId")))
		return
	ClientSession.join_token = str(tokens.get("a", ""))
	ClientSession.dummy_token = str(tokens.get("b", ""))
	var human: Dictionary = MatchAPI.join(match_id, ClientSession.join_token)
	var dummy: Dictionary = MatchAPI.join(match_id, ClientSession.dummy_token)
	if human.has("error") or dummy.has("error"):
		_toast_msg("Join failed: %s" % str(human.get("error", dummy.get("error", ""))))
		return
	ClientSession.match_id = match_id
	ClientSession.player_id = str(human.get("playerId", ""))
	ClientSession.seat = str(human.get("seat", "a"))
	ClientSession.dummy_player_id = str(dummy.get("playerId", ""))
	var ready_snap: Dictionary = MatchAPI.get_snapshot(match_id, ClientSession.player_id)
	if ready_snap.is_empty():
		ready_snap = human.get("snapshot", {})
	ClientSession.apply_snapshot(ready_snap)
	MatchAPI.start_events()
	get_tree().change_scene_to_file("res://scenes/match/match_screen.tscn")


func _start_job(tier: int) -> void:
	MatchAPI.clear_all()
	ClientSession.reset_match()
	ClientSession.match_mode = Contract.MODE_SP_JOB
	ClientSession.job_tier = tier
	if ClientSession.use_live_api():
		var health: Dictionary = MatchAPI.health()
		if not bool(health.get("ok", false)):
			_toast_msg("Live API down at %s  (GET /health)" % ClientSession.api_base_url())
			return
	var created: Dictionary = MatchAPI.create_job(tier)
	var match_id := str(created.get("matchId", ""))
	if match_id == "" or created.has("error"):
		_toast_msg("Job failed: %s" % str(created.get("error", "no matchId")))
		return
	ClientSession.match_id = match_id
	ClientSession.job_id = str(created.get("jobId", ""))
	ClientSession.player_id = str(created.get("playerId", ""))
	ClientSession.seat = str(created.get("seat", "a"))
	ClientSession.join_token = str(created.get("joinToken", ""))
	if ClientSession.join_token == "":
		var tokens: Variant = created.get("joinTokens", {})
		if tokens is Dictionary:
			ClientSession.join_token = str(tokens.get("a", ""))
	ClientSession.job_tier = int(created.get("tier", tier))
	## LIVE job: server bot is seat B. Mock still returns dummy ids for the local loop.
	if not ClientSession.use_live_api():
		ClientSession.dummy_token = str(created.get("dummyToken", ""))
		ClientSession.dummy_player_id = str(created.get("dummyPlayerId", ""))
	var ready_snap: Dictionary = created.get("snapshot", {})
	if ready_snap.is_empty():
		ready_snap = MatchAPI.get_snapshot(match_id, ClientSession.player_id)
	ClientSession.apply_snapshot(ready_snap)
	MatchAPI.start_events()
	get_tree().change_scene_to_file("res://scenes/match/match_screen.tscn")
