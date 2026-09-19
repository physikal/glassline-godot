extends Control

const Chrome := preload("res://scripts/chrome.gd")
const HexBoard := preload("res://scenes/match/hex_board.gd")
const ExposureDoll := preload("res://scenes/match/exposure_doll.gd")
const Contract := preload("res://types/contract.gd")
const ActionIntent := preload("res://types/action_intent.gd")
const ActionResult := preload("res://types/action_result.gd")
const Snapshot := preload("res://types/snapshot.gd")
const HexMath := preload("res://scripts/hex_math.gd")
const MarksPayout := preload("res://types/marks_payout.gd")

enum Aim { NONE, ATTACK, RECON, RELOCATE }

var _board: HexBoard
var _board_host: Control
var _optic
var _status: Label
var _turn: Label
var _phase: Label
var _legend_hover: Label
var _toast: Label
var _end_panel: PanelContainer
var _exposure: HSlider
var _exposure_lbl: Label
var _exposure_doll: ExposureDoll
var _btn_attack: Button
var _btn_recon: Button
var _btn_uav: Button
var _btn_decoy: Button
var _ability_cap: Label
var _decoy_cap: Label
var _btn_start: Button
var _btn_end: Button
var _over: ColorRect
var _over_lbl: Label
var _over_settle: Label
var _over_hint: Label
var _over_timer: Label
var _btn_play_again: Button
var _btn_decline: Button
var _btn_hideout: Button
var _you_chip: Label
var _rival_chip: Label

var _aim: int = Aim.NONE
var _selected: Variant = null
var _dummy_placed: bool = false
var _dummy_busy: bool = false
var _dummy_delay: float = 0.0
var _relocate_hex: Variant = null
var _rematch_left: float = -1.0
var _rematch_busy: bool = false
var _going_hideout: bool = false


func _ready() -> void:
	set_anchors_preset(PRESET_FULL_RECT)
	set_process(true)
	_build()
	MatchAPI.match_event.connect(_on_match_event)
	if ClientSession.dummy_player_id == "" and ClientSession.is_job():
		_dummy_placed = true
	_apply_server_reconnect()
	var args := OS.get_cmdline_user_args()
	if "--capture-a1" in args:
		_capture_after_play()
	elif "--capture-a2" in args:
		_capture_a2_reconnect()
	elif "--capture-sp-end" in args:
		_capture_sp_end()
	elif "--capture-equip-doll" in args:
		_capture_equip_doll()
	elif "--capture-decoy-hud" in args:
		_capture_decoy_hud()
	elif "--capture-decoy-blip" in args:
		_capture_decoy_blip()
	elif "--capture-rematch-ended" in args:
		_capture_rematch_ended()
	elif "--capture-rematch-ready" in args:
		_capture_rematch_ready()


func _capture_after_play() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path("res://artifacts/a1-after-play.png")
	img.save_png(path)
	print("A1_AFTER_PLAY_CAPTURE ", path)
	get_tree().quit()


func _capture_sp_end() -> void:
	await get_tree().process_frame
	var snap: Snapshot = ClientSession.typed_snapshot()
	if snap.status() == Contract.STATUS_READY or snap.status() == Contract.STATUS_WAITING:
		_submit(ActionIntent.select_hex(2, 2))
		await get_tree().process_frame
		snap = ClientSession.typed_snapshot()
	if snap.status() == Contract.STATUS_READY:
		_submit(ActionIntent.start())
		await get_tree().process_frame
		snap = ClientSession.typed_snapshot()
	if snap.status() == Contract.STATUS_ACTIVE:
		## Mock bot hex is tier-locked (T1 8,6 / T2 7,5 / T3 8,5).
		var bot: Dictionary = Contract.job_bot_hex(ClientSession.job_tier)
		_submit(ActionIntent.attack(int(bot.get("q", 8)), int(bot.get("r", 6))))
		await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path("res://artifacts/ux/sp_job_end_reason_job.png")
	img.save_png(path)
	print("SP_END_REASON_CAPTURE ", path)
	get_tree().quit()


func _apply_server_reconnect() -> Dictionary:
	## A2: GET /matches/:id (or mock) replaces last_snapshot. No local merge.
	## Soft P2: do not show a player-facing SERVER SNAPSHOT (or similar) debug badge.
	_aim = Aim.NONE
	_relocate_hex = null
	var fresh: Dictionary = MatchAPI.reconnect()
	var snap: Snapshot = ClientSession.typed_snapshot()
	_exposure.value = snap.you_exposure()
	_bind_server_exposure(snap)
	_refresh(snap)
	return fresh


func _bind_server_exposure(snap: Snapshot) -> void:
	## Doll is server you.exposurePct. Slider is the next end_turn intent only.
	## Chrome wash is you.equippedSkinId (shop snapshot cache if match omits it).
	if _exposure_doll:
		_exposure_doll.bind_server_pct(snap.you_exposure())
		var skin := snap.you_equipped_skin_id()
		if skin == "" and not snap.you().has("equippedSkinId") and not snap.you().has("equipped"):
			skin = ClientSession.equipped_cosmetic
		_exposure_doll.bind_equipped(skin)


func _capture_equip_doll() -> void:
	## E6: same equippedSkinId chrome on the exposure doll (end-turn panel).
	await get_tree().process_frame
	var snap: Snapshot = ClientSession.typed_snapshot()
	if snap.status() == Contract.STATUS_READY or snap.status() == Contract.STATUS_WAITING:
		_submit(ActionIntent.select_hex(2, 2))
		await get_tree().create_timer(0.7).timeout
		snap = ClientSession.typed_snapshot()
	if snap.status() == Contract.STATUS_READY:
		_submit(ActionIntent.start())
		await get_tree().process_frame
		snap = ClientSession.typed_snapshot()
	if snap.status() == Contract.STATUS_ACTIVE and str(snap.phase()) == Contract.PHASE_ACTION:
		_submit(ActionIntent.attack(0, 0))
		await get_tree().process_frame
		snap = ClientSession.typed_snapshot()
	_toast.text = ""
	_end_panel.visible = true
	_bind_server_exposure(ClientSession.typed_snapshot())
	if _exposure_doll:
		## High exposure so cover does not hide the leafy hood / shirt chrome.
		_exposure_doll.bind_server_pct(85.0)
		_exposure_doll.bind_equipped(ClientSession.equipped_cosmetic)
		_exposure_doll.custom_minimum_size = Vector2(96, 128)
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path("res://artifacts/ux/equip_exposure_doll.png")
	img.save_png(path)
	print("E6_EQUIP_DOLL ", path)
	get_tree().quit()


func _ensure_active_for_decoy() -> Snapshot:
	var snap: Snapshot = ClientSession.typed_snapshot()
	if snap.status() == Contract.STATUS_READY or snap.status() == Contract.STATUS_WAITING:
		_submit(ActionIntent.select_hex(2, 2))
		if ClientSession.dummy_player_id != "":
			_submit_as(ClientSession.dummy_player_id, ActionIntent.select_hex(7, 5))
		snap = ClientSession.typed_snapshot()
	if snap.status() == Contract.STATUS_READY:
		_submit(ActionIntent.start())
		snap = ClientSession.typed_snapshot()
	return snap


func _capture_decoy_hud() -> void:
	await get_tree().process_frame
	var snap := _ensure_active_for_decoy()
	_refresh(snap)
	_toast.text = ""
	_status.text = "Your action — Attack, Recon, UAV, or plant a Decoy."
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path("res://artifacts/ux/decoy_action_hud.png")
	img.save_png(path)
	print("D6_DECOY_HUD ", path)
	get_tree().quit()


func _capture_decoy_blip() -> void:
	await get_tree().process_frame
	var snap := _ensure_active_for_decoy()
	if snap.status() == Contract.STATUS_ACTIVE and str(snap.phase()) == Contract.PHASE_ACTION:
		_submit(ActionIntent.decoy())
		snap = ClientSession.typed_snapshot()
	_refresh(snap)
	_end_panel.visible = false
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path("res://artifacts/ux/decoy_dashed_blip.png")
	img.save_png(path)
	print("D6_DECOY_BLIP ", path)
	get_tree().quit()


func _force_pvp_end_for_capture() -> Snapshot:
	var snap: Snapshot = ClientSession.typed_snapshot()
	if snap.status() == Contract.STATUS_READY or snap.status() == Contract.STATUS_WAITING:
		_submit(ActionIntent.select_hex(2, 2))
		if ClientSession.dummy_player_id != "":
			_submit_as(ClientSession.dummy_player_id, ActionIntent.select_hex(7, 5))
			_dummy_placed = true
		snap = ClientSession.typed_snapshot()
	if snap.status() == Contract.STATUS_READY:
		_submit(ActionIntent.start())
		snap = ClientSession.typed_snapshot()
	if snap.status() == Contract.STATUS_ACTIVE and str(snap.phase()) == Contract.PHASE_ACTION:
		_submit(ActionIntent.attack(7, 5))
		snap = ClientSession.typed_snapshot()
	return snap


func _capture_rematch_ended() -> void:
	await get_tree().process_frame
	var snap := _force_pvp_end_for_capture()
	_refresh(snap)
	_toast.text = ""
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path("res://artifacts/ux/rematch_ended_cta.png")
	img.save_png(path)
	print("R6_REMATCH_ENDED ", path)
	get_tree().quit()


func _capture_rematch_ready() -> void:
	await get_tree().process_frame
	_force_pvp_end_for_capture()
	_on_play_again()
	await get_tree().process_frame
	var snap: Snapshot = ClientSession.typed_snapshot()
	if snap.status() == Contract.STATUS_READY:
		_submit(ActionIntent.select_hex(2, 2))
		if ClientSession.dummy_player_id != "":
			_submit_as(ClientSession.dummy_player_id, ActionIntent.select_hex(7, 5))
			_dummy_placed = true
		snap = ClientSession.typed_snapshot()
	_refresh(snap)
	_toast.text = "Fresh drop — same rival, new board."
	_over.visible = false
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path("res://artifacts/ux/rematch_ready_new_board.png")
	img.save_png(path)
	print("R6_REMATCH_READY ", path)
	get_tree().quit()


func _capture_a2_reconnect() -> void:
	await get_tree().process_frame
	if ClientSession.typed_snapshot().status() == Contract.STATUS_READY:
		_submit(ActionIntent.select_hex(2, 2))
		await get_tree().process_frame
	## Invent local terrain + "I hit" — reconnect must wipe both.
	var dirty: Dictionary = ClientSession.last_snapshot.duplicate(true)
	var rows: Array = dirty.get("terrain", [])
	if not (rows is Array):
		rows = []
	rows = rows.duplicate()
	rows.append({"q": 8, "r": 6, "type": "hard"})
	dirty["terrain"] = rows
	dirty["lastAction"] = {"type": "attack", "hit": true, "kill": true}
	ClientSession.last_snapshot = dirty
	_apply_server_reconnect()
	_end_panel.visible = true
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path("res://artifacts/ux/a2_reconnect_server_snapshot.png")
	img.save_png(path)
	print("A2_RECONNECT_CAPTURE ", path)
	get_tree().quit()


func _exit_tree() -> void:
	if MatchAPI.match_event.is_connected(_on_match_event):
		MatchAPI.match_event.disconnect(_on_match_event)
	MatchAPI.stop_events()


func _build() -> void:
	var desk := TextureRect.new()
	desk.texture = Chrome.make_wood_texture(320, 180)
	desk.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	desk.stretch_mode = TextureRect.STRETCH_SCALE
	desk.set_anchors_preset(PRESET_FULL_RECT)
	desk.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(desk)

	var wash := ColorRect.new()
	wash.color = Color(0.08, 0.04, 0.03, 0.28)
	wash.set_anchors_preset(PRESET_FULL_RECT)
	wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(wash)

	var top := ColorRect.new()
	top.color = Color(0.10, 0.06, 0.04, 0.88)
	top.set_anchors_and_offsets_preset(PRESET_TOP_WIDE)
	top.offset_bottom = 108
	add_child(top)

	_add_player_card(true)
	_add_player_card(false)

	var reticle := TextureRect.new()
	reticle.texture = Chrome.make_icon("attack", Color.WHITE, 28)
	reticle.position = Vector2(430, 18)
	reticle.size = Vector2(36, 36)
	reticle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(reticle)

	var title := Label.new()
	title.text = "SP JOB" if ClientSession.is_job() else "GLASSLINE"
	title.position = Vector2(0, 16)
	title.size = Vector2(1280, 40)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	Chrome.apply_label(title, 22, Color.WHITE, true)
	add_child(title)

	var clock := TextureRect.new()
	clock.texture = Chrome.make_icon("clock", Chrome.CREAM, 28)
	clock.position = Vector2(24, 118)
	clock.size = Vector2(24, 24)
	clock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(clock)
	var timer := Label.new()
	timer.text = "01:30"
	timer.position = Vector2(52, 118)
	timer.size = Vector2(120, 24)
	Chrome.apply_label(timer, 12, Chrome.CREAM, true)
	add_child(timer)

	_turn = Label.new()
	_turn.position = Vector2(0, 56)
	_turn.size = Vector2(1280, 22)
	_turn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	Chrome.apply_label(_turn, 10, Chrome.HIGH_GOLD, true)
	add_child(_turn)

	var legend := VBoxContainer.new()
	legend.position = Vector2(16, 168)
	legend.add_theme_constant_override("separation", 12)
	add_child(legend)
	_legend_row(legend, Chrome.OPEN, "OPEN")
	_legend_row(legend, Chrome.BRUSH, "BRUSH")
	_legend_row(legend, Chrome.HARD, "HARD")
	_legend_row(legend, Chrome.UNKNOWN, "UNKNOWN")

	_legend_hover = Label.new()
	_legend_hover.position = Vector2(16, 380)
	_legend_hover.size = Vector2(200, 80)
	_legend_hover.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	Chrome.apply_label(_legend_hover, 8, Chrome.CREAM, true)
	add_child(_legend_hover)

	var well := ColorRect.new()
	well.color = Color(0.07, 0.05, 0.04, 0.55)
	well.position = Vector2(210, 128)
	well.size = Vector2(860, 478)
	well.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(well)

	_board_host = Control.new()
	_board_host.position = Vector2(220, 132)
	_board_host.size = Vector2(840, 470)
	_board_host.mouse_filter = Control.MOUSE_FILTER_STOP
	_board_host.gui_input.connect(_on_board_input)
	add_child(_board_host)

	_board = HexBoard.new()
	_board_host.add_child(_board)
	_board.position = Vector2(420, 235)

	_status = Label.new()
	_status.position = Vector2(200, 82)
	_status.size = Vector2(880, 22)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	Chrome.apply_label(_status, 8, Color("f0e3b0"), true)
	add_child(_status)

	_phase = Label.new()
	_phase.position = Vector2(200, 100)
	_phase.size = Vector2(880, 18)
	_phase.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	Chrome.apply_label(_phase, 8, Chrome.TEAL, true)
	add_child(_phase)

	var bottom := ColorRect.new()
	bottom.color = Color(0.10, 0.06, 0.04, 0.90)
	bottom.set_anchors_and_offsets_preset(PRESET_BOTTOM_WIDE)
	bottom.offset_top = -108
	add_child(bottom)

	var row := HBoxContainer.new()
	row.position = Vector2(40, 624)
	row.size = Vector2(1200, 80)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	add_child(row)

	_btn_attack = Chrome.action_button("attack", "ATTACK", Chrome.ATTACK_RED, Color.WHITE, Vector2(200, 68))
	_btn_attack.pressed.connect(_on_attack)
	row.add_child(_btn_attack)
	_btn_recon = Chrome.action_button("recon", "RECON", Chrome.RECON_BLUE, Color.WHITE, Vector2(200, 68))
	_btn_recon.pressed.connect(_on_recon)
	row.add_child(_btn_recon)
	var uav_col := VBoxContainer.new()
	uav_col.alignment = BoxContainer.ALIGNMENT_CENTER
	uav_col.add_theme_constant_override("separation", 2)
	_ability_cap = Label.new()
	_ability_cap.text = Contract.ABILITY_SLOT
	_ability_cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	Chrome.apply_label(_ability_cap, 8, Chrome.HIGH_GOLD, true)
	uav_col.add_child(_ability_cap)
	_btn_uav = Chrome.action_button("ability", Contract.ABILITY_LABEL, Chrome.ABILITY_PURPLE, Color.WHITE, Vector2(200, 56))
	_btn_uav.tooltip_text = "Ability — UAV Sweep. Posts type: uav."
	_btn_uav.pressed.connect(_on_uav)
	uav_col.add_child(_btn_uav)
	row.add_child(uav_col)
	var decoy_col := VBoxContainer.new()
	decoy_col.alignment = BoxContainer.ALIGNMENT_CENTER
	decoy_col.add_theme_constant_override("separation", 2)
	_decoy_cap = Label.new()
	_decoy_cap.text = Contract.DECOY_SLOT
	_decoy_cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	Chrome.apply_label(_decoy_cap, 8, Chrome.HIGH_GOLD, true)
	decoy_col.add_child(_decoy_cap)
	_btn_decoy = Chrome.action_button("decoy", Contract.DECOY_LABEL, Chrome.DECOY_CARAMEL, Color.WHITE, Vector2(200, 56))
	_btn_decoy.tooltip_text = Contract.DECOY_COPY
	_btn_decoy.pressed.connect(_on_decoy)
	decoy_col.add_child(_btn_decoy)
	row.add_child(decoy_col)

	_btn_start = Chrome.chunk_button("START", Chrome.PLAY_GREEN, Color.WHITE, Vector2(160, 40))
	_btn_start.position = Vector2(1096, 64)
	_btn_start.pressed.connect(_on_start)
	add_child(_btn_start)

	_end_panel = PanelContainer.new()
	_end_panel.position = Vector2(430, 520)
	_end_panel.visible = false
	var end_box := Chrome.flat(Color(0.12, 0.09, 0.07, 0.95), 16, Color("f0e3b0"), 2)
	_end_panel.add_theme_stylebox_override("panel", end_box)
	add_child(_end_panel)
	var end_col := VBoxContainer.new()
	end_col.add_theme_constant_override("separation", 8)
	_end_panel.add_child(end_col)
	var end_title := Label.new()
	end_title.text = "END TURN"
	Chrome.apply_label(end_title, 10, Chrome.CREAM, true)
	end_col.add_child(end_title)
	var expose_row := HBoxContainer.new()
	expose_row.add_theme_constant_override("separation", 12)
	end_col.add_child(expose_row)
	_exposure_doll = ExposureDoll.new()
	_exposure_doll.custom_minimum_size = Vector2(88, 118)
	expose_row.add_child(_exposure_doll)
	var expose_col := VBoxContainer.new()
	expose_col.add_theme_constant_override("separation", 6)
	expose_row.add_child(expose_col)
	_exposure_lbl = Label.new()
	Chrome.apply_label(_exposure_lbl, 8, Chrome.HIGH_GOLD, true)
	expose_col.add_child(_exposure_lbl)
	_exposure = HSlider.new()
	_exposure.min_value = 0
	_exposure.max_value = 100
	_exposure.value = Contract.DEFAULT_EXPOSURE
	_exposure.custom_minimum_size = Vector2(280, 20)
	_exposure.value_changed.connect(func(v: float) -> void:
		_exposure_lbl.text = "NEXT  %d%%" % int(v)
	)
	expose_col.add_child(_exposure)
	_exposure_lbl.text = "NEXT  50%"
	_exposure_doll.bind_server_pct(Contract.DEFAULT_EXPOSURE)
	var move_hint := Label.new()
	move_hint.text = "Optional: click an adjacent hex to relocate"
	Chrome.apply_label(move_hint, 8, Chrome.CREAM)
	end_col.add_child(move_hint)
	_btn_end = Chrome.chunk_button("END TURN", Chrome.TEAL, Color.WHITE, Vector2(220, 44))
	_btn_end.pressed.connect(_on_end_turn)
	end_col.add_child(_btn_end)

	_toast = Label.new()
	_toast.position = Vector2(240, 580)
	_toast.size = Vector2(800, 28)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	Chrome.apply_label(_toast, 10, Color("f7e7a8"), true)
	add_child(_toast)

	_optic = preload("res://scenes/optic/optic_overlay.gd").new()
	_optic.set_anchors_preset(PRESET_FULL_RECT)
	add_child(_optic)
	_optic.fire_pressed.connect(_on_optic_fire)
	_optic.cancelled.connect(func() -> void: _aim = Aim.NONE)

	_over = ColorRect.new()
	_over.color = Color(0.05, 0.03, 0.02, 0.82)
	_over.set_anchors_preset(PRESET_FULL_RECT)
	_over.visible = false
	add_child(_over)
	var over_col := VBoxContainer.new()
	over_col.set_anchors_preset(PRESET_FULL_RECT)
	over_col.offset_left = 240
	over_col.offset_right = -240
	over_col.offset_top = 140
	over_col.offset_bottom = -80
	over_col.alignment = BoxContainer.ALIGNMENT_CENTER
	over_col.add_theme_constant_override("separation", 14)
	var plate := PanelContainer.new()
	plate.set_anchors_preset(PRESET_CENTER)
	plate.offset_left = -340
	plate.offset_right = 340
	plate.offset_top = -210
	plate.offset_bottom = 210
	var plate_box := Chrome.flat(Color(0.12, 0.08, 0.05, 0.96), 18, Chrome.HIGH_GOLD, 2)
	plate.add_theme_stylebox_override("panel", plate_box)
	_over.add_child(plate)
	over_col.set_anchors_preset(PRESET_FULL_RECT)
	over_col.offset_left = 24
	over_col.offset_right = -24
	over_col.offset_top = 16
	over_col.offset_bottom = -16
	over_col.alignment = BoxContainer.ALIGNMENT_CENTER
	over_col.add_theme_constant_override("separation", 12)
	plate.add_child(over_col)
	_over_lbl = Label.new()
	_over_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_over_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	Chrome.apply_label(_over_lbl, 18, Color.WHITE, true)
	over_col.add_child(_over_lbl)
	_over_settle = Label.new()
	_over_settle.text = Contract.REMATCH_SETTLED_COPY
	_over_settle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_over_settle.visible = false
	Chrome.apply_label(_over_settle, 10, Chrome.HIGH_GOLD, true)
	over_col.add_child(_over_settle)
	_over_hint = Label.new()
	_over_hint.text = Contract.REMATCH_HINT_COPY
	_over_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_over_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_over_hint.visible = false
	Chrome.apply_label(_over_hint, 10, Chrome.CREAM, true)
	over_col.add_child(_over_hint)
	_over_timer = Label.new()
	_over_timer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_over_timer.visible = false
	Chrome.apply_label(_over_timer, 10, Chrome.CREAM, true)
	over_col.add_child(_over_timer)
	var over_btns := HBoxContainer.new()
	over_btns.alignment = BoxContainer.ALIGNMENT_CENTER
	over_btns.add_theme_constant_override("separation", 16)
	over_col.add_child(over_btns)
	_btn_play_again = Chrome.chunk_button(Contract.REMATCH_PLAY_COPY, Chrome.PLAY_GREEN, Color.WHITE, Vector2(280, 56))
	_btn_play_again.pressed.connect(_on_play_again)
	over_btns.add_child(_btn_play_again)
	_btn_decline = Chrome.chunk_button(Contract.REMATCH_DECLINE_COPY, Chrome.WOOD, Chrome.CREAM, Vector2(220, 56))
	_btn_decline.pressed.connect(_on_rematch_decline)
	over_btns.add_child(_btn_decline)
	_btn_hideout = Chrome.chunk_button("HIDEOUT", Chrome.PLAY_GREEN, Color.WHITE, Vector2(240, 56))
	_btn_hideout.pressed.connect(_go_hideout)
	over_col.add_child(_btn_hideout)


func _add_player_card(is_you: bool) -> void:
	var card := ColorRect.new()
	card.color = Color(0.08, 0.05, 0.04, 0.72)
	card.size = Vector2(300, 72)
	if is_you:
		card.position = Vector2(16, 12)
	else:
		card.position = Vector2(1008, 12)
		card.size = Vector2(256, 72)
	add_child(card)

	var face := TextureRect.new()
	face.texture = Chrome.make_face("p1" if is_you else "p2", 44)
	face.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	face.position = card.position + Vector2(8, 14)
	face.size = Vector2(44, 44)
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(face)

	var tag := Label.new()
	tag.text = "P1" if is_you else "P2"
	tag.position = card.position + Vector2(60, 8)
	Chrome.apply_label(tag, 8, Chrome.HIGH_GOLD if is_you else Chrome.P2, true)
	add_child(tag)

	var chip := Label.new()
	chip.position = card.position + Vector2(60, 26)
	chip.size = Vector2(230, 42)
	chip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	Chrome.apply_label(chip, 10, Chrome.CREAM, true)
	add_child(chip)
	if is_you:
		_you_chip = chip
	else:
		_rival_chip = chip


func _legend_row(parent: VBoxContainer, color: Color, text: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.add_child(Chrome.hex_swatch(color, 22))
	var lbl := Label.new()
	lbl.text = text
	Chrome.apply_label(lbl, 8, Chrome.CREAM, true)
	row.add_child(lbl)
	parent.add_child(row)


func _on_match_event(player_id: String, _event_name: String, snapshot: Dictionary) -> void:
	if player_id != ClientSession.player_id:
		return
	ClientSession.apply_snapshot(snapshot)
	var snap: Snapshot = Snapshot.from_dict(snapshot)
	_bind_server_exposure(snap)
	_refresh(snap)


func _refresh(snap: Snapshot) -> void:
	_bind_server_exposure(snap)
	_board.apply_snapshot(snap, _selected, _highlights(snap))
	_you_chip.text = "%s  SEAT %s  %s" % [ClientSession.HANDLE, snap.you_seat().to_upper(), Chrome.marks_chip_text(snap.you_marks())]
	_rival_chip.text = "BOT" if ClientSession.is_job() or snap.is_job() else ClientSession.RIVAL
	_turn.text = "TURN  %d / %d" % [snap.turn_index(), snap.turn_cap()]
	var whose := str(snap.whose_turn()) if snap.whose_turn() != null else "-"
	var phase_txt := str(snap.phase()) if snap.phase() != null else "-"
	_phase.text = "STATUS %s   PHASE %s   TO %s" % [snap.status(), phase_txt, whose.to_upper()]

	match snap.status():
		Contract.STATUS_READY:
			_status.text = ""
			_phase.text = ""
			_toast.text = ""
			_btn_start.visible = snap.you_placed() and _dummy_placed
			_set_actions(false)
			_end_panel.visible = false
		Contract.STATUS_ACTIVE:
			_btn_start.visible = false
			var yours := snap.is_your_turn()
			if _dummy_delay > 0.0:
				_status.text = "Rival is lining up…  %.1fs" % _dummy_delay
				_set_actions(false)
				_end_panel.visible = false
			elif yours and str(snap.phase()) == Contract.PHASE_ACTION:
				_status.text = "Your action — Attack, Recon, %s, or plant a Decoy." % Contract.ABILITY_LABEL
				_set_actions(true)
				_end_panel.visible = false
			elif yours and str(snap.phase()) == Contract.PHASE_END_TURN:
				_status.text = "End turn — set exposure, optional adjacent move."
				_set_actions(false)
				_end_panel.visible = true
				_bind_server_exposure(snap)
			else:
				_status.text = "Rival is lining up…"
				_set_actions(false)
				_end_panel.visible = false
				_queue_dummy(snap)
		Contract.STATUS_ENDED:
			_btn_start.visible = false
			_set_actions(false)
			_end_panel.visible = false
			_show_ended(snap)
		_:
			_status.text = snap.status()

	var last: Variant = snap.last_action()
	if last is Dictionary and snap.status() != Contract.STATUS_READY:
		_toast.text = _describe_last(last)
	_btn_uav.disabled = _btn_uav.disabled or snap.uav_remaining() <= 0
	if snap.uav_remaining() <= 0:
		_btn_uav.text = "%s SPENT" % Contract.ABILITY_LABEL
	else:
		_btn_uav.text = Contract.ABILITY_LABEL
	_btn_decoy.disabled = _btn_decoy.disabled or not snap.decoy_available()
	if not snap.decoy_available():
		_btn_decoy.text = "%s SPENT" % Contract.DECOY_LABEL
	else:
		_btn_decoy.text = Contract.DECOY_LABEL


func _highlights(snap: Snapshot) -> Dictionary:
	var extra := {}
	if _relocate_hex != null:
		extra[Contract.hex_key(_relocate_hex)] = Color("7ec8e3")
	if snap.enemy_soft_hot() > 0 and snap.enemy_visible_hex() != null:
		extra[Contract.hex_key(snap.enemy_visible_hex())] = Color("f0a020")
	return extra


func _set_actions(on: bool) -> void:
	_btn_attack.disabled = not on
	_btn_recon.disabled = not on
	_btn_uav.disabled = not on
	_btn_decoy.disabled = not on


func _on_board_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var hex: Variant = _pick(event.position)
		_board.set_hover(hex)
		if hex != null:
			var snap: Snapshot = ClientSession.typed_snapshot()
			var key := "%d,%d" % [int(hex["q"]), int(hex["r"])]
			var kind := str(snap.terrain_map().get(key, "unknown"))
			_legend_hover.text = "Q%d R%d\n%s" % [int(hex["q"]), int(hex["r"]), kind.to_upper()]
	elif event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
			var hex: Variant = _pick(mouse.position)
			if hex != null:
				_handle_hex(int(hex["q"]), int(hex["r"]))


func _pick(local: Vector2) -> Variant:
	return _board.pick_local(local - _board.position)


func _handle_hex(q: int, r: int) -> void:
	var snap: Snapshot = ClientSession.typed_snapshot()
	if snap.status() == Contract.STATUS_READY:
		_submit(ActionIntent.select_hex(q, r))
		_maybe_dummy_drop(q, r)
		return
	if _aim == Aim.RELOCATE or (_end_panel.visible and _aim != Aim.ATTACK and _aim != Aim.RECON):
		_relocate_hex = Contract.hex_dict(q, r)
		_selected = _relocate_hex
		_toast.text = "Relocate queued Q%d R%d (must be adjacent)." % [q, r]
		_refresh(snap)
		return
	if _aim == Aim.RECON:
		_aim = Aim.NONE
		_submit(ActionIntent.recon(q, r))
		return
	if _aim == Aim.ATTACK:
		_selected = Contract.hex_dict(q, r)
		var kind := str(snap.terrain_map().get("%d,%d" % [q, r], "unknown"))
		var show_fig := Contract.same_hex(snap.enemy_visible_hex(), _selected)
		_optic.open_for(_selected, kind, show_fig)
		return
	_selected = Contract.hex_dict(q, r)
	_refresh(snap)


func _maybe_dummy_drop(_q: int, _r: int) -> void:
	if _dummy_placed or ClientSession.dummy_player_id == "":
		return
	get_tree().create_timer(0.35).timeout.connect(func() -> void:
		var you: Variant = ClientSession.typed_snapshot().you_hex()
		var dest := Vector2i(7, 5)
		if you is Dictionary:
			var best := dest
			var best_d := -1
			for qq in Contract.BOARD_Q:
				for rr in Contract.BOARD_R:
					var d := HexMath.distance(int(you["q"]), int(you["r"]), qq, rr)
					if d > best_d:
						best_d = d
						best = Vector2i(qq, rr)
			dest = best
		var dummy_result := _submit_as(ClientSession.dummy_player_id, ActionIntent.select_hex(dest.x, dest.y))
		if dummy_result.ok:
			_dummy_placed = true
			# Live auto-activates on the second drop; refetch the caller-scoped snapshot.
			var fresh: Dictionary = MatchAPI.get_snapshot(ClientSession.match_id, ClientSession.player_id)
			if not fresh.is_empty():
				ClientSession.apply_snapshot(fresh)
			_refresh(ClientSession.typed_snapshot())
	)


func _on_start() -> void:
	_submit(ActionIntent.start())


func _on_attack() -> void:
	_aim = Aim.ATTACK
	_toast.text = "ATTACK: click a hex, then FIRE in the optic. Server decides hit."


func _on_recon() -> void:
	_aim = Aim.RECON
	_toast.text = "RECON: click a sector center (hex + 6 neighbors)."


func _on_uav() -> void:
	_submit(ActionIntent.ability())


func _on_decoy() -> void:
	_submit(ActionIntent.decoy())


func _on_optic_fire() -> void:
	if _selected == null:
		return
	var q := int(_selected["q"])
	var r := int(_selected["r"])
	var result := _submit(ActionIntent.attack(q, r))
	if result != null and result.ok:
		var last: Variant = result.snapshot.get("lastAction", {})
		var hit := last is Dictionary and bool(last.get("hit", false))
		_optic.show_server_result("SERVER  HIT" if hit else "SERVER  MISS")
		if hit:
			get_tree().create_timer(0.9).timeout.connect(func() -> void: _optic.close())
		else:
			get_tree().create_timer(0.8).timeout.connect(func() -> void: _optic.close())
	_aim = Aim.NONE


func _on_end_turn() -> void:
	var body := ActionIntent.end_turn(_exposure.value, _relocate_hex)
	_relocate_hex = null
	_selected = null
	_dummy_delay = 1.4
	_dummy_busy = true
	_status.text = "Rival is lining up…  1.4s"
	_set_actions(false)
	_end_panel.visible = false
	_submit(body)


func _submit(action: Dictionary) -> ActionResult:
	return _submit_as(ClientSession.player_id, action)


func _submit_as(player_id: String, action: Dictionary) -> ActionResult:
	var result: ActionResult = MatchAPI.apply_action(ClientSession.match_id, player_id, action)
	if player_id == ClientSession.player_id:
		if result.ok:
			ClientSession.apply_snapshot(result.snapshot)
			_refresh(Snapshot.from_dict(result.snapshot))
		else:
			_toast.text = "REFUSED  %s" % result.error
	return result


func _process(delta: float) -> void:
	_tick_rematch(delta)
	if _dummy_delay <= 0.0:
		return
	_dummy_delay = maxf(0.0, _dummy_delay - delta)
	_status.text = "Rival is lining up…  %.1fs" % _dummy_delay
	if _dummy_delay <= 0.0:
		_dummy_step()


func _queue_dummy(snap: Snapshot) -> void:
	if ClientSession.dummy_player_id == "":
		return
	if _dummy_busy or _dummy_delay > 0.0:
		return
	if snap.status() != Contract.STATUS_ACTIVE:
		return
	if str(snap.whose_turn()) == snap.you_seat():
		return
	_dummy_busy = true
	_dummy_delay = 1.1
	_status.text = "Rival is lining up…  1.1s"
	_toast.text = "RivalSniper is taking the glass…"


func _dummy_step() -> void:
	var raw: Dictionary = MatchAPI.get_snapshot(ClientSession.match_id, ClientSession.dummy_player_id)
	if raw.is_empty():
		raw = ClientSession.last_snapshot
	var dummy_snap: Snapshot = Snapshot.from_dict(raw)
	if dummy_snap.status() != Contract.STATUS_ACTIVE or str(dummy_snap.whose_turn()) == ClientSession.seat:
		_dummy_busy = false
		_dummy_delay = 0.0
		return
	if str(dummy_snap.phase()) == Contract.PHASE_ACTION:
		_submit_as(ClientSession.dummy_player_id, ActionIntent.recon(4, 3))
		_dummy_delay = 0.9
		_status.text = "Rival is lining up…  0.9s"
	elif str(dummy_snap.phase()) == Contract.PHASE_END_TURN:
		_submit_as(ClientSession.dummy_player_id, ActionIntent.end_turn(Contract.DEFAULT_EXPOSURE))
		_dummy_busy = false
		_dummy_delay = 0.0


func _show_ended(snap: Snapshot) -> void:
	if _going_hideout or _rematch_busy:
		return
	if snap.rematch_ready():
		_enter_rematch(_ready_body_from_snap(snap))
		return
	if snap.rematch_leave():
		_go_hideout()
		return
	_over.visible = true
	_over_lbl.text = MarksPayout.end_overlay(snap.raw, snap.you_seat(), ClientSession.is_job() or snap.is_job())
	var offered := snap.rematch_offered()
	var you_waiting := offered and snap.rematch_you_accepted() and not snap.rematch_opponent_accepted()
	_over_settle.visible = offered
	_over_settle.text = Contract.REMATCH_SETTLED_COPY
	_over_hint.visible = offered
	_over_hint.text = Contract.REMATCH_WAIT_COPY if you_waiting else Contract.REMATCH_HINT_COPY
	_btn_play_again.visible = offered
	_btn_play_again.disabled = you_waiting
	_btn_decline.visible = offered
	_btn_hideout.visible = not offered
	_over_timer.visible = offered
	if offered and _rematch_left < 0.0:
		_rematch_left = float(Contract.REMATCH_TIMEOUT_SEC)
	if offered:
		_over_timer.text = Contract.REMATCH_TIMER_COPY % maxi(0, ceili(_rematch_left))


func _tick_rematch(delta: float) -> void:
	if not _over.visible or _rematch_left < 0.0 or _going_hideout:
		return
	_rematch_left = maxf(0.0, _rematch_left - delta)
	if _over_timer:
		_over_timer.text = Contract.REMATCH_TIMER_COPY % maxi(0, ceili(_rematch_left))
	if _rematch_left <= 0.0:
		_on_rematch_timeout()


func _on_play_again() -> void:
	if _rematch_busy or _going_hideout:
		return
	var body: Dictionary = MatchAPI.rematch(true)
	if str(body.get("error", "")) == Contract.REMATCH_ERR_UNAVAILABLE:
		_go_hideout()
		return
	## Editor dummy: rival accepts, then replay as you so LIVE returns your joinToken.
	if ClientSession.dummy_player_id != "":
		var rem: Variant = body.get("rematch", {})
		var st := str(body.get("status", ""))
		if st == "" and rem is Dictionary:
			st = str(rem.get("status", ""))
		if st != Contract.REMATCH_READY and st != Contract.REMATCH_DECLINED and st != Contract.REMATCH_EXPIRED:
			var dummy_body: Dictionary = MatchAPI.rematch_as(ClientSession.dummy_player_id, true)
			var dummy_join := str(dummy_body.get("joinToken", ""))
			if dummy_join != "":
				ClientSession.dummy_token = dummy_join
			body = MatchAPI.rematch(true)
	_apply_rematch_body(body)


func _on_rematch_decline() -> void:
	if _going_hideout:
		return
	MatchAPI.rematch(false)
	_go_hideout()


func _on_rematch_timeout() -> void:
	if _going_hideout:
		return
	var snap: Snapshot = ClientSession.typed_snapshot()
	if snap.rematch_ready():
		_enter_rematch(_ready_body_from_snap(snap))
		return
	MatchAPI.rematch(false)
	_go_hideout()


func _ready_body_from_snap(snap: Snapshot) -> Dictionary:
	## Poll/SSE only names newMatchId. `_enter_rematch` replays for joinToken.
	return {
		"status": Contract.REMATCH_READY,
		"rematch": snap.rematch(),
		"newMatchId": snap.rematch_new_match_id(),
		"matchId": snap.rematch_new_match_id(),
		"snapshot": snap.raw,
	}


func _ensure_ready_body(body: Dictionary) -> Dictionary:
	if str(body.get("joinToken", "")) != "":
		return body
	var rem: Variant = body.get("rematch", {})
	var st := str(body.get("status", ""))
	if st == "" and rem is Dictionary:
		st = str(rem.get("status", ""))
	var new_id := str(body.get("matchId", body.get("newMatchId", "")))
	if rem is Dictionary and new_id == "":
		new_id = str(rem.get("newMatchId", rem.get("matchId", "")))
	if st != Contract.REMATCH_READY or new_id == "":
		return body
	var replay: Dictionary = MatchAPI.rematch(true)
	if str(replay.get("joinToken", "")) != "" or str(replay.get("status", "")) == Contract.REMATCH_READY:
		return replay
	return body


func _apply_rematch_body(body: Dictionary) -> void:
	if body.is_empty():
		return
	var rem: Variant = body.get("rematch", {})
	if not (rem is Dictionary):
		rem = {}
	var st := str(body.get("status", rem.get("status", "")))
	if st == "200":
		st = str(rem.get("status", ""))
	var new_id := str(rem.get("newMatchId", body.get("newMatchId", body.get("matchId", ""))))
	if st == Contract.REMATCH_READY and new_id != "":
		_enter_rematch(body)
		return
	if st in [Contract.REMATCH_DECLINED, Contract.REMATCH_EXPIRED]:
		_go_hideout()
		return
	var snap_raw: Variant = body.get("snapshot", {})
	if snap_raw is Dictionary and not snap_raw.is_empty() \
			and str(snap_raw.get("status", "")) == Contract.STATUS_ENDED:
		ClientSession.apply_snapshot(snap_raw)
	_refresh(ClientSession.typed_snapshot())


func _enter_rematch(body: Dictionary) -> void:
	if _rematch_busy or _going_hideout:
		return
	_rematch_busy = true
	_over.visible = false
	_rematch_left = -1.0
	body = _ensure_ready_body(body)
	var snap_dict: Dictionary = MatchAPI.bind_new_match(body)
	_dummy_placed = false
	_dummy_busy = false
	_dummy_delay = 0.0
	_selected = null
	_aim = Aim.NONE
	_relocate_hex = null
	_rematch_busy = false
	if snap_dict.is_empty():
		_go_hideout()
		return
	_refresh(ClientSession.typed_snapshot())


func _go_hideout() -> void:
	if _going_hideout:
		return
	_going_hideout = true
	_over.visible = false
	_rematch_left = -1.0
	if get_tree() != null:
		get_tree().change_scene_to_file("res://scenes/lobby/hideout_lobby.tscn")


func _describe_last(last: Dictionary) -> String:
	var kind := str(last.get("type", ""))
	match kind:
		Contract.ACT_ATTACK:
			if bool(last.get("decoyCleared", false)):
				return "lastAction attack  hit=false  decoyCleared=true  (toy doll gone)"
			return "lastAction attack  hit=%s  (server)" % str(last.get("hit", false))
		Contract.ACT_RECON:
			var spotted: Variant = last.get("spotted", last.get("found", false))
			return "lastAction recon  spotted=%s  (server)" % str(spotted)
		Contract.ACT_REJECT:
			return "lastAction reject  %s" % str(last.get("reason", ""))
		Contract.ACT_UAV:
			return "lastAction uav  revealed=%s  (server)" % str(last.get("revealed", false))
		Contract.ACT_DECOY:
			var planted: Variant = last.get("hex", null)
			if planted is Dictionary:
				return "lastAction decoy  planted Q%d R%d  (toy doll · server)" % [
					int(planted.get("q", 0)),
					int(planted.get("r", 0)),
				]
			return "lastAction decoy  planted  (toy doll · server)"
		Contract.ACT_FORFEIT:
			return "lastAction forfeit  winner=%s  (server)" % str(last.get("winner", ""))
		Contract.ACT_END_TURN:
			return "lastAction end_turn  moved=%s" % str(last.get("moved", false))
		Contract.ACT_SELECT_HEX:
			return "lastAction select_hex  seat %s" % str(last.get("seat", ""))
		Contract.ACT_START:
			return "lastAction start — seat A shoots first"
		_:
			return ""
