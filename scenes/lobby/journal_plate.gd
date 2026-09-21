extends Control
## Hideout hunt journal. Wood plate + chunky chips. Rows come only from a journal payload.

const Chrome := preload("res://scripts/chrome.gd")
const Contract := preload("res://types/contract.gd")
const Journal := preload("res://types/journal.gd")

signal practice_again
signal rematch_match(match_id: String)
signal closed

var _plate: PanelContainer
var _rows_box: VBoxContainer
var _empty_title: Label
var _empty_sub: Label
var _scroll: ScrollContainer
var _row_views: Array = []
var practice_presses: int = 0
var rematch_presses: int = 0


func _ready() -> void:
	## Visibility is owned by the hideout. Do not force-hide here — _ready can
	## run after the plate was already opened for a capture.
	_build()
	_fit_viewport()


func open() -> void:
	visible = true
	_fit_viewport()


func _fit_viewport() -> void:
	## Anchors stay 0×0 if this node is built before the hideout has a size.
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var vp := get_viewport_rect().size
	if vp.x < 2.0 or vp.y < 2.0:
		vp = Vector2(1280, 720)
	position = Vector2.ZERO
	size = vp


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func bind(body: Dictionary) -> void:
	## Render `entries` only. A missing list is the cozy empty plate — never a local hunt.
	var bag := Journal.payload(body)
	var entries: Array = bag.get("entries", [])
	_render(entries)


func row_count() -> int:
	return _row_views.size()


func empty_visible() -> bool:
	return _empty_title != null and _empty_title.visible


func empty_headline() -> String:
	if _empty_title == null:
		return ""
	return _empty_title.text


func row_marks(index: int) -> String:
	var view: Dictionary = _view(index)
	var label: Label = view.get("marks", null)
	return label.text if label else ""


func row_tag(index: int) -> String:
	var view: Dictionary = _view(index)
	var label: Label = view.get("tag", null)
	return label.text if label else ""


func row_result(index: int) -> String:
	var view: Dictionary = _view(index)
	var label: Label = view.get("result", null)
	return label.text if label else ""


func row_rival(index: int) -> String:
	var view: Dictionary = _view(index)
	var label: Label = view.get("rival", null)
	return label.text if label else ""


func row_cta_text(index: int) -> String:
	var view: Dictionary = _view(index)
	var button: Button = view.get("cta", null)
	return button.text if button else ""


func row_cta_disabled(index: int) -> bool:
	var view: Dictionary = _view(index)
	var button: Button = view.get("cta", null)
	return button == null or button.disabled


func press_row(index: int) -> void:
	var view: Dictionary = _view(index)
	var button: Button = view.get("cta", null)
	if button == null or button.disabled:
		return
	button.pressed.emit()


func uses_wood() -> bool:
	return _plate != null and _plate.get_node_or_null("Wood") is TextureRect


func plate_copy() -> String:
	var bits: PackedStringArray = []
	if _empty_title:
		bits.append(_empty_title.text)
	if _empty_sub:
		bits.append(_empty_sub.text)
	for view in _row_views:
		for key in ["result", "rival", "marks", "tag"]:
			var label: Label = view.get(key, null)
			if label:
				bits.append(label.text)
		var button: Button = view.get("cta", null)
		if button:
			bits.append(button.text)
	return " ".join(bits)


func _build() -> void:
	set_anchors_preset(PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.03, 0.02, 0.55)
	dim.set_anchors_preset(PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	_plate = PanelContainer.new()
	_plate.name = "JournalPlate"
	_plate.set_anchors_preset(PRESET_CENTER)
	_plate.offset_left = -460
	_plate.offset_right = 460
	_plate.offset_top = -280
	_plate.offset_bottom = 280
	var box := Chrome.flat(Color(0.10, 0.07, 0.05, 0.20), 22, Chrome.HIGH_GOLD, 4)
	box.content_margin_left = 22
	box.content_margin_right = 22
	box.content_margin_top = 16
	box.content_margin_bottom = 16
	_plate.add_theme_stylebox_override("panel", box)
	add_child(_plate)

	var wood := TextureRect.new()
	wood.name = "Wood"
	wood.set_anchors_preset(PRESET_FULL_RECT)
	wood.offset_left = 6
	wood.offset_top = 6
	wood.offset_right = -6
	wood.offset_bottom = -6
	wood.texture = Chrome.make_wood_texture(320, 180)
	wood.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	wood.stretch_mode = TextureRect.STRETCH_SCALE
	wood.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plate.add_child(wood)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plate.add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(col)

	var kicker := Label.new()
	kicker.text = Contract.JOURNAL_KICKER
	Chrome.apply_label(kicker, 8, Chrome.HIGH_GOLD, true)
	col.add_child(kicker)

	var heading := Label.new()
	heading.text = Contract.JOURNAL_HEADING
	Chrome.apply_label(heading, 16, Chrome.CREAM, true)
	col.add_child(heading)

	var blurb := Label.new()
	blurb.text = Contract.JOURNAL_BLURB
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	Chrome.apply_label(blurb, 8, Chrome.CREAM)
	col.add_child(blurb)

	var body := Control.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.custom_minimum_size = Vector2(0, 280)
	col.add_child(body)

	_empty_title = Label.new()
	_empty_title.set_anchors_preset(PRESET_CENTER)
	_empty_title.offset_left = -280
	_empty_title.offset_right = 280
	_empty_title.offset_top = -36
	_empty_title.offset_bottom = 0
	_empty_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_title.text = Contract.JOURNAL_EMPTY
	Chrome.apply_label(_empty_title, 14, Chrome.CREAM, true)
	body.add_child(_empty_title)

	_empty_sub = Label.new()
	_empty_sub.set_anchors_preset(PRESET_CENTER)
	_empty_sub.offset_left = -300
	_empty_sub.offset_right = 300
	_empty_sub.offset_top = 8
	_empty_sub.offset_bottom = 48
	_empty_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_empty_sub.text = Contract.JOURNAL_EMPTY_SUB
	Chrome.apply_label(_empty_sub, 8, Chrome.POSTER_PAPER)
	body.add_child(_empty_sub)

	_scroll = ScrollContainer.new()
	_scroll.set_anchors_preset(PRESET_FULL_RECT)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.visible = false
	body.add_child(_scroll)

	_rows_box = VBoxContainer.new()
	_rows_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows_box.add_theme_constant_override("separation", 8)
	_scroll.add_child(_rows_box)

	var back := Chrome.chunk_button(Contract.JOURNAL_CLOSE, Chrome.INK, Chrome.CREAM, Vector2(160, 48))
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(close)
	col.add_child(back)


func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mouse := event as InputEventMouseButton
	if not mouse.pressed or mouse.button_index != MOUSE_BUTTON_LEFT:
		return
	if _plate and _plate.get_global_rect().has_point(mouse.global_position):
		return
	close()
	accept_event()


func _render(entries: Array) -> void:
	for child in _rows_box.get_children():
		child.queue_free()
	_row_views.clear()
	var show_empty := entries.is_empty()
	_empty_title.visible = show_empty
	_empty_sub.visible = show_empty
	_scroll.visible = not show_empty
	for item in entries:
		if item is Dictionary:
			_add_row(item)


func _add_row(entry: Dictionary) -> void:
	var row := PanelContainer.new()
	var chip := Chrome.flat(Color(0.12, 0.08, 0.05, 0.92), 16, Color("3d2a1c"), 3)
	chip.content_margin_left = 10
	chip.content_margin_right = 10
	chip.content_margin_top = 8
	chip.content_margin_bottom = 8
	row.add_theme_stylebox_override("panel", chip)
	_rows_box.add_child(row)

	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
	row.add_child(line)

	var result := _pill(Journal.result_text(entry), _result_color(entry), Color.WHITE)
	line.add_child(result)

	var rival := Label.new()
	rival.text = Journal.rival_text(entry)
	rival.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rival.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	rival.clip_text = true
	Chrome.apply_label(rival, 10, Chrome.CREAM, true)
	line.add_child(rival)

	var marks := Label.new()
	marks.text = Journal.marks_text(entry)
	marks.custom_minimum_size = Vector2(88, 0)
	marks.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	marks.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	Chrome.apply_label(marks, 10, Chrome.HIGH_GOLD, true)
	line.add_child(marks)

	var tag := _pill(Journal.mode_tag(entry), Chrome.INK, Chrome.POSTER_PAPER)
	line.add_child(tag)

	var enabled := Journal.cta_enabled(entry)
	var cta := Chrome.chunk_button(Journal.cta_text(entry), Chrome.PLAY_GREEN, Color.WHITE, Vector2(230, 44))
	cta.disabled = not enabled
	if not enabled:
		Chrome.paint_chunk_button(cta, Color("3a322c"), Color("8a8074"))
	cta.pressed.connect(_on_row_pressed.bind(entry))
	line.add_child(cta)

	_row_views.append({
		"result": result.get_child(0),
		"rival": rival,
		"marks": marks,
		"tag": tag.get_child(0),
		"cta": cta,
	})


func _on_row_pressed(entry: Dictionary) -> void:
	var action := Journal.action_for(entry)
	if action == "practice":
		practice_presses += 1
		practice_again.emit()
	elif action == "rematch":
		rematch_presses += 1
		rematch_match.emit(str(entry.get("matchId", "")))


func _pill(text: String, bg: Color, fg: Color) -> PanelContainer:
	var chip := Chrome.pill_chip(bg, bg.lightened(0.18))
	chip.custom_minimum_size = Vector2(108, 36)
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	Chrome.apply_label(label, 8, fg, true)
	chip.add_child(label)
	return chip


func _result_color(entry: Dictionary) -> Color:
	match str(entry.get("result", "")):
		"win":
			return Chrome.PLAY_GREEN
		"loss":
			return Chrome.ATTACK_RED
		"forfeit":
			return Chrome.JOBS_ORANGE
		_:
			return Chrome.WOOD_MID


func _view(index: int) -> Dictionary:
	if index < 0 or index >= _row_views.size():
		return {}
	return _row_views[index]
