extends Control
## Terrain coach — one-shot HIGH GROUND + BRUSH chips.
## Same wood-plate chrome as the first-hunt coach. Client-only ConfigFile.
## Chip bodies ignore the mouse. The board stays live. No payout, no network, no combat table.

const Chrome := preload("res://scripts/chrome.gd")
const Contract := preload("res://types/contract.gd")

signal dismissed

static var store_path: String = Contract.COACH_STORE
## Captures of other plates can hide these chips without marking them seen.
static var suppressed: bool = false

var _chip_high: PanelContainer
var _chip_brush: PanelContainer
var _btn_got_it: Button
var _btn_x: Button
var _kicker: Label
var _latched_high: bool = false
var _latched_brush: bool = false
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


static func is_kind_seen(kind: String) -> bool:
	return _seen_kinds().has(kind)


static func seen_text() -> String:
	return ",".join(_seen_kinds())


static func mark_kind(kind: String) -> void:
	if kind == "" or is_kind_seen(kind):
		return
	var cfg := ConfigFile.new()
	cfg.load(store_path)
	var seen := _seen_kinds()
	seen.append(kind)
	cfg.set_value(Contract.COACH_SECTION, Contract.COACH_TERRAIN_SEEN_KEY, ",".join(seen))
	cfg.save(store_path)


static func clear_seen() -> void:
	var cfg := ConfigFile.new()
	cfg.load(store_path)
	cfg.set_value(Contract.COACH_SECTION, Contract.COACH_TERRAIN_SEEN_KEY, "")
	cfg.save(store_path)


static func reset_store_for_test(path: String = "user://glassline_coach_terrain_test.cfg") -> void:
	store_path = path
	clear_seen()


static func restore_store() -> void:
	store_path = Contract.COACH_STORE
	suppressed = false


static func _seen_kinds() -> PackedStringArray:
	var cfg := ConfigFile.new()
	if cfg.load(store_path) != OK:
		return PackedStringArray()
	var raw := str(cfg.get_value(Contract.COACH_SECTION, Contract.COACH_TERRAIN_SEEN_KEY, ""))
	var out := PackedStringArray()
	for part in raw.split(",", false):
		var bit := str(part).strip_edges()
		if bit != "" and not out.has(bit):
			out.append(bit)
	return out


func is_showing() -> bool:
	return _showing and visible


func visible_titles() -> PackedStringArray:
	var titles := PackedStringArray()
	if not is_showing():
		return titles
	for chip in [_chip_high, _chip_brush]:
		if chip != null and chip.visible:
			var title := str(chip.get_meta("coach_title", ""))
			if title != "":
				titles.append(title)
	return titles


func chip_global_rect(kind: String) -> Rect2:
	var chip := _chip_for(kind)
	if chip == null or not chip.visible:
		return Rect2()
	return chip.get_global_rect()


func passthrough_ok() -> bool:
	if mouse_filter != Control.MOUSE_FILTER_IGNORE:
		return false
	for chip in [_chip_high, _chip_brush]:
		if chip != null and chip.mouse_filter != Control.MOUSE_FILTER_IGNORE:
			return false
	return true


func present(high_on: bool, brush_on: bool) -> void:
	if not _built:
		_build()
	if suppressed:
		_hide_chips()
		return
	if high_on and not is_kind_seen(Contract.COACH_TERRAIN_HIGH):
		_latched_high = true
	if brush_on and not is_kind_seen(Contract.COACH_TERRAIN_BRUSH):
		_latched_brush = true
	if is_kind_seen(Contract.COACH_TERRAIN_HIGH):
		_latched_high = false
	if is_kind_seen(Contract.COACH_TERRAIN_BRUSH):
		_latched_brush = false
	if _latched_high or _latched_brush:
		_show_chips()
	else:
		_hide_chips()


func dismiss() -> void:
	if _latched_high:
		mark_kind(Contract.COACH_TERRAIN_HIGH)
	if _latched_brush:
		mark_kind(Contract.COACH_TERRAIN_BRUSH)
	_latched_high = false
	_latched_brush = false
	_hide_chips()
	dismissed.emit()


func _build() -> void:
	_built = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(PRESET_FULL_RECT)
	## One wood-plate family. Legend green made the BRUSH tip read as a callout.
	var plate_accent := Chrome.HIGH_GOLD
	_chip_high = _make_chip(
		Contract.COACH_TERRAIN_HIGH_TITLE,
		Contract.COACH_TERRAIN_HIGH_COPY,
		plate_accent,
		"high"
	)
	_chip_brush = _make_chip(
		Contract.COACH_TERRAIN_BRUSH_TITLE,
		Contract.COACH_TERRAIN_BRUSH_COPY,
		plate_accent,
		"brush"
	)
	add_child(_chip_high)
	add_child(_chip_brush)

	_kicker = Label.new()
	_kicker.text = Contract.COACH_TERRAIN_KICKER
	_kicker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_kicker.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
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
	if _chip_high:
		_chip_high.visible = _latched_high
	if _chip_brush:
		_chip_brush.visible = _latched_brush
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
	for chip in [_chip_high, _chip_brush]:
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
		"high", Contract.COACH_TERRAIN_HIGH:
			return _chip_high
		"brush", Contract.COACH_TERRAIN_BRUSH:
			return _chip_brush
		_:
			return null


func _make_chip(title: String, body: String, accent: Color, icon_kind: String) -> PanelContainer:
	var panel := PanelContainer.new()
	## Decorative only — hex / action clicks pass through the chip body.
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.custom_minimum_size = Vector2(220, 86)
	panel.size = Vector2(220, 86)
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
	body_lbl.custom_minimum_size = Vector2(196, 40)
	body_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	Chrome.apply_label(body_lbl, 8, Chrome.CREAM, true)
	col.add_child(body_lbl)
	return panel


func _layout_chips() -> void:
	if not _showing:
		return
	## Gutters stay clear of the hex well (220,132 → 1060,602).
	if _chip_high and _chip_high.visible:
		_chip_high.position = Vector2(1048, 168)
	if _chip_brush and _chip_brush.visible:
		_chip_brush.position = Vector2(12, 168)
	var anchor := _chip_brush if _chip_brush != null and _chip_brush.visible else _chip_high
	var origin := anchor.position if anchor else Vector2(12, 168)
	if _kicker:
		_kicker.position = origin + Vector2(4, -20)
	if _btn_got_it:
		_btn_got_it.position = origin + Vector2(0, 94)
	if _btn_x:
		_btn_x.position = origin + Vector2(156, 94)
