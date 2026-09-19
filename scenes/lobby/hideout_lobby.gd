extends Control

const Chrome := preload("res://scripts/chrome.gd")
const Contract := preload("res://types/contract.gd")
const MarksPayout := preload("res://types/marks_payout.gd")
const Shop := preload("res://types/shop.gd")

var _bg: TextureRect
var _wood_covers: Array[ColorRect] = []
var _toast: Label
var _marks: Label
var _last_pay: Label
var _mode_lbl: Label
var _mode_btn: Button
var _jobs_panel: PanelContainer
var _shop_row: PanelContainer
var _shop_name: Label
var _shop_price: Label
var _shop_btn: Button
var _shop_status: Label
var _buying: bool = false


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
	elif "--capture-a1" in args:
		await get_tree().process_frame
		_on_play()
	elif "--capture-a2" in args:
		await get_tree().process_frame
		_on_play()
	elif "--capture-sp-end" in args:
		await get_tree().process_frame
		_on_start_job()


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


func _capture_named(res_path: String, tag: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path(res_path)
	img.save_png(path)
	print("%s %s" % [tag, path])
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
	_on_shop_primary()
	await get_tree().process_frame
	await get_tree().process_frame
	await _capture_named("res://artifacts/ux/shop_post_buy_marks.png", "S5_SHOP_POST_BUY")


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

	var dock_cover := ColorRect.new()
	dock_cover.color = Color("7a4e2c")
	dock_cover.set_anchors_and_offsets_preset(PRESET_BOTTOM_WIDE)
	dock_cover.offset_top = -128
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
	row.set_anchors_preset(PRESET_BOTTOM_WIDE)
	row.offset_top = -108
	row.offset_bottom = -22
	row.offset_left = 72
	row.offset_right = -72
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 22)
	add_child(row)

	var loadout := Chrome.dock_button("LOADOUT", Chrome.LOADOUT_BLUE, Color.WHITE, Vector2(268, 68), "loadout")
	loadout.pressed.connect(_focus_shop)
	row.add_child(loadout)

	var play := Chrome.dock_button("PLAY", Chrome.PLAY_GREEN, Color.WHITE, Vector2(380, 78), "play")
	play.pressed.connect(_on_play)
	row.add_child(play)

	var jobs := Chrome.dock_button("JOBS", Chrome.JOBS_ORANGE, Color.WHITE, Vector2(268, 68), "jobs")
	jobs.pressed.connect(_toggle_jobs)
	row.add_child(jobs)

	_build_shop_row()

	_toast = Label.new()
	_toast.set_anchors_preset(PRESET_BOTTOM_WIDE)
	_toast.offset_top = -248
	_toast.offset_bottom = -212
	_toast.offset_left = 80
	_toast.offset_right = -80
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	Chrome.apply_label(_toast, 10, Color("f0e3b0"), true)
	add_child(_toast)

	_build_jobs_panel()


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
	face.custom_minimum_size = Vector2(40, 40)
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

	var wallet := HBoxContainer.new()
	wallet.set_anchors_preset(PRESET_TOP_RIGHT)
	wallet.offset_left = -500
	wallet.offset_right = -16
	wallet.offset_top = 12
	wallet.offset_bottom = 64
	wallet.alignment = BoxContainer.ALIGNMENT_END
	wallet.add_theme_constant_override("separation", 10)
	add_child(wallet)

	wallet.add_child(_currency_chip("coin", Chrome.COIN_GOLD, "4,250"))
	wallet.add_child(_currency_chip("gem", Chrome.GEM_PURPLE, "310"))


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
	## Hideout ARMORY row — lobby-canon language. One cosmetic stub. No IAP / combat.
	_shop_row = PanelContainer.new()
	_shop_row.set_anchors_preset(PRESET_BOTTOM_WIDE)
	_shop_row.offset_left = 72
	_shop_row.offset_right = -72
	_shop_row.offset_top = -200
	_shop_row.offset_bottom = -118
	var box := Chrome.flat(Color(0.10, 0.08, 0.06, 0.94), 20, Chrome.HIGH_GOLD, 3)
	box.content_margin_left = 18
	box.content_margin_right = 18
	box.content_margin_top = 8
	box.content_margin_bottom = 8
	_shop_row.add_theme_stylebox_override("panel", box)
	add_child(_shop_row)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	_shop_row.add_child(col)

	var line := HBoxContainer.new()
	line.alignment = BoxContainer.ALIGNMENT_CENTER
	line.add_theme_constant_override("separation", 22)
	col.add_child(line)

	var kicker := Label.new()
	kicker.text = "ARMORY"
	kicker.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	Chrome.apply_label(kicker, 10, Chrome.HIGH_GOLD, true)
	line.add_child(kicker)

	_shop_name = Label.new()
	_shop_name.text = Contract.SHOP_STUB_ITEM_NAME
	_shop_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	Chrome.apply_label(_shop_name, 12, Chrome.CREAM, true)
	line.add_child(_shop_name)

	_shop_price = Label.new()
	_shop_price.text = Chrome.marks_star_text(Contract.SHOP_STUB_PRICE)
	_shop_price.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	Chrome.apply_label(_shop_price, 12, Chrome.HIGH_GOLD, true)
	line.add_child(_shop_price)

	_shop_btn = Chrome.chunk_button("BUY", Chrome.LOADOUT_BLUE, Color.WHITE, Vector2(168, 48))
	_shop_btn.pressed.connect(_on_shop_primary)
	line.add_child(_shop_btn)

	_shop_status = Label.new()
	_shop_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	Chrome.apply_label(_shop_status, 8, Color("f0e3b0"), true)
	col.add_child(_shop_status)


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
	if wallet.has("owned") or wallet.has("equipped") or wallet.has("you"):
		ClientSession.apply_shop(wallet)


func _bind_shop() -> void:
	var bag: Dictionary = MatchAPI.get_shop()
	ClientSession.apply_shop(bag)
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
	_stamp_wood(img, maxi(0, w - 500), 0, w, mini(62, h), px, py, pw, ph)
	_stamp_wood(img, 0, maxi(0, h - 140), w, h, px, py, pw, ph)
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
	if _shop_row:
		_shop_row.visible = true
	_toast_msg("ARMORY  ·  Ghillie Recolor  ★%d  ·  visual only" % Contract.SHOP_STUB_PRICE)


func _refresh_shop() -> void:
	if _shop_name == null:
		return
	## LIVE and mock both go through MatchAPI.get_shop / buy_shop.
	var bag = Shop.from_any(MatchAPI.get_shop())
	_shop_name.text = bag.item_name()
	_shop_price.text = Chrome.marks_star_text(bag.price())
	var owned: bool = ClientSession.owns_cosmetic(Contract.SHOP_STUB_ITEM_ID)
	var can_buy: bool = int(ClientSession.marks) >= int(bag.price())
	_shop_btn.text = Shop.row_action_text(owned)
	_shop_btn.disabled = not Shop.row_buy_enabled(owned, can_buy, _buying)
	_shop_status.text = Shop.row_status_text(owned, can_buy)
	if owned:
		Chrome.paint_chunk_button(_shop_btn, Color("2a241c"), Chrome.HIGH_GOLD)
	elif can_buy:
		Chrome.paint_chunk_button(_shop_btn, Chrome.LOADOUT_BLUE, Color.WHITE)
	else:
		## ★24 vs ★50 — muted / disabled BUY, not an active CTA.
		Chrome.paint_chunk_button(_shop_btn, Color("3a322c"), Color(0.72, 0.68, 0.58, 0.70))
	_refresh_bg()


func _on_shop_primary() -> void:
	if _buying:
		return
	if ClientSession.owns_cosmetic(Contract.SHOP_STUB_ITEM_ID):
		_on_equip_toggle()
		return
	if ClientSession.use_live_api():
		MatchAPI.ensure_player()
	_buying = true
	_shop_btn.disabled = true
	var buy_id := Contract.new_client_buy_id()
	var listed = Shop.from_any(MatchAPI.get_shop())
	var body: Dictionary = MatchAPI.buy_shop(listed.item_id(), buy_id)
	var shop = Shop.from_any(body)
	## Snapshot / buy you.marks is sole Marks truth — never marks -= on this client.
	ClientSession.apply_shop(body)
	_refresh_marks()
	_buying = false
	if shop.is_insufficient():
		_shop_status.text = Contract.SHOP_INSUFFICIENT_COPY
		_toast_msg("ARMORY rejected  ·  insufficient_marks")
	elif shop.is_unavailable():
		_shop_status.text = "LIVE shop not ready"
		_toast_msg("LIVE /shop 404  ·  mock ARMORY on F2")
	elif not shop.ok:
		_shop_status.text = str(shop.error)
		_toast_msg("ARMORY rejected  ·  %s" % shop.error)
	else:
		_shop_status.text = Contract.SHOP_OWNED_COPY
		_toast_msg(Contract.SHOP_OWNED_COPY)
	_refresh_shop()


func _on_equip_toggle() -> void:
	if not ClientSession.owns_cosmetic(Contract.SHOP_STUB_ITEM_ID):
		_toast_msg("Buy Ghillie Recolor in ARMORY.")
		return
	var next_id := "" if ClientSession.is_equipped(Contract.SHOP_STUB_ITEM_ID) else Contract.SHOP_STUB_ITEM_ID
	var body: Dictionary = MatchAPI.equip_cosmetic(next_id)
	if ClientSession.use_live_api():
		ClientSession.bind_equip_local(next_id)
	else:
		ClientSession.apply_shop(body)
	_refresh_shop()
	_toast_msg(Contract.SHOP_OWNED_COPY)


func _toggle_suit() -> void:
	if ClientSession.owns_cosmetic(Contract.SHOP_STUB_ITEM_ID):
		_on_equip_toggle()
		return
	_toast_msg("Buy Ghillie Recolor in ARMORY  ·  ★%d" % Contract.SHOP_STUB_PRICE)


func _toast_msg(text: String) -> void:
	_toast.text = text


func _toggle_jobs() -> void:
	_jobs_panel.visible = not _jobs_panel.visible
	if _jobs_panel.visible:
		_toast_msg("Hunt a bot — same Attack / Recon / UAV.")


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
		MatchAPI.ensure_player()
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
		MatchAPI.ensure_player()
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
