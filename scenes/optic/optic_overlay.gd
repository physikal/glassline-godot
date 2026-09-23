extends Control
## Toy optic. FIRE only submits the chosen hex — MockMatchServer owns hit/miss.
## Attack frame is the Josh-locked optic-attack.jpg landscape. FAR/MID/NEAR display-only.
## The plate paints above the hex board — not hex tiles seen through the scope.
## Virtual thumb stick replaces the plate D-pad. Fire stays a separate tap.

const Chrome := preload("res://scripts/chrome.gd")
const ArtPack := preload("res://scripts/art_pack.gd")
const Contract := preload("res://types/contract.gd")
const OpticJoystick := preload("res://scenes/optic/optic_joystick.gd")

signal fire_pressed
signal cancelled

var target_hex: Dictionary = {}
var terrain_type: String = "unknown"
var intel_visible: bool = false
var last_server_note: String = ""
var gun_family: String = Contract.GUN_FIELDBOLT

var _zoom := "MID"
var _time := 0.0
var _stick := Vector2.ZERO
var _amp := 1.2
var _window_sec := 1.2
var _window_left := 1.2
var _feel_frozen := false
var _figure: Control
var _note: Label
var _area: Label
var _joystick: Control
var _family_stamp: TextureRect
var _family_lbl: Label
var _feel_bar: ColorRect
var _feel_fill: ColorRect
var _feel_lbl: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	## Hex faces sit at z 1–2 and were painting through this plate.
	## Landscape optic-attack stays above the board, under forfeit (z 50).
	z_index = 36
	z_as_relative = false
	_build()
	visible = false


func open_for(hex: Dictionary, terrain: String, show_figure: bool, family: String = "") -> void:
	target_hex = hex
	terrain_type = terrain
	intel_visible = show_figure
	last_server_note = ""
	_zoom = "MID"
	_stick = Vector2.ZERO
	if _joystick and _joystick.has_method("pose"):
		_joystick.pose(Vector2.ZERO)
	gun_family = Contract.canonical_gun_id(family)
	if gun_family == "":
		gun_family = ClientSession.equipped_gun_id() if ClientSession else Contract.GUN_FIELDBOLT
	if _note:
		_note.text = ""
	_feel_frozen = false
	_apply_feel()
	_refresh_family()
	_refresh_area()
	visible = true


func pose_joystick_for_capture() -> void:
	## Nudge the thumb so the still reads as a stick, not the plate plus-pad.
	if _joystick and _joystick.has_method("pose"):
		_joystick.pose(Vector2(0.62, -0.38))


func pose_feel_for_capture() -> void:
	## Freeze the glass bar full and the figure at peak wobble so a still can read the juice.
	_apply_feel()
	_feel_frozen = true
	_time = 1.5708 / 3.1
	_window_left = _window_sec
	_paint_feel_bar()
	_paint_wobble()


func show_server_result(note: String) -> void:
	last_server_note = note
	if _note:
		_note.text = note


func close() -> void:
	visible = false
	_stick = Vector2.ZERO
	if _joystick and _joystick.has_method("pose"):
		_joystick.pose(Vector2.ZERO)


func _process(delta: float) -> void:
	if not visible or _feel_frozen:
		return
	_time += delta
	if _window_left > 0.0:
		_window_left = maxf(0.0, _window_left - delta)
		_paint_feel_bar()
	_paint_wobble()


func _apply_feel() -> void:
	## Chrome only. Server wobbleScale / shotWindowSec when present; else Design numbers.
	## Never writes hit, spot, or exposure.
	var scale := Contract.WOBBLE_SCALE_BASE
	var window_sec := Contract.SHOT_WINDOW_BASE_SEC
	if ClientSession:
		scale = ClientSession.attack_wobble_scale()
		window_sec = ClientSession.feel_shot_window_sec
	_amp = 1.2 * scale
	_window_sec = maxf(0.2, window_sec)
	_window_left = _window_sec
	var optic_on := _window_sec > 1.25
	var quiet := scale < 0.99
	if _feel_bar:
		_feel_bar.visible = optic_on
	if _feel_fill:
		_feel_fill.visible = optic_on
	if _feel_lbl:
		if optic_on:
			_feel_lbl.text = Contract.PART_TOAST_WINDOW
		elif quiet:
			_feel_lbl.text = Contract.PART_TOAST_WOBBLE
		else:
			_feel_lbl.text = ""
		_feel_lbl.visible = _feel_lbl.text != ""
	_paint_feel_bar()


func _paint_wobble() -> void:
	if _figure == null:
		return
	var wobble := Vector2(sin(_time * 3.1), cos(_time * 2.4)) * _amp
	_figure.position = Vector2(628, 268) + wobble + _stick * 36.0


func _paint_feel_bar() -> void:
	if _feel_fill == null or _window_sec <= 0.0:
		return
	var full := 280.0 * (_window_sec / 1.4)
	var ratio := clampf(_window_left / _window_sec, 0.0, 1.0)
	_feel_fill.size = Vector2(full * ratio, 10)


func _on_stick(value: Vector2) -> void:
	## Display-only reticle nudge. Does not change the attack hex / intent.
	_stick = value


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 1)
	dim.set_anchors_preset(PRESET_FULL_RECT)
	add_child(dim)

	var plate := TextureRect.new()
	plate.texture = load("res://assets/canon/optic-attack.jpg")
	plate.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	plate.set_anchors_preset(PRESET_FULL_RECT)
	plate.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	plate.stretch_mode = TextureRect.STRETCH_SCALE
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(plate)

	_figure = Control.new()
	_figure.name = "Figure"
	_figure.position = Vector2(628, 268)
	_figure.size = Vector2(28, 48)
	_figure.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_figure)

	## Invisible hotspots over the plate's FAR/MID/NEAR. Display-only.
	var zoom_box := VBoxContainer.new()
	zoom_box.position = Vector2(48, 248)
	zoom_box.add_theme_constant_override("separation", 10)
	add_child(zoom_box)
	for z in ["FAR", "MID", "NEAR"]:
		var zb := Button.new()
		zb.custom_minimum_size = Vector2(132, 44)
		zb.modulate = Color(1, 1, 1, 0.04)
		zb.flat = true
		zb.pressed.connect(_set_zoom.bind(z))
		zoom_box.add_child(zb)

	## Stamp out the painted plus-pad, then sit a circular thumb stick on it.
	var pad_hide := ColorRect.new()
	pad_hide.color = Color("06090e")
	pad_hide.position = Vector2(16, 398)
	pad_hide.size = Vector2(268, 276)
	pad_hide.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(pad_hide)

	_joystick = OpticJoystick.new()
	_joystick.position = Vector2(36, 418)
	_joystick.stick_changed.connect(_on_stick)
	add_child(_joystick)

	## FIRE is a separate tap on the plate's orange optic button. Not the stick.
	var fire := Button.new()
	fire.name = "FireTap"
	fire.custom_minimum_size = Vector2(148, 148)
	fire.position = Vector2(1068, 528)
	fire.modulate = Color(1, 1, 1, 0.04)
	fire.flat = true
	fire.pressed.connect(func() -> void: fire_pressed.emit())
	add_child(fire)

	var back := Chrome.chunk_button("BACK", Chrome.INK, Chrome.CREAM, Vector2(100, 36))
	back.position = Vector2(16, 668)
	back.pressed.connect(func() -> void:
		close()
		cancelled.emit()
	)
	add_child(back)

	_area = Label.new()
	_area.visible = false
	add_child(_area)

	_note = Label.new()
	_note.position = Vector2(360, 86)
	_note.size = Vector2(560, 40)
	_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	Chrome.apply_label(_note, 16, Color("f0f4c0"), true)
	add_child(_note)

	_family_stamp = TextureRect.new()
	_family_stamp.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_family_stamp.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_family_stamp.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_family_stamp.position = Vector2(980, 16)
	_family_stamp.size = Vector2(220, 48)
	_family_stamp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_family_stamp)

	_family_lbl = Label.new()
	_family_lbl.position = Vector2(980, 64)
	_family_lbl.size = Vector2(260, 28)
	_family_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	Chrome.apply_label(_family_lbl, 8, Chrome.HIGH_GOLD, true)
	add_child(_family_lbl)

	## Shot-window juice. Hidden until an optic part lengthens the glass. Not a hit meter.
	_feel_bar = ColorRect.new()
	_feel_bar.color = Color("24160f")
	_feel_bar.position = Vector2(500, 620)
	_feel_bar.size = Vector2(280, 14)
	_feel_bar.visible = false
	_feel_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_feel_bar)
	_feel_fill = ColorRect.new()
	_feel_fill.color = Color("c9a24a")
	_feel_fill.position = Vector2(502, 622)
	_feel_fill.size = Vector2(276, 10)
	_feel_fill.visible = false
	_feel_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_feel_fill)
	_feel_lbl = Label.new()
	_feel_lbl.position = Vector2(500, 636)
	_feel_lbl.size = Vector2(280, 24)
	_feel_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_feel_lbl.visible = false
	Chrome.apply_label(_feel_lbl, 10, Color("f0e3b0"), true)
	add_child(_feel_lbl)

	_refresh_family()
	_refresh_area()


func _refresh_family() -> void:
	var family := gun_family if gun_family != "" else Contract.GUN_FIELDBOLT
	if _family_stamp:
		_family_stamp.texture = ArtPack.rifle_texture(family, "owned")
		_family_stamp.modulate = ArtPack.optic_accent(family)
	if _family_lbl:
		_family_lbl.text = "%s  ·  %s" % [Contract.gun_family_name(family), Contract.GUN_VISUAL_COPY]


func _refresh_area() -> void:
	if _figure:
		_figure.visible = intel_visible
	if _area:
		var t := terrain_type.to_upper() if terrain_type != "unknown" else "UNKNOWN"
		_area.text = "AREA  %s" % t


func _set_zoom(z: String) -> void:
	## Display-only. No new loops / ballistics.
	_zoom = z
