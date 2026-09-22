extends Control
## First-hunt coach — cozy tip chips on the first PvP / private live (or mock) match.
## Client-only ConfigFile persist. Never modal-locks. No Marks / combat delta.

const Chrome := preload("res://scripts/chrome.gd")
const Contract := preload("res://types/contract.gd")

signal dismissed

static var store_path: String = Contract.COACH_STORE

var _chip_attack: PanelContainer
var _chip_recon: PanelContainer
var _chip_doll: PanelContainer
var _chip_decoy: PanelContainer
var _btn_got_it: Button
var _btn_x: Button
var _kicker: Label
var _anchor_attack: Control
var _anchor_recon: Control
var _anchor_decoy: Control
var _anchor_doll: Control
var _showing: bool = false
var _built: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(PRESET_FULL_RECT)
	if not _built:
		_build()


func _process(_delta: float) -> void:
	if _showing:
		_layout_chips()


static func is_seen() -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(store_path) != OK:
		return false
	return bool(cfg.get_value(Contract.COACH_SECTION, Contract.COACH_SEEN_KEY, false))


static func mark_seen() -> void:
	var cfg := ConfigFile.new()
	cfg.load(store_path)
	cfg.set_value(Contract.COACH_SECTION, Contract.COACH_SEEN_KEY, true)
	cfg.save(store_path)


static func clear_seen() -> void:
	var cfg := ConfigFile.new()
	cfg.load(store_path)
	cfg.set_value(Contract.COACH_SECTION, Contract.COACH_SEEN_KEY, false)
	cfg.save(store_path)


static func reset_tips() -> void:
	## Local only. Clears first-hunt, terrain kinds, and the gear-floor tip. No API.
	## coachTerrainSeen is a comma list (high,brush), so clear it to empty.
	var cfg := ConfigFile.new()
	cfg.load(store_path)
	cfg.set_value(Contract.COACH_SECTION, Contract.COACH_SEEN_KEY, false)
	cfg.set_value(Contract.COACH_SECTION, Contract.COACH_TERRAIN_SEEN_KEY, "")
	## Gear-floor tip shares this store. Reset brings the one-shot back.
	cfg.set_value(Contract.COACH_SECTION, Contract.EXPOSURE_FLOOR_SEEN_KEY, false)
	cfg.set_value(Contract.COACH_SECTION, Contract.EXPOSURE_FLOOR_LATCH_KEY, false)
	cfg.set_value(Contract.COACH_SECTION, Contract.EXPOSURE_FLOOR_PRIOR_KEY, Contract.EXPOSURE_FLOOR_START)
	cfg.save(store_path)


static func reset_store_for_test(path: String = "user://glassline_coach_test.cfg") -> void:
	store_path = path
	clear_seen()


static func restore_store() -> void:
	store_path = Contract.COACH_STORE


func is_showing() -> bool:
	return _showing and visible


func visible_titles() -> PackedStringArray:
	var titles := PackedStringArray()
	if not is_showing():
		return titles
	for chip in [_chip_attack, _chip_recon, _chip_doll, _chip_decoy]:
		if chip != null and chip.visible:
			var title := str(chip.get_meta("coach_title", ""))
			if title != "":
				titles.append(title)
	return titles


func chip_global_rect(kind: String) -> Rect2:
	var chip := _chip_for(kind)
	if chip == null:
		return Rect2()
	return chip.get_global_rect()


func passthrough_ok() -> bool:
	if mouse_filter != Control.MOUSE_FILTER_IGNORE:
		return false
	for chip in [_chip_attack, _chip_recon, _chip_doll, _chip_decoy]:
		if chip != null and chip.mouse_filter != Control.MOUSE_FILTER_IGNORE:
			return false
	return true


func should_present(is_job: bool, match_active: bool) -> bool:
	if is_job:
		return false
	if not match_active:
		return false
	return not is_seen()


func present(is_job: bool, match_active: bool) -> void:
	if not _built:
		_build()
	if should_present(is_job, match_active):
		_show_chips()
	else:
		_hide_chips()


func dismiss() -> void:
	mark_seen()
	_hide_chips()
	dismissed.emit()


func bind_anchors(attack: Control, recon: Control, decoy: Control, doll: Control) -> void:
	_anchor_attack = attack
	_anchor_recon = recon
	_anchor_decoy = decoy
	_anchor_doll = doll
	_layout_chips()


func _build() -> void:
	_built = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(PRESET_FULL_RECT)
	_chip_attack = _make_chip("ATTACK", Contract.COACH_ATTACK, Chrome.ATTACK_RED, "attack")
	_chip_recon = _make_chip("RECON", Contract.COACH_RECON, Chrome.RECON_BLUE, "recon")
	_chip_doll = _make_chip("DOLL", Contract.COACH_DOLL, Chrome.HIGH_GOLD, "decoy")
	_chip_decoy = _make_chip("DECOY", Contract.COACH_DECOY, Chrome.DECOY_CARAMEL, "decoy")
	add_child(_chip_attack)
	add_child(_chip_recon)
	add_child(_chip_doll)
	add_child(_chip_decoy)

	_kicker = Label.new()
	_kicker.text = Contract.COACH_KICKER
	_kicker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_kicker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	Chrome.apply_label(_kicker, 8, Chrome.HIGH_GOLD, true)
	_kicker.size = Vector2(180, 18)
	add_child(_kicker)

	_btn_got_it = Chrome.chunk_button(Contract.COACH_GOT_IT, Chrome.TEAL, Color.WHITE, Vector2(148, 40))
	_btn_got_it.pressed.connect(dismiss)
	_btn_got_it.focus_mode = Control.FOCUS_NONE
	add_child(_btn_got_it)

	_btn_x = Button.new()
	_btn_x.text = "X"
	_btn_x.custom_minimum_size = Vector2(40, 40)
	_btn_x.focus_mode = Control.FOCUS_NONE
	_btn_x.mouse_filter = Control.MOUSE_FILTER_STOP
	_btn_x.add_theme_font_override("font", Chrome.pixel_font())
	_btn_x.add_theme_font_size_override("font_size", 10)
	_btn_x.add_theme_color_override("font_color", Chrome.CREAM)
	_btn_x.add_theme_stylebox_override("normal", Chrome.flat(Color(0.16, 0.10, 0.08, 0.95), 10, Chrome.HIGH_GOLD, 2))
	_btn_x.add_theme_stylebox_override("hover", Chrome.flat(Color(0.22, 0.14, 0.10, 0.95), 10, Color.WHITE, 2))
	_btn_x.add_theme_stylebox_override("pressed", Chrome.flat(Color(0.10, 0.07, 0.05, 0.95), 10, Chrome.WOOD, 2))
	_btn_x.pressed.connect(dismiss)
	add_child(_btn_x)
	_hide_chips()


func _show_chips() -> void:
	_showing = true
	visible = true
	for chip in [_chip_attack, _chip_recon, _chip_doll, _chip_decoy]:
		if chip:
			chip.visible = true
	if _kicker:
		_kicker.visible = true
	if _btn_got_it:
		_btn_got_it.visible = true
	if _btn_x:
		_btn_x.visible = true
	_layout_chips()


func _hide_chips() -> void:
	_showing = false
	visible = false
	for chip in [_chip_attack, _chip_recon, _chip_doll, _chip_decoy]:
		if chip:
			chip.visible = false
	if _kicker:
		_kicker.visible = false
	if _btn_got_it:
		_btn_got_it.visible = false
	if _btn_x:
		_btn_x.visible = false


func _chip_for(kind: String) -> PanelContainer:
	match kind:
		"attack":
			return _chip_attack
		"recon":
			return _chip_recon
		"doll", "exposure":
			return _chip_doll
		"decoy":
			return _chip_decoy
		_:
			return null


func _make_chip(title: String, body: String, accent: Color, icon_kind: String) -> PanelContainer:
	var panel := PanelContainer.new()
	## Decorative only — hex / action clicks pass through the chip body.
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.custom_minimum_size = Vector2(200, 78)
	panel.size = Vector2(200, 78)
	panel.set_meta("coach_title", title)
	var box := Chrome.flat(Color(0.11, 0.08, 0.06, 0.94), 12, accent, 2)
	box.content_margin_left = 10
	box.content_margin_right = 8
	box.content_margin_top = 6
	box.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", box)

	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 4)
	panel.add_child(col)

	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_theme_constant_override("separation", 6)
	col.add_child(head)

	var icon := TextureRect.new()
	icon.texture = Chrome.make_icon(icon_kind, accent, 18)
	icon.custom_minimum_size = Vector2(18, 18)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(icon)

	var title_lbl := Label.new()
	title_lbl.text = title
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	Chrome.apply_label(title_lbl, 8, Chrome.HIGH_GOLD, true)
	head.add_child(title_lbl)

	var body_lbl := Label.new()
	body_lbl.text = body
	body_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body_lbl.custom_minimum_size = Vector2(176, 36)
	body_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	Chrome.apply_label(body_lbl, 8, Chrome.CREAM, true)
	col.add_child(body_lbl)
	return panel


func _layout_chips() -> void:
	if not _showing:
		return
	## Gutters stay clear of the hex well (220,132 → 1060,602) and action pills.
	_place_free(_chip_attack, Vector2(8, 456))
	_place_free(_chip_recon, Vector2(8, 548))
	_place_free(_chip_doll, Vector2(1058, 456))
	_place_free(_chip_decoy, Vector2(1058, 548))
	if _anchor_doll != null and _anchor_doll.is_visible_in_tree() and _doll_host_visible():
		_place_free(_chip_doll, Vector2(1058, 400))
	if _kicker:
		_kicker.position = Vector2(16, 616)
	if _btn_got_it:
		_btn_got_it.position = Vector2(16, 636)
	if _btn_x:
		_btn_x.position = Vector2(170, 636)


func _doll_host_visible() -> bool:
	if _anchor_doll == null:
		return false
	var walk: Node = _anchor_doll
	while walk != null:
		if walk is CanvasItem and not (walk as CanvasItem).visible:
			return false
		walk = walk.get_parent()
	return true


func _place_free(chip: Control, pos: Vector2) -> void:
	if chip:
		chip.position = pos
