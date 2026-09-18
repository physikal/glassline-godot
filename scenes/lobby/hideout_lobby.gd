extends Control

const Chrome := preload("res://scripts/chrome.gd")

var _bg: TextureRect
var _toast: Label
var _marks: Label


func _ready() -> void:
	set_anchors_preset(PRESET_FULL_RECT)
	_build()
	_refresh_bg()
	if _marks:
		_marks.text = "MARKS  %d" % ClientSession.marks


func _build() -> void:
	_bg = TextureRect.new()
	_bg.set_anchors_preset(PRESET_FULL_RECT)
	_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg)

	var top := ColorRect.new()
	top.color = Color(0.08, 0.06, 0.05, 0.82)
	top.set_anchors_and_offsets_preset(PRESET_TOP_WIDE)
	top.offset_bottom = 78
	add_child(top)

	var chip := Label.new()
	chip.text = "%s   ★24" % ClientSession.HANDLE
	chip.position = Vector2(24, 22)
	Chrome.apply_label(chip, 12, Chrome.CREAM, true)
	add_child(chip)

	_marks = Label.new()
	_marks.position = Vector2(24, 48)
	Chrome.apply_label(_marks, 8, Chrome.HIGH_GOLD, true)
	add_child(_marks)

	var title := Label.new()
	title.text = "GLASSLINE"
	title.position = Vector2(0, 16)
	title.size = Vector2(1280, 48)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	Chrome.apply_label(title, 28, Color.WHITE, true)
	add_child(title)

	var offline := Label.new()
	offline.text = "OFFLINE MOCK"
	offline.position = Vector2(1040, 22)
	Chrome.apply_label(offline, 8, Chrome.TEAL, true)
	add_child(offline)

	var bottom := ColorRect.new()
	bottom.color = Color(0.08, 0.06, 0.05, 0.88)
	bottom.set_anchors_and_offsets_preset(PRESET_BOTTOM_WIDE)
	bottom.offset_top = -110
	add_child(bottom)

	var row := HBoxContainer.new()
	row.set_anchors_preset(PRESET_BOTTOM_WIDE)
	row.offset_top = -96
	row.offset_bottom = -20
	row.offset_left = 80
	row.offset_right = -80
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 28)
	add_child(row)

	var loadout := Chrome.chunk_button("  LOADOUT", Chrome.LOADOUT_BLUE, Color.WHITE, Vector2(260, 68))
	loadout.pressed.connect(_toast_msg.bind("Slice 1: loadout stays in the hideout."))
	row.add_child(loadout)

	var play := Chrome.chunk_button("  PLAY", Chrome.PLAY_GREEN, Color.WHITE, Vector2(300, 72))
	play.pressed.connect(_on_play)
	row.add_child(play)

	var jobs := Chrome.chunk_button("  JOBS", Chrome.JOBS_WHITE, Chrome.INK, Vector2(260, 68))
	jobs.pressed.connect(_toast_msg.bind("Slice 1: jobs board is a stub."))
	row.add_child(jobs)

	var ghillie := Chrome.chunk_button("SUIT", Chrome.TEAL, Color.WHITE, Vector2(120, 44))
	ghillie.position = Vector2(24, 600)
	ghillie.pressed.connect(_toggle_suit)
	add_child(ghillie)

	_toast = Label.new()
	_toast.position = Vector2(200, 540)
	_toast.size = Vector2(880, 36)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	Chrome.apply_label(_toast, 10, Color("f0e3b0"), true)
	add_child(_toast)


func _refresh_bg() -> void:
	var path := "res://assets/canon/lobby-ghillie.jpg" if ClientSession.ghillie else "res://assets/canon/lobby-canon.jpg"
	_bg.texture = load(path)


func _toggle_suit() -> void:
	ClientSession.ghillie = not ClientSession.ghillie
	_refresh_bg()


func _toast_msg(text: String) -> void:
	_toast.text = text


func _on_play() -> void:
	MockMatchServer.clear_all()
	ClientSession.reset_match()
	var created: Dictionary = MockMatchServer.create_match()
	var match_id := str(created.get("matchId", ""))
	var tokens: Dictionary = created.get("joinTokens", {})
	var human: Dictionary = MockMatchServer.join(match_id, str(tokens.get("a", "")))
	var dummy: Dictionary = MockMatchServer.join(match_id, str(tokens.get("b", "")))
	if human.has("error") or dummy.has("error"):
		_toast_msg("Mock join failed.")
		return
	ClientSession.match_id = match_id
	ClientSession.player_id = str(human.get("playerId", ""))
	ClientSession.seat = str(human.get("seat", "a"))
	ClientSession.dummy_player_id = str(dummy.get("playerId", ""))
	ClientSession.apply_snapshot(human.get("snapshot", {}))
	get_tree().change_scene_to_file("res://scenes/match/match_screen.tscn")
