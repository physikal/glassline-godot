extends Control

const Chrome := preload("res://scripts/chrome.gd")
const ArtPack := preload("res://scripts/art_pack.gd")
const Contract := preload("res://types/contract.gd")
const MarksPayout := preload("res://types/marks_payout.gd")
const Shop := preload("res://types/shop.gd")
const Lobby := preload("res://types/lobby.gd")
const Queue := preload("res://types/queue.gd")
const ExposureDoll := preload("res://scenes/match/exposure_doll.gd")
const JournalPlate := preload("res://scenes/lobby/journal_plate.gd")
const GearStrip := preload("res://scenes/lobby/gear_strip.gd")
const InviteShare := preload("res://scripts/invite_share.gd")
const LobbyPaste := preload("res://scripts/lobby_paste.gd")

var _bg: TextureRect
var _wood_covers: Array[ColorRect] = []
var _toast: Label
var _marks: Label
var _last_pay: Label
var _mode_lbl: Label
var _mode_btn: Button
var _jobs_panel: PanelContainer
var _invite_panel: PanelContainer
var _invite_home: VBoxContainer
var _invite_wait: VBoxContainer
var _invite_code_lbl: Label
var _invite_copied_chip: PanelContainer
var _invite_copied: Label
var _invite_reject: Label
var _join_edit: LineEdit
var _join_paste: Button
var _join_paste_code: String = ""
var _join_pasted: Label
var _lobby_poll: float = 0.0
var _lobby_waiting: bool = false
var _queue_panel: PanelContainer
var _queue_waiting: bool = false
var _queue_poll: float = 0.0
var _queue_elapsed: float = 0.0
var _shop_row: PanelContainer
var _shop_col: VBoxContainer
var _shop_lines: Dictionary = {}
var _bandana_wash: ColorRect
var _poster: TextureRect
var _buying_id: String = ""
var _gun_rack: Control
var _gun_hands: TextureRect
var _gun_kicker: Label
var _wallet_row: HBoxContainer
var _taste_doll: ExposureDoll
var _dock_quick: Button
var _dock_invite: Button
var _dock_practice: Button
var _practice_panel: PanelContainer
var _journal_plate: JournalPlate
var _gear: GearStrip
var _dock: HBoxContainer


func _ready() -> void:
	set_anchors_preset(PRESET_FULL_RECT)
	_build()
	_refresh_bg()
	if ClientSession.use_live_api():
		MatchAPI.ensure_player()
	_bind_wallet()
	_bind_shop()
	_refresh_marks()
	_refresh_shop()
	var args := OS.get_cmdline_user_args()
	if "--assert-paste-toast" in args:
		get_tree().quit(_assert_paste_toast())
		return
	if "--capture-lobby" in args:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(Vector2i(1280, 720))
		await _capture_lobby()
	elif "--capture-shop" in args:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(Vector2i(1280, 720))
		await _capture_named("res://artifacts/ux/shop_row.png", "S5_SHOP_ROW")
	elif "--capture-shop-buy" in args:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(Vector2i(1280, 720))
		await _capture_shop_buy()
	elif "--capture-armory-two-row" in args:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(Vector2i(1280, 720))
		await _capture_named("res://artifacts/ux/armory_two_row.png", "S25_ARMORY_TWO_ROW")
	elif "--capture-armory-bandana-buy" in args:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(Vector2i(1280, 720))
		await _capture_armory_bandana_buy()
	elif "--capture-armory-three-row" in args:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(Vector2i(1280, 720))
		await _capture_named("res://artifacts/ux/armory_three_row.png", "S35_ARMORY_THREE_ROW")
	elif "--capture-armory-poster-buy" in args:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(Vector2i(1280, 720))
		await _capture_armory_poster_buy()
	elif "--capture-hideout-poster" in args:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(Vector2i(1280, 720))
		await _capture_hideout_poster()
	elif "--capture-equip-hideout" in args:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(Vector2i(1280, 720))
		await _capture_equip_hideout()
	elif "--capture-equip-doll" in args:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(Vector2i(1280, 720))
		await _capture_equip_then_play()
	elif "--capture-a1" in args:
		await get_tree().process_frame
		_on_play()
	elif "--capture-a2" in args:
		await get_tree().process_frame
		_on_play()
	elif "--capture-sp-end" in args:
		await get_tree().process_frame
		_on_start_job()
	elif "--capture-lobby-create-wait" in args:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(Vector2i(1280, 720))
		await _capture_lobby_create_wait()
	elif "--capture-lobby-join" in args:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(Vector2i(1280, 720))
		await _capture_lobby_join()
	elif "--capture-lobby-paste" in args:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(Vector2i(1280, 720))
		await _capture_lobby_paste()
	elif "--capture-lobby-bad-code" in args:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(Vector2i(1280, 720))
		await _capture_lobby_bad_code()
	elif "--capture-lobby-cancel-hideout" in args:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(Vector2i(1280, 720))
		await _capture_lobby_cancel_hideout()
	elif "--capture-queue-finding-rival" in args:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(Vector2i(1280, 720))
		await _capture_queue_finding_rival()
	elif "--capture-queue-cancel-hideout" in args:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(Vector2i(1280, 720))
		await _capture_queue_cancel_hideout()
	elif "--capture-queue-timeout-hideout" in args:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(Vector2i(1280, 720))
		await _capture_queue_timeout_hideout()
	elif "--capture-queue-matched-board" in args:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(Vector2i(1280, 720))
		await _capture_queue_matched_board()
	elif "--capture-sp-jobs-ladder" in args:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(Vector2i(1280, 720))
		await _capture_jobs_ladder()
	elif "--capture-sp-job-t3" in args:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(Vector2i(1280, 720))
		await _capture_sp_job_t3()
	elif "--capture-coach-tips" in args or "--capture-coach-dismissed" in args \
			or "--capture-coach-chip" in args:
		await get_tree().process_frame
		_on_play()
	elif "--capture-art-hideout" in args:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(Vector2i(1280, 720))
		await _capture_art_hideout()
	elif "--capture-art-armory" in args:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(Vector2i(1280, 720))
		_prep_art_hideout_chrome()
		if _shop_row:
			_shop_row.visible = true
		await _capture_named("res://artifacts/ux/01_hideout_idle_armory.png", "ART_01_HIDEOUT_IDLE_ARMORY")
	elif "--capture-art-ui-chips" in args:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(Vector2i(1280, 720))
		await _capture_queue_finding_rival()
	elif "--capture-art-operative-doll" in args:
		## Still 04 is the match end-turn doll — not a hideout inset.
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(Vector2i(1280, 720))
		await get_tree().process_frame
		_on_play()
	elif "--capture-gun-armory-three-row" in args:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(Vector2i(1280, 720))
		await _capture_gun_armory_three_row()
	elif "--capture-gun-rack-dynamic" in args:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(Vector2i(1280, 720))
		await _capture_gun_rack_dynamic()
	elif "--capture-gun-equipped-optic" in args:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(Vector2i(1280, 720))
		await _capture_gun_equipped_optic()
	elif "--capture-art-hex" in args or "--capture-art-optic" in args:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(Vector2i(1280, 720))
		await get_tree().process_frame
		_on_play()
	elif "--capture-decoy-hud" in args or "--capture-decoy-blip" in args:
		await get_tree().process_frame
		_on_play()
	elif "--capture-high-ground-lit" in args or "--capture-high-ground-muted" in args \
			or "--capture-brush-cover-toast" in args \
			or "--capture-coach-terrain-high" in args \
			or "--capture-coach-terrain-brush" in args:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(Vector2i(1280, 720))
		await get_tree().process_frame
		_on_play()
	elif "--capture-rematch-ended" in args or "--capture-rematch-ready" in args:
		await get_tree().process_frame
		_on_play()
	elif "--capture-practice-cta" in args:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(Vector2i(1280, 720))
		await _capture_practice_cta()
	elif "--capture-practice-no-marks" in args:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(Vector2i(1280, 720))
		await _capture_practice_no_marks()
	elif "--capture-practice-bot" in args:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(Vector2i(1280, 720))
		await get_tree().process_frame
		_start_practice()
	elif "--capture-journal-empty" in args:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(Vector2i(1280, 720))
		await _capture_journal_empty()
	elif "--capture-journal-rows" in args:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(Vector2i(1280, 720))
		await _capture_journal_rows()
	elif "--capture-journal-muted" in args:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(Vector2i(1280, 720))
		await _capture_journal_muted()
	elif "--capture-gear-strip" in args:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(Vector2i(1280, 720))
		await _capture_gear(false, false)
	elif "--capture-gear-muted" in args:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(Vector2i(1280, 720))
		await _capture_gear(true, false)
	elif "--capture-gear-confirm" in args:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(Vector2i(1280, 720))
		await _capture_gear(false, true)
	elif "--capture-abandon-cta" in args or "--capture-grace-countdown" in args \
			or "--capture-forfeit-overlay" in args \
			or "--capture-end-summary-kill" in args \
			or "--capture-end-summary-forfeit" in args \
			or "--capture-end-summary-standoff" in args:
		if "--capture-end-summary-kill" in args or "--capture-end-summary-forfeit" in args \
				or "--capture-end-summary-standoff" in args:
			if not ClientSession.use_live_api():
				MockMatchServer.reset_wallet(0)
		await get_tree().process_frame
		_on_play()


func _capture_lobby() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path("res://artifacts/a1-lobby.png")
	img.save_png(path)
	print("A1_LOBBY_CAPTURE ", path)
	get_tree().quit()


func _capture_named(res_path: String, tag: String, quit_after: bool = true) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path(res_path)
	img.save_png(path)
	print("%s %s" % [tag, path])
	if quit_after:
		get_tree().quit()


func _capture_shop_buy() -> void:
	## Mock ledger only — seed enough Marks, then bind the buy snapshot (never marks -=).
	if not ClientSession.use_live_api():
		MockMatchServer.reset_wallet(80)
	_bind_wallet()
	_bind_shop()
	_refresh_marks()
	_refresh_shop()
	await get_tree().process_frame
	_on_shop_primary(Contract.SHOP_STUB_ITEM_ID)
	await get_tree().process_frame
	await get_tree().process_frame
	await _capture_named("res://artifacts/ux/shop_post_buy_marks.png", "S5_SHOP_POST_BUY")


func _capture_armory_bandana_buy() -> void:
	## Mock ledger only — seed enough Marks, bind bandana buy snapshot (never marks -=).
	if not ClientSession.use_live_api():
		MockMatchServer.reset_wallet(180)
	_bind_wallet()
	_bind_shop()
	_refresh_marks()
	_refresh_shop()
	await get_tree().process_frame
	_on_shop_primary(Contract.SHOP_BANDANA_ITEM_ID)
	await get_tree().process_frame
	await get_tree().process_frame
	await _capture_named("res://artifacts/ux/armory_bandana_post_buy.png", "S25_ARMORY_BANDANA_BUY")


func _capture_armory_poster_buy() -> void:
	## Mock ledger only — seed enough Marks, bind poster buy snapshot (never marks -=).
	if not ClientSession.use_live_api():
		MockMatchServer.reset_wallet(200)
	_bind_wallet()
	_bind_shop()
	_refresh_marks()
	_refresh_shop()
	await get_tree().process_frame
	_on_shop_primary(Contract.SHOP_POSTER_ITEM_ID)
	await get_tree().process_frame
	await get_tree().process_frame
	await _capture_named("res://artifacts/ux/armory_poster_post_buy.png", "S35_ARMORY_POSTER_BUY")


func _capture_hideout_poster() -> void:
	## S3.4: owned + auto-equip poster on the hideout wall. Marks from snapshot only.
	if not ClientSession.use_live_api():
		MockMatchServer.reset_wallet(200)
	_bind_wallet()
	_bind_shop()
	_refresh_marks()
	_refresh_shop()
	await get_tree().process_frame
	_on_shop_primary(Contract.SHOP_POSTER_ITEM_ID)
	await get_tree().process_frame
	if int(ClientSession.marks) >= Contract.SHOP_STUB_PRICE:
		_on_shop_primary(Contract.SHOP_STUB_ITEM_ID)
		await get_tree().process_frame
	if _shop_row:
		_shop_row.visible = false
	await get_tree().process_frame
	await get_tree().process_frame
	await _capture_named("res://artifacts/ux/hideout_poster_equipped.png", "S34_HIDEOUT_POSTER")


func _capture_equip_hideout() -> void:
	## E6: OWNED ghillie shows EQUIPPED + hideout plate. Marks from snapshot only.
	if not ClientSession.use_live_api():
		MockMatchServer.reset_wallet(80)
	_bind_wallet()
	_bind_shop()
	_refresh_marks()
	_refresh_shop()
	await get_tree().process_frame
	_on_shop_primary(Contract.SHOP_STUB_ITEM_ID)
	await get_tree().process_frame
	await get_tree().process_frame
	await _capture_named("res://artifacts/ux/equip_owned_hideout.png", "E6_EQUIP_HIDEOUT")


func _capture_equip_then_play() -> void:
	## Seed + equip ghillie, then PLAY so match stills can bind the same skin id.
	if not ClientSession.use_live_api():
		MockMatchServer.reset_wallet(80)
	_bind_wallet()
	_bind_shop()
	_refresh_marks()
	_refresh_shop()
	await get_tree().process_frame
	_on_shop_primary(Contract.SHOP_STUB_ITEM_ID)
	await get_tree().process_frame
	_start_match(Contract.MODE_PVP)


func _capture_lobby_create_wait() -> void:
	_open_invite()
	_on_create_lobby()
	await _capture_named("res://artifacts/ux/lobby_create_wait.png", "P6_LOBBY_CREATE_WAIT", false)
	_on_copy_lobby_code()
	await _capture_named("res://artifacts/ux/lobby_invite_copied.png", "I6_LOBBY_COPIED")


func _capture_lobby_join() -> void:
	DisplayServer.clipboard_set("")
	_open_invite()
	if _join_edit:
		_join_edit.text = ""
		_join_edit.grab_focus()
	await _capture_named("res://artifacts/ux/lobby_join.png", "P6_LOBBY_JOIN")


func _assert_paste_toast() -> int:
	## Soft P2: Pasted. only after a PASTE tap this visit.
	var failed: PackedStringArray = []
	_open_invite()
	if _join_edit:
		_join_edit.text = ""
	if (_join_pasted and _join_pasted.visible) or _toast.text == Contract.LOBBY_PASTED_COPY:
		failed.append("fresh join shows Pasted")
	if _join_edit and _join_edit.text != "":
		failed.append("fresh join auto-filled")
	_set_paste_offer("H7K3P2")
	_on_paste_lobby_code()
	if _join_edit == null or _join_edit.text != "H7K3P2":
		failed.append("tap did not fill")
	if _join_pasted == null or not _join_pasted.visible or _join_pasted.text != Contract.LOBBY_PASTED_COPY:
		failed.append("tap did not show Pasted")
	if _toast.text != Contract.LOBBY_PASTED_COPY:
		failed.append("tap did not toast Pasted")
	DisplayServer.clipboard_set("")
	_peek_join_clipboard()
	if _join_paste and _join_paste.visible:
		failed.append("empty peek left the chip up")
	if (_join_pasted and _join_pasted.visible) or _toast.text == Contract.LOBBY_PASTED_COPY:
		failed.append("empty peek left Pasted")
	if _join_edit and _join_edit.text != "H7K3P2":
		failed.append("empty peek rewrote the field")
	_set_paste_offer("H7K3P2")
	_on_paste_lobby_code()
	_close_invite()
	if (_join_pasted and _join_pasted.visible) or _toast.text == Contract.LOBBY_PASTED_COPY:
		failed.append("leave left Pasted")
	_open_invite()
	if _join_paste and _join_paste.visible:
		failed.append("reopen empty showed the chip")
	if (_join_pasted and _join_pasted.visible) or _toast.text == Contract.LOBBY_PASTED_COPY:
		failed.append("reopen showed Pasted")
	_set_paste_offer("H7K3P2")
	_on_paste_lobby_code()
	DisplayServer.clipboard_set("H7K3P2")
	_show_invite_home()
	if (_join_pasted and _join_pasted.visible) or _toast.text == Contract.LOBBY_PASTED_COPY:
		failed.append("opening join left Pasted")
	if LobbyPaste.peek_code() == "H7K3P2" and _join_paste and not _join_paste.visible:
		failed.append("open peek hid a valid code")
	if failed.is_empty():
		print("PASTE_TOAST_OK")
		return 0
	for line in failed:
		print("FAIL: ", line)
	return 1


func _capture_lobby_paste() -> void:
	## C6 / C2: chip when the clipboard is a code, fill on tap, gold Pasted. line.
	DisplayServer.clipboard_set("H7K3P2")
	_open_invite()
	if _join_edit:
		_join_edit.text = ""
		_join_edit.caret_column = 0
	await _capture_named("res://artifacts/ux/lobby_paste.png", "C6_LOBBY_PASTE", false)
	_on_paste_lobby_code()
	await _capture_named("res://artifacts/ux/lobby_pasted.png", "C2_LOBBY_PASTED", false)
	## Soft P2: reopen Join with an empty clipboard. Pasted. must not stick.
	_close_invite()
	DisplayServer.clipboard_set("")
	_open_invite()
	if _join_edit:
		_join_edit.text = ""
		_join_edit.caret_column = 0
	await _capture_named("res://artifacts/ux/lobby_paste_empty.png", "C3_LOBBY_PASTE_EMPTY")


func _capture_lobby_bad_code() -> void:
	_open_invite()
	if _join_edit:
		_join_edit.text = "ABCDEF"
	_on_join_lobby()
	await _capture_named("res://artifacts/ux/lobby_bad_code.png", "P6_LOBBY_BAD_CODE")


func _capture_lobby_cancel_hideout() -> void:
	_open_invite()
	_on_create_lobby()
	await get_tree().process_frame
	_on_cancel_lobby()
	await _capture_named("res://artifacts/ux/lobby_cancel_hideout.png", "P6_LOBBY_CANCEL_HIDEOUT")


func _prep_queue_capture() -> void:
	if not ClientSession.use_live_api():
		MockMatchServer.reset_wallet(24)
		MockMatchServer.queue_pair_delay_ms = 80
		ClientSession.durable_player_id = "p_mock"
	_bind_wallet()
	_refresh_marks()


func _capture_queue_finding_rival() -> void:
	_prep_queue_capture()
	_on_quick_match()
	await _capture_named("res://artifacts/ux/queue_finding_rival.png", "Q6_QUEUE_FINDING")


func _capture_queue_cancel_hideout() -> void:
	_prep_queue_capture()
	_on_quick_match()
	await get_tree().process_frame
	_on_cancel_queue()
	await _capture_named("res://artifacts/ux/queue_cancel_hideout.png", "Q3_QUEUE_CANCEL_HIDEOUT")


func _capture_queue_timeout_hideout() -> void:
	_prep_queue_capture()
	_on_quick_match()
	await get_tree().process_frame
	_on_queue_timeout()
	await _capture_named("res://artifacts/ux/queue_timeout_hideout.png", "Q4_QUEUE_TIMEOUT_HIDEOUT")


func _capture_queue_matched_board() -> void:
	## Pair a second mock seat, then hand off into the existing drop board.
	_prep_queue_capture()
	if not ClientSession.use_live_api():
		MockMatchServer.queue_pair_delay_ms = 0
	_on_quick_match()
	if not ClientSession.use_live_api():
		MockMatchServer.enqueue("p_guest")
	_poll_queue()


func _prep_art_hideout_chrome() -> void:
	## Hide ARMORY sheet only. Invite + Quick Match stay on the live dock.
	if _shop_row:
		_shop_row.visible = false
	if _dock_quick:
		_dock_quick.visible = true
	if _dock_practice:
		_dock_practice.visible = true
	if _dock_invite:
		_dock_invite.visible = true
	_refresh_gun_rack()


func _capture_gun_armory_three_row() -> void:
	## Taste: Fieldbolt owned · Railframe ★125 · Crescent ★200.
	if not ClientSession.use_live_api():
		MockMatchServer.reset_wallet(24)
	_bind_wallet()
	_bind_shop()
	_refresh_marks()
	_refresh_shop()
	if _shop_row:
		_shop_row.visible = true
		_shop_row.offset_top = -420
		_shop_row.offset_bottom = -88
	_hide_non_gun_shop_rows()
	_debug_status_toast(Chrome.armory_debug_ribbon())
	await _capture_named("res://artifacts/ux/gun_armory_three_row.png", "GUN_ARMORY_THREE_ROW")


func _capture_gun_rack_dynamic() -> void:
	## Owned painted + equipped highlight · locked silhouettes.
	if not ClientSession.use_live_api():
		MockMatchServer.reset_wallet(200)
		MockMatchServer.buy_shop(Contract.GUN_RAILFRAME, "ux-rack-rail")
		MockMatchServer.equip_cosmetic(Contract.GUN_FIELDBOLT, Contract.GUN_SLOT)
	_bind_wallet()
	_bind_shop()
	_refresh_marks()
	_refresh_shop()
	if _shop_row:
		_shop_row.visible = false
	_refresh_gun_rack()
	_debug_status_toast(Chrome.rack_debug_ribbon())
	await _capture_named("res://artifacts/ux/gun_rack_dynamic.png", "GUN_RACK_DYNAMIC")


func _capture_gun_equipped_optic() -> void:
	## Attack optic family matches equipped Railframe (not hardcoded Fieldbolt).
	if not ClientSession.use_live_api():
		MockMatchServer.reset_wallet(200)
		MockMatchServer.buy_shop(Contract.GUN_RAILFRAME, "ux-optic-rail")
	_bind_wallet()
	_bind_shop()
	_refresh_marks()
	_refresh_shop()
	await get_tree().process_frame
	_start_match(Contract.MODE_PVP)


func _hide_non_gun_shop_rows() -> void:
	if _shop_col == null:
		return
	for child in _shop_col.get_children():
		if child == _gun_kicker:
			continue
		if child is Label and str((child as Label).text) == "ARMORY":
			(child as Label).text = "ARMORY"
			continue
		var matched := false
		for item_id in _shop_lines.keys():
			if Contract.is_gun_chrome(str(item_id)) and _shop_lines[item_id].get("row", null) == child:
				matched = true
				break
		if child is PanelContainer and not matched:
			(child as CanvasItem).visible = false


func _capture_art_hideout() -> void:
	## Starter Fieldbolt owned+equipped, other two locked painted silhouettes.
	if not ClientSession.use_live_api():
		MockMatchServer.reset_wallet(24)
	_bind_wallet()
	_bind_shop()
	_refresh_marks()
	_refresh_shop()
	_prep_art_hideout_chrome()
	await get_tree().process_frame
	await get_tree().process_frame
	await _capture_named("res://artifacts/ux/02_dynamic_rack.png", "ART_02_DYNAMIC_RACK", false)
	## Ghillie plate pair for side_by_side_ghillie — same hideout, ghillie body.
	ClientSession.ghillie = true
	ClientSession.equipped_cosmetic = Contract.SHOP_STUB_ITEM_ID
	_refresh_bg()
	_prep_art_hideout_chrome()
	await get_tree().process_frame
	await get_tree().process_frame
	await _capture_named("res://artifacts/ux/ghillie_hideout.png", "ART_GHILLIE_HIDEOUT")


func _capture_jobs_ladder() -> void:
	if not _jobs_panel.visible:
		_toggle_jobs()
	await _capture_named("res://artifacts/ux/sp_jobs_ladder.png", "J5_SP_JOBS_LADDER")


func _capture_sp_job_t3() -> void:
	## Mock T3 complete on the hideout — snapshot you.marks only. Never marks +=.
	if not ClientSession.use_live_api():
		MockMatchServer.reset_wallet(0)
	_bind_wallet()
	_refresh_marks()
	var cid := Contract.new_client_job_id()
	var done: Dictionary = MatchAPI.complete_job(3, cid)
	var snap: Variant = done.get("snapshot", {})
	if snap is Dictionary and not snap.is_empty():
		ClientSession.apply_snapshot(snap)
	elif done.has("you") or done.has("marks"):
		ClientSession.apply_shop(done)
	_refresh_marks()
	if _jobs_panel:
		_jobs_panel.visible = false
	if _shop_row:
		_shop_row.visible = true
	_toast_msg("Night Contract  ·  ★20")
	await _capture_named("res://artifacts/ux/sp_job_t3_post_marks.png", "J5_SP_JOB_T3_MARKS")


func _build() -> void:
	var wood := ColorRect.new()
	wood.color = Color("7a4e2c")
	wood.set_anchors_preset(PRESET_FULL_RECT)
	wood.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(wood)

	_bg = TextureRect.new()
	_bg.set_anchors_preset(PRESET_FULL_RECT)
	_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bg.stretch_mode = TextureRect.STRETCH_SCALE
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg)

	_bandana_wash = ColorRect.new()
	_bandana_wash.color = Chrome.BANDANA_WASH
	_bandana_wash.set_anchors_preset(PRESET_FULL_RECT)
	_bandana_wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bandana_wash.visible = false
	add_child(_bandana_wash)

	## Toy-spy hideout poster — on the wall beside the operative, above ARMORY.
	_poster = TextureRect.new()
	_poster.texture = Chrome.make_hideout_poster(96, 128)
	_poster.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_poster.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_poster.stretch_mode = TextureRect.STRETCH_SCALE
	_poster.set_anchors_preset(PRESET_CENTER)
	_poster.offset_left = -340
	_poster.offset_right = -164
	_poster.offset_top = -236
	_poster.offset_bottom = -4
	_poster.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_poster.visible = false
	add_child(_poster)

	_build_gun_rack()

	var dock_cover := ColorRect.new()
	dock_cover.color = Color("7a4e2c")
	dock_cover.set_anchors_and_offsets_preset(PRESET_BOTTOM_WIDE)
	dock_cover.offset_top = -200
	dock_cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dock_cover)
	_wood_covers.append(dock_cover)

	## Operative hit — ghillie stays off the dock so PLAY can read as the CTA.
	var operative := Button.new()
	operative.flat = true
	operative.tooltip_text = "Swap suit"
	operative.set_anchors_preset(PRESET_CENTER)
	operative.offset_left = -130
	operative.offset_right = 130
	operative.offset_top = -150
	operative.offset_bottom = 170
	var clear := StyleBoxEmpty.new()
	operative.add_theme_stylebox_override("normal", clear)
	operative.add_theme_stylebox_override("hover", clear)
	operative.add_theme_stylebox_override("pressed", clear)
	operative.add_theme_stylebox_override("focus", clear)
	operative.pressed.connect(_toggle_suit)
	add_child(operative)

	_build_top_bar()
	_build_gear_strip()

	_last_pay = Label.new()
	_last_pay.visible = false
	add_child(_last_pay)

	_mode_lbl = Label.new()
	_mode_lbl.visible = false
	add_child(_mode_lbl)

	## Live/mock stays on F2 — no MOCK/LIVE debug chip in the hideout still.
	_mode_btn = Chrome.dock_button("MOCK", Chrome.INK, Chrome.CREAM, Vector2(118, 36))
	_mode_btn.visible = false
	_mode_btn.pressed.connect(_toggle_live)
	add_child(_mode_btn)
	_refresh_mode()

	var row := HBoxContainer.new()
	_dock = row
	row.set_anchors_preset(PRESET_BOTTOM_WIDE)
	row.offset_top = -108
	row.offset_bottom = -22
	row.offset_left = 28
	row.offset_right = -28
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	add_child(row)

	var loadout := Chrome.dock_button("LOADOUT", Chrome.LOADOUT_BLUE, Color.WHITE, Vector2(200, 64), "loadout")
	loadout.pressed.connect(_focus_shop)
	row.add_child(loadout)

	var play := Chrome.dock_button("PLAY", Chrome.PLAY_GREEN, Color.WHITE, Vector2(210, 72), "play")
	play.pressed.connect(_on_play)
	row.add_child(play)

	_dock_quick = Chrome.dock_button(Contract.QUEUE_CTA, Chrome.TEAL, Color.WHITE, Vector2(230, 64), "quick")
	_dock_quick.tooltip_text = "Find a rival. Same hunt. No ranked."
	_dock_quick.pressed.connect(_on_quick_match)
	row.add_child(_dock_quick)

	## Cozy paper chip — toy-spy icon, same dock weight as Quick Match / Invite.
	_dock_practice = Chrome.dock_button(Contract.PRACTICE_CTA, Chrome.POSTER_PAPER, Chrome.INK, Vector2(210, 64), "practice")
	_dock_practice.tooltip_text = Contract.PRACTICE_NO_MARKS
	_dock_practice.pressed.connect(_open_practice)
	row.add_child(_dock_practice)

	_dock_invite = Chrome.dock_button("INVITE", Chrome.HIGH_GOLD, Chrome.INK, Vector2(170, 64), "invite")
	_dock_invite.pressed.connect(_toggle_invite)
	row.add_child(_dock_invite)

	var jobs := Chrome.dock_button("JOBS", Chrome.JOBS_ORANGE, Color.WHITE, Vector2(160, 64), "jobs")
	jobs.pressed.connect(_toggle_jobs)
	row.add_child(jobs)

	_build_shop_row()
	_refresh_gun_rack()

	_toast = Label.new()
	_toast.set_anchors_preset(PRESET_BOTTOM_WIDE)
	_toast.offset_top = -400
	_toast.offset_bottom = -364
	_toast.offset_left = 80
	_toast.offset_right = -80
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	Chrome.apply_label(_toast, 10, Color("f0e3b0"), true)
	add_child(_toast)

	_build_jobs_panel()
	_build_invite_panel()
	_build_queue_panel()
	_build_practice_panel()
	_build_journal_plate()


func _build_top_bar() -> void:
	## Floating canon chrome — identity + readable Marks + gold/gems. No brown blocker bar.
	var left := HBoxContainer.new()
	left.position = Vector2(14, 12)
	left.add_theme_constant_override("separation", 12)
	add_child(left)

	var identity := Chrome.pill_chip()
	left.add_child(identity)
	var id_row := HBoxContainer.new()
	id_row.add_theme_constant_override("separation", 10)
	identity.add_child(id_row)

	var face := TextureRect.new()
	face.texture = Chrome.make_face("p1", 40)
	face.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	face.custom_minimum_size = Vector2(40, 40)
	face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	id_row.add_child(face)

	var id_col := VBoxContainer.new()
	id_col.add_theme_constant_override("separation", 4)
	id_row.add_child(id_col)

	var handle := Label.new()
	handle.text = ClientSession.HANDLE
	Chrome.apply_label(handle, 11, Chrome.CREAM, true)
	id_col.add_child(handle)

	var xp_track := Panel.new()
	xp_track.custom_minimum_size = Vector2(132, 10)
	xp_track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var track_box := Chrome.flat(Color("14110e"), 6, Color("2a2018"), 1)
	track_box.content_margin_left = 0
	track_box.content_margin_right = 0
	track_box.content_margin_top = 0
	track_box.content_margin_bottom = 0
	xp_track.add_theme_stylebox_override("panel", track_box)
	id_col.add_child(xp_track)

	var xp_fill := ColorRect.new()
	xp_fill.color = Chrome.XP_GREEN
	xp_fill.position = Vector2(2, 2)
	xp_fill.size = Vector2(84, 6)
	xp_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	xp_track.add_child(xp_fill)

	var marks_chip := Chrome.pill_chip(Chrome.INK, Chrome.HIGH_GOLD)
	left.add_child(marks_chip)
	_marks = Label.new()
	_marks.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	Chrome.apply_label(_marks, 12, Chrome.HIGH_GOLD, true)
	marks_chip.add_child(_marks)

	var journal := Chrome.dock_button(Contract.JOURNAL_CTA, Chrome.WOOD, Chrome.CREAM, Vector2(150, 36))
	journal.tooltip_text = "Last hunts from the ledger."
	journal.pressed.connect(_open_journal)
	left.add_child(journal)

	var wallet := HBoxContainer.new()
	wallet.set_anchors_preset(PRESET_TOP_RIGHT)
	wallet.offset_left = -500
	wallet.offset_right = -16
	wallet.offset_top = 12
	wallet.offset_bottom = 64
	wallet.alignment = BoxContainer.ALIGNMENT_END
	wallet.add_theme_constant_override("separation", 10)
	add_child(wallet)

	## Marks ★ only until Design stamps gold/gem chips.
	_wallet_row = wallet
	_wallet_row.visible = false


func _currency_chip(icon_kind: String, color: Color, amount: String) -> PanelContainer:
	var chip := Chrome.pill_chip()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	chip.add_child(row)
	var icon := TextureRect.new()
	icon.texture = Chrome.make_icon(icon_kind, color, 22)
	icon.custom_minimum_size = Vector2(22, 22)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon)
	var label := Label.new()
	label.text = amount
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	Chrome.apply_label(label, 10, Chrome.CREAM, true)
	row.add_child(label)
	return chip


func _build_shop_row() -> void:
	## Hideout ARMORY — catalog rows (skins / poster / guns). No IAP / combat.
	_shop_row = PanelContainer.new()
	_shop_row.set_anchors_preset(PRESET_BOTTOM_WIDE)
	_shop_row.offset_left = 72
	_shop_row.offset_right = -72
	_shop_row.offset_top = -358
	_shop_row.offset_bottom = -118
	var box := Chrome.flat(Color(0.10, 0.08, 0.06, 0.94), 20, Chrome.HIGH_GOLD, 3)
	box.content_margin_left = 18
	box.content_margin_right = 18
	box.content_margin_top = 6
	box.content_margin_bottom = 6
	_shop_row.add_theme_stylebox_override("panel", box)
	add_child(_shop_row)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_shop_row.add_child(scroll)

	_shop_col = VBoxContainer.new()
	_shop_col.add_theme_constant_override("separation", 4)
	_shop_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_shop_col)

	var kicker := Label.new()
	kicker.text = "ARMORY"
	kicker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	Chrome.apply_label(kicker, 10, Chrome.HIGH_GOLD, true)
	_shop_col.add_child(kicker)

	for item in Contract.shop_catalog_items():
		if item is Dictionary and not Contract.is_gun_chrome(str(item.get("id", ""))):
			_shop_col.add_child(_make_shop_line(item))

	_gun_kicker = Label.new()
	_gun_kicker.text = "GUNS  ·  visual only"
	_gun_kicker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	Chrome.apply_label(_gun_kicker, 8, Chrome.HIGH_GOLD, true)
	_shop_col.add_child(_gun_kicker)

	for item in Contract.shop_catalog_items():
		if item is Dictionary and Contract.is_gun_chrome(str(item.get("id", ""))):
			_shop_col.add_child(_make_shop_line(item))


func _make_shop_line(item: Dictionary) -> PanelContainer:
	var item_id := str(item.get("id", item.get("itemId", "")))
	var row := PanelContainer.new()
	var box := Chrome.flat(Color(0.12, 0.09, 0.07, 0.94), 16, Chrome.HIGH_GOLD, 2)
	box.content_margin_left = 14
	box.content_margin_right = 12
	box.content_margin_top = 3
	box.content_margin_bottom = 3
	row.add_theme_stylebox_override("panel", box)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 1)
	row.add_child(col)

	var line := HBoxContainer.new()
	line.alignment = BoxContainer.ALIGNMENT_CENTER
	line.add_theme_constant_override("separation", 16)
	col.add_child(line)

	var name_lbl := Label.new()
	name_lbl.text = str(item.get("name", ""))
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	Chrome.apply_label(name_lbl, 11, Chrome.CREAM, true)
	line.add_child(name_lbl)

	var price_lbl := Label.new()
	price_lbl.text = Chrome.marks_star_text(int(item.get("price", 0)))
	price_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	Chrome.apply_label(price_lbl, 12, Chrome.HIGH_GOLD, true)
	line.add_child(price_lbl)

	var btn := Chrome.chunk_button("BUY", Chrome.LOADOUT_BLUE, Color.WHITE, Vector2(172, 38))
	btn.pressed.connect(func() -> void: _on_shop_primary(item_id))
	line.add_child(btn)

	var status := Label.new()
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	Chrome.apply_label(status, 8, Color("f0e3b0"), true)
	col.add_child(status)

	_shop_lines[item_id] = {
		"row": row,
		"name": name_lbl,
		"price": price_lbl,
		"btn": btn,
		"status": status,
	}
	return row


func _build_gun_rack() -> void:
	## Plate-cropped family stamps. Owned painted · locked silhouette · equipped gold.
	_gun_rack = Control.new()
	_gun_rack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gun_rack.set_anchors_preset(PRESET_FULL_RECT)
	add_child(_gun_rack)
	_gun_hands = TextureRect.new()
	_gun_hands.texture = ArtPack.rifle_held_texture()
	_gun_hands.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_gun_hands.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_gun_hands.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_gun_hands.position = ArtPack.HELD_POS
	_gun_hands.size = ArtPack.HELD_SIZE
	_gun_hands.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_gun_hands)


func _refresh_gun_rack() -> void:
	if _gun_rack == null:
		return
	for child in _gun_rack.get_children():
		child.queue_free()
	_gun_rack.visible = true
	for family in Contract.gun_family_ids():
		var gid := str(family)
		var state := ClientSession.gun_slot_state(gid)
		var stamp := TextureRect.new()
		stamp.texture = ArtPack.rifle_texture(gid, "locked" if state == "locked" else "owned")
		stamp.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		stamp.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		stamp.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		stamp.position = ArtPack.rack_position(gid)
		stamp.size = ArtPack.rack_size(gid)
		stamp.mouse_filter = Control.MOUSE_FILTER_STOP
		stamp.gui_input.connect(_on_rack_stamp_input.bind(gid))
		_gun_rack.add_child(stamp)
		if state == "equipped":
			var glow := ColorRect.new()
			glow.color = Color(Chrome.HIGH_GOLD, 0.0)
			glow.position = ArtPack.rack_position(gid) + Vector2(-6, ArtPack.rack_size(gid).y - 4)
			glow.size = Vector2(ArtPack.rack_size(gid).x + 12, 5)
			glow.color = Chrome.HIGH_GOLD
			glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_gun_rack.add_child(glow)
	if _gun_hands:
		var family := ClientSession.equipped_gun_id()
		_gun_hands.texture = ArtPack.rifle_held_texture()
		_gun_hands.modulate = ArtPack.optic_accent(family)
		_gun_hands.visible = true


func _on_rack_stamp_input(event: InputEvent, item_id: String) -> void:
	if not (event is InputEventMouseButton):
		return
	var mouse := event as InputEventMouseButton
	if not mouse.pressed or mouse.button_index != MOUSE_BUTTON_LEFT:
		return
	if ClientSession.owns_gun(item_id):
		if not ClientSession.is_equipped(item_id):
			_on_equip_toggle(item_id)
		return
	_toast_msg("Buy %s in ARMORY  ·  visual only" % Contract.gun_family_name(item_id))


func _build_jobs_panel() -> void:
	## Three ARMORY-language rows. T1 stub stays; T2 / T3 are the new ladder.
	_jobs_panel = PanelContainer.new()
	_jobs_panel.visible = false
	_jobs_panel.set_anchors_preset(PRESET_CENTER)
	_jobs_panel.offset_left = -360
	_jobs_panel.offset_right = 360
	_jobs_panel.offset_top = -210
	_jobs_panel.offset_bottom = 210
	var box := Chrome.flat(Color(0.10, 0.08, 0.06, 0.96), 20, Chrome.HIGH_GOLD, 3)
	box.content_margin_left = 22
	box.content_margin_right = 22
	box.content_margin_top = 16
	box.content_margin_bottom = 16
	_jobs_panel.add_theme_stylebox_override("panel", box)
	add_child(_jobs_panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
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
	blurb.text = "Same Attack / Recon / UAV / Decoy vs a scripted seat."
	Chrome.apply_label(blurb, 8, Chrome.CREAM)
	col.add_child(blurb)

	for tier in Contract.JOB_TIERS:
		col.add_child(_make_job_row(int(tier)))

	var back_row := HBoxContainer.new()
	back_row.add_theme_constant_override("separation", 0)
	col.add_child(back_row)
	var cancel := Chrome.chunk_button("BACK", Chrome.INK, Chrome.CREAM, Vector2(160, 40))
	cancel.pressed.connect(_toggle_jobs)
	back_row.add_child(cancel)


func _make_job_row(tier: int) -> PanelContainer:
	var row := PanelContainer.new()
	var box := Chrome.flat(Color(0.12, 0.09, 0.07, 0.94), 16, Chrome.HIGH_GOLD, 2)
	box.content_margin_left = 14
	box.content_margin_right = 12
	box.content_margin_top = 6
	box.content_margin_bottom = 6
	row.add_theme_stylebox_override("panel", box)

	var line := HBoxContainer.new()
	line.alignment = BoxContainer.ALIGNMENT_CENTER
	line.add_theme_constant_override("separation", 16)
	row.add_child(line)

	var name_lbl := Label.new()
	name_lbl.text = Contract.job_row_label(tier)
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	Chrome.apply_label(name_lbl, 11, Chrome.CREAM, true)
	line.add_child(name_lbl)

	var pay := Label.new()
	pay.text = Chrome.marks_star_text(Contract.job_tier_delta(tier))
	pay.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	Chrome.apply_label(pay, 12, Chrome.HIGH_GOLD, true)
	line.add_child(pay)

	var start := Chrome.chunk_button("START", Chrome.JOBS_ORANGE, Color.WHITE, Vector2(148, 44))
	start.pressed.connect(func() -> void: _start_job(tier))
	line.add_child(start)
	return row


func _build_invite_panel() -> void:
	## Wartable / ARMORY language. No ranked queue chrome. No countdown.
	_invite_panel = PanelContainer.new()
	_invite_panel.visible = false
	_invite_panel.set_anchors_preset(PRESET_CENTER)
	_invite_panel.offset_left = -400
	_invite_panel.offset_right = 400
	_invite_panel.offset_top = -230
	_invite_panel.offset_bottom = 230
	var box := Chrome.flat(Color(0.10, 0.08, 0.06, 0.96), 20, Chrome.HIGH_GOLD, 3)
	box.content_margin_left = 22
	box.content_margin_right = 22
	box.content_margin_top = 16
	box.content_margin_bottom = 16
	_invite_panel.add_theme_stylebox_override("panel", box)
	add_child(_invite_panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	_invite_panel.add_child(col)

	_invite_home = VBoxContainer.new()
	_invite_home.add_theme_constant_override("separation", 10)
	col.add_child(_invite_home)

	var kicker := Label.new()
	kicker.text = Contract.LOBBY_KICKER
	Chrome.apply_label(kicker, 8, Chrome.HIGH_GOLD, true)
	_invite_home.add_child(kicker)

	var heading := Label.new()
	heading.text = Contract.LOBBY_HEADING
	Chrome.apply_label(heading, 16, Chrome.CREAM, true)
	_invite_home.add_child(heading)

	var blurb := Label.new()
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.text = Contract.LOBBY_BLURB
	Chrome.apply_label(blurb, 8, Chrome.CREAM)
	_invite_home.add_child(blurb)

	var create := Chrome.chunk_button(Contract.LOBBY_CREATE_COPY, Chrome.HIGH_GOLD, Chrome.INK, Vector2(420, 52))
	create.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	create.pressed.connect(_on_create_lobby)
	_invite_home.add_child(create)

	var join_row := HBoxContainer.new()
	join_row.alignment = BoxContainer.ALIGNMENT_CENTER
	join_row.add_theme_constant_override("separation", 12)
	_invite_home.add_child(join_row)

	_join_edit = LineEdit.new()
	_join_edit.placeholder_text = "CODE"
	_join_edit.max_length = 8
	_join_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_join_edit.custom_minimum_size = Vector2(240, 48)
	_join_edit.add_theme_font_override("font", Chrome.pixel_font())
	_join_edit.add_theme_font_size_override("font_size", 14)
	_join_edit.add_theme_color_override("font_color", Chrome.CREAM)
	_join_edit.add_theme_color_override("font_placeholder_color", Color(0.72, 0.68, 0.58, 0.70))
	var field_box := Chrome.flat(Color(0.12, 0.09, 0.07, 0.94), 16, Chrome.HIGH_GOLD, 2)
	_join_edit.add_theme_stylebox_override("normal", field_box)
	_join_edit.add_theme_stylebox_override("focus", Chrome.flat(Color(0.14, 0.10, 0.08, 0.96), 16, Chrome.HIGH_GOLD, 3))
	_join_edit.text_changed.connect(_on_join_code_changed)
	_join_edit.text_submitted.connect(func(_t: String) -> void: _on_join_lobby())
	_join_edit.focus_entered.connect(_peek_join_clipboard)
	join_row.add_child(_join_edit)

	## Same wood/gold family as COPY on the wait plate. Hidden until a code is on the clipboard.
	_join_paste = Chrome.chunk_button(Contract.LOBBY_PASTE_CODE, Chrome.WOOD_DARK, Chrome.HIGH_GOLD, Vector2(168, 48))
	_join_paste.icon = Chrome.make_icon("clipboard", Chrome.HIGH_GOLD, 28)
	_join_paste.add_theme_constant_override("h_separation", 8)
	_join_paste.add_theme_constant_override("icon_max_width", 22)
	_join_paste.focus_mode = Control.FOCUS_NONE
	_join_paste.visible = false
	_join_paste.disabled = true
	_join_paste.pressed.connect(_on_paste_lobby_code)
	join_row.add_child(_join_paste)

	var join_btn := Chrome.chunk_button(Contract.LOBBY_JOIN_COPY, Chrome.TEAL, Color.WHITE, Vector2(148, 48))
	join_btn.pressed.connect(_on_join_lobby)
	join_row.add_child(join_btn)

	_join_pasted = Label.new()
	_join_pasted.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_join_pasted.visible = false
	Chrome.apply_label(_join_pasted, 10, Chrome.HIGH_GOLD, true)
	_invite_home.add_child(_join_pasted)

	_invite_reject = Label.new()
	_invite_reject.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_invite_reject.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	Chrome.apply_label(_invite_reject, 8, Color("f0e3b0"), true)
	_invite_home.add_child(_invite_reject)

	var back := Chrome.chunk_button(Contract.LOBBY_BACK_COPY, Chrome.INK, Chrome.CREAM, Vector2(160, 40))
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(_close_invite)
	_invite_home.add_child(back)

	_invite_wait = VBoxContainer.new()
	_invite_wait.visible = false
	_invite_wait.add_theme_constant_override("separation", 12)
	col.add_child(_invite_wait)

	var wait_kicker := Label.new()
	wait_kicker.text = Contract.LOBBY_KICKER
	Chrome.apply_label(wait_kicker, 8, Chrome.HIGH_GOLD, true)
	_invite_wait.add_child(wait_kicker)

	var wait_head := Label.new()
	wait_head.text = Contract.LOBBY_CODE_HINT
	Chrome.apply_label(wait_head, 10, Chrome.CREAM, true)
	_invite_wait.add_child(wait_head)

	var code_row := HBoxContainer.new()
	code_row.alignment = BoxContainer.ALIGNMENT_CENTER
	code_row.add_theme_constant_override("separation", 12)
	_invite_wait.add_child(code_row)

	_invite_code_lbl = Label.new()
	_invite_code_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_invite_code_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	Chrome.apply_label(_invite_code_lbl, 26, Chrome.HIGH_GOLD, true)
	code_row.add_child(_invite_code_lbl)

	## Wood/gold chips — same family as the gear strip. Wait plate only.
	var wait_copy := Chrome.chunk_button(Contract.LOBBY_COPY_CODE, Chrome.WOOD_DARK, Chrome.HIGH_GOLD, Vector2(148, 52))
	wait_copy.icon = Chrome.make_icon("copy", Chrome.HIGH_GOLD, 28)
	wait_copy.add_theme_constant_override("h_separation", 8)
	wait_copy.add_theme_constant_override("icon_max_width", 22)
	wait_copy.focus_mode = Control.FOCUS_NONE
	wait_copy.pressed.connect(_on_copy_lobby_code)
	code_row.add_child(wait_copy)

	var wait_share := Chrome.chunk_button(Contract.LOBBY_SHARE_CODE, Chrome.HIGH_GOLD, Chrome.INK, Vector2(164, 52))
	wait_share.icon = Chrome.make_icon("share", Chrome.INK, 28)
	wait_share.add_theme_constant_override("h_separation", 8)
	wait_share.add_theme_constant_override("icon_max_width", 22)
	wait_share.focus_mode = Control.FOCUS_NONE
	wait_share.pressed.connect(_on_share_lobby_code)
	code_row.add_child(wait_share)

	var wait_line := Label.new()
	wait_line.text = Contract.LOBBY_WAIT_COPY
	wait_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	Chrome.apply_label(wait_line, 8, Chrome.CREAM, true)
	_invite_wait.add_child(wait_line)

	_invite_copied_chip = Chrome.pill_chip(Chrome.WOOD_DARK, Chrome.HIGH_GOLD)
	_invite_copied_chip.visible = false
	_invite_copied_chip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_invite_wait.add_child(_invite_copied_chip)
	_invite_copied = Label.new()
	_invite_copied.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	Chrome.apply_label(_invite_copied, 10, Chrome.HIGH_GOLD, true)
	_invite_copied_chip.add_child(_invite_copied)

	var wait_actions := HBoxContainer.new()
	wait_actions.alignment = BoxContainer.ALIGNMENT_CENTER
	wait_actions.add_theme_constant_override("separation", 16)
	_invite_wait.add_child(wait_actions)

	var cancel := Chrome.chunk_button(Contract.LOBBY_CANCEL_COPY, Chrome.INK, Chrome.CREAM, Vector2(160, 40))
	cancel.pressed.connect(_on_cancel_lobby)
	wait_actions.add_child(cancel)


func _build_queue_panel() -> void:
	## Cozy wartable "Finding a rival…" — toy-spy, no MMR / ranked countdown.
	_queue_panel = PanelContainer.new()
	_queue_panel.visible = false
	_queue_panel.set_anchors_preset(PRESET_CENTER)
	_queue_panel.offset_left = -320
	_queue_panel.offset_right = 320
	_queue_panel.offset_top = -190
	_queue_panel.offset_bottom = 190
	var box := Chrome.flat(Color(0.10, 0.08, 0.06, 0.96), 20, Chrome.TEAL, 3)
	box.content_margin_left = 22
	box.content_margin_right = 22
	box.content_margin_top = 16
	box.content_margin_bottom = 16
	_queue_panel.add_theme_stylebox_override("panel", box)
	add_child(_queue_panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	_queue_panel.add_child(col)

	var kicker := Label.new()
	kicker.text = Contract.QUEUE_KICKER
	Chrome.apply_label(kicker, 8, Chrome.HIGH_GOLD, true)
	col.add_child(kicker)

	var heading := Label.new()
	heading.text = Contract.QUEUE_HEADING
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	Chrome.apply_label(heading, 16, Chrome.CREAM, true)
	col.add_child(heading)

	var blurb := Label.new()
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.text = Contract.QUEUE_BLURB
	Chrome.apply_label(blurb, 8, Chrome.CREAM)
	col.add_child(blurb)

	var chip := Chrome.pill_chip(Chrome.INK, Chrome.TEAL)
	col.add_child(chip)
	var wait := Label.new()
	wait.text = Contract.QUEUE_WAIT_COPY
	wait.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	Chrome.apply_label(wait, 10, Chrome.CREAM, true)
	chip.add_child(wait)

	var cancel := Chrome.chunk_button(Contract.QUEUE_CANCEL_COPY, Chrome.INK, Chrome.CREAM, Vector2(200, 44))
	cancel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	cancel.pressed.connect(_on_cancel_queue)
	col.add_child(cancel)


func _build_practice_panel() -> void:
	## Cozy confirm — paper and ink, not queue chrome. No Marks is on the panel before start.
	_practice_panel = PanelContainer.new()
	_practice_panel.visible = false
	_practice_panel.set_anchors_preset(PRESET_CENTER)
	_practice_panel.offset_left = -340
	_practice_panel.offset_right = 340
	_practice_panel.offset_top = -200
	_practice_panel.offset_bottom = 200
	var box := Chrome.flat(Color(0.95, 0.90, 0.78, 0.97), 20, Chrome.INK, 3)
	box.content_margin_left = 22
	box.content_margin_right = 22
	box.content_margin_top = 16
	box.content_margin_bottom = 16
	_practice_panel.add_theme_stylebox_override("panel", box)
	add_child(_practice_panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	_practice_panel.add_child(col)

	var kicker := Label.new()
	kicker.text = Contract.PRACTICE_KICKER
	Chrome.apply_label(kicker, 8, Chrome.INK, true)
	col.add_child(kicker)

	var heading := Label.new()
	heading.text = Contract.PRACTICE_HEADING
	Chrome.apply_label(heading, 16, Chrome.INK, true)
	col.add_child(heading)

	var blurb := Label.new()
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.text = Contract.PRACTICE_BLURB
	Chrome.apply_label(blurb, 8, Chrome.INK)
	col.add_child(blurb)

	var no_marks := Label.new()
	no_marks.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	no_marks.text = Contract.PRACTICE_NO_MARKS
	Chrome.apply_label(no_marks, 10, Chrome.INK, true)
	col.add_child(no_marks)

	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 16)
	col.add_child(actions)

	var start := Chrome.chunk_button(Contract.PRACTICE_START, Chrome.PLAY_GREEN, Color.WHITE, Vector2(280, 52))
	start.pressed.connect(_start_practice)
	actions.add_child(start)

	var back := Chrome.chunk_button(Contract.PRACTICE_BACK, Chrome.INK, Chrome.CREAM, Vector2(180, 52))
	back.pressed.connect(_close_practice)
	actions.add_child(back)


func _build_gear_strip() -> void:
	_gear = GearStrip.new()
	_gear.tips_reset.connect(_on_tips_reset)
	add_child(_gear)


func _on_tips_reset() -> void:
	_toast_msg(Contract.GEAR_CONFIRM_COPY)


func _capture_gear(muted: bool, confirm: bool) -> void:
	if _shop_row:
		_shop_row.visible = false
	AudioJuice.set_muted(muted)
	if _gear:
		_gear.refresh_mute()
		if confirm:
			_gear.press_reset()
	var path := "res://artifacts/ux/gear_strip_live.png"
	var tag := "S1_GEAR_LIVE"
	if confirm:
		path = "res://artifacts/ux/gear_strip_confirm.png"
		tag = "S4_GEAR_CONFIRM"
	elif muted:
		path = "res://artifacts/ux/gear_strip_muted.png"
		tag = "S2_GEAR_MUTED"
	await _capture_named(path, tag)


func _build_journal_plate() -> void:
	_journal_plate = JournalPlate.new()
	_journal_plate.visible = false
	_journal_plate.z_index = 40
	_journal_plate.practice_again.connect(_start_practice)
	_journal_plate.rematch_match.connect(_journal_rematch)
	_journal_plate.closed.connect(_on_journal_closed)
	add_child(_journal_plate)


func _bind_wallet() -> void:
	var wallet: Dictionary = MatchAPI.wallet()
	if wallet.has("marks"):
		ClientSession.bind_marks(int(wallet.get("marks")))
	if wallet.has("owned") or wallet.has("equipped") or wallet.has("equippedSkinId") \
			or wallet.has("equippedDecorId") or wallet.has("equippedGunId") \
			or wallet.has("ownedGuns") or wallet.has("you"):
		ClientSession.apply_shop(wallet)


func _bind_shop() -> void:
	var bag: Dictionary = MatchAPI.get_shop()
	ClientSession.apply_shop(bag)
	if ClientSession.use_live_api():
		var me: Dictionary = MatchAPI.get_shop_me()
		if str(me.get("error", "")) == "":
			ClientSession.apply_shop(me)
	_refresh_shop()


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
			if _toast and _toast.text == "":
				_toast_msg(_last_pay.text)


func _refresh_bg() -> void:
	var path := "res://assets/canon/lobby-ghillie.jpg" if ClientSession.ghillie else "res://assets/canon/lobby-canon.jpg"
	var src: Texture2D = load(path)
	_bg.texture = _plate_without_baked_chrome(src)
	if _bandana_wash:
		_bandana_wash.visible = ClientSession.bandana and not ClientSession.ghillie
	if _poster:
		_poster.visible = ClientSession.poster


func _plate_without_baked_chrome(src: Texture2D) -> Texture2D:
	## Stamp wall/floor wood over the plate's baked HUD + dock so live chrome can sit on the room.
	if src == null:
		return src
	var img := src.get_image()
	if img == null:
		return src
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	var w := img.get_width()
	var h := img.get_height()
	## Patch from open wall (left of operative, under the rifles).
	## Open wall left of the operative mid-torso — skip jacket, beanbag, rifles.
	var px := clampi(int(w * 0.34), 0, w - 2)
	var py := clampi(int(h * 0.47), 0, h - 2)
	var pw := mini(96, w - px)
	var ph := mini(48, h - py)
	## Island stamps under live chips only — not a full-width brown bar.
	_stamp_wood(img, 0, 0, mini(400, w), mini(122, h), px, py, pw, ph)
	## Cover baked gold / gem — Marks ★ is the only still chip.
	_stamp_wood(img, maxi(0, w - 420), 0, w, mini(70, h), px, py, pw, ph)
	_stamp_wood(img, 0, maxi(0, h - 220), w, h, px, py, pw, ph)
	## Leave the plate's olive / tan / teal rifles. They ARE the Fieldbolt family.
	var wood := img.get_pixel(px, py)
	for cover in _wood_covers:
		cover.color = wood
	return ImageTexture.create_from_image(img)


func _stamp_wood(img: Image, x0: int, y0: int, x1: int, y1: int, px: int, py: int, pw: int, ph: int) -> void:
	if pw <= 0 or ph <= 0:
		return
	for y in range(y0, y1):
		for x in range(x0, x1):
			img.set_pixel(x, y, img.get_pixel(px + posmod(x - x0, pw), py + posmod(y - y0, ph)))


func _focus_shop() -> void:
	if _queue_waiting:
		return
	if _shop_row:
		_shop_row.visible = true
	## Soft P2: LOADOUT opens ARMORY rows. No inventory-dump ribbon in LIVE play.
	_debug_status_toast(Chrome.armory_debug_ribbon())


func _refresh_shop() -> void:
	## LIVE and mock both go through MatchAPI.get_shop / buy_shop.
	var bag = Shop.from_any(MatchAPI.get_shop())
	_ensure_shop_lines(bag.items)
	if _shop_lines.is_empty():
		return
	for item_id in _shop_lines.keys():
		var widgets: Dictionary = _shop_lines[item_id]
		var name_lbl: Label = widgets.get("name")
		var price_lbl: Label = widgets.get("price")
		var btn: Button = widgets.get("btn")
		var status: Label = widgets.get("status")
		if name_lbl:
			name_lbl.text = bag.name_of(str(item_id))
		var price: int = int(bag.price_of(str(item_id)))
		if price_lbl:
			if Contract.is_gun_chrome(str(item_id)) and price <= 0:
				price_lbl.text = Contract.GUN_STARTER_COPY
			else:
				price_lbl.text = Chrome.marks_star_text(price)
		var owned: bool = ClientSession.owns_cosmetic(str(item_id))
		var equipped: bool = ClientSession.is_equipped(str(item_id))
		var can_buy: bool = int(ClientSession.marks) >= price
		var buying: bool = _buying_id == str(item_id)
		if btn:
			btn.text = Shop.row_action_text(owned, equipped)
			btn.disabled = not Shop.row_buy_enabled(owned, can_buy, buying)
			if equipped:
				Chrome.paint_chunk_button(btn, Color("2a241c"), Chrome.HIGH_GOLD)
			elif owned:
				Chrome.paint_chunk_button(btn, Chrome.TEAL, Color.WHITE)
			elif can_buy:
				Chrome.paint_chunk_button(btn, Chrome.LOADOUT_BLUE, Color.WHITE)
			else:
				Chrome.paint_chunk_button(btn, Color("3a322c"), Color(0.72, 0.68, 0.58, 0.70))
		if status:
			status.text = Shop.row_status_text(owned, can_buy, equipped)
	_refresh_bg()
	_refresh_gun_rack()


func _ensure_shop_lines(items: Array) -> void:
	## Render catalog rows from GET /shop (or mock stub). Do not hardcode a two-row cap.
	var source: Array = items
	if source.is_empty():
		source = Contract.shop_catalog_items()
	if _shop_col == null:
		return
	for entry in source:
		if not (entry is Dictionary):
			continue
		var item_id := str(entry.get("id", entry.get("itemId", "")))
		if item_id == "" or _shop_lines.has(item_id):
			continue
		var line := _make_shop_line(entry)
		if Contract.is_gun_chrome(item_id) and _gun_kicker != null:
			_shop_col.add_child(line)
		elif _gun_kicker != null:
			_shop_col.add_child(line)
			_shop_col.move_child(line, _gun_kicker.get_index())
		else:
			_shop_col.add_child(line)


func _on_shop_primary(item_id: String) -> void:
	if _buying_id != "":
		return
	if ClientSession.owns_cosmetic(item_id):
		_on_equip_toggle(item_id)
		return
	if ClientSession.use_live_api():
		MatchAPI.ensure_player()
	_buying_id = item_id
	var widgets: Dictionary = _shop_lines.get(item_id, {})
	var btn: Button = widgets.get("btn")
	var status: Label = widgets.get("status")
	if btn:
		btn.disabled = true
	var buy_id := Contract.new_client_buy_id()
	var body: Dictionary = MatchAPI.buy_shop(item_id, buy_id)
	var shop = Shop.from_any(body)
	## Snapshot / buy you.marks is sole Marks truth — never marks -= on this client.
	ClientSession.apply_shop(body)
	_refresh_marks()
	_buying_id = ""
	if shop.is_insufficient():
		if status:
			status.text = Contract.SHOP_INSUFFICIENT_COPY
		_toast_msg("ARMORY rejected  ·  insufficient_marks")
	elif shop.is_unavailable() or shop.error == Contract.SHOP_ERR_UNKNOWN_ITEM:
		if status:
			status.text = "LIVE shop not ready" if shop.is_unavailable() else str(shop.error)
		_toast_msg("LIVE catalog missing  ·  mock ARMORY on F2")
	elif not shop.ok:
		if status:
			status.text = str(shop.error)
		_toast_msg("ARMORY rejected  ·  %s" % shop.error)
	else:
		if status:
			status.text = Contract.SHOP_EQUIPPED_COPY
		## Soft P2: no floating Bought / wearing / visual stack — ARMORY row is the one line.
		_toast_msg("")
	_refresh_shop()


func _on_equip_toggle(item_id: String) -> void:
	if not ClientSession.owns_cosmetic(item_id):
		_toast_msg("Buy %s in ARMORY." % Shop.from_any({}).name_of(item_id))
		return
	var marks_before := int(ClientSession.marks)
	var next_id := "" if ClientSession.is_equipped(item_id) else item_id
	var slot := "skin"
	if Contract.is_gun_chrome(item_id):
		slot = Contract.GUN_SLOT
	elif Contract.is_decor_chrome(item_id):
		slot = "decor"
	var body: Dictionary = MatchAPI.equip_cosmetic(next_id, slot)
	var shop = Shop.from_any(body)
	if shop.ok:
		## Snapshot is the only equipped id. Never invent a skin.
		ClientSession.apply_shop(body)
	elif ClientSession.use_live_api() and shop.is_unavailable():
		## Coder /shop/equip 404 — local chrome only, documented blocker.
		ClientSession.bind_equip_local(next_id, slot)
		_toast_msg("LIVE /shop/equip pending Coder  ·  local chrome")
		_refresh_shop()
		return
	elif shop.is_not_owned() or not shop.ok:
		ClientSession.apply_shop(body)
		_toast_msg("Need to own that chrome first.")
		_refresh_shop()
		return
	_refresh_marks()
	_refresh_shop()
	if int(ClientSession.marks) != marks_before:
		_toast_msg("Marks chip rebound from snapshot")
	else:
		## Soft P2: EQUIP / EQUIPPED / OWNED row copy is the single wear status.
		_toast_msg("")


func _toggle_suit() -> void:
	var owned: Array = []
	for item in Contract.shop_catalog_items():
		if item is Dictionary:
			var sid := str(item.get("id", ""))
			if sid != "" and Contract.is_suit_chrome(sid) and ClientSession.owns_cosmetic(sid):
				owned.append(sid)
	if owned.is_empty():
		_toast_msg("Buy Ghillie, Bandana, or Hideout Poster in ARMORY")
		return
	var cycle: Array = [""]
	cycle.append_array(owned)
	var idx := cycle.find(ClientSession.equipped_cosmetic)
	var next_id := str(cycle[(idx + 1) % cycle.size()])
	if next_id == "":
		_on_equip_toggle(str(ClientSession.equipped_cosmetic))
	else:
		_on_equip_toggle(next_id)


func _toast_msg(text: String) -> void:
	_toast.text = text


func _debug_status_toast(text: String) -> void:
	## Soft P2: ARMORY · Fieldbolt owned… / RACK · Fieldbolt equipped… stay gated.
	_toast_msg(text if Chrome.debug_status_ribbons() else "")


func _toggle_jobs() -> void:
	if _queue_waiting:
		return
	_close_journal()
	if _invite_panel and _invite_panel.visible and _lobby_waiting:
		return
	if _invite_panel:
		_invite_panel.visible = false
	if _practice_panel:
		_practice_panel.visible = false
	_jobs_panel.visible = not _jobs_panel.visible
	if _shop_row:
		_shop_row.visible = not _jobs_panel.visible
	if _jobs_panel.visible:
		_toast_msg("T1 ★10   ·   T2 ★15   ·   T3 ★20")


func _toggle_invite() -> void:
	if _queue_waiting:
		return
	if _lobby_waiting and _invite_panel and _invite_panel.visible:
		return
	if _invite_panel and _invite_panel.visible:
		_close_invite()
		return
	_open_invite()


func _open_invite() -> void:
	_close_journal()
	if _jobs_panel:
		_jobs_panel.visible = false
	if _practice_panel:
		_practice_panel.visible = false
	if _shop_row:
		_shop_row.visible = false
	if _invite_panel:
		_invite_panel.visible = true
	_show_invite_home()
	if _invite_reject:
		_invite_reject.text = ""
	_toast_msg("")


func _close_invite() -> void:
	_lobby_waiting = false
	_lobby_poll = 0.0
	if _invite_panel:
		_invite_panel.visible = false
	_clear_pasted_toast()
	_show_invite_home()
	if _shop_row:
		_shop_row.visible = true
	if _jobs_panel:
		_jobs_panel.visible = false


func _show_invite_home() -> void:
	if _invite_home:
		_invite_home.visible = true
	if _invite_wait:
		_invite_wait.visible = false
	if _invite_reject:
		_invite_reject.text = ""
	_clear_code_copied()
	_clear_pasted_toast()
	_peek_join_clipboard()


func _show_invite_wait() -> void:
	_clear_pasted_toast()
	if _invite_home:
		_invite_home.visible = false
	if _invite_wait:
		_invite_wait.visible = true
	if _invite_code_lbl:
		_invite_code_lbl.text = Contract.lobby_code_display(ClientSession.lobby_code)
	_clear_code_copied()
	_lobby_waiting = true
	_lobby_poll = 0.0


func _clear_code_copied() -> void:
	if _invite_copied:
		_invite_copied.text = ""
	if _invite_copied_chip:
		_invite_copied_chip.visible = false


func _show_code_copied() -> void:
	if _invite_copied:
		_invite_copied.text = Contract.LOBBY_COPIED_COPY
	if _invite_copied_chip:
		_invite_copied_chip.visible = true
	_toast_msg(Contract.LOBBY_COPIED_COPY)


func _on_join_code_changed(text: String) -> void:
	var norm := Contract.normalize_lobby_code(text)
	if _join_edit and _join_edit.text != norm:
		_join_edit.text = norm
		_join_edit.caret_column = norm.length()
	if _invite_reject and _invite_reject.text != "":
		_invite_reject.text = ""
	_clear_pasted_toast()


func _on_create_lobby() -> void:
	if ClientSession.use_live_api():
		var health: Dictionary = MatchAPI.health()
		if not bool(health.get("ok", false)):
			_toast_msg("Live API down at %s  (GET /health)" % ClientSession.api_base_url())
			return
		MatchAPI.ensure_player()
	var body: Dictionary = MatchAPI.create_lobby()
	var lobby = Lobby.from_any(body)
	if lobby.has_marks:
		ClientSession.bind_marks(lobby.marks)
		_refresh_marks()
	if lobby.is_unavailable():
		if _invite_reject:
			_invite_reject.text = Contract.LOBBY_UNAVAILABLE_COPY
		_toast_msg("LIVE /lobbies pending Coder  ·  mock INVITE on F2")
		return
	if not lobby.is_waiting() or str(lobby.lobby_id) == "" or str(lobby.code) == "":
		if _invite_reject:
			_invite_reject.text = lobby.reject_copy()
		_toast_msg("Invite failed  ·  %s" % lobby.error)
		return
	ClientSession.lobby_id = lobby.lobby_id
	ClientSession.lobby_code = lobby.code
	ClientSession.lobby_seat = lobby.seat if lobby.seat != "" else Contract.SEAT_A
	_show_invite_wait()
	_toast_msg("")


func _join_form_open() -> bool:
	return _invite_panel != null and _invite_panel.visible \
			and _invite_home != null and _invite_home.visible


func _peek_join_clipboard() -> void:
	## One read when the join form is open. Does not write the field or call join.
	if not _join_form_open():
		_set_paste_offer("")
		return
	var code := LobbyPaste.peek_code()
	_set_paste_offer(code)
	if not Contract.is_lobby_code(code):
		_clear_pasted_toast()


func _clear_pasted_toast() -> void:
	## Soft P2: Pasted. only after a PASTE tap this visit.
	_set_pasted_note(false)
	if _toast != null and _toast.text == Contract.LOBBY_PASTED_COPY:
		_toast_msg("")


func _set_pasted_note(on: bool) -> void:
	if _join_pasted == null:
		return
	_join_pasted.text = Contract.LOBBY_PASTED_COPY if on else ""
	_join_pasted.visible = on


func _set_paste_offer(code: String) -> void:
	_join_paste_code = code if Contract.is_lobby_code(code) else ""
	if _join_paste == null:
		return
	var offered := _join_paste_code != ""
	_join_paste.visible = offered
	_join_paste.disabled = not offered
	if not offered:
		_clear_pasted_toast()


func _on_paste_lobby_code() -> void:
	## Chip tap fills the field. Join stays on the JOIN button.
	if not Contract.is_lobby_code(_join_paste_code) or _join_edit == null:
		_set_paste_offer("")
		return
	var filled := LobbyPaste.fill_text(_join_edit.text, _join_paste_code)
	_join_edit.text = filled
	_join_edit.caret_column = filled.length()
	_set_pasted_note(true)
	_toast_msg(Contract.LOBBY_PASTED_COPY)


func _on_join_lobby() -> void:
	var typed := ""
	if _join_edit:
		typed = _join_edit.text
	if ClientSession.use_live_api():
		var health: Dictionary = MatchAPI.health()
		if not bool(health.get("ok", false)):
			_toast_msg("Live API down at %s  (GET /health)" % ClientSession.api_base_url())
			return
		MatchAPI.ensure_player()
	var body: Dictionary = MatchAPI.join_lobby(typed)
	var lobby = Lobby.from_any(body)
	if lobby.has_marks:
		ClientSession.bind_marks(lobby.marks)
		_refresh_marks()
	if lobby.is_ready():
		_enter_lobby_match(body)
		return
	## Plain reject. Field stays editable — no soft lock.
	if _invite_reject:
		_invite_reject.text = lobby.reject_copy()
	_toast_msg("")
	if _join_edit:
		_join_edit.editable = true
		_join_edit.grab_focus()


func _on_copy_lobby_code() -> void:
	## Same lobby code already on the plate. Clipboard gets the 6-char form.
	if not InviteShare.copy_code(ClientSession.lobby_code):
		return
	_show_code_copied()


func _on_share_lobby_code() -> void:
	## OS share sheet with the short blurb. Desktop copies that blurb and toasts.
	var mode := InviteShare.share_code(ClientSession.lobby_code)
	if mode == InviteShare.RESULT_NONE:
		return
	if mode == InviteShare.RESULT_CLIPBOARD:
		_show_code_copied()


func _on_cancel_lobby() -> void:
	var lid := ClientSession.lobby_id
	var marks_before := int(ClientSession.marks)
	if lid != "":
		var body: Dictionary = MatchAPI.cancel_lobby(lid)
		var lobby = Lobby.from_any(body)
		if lobby.has_marks:
			ClientSession.bind_marks(lobby.marks)
	ClientSession.lobby_id = ""
	ClientSession.lobby_code = ""
	ClientSession.lobby_seat = ""
	_lobby_waiting = false
	_close_invite()
	_refresh_marks()
	if int(ClientSession.marks) != marks_before:
		_toast_msg("Marks chip rebound from snapshot")
	else:
		_toast_msg(Contract.LOBBY_HIDEOUT_COPY)


func _poll_lobby() -> void:
	if ClientSession.lobby_id == "":
		return
	var body: Dictionary = MatchAPI.get_lobby(ClientSession.lobby_id)
	var lobby = Lobby.from_any(body)
	if lobby.has_marks:
		ClientSession.bind_marks(lobby.marks)
		_refresh_marks()
	if lobby.is_ready():
		_enter_lobby_match(body)
		return
	if lobby.is_expired() or lobby.is_reject():
		_lobby_waiting = false
		_show_invite_home()
		if _invite_reject:
			_invite_reject.text = lobby.reject_copy()
		_toast_msg(lobby.reject_copy())
		ClientSession.lobby_id = ""
		ClientSession.lobby_code = ""


func _enter_lobby_match(body: Dictionary) -> void:
	_lobby_waiting = false
	var snap: Dictionary = MatchAPI.bind_lobby_match(body)
	if ClientSession.match_id == "" or snap.is_empty():
		_toast_msg("Invite ready but bind failed")
		_show_invite_home()
		return
	if _invite_panel:
		_invite_panel.visible = false
	get_tree().change_scene_to_file("res://scenes/match/match_screen.tscn")


func _on_quick_match() -> void:
	if _queue_waiting:
		return
	if _lobby_waiting:
		return
	_close_journal()
	if ClientSession.use_live_api():
		var health: Dictionary = MatchAPI.health()
		if not bool(health.get("ok", false)):
			_toast_msg("Live API down at %s  (GET /health)" % ClientSession.api_base_url())
			return
		MatchAPI.ensure_player()
	var body: Dictionary = MatchAPI.enqueue()
	var q = Queue.from_any(body)
	if q.has_marks:
		ClientSession.bind_marks(q.marks)
		_refresh_marks()
	if q.is_unavailable():
		_toast_msg("LIVE /queue pending Coder  ·  mock QUICK MATCH on F2")
		return
	if q.code_name == Contract.QUEUE_ERR_IN_MATCH:
		_toast_msg("Already in a hunt.")
		return
	if q.code_name == Contract.QUEUE_ERR_IN_LOBBY:
		_toast_msg("Finish the invite first.")
		return
	if q.is_matched():
		_enter_queue_match(body)
		return
	if not q.is_queued():
		_toast_msg("Queue failed  ·  %s" % q.error)
		return
	_show_queue_wait()


func _show_queue_wait() -> void:
	if _jobs_panel:
		_jobs_panel.visible = false
	if _invite_panel:
		_invite_panel.visible = false
	if _shop_row:
		_shop_row.visible = false
	if _queue_panel:
		_queue_panel.visible = true
	_queue_waiting = true
	ClientSession.queueing = true
	_queue_poll = 0.0
	_queue_elapsed = 0.0
	_toast_msg("")


func _close_queue() -> void:
	_queue_waiting = false
	ClientSession.queueing = false
	_queue_poll = 0.0
	_queue_elapsed = 0.0
	if _queue_panel:
		_queue_panel.visible = false
	if _shop_row:
		_shop_row.visible = true
	if _jobs_panel:
		_jobs_panel.visible = false


func _on_cancel_queue() -> void:
	var marks_before := int(ClientSession.marks)
	var body: Dictionary = MatchAPI.dequeue()
	var q = Queue.from_any(body)
	if q.has_marks:
		ClientSession.bind_marks(q.marks)
	_close_queue()
	_refresh_marks()
	if int(ClientSession.marks) != marks_before:
		_toast_msg("Marks chip rebound from snapshot")
	else:
		_toast_msg(Contract.QUEUE_HIDEOUT_COPY)


func _on_queue_timeout() -> void:
	var marks_before := int(ClientSession.marks)
	var body: Dictionary = MatchAPI.dequeue()
	var q = Queue.from_any(body)
	if q.has_marks:
		ClientSession.bind_marks(q.marks)
	_close_queue()
	_refresh_marks()
	if int(ClientSession.marks) != marks_before:
		_toast_msg("Marks chip rebound from snapshot")
	else:
		_toast_msg(Contract.QUEUE_TIMEOUT_COPY)


func _poll_queue() -> void:
	if not _queue_waiting:
		return
	var body: Dictionary = MatchAPI.get_queue()
	var q = Queue.from_any(body)
	if q.has_marks:
		ClientSession.bind_marks(q.marks)
		_refresh_marks()
	if q.is_matched():
		_enter_queue_match(body)
		return
	if q.is_timeout() or q.is_unavailable():
		_close_queue()
		_toast_msg(q.reject_copy())
		return
	if q.is_idle():
		_close_queue()
		_toast_msg(Contract.QUEUE_HIDEOUT_COPY)


func _enter_queue_match(body: Dictionary) -> void:
	_queue_waiting = false
	ClientSession.queueing = false
	var snap: Dictionary = MatchAPI.bind_queue_match(body)
	if ClientSession.match_id == "" or snap.is_empty():
		_toast_msg("Queue ready but bind failed")
		_close_queue()
		return
	if _queue_panel:
		_queue_panel.visible = false
	get_tree().change_scene_to_file.call_deferred("res://scenes/match/match_screen.tscn")


func _notification(what: int) -> void:
	if what != NOTIFICATION_WM_WINDOW_FOCUS_IN and what != NOTIFICATION_APPLICATION_FOCUS_IN:
		return
	if not _join_form_open():
		return
	_peek_join_clipboard()


func _process(delta: float) -> void:
	if _queue_waiting:
		_queue_elapsed += delta
		if _queue_elapsed >= float(Contract.QUEUE_TTL_SEC):
			_on_queue_timeout()
			return
		_queue_poll += delta
		if _queue_poll >= 1.0:
			_queue_poll = 0.0
			_poll_queue()
		return
	if not _lobby_waiting:
		return
	_lobby_poll += delta
	if _lobby_poll < 1.0:
		return
	_lobby_poll = 0.0
	_poll_lobby()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F2:
		_toggle_live()


func _toggle_live() -> void:
	ClientSession.live_override = 0 if ClientSession.use_live_api() else 1
	if ClientSession.use_live_api():
		MatchAPI.ensure_player()
	_refresh_mode()
	_bind_wallet()
	_bind_shop()
	_refresh_marks()
	_refresh_shop()


func _refresh_mode() -> void:
	if ClientSession.use_live_api():
		_mode_lbl.text = "LIVE  %s" % ClientSession.api_base_url()
		_mode_btn.text = "LIVE"
		_mode_btn.tooltip_text = ClientSession.api_base_url()
	else:
		_mode_lbl.text = "OFFLINE MOCK"
		_mode_btn.text = "MOCK"
		_mode_btn.tooltip_text = "Offline mock"


func _on_play() -> void:
	if _queue_waiting:
		return
	_start_match(Contract.MODE_PVP)


func _open_practice() -> void:
	if _queue_waiting or _lobby_waiting:
		return
	_close_journal()
	if _jobs_panel:
		_jobs_panel.visible = false
	if _invite_panel:
		_invite_panel.visible = false
	if _shop_row:
		_shop_row.visible = false
	if _practice_panel:
		_practice_panel.visible = true
	_toast_msg("")


func _close_practice() -> void:
	if _practice_panel:
		_practice_panel.visible = false
	if _shop_row and not _queue_waiting and not _lobby_waiting:
		_shop_row.visible = true


func _capture_practice_cta() -> void:
	_close_practice()
	if _shop_row:
		_shop_row.visible = false
	await _capture_named("res://artifacts/ux/practice_cta.png", "P6_PRACTICE_CTA")


func _capture_practice_no_marks() -> void:
	_open_practice()
	await _capture_named("res://artifacts/ux/practice_no_marks.png", "P6_PRACTICE_NO_MARKS")


func _open_journal() -> void:
	if _queue_waiting or _lobby_waiting:
		return
	if _jobs_panel:
		_jobs_panel.visible = false
	if _invite_panel and not _lobby_waiting:
		_invite_panel.visible = false
	if _practice_panel:
		_practice_panel.visible = false
	if _queue_panel:
		_queue_panel.visible = false
	if _shop_row:
		_shop_row.visible = false
	if _journal_plate == null:
		return
	if _dock:
		_dock.visible = false
	_journal_plate.open()
	_journal_plate.bind(MatchAPI.get_journal())
	_toast_msg("")


func _close_journal() -> void:
	if _journal_plate and _journal_plate.visible:
		_journal_plate.close()


func _on_journal_closed() -> void:
	if _dock and not _queue_waiting:
		_dock.visible = true
	if _shop_row and not _queue_waiting and not _lobby_waiting:
		if _jobs_panel == null or not _jobs_panel.visible:
			if _invite_panel == null or not _invite_panel.visible:
				if _practice_panel == null or not _practice_panel.visible:
					_shop_row.visible = true


func _journal_rematch(match_id: String) -> void:
	## Same rematch POST as the end overlay. Practice rows never land here.
	if match_id == "":
		return
	_close_journal()
	var body: Dictionary = MatchAPI.rematch_match(match_id, true)
	if not ClientSession.use_live_api():
		var st := _journal_rematch_status(body)
		if st == Contract.REMATCH_WAITING:
			var other := MockMatchServer.other_player_id(match_id, ClientSession.player_id)
			if other != "":
				ClientSession.dummy_player_id = other
				var dummy_body: Dictionary = MatchAPI.rematch_as(other, true)
				var dummy_join := str(dummy_body.get("joinToken", ""))
				if dummy_join != "":
					ClientSession.dummy_token = dummy_join
				body = MatchAPI.rematch(true)
	var status := _journal_rematch_status(body)
	if status == Contract.REMATCH_READY:
		MatchAPI.bind_new_match(body)
		get_tree().change_scene_to_file("res://scenes/match/match_screen.tscn")
		return
	_open_journal()
	if status == Contract.REMATCH_WAITING:
		_toast_msg(Contract.JOURNAL_WAIT_COPY)
	elif str(body.get("error", "")) != "" or status in [Contract.REMATCH_DECLINED, Contract.REMATCH_EXPIRED]:
		_toast_msg(Contract.JOURNAL_CLOSED_COPY)


func _journal_rematch_status(body: Dictionary) -> String:
	var st := str(body.get("status", ""))
	if st == "" or st.is_valid_int():
		var rem: Variant = body.get("rematch", {})
		if rem is Dictionary:
			st = str(rem.get("status", ""))
	return st


func _capture_journal_empty() -> void:
	if not ClientSession.use_live_api():
		MockMatchServer.clear_all()
	if _shop_row:
		_shop_row.visible = false
	_open_journal()
	await _capture_named("res://artifacts/ux/journal_empty.png", "J5_JOURNAL_EMPTY")


func _capture_journal_rows() -> void:
	if not ClientSession.use_live_api():
		_seed_journal_rows()
	if _shop_row:
		_shop_row.visible = false
	_open_journal()
	await _capture_named("res://artifacts/ux/journal_rows.png", "J1_JOURNAL_ROWS")


func _capture_journal_muted() -> void:
	if not ClientSession.use_live_api():
		_seed_journal_muted()
	if _shop_row:
		_shop_row.visible = false
	_open_journal()
	await _capture_named("res://artifacts/ux/journal_muted.png", "J3_JOURNAL_MUTED")


func _seed_journal_rows() -> void:
	## Three ledger rows for the still. Practice Δ0, a quick win, a quick loss.
	MockMatchServer.clear_all()
	MockMatchServer.reset_wallet(24)
	MockMatchServer.test_now_ms = 1000
	_end_seed_match(Contract.MODE_PVP, Contract.SEAT_B, Contract.END_KILL)
	MockMatchServer.test_now_ms = 2000
	_end_seed_match(Contract.MODE_PVP, Contract.SEAT_A, Contract.END_KILL)
	MockMatchServer.test_now_ms = 3000
	_end_seed_match(Contract.MODE_PRACTICE, Contract.SEAT_A, Contract.END_KILL)
	MockMatchServer.test_now_ms = 3000


func _seed_journal_muted() -> void:
	## Older PvP rematch window is closed. Practice again on the new row stays live.
	MockMatchServer.clear_all()
	MockMatchServer.reset_wallet(24)
	MockMatchServer.test_now_ms = 1000
	_end_seed_match(Contract.MODE_PVP, Contract.SEAT_A, Contract.END_KILL)
	MockMatchServer.test_now_ms = 1000 + Contract.REMATCH_TIMEOUT_MS + 50
	_end_seed_match(Contract.MODE_PRACTICE, Contract.SEAT_B, Contract.END_FORFEIT)


func _end_seed_match(mode: String, winner: String, reason: String) -> void:
	var created: Dictionary = MockMatchServer.create_match({"mode": mode})
	var mid := str(created.get("matchId", ""))
	if mode == Contract.MODE_PRACTICE:
		MockMatchServer.join(mid, Contract.create_join_token(created))
	else:
		var tokens: Dictionary = created.get("joinTokens", {})
		MockMatchServer.join(mid, str(tokens.get("a", "")))
		MockMatchServer.join(mid, str(tokens.get("b", "")))
	MockMatchServer.force_end(mid, winner, reason)


func _start_practice() -> void:
	## POST /matches { mode: practice } then sit seat A with the create joinToken.
	## Seat B is the server bot — this client never claims it.
	if _queue_waiting or _lobby_waiting:
		return
	_close_journal()
	if _practice_panel:
		_practice_panel.visible = false
	MatchAPI.clear_all()
	ClientSession.reset_match()
	ClientSession.match_mode = Contract.MODE_PRACTICE
	if ClientSession.use_live_api():
		var health: Dictionary = MatchAPI.health()
		if not bool(health.get("ok", false)):
			ClientSession.reset_match()
			_toast_msg("Live API down at %s  (GET /health)" % ClientSession.api_base_url())
			return
		MatchAPI.ensure_player()
	var created: Dictionary = MatchAPI.create_match({"mode": Contract.MODE_PRACTICE})
	if not Contract.practice_envelope_ok(created):
		ClientSession.reset_match()
		_toast_msg(Contract.PRACTICE_UNAVAILABLE_COPY)
		return
	## LIVE practice create echoes mode. Older bodies omit it — peek the snapshot then.
	## A PvP snap, or a missing bot, never enters the hunt.
	var named := str(created.get("mode", created.get("kind", "")))
	if named != Contract.MODE_PRACTICE:
		ClientSession.match_id = str(created.get("matchId", ""))
		ClientSession.join_token = Contract.create_join_token(created)
		ClientSession.seat = Contract.create_seat(created)
		var peek: Dictionary = MatchAPI.get_snapshot(ClientSession.match_id, "")
		if not Contract.practice_snapshot_ok(peek):
			ClientSession.reset_match()
			MatchAPI.clear_all()
			_toast_msg(Contract.PRACTICE_UNAVAILABLE_COPY)
			return
	var seated: Dictionary = MatchAPI.sit_created_pvp(created, false)
	if seated.has("error"):
		ClientSession.reset_match()
		_toast_msg("Join failed: %s" % str(seated.get("error", "")))
		return
	ClientSession.dummy_player_id = ""
	ClientSession.dummy_token = ""
	var human: Dictionary = seated.get("human", {})
	if not (human is Dictionary):
		human = {}
	var ready_snap: Dictionary = MatchAPI.get_snapshot(ClientSession.match_id, ClientSession.player_id)
	if ready_snap.is_empty():
		ready_snap = human.get("snapshot", {})
	if not Contract.practice_snapshot_ok(ready_snap):
		ClientSession.reset_match()
		MatchAPI.clear_all()
		_toast_msg(Contract.PRACTICE_UNAVAILABLE_COPY)
		return
	ClientSession.apply_snapshot(ready_snap)
	MatchAPI.start_events()
	get_tree().change_scene_to_file("res://scenes/match/match_screen.tscn")


func _on_start_job() -> void:
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
		MatchAPI.ensure_player()
	var created: Dictionary = MatchAPI.create_match({
		"mode": mode,
		"job": mode == Contract.MODE_SP_JOB,
		"sp": mode == Contract.MODE_SP_JOB,
		"jobTier": 1,
	})
	var match_id := str(created.get("matchId", ""))
	var join_tok := Contract.create_join_token(created)
	if match_id == "" or join_tok == "":
		_toast_msg("Create failed: %s" % str(created.get("error", "no matchId")))
		return
	var seated: Dictionary = MatchAPI.sit_created_pvp(created)
	if seated.has("error"):
		_toast_msg("Join failed: %s" % str(seated.get("error", "")))
		return
	var human: Dictionary = seated.get("human", {})
	if not (human is Dictionary):
		human = {}
	var ready_snap: Dictionary = MatchAPI.get_snapshot(match_id, ClientSession.player_id)
	if ready_snap.is_empty():
		ready_snap = human.get("snapshot", {})
	ClientSession.apply_snapshot(ready_snap)
	MatchAPI.start_events()
	get_tree().change_scene_to_file("res://scenes/match/match_screen.tscn")


func _start_job(tier: int) -> void:
	if _jobs_panel:
		_jobs_panel.visible = false
	if _shop_row:
		_shop_row.visible = true
	MatchAPI.clear_all()
	ClientSession.reset_match()
	ClientSession.match_mode = Contract.MODE_SP_JOB
	ClientSession.job_tier = tier
	var client_job_id := Contract.new_client_job_id()
	ClientSession.client_job_id = client_job_id
	if ClientSession.use_live_api():
		var health: Dictionary = MatchAPI.health()
		if not bool(health.get("ok", false)):
			_toast_msg("Live API down at %s  (GET /health)" % ClientSession.api_base_url())
			return
		MatchAPI.ensure_player()
	var created: Dictionary = MatchAPI.create_job(tier, client_job_id)
	var match_id := str(created.get("matchId", ""))
	if match_id == "" or created.has("error"):
		_toast_msg("Job failed: %s" % str(created.get("error", "no matchId")))
		return
	ClientSession.match_id = match_id
	ClientSession.job_id = str(created.get("jobId", ""))
	if str(created.get("clientJobId", "")) != "":
		ClientSession.client_job_id = str(created.get("clientJobId"))
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
