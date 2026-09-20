extends Control
## Toy optic. FIRE only submits the chosen hex — MockMatchServer owns hit/miss.

const Chrome := preload("res://scripts/chrome.gd")
const ArtPack := preload("res://scripts/art_pack.gd")
const Contract := preload("res://types/contract.gd")

signal fire_pressed
signal cancelled

var target_hex: Dictionary = {}
var terrain_type: String = "unknown"
var intel_visible: bool = false
var last_server_note: String = ""

var _zoom := "MID"
var _wobble := Vector2.ZERO
var _time := 0.0
var _world: Control
var _figure: Control
var _note: Label
var _area: Label
var _family_lbl: Label
var _timer_fill: ColorRect
var _reticle: Control
var _zoom_btns: Dictionary = {}
var gun_family: String = Contract.GUN_FIELDBOLT


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
	var amp := 2.0
	match _zoom:
		"NEAR":
			amp = 1.2
		"FAR":
			amp = 6.0
	_wobble = Vector2(sin(_time * 3.1), cos(_time * 2.4)) * amp
	if _figure:
		_figure.position = Vector2(628, 268) + _wobble
	if _timer_fill:
		var pulse := 0.55 + 0.45 * absf(sin(_time * 1.4))
		_timer_fill.scale.x = pulse


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 1)
	dim.set_anchors_preset(PRESET_FULL_RECT)
	add_child(dim)

	_world = Control.new()
	_world.set_anchors_preset(PRESET_FULL_RECT)
	_world.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_world)

	var plate := TextureRect.new()
	plate.texture = load("res://assets/canon/optic-attack.jpg")
	plate.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	plate.set_anchors_preset(PRESET_FULL_RECT)
	plate.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	plate.stretch_mode = TextureRect.STRETCH_SCALE
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_world.add_child(plate)

	_figure = Control.new()
	_figure.name = "Figure"
	_figure.position = Vector2(628, 268)
	_figure.size = Vector2(28, 48)
	_figure.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_world.add_child(_figure)

	var hud := Control.new()
	hud.set_anchors_preset(PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hud)

	_reticle = Control.new()
	_reticle.set_anchors_preset(PRESET_FULL_RECT)
	_reticle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reticle.draw.connect(_draw_reticle.bind(_reticle))
	hud.add_child(_reticle)

	## Invisible hotspots over the plate's ZOOM / FIRE. Plate chrome stays the picture.
	var zoom_box := VBoxContainer.new()
	zoom_box.position = Vector2(48, 248)
	zoom_box.add_theme_constant_override("separation", 10)
	add_child(zoom_box)
	for z in ["FAR", "MID", "NEAR"]:
		var zb := Chrome.zoom_pill(z, z == _zoom)
		zb.modulate = Color(1, 1, 1, 0.04)
		zb.custom_minimum_size = Vector2(132, 44)
		zb.pressed.connect(_set_zoom.bind(z))
		zoom_box.add_child(zb)
		_zoom_btns[z] = zb

	var fire := Chrome.circle_button("", Chrome.FIRE_ORANGE, Color.WHITE, 148)
	fire.modulate = Color(1, 1, 1, 0.04)
	fire.position = Vector2(1068, 528)
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

	_family_lbl = Label.new()
	_family_lbl.position = Vector2(980, 16)
	_family_lbl.size = Vector2(280, 28)
	_family_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	Chrome.apply_label(_family_lbl, 10, Chrome.HIGH_GOLD, true)
	add_child(_family_lbl)

	_note = Label.new()
	_note.position = Vector2(360, 86)
	_note.size = Vector2(560, 40)
	_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	Chrome.apply_label(_note, 16, Color("f0f4c0"), true)
	add_child(_note)

	_timer_fill = ColorRect.new()
	_timer_fill.visible = false
	add_child(_timer_fill)

	_refresh_area()


func _refresh_area() -> void:
	if _figure:
		_figure.visible = intel_visible
	if _area:
		var t := terrain_type.to_upper() if terrain_type != "unknown" else "UNKNOWN"
		_area.text = "AREA  %s" % t
	if _family_lbl:
		var name := Contract.gun_family_name(gun_family)
		_family_lbl.text = name
		Chrome.apply_label(_family_lbl, 10, ArtPack.optic_accent(gun_family), true)
	if _reticle:
		_reticle.queue_redraw()
	_paint_zoom()


func _set_zoom(z: String) -> void:
	_zoom = z
	_paint_zoom()


func _paint_zoom() -> void:
	for key in _zoom_btns.keys():
		Chrome.paint_zoom_pill(_zoom_btns[key], str(key) == _zoom)


func _draw_reticle(node: Control) -> void:
	## Plate already carries the circular housing + white cross. Family ticks only.
	var c := node.size * 0.5
	var radius: float = minf(node.size.x, node.size.y) * 0.34
	var accent := ArtPack.optic_accent(gun_family)
	match Contract.canonical_gun_id(gun_family):
		Contract.GUN_RAILFRAME:
			node.draw_rect(Rect2(c + Vector2(-radius - 2, -7), Vector2(10, 14)), accent, false, 2.0)
			node.draw_rect(Rect2(c + Vector2(radius - 8, -7), Vector2(10, 14)), accent, false, 2.0)
		Contract.GUN_CRESCENT:
			node.draw_arc(c, radius - 16.0, -0.35, 0.35, 10, accent, 2.4, true)
		_:
			node.draw_circle(c + Vector2(0, -radius + 10), 3.0, accent)
			node.draw_circle(c + Vector2(0, radius - 10), 3.0, accent)
	node.draw_arc(c, 9.0, 0.0, TAU, 20, accent, 1.4, true)
