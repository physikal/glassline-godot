extends Control
## Hideout gear strip. Wood plate + chunky chips.
## Master mute shares AudioJuice with match SOUND chrome. Coach reset is local.

const Chrome := preload("res://scripts/chrome.gd")
const Contract := preload("res://types/contract.gd")
const Coach := preload("res://scenes/match/first_hunt_coach.gd")

signal tips_reset

## Headless stand-in. The hideout leaves this empty and uses the AudioJuice autoload.
var audio = null

var _plate: PanelContainer
var _mute_btn: Button
var _reset_btn: Button
var _confirm_box: VBoxContainer
var _confirm_label: Label
var _yes_btn: Button
var _no_btn: Button
var _confirming: bool = false
var _built: bool = false

const _IDLE_BOTTOM := 122.0
const _CONFIRM_BOTTOM := 214.0


func _ready() -> void:
	if not _built:
		_build()
	refresh_mute()


func uses_wood() -> bool:
	return _plate != null and _plate.get_node_or_null("Wood") is TextureRect


func mute_text() -> String:
	if _mute_btn == null:
		return ""
	return _mute_btn.text


func mute_icon_kind() -> String:
	if _mute_btn == null:
		return ""
	return str(_mute_btn.get_meta("icon_kind", ""))


func is_confirming() -> bool:
	return _confirming and _confirm_box != null and _confirm_box.visible


func confirm_copy() -> String:
	if _confirm_label == null:
		return ""
	return _confirm_label.text


func plate_copy() -> String:
	var bits: PackedStringArray = [Contract.GEAR_KICKER]
	if _mute_btn:
		bits.append(_mute_btn.text)
	if _reset_btn and _reset_btn.visible:
		bits.append(_reset_btn.text)
	if is_confirming() and _confirm_label:
		bits.append(_confirm_label.text)
		if _yes_btn:
			bits.append(_yes_btn.text)
		if _no_btn:
			bits.append(_no_btn.text)
	return " ".join(bits)


func refresh_mute() -> void:
	_refresh_mute()


func press_mute() -> void:
	_on_mute()


func press_reset() -> void:
	_on_reset()


func press_confirm() -> void:
	_on_confirm()


func press_cancel() -> void:
	_on_cancel()


func _build() -> void:
	_built = true
	name = "GearStrip"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_TOP_RIGHT)
	offset_left = -456.0
	offset_right = -16.0
	offset_top = 12.0
	offset_bottom = _IDLE_BOTTOM

	_plate = PanelContainer.new()
	_plate.name = "GearPlate"
	_plate.set_anchors_preset(Control.PRESET_FULL_RECT)
	var box := Chrome.flat(Color(0.10, 0.07, 0.05, 0.28), 18, Chrome.HIGH_GOLD, 3)
	box.content_margin_left = 12
	box.content_margin_right = 12
	box.content_margin_top = 8
	box.content_margin_bottom = 8
	_plate.add_theme_stylebox_override("panel", box)
	add_child(_plate)

	var wood := TextureRect.new()
	wood.name = "Wood"
	wood.set_anchors_preset(Control.PRESET_FULL_RECT)
	wood.texture = Chrome.make_wood_texture(220, 96)
	wood.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	wood.stretch_mode = TextureRect.STRETCH_SCALE
	wood.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plate.add_child(wood)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plate.add_child(col)

	var kicker := Label.new()
	kicker.text = Contract.GEAR_KICKER
	kicker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	Chrome.apply_label(kicker, 8, Chrome.HIGH_GOLD, true)
	col.add_child(kicker)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(row)

	_mute_btn = Chrome.chunk_button(Contract.GEAR_MUTE_LIVE, Chrome.POSTER_PAPER, Chrome.INK, Vector2(176, 48))
	_mute_btn.pressed.connect(_on_mute)
	_mute_btn.focus_mode = Control.FOCUS_NONE
	row.add_child(_mute_btn)

	_reset_btn = Chrome.chunk_button(Contract.GEAR_RESET, Chrome.WOOD_DARK, Chrome.CREAM, Vector2(210, 48))
	_reset_btn.pressed.connect(_on_reset)
	_reset_btn.focus_mode = Control.FOCUS_NONE
	row.add_child(_reset_btn)

	_confirm_box = VBoxContainer.new()
	_confirm_box.visible = false
	_confirm_box.add_theme_constant_override("separation", 8)
	_confirm_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_confirm_box)

	_confirm_label = Label.new()
	_confirm_label.text = Contract.GEAR_CONFIRM_COPY
	_confirm_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_confirm_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	Chrome.apply_label(_confirm_label, 10, Chrome.CREAM, true)
	_confirm_box.add_child(_confirm_label)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	actions.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_confirm_box.add_child(actions)

	_yes_btn = Chrome.chunk_button(Contract.GEAR_CONFIRM_YES, Chrome.HIGH_GOLD, Chrome.INK, Vector2(168, 44))
	_yes_btn.focus_mode = Control.FOCUS_NONE
	_yes_btn.pressed.connect(_on_confirm)
	actions.add_child(_yes_btn)

	_no_btn = Chrome.chunk_button(Contract.GEAR_CONFIRM_NO, Chrome.INK, Chrome.CREAM, Vector2(168, 44))
	_no_btn.focus_mode = Control.FOCUS_NONE
	_no_btn.pressed.connect(_on_cancel)
	actions.add_child(_no_btn)

	_refresh_mute()


func _audio():
	if audio != null:
		return audio
	## Autoload node. Resolved by path so headless script checks can compile
	## before the singleton name is in scope.
	return get_node("/root/AudioJuice")


func _refresh_mute() -> void:
	if _mute_btn == null:
		return
	var muted := bool(_audio().muted)
	var fg := Chrome.CREAM if muted else Chrome.INK
	var bg := Chrome.INK if muted else Chrome.POSTER_PAPER
	_mute_btn.text = Contract.GEAR_MUTE_MUTED if muted else Contract.GEAR_MUTE_LIVE
	Chrome.paint_chunk_button(_mute_btn, bg, fg)
	var kind := "speaker_off" if muted else "speaker"
	_mute_btn.set_meta("icon_kind", kind)
	_mute_btn.icon = Chrome.make_icon(kind, fg, 22)
	_mute_btn.add_theme_constant_override("h_separation", 8)
	_mute_btn.add_theme_constant_override("icon_max_width", 22)
	_mute_btn.tooltip_text = Chrome.mute_button_tip(muted)


func _on_mute() -> void:
	_audio().toggle_mute()
	_refresh_mute()


func _on_reset() -> void:
	_set_confirming(true)


func _on_cancel() -> void:
	_set_confirming(false)


func _on_confirm() -> void:
	if not _confirming:
		return
	Coach.reset_tips()
	_set_confirming(false)
	tips_reset.emit()


func _set_confirming(on: bool) -> void:
	_confirming = on
	if _confirm_box:
		_confirm_box.visible = on
	if _reset_btn:
		_reset_btn.visible = not on
	offset_bottom = _CONFIRM_BOTTOM if on else _IDLE_BOTTOM
