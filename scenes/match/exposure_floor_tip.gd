extends Control
## Muted one-shot when the server gear floor drops.
## Same wood-plate family as the coach tips. Local ConfigFile. No API / Marks / combat.

const Chrome := preload("res://scripts/chrome.gd")
const Contract := preload("res://types/contract.gd")

signal dismissed

static var store_path: String = Contract.COACH_STORE
## Plate captures hide the chip without marking it seen.
static var suppressed: bool = false

var _chip: PanelContainer
var _body: Label
var _btn_got_it: Button
var _btn_x: Button
var _anchor: Control
var _showing: bool = false
var _built: bool = false
var _memory_prior: int = -1


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(PRESET_FULL_RECT)
	if not _built:
		_build()


func _process(_delta: float) -> void:
	if _showing:
		_layout()


static func is_seen() -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(store_path) != OK:
		return false
	return bool(cfg.get_value(Contract.COACH_SECTION, Contract.EXPOSURE_FLOOR_SEEN_KEY, false))


static func mark_seen() -> void:
	var cfg := ConfigFile.new()
	cfg.load(store_path)
	cfg.set_value(Contract.COACH_SECTION, Contract.EXPOSURE_FLOOR_SEEN_KEY, true)
	cfg.set_value(Contract.COACH_SECTION, Contract.EXPOSURE_FLOOR_LATCH_KEY, false)
	cfg.save(store_path)


static func clear_seen() -> void:
	var cfg := ConfigFile.new()
	cfg.load(store_path)
	cfg.set_value(Contract.COACH_SECTION, Contract.EXPOSURE_FLOOR_SEEN_KEY, false)
	cfg.save(store_path)


static func is_latched() -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(store_path) != OK:
		return false
	return bool(cfg.get_value(Contract.COACH_SECTION, Contract.EXPOSURE_FLOOR_LATCH_KEY, false))


static func set_latched(on: bool) -> void:
	var cfg := ConfigFile.new()
	cfg.load(store_path)
	cfg.set_value(Contract.COACH_SECTION, Contract.EXPOSURE_FLOOR_LATCH_KEY, on)
	cfg.save(store_path)


static func stored_prior() -> int:
	var cfg := ConfigFile.new()
	if cfg.load(store_path) != OK:
		return -1
	if not cfg.has_section_key(Contract.COACH_SECTION, Contract.EXPOSURE_FLOOR_PRIOR_KEY):
		return -1
	return int(cfg.get_value(Contract.COACH_SECTION, Contract.EXPOSURE_FLOOR_PRIOR_KEY, -1))


static func store_prior(floor: int) -> void:
	var cfg := ConfigFile.new()
	cfg.load(store_path)
	cfg.set_value(Contract.COACH_SECTION, Contract.EXPOSURE_FLOOR_PRIOR_KEY, floor)
	cfg.save(store_path)


static func reset_store_for_test(path: String = "user://glassline_exposure_floor_tip_test.cfg") -> void:
	store_path = path
	var cfg := ConfigFile.new()
	cfg.save(store_path)
	clear_seen()
	set_latched(false)


static func restore_store() -> void:
	store_path = Contract.COACH_STORE
	suppressed = false


func is_showing() -> bool:
	return _showing and visible


func body_text() -> String:
	if _body == null:
		return ""
	return _body.text


func visible_titles() -> PackedStringArray:
	var titles := PackedStringArray()
	if is_showing():
		titles.append(Contract.EXPOSURE_FLOOR_TIP_TITLE)
	return titles


func passthrough_ok() -> bool:
	if mouse_filter != Control.MOUSE_FILTER_IGNORE:
		return false
	if _chip != null and _chip.mouse_filter != Control.MOUSE_FILTER_IGNORE:
		return false
	return true


func bind_anchor(doll: Control) -> void:
	_anchor = doll
	_layout()


func seed_prior(floor: int) -> void:
	_memory_prior = floor
	store_prior(floor)


func observe(floor: int) -> void:
	## First reading sets the prior. A later lower legal floor latches the tip once.
	if not _built:
		_build()
	var legal := Contract.exposure_floor_or_start(floor, true)
	var prev := _memory_prior
	if prev < 0:
		prev = stored_prior()
	var dropped := prev >= 0 and legal < prev
	_memory_prior = legal
	store_prior(legal)
	if dropped and not is_seen():
		set_latched(true)
	if suppressed or is_seen():
		_hide()
		return
	if is_latched():
		_show()
	else:
		_hide()


func dismiss() -> void:
	mark_seen()
	_hide()
	dismissed.emit()


func _build() -> void:
	_built = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(PRESET_FULL_RECT)
	_chip = PanelContainer.new()
	_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chip.custom_minimum_size = Vector2(320, 78)
	_chip.size = Vector2(320, 78)
	var accent := Chrome.HIGH_GOLD
	accent.a = 0.55
	var box := Chrome.flat(Color(0.11, 0.08, 0.06, 0.82), 12, accent, 2)
	box.content_margin_left = 10
	box.content_margin_right = 10
	box.content_margin_top = 6
	box.content_margin_bottom = 8
	_chip.add_theme_stylebox_override("panel", box)
	add_child(_chip)

	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 4)
	_chip.add_child(col)

	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_theme_constant_override("separation", 6)
	col.add_child(head)
	var icon := TextureRect.new()
	icon.texture = Chrome.make_icon("decoy", Chrome.HIGH_GOLD, 16)
	icon.custom_minimum_size = Vector2(16, 16)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(icon)
	var title := Label.new()
	title.text = Contract.EXPOSURE_FLOOR_TIP_TITLE
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	Chrome.apply_label(title, 8, Chrome.HIGH_GOLD, true)
	head.add_child(title)

	_body = Label.new()
	_body.text = Contract.EXPOSURE_FLOOR_TIP
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.custom_minimum_size = Vector2(292, 32)
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	Chrome.apply_label(_body, 8, Chrome.CREAM, true)
	col.add_child(_body)

	_btn_got_it = Chrome.chunk_button(Contract.COACH_GOT_IT, Chrome.TEAL, Color.WHITE, Vector2(132, 36))
	_btn_got_it.pressed.connect(dismiss)
	_btn_got_it.focus_mode = Control.FOCUS_NONE
	add_child(_btn_got_it)

	_btn_x = Button.new()
	_btn_x.text = "X"
	_btn_x.custom_minimum_size = Vector2(36, 36)
	_btn_x.focus_mode = Control.FOCUS_NONE
	_btn_x.mouse_filter = Control.MOUSE_FILTER_STOP
	_btn_x.add_theme_font_override("font", Chrome.pixel_font())
	_btn_x.add_theme_font_size_override("font_size", 10)
	_btn_x.add_theme_color_override("font_color", Chrome.CREAM)
	_btn_x.add_theme_stylebox_override("normal", Chrome.flat(Color(0.16, 0.10, 0.08, 0.9), 10, Chrome.HIGH_GOLD, 2))
	_btn_x.add_theme_stylebox_override("hover", Chrome.flat(Color(0.22, 0.14, 0.10, 0.9), 10, Color.WHITE, 2))
	_btn_x.add_theme_stylebox_override("pressed", Chrome.flat(Color(0.10, 0.07, 0.05, 0.9), 10, Chrome.WOOD, 2))
	_btn_x.pressed.connect(dismiss)
	add_child(_btn_x)
	_hide()


func _show() -> void:
	_showing = true
	visible = true
	if _chip:
		_chip.visible = true
	if _btn_got_it:
		_btn_got_it.visible = true
	if _btn_x:
		_btn_x.visible = true
	_layout()


func _hide() -> void:
	_showing = false
	visible = false
	if _chip:
		_chip.visible = false
	if _btn_got_it:
		_btn_got_it.visible = false
	if _btn_x:
		_btn_x.visible = false


func _layout() -> void:
	if not _showing or _chip == null:
		return
	var origin := Vector2(720, 248)
	if _anchor != null and is_instance_valid(_anchor):
		var rect := _anchor.get_global_rect()
		origin = rect.position + Vector2(rect.size.x + 16.0, 0.0) - global_position
		if origin.x + _chip.size.x > 1240.0:
			origin.x = maxf(16.0, rect.position.x - _chip.size.x - 16.0)
		origin.y = maxf(16.0, origin.y)
	_chip.position = origin
	if _btn_got_it:
		_btn_got_it.position = origin + Vector2(0, _chip.size.y + 8)
	if _btn_x:
		_btn_x.position = origin + Vector2(_chip.size.x - 36, -8)
