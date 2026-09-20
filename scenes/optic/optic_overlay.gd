extends Control
## Toy optic. FIRE only submits the chosen hex — MockMatchServer owns hit/miss.
## Attack frame is the Josh-locked optic-attack.jpg plate. FAR/MID/NEAR display-only.

const Chrome := preload("res://scripts/chrome.gd")
const ArtPack := preload("res://scripts/art_pack.gd")
const Contract := preload("res://types/contract.gd")

signal fire_pressed
signal cancelled

var target_hex: Dictionary = {}
var terrain_type: String = "unknown"
var intel_visible: bool = false
var last_server_note: String = ""
var gun_family: String = Contract.GUN_FIELDBOLT

var _zoom := "MID"
var _time := 0.0
var _figure: Control
var _note: Label
var _area: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	visible = false


func open_for(hex: Dictionary, terrain: String, show_figure: bool, family: String = "") -> void:
	target_hex = hex
	terrain_type = terrain
	intel_visible = show_figure
	last_server_note = ""
	_zoom = "MID"
	gun_family = Contract.canonical_gun_id(family)
	if gun_family == "":
		gun_family = ClientSession.equipped_gun_id() if ClientSession else Contract.GUN_FIELDBOLT
	if _note:
		_note.text = ""
	_refresh_area()
	visible = true


func show_server_result(note: String) -> void:
	last_server_note = note
	if _note:
		_note.text = note


func close() -> void:
	visible = false


func _process(delta: float) -> void:
	if not visible:
		return
	_time += delta
	if _figure:
		var amp := 1.2
		_figure.position = Vector2(628, 268) + Vector2(sin(_time * 3.1), cos(_time * 2.4)) * amp


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

	## Invisible hotspots over the plate's FAR/MID/NEAR + FIRE. Plate chrome stays.
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

	var fire := Button.new()
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

	_refresh_area()


func _refresh_area() -> void:
	if _figure:
		_figure.visible = intel_visible
	if _area:
		var t := terrain_type.to_upper() if terrain_type != "unknown" else "UNKNOWN"
		_area.text = "AREA  %s" % t


func _set_zoom(z: String) -> void:
	## Display-only. No new loops / ballistics.
	_zoom = z
