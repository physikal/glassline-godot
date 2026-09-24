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
const FirstHuntCoach := preload("res://scenes/match/first_hunt_coach.gd")
const TerrainCoach := preload("res://scenes/match/terrain_coach.gd")
const ExposureFloorTip := preload("res://scenes/match/exposure_floor_tip.gd")

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
## Untouched NEXT baseline. Starts at the same 50 as the slider. A player drag
## above the floor sets _next_player_raised so a later snapshot does not snap it.
var _next_baseline: float = Contract.EXPOSURE_FLOOR_START
var _next_player_raised: bool = false
var _syncing_next: bool = false
var _btn_attack: Button
var _btn_recon: Button
var _btn_uav: Button
var _btn_smoke: Button
var _btn_decoy: Button
var _btn_high: Button
var _high_cap: Label
var _high_chip: Control
var _clock_chip: Label
var _turn_pill: PanelContainer
var _ability_cap: Label
var _decoy_cap: Label
var _decoy_tip: PanelContainer
var _btn_start: Button
var _btn_abandon: Button
var _btn_end: Button
var _clock_icon: TextureRect
var _grace_lbl: Label
var _over: ColorRect
var _over_lbl: Label
var _over_marks: Label
var _over_xp: Label
var _over_reason: Label
var _over_settle: Label
var _over_hint: Label
var _over_timer: Label
var _btn_play_again: Button
var _btn_decline: Button
var _btn_hideout: Button
var _you_chip: Label
var _rival_chip: Label
var _you_level: Label
var _rival_level: Label
## Locked plate parks RivalSniper at star 18. Snapshot has no enemy marks field.
const PLATE_RIVAL_STAR := 18
var _coach: FirstHuntCoach
var _terrain: TerrainCoach
var _floor_tip: ExposureFloorTip

var _aim: int = Aim.NONE
var _selected: Variant = null
var _dummy_placed: bool = false
var _dummy_busy: bool = false
var _dummy_delay: float = 0.0
var _relocate_hex: Variant = null
var _rematch_left: float = -1.0
var _grace_left: float = -1.0
var _rematch_busy: bool = false
var _abandon_busy: bool = false
var _going_hideout: bool = false
var _art_lock_end_panel: bool = false
var _plate_hud: bool = false
var _mute_btn: Button
var _practice_chip: Label


func _ready() -> void:
	set_anchors_preset(PRESET_FULL_RECT)
	set_process(true)
	_build()
	MatchAPI.match_event.connect(_on_match_event)
	if ClientSession.dummy_player_id == "" and (ClientSession.is_job() or ClientSession.is_practice()):
		_dummy_placed = true
	var args := OS.get_cmdline_user_args()
	if _cmdline_is_capture(args):
		## Plate stills stay clean. Terrain captures opt back in.
		TerrainCoach.suppressed = true
		ExposureFloorTip.suppressed = true
	_apply_server_reconnect()
	if "--capture-a1" in args:
		_capture_after_play()
	elif "--capture-a2" in args:
		_capture_a2_reconnect()
	elif "--capture-sp-end" in args:
		_capture_sp_end()
	elif "--capture-equip-doll" in args:
		_capture_equip_doll()
	elif "--capture-gun-equipped-optic" in args:
		_capture_gun_equipped_optic()
	elif "--capture-part-optic-feel" in args:
		_capture_part_optic_feel()
	elif "--capture-art-hex" in args:
		_capture_art_hex()
	elif "--capture-art-operative-doll" in args:
		_capture_art_operative_doll()
	elif "--capture-art-optic" in args:
		_capture_art_optic()
	elif "--capture-decoy-hud" in args:
		_capture_decoy_hud()
	elif "--capture-decoy-blip" in args:
		_capture_decoy_blip()
	elif "--capture-rematch-ended" in args:
		_capture_rematch_ended()
	elif "--capture-rematch-ready" in args:
		_capture_rematch_ready()
	elif "--capture-abandon-cta" in args:
		_capture_abandon_cta()
	elif "--capture-grace-countdown" in args:
		_capture_grace_countdown()
	elif "--capture-forfeit-overlay" in args:
		_capture_forfeit_overlay()
	elif "--capture-end-summary-kill" in args:
		_capture_end_summary_kill()
	elif "--capture-end-summary-forfeit" in args:
		_capture_end_summary_forfeit()
	elif "--capture-end-summary-standoff" in args:
		_capture_end_summary_standoff()
	elif "--capture-end-xp" in args:
		_capture_end_xp("grant")
	elif "--capture-end-xp-level" in args:
		_capture_end_xp("level")
	elif "--capture-end-xp-practice" in args:
		_capture_end_xp("practice")
	elif "--capture-coach-tips" in args:
		_capture_coach_tips()
	elif "--capture-coach-dismissed" in args:
		_capture_coach_dismissed()
	elif "--capture-coach-chip" in args:
		_capture_coach_chip()
	elif "--capture-coach-terrain-high" in args:
		_capture_coach_terrain_high()
	elif "--capture-coach-terrain-brush" in args:
		_capture_coach_terrain_brush()
	elif "--capture-queue-matched-board" in args:
		_capture_queue_matched_board()
	elif "--capture-high-ground-lit" in args:
		_capture_high_ground(true)
	elif "--capture-high-ground-muted" in args:
		_capture_high_ground(false)
	elif "--capture-brush-cover-toast" in args:
		_capture_brush_cover_toast()
	elif "--capture-practice-bot" in args:
		_capture_practice_bot()
	elif "--capture-exposure-floor-50" in args:
		_capture_exposure_floor("50")
	elif "--capture-exposure-floor-step" in args:
		_capture_exposure_floor("step")
	elif "--capture-exposure-floor-tip" in args:
		_capture_exposure_floor("tip")
	elif "--capture-smoke-available" in args:
		_capture_smoke("available")
	elif "--capture-smoke-spent" in args:
		_capture_smoke("spent")
	elif "--capture-smoke-active" in args:
		_capture_smoke("active")
	elif "--capture-smoke-locked" in args:
		_capture_smoke("locked")
	elif "--capture-smoke-lock-toast" in args:
		_capture_smoke("toast")
	elif "--capture-decoy-locked" in args:
		_capture_decoy_lock("locked")
	elif "--capture-decoy-unlocked" in args:
		_capture_decoy_lock("unlocked")
	elif "--capture-decoy-lock-toast" in args:
		_capture_decoy_lock("toast")
	elif "--capture-hud-punch" in args:
		_capture_hud_punch()
	elif "--capture-soft-hud" in args:
		_capture_soft_hud()


func _cmdline_is_capture(args: PackedStringArray) -> bool:
	for arg in args:
		if str(arg).begins_with("--capture-"):
			return true
	return false


func _capture_exposure_floor(kind: String) -> void:
	## Doll reads you.exposureFloor. Step + tip stills stamp the mock field.
	## The tip capture is the only one that un-suppresses the one-shot.
	if _coach:
		_coach.dismiss()
	_dummy_busy = true
	_dummy_delay = 0.0
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	await get_tree().process_frame
	if not ClientSession.use_live_api():
		MockMatchServer.test_omit_exposure_floor = false
		MockMatchServer.test_exposure_floor = null
	var snap: Snapshot = ClientSession.typed_snapshot()
	if snap.status() == Contract.STATUS_READY or snap.status() == Contract.STATUS_WAITING or snap.status() == "":
		_submit(ActionIntent.select_hex(2, 2))
		await get_tree().process_frame
		if ClientSession.dummy_player_id != "":
			MatchAPI.apply_action(ClientSession.match_id, ClientSession.dummy_player_id, ActionIntent.select_hex(7, 5))
			await get_tree().process_frame
		snap = ClientSession.typed_snapshot()
	if snap.status() == Contract.STATUS_READY:
		_submit(ActionIntent.start())
		await get_tree().process_frame
		snap = ClientSession.typed_snapshot()
	if snap.status() == Contract.STATUS_ACTIVE and str(snap.phase()) == Contract.PHASE_ACTION:
		_submit(ActionIntent.attack(0, 0))
		await get_tree().process_frame
		snap = ClientSession.typed_snapshot()
	if not ClientSession.use_live_api():
		if kind == "step" or kind == "tip":
			MockMatchServer.test_exposure_floor = 40
		else:
			MockMatchServer.test_exposure_floor = null
	if kind == "tip" and _floor_tip:
		ExposureFloorTip.suppressed = false
		ExposureFloorTip.clear_seen()
		ExposureFloorTip.set_latched(false)
		_floor_tip.seed_prior(Contract.EXPOSURE_FLOOR_START)
	_art_lock_end_panel = true
	_apply_server_reconnect()
	snap = ClientSession.typed_snapshot()
	_toast.text = ""
	_status.text = ""
	_phase.text = ""
	_set_actions(false)
	_end_panel.visible = true
	_end_panel.position = Vector2(240, 160)
	if _btn_decoy:
		_btn_decoy.visible = false
	if _btn_abandon:
		_btn_abandon.visible = false
	if _exposure_doll:
		_exposure_doll.custom_minimum_size = Vector2(220, 300)
		_exposure_doll.size = Vector2(220, 300)
		_exposure_doll.bind_floor(snap.you_exposure_floor())
	if _floor_tip:
		_floor_tip.bind_anchor(_exposure_doll)
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var file_name := "exposure_floor_50.png"
	var tag := "E3_FLOOR_50"
	if kind == "step":
		file_name = "exposure_floor_40.png"
		tag = "E3_FLOOR_40"
	elif kind == "tip":
		file_name = "exposure_floor_tip.png"
		tag = "E3_FLOOR_TIP"
	var path := ProjectSettings.globalize_path("res://artifacts/ux/%s" % file_name)
	img.save_png(path)
	var label := _exposure_doll.exposure_label() if _exposure_doll else ""
	var showing := _floor_tip.is_showing() if _floor_tip else false
	print("EXPOSURE_FLOOR_CAPTURE ", tag, " ", path, " LABEL ", label, " TIP ", showing, " FLOOR ", snap.you_exposure_floor())
	get_tree().quit()


func _capture_high_ground(lit: bool) -> void:
	## Mock toggle drives the chip. Client never invents from the local hex.
	TerrainCoach.suppressed = true
	if _coach:
		_coach.dismiss()
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	if not ClientSession.use_live_api():
		MockMatchServer.test_high_ground_active = lit
	await get_tree().process_frame
	var snap := _ensure_active_for_decoy()
	if ClientSession.match_id != "":
		_apply_server_reconnect()
		snap = ClientSession.typed_snapshot()
	_refresh(snap)
	_toast.text = ""
	_status.text = ""
	_phase.text = ""
	if _btn_decoy:
		_btn_decoy.visible = false
	if _btn_abandon:
		_btn_abandon.visible = false
	_set_actions(true)
	if _clock_chip:
		_clock_chip.text = "01:30"
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var name := "high_ground_lit_hard.png" if lit else "high_ground_muted_open.png"
	var path := ProjectSettings.globalize_path("res://artifacts/ux/%s" % name)
	img.save_png(path)
	print("HIGH_GROUND_%s " % ("LIT" if lit else "MUTED"), path)
	get_tree().quit()


func _capture_brush_cover_toast() -> void:
	## Optional still: occupy a BRUSH target and keep the server toast. No chip.
	TerrainCoach.suppressed = true
	if _coach:
		_coach.dismiss()
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	_dummy_busy = true
	_dummy_placed = true
	_dummy_delay = 0.0
	await get_tree().process_frame
	var snap := _setup_brush_cover_occupy()
	_refresh(snap)
	if _over:
		_over.visible = false
	if _btn_decoy:
		_btn_decoy.visible = false
	if _btn_abandon:
		_btn_abandon.visible = false
	_status.text = ""
	_phase.text = ""
	var last: Variant = snap.last_action()
	var line := Chrome.describe_attack_result(last if last is Dictionary else {})
	var plate := ColorRect.new()
	plate.color = Color("1a1410")
	plate.position = Vector2(200, 168)
	plate.size = Vector2(880, 52)
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.z_index = 20
	add_child(plate)
	if _toast:
		_toast.position = Vector2(210, 176)
		_toast.size = Vector2(860, 36)
		Chrome.apply_label(_toast, 12, Color("f7e7a8"), true)
		_toast.text = line
		_toast.z_index = 21
		_toast.move_to_front()
	print("BRUSH_COVER_TOAST_TEXT ", line)
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path("res://artifacts/ux/brush_cover_toast.png")
	img.save_png(path)
	print("BRUSH_COVER_TOAST ", path)
	get_tree().quit()


func _setup_brush_cover_occupy() -> Snapshot:
	## Mock: OPEN attacker vs BRUSH target. Display lastAction.coverApplied only.
	if ClientSession.use_live_api() or ClientSession.match_id == "":
		return _ensure_active_for_decoy()
	var mid := ClientSession.match_id
	var pid := ClientSession.player_id
	var dummy := ClientSession.dummy_player_id
	var open_hex: Dictionary = MockMatchServer.find_hex_of_type(mid, Contract.TYPE_OPEN)
	var brush_hex: Dictionary = MockMatchServer.find_hex_of_type(mid, Contract.TYPE_BRUSH)
	if open_hex.is_empty() or brush_hex.is_empty() or pid == "" or dummy == "":
		return _ensure_active_for_decoy()
	MockMatchServer.apply_action(mid, pid, ActionIntent.select_hex(int(open_hex.get("q", 0)), int(open_hex.get("r", 0))))
	MockMatchServer.apply_action(mid, dummy, ActionIntent.select_hex(int(brush_hex.get("q", 1)), int(brush_hex.get("r", 0))))
	MockMatchServer.apply_action(mid, pid, ActionIntent.start())
	var fired: ActionResult = MockMatchServer.apply_action(
		mid,
		pid,
		ActionIntent.attack(int(brush_hex.get("q", 1)), int(brush_hex.get("r", 0)))
	)
	if not fired.snapshot.is_empty():
		ClientSession.apply_snapshot(fired.snapshot)
	return ClientSession.typed_snapshot()


func _capture_queue_matched_board() -> void:
	if _coach:
		_coach.dismiss()
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path("res://artifacts/ux/queue_matched_board.png")
	img.save_png(path)
	print("Q2_QUEUE_MATCHED_BOARD ", path)
	get_tree().quit()


func _capture_after_play() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path("res://artifacts/a1-after-play.png")
	img.save_png(path)
	print("A1_AFTER_PLAY_CAPTURE ", path)
	get_tree().quit()


func _capture_art_operative_doll() -> void:
	## Match end-turn paper-doll — never a hideout inset.
	if _coach:
		_coach.dismiss()
	_dummy_busy = true
	_dummy_delay = 0.0
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	await get_tree().process_frame
	var snap: Snapshot = ClientSession.typed_snapshot()
	if snap.status() == Contract.STATUS_READY or snap.status() == Contract.STATUS_WAITING:
		_submit(ActionIntent.select_hex(2, 2))
		await get_tree().process_frame
		if ClientSession.dummy_player_id != "":
			MatchAPI.apply_action(ClientSession.match_id, ClientSession.dummy_player_id, ActionIntent.select_hex(7, 5))
			await get_tree().process_frame
		snap = ClientSession.typed_snapshot()
	if snap.status() == Contract.STATUS_READY:
		_submit(ActionIntent.start())
		await get_tree().process_frame
		snap = ClientSession.typed_snapshot()
	## Empty-hex miss → await_end_turn (same path as the headless loop).
	if snap.status() == Contract.STATUS_ACTIVE and str(snap.phase()) == Contract.PHASE_ACTION:
		_submit(ActionIntent.attack(0, 0))
		await get_tree().process_frame
		await get_tree().process_frame
		snap = ClientSession.typed_snapshot()
	_toast.text = ""
	_set_actions(false)
	_art_lock_end_panel = true
	_end_panel.visible = true
	_end_panel.position = Vector2(340, 200)
	if _exposure_doll:
		_exposure_doll.custom_minimum_size = Vector2(200, 292)
		_exposure_doll.size = Vector2(200, 292)
		_exposure_doll.bind_equipped(ClientSession.equipped_cosmetic)
		_exposure_doll.bind_server_pct(72.0)
	if _exposure_lbl:
		_exposure_lbl.text = "EXPOSURE  72%"
	if _exposure:
		_exposure.value = 72.0
	await get_tree().process_frame
	await get_tree().process_frame
	if _exposure_doll:
		_exposure_doll.bind_server_pct(72.0)
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path("res://artifacts/ux/04_operative_exposure_doll.png")
	img.save_png(path)
	print("ART_04_OPERATIVE_DOLL ", path)
	print("ART_04_PHASE ", str(snap.phase()), " STATUS ", snap.status())
	get_tree().quit()


func _capture_art_hex() -> void:
	## Match-board plate HUD + server-revealed stamps. Not a hideout / SaaS dock.
	if _coach:
		_coach.dismiss()
	_dummy_busy = true
	_dummy_delay = 0.0
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	await get_tree().process_frame
	var snap: Snapshot = ClientSession.typed_snapshot()
	if snap.status() == Contract.STATUS_READY or snap.status() == Contract.STATUS_WAITING:
		_submit(ActionIntent.select_hex(2, 2))
		await get_tree().process_frame
		if ClientSession.dummy_player_id != "":
			MatchAPI.apply_action(ClientSession.match_id, ClientSession.dummy_player_id, ActionIntent.select_hex(7, 5))
			await get_tree().process_frame
		snap = ClientSession.typed_snapshot()
	if snap.status() == Contract.STATUS_READY:
		_submit(ActionIntent.start())
		await get_tree().process_frame
	if not ClientSession.use_live_api() and ClientSession.match_id != "":
		MockMatchServer.reveal_inner_for_art(ClientSession.match_id)
		_apply_server_reconnect()
	_toast.text = ""
	_status.text = ""
	_phase.text = ""
	if _btn_decoy:
		_btn_decoy.visible = false
	if _btn_abandon:
		_btn_abandon.visible = false
	_set_actions(true)
	if _clock_chip:
		_clock_chip.text = "01:30"
	if _clock_icon:
		_clock_icon.visible = true
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path("res://artifacts/ux/03_hex_open_brush_hard_unknown.png")
	img.save_png(path)
	print("ART_03_HEX ", path)
	get_tree().quit()


func _capture_art_optic() -> void:
	if _coach:
		_coach.dismiss()
	await get_tree().process_frame
	_submit(ActionIntent.select_hex(2, 2))
	await get_tree().process_frame
	if ClientSession.dummy_player_id != "":
		MatchAPI.apply_action(ClientSession.match_id, ClientSession.dummy_player_id, ActionIntent.select_hex(7, 5))
		await get_tree().process_frame
	_submit(ActionIntent.start())
	await get_tree().process_frame
	_optic.open_for(Contract.hex_dict(4, 3), Contract.TYPE_BRUSH, true, ClientSession.equipped_gun_id())
	if _optic.has_method("pose_joystick_for_capture"):
		_optic.pose_joystick_for_capture()
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path("res://artifacts/ux/05_attack_optic_fieldbolt.png")
	img.save_png(path)
	var joy := ProjectSettings.globalize_path("res://artifacts/ux/05_attack_optic_joystick.png")
	img.save_png(joy)
	print("ART_05_ATTACK_OPTIC ", path)
	print("ART_05_ATTACK_JOYSTICK ", joy)
	get_tree().quit()


func _capture_gun_equipped_optic() -> void:
	## Equipped family stamp + visual-only copy on the locked optic plate.
	if _coach:
		_coach.dismiss()
	await get_tree().process_frame
	_submit(ActionIntent.select_hex(2, 2))
	await get_tree().process_frame
	if ClientSession.dummy_player_id != "":
		MatchAPI.apply_action(ClientSession.match_id, ClientSession.dummy_player_id, ActionIntent.select_hex(7, 5))
		await get_tree().process_frame
	_submit(ActionIntent.start())
	await get_tree().process_frame
	_optic.open_for(Contract.hex_dict(4, 3), Contract.TYPE_BRUSH, true, ClientSession.equipped_gun_id())
	if _optic.has_method("pose_joystick_for_capture"):
		_optic.pose_joystick_for_capture()
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path("res://artifacts/ux/gun_equipped_optic.png")
	img.save_png(path)
	print("GUN_EQUIPPED_OPTIC ", path)
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
	## Server exposurePct may still be the default 50. Do not treat that
	## assignment as a player raise — bind snaps a stale 50 down to the floor.
	if _exposure:
		_syncing_next = true
		_exposure.value = snap.you_exposure()
		## Server exposurePct is not a slider raise. A leftover 50 still snaps.
		_next_player_raised = false
		_syncing_next = false
	_bind_server_exposure(snap)
	_refresh(snap)
	return fresh


func _bind_high_ground(snap: Snapshot) -> void:
	## Chip truth is snapshot you.highGroundActive. Never local hex / terrain.
	## Smoke does not light this chip.
	if _high_chip:
		Chrome.paint_high_ground_chip(_high_chip, snap.you_high_ground_active())


func _bind_decoy(snap: Snapshot) -> void:
	## Lit only at operative L3 with a named charge. Locked stays on the wood plate and can toast.
	if _btn_decoy == null:
		return
	var chrome := snap.decoy_chrome()
	var lit := chrome == Contract.DECOY_CHROME_AVAILABLE
	var locked := chrome == Contract.DECOY_CHROME_LOCKED
	Chrome.paint_decoy_button(_btn_decoy, chrome)
	if locked:
		_btn_decoy.disabled = false
	elif not lit:
		_btn_decoy.disabled = true
	## Lock line is a tap toast. The legend and header do not keep a sticky tip.
	if _decoy_tip:
		_decoy_tip.visible = false
	if _decoy_cap:
		_decoy_cap.text = ""


func _show_decoy_lock_toast(snap: Snapshot) -> void:
	## Soft tip. Does not POST and does not spend the charge.
	_place_lock_toast(snap.decoy_lock_toast())


func _bind_smoke(snap: Snapshot) -> void:
	## Lit only at operative L5 with a named charge. Locked stays on the wood plate and can toast.
	if _btn_smoke == null:
		return
	var chrome := snap.smoke_chrome()
	var lit := chrome == Contract.SMOKE_CHROME_AVAILABLE
	var locked := chrome == Contract.SMOKE_CHROME_LOCKED
	Chrome.paint_smoke_chip(_btn_smoke, lit, locked)
	if locked:
		_btn_smoke.disabled = false
		_btn_smoke.tooltip_text = Contract.SMOKE_LOCKED_TOAST
	elif lit:
		_btn_smoke.tooltip_text = Contract.SMOKE_COPY
	elif chrome == Contract.SMOKE_CHROME_SPENT:
		_btn_smoke.disabled = true
		_btn_smoke.tooltip_text = Contract.SMOKE_SPENT_COPY
	else:
		_btn_smoke.disabled = true
		_btn_smoke.tooltip_text = Contract.SMOKE_ABSENT_COPY
	_apply_smoke_toast(snap)


func _show_smoke_lock_toast(snap: Snapshot) -> void:
	## Soft tip. Does not POST and does not spend the charge.
	_place_lock_toast(snap.smoke_lock_toast())


func _apply_smoke_toast(snap: Snapshot) -> void:
	if _toast == null:
		return
	if snap.smoke_active():
		_toast.text = Contract.SMOKE_TOAST
		_toast.position = Vector2(180, 48)
		_toast.size = Vector2(920, 36)
		_toast.z_index = 45
		_toast.z_as_relative = false
		return
	_toast.position = Vector2(160, 688)
	_toast.size = Vector2(960, 28)
	_toast.z_index = 0


func _bind_doll_parts(snap: Snapshot) -> void:
	if _exposure_doll == null or not _exposure_doll.has_method("bind_parts"):
		return
	var optic := snap.you_equipped_optic_id() if snap.you().has("equippedOpticId") else ClientSession.equipped_optic_id()
	var stock := snap.you_equipped_stock_id() if snap.you().has("equippedStockId") else ClientSession.equipped_stock_id()
	var barrel := snap.you_equipped_barrel_id() if snap.you().has("equippedBarrelId") else ClientSession.equipped_barrel_id()
	_exposure_doll.bind_parts(optic, stock, barrel)


func _capture_part_optic_feel() -> void:
	## Optic lengthens the glass bar. Stock/barrel quiet the figure. Hit stays server-side.
	if _coach:
		_coach.dismiss()
	await get_tree().process_frame
	_submit(ActionIntent.select_hex(2, 2))
	await get_tree().process_frame
	if ClientSession.dummy_player_id != "":
		MatchAPI.apply_action(ClientSession.match_id, ClientSession.dummy_player_id, ActionIntent.select_hex(7, 5))
		await get_tree().process_frame
	_submit(ActionIntent.start())
	await get_tree().process_frame
	_optic.open_for(Contract.hex_dict(4, 3), Contract.TYPE_BRUSH, true, ClientSession.equipped_gun_id())
	if _optic.has_method("pose_feel_for_capture"):
		_optic.pose_feel_for_capture()
	if _optic.has_method("pose_joystick_for_capture"):
		_optic.pose_joystick_for_capture()
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path("res://artifacts/ux/part_optic_feel.png")
	img.save_png(path)
	print("PART_OPTIC_FEEL ", path)
	get_tree().quit()


func _bind_server_exposure(snap: Snapshot) -> void:
	## Doll % is server you.exposureFloor. Missing field fail-closes to 50.
	## NEXT label + slider use that same floor as baseline and minimum.
	## A stale default of 50 snaps down when the floor is lower. A player
	## raise stays inside the band. The slider never writes the floor.
	## Chrome wash is you.equippedSkinId (shop snapshot cache if match omits it).
	var floor := snap.you_exposure_floor()
	if _exposure_doll:
		_exposure_doll.bind_floor(floor)
		var skin := snap.you_equipped_skin_id()
		if skin == "" and not snap.you().has("equippedSkinId") and not snap.you().has("equipped"):
			skin = ClientSession.equipped_cosmetic
		_exposure_doll.bind_equipped(skin)
		_bind_doll_parts(snap)
	if _exposure:
		var snapped: Dictionary = Contract.snap_next_exposure(
			floor, float(_exposure.value), _next_baseline, _next_player_raised
		)
		_next_baseline = float(snapped["baseline"])
		_next_player_raised = bool(snapped["player_raised"])
		var shown := float(snapped["value"])
		_syncing_next = true
		_exposure.min_value = float(snapped["min"])
		if not is_equal_approx(float(_exposure.value), shown):
			_exposure.value = shown
		_syncing_next = false
		if _exposure_lbl:
			_exposure_lbl.text = "NEXT  %d%%" % int(shown)
	if _floor_tip:
		_floor_tip.observe(floor)


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


func _capture_smoke(kind: String) -> void:
	## Stills: lit chip, muted spent chip, active toast, locked wood, lock toast.
	if _coach:
		_coach.dismiss()
	_dummy_busy = true
	_dummy_delay = 0.0
	if kind == "locked" or kind == "toast":
		MockMatchServer.operative_level = Contract.SMOKE_UNLOCK_LEVEL - 1
	else:
		MockMatchServer.operative_level = Contract.SMOKE_UNLOCK_LEVEL
	MockMatchServer.test_omit_operative_level = false
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	await get_tree().process_frame
	var snap := _smoke_drop_open()
	if kind == "active" or kind == "spent":
		if snap.status() == Contract.STATUS_ACTIVE and str(snap.phase()) == Contract.PHASE_ACTION and snap.smoke_available():
			_submit(ActionIntent.smoke())
			snap = ClientSession.typed_snapshot()
	if kind == "spent":
		## Decoy clock: enemy end_turn keeps the puff. The caster's next end_turn clears it.
		if str(snap.phase()) == Contract.PHASE_END_TURN and str(snap.whose_turn()) == ClientSession.seat:
			_submit_as(ClientSession.player_id, ActionIntent.end_turn(Contract.DEFAULT_EXPOSURE))
			snap = ClientSession.typed_snapshot()
		var dummy := ClientSession.dummy_player_id
		if dummy != "":
			var draw: Dictionary = MatchAPI.get_snapshot(ClientSession.match_id, dummy)
			var dsnap: Snapshot = Snapshot.from_dict(draw)
			if str(dsnap.phase()) == Contract.PHASE_ACTION:
				var miss := _smoke_miss_hex(dsnap.you_hex(), snap.you_hex())
				_submit_as(dummy, ActionIntent.attack(int(miss["q"]), int(miss["r"])))
				draw = MatchAPI.get_snapshot(ClientSession.match_id, dummy)
				dsnap = Snapshot.from_dict(draw)
			if str(dsnap.phase()) == Contract.PHASE_END_TURN:
				_submit_as(dummy, ActionIntent.end_turn(Contract.DEFAULT_EXPOSURE))
			var fresh: Dictionary = MatchAPI.get_snapshot(ClientSession.match_id, ClientSession.player_id)
			if not fresh.is_empty():
				ClientSession.apply_snapshot(fresh)
			snap = ClientSession.typed_snapshot()
		if snap.smoke_active() and str(snap.whose_turn()) == ClientSession.seat:
			if str(snap.phase()) == Contract.PHASE_ACTION:
				var mine := _smoke_miss_hex(snap.you_hex(), null)
				_submit(ActionIntent.attack(int(mine["q"]), int(mine["r"])))
				snap = ClientSession.typed_snapshot()
			if str(snap.phase()) == Contract.PHASE_END_TURN:
				_submit(ActionIntent.end_turn(Contract.DEFAULT_EXPOSURE))
				snap = ClientSession.typed_snapshot()
	_dummy_busy = true
	_dummy_delay = 0.0
	_refresh(snap)
	_end_panel.visible = false
	_btn_start.visible = false
	if _btn_decoy:
		_btn_decoy.visible = false
	if _decoy_tip:
		_decoy_tip.visible = false
	if _btn_abandon:
		_btn_abandon.visible = false
	_set_actions(kind != "active")
	_bind_smoke(snap)
	_status.text = ""
	_phase.text = ""
	if kind == "active":
		_toast.text = Contract.SMOKE_TOAST
		_toast.position = Vector2(180, 48)
		_toast.size = Vector2(920, 36)
		_toast.z_index = 45
		_toast.z_as_relative = false
		Chrome.apply_label(_toast, 16, Color("f7e7a8"), true)
	elif kind == "toast":
		_show_smoke_lock_toast(snap)
	else:
		_toast.text = ""
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var file_name := "smoke_chip_available.png"
	var tag := "SMOKE_AVAILABLE"
	if kind == "spent":
		file_name = "smoke_chip_spent.png"
		tag = "SMOKE_SPENT"
	elif kind == "active":
		file_name = "smoke_active_toast.png"
		tag = "SMOKE_ACTIVE"
	elif kind == "locked":
		file_name = "smoke_chip_locked.png"
		tag = "SMOKE_LOCKED"
	elif kind == "toast":
		file_name = "smoke_lock_toast.png"
		tag = "SMOKE_LOCK_TOAST"
	var path := ProjectSettings.globalize_path("res://artifacts/ux/%s" % file_name)
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	var lit := bool(_btn_smoke.get_meta("smoke_lit")) if _btn_smoke and _btn_smoke.has_meta("smoke_lit") else false
	var locked := bool(_btn_smoke.get_meta("smoke_locked")) if _btn_smoke and _btn_smoke.has_meta("smoke_locked") else false
	print("SMOKE_CAPTURE ", tag, " ", path, " LIT ", lit, " LOCKED ", locked, " CHROME ", snap.smoke_chrome(), " ACTIVE ", snap.smoke_active(), " AVAIL ", snap.smoke_available(), " LEVEL ", snap.operative_level(), " HG ", snap.you_high_ground_active())
	get_tree().quit()


func _smoke_miss_hex(a: Variant, b: Variant) -> Dictionary:
	for q in Contract.BOARD_Q:
		for r in Contract.BOARD_R:
			var cand := Contract.hex_dict(q, r)
			if a != null and Contract.same_hex(cand, a):
				continue
			if b != null and Contract.same_hex(cand, b):
				continue
			return cand
	return Contract.hex_dict(0, 0)


func _smoke_drop_open() -> Snapshot:
	## OPEN footing so the still cannot be read as a HIGH GROUND chip.
	var snap: Snapshot = ClientSession.typed_snapshot()
	if ClientSession.use_live_api() or ClientSession.match_id == "":
		return _ensure_active_for_decoy()
	var open_a: Dictionary = MockMatchServer.find_hex_of_type(ClientSession.match_id, Contract.TYPE_OPEN)
	var skip: Variant = open_a if not open_a.is_empty() else null
	var open_b: Dictionary = MockMatchServer.find_hex_of_type(ClientSession.match_id, Contract.TYPE_OPEN, skip)
	var aq := int(open_a.get("q", 2))
	var ar := int(open_a.get("r", 2))
	var bq := int(open_b.get("q", 7))
	var br := int(open_b.get("r", 5))
	if Contract.same_hex(Contract.hex_dict(aq, ar), Contract.hex_dict(bq, br)):
		bq = 7
		br = 5
	if snap.status() == Contract.STATUS_READY or snap.status() == Contract.STATUS_WAITING or snap.status() == "":
		_submit(ActionIntent.select_hex(aq, ar))
		if ClientSession.dummy_player_id != "":
			_submit_as(ClientSession.dummy_player_id, ActionIntent.select_hex(bq, br))
		snap = ClientSession.typed_snapshot()
	if snap.status() == Contract.STATUS_READY:
		_submit(ActionIntent.start())
		snap = ClientSession.typed_snapshot()
	return snap


func _capture_hud_punch() -> void:
	## H1–H4 stills. Layout only: rail, toast, board, legend.
	if _coach:
		_coach.dismiss()
	_dummy_busy = true
	_dummy_delay = 0.0
	MockMatchServer.operative_level = Contract.SMOKE_UNLOCK_LEVEL
	MockMatchServer.test_omit_operative_level = false
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	await get_tree().process_frame
	## FoW honeycomb — unrevealed 9×7, before the punch reveals inner stamps.
	_refresh(ClientSession.typed_snapshot())
	_end_panel.visible = false
	_btn_start.visible = false
	if _btn_abandon:
		_btn_abandon.visible = false
	_status.text = ""
	_phase.text = ""
	_toast.text = ""
	## Unrevealed board, keys at full weight so the floating ink reads.
	_set_actions(true)
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_save_hud_png("res://artifacts/ux/hud_board_full.png", "BOARD_FULL")
	var snap := _smoke_drop_open()
	_refresh(snap)
	_end_panel.visible = false
	_btn_start.visible = false
	if _btn_abandon:
		_btn_abandon.visible = false
	_status.text = ""
	_phase.text = ""
	_toast.text = ""
	_set_actions(true)
	_bind_decoy(snap)
	_bind_smoke(snap)
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_save_hud_png("res://artifacts/ux/hud_h1_ability_rail.png", "H1_RAIL")
	var h1 := get_viewport().get_texture().get_image()
	var rail_band := h1.get_region(Rect2i(0, 530, 1280, 190))
	rail_band.save_png(ProjectSettings.globalize_path("res://artifacts/ux/hud_ability_rail.png"))
	print("HUD_RAIL ", ProjectSettings.globalize_path("res://artifacts/ux/hud_ability_rail.png"))
	var full := get_viewport().get_texture().get_image()
	var board := full.get_region(Rect2i(240, 110, 980, 470))
	var legend := full.get_region(Rect2i(0, 148, 210, 200))
	board.save_png(ProjectSettings.globalize_path("res://artifacts/ux/hud_h3_board.png"))
	legend.save_png(ProjectSettings.globalize_path("res://artifacts/ux/hud_h4_legend.png"))
	print("H3_BOARD ", ProjectSettings.globalize_path("res://artifacts/ux/hud_h3_board.png"))
	print("H4_LEGEND ", ProjectSettings.globalize_path("res://artifacts/ux/hud_h4_legend.png"))
	MockMatchServer.operative_level = Contract.DECOY_UNLOCK_LEVEL - 1
	var fresh: Dictionary = MatchAPI.get_snapshot(ClientSession.match_id, ClientSession.player_id)
	if not fresh.is_empty():
		ClientSession.apply_snapshot(fresh)
	snap = ClientSession.typed_snapshot()
	_refresh(snap)
	_end_panel.visible = false
	_btn_start.visible = false
	_status.text = ""
	_phase.text = ""
	_set_actions(true)
	_bind_decoy(snap)
	_bind_smoke(snap)
	_show_decoy_lock_toast(snap)
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_save_hud_png("res://artifacts/ux/hud_h2_lock_toast.png", "H2_TOAST")
	_save_hud_png("res://artifacts/ux/hud_lock_toast.png", "LOCK_TOAST")
	print("HUD_PUNCH LEVEL ", snap.operative_level(), " DECOY ", snap.decoy_chrome(), " SMOKE ", snap.smoke_chrome(), " TOAST ", _toast.text if _toast else "", " TOAST_Y ", _toast.position.y if _toast else -1)
	get_tree().quit()


func _capture_soft_hud() -> void:
	## Revealed OPEN / BRUSH / HARD interior. UNKNOWN stays on the rim.
	if _coach:
		_coach.dismiss()
	_dummy_busy = true
	_dummy_delay = 0.0
	MockMatchServer.operative_level = Contract.SMOKE_UNLOCK_LEVEL
	MockMatchServer.test_omit_operative_level = false
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	await get_tree().process_frame
	var snap: Snapshot = ClientSession.typed_snapshot()
	if snap.status() == Contract.STATUS_READY or snap.status() == Contract.STATUS_WAITING or snap.status() == "":
		_submit(ActionIntent.select_hex(2, 2))
		await get_tree().process_frame
		if ClientSession.dummy_player_id != "":
			MatchAPI.apply_action(ClientSession.match_id, ClientSession.dummy_player_id, ActionIntent.select_hex(6, 4))
			await get_tree().process_frame
		snap = ClientSession.typed_snapshot()
	if snap.status() == Contract.STATUS_READY:
		_submit(ActionIntent.start())
		await get_tree().process_frame
	if not ClientSession.use_live_api() and ClientSession.match_id != "":
		## Locked frame is the lit chip (+10% ACCURACY). Parked copy stays the live default.
		MockMatchServer.test_high_ground_active = true
		MockMatchServer.reveal_inner_for_art(ClientSession.match_id)
		_apply_server_reconnect()
	snap = ClientSession.typed_snapshot()
	_refresh(snap)
	_end_panel.visible = false
	_btn_start.visible = false
	if _btn_abandon:
		_btn_abandon.visible = false
	_status.text = ""
	_phase.text = ""
	_toast.text = ""
	if _legend_hover:
		_legend_hover.text = ""
	if _clock_chip:
		_clock_chip.text = "01:30"
	if _turn:
		_turn.text = "TURN  1"
	_set_actions(true)
	_bind_decoy(snap)
	_bind_smoke(snap)
	_bind_high_ground(snap)
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var root := "res://artifacts/ux/soft_hud_dialect"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(root))
	_save_hud_png(root + "/full_plate.png", "SOFT_FULL")
	var full := get_viewport().get_texture().get_image()
	full.get_region(Rect2i(0, 0, 1280, 130)).save_png(ProjectSettings.globalize_path(root + "/top_chrome.png"))
	full.get_region(Rect2i(0, 96, 220, 280)).save_png(ProjectSettings.globalize_path(root + "/legend_timer.png"))
	full.get_region(Rect2i(200, 100, 900, 480)).save_png(ProjectSettings.globalize_path(root + "/board_full.png"))
	full.get_region(Rect2i(0, 540, 1280, 180)).save_png(ProjectSettings.globalize_path(root + "/ability_rail.png"))
	full.get_region(Rect2i(900, 540, 380, 180)).save_png(ProjectSettings.globalize_path(root + "/high_ground.png"))
	full.get_region(Rect2i(1100, 180, 180, 200)).save_png(ProjectSettings.globalize_path(root + "/table_corner.png"))
	var counts := {"open": 0, "brush": 0, "hard": 0, "unknown": 0}
	for cell in snap.terrain():
		var kind := str(cell.get("type", "unknown"))
		if counts.has(kind):
			counts[kind] = int(counts[kind]) + 1
		else:
			counts["unknown"] = int(counts["unknown"]) + 1
	var revealed := int(counts["open"]) + int(counts["brush"]) + int(counts["hard"])
	print("SOFT_HUD_TERRAIN open ", counts["open"], " brush ", counts["brush"], " hard ", counts["hard"], " listed ", revealed, " hg ", snap.you_high_ground_active())
	print("SOFT_HUD_STILLS ", ProjectSettings.globalize_path(root))
	get_tree().quit()


func _save_hud_png(res_path: String, tag: String) -> void:
	var img := get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path(res_path)
	img.save_png(path)
	print("HUD_PUNCH ", tag, " ", path)


func _capture_decoy_lock(kind: String) -> void:
	## Stills: locked L2 chip, unlocked L3, and the toast (not a header plate).
	if _coach:
		_coach.dismiss()
	_dummy_busy = true
	_dummy_delay = 0.0
	if kind == "unlocked":
		MockMatchServer.operative_level = Contract.DECOY_UNLOCK_LEVEL
	else:
		MockMatchServer.operative_level = Contract.DECOY_UNLOCK_LEVEL - 1
	MockMatchServer.test_omit_operative_level = false
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	await get_tree().process_frame
	var snap := _ensure_active_for_decoy()
	_dummy_busy = true
	_dummy_delay = 0.0
	_refresh(snap)
	_end_panel.visible = false
	_btn_start.visible = false
	if _btn_abandon:
		_btn_abandon.visible = false
	_set_actions(true)
	_bind_decoy(snap)
	_status.text = ""
	_phase.text = ""
	if kind == "toast":
		_show_decoy_lock_toast(snap)
	else:
		_toast.text = ""
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var file_name := "decoy_chip_unlocked.png"
	var tag := "DECOY_UNLOCKED"
	if kind == "locked":
		file_name = "decoy_chip_locked.png"
		tag = "DECOY_LOCKED"
	elif kind == "toast":
		file_name = "decoy_lock_toast.png"
		tag = "DECOY_LOCK_TOAST"
	var path := ProjectSettings.globalize_path("res://artifacts/ux/%s" % file_name)
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	var lit := bool(_btn_decoy.get_meta("decoy_lit")) if _btn_decoy and _btn_decoy.has_meta("decoy_lit") else false
	var locked := bool(_btn_decoy.get_meta("decoy_locked")) if _btn_decoy and _btn_decoy.has_meta("decoy_locked") else false
	var tip := _decoy_cap.text if _decoy_cap else ""
	print("DECOY_CAPTURE ", tag, " ", path, " LIT ", lit, " LOCKED ", locked, " TIP ", tip, " CHROME ", snap.decoy_chrome(), " AVAIL ", snap.decoy_available(), " LEVEL ", snap.operative_level(), " TOAST ", _toast.text if _toast else "")
	get_tree().quit()


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


func _force_pvp_active_for_capture() -> Snapshot:
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
	return snap


func _capture_abandon_cta() -> void:
	await get_tree().process_frame
	var snap := _force_pvp_active_for_capture()
	_refresh(snap)
	_toast.text = ""
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path("res://artifacts/ux/abandon_cta.png")
	img.save_png(path)
	print("A41_ABANDON_CTA ", path)
	get_tree().quit()


func _capture_grace_countdown() -> void:
	await get_tree().process_frame
	var snap := _force_pvp_active_for_capture()
	if ClientSession.dummy_player_id != "":
		MockMatchServer.start_grace(ClientSession.match_id, ClientSession.dummy_player_id, 23.0)
		var fresh: Dictionary = MatchAPI.get_snapshot(ClientSession.match_id, ClientSession.player_id)
		if not fresh.is_empty():
			ClientSession.apply_snapshot(fresh)
			snap = Snapshot.from_dict(fresh)
	_refresh(snap)
	_toast.text = ""
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path("res://artifacts/ux/grace_countdown.png")
	img.save_png(path)
	print("A43_GRACE_COUNTDOWN ", path)
	get_tree().quit()


func _capture_forfeit_overlay() -> void:
	await get_tree().process_frame
	_force_pvp_active_for_capture()
	## Remaining seat wins: dummy leaves → you +15, rematch chrome, no mil-sim.
	if ClientSession.dummy_player_id != "":
		var body: Dictionary = MatchAPI.abandon_as(ClientSession.dummy_player_id)
		var snap_raw: Variant = body.get("snapshot", {})
		if snap_raw is Dictionary and not snap_raw.is_empty():
			## Caller-scoped: refetch your seat so rematch + payout are yours.
			var yours: Dictionary = MatchAPI.get_snapshot(ClientSession.match_id, ClientSession.player_id)
			if yours.is_empty():
				yours = snap_raw
			ClientSession.apply_snapshot(yours)
	_refresh(ClientSession.typed_snapshot())
	_toast.text = ""
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path("res://artifacts/ux/forfeit_overlay.png")
	img.save_png(path)
	print("A44_FORFEIT_OVERLAY ", path)
	get_tree().quit()


func _capture_end_summary_png(path: String, tag: String) -> void:
	_toast.text = ""
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var out := ProjectSettings.globalize_path(path)
	img.save_png(out)
	print("%s %s" % [tag, out])
	get_tree().quit()


func _capture_end_summary_kill() -> void:
	await get_tree().process_frame
	var snap := _force_pvp_end_for_capture()
	_refresh(snap)
	await _capture_end_summary_png("res://artifacts/ux/end_summary_kill.png", "M1_END_SUMMARY_KILL")


func _capture_end_summary_forfeit() -> void:
	await get_tree().process_frame
	_force_pvp_active_for_capture()
	if ClientSession.dummy_player_id != "":
		MatchAPI.abandon_as(ClientSession.dummy_player_id)
		var yours: Dictionary = MatchAPI.get_snapshot(ClientSession.match_id, ClientSession.player_id)
		if not yours.is_empty():
			ClientSession.apply_snapshot(yours)
	_refresh(ClientSession.typed_snapshot())
	await _capture_end_summary_png("res://artifacts/ux/end_summary_forfeit.png", "M1_END_SUMMARY_FORFEIT")


func _prep_coach_capture() -> Snapshot:
	TerrainCoach.suppressed = true
	FirstHuntCoach.clear_seen()
	var snap := _force_pvp_active_for_capture()
	_refresh(snap)
	_toast.text = ""
	if _coach:
		_coach.present(false, snap.status() == Contract.STATUS_ACTIVE)
	return snap


func _capture_coach_png(path: String, tag: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var out := ProjectSettings.globalize_path(path)
	img.save_png(out)
	print("%s %s" % [tag, out])
	get_tree().quit()


func _capture_coach_tips() -> void:
	await get_tree().process_frame
	_prep_coach_capture()
	await _capture_coach_png("res://artifacts/ux/coach_tips_first_match.png", "C6_COACH_TIPS")


func _capture_coach_dismissed() -> void:
	await get_tree().process_frame
	var snap := _prep_coach_capture()
	if _coach:
		_coach.dismiss()
	_refresh(snap)
	_toast.text = ""
	await _capture_coach_png("res://artifacts/ux/coach_dismissed.png", "C3_COACH_DISMISSED")


func _capture_coach_chip() -> void:
	await get_tree().process_frame
	_prep_coach_capture()
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var out := ProjectSettings.globalize_path("res://artifacts/ux/coach_chip_closeup.png")
	if _coach:
		var r := _coach.chip_global_rect("attack")
		if r.size.x > 8.0 and r.size.y > 8.0:
			var pad := 12
			var region := Rect2i(
				maxi(0, int(r.position.x) - pad),
				maxi(0, int(r.position.y) - pad),
				int(r.size.x) + pad * 2,
				int(r.size.y) + pad * 2
			)
			region = region.intersection(Rect2i(Vector2i.ZERO, img.get_size()))
			if region.size.x > 0 and region.size.y > 0:
				img = img.get_region(region)
	img.save_png(out)
	print("C6_COACH_CHIP %s" % out)
	get_tree().quit()


func _capture_coach_terrain_high() -> void:
	## Hard hex lights the HIGH GROUND coach chip. Board stays live.
	TerrainCoach.suppressed = false
	TerrainCoach.clear_seen()
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	if not ClientSession.use_live_api():
		MockMatchServer.test_high_ground_active = true
	await get_tree().process_frame
	var snap := _ensure_active_for_decoy()
	if ClientSession.match_id != "":
		_apply_server_reconnect()
		snap = ClientSession.typed_snapshot()
	if _coach:
		_coach.dismiss()
	_refresh(snap)
	_toast.text = ""
	_status.text = ""
	_phase.text = ""
	if _btn_decoy:
		_btn_decoy.visible = false
	if _btn_abandon:
		_btn_abandon.visible = false
	_set_actions(true)
	if _clock_chip:
		_clock_chip.text = "01:30"
	await _capture_coach_png("res://artifacts/ux/coach_terrain_high.png", "CT_HIGH")


func _capture_coach_terrain_brush() -> void:
	## Leafy cover toast language on the BRUSH chip. No cover badge.
	TerrainCoach.suppressed = false
	TerrainCoach.clear_seen()
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	_dummy_busy = true
	_dummy_placed = true
	_dummy_delay = 0.0
	await get_tree().process_frame
	var snap := _setup_brush_cover_occupy()
	if _coach:
		_coach.dismiss()
	_refresh(snap)
	if _over:
		_over.visible = false
	if _btn_decoy:
		_btn_decoy.visible = false
	if _btn_abandon:
		_btn_abandon.visible = false
	_status.text = ""
	_phase.text = ""
	_toast.text = ""
	await _capture_coach_png("res://artifacts/ux/coach_terrain_brush.png", "CT_BRUSH")


func _capture_end_summary_standoff() -> void:
	await get_tree().process_frame
	_force_pvp_active_for_capture()
	var body: Dictionary = MockMatchServer.force_standoff(ClientSession.match_id, ClientSession.player_id)
	var snap_raw: Variant = body.get("snapshot", {})
	if snap_raw is Dictionary and not snap_raw.is_empty():
		ClientSession.apply_snapshot(snap_raw)
	_refresh(ClientSession.typed_snapshot())
	await _capture_end_summary_png("res://artifacts/ux/end_summary_standoff.png", "M1_END_SUMMARY_STANDOFF")


func _stamp_capture_xp(total: int, level: int) -> void:
	## Ended you.xp / operativeLevel for the still. The mock does not grant XP.
	if ClientSession.use_live_api():
		return
	MockMatchServer.account_xp = total
	MockMatchServer.operative_level = level
	MockMatchServer.test_omit_xp = false
	MockMatchServer.test_omit_operative_level = false


func _force_practice_end_for_capture() -> Snapshot:
	## Toy spy sits at (6, 1). Occupy that hex and the practice hunt ends Δ0.
	var snap: Snapshot = ClientSession.typed_snapshot()
	if snap.status() == Contract.STATUS_READY or snap.status() == Contract.STATUS_WAITING:
		_submit(ActionIntent.select_hex(2, 2))
		snap = ClientSession.typed_snapshot()
	if snap.status() == Contract.STATUS_READY:
		_submit(ActionIntent.start())
		snap = ClientSession.typed_snapshot()
	if snap.status() == Contract.STATUS_ACTIVE and str(snap.phase()) == Contract.PHASE_ACTION:
		_submit(ActionIntent.attack(6, 1))
		snap = ClientSession.typed_snapshot()
	return snap


func _capture_end_xp(kind: String) -> void:
	## PvP grant, level-up, or practice omit. XP line is under the Marks Δ.
	await get_tree().process_frame
	if _coach:
		_coach.dismiss()
	var path := "res://artifacts/ux/end_xp_pvp.png"
	var tag := "END_XP_PVP"
	if kind == "level":
		_stamp_capture_xp(100, 2)
		path = "res://artifacts/ux/end_xp_level.png"
		tag = "END_XP_LEVEL"
		_refresh(_force_pvp_end_for_capture())
	elif kind == "practice":
		_stamp_capture_xp(40, 1)
		path = "res://artifacts/ux/end_xp_practice.png"
		tag = "END_XP_PRACTICE"
		_refresh(_force_practice_end_for_capture())
	else:
		## Forfeit win +50 from a total that stays on L1 (70 = 20 + 50).
		_stamp_capture_xp(70, 1)
		_force_pvp_active_for_capture()
		if ClientSession.dummy_player_id != "":
			MatchAPI.abandon_as(ClientSession.dummy_player_id)
			var yours: Dictionary = MatchAPI.get_snapshot(ClientSession.match_id, ClientSession.player_id)
			if not yours.is_empty():
				ClientSession.apply_snapshot(yours)
		_refresh(ClientSession.typed_snapshot())
	if _coach:
		_coach.dismiss()
	_toast.text = ""
	var painted := _over_xp.text if _over_xp else ""
	print("END_XP_LINE ", tag, " ", painted)
	await _capture_end_summary_png(path, tag)


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
	var Art := preload("res://scripts/art_pack.gd")
	var plate_tex: Texture2D = Art.match_board_plate()
	_plate_hud = plate_tex != null
	if not _plate_hud:
		push_warning("match-board plate missing; floating HUD still draws")
	## Desk only. The baked jpg is the wood-tray dialect (header bar, inset
	## legend, button tray). Do not blit it — chrome is floating plates.
	var desk := TextureRect.new()
	desk.texture = Chrome.make_match_desk(1280, 720)
	desk.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	desk.stretch_mode = TextureRect.STRETCH_SCALE
	desk.set_anchors_preset(PRESET_FULL_RECT)
	desk.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(desk)

	_add_float_player_card(true)
	_add_float_player_card(false)
	## Ring sits behind the word. The word is the header, centered, not a left logo.
	var reticle := TextureRect.new()
	reticle.texture = Chrome.make_wordmark_ring(168)
	reticle.position = Vector2(556, 0)
	reticle.size = Vector2(168, 168)
	reticle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	reticle.z_index = 3
	add_child(reticle)
	var title := Label.new()
	if ClientSession.is_practice():
		title.text = "PRACTICE"
	elif ClientSession.is_job():
		title.text = "SP JOB"
	else:
		title.text = "Glassline"
	var title_bold := Label.new()
	title_bold.text = title.text
	title_bold.position = Vector2(342, 18)
	title_bold.size = Vector2(600, 64)
	title_bold.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_bold.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_bold.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_bold.z_index = 6
	Chrome.apply_label(title_bold, 32, Color.WHITE, true)
	title_bold.add_theme_constant_override("outline_size", 0)
	add_child(title_bold)
	var title_shadow := Label.new()
	title_shadow.text = title.text
	title_shadow.position = Vector2(344, 22)
	title_shadow.size = Vector2(600, 64)
	title_shadow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_shadow.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_shadow.z_index = 5
	Chrome.apply_label(title_shadow, 32, Color("0c0a08"), true)
	title_shadow.add_theme_constant_override("outline_size", 0)
	add_child(title_shadow)
	title.position = Vector2(340, 18)
	title.size = Vector2(600, 64)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.z_index = 6
	Chrome.apply_label(title, 32, Color.WHITE, true)
	title.add_theme_constant_override("outline_size", 3)
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	add_child(title)

	var clock_plate := PanelContainer.new()
	clock_plate.position = Vector2(8, 104)
	clock_plate.size = Vector2(176, 52)
	clock_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clock_plate.z_index = 5
	_paint_tight_plate(clock_plate, Color("16120e"), 14, 5, 10, 6)
	add_child(clock_plate)
	var clock_row := HBoxContainer.new()
	clock_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clock_row.alignment = BoxContainer.ALIGNMENT_CENTER
	clock_row.add_theme_constant_override("separation", 8)
	clock_plate.add_child(clock_row)
	_clock_icon = TextureRect.new()
	_clock_icon.texture = Chrome.make_icon("clock", Color("5ee7f5"), 34)
	_clock_icon.custom_minimum_size = Vector2(34, 34)
	_clock_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_clock_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_clock_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clock_row.add_child(_clock_icon)
	_clock_chip = Label.new()
	_clock_chip.text = "01:30"
	_clock_chip.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	Chrome.apply_label(_clock_chip, 14, Chrome.CREAM, true)
	clock_row.add_child(_clock_chip)
	_grace_lbl = Label.new()
	_grace_lbl.text = ""
	_grace_lbl.position = Vector2(52, 132)
	_grace_lbl.size = Vector2(560, 24)
	Chrome.apply_label(_grace_lbl, 10, Chrome.HIGH_GOLD, true)
	_grace_lbl.visible = false
	add_child(_grace_lbl)

	_btn_abandon = Chrome.chunk_button(Contract.ABANDON_COPY, Chrome.WOOD, Chrome.CREAM, Vector2(200, 40))
	_btn_abandon.position = Vector2(1056, 88)
	_btn_abandon.tooltip_text = "Leave the hunt. Rival keeps the Marks table (+%d / %d)." % [Contract.MARKS_FORFEIT_WIN, Contract.MARKS_FORFEIT_LOSS]
	_btn_abandon.pressed.connect(_on_abandon)
	_btn_abandon.visible = false
	add_child(_btn_abandon)

	_turn_pill = PanelContainer.new()
	_turn_pill.position = Vector2(556, 104)
	_turn_pill.size = Vector2(168, 34)
	_turn_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_turn_pill.z_index = 5
	_paint_tight_plate(_turn_pill, Color("16120e"), 12, 4, 8, 4)
	add_child(_turn_pill)
	_turn = Label.new()
	_turn.text = "TURN  1"
	_turn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_turn.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	Chrome.apply_label(_turn, 10, Chrome.CREAM, true)
	_turn_pill.add_child(_turn)

	_mount_float_legend()

	_legend_hover = Label.new()
	_legend_hover.position = Vector2(16, 420)
	_legend_hover.size = Vector2(210, 64)
	_legend_hover.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	Chrome.apply_label(_legend_hover, 8, Chrome.CREAM, true)
	add_child(_legend_hover)

	_board_host = Control.new()
	## Center hex sits in the host. Top points land under the header.
	## Same seat as the cleared 9×7 — do not shove the grid into a tray.
	_board_host.position = Vector2(250, 124)
	_board_host.size = Vector2(940, 436)
	_board_host.mouse_filter = Control.MOUSE_FILTER_STOP
	_board_host.gui_input.connect(_on_board_input)
	add_child(_board_host)

	_board = HexBoard.new()
	_board_host.add_child(_board)
	_board.position = Vector2(_board_host.size.x * 0.5, _board_host.size.y * 0.5)

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

	_btn_attack = Chrome.game_button("attack", "ATTACK", Chrome.ATTACK_RED, Color.WHITE, Vector2(224, 92))
	_btn_attack.position = Vector2(12, 584)
	_btn_attack.z_index = 4
	_btn_attack.pressed.connect(_on_attack)
	add_child(_btn_attack)
	_btn_recon = Chrome.game_button("recon", "RECON", Chrome.RECON_BLUE, Color.WHITE, Vector2(224, 92))
	_btn_recon.position = Vector2(248, 584)
	_btn_recon.z_index = 4
	_btn_recon.pressed.connect(_on_recon)
	add_child(_btn_recon)
	## Soft rail stays UAV / DECOY / SMOKE under ABILITY. No wood-tray mat.
	_mount_ability_rail(self, true)
	_high_chip = Chrome.high_ground_chip(false)
	_high_chip.position = Vector2(928, 568)
	_high_chip.size = Vector2(300, 112)
	_high_chip.z_index = 4
	add_child(_high_chip)
	_btn_high = Button.new()
	_btn_high.visible = false
	_btn_high.disabled = true
	add_child(_btn_high)
	_high_cap = Label.new()
	_high_cap.visible = false
	add_child(_high_cap)
	## Ability chips are mounted in _mount_ability_rail. No free-float keys.

	## Soft P2: rematch-ready START is a centered drop cue, not tucked under P2.
	_btn_start = Chrome.chunk_button("START", Chrome.PLAY_GREEN, Color.WHITE, Vector2(320, 56))
	_btn_start.position = Vector2(480, 508)
	_btn_start.pressed.connect(_on_start)
	add_child(_btn_start)

	_end_panel = PanelContainer.new()
	_end_panel.position = Vector2(380, 430)
	_end_panel.visible = false
	## HexBoard Sprite2D faces use z_index 1–2; keep END TURN chrome above the table.
	_end_panel.z_index = 40
	_end_panel.z_as_relative = false
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
	_exposure_doll.custom_minimum_size = Vector2(176, 168)
	expose_row.add_child(_exposure_doll)
	var expose_col := VBoxContainer.new()
	expose_col.add_theme_constant_override("separation", 6)
	expose_row.add_child(expose_col)
	_exposure_lbl = Label.new()
	Chrome.apply_label(_exposure_lbl, 8, Chrome.HIGH_GOLD, true)
	expose_col.add_child(_exposure_lbl)
	_exposure = HSlider.new()
	_exposure.min_value = Contract.EXPOSURE_FLOOR_START
	_exposure.max_value = 100
	_exposure.value = Contract.EXPOSURE_FLOOR_START
	_exposure.custom_minimum_size = Vector2(280, 20)
	_exposure.value_changed.connect(func(v: float) -> void:
		_exposure_lbl.text = "NEXT  %d%%" % int(v)
		if _syncing_next:
			return
		## A drag above the live floor is the player's raise. Back on the
		## floor, NEXT tracks the server baseline again.
		if v > float(_exposure.min_value) + 0.01:
			_next_player_raised = true
		else:
			_next_player_raised = false
			_next_baseline = float(v)
	)
	expose_col.add_child(_exposure)
	_exposure_lbl.text = "NEXT  50%"
	_exposure_doll.bind_floor(Contract.EXPOSURE_FLOOR_START)
	var move_hint := Label.new()
	move_hint.text = "Optional: click an adjacent hex to relocate"
	Chrome.apply_label(move_hint, 8, Chrome.CREAM)
	end_col.add_child(move_hint)
	_btn_end = Chrome.chunk_button("END TURN", Chrome.TEAL, Color.WHITE, Vector2(220, 44))
	_btn_end.pressed.connect(_on_end_turn)
	end_col.add_child(_btn_end)

	_toast = Label.new()
	_toast.position = Vector2(160, 688)
	_toast.size = Vector2(960, 28)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	Chrome.apply_label(_toast, 10, Color("f7e7a8"), true)
	add_child(_toast)
	_mute_btn = Chrome.gear_button(AudioJuice.muted)
	_mute_btn.position = Vector2(1216, 16)
	_mute_btn.z_index = 7
	_mute_btn.tooltip_text = Chrome.mute_button_tip(AudioJuice.muted)
	_mute_btn.pressed.connect(_toggle_mute)
	add_child(_mute_btn)

	_practice_chip = Label.new()
	_practice_chip.text = Contract.PRACTICE_CHIP
	_practice_chip.position = Vector2(360, 8)
	_practice_chip.size = Vector2(560, 28)
	_practice_chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_practice_chip.z_index = 30
	_practice_chip.visible = false
	Chrome.apply_label(_practice_chip, 10, Chrome.HIGH_GOLD, true)
	add_child(_practice_chip)

	_coach = FirstHuntCoach.new()
	_coach.set_anchors_preset(PRESET_FULL_RECT)
	_coach.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_coach.bind_anchors(_btn_attack, _btn_recon, _btn_decoy, _exposure_doll)
	add_child(_coach)

	_terrain = TerrainCoach.new()
	_terrain.set_anchors_preset(PRESET_FULL_RECT)
	_terrain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	## Above the end plate so a brush tip on a killing shot can still be dismissed.
	_terrain.z_index = 40
	add_child(_terrain)

	_floor_tip = ExposureFloorTip.new()
	_floor_tip.set_anchors_preset(PRESET_FULL_RECT)
	_floor_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	## Above the end plate so GOT IT can be tapped. Under the forfeit plate (z 50).
	_floor_tip.z_index = 42
	_floor_tip.z_as_relative = false
	_floor_tip.bind_anchor(_exposure_doll)
	add_child(_floor_tip)

	_optic = preload("res://scenes/optic/optic_overlay.gd").new()
	_optic.set_anchors_preset(PRESET_FULL_RECT)
	add_child(_optic)
	_optic.fire_pressed.connect(_on_optic_fire)
	_optic.cancelled.connect(func() -> void: _aim = Aim.NONE)

	_over = ColorRect.new()
	_over.color = Color(0.05, 0.03, 0.02, 0.82)
	_over.set_anchors_preset(PRESET_FULL_RECT)
	_over.visible = false
	## Hex faces sit at z 1–2. End-match wood (forfeit / kill / standoff) must paint above the board.
	_over.z_index = 50
	_over.z_as_relative = false
	add_child(_over)
	var plate := PanelContainer.new()
	plate.set_anchors_preset(PRESET_CENTER)
	plate.offset_left = -360
	plate.offset_right = 360
	plate.offset_top = -230
	plate.offset_bottom = 230
	var plate_box := Chrome.flat(Color(0.12, 0.08, 0.05, 0.96), 20, Chrome.HIGH_GOLD, 3)
	plate_box.content_margin_left = 28
	plate_box.content_margin_right = 28
	plate_box.content_margin_top = 22
	plate_box.content_margin_bottom = 22
	plate.add_theme_stylebox_override("panel", plate_box)
	_over.add_child(plate)
	var over_col := VBoxContainer.new()
	over_col.alignment = BoxContainer.ALIGNMENT_CENTER
	over_col.add_theme_constant_override("separation", 10)
	plate.add_child(over_col)
	_over_lbl = Label.new()
	_over_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_over_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	Chrome.apply_label(_over_lbl, 18, Color.WHITE, true)
	over_col.add_child(_over_lbl)
	_over_marks = Label.new()
	_over_marks.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	Chrome.apply_label(_over_marks, 14, Chrome.HIGH_GOLD, true)
	over_col.add_child(_over_marks)
	_over_xp = Label.new()
	_over_xp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_over_xp.visible = false
	Chrome.apply_label(_over_xp, 13, Chrome.XP_GREEN, true)
	over_col.add_child(_over_xp)
	_over_reason = Label.new()
	_over_reason.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	Chrome.apply_label(_over_reason, 10, Chrome.CREAM, true)
	over_col.add_child(_over_reason)
	_over_settle = Label.new()
	_over_settle.text = Contract.REMATCH_SETTLED_COPY
	_over_settle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_over_settle.visible = false
	Chrome.apply_label(_over_settle, 11, Chrome.HIGH_GOLD, true)
	over_col.add_child(_over_settle)
	_over_hint = Label.new()
	_over_hint.text = Contract.REMATCH_HINT_COPY
	_over_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_over_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_over_hint.visible = false
	Chrome.apply_label(_over_hint, 11, Chrome.CREAM, true)
	over_col.add_child(_over_hint)
	_over_timer = Label.new()
	_over_timer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_over_timer.visible = false
	Chrome.apply_label(_over_timer, 11, Chrome.CREAM, true)
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


func _mount_ability_rail(parent: Control, plate: bool) -> void:
	## One rail under the ABILITY label. UAV / DECOY / SMOKE never free-float.
	var rail := VBoxContainer.new()
	rail.name = "AbilityRail"
	rail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rail.add_theme_constant_override("separation", 2)
	rail.alignment = BoxContainer.ALIGNMENT_CENTER
	if plate:
		## Sits in the gap between RECON and HIGH GROUND. Chip row matches ATTACK height.
		rail.position = Vector2(484, 564)
		rail.custom_minimum_size = Vector2(432, 120)
		rail.size = Vector2(432, 120)
		rail.z_index = 4
	else:
		rail.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		rail.custom_minimum_size = Vector2(300, 88)
	parent.add_child(rail)
	_ability_cap = Label.new()
	_ability_cap.text = Contract.ABILITY_SLOT
	_ability_cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ability_cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	Chrome.apply_label(_ability_cap, 12, Chrome.CREAM, true)
	rail.add_child(_ability_cap)
	var chips := HBoxContainer.new()
	chips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chips.alignment = BoxContainer.ALIGNMENT_CENTER
	chips.add_theme_constant_override("separation", 8)
	rail.add_child(chips)
	_btn_uav = Chrome.rail_chip("ability", Contract.ABILITY_LABEL, Chrome.ABILITY_PURPLE, Color.WHITE)
	_btn_uav.tooltip_text = "Ability — UAV Sweep. Posts type: uav."
	_btn_uav.pressed.connect(_on_uav)
	chips.add_child(_btn_uav)
	_btn_decoy = Chrome.rail_chip("decoy", Contract.DECOY_LABEL, Chrome.DECOY_CARAMEL, Color.WHITE)
	_btn_decoy.tooltip_text = Contract.DECOY_COPY
	_btn_decoy.pressed.connect(_on_decoy)
	chips.add_child(_btn_decoy)
	_btn_smoke = Chrome.rail_chip("smoke", Contract.SMOKE_LABEL, Chrome.ABILITY_PURPLE, Color.WHITE)
	_btn_smoke.pressed.connect(_on_smoke)
	chips.add_child(_btn_smoke)


func _place_lock_toast(line: String) -> void:
	## Toast band under the action row. Never sticky under the player plate.
	if _toast == null:
		return
	_toast.text = line
	_toast.position = Vector2(160, 688)
	_toast.size = Vector2(960, 28)
	_toast.z_index = 46
	_toast.z_as_relative = false
	Chrome.apply_label(_toast, 11, Color("f7e7a8"), true)


func _legend_row(parent: VBoxContainer, kind: String, text: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var stamp := TextureRect.new()
	stamp.texture = Chrome.hex_legend_tex(kind)
	stamp.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	stamp.custom_minimum_size = Vector2(34, 32)
	stamp.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stamp.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	stamp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(stamp)
	var lbl := Label.new()
	lbl.text = text
	Chrome.apply_label(lbl, 10, Chrome.CREAM, true)
	row.add_child(lbl)
	parent.add_child(row)


func _paint_tight_plate(panel: Control, bg: Color, radius: int, border_px: int, margin_h: int, margin_v: int) -> void:
	var sz := panel.size
	if sz.x < 8.0:
		sz = panel.custom_minimum_size
	var box := Chrome.float_box(bg, radius, border_px, sz)
	box.content_margin_left = margin_h
	box.content_margin_right = margin_h
	box.content_margin_top = margin_v
	box.content_margin_bottom = margin_v
	panel.add_theme_stylebox_override("panel", box)


func _mount_float_legend() -> void:
	## Slim dark plate over the desk. Names only — not the wood-tray subtitle column.
	var plate := PanelContainer.new()
	plate.position = Vector2(8, 156)
	plate.size = Vector2(188, 196)
	plate.custom_minimum_size = plate.size
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.z_index = 4
	_paint_tight_plate(plate, Color("16120e"), 14, 5, 10, 8)
	add_child(plate)
	var legend := VBoxContainer.new()
	legend.add_theme_constant_override("separation", 4)
	legend.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_child(legend)
	_legend_row(legend, Contract.TYPE_OPEN, "OPEN")
	_legend_row(legend, Contract.TYPE_BRUSH, "BRUSH")
	_legend_row(legend, Contract.TYPE_HARD, "HARD")
	_legend_row(legend, "unknown", "UNKNOWN")


func _add_float_player_card(is_you: bool) -> void:
	var panel := PanelContainer.new()
	panel.position = Vector2(8, 8) if is_you else Vector2(948, 8)
	panel.size = Vector2(300, 92)
	panel.custom_minimum_size = panel.size
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.z_index = 5
	_paint_tight_plate(panel, Color("16120e"), 14, 6, 8, 6)
	add_child(panel)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	panel.add_child(row)
	var face := TextureRect.new()
	face.texture = Chrome.make_plate_portrait("p1" if is_you else "p2", 64)
	face.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	face.custom_minimum_size = Vector2(64, 64)
	face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 3)
	var chip := Label.new()
	chip.custom_minimum_size = Vector2(160, 22)
	chip.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if not is_you:
		chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	Chrome.apply_label(chip, 12, Chrome.CREAM, true)
	col.add_child(chip)
	var star_row := HBoxContainer.new()
	star_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	star_row.add_theme_constant_override("separation", 6)
	if not is_you:
		star_row.alignment = BoxContainer.ALIGNMENT_END
	var star := TextureRect.new()
	var star_col := Color("3ec8e0") if is_you else Color("f0c44a")
	star.texture = Chrome.make_icon("star", star_col, 18)
	star.custom_minimum_size = Vector2(18, 18)
	star.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	star.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	star.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var level := Label.new()
	level.text = "24" if is_you else str(PLATE_RIVAL_STAR)
	level.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	Chrome.apply_label(level, 14, star_col, true)
	if is_you:
		star_row.add_child(star)
		star_row.add_child(level)
	else:
		star_row.add_child(star)
		star_row.add_child(level)
	col.add_child(star_row)
	var bar := Panel.new()
	bar.custom_minimum_size = Vector2(168, 18)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bar_fill := Color("2eb8e6") if is_you else Color("f08a2a")
	var bar_box := Chrome.bevel_style(bar_fill, Vector2(168, 18), 8, 3)
	bar_box.content_margin_left = 0
	bar_box.content_margin_right = 0
	bar_box.content_margin_top = 0
	bar_box.content_margin_bottom = 0
	bar.add_theme_stylebox_override("panel", bar_box)
	col.add_child(bar)
	if is_you:
		row.add_child(face)
		row.add_child(col)
		_you_chip = chip
		_you_level = level
	else:
		row.add_child(col)
		row.add_child(face)
		_rival_chip = chip
		_rival_level = level


func _on_match_event(player_id: String, _event_name: String, snapshot: Dictionary) -> void:
	if player_id != ClientSession.player_id:
		return
	ClientSession.apply_snapshot(snapshot)
	var snap: Snapshot = Snapshot.from_dict(snapshot)
	_bind_server_exposure(snap)
	_refresh(snap)


func _refresh(snap: Snapshot) -> void:
	_bind_server_exposure(snap)
	_sync_practice_bot(snap)
	_board.apply_snapshot(snap, _selected, _highlights(snap))
	_you_chip.text = ClientSession.HANDLE
	if _you_level:
		_you_level.text = str(snap.you_marks())
	if _practice_rival(snap):
		_rival_chip.text = Contract.PRACTICE_RIVAL
	elif ClientSession.is_job() or snap.is_job():
		_rival_chip.text = "BOT"
	else:
		_rival_chip.text = ClientSession.RIVAL
	if _rival_level:
		_rival_level.text = str(PLATE_RIVAL_STAR)
	if _practice_chip:
		_practice_chip.visible = _practice_rival(snap)
		_practice_chip.text = Contract.PRACTICE_CHIP
	if _btn_abandon:
		if snap.is_practice() or ClientSession.is_practice():
			_btn_abandon.tooltip_text = Contract.PRACTICE_ABANDON_TIP
		else:
			_btn_abandon.tooltip_text = "Leave the hunt. Rival keeps the Marks table (+%d / %d)." % [Contract.MARKS_FORFEIT_WIN, Contract.MARKS_FORFEIT_LOSS]
	var turn_n := snap.turn_index()
	if turn_n < 1:
		turn_n = 1
	_turn.text = "TURN  %d" % turn_n
	_phase.text = ""

	match snap.status():
		Contract.STATUS_READY:
			_status.text = ""
			_phase.text = ""
			_toast.text = ""
			var both_dropped := snap.you_placed() and (_dummy_placed or snap.enemy_placed())
			_btn_start.text = "START" if both_dropped else "DROP"
			_btn_start.disabled = not both_dropped
			_btn_start.visible = true
			_set_actions(false)
			_end_panel.visible = false
			_set_abandon_visible(false)
			_bind_grace(snap)
		Contract.STATUS_ACTIVE:
			_btn_start.visible = false
			_set_abandon_visible(true)
			_bind_grace(snap)
			var yours := snap.is_your_turn()
			if _art_lock_end_panel:
				_status.text = "End turn — set exposure, optional adjacent move."
				_set_actions(false)
				_end_panel.visible = true
				if _exposure_doll:
					var skin := snap.you_equipped_skin_id()
					if skin == "":
						skin = ClientSession.equipped_cosmetic
					_exposure_doll.bind_equipped(skin)
			elif _dummy_delay > 0.0:
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
			_set_abandon_visible(false)
			_bind_grace(snap)
			_show_ended(snap)
		_:
			_status.text = snap.status()
			_set_abandon_visible(false)
			_bind_grace(snap)

	var last: Variant = snap.last_action()
	if last is Dictionary and snap.status() != Contract.STATUS_READY:
		_toast.text = Chrome.describe_last_action(last)
		AudioJuice.notice_last_action(last)
	_btn_uav.disabled = _btn_uav.disabled or snap.uav_remaining() <= 0
	if snap.uav_remaining() <= 0:
		_btn_uav.text = "%s\nSPENT" % Contract.ABILITY_LABEL
	else:
		_btn_uav.text = Contract.ABILITY_LABEL
	_bind_decoy(snap)
	_bind_high_ground(snap)
	_bind_smoke(snap)
	_sync_coach(snap)
	_sync_terrain_coach(snap)


func _highlights(snap: Snapshot) -> Dictionary:
	var extra := {}
	if _relocate_hex != null:
		extra[Contract.hex_key(_relocate_hex)] = Color("7ec8e3")
	if snap.enemy_soft_hot() > 0 and snap.enemy_visible_hex() != null:
		extra[Contract.hex_key(snap.enemy_visible_hex())] = Color("f0a020")
	return extra


func _sync_coach(snap: Snapshot) -> void:
	if _coach == null:
		return
	var job := ClientSession.is_job() or snap.is_job()
	var live := snap.status() == Contract.STATUS_ACTIVE
	_coach.present(job, live)


func _sync_terrain_coach(snap: Snapshot) -> void:
	## HIGH while the hard-hex chip is lit. BRUSH when the server says cover applied.
	## A brush hit ends the hunt, so that tip is allowed on the ended snapshot too.
	## Missing cover is not relevant. Jobs skip. Chip bodies never lock the board.
	if _terrain == null:
		return
	var job := ClientSession.is_job() or snap.is_job()
	if job:
		_terrain.present(false, false)
		return
	var live := snap.status() == Contract.STATUS_ACTIVE
	var ended := snap.status() == Contract.STATUS_ENDED
	if not live and not ended:
		_terrain.present(false, false)
		return
	var cover: Variant = snap.last_cover_applied()
	var brush := false
	if cover == true:
		brush = true
	var high := live and snap.you_high_ground_active()
	_terrain.present(high, brush)


func _set_actions(on: bool) -> void:
	_btn_attack.disabled = not on
	_btn_recon.disabled = not on
	_btn_uav.disabled = not on
	_btn_decoy.disabled = not on
	if _btn_smoke:
		_btn_smoke.disabled = not on


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
		_optic.open_for(_selected, kind, show_fig, ClientSession.equipped_gun_id())
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
	## Fail closed: locked, spent, or a missing level/charge does not POST.
	var snap: Snapshot = ClientSession.typed_snapshot()
	if snap.decoy_chrome() == Contract.DECOY_CHROME_LOCKED:
		_show_decoy_lock_toast(snap)
		return
	if snap.decoy_chrome() != Contract.DECOY_CHROME_AVAILABLE:
		return
	_submit(ActionIntent.decoy())


func _on_smoke() -> void:
	## Fail closed: locked, spent, or a missing level/charge does not POST.
	var snap: Snapshot = ClientSession.typed_snapshot()
	if snap.smoke_chrome() == Contract.SMOKE_CHROME_LOCKED:
		_show_smoke_lock_toast(snap)
		return
	if snap.smoke_chrome() != Contract.SMOKE_CHROME_AVAILABLE:
		return
	_submit(ActionIntent.smoke())


func _toggle_mute() -> void:
	AudioJuice.toggle_mute()
	if _mute_btn:
		Chrome.paint_gear_button(_mute_btn, AudioJuice.muted)
		_mute_btn.tooltip_text = Chrome.mute_button_tip(AudioJuice.muted)


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
	var floor := ClientSession.typed_snapshot().you_exposure_floor()
	var intent := Contract.clamp_exposure_intent(floor, _exposure.value)
	## Intent exposurePct only. The gear floor is not a client field.
	var body := ActionIntent.end_turn(intent, _relocate_hex)
	_relocate_hex = null
	_selected = null
	## Practice bot already moved inside the server response. No local dummy wait.
	if ClientSession.is_practice() and ClientSession.dummy_player_id == "":
		_dummy_delay = 0.0
		_dummy_busy = false
	else:
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


func _set_abandon_visible(on: bool) -> void:
	if _btn_abandon:
		_btn_abandon.visible = on
		_btn_abandon.disabled = _abandon_busy or not on


func _bind_grace(snap: Snapshot) -> void:
	var left := 0.0
	if snap.status() == Contract.STATUS_ACTIVE:
		left = snap.grace_remaining_sec()
		if left <= 0.0 and LiveMatchClient.poll_failed_since_msec >= 0:
			var elapsed := float(Time.get_ticks_msec() - LiveMatchClient.poll_failed_since_msec) / 1000.0
			left = maxf(0.0, float(Contract.FORFEIT_GRACE_SEC) - elapsed)
	_grace_left = left if left > 0.0 else -1.0
	_paint_grace(snap, left)


func _paint_grace(snap: Snapshot, left: float) -> void:
	var show := snap.status() == Contract.STATUS_ACTIVE and left > 0.0
	if _clock_icon:
		_clock_icon.visible = true
	if _grace_lbl:
		_grace_lbl.visible = show
		if show:
			var clock := Contract.format_grace_clock(left)
			if snap.in_grace() or snap.enemy_disconnected_at() != null:
				_grace_lbl.text = Contract.GRACE_RIVAL_COPY % clock
			else:
				_grace_lbl.text = Contract.GRACE_HOLD_COPY % clock


func _tick_grace(delta: float) -> void:
	if _grace_left < 0.0 or _over.visible:
		return
	_grace_left = maxf(0.0, _grace_left - delta)
	_paint_grace(ClientSession.typed_snapshot(), _grace_left)
	if _grace_left <= 0.0:
		var fresh: Dictionary = MatchAPI.reconnect()
		if not fresh.is_empty():
			_refresh(ClientSession.typed_snapshot())


func _on_abandon() -> void:
	if _abandon_busy or _going_hideout:
		return
	_abandon_busy = true
	_set_abandon_visible(true)
	var body: Dictionary = MatchAPI.abandon()
	_abandon_busy = false
	if str(body.get("error", "")) == Contract.ABANDON_ERR_UNAVAILABLE:
		_toast.text = "LIVE /abandon pending Coder"
		return
	var snap_raw: Variant = body.get("snapshot", {})
	if snap_raw is Dictionary and not snap_raw.is_empty():
		ClientSession.apply_snapshot(snap_raw)
	elif bool(body.get("ok", false)):
		MatchAPI.reconnect()
	_refresh(ClientSession.typed_snapshot())
	if str(body.get("error", "")) != "" and not bool(body.get("ok", false)):
		_toast.text = "REFUSED  %s" % str(body.get("error"))


func _process(delta: float) -> void:
	_tick_rematch(delta)
	_tick_grace(delta)
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
	var job := ClientSession.is_job() or snap.is_job()
	var practice := snap.is_practice() or ClientSession.is_practice()
	var parts: Dictionary = MarksPayout.overlay_parts(snap.raw, snap.you_seat(), job, practice)
	_over_lbl.text = str(parts.get("headline", ""))
	if _over_marks:
		_over_marks.text = str(parts.get("marks", ""))
		_over_marks.visible = str(parts.get("marks", "")) != ""
	if _over_xp:
		var xp_line := str(parts.get("xp", ""))
		_over_xp.text = xp_line
		_over_xp.visible = xp_line != ""
	if _over_reason:
		_over_reason.text = str(parts.get("reason", ""))
		_over_reason.visible = str(parts.get("reason", "")) != ""
	var offered := snap.rematch_offered()
	var foil := snap.is_forfeit() and not snap.is_job()
	if foil and not offered and snap.status() == Contract.STATUS_ENDED:
		offered = true
	var you_waiting := offered and snap.rematch_you_accepted() and not snap.rematch_opponent_accepted()
	_over_settle.visible = offered or snap.is_forfeit() or practice
	_over_settle.text = Contract.PRACTICE_SETTLED_COPY if practice else Contract.REMATCH_SETTLED_COPY
	_over_hint.visible = offered
	if practice:
		_over_hint.text = Contract.PRACTICE_WAIT_COPY if you_waiting else Contract.PRACTICE_REMATCH_HINT
	elif foil:
		_over_hint.text = Contract.REMATCH_WAIT_COPY if you_waiting else Contract.FORFEIT_HINT_COPY
	else:
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


func _capture_practice_bot() -> void:
	## In-match still: same HUD, toy-spy chip, server bot already seated.
	if _coach:
		_coach.dismiss()
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	_dummy_busy = true
	_dummy_placed = true
	_dummy_delay = 0.0
	await get_tree().process_frame
	var snap := ClientSession.typed_snapshot()
	if snap.status() == Contract.STATUS_READY and not snap.you_placed():
		_submit(ActionIntent.select_hex(2, 2))
		snap = ClientSession.typed_snapshot()
	if snap.status() == Contract.STATUS_READY:
		_submit(ActionIntent.start())
		snap = ClientSession.typed_snapshot()
	_refresh(snap)
	if _over:
		_over.visible = false
	if _coach:
		_coach.dismiss()
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path("res://artifacts/ux/practice_vs_bot.png")
	img.save_png(path)
	print("P6_PRACTICE_VS_BOT ", path)
	get_tree().quit()


func _sync_practice_bot(snap: Snapshot) -> void:
	## Server already seated the toy spy. Do not invent a client-side dummy.
	if ClientSession.dummy_player_id != "":
		return
	if (snap.is_practice() or ClientSession.is_practice()) and snap.enemy_is_bot():
		_dummy_placed = true


func _practice_rival(snap: Snapshot) -> bool:
	return (snap.is_practice() or ClientSession.is_practice()) and (snap.enemy_is_bot() or ClientSession.dummy_player_id == "")


func _enter_rematch(body: Dictionary) -> void:
	if _rematch_busy or _going_hideout:
		return
	var keep_practice := ClientSession.is_practice() or ClientSession.typed_snapshot().is_practice()
	_rematch_busy = true
	_over.visible = false
	_rematch_left = -1.0
	body = _ensure_ready_body(body)
	var snap_dict: Dictionary = MatchAPI.bind_new_match(body)
	var neu := ClientSession.typed_snapshot()
	if keep_practice and (not ClientSession.is_practice() or not neu.is_practice() or not neu.enemy_is_bot()):
		_rematch_busy = false
		_toast.text = Contract.PRACTICE_UNAVAILABLE_COPY
		_go_hideout()
		return
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
	return Chrome.describe_last_action(last)
