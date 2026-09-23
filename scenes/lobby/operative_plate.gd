extends PanelContainer
## Hideout wood chip. Level + XP toward next. Soft “SMOKE · L5” under L5.
## Reads the session bind. Does not read the match smoke charge and does not grant XP.

const Chrome := preload("res://scripts/chrome.gd")
const Contract := preload("res://types/contract.gd")

const TRACK_W := 132.0

var _level: Label
var _xp: Label
var _track: Panel
var _fill: ColorRect
var _tip_chip: PanelContainer
var _tip: Label


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := Chrome.flat(Chrome.WOOD_DARK, 18, Chrome.WOOD, 2)
	box.content_margin_left = 12
	box.content_margin_right = 12
	box.content_margin_top = 8
	box.content_margin_bottom = 8
	add_theme_stylebox_override("panel", box)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(col)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(row)

	_level = Label.new()
	_level.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	Chrome.apply_label(_level, 12, Chrome.CREAM, true)
	row.add_child(_level)

	_xp = Label.new()
	_xp.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	Chrome.apply_label(_xp, 8, Chrome.HIGH_GOLD, true)
	row.add_child(_xp)

	_track = Panel.new()
	_track.custom_minimum_size = Vector2(TRACK_W, 10)
	_track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var track_box := Chrome.flat(Color("14110e"), 6, Color("2a2018"), 1)
	track_box.content_margin_left = 0
	track_box.content_margin_right = 0
	track_box.content_margin_top = 0
	track_box.content_margin_bottom = 0
	_track.add_theme_stylebox_override("panel", track_box)
	col.add_child(_track)

	_fill = ColorRect.new()
	_fill.color = Chrome.XP_GREEN
	_fill.position = Vector2(2, 2)
	_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_track.add_child(_fill)

	_tip_chip = Chrome.pill_chip(Chrome.SMOKE_SPENT, Color("4a453e"))
	_tip_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_tip_chip)
	_tip = Label.new()
	_tip.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	Chrome.apply_label(_tip, 8, Chrome.SMOKE_SPENT_INK, true)
	_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip_chip.add_child(_tip)

	visible = false
	set_meta("xp_progress", -1)
	set_meta("xp_remaining", -1)


func bind_from_session() -> void:
	bind(
		ClientSession.operative_level_present,
		ClientSession.operative_level,
		ClientSession.xp_present,
		ClientSession.xp
	)


func bind(level_present: bool, level: int, xp_present: bool, xp: int) -> void:
	## Server numbers only. A missing level is not derived from xp.
	var show_level := level_present and level >= 1
	var show_xp := xp_present and xp >= 0
	visible = show_level or show_xp
	if show_level:
		_level.text = "L%d" % level
		_level.visible = true
	else:
		_level.text = ""
		_level.visible = false
	if show_xp:
		var progress := Contract.xp_progress(xp)
		var left := Contract.xp_remaining(xp)
		_xp.text = "%d / %d" % [progress, Contract.XP_PER_LEVEL]
		_xp.visible = true
		_track.visible = true
		var width := (TRACK_W - 4.0) * float(progress) / float(Contract.XP_PER_LEVEL)
		_fill.size = Vector2(maxf(0.0, width), 6)
		tooltip_text = "%d to next" % left
		set_meta("xp_progress", progress)
		set_meta("xp_remaining", left)
	else:
		_xp.text = ""
		_xp.visible = false
		_track.visible = false
		_fill.size = Vector2.ZERO
		tooltip_text = ""
		set_meta("xp_progress", -1)
		set_meta("xp_remaining", -1)
	var show_tip := show_level and level < Contract.SMOKE_UNLOCK_LEVEL
	_tip.text = Contract.XP_PLATE_TIP if show_tip else ""
	_tip_chip.visible = show_tip


func level_text() -> String:
	return _level.text if _level != null else ""


func tip_visible() -> bool:
	return _tip_chip != null and _tip_chip.visible


func tip_text() -> String:
	if not tip_visible():
		return ""
	return _tip.text


func progress() -> int:
	return int(get_meta("xp_progress", -1))


func remaining() -> int:
	return int(get_meta("xp_remaining", -1))


func fill_ratio() -> float:
	if progress() < 0:
		return -1.0
	return float(progress()) / float(Contract.XP_PER_LEVEL)
