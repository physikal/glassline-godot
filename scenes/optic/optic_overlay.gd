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
var _note: Label
var _area: Label
var _family_lbl: Label
var _timer_fill: ColorRect
var _reticle: Control
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
	if _world:
		_world.position = _wobble
	if _timer_fill:
		var pulse := 0.55 + 0.45 * absf(sin(_time * 1.4))
		_timer_fill.scale.x = pulse


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(PRESET_FULL_RECT)
	add_child(dim)

	_world = Control.new()
	_world.set_anchors_preset(PRESET_FULL_RECT)
	_world.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_world)

	var sky := ColorRect.new()
	sky.color = Color("7ec8e3")
	sky.set_anchors_preset(PRESET_FULL_RECT)
	_world.add_child(sky)

	var ground := ColorRect.new()
	ground.name = "Ground"
	ground.set_anchors_and_offsets_preset(PRESET_BOTTOM_WIDE)
	ground.offset_top = -280
	_world.add_child(ground)

	for tree in [
		[Vector2(220, 250), Vector2(36, 90)],
		[Vector2(340, 230), Vector2(44, 110)],
		[Vector2(860, 240), Vector2(40, 100)],
		[Vector2(980, 260), Vector2(34, 86)],
	]:
		var trunk := ColorRect.new()
		trunk.color = Color("5a3a22")
		trunk.position = tree[0] + Vector2(tree[1].x * 0.38, tree[1].y * 0.55)
		trunk.size = Vector2(10, tree[1].y * 0.45)
		_world.add_child(trunk)
		var canopy := ColorRect.new()
		canopy.color = Color("2f8f78")
		canopy.position = tree[0]
		canopy.size = Vector2(tree[1].x, tree[1].y * 0.62)
		_world.add_child(canopy)

	var rock := ColorRect.new()
	rock.name = "Rock"
	rock.size = Vector2(200, 78)
	rock.position = Vector2(540, 348)
	rock.color = Color("9aa0a6")
	_world.add_child(rock)

	var figure := Control.new()
	figure.name = "Figure"
	figure.position = Vector2(610, 292)
	figure.size = Vector2(50, 80)
	figure.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var body := ColorRect.new()
	body.color = Color("1d6b54")
	body.position = Vector2(14, 22)
	body.size = Vector2(20, 30)
	figure.add_child(body)
	var head := ColorRect.new()
	head.color = Color("e6c39a")
	head.position = Vector2(17, 8)
	head.size = Vector2(14, 14)
	figure.add_child(head)
	var hair := ColorRect.new()
	hair.color = Color("5a3a22")
	hair.position = Vector2(16, 6)
	hair.size = Vector2(16, 6)
	figure.add_child(hair)
	var pin := ColorRect.new()
	pin.color = Color("e23b3b")
	pin.position = Vector2(21, 0)
	pin.size = Vector2(6, 6)
	figure.add_child(pin)
	_world.add_child(figure)

	var hud := Control.new()
	hud.set_anchors_preset(PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hud)

	_reticle = Control.new()
	_reticle.set_anchors_preset(PRESET_FULL_RECT)
	_reticle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reticle.draw.connect(_draw_reticle.bind(_reticle))
	hud.add_child(_reticle)

	var zoom_box := VBoxContainer.new()
	zoom_box.position = Vector2(24, 220)
	zoom_box.add_theme_constant_override("separation", 8)
	add_child(zoom_box)
	var zoom_title := Label.new()
	zoom_title.text = "ZOOM"
	Chrome.apply_label(zoom_title, 10, Chrome.CREAM, true)
	zoom_box.add_child(zoom_title)
	for z in ["FAR", "MID", "NEAR"]:
		var zb := Chrome.chunk_button(z, Chrome.HIGH_GOLD, Chrome.INK, Vector2(120, 40))
		zb.pressed.connect(_set_zoom.bind(z))
		zoom_box.add_child(zb)

	var fire := Chrome.chunk_button("FIRE", Chrome.FIRE_ORANGE, Color.WHITE, Vector2(180, 180))
	fire.position = Vector2(1050, 500)
	fire.pressed.connect(func() -> void: fire_pressed.emit())
	add_child(fire)

	var back := Chrome.chunk_button("BACK", Chrome.INK, Chrome.CREAM, Vector2(140, 48))
	back.position = Vector2(24, 24)
	back.pressed.connect(func() -> void:
		close()
		cancelled.emit()
	)
	add_child(back)

	_area = Label.new()
	_area.position = Vector2(500, 640)
	_area.size = Vector2(280, 40)
	_area.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	Chrome.apply_label(_area, 10, Chrome.CREAM, true)
	add_child(_area)

	_family_lbl = Label.new()
	_family_lbl.position = Vector2(430, 600)
	_family_lbl.size = Vector2(420, 28)
	_family_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	Chrome.apply_label(_family_lbl, 10, Chrome.HIGH_GOLD, true)
	add_child(_family_lbl)

	_note = Label.new()
	_note.position = Vector2(360, 80)
	_note.size = Vector2(560, 40)
	_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	Chrome.apply_label(_note, 16, Color("f0f4c0"), true)
	add_child(_note)

	var timer_back := ColorRect.new()
	timer_back.color = Color(0.1, 0.1, 0.1, 0.8)
	timer_back.position = Vector2(420, 24)
	timer_back.size = Vector2(440, 22)
	add_child(timer_back)
	_timer_fill = ColorRect.new()
	_timer_fill.color = Color("3ecf8e")
	_timer_fill.position = Vector2(424, 28)
	_timer_fill.size = Vector2(432, 14)
	_timer_fill.pivot_offset = Vector2.ZERO
	add_child(_timer_fill)
	var timer_lbl := Label.new()
	timer_lbl.text = "SHOT TIMER"
	timer_lbl.position = Vector2(430, 4)
	Chrome.apply_label(timer_lbl, 8, Chrome.CREAM, true)
	add_child(timer_lbl)

	_refresh_area()


func _refresh_area() -> void:
	if _world:
		var ground := _world.get_node_or_null("Ground") as ColorRect
		if ground:
			ground.color = Chrome.terrain_color(terrain_type)
		var fig := _world.get_node_or_null("Figure")
		if fig:
			fig.visible = intel_visible
	if _area:
		var t := terrain_type.to_upper() if terrain_type != "unknown" else "UNKNOWN"
		_area.text = "AREA  %s   Q%d R%d" % [t, int(target_hex.get("q", 0)), int(target_hex.get("r", 0))]
	if _family_lbl:
		var name := Contract.gun_family_name(gun_family)
		_family_lbl.text = "%s  ·  TOY OPTIC" % name
		Chrome.apply_label(_family_lbl, 10, ArtPack.optic_accent(gun_family), true)
	if _reticle:
		_reticle.queue_redraw()


func _set_zoom(z: String) -> void:
	_zoom = z
	if _world:
		var s := 1.0
		match z:
			"NEAR":
				s = 1.18
			"FAR":
				s = 0.86
		_world.scale = Vector2(s, s)
		_world.pivot_offset = size * 0.5


func _draw_reticle(node: Control) -> void:
	var c := node.size * 0.5
	var radius: float = minf(node.size.x, node.size.y) * 0.42
	var housing := ArtPack.optic_ring_color(gun_family)
	var accent := ArtPack.optic_accent(gun_family)
	node.draw_arc(c, radius + 22.0, 0.0, TAU, 80, Color(0.04, 0.03, 0.02, 0.94), 52.0, true)
	node.draw_arc(c, radius + 8.0, 0.0, TAU, 72, housing, 16.0, true)
	node.draw_arc(c, radius, 0.0, TAU, 72, Color("e8e8e8"), 3.0, true)
	match Contract.canonical_gun_id(gun_family):
		Contract.GUN_RAILFRAME:
			node.draw_rect(Rect2(c + Vector2(-radius - 8, -10), Vector2(16, 20)), accent, false, 2.0)
			node.draw_rect(Rect2(c + Vector2(radius - 8, -10), Vector2(16, 20)), accent, false, 2.0)
			node.draw_line(c + Vector2(0, -radius + 8), c + Vector2(0, radius - 8), Color("f4f4f4"), 3.0)
			node.draw_line(c + Vector2(-radius + 8, 0), c + Vector2(radius - 8, 0), Color("f4f4f4"), 3.0)
		Contract.GUN_CRESCENT:
			node.draw_arc(c, radius - 18.0, -0.4, 0.4, 12, accent, 3.0, true)
			node.draw_line(c + Vector2(0, -radius + 4), c + Vector2(0, -10), Color("f4f4f4"), 2.0)
			node.draw_line(c + Vector2(0, 10), c + Vector2(0, radius - 4), Color("f4f4f4"), 2.0)
			node.draw_line(c + Vector2(-radius + 4, 0), c + Vector2(-12, 0), Color("f4f4f4"), 2.0)
			node.draw_line(c + Vector2(12, 0), c + Vector2(radius - 4, 0), Color("f4f4f4"), 2.0)
		_:
			node.draw_line(c + Vector2(0, -radius), c + Vector2(0, radius), Color("f4f4f4"), 2.0)
			node.draw_line(c + Vector2(-radius, 0), c + Vector2(radius, 0), Color("f4f4f4"), 2.0)
	node.draw_circle(c, 3.0, Color("e23b3b"))
	node.draw_arc(c, 10.0, 0.0, TAU, 24, accent, 1.6, true)
