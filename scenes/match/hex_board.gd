extends Node2D
## Interactive 9×7 axial board (BOARD_Q=9 cols × BOARD_R=7 rows, 63 hexes).
## Faces are tileable OPEN/BRUSH/HARD/? stamps. Snapshot owns revealed types.
## Client never invents terrain. UNKNOWN is FoW chrome only.

const HexMath := preload("res://scripts/hex_math.gd")
const Contract := preload("res://types/contract.gd")
const Chrome := preload("res://scripts/chrome.gd")
const Snapshot := preload("res://types/snapshot.gd")

signal hex_clicked(q: int, r: int)
signal hex_hovered(q: int, r: int)

const HEX_SIZE := 44.0
const PREVIEW_YOU := Vector2i(2, 2)
const PREVIEW_RIVAL := Vector2i(6, 4)

var _terrain: Dictionary = {}
var _you_hex: Variant = null
var _enemy_hex: Variant = null
var _own_decoy: Variant = null
var _enemy_decoy: Variant = null
var _selected: Variant = null
var _hover: Variant = null
var _highlights: Dictionary = {} # "q,r" -> Color
var _origin := Vector2.ZERO
var _preview_tokens: bool = true
var _faces: Dictionary = {}
var _ink: Node2D


func _ready() -> void:
	_origin = HexMath.axial_to_pixel(4, 3, HEX_SIZE)
	_build_faces()
	_ink = preload("res://scenes/match/hex_ink.gd").new()
	_ink.board = self
	_ink.z_index = 2
	_ink.z_as_relative = true
	add_child(_ink)
	_sync_faces()
	queue_redraw()


func board_size() -> Vector2:
	return HexMath.board_pixel_size(HEX_SIZE)


func apply_snapshot(snap: Snapshot, selected: Variant = null, extra_highlights: Dictionary = {}) -> void:
	_terrain = snap.terrain_map()
	_you_hex = snap.you_hex()
	_enemy_hex = snap.enemy_visible_hex()
	_own_decoy = snap.you_decoy_hex()
	_enemy_decoy = snap.enemy_decoy_soft_hex()
	if snap.status() == Contract.STATUS_ENDED:
		_own_decoy = null
		_enemy_decoy = null
	_selected = selected
	_highlights = extra_highlights
	_preview_tokens = snap.status() == Contract.STATUS_READY
	_sync_faces()
	queue_redraw()
	if _ink:
		_ink.queue_redraw()


func set_hover(hex: Variant) -> void:
	_hover = hex
	queue_redraw()
	if _ink:
		_ink.queue_redraw()


func cell_kind(q: int, r: int) -> String:
	## Snapshot revealed stamps only. UNKNOWN is FoW chrome — never invent terrain.
	var key := "%d,%d" % [q, r]
	if _terrain.has(key):
		var kind := str(_terrain[key])
		if kind == Contract.TYPE_OPEN or kind == Contract.TYPE_BRUSH or kind == Contract.TYPE_HARD:
			return kind
	return "unknown"


func _build_faces() -> void:
	## Sprite2D (not draw_texture_rect) — Compatibility/llvmpipe paints alpha as white.
	for q in Contract.BOARD_Q:
		for r in Contract.BOARD_R:
			var s := Sprite2D.new()
			s.centered = true
			s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			s.z_index = 1
			s.z_as_relative = true
			add_child(s)
			_faces["%d,%d" % [q, r]] = s


func _sync_faces() -> void:
	if _faces.is_empty():
		_build_faces()
	var w := HEX_SIZE * 1.7320508
	var h := HEX_SIZE * 2.0
	for q in Contract.BOARD_Q:
		for r in Contract.BOARD_R:
			var key := "%d,%d" % [q, r]
			var s: Sprite2D = _faces[key]
			s.position = HexMath.axial_to_pixel(q, r, HEX_SIZE) - _origin
			var tile: Texture2D = Chrome.hex_tile(cell_kind(q, r))
			s.texture = tile
			if tile and tile.get_width() >= 24:
				s.scale = Vector2(w / float(tile.get_width()), h / float(tile.get_height()))
				s.visible = true
			else:
				s.visible = false


func _draw() -> void:
	_sync_faces()
	var corners := HexMath.hex_corners(HEX_SIZE - 1.2)
	for q in Contract.BOARD_Q:
		for r in Contract.BOARD_R:
			var center := HexMath.axial_to_pixel(q, r, HEX_SIZE) - _origin
			var key := "%d,%d" % [q, r]
			var kind := cell_kind(q, r)
			var fill := Chrome.terrain_color(kind)
			var body := PackedVector2Array()
			for p in corners:
				body.append(center + p)
			var face: Sprite2D = _faces.get(key)
			if face == null or not face.visible:
				draw_colored_polygon(body, fill)
				_paint_fallback(center, kind, fill)
	if _ink:
		_ink.queue_redraw()


func render_ink(layer: CanvasItem) -> void:
	var corners := HexMath.hex_corners(HEX_SIZE - 1.2)
	for q in Contract.BOARD_Q:
		for r in Contract.BOARD_R:
			var center := HexMath.axial_to_pixel(q, r, HEX_SIZE) - _origin
			var key := "%d,%d" % [q, r]
			var kind := cell_kind(q, r)
			var body := PackedVector2Array()
			for p in corners:
				body.append(center + p)
			var outline := Color(0.10, 0.08, 0.07, 0.88)
			if Contract.same_hex(_selected, Contract.hex_dict(q, r)):
				outline = Color("e23b3b")
			elif Contract.same_hex(_hover, Contract.hex_dict(q, r)):
				outline = Color.WHITE
			layer.draw_polyline(body + PackedVector2Array([body[0]]), outline, 1.6, true)
			if _highlights.has(key):
				layer.draw_arc(center, HEX_SIZE * 0.72, 0.0, TAU, 28, _highlights[key], 3.0, true)
	_draw_tokens_on(layer)


func _paint_fallback(center: Vector2, kind: String, fill: Color) -> void:
	match kind:
		Contract.TYPE_BRUSH:
			_bush(center + Vector2(0, 2), 13.0)
		Contract.TYPE_HARD:
			_rock_pile(center)
		Contract.TYPE_OPEN:
			draw_circle(center + Vector2(-8, 6), 1.6, fill.darkened(0.22))
			draw_circle(center + Vector2(7, -5), 1.3, fill.darkened(0.16))
		_:
			_draw_mark(self, center, "?", Color("d8d8de"))


func _bush(pos: Vector2, radius: float) -> void:
	## Fallback painted clump if the canon stamp failed to import.
	draw_circle(pos + Vector2(0, 3), radius, Color("2a4a18"))
	draw_circle(pos + Vector2(-5, 0), radius * 0.74, Color("3d6a28"))
	draw_circle(pos + Vector2(5, -1), radius * 0.70, Color("6a9e3a"))
	draw_circle(pos + Vector2(0, -4), radius * 0.48, Color("5a8f34"))


func _rock_pile(center: Vector2) -> void:
	var a := PackedVector2Array([
		center + Vector2(-10, 4), center + Vector2(-2, -6), center + Vector2(8, 2),
		center + Vector2(4, 8), center + Vector2(-8, 8),
	])
	draw_colored_polygon(a, Color("6a7078"))
	var b := PackedVector2Array([
		center + Vector2(-2, -2), center + Vector2(6, -8), center + Vector2(11, 0),
		center + Vector2(4, 4),
	])
	draw_colored_polygon(b, Color("9aa3ad"))
	draw_circle(center + Vector2(-4, -3), 2.0, Color("d5dbe2"))


func _draw_tokens_on(layer: CanvasItem) -> void:
	var you: Variant = _you_hex
	if you == null and _preview_tokens:
		you = Contract.hex_dict(PREVIEW_YOU.x, PREVIEW_YOU.y)
	var rival: Variant = _enemy_hex
	if rival == null and _preview_tokens:
		rival = Contract.hex_dict(PREVIEW_RIVAL.x, PREVIEW_RIVAL.y)
	if you != null:
		_draw_token(layer, _center_of(you), Chrome.P1, "P1")
	if rival != null and not Contract.same_hex(rival, you):
		_draw_token(layer, _center_of(rival), Chrome.P2, "P2")
	if _own_decoy != null and not Contract.same_hex(_own_decoy, you):
		_draw_decoy_blip(layer, _center_of(_own_decoy), true)
	if _enemy_decoy != null and not Contract.same_hex(_enemy_decoy, _own_decoy):
		_draw_decoy_blip(layer, _center_of(_enemy_decoy), false)


func _center_of(hex: Variant) -> Vector2:
	return HexMath.axial_to_pixel(int(hex["q"]), int(hex["r"]), HEX_SIZE) - _origin


func _draw_decoy_blip(layer: CanvasItem, center: Vector2, own: bool) -> void:
	## Dashed toy doll — cozy stuffed dummy, not mil-sim smoke.
	var ring := Color("f2e6c4") if own else Color(0.94, 0.62, 0.38, 0.82)
	var doll := Chrome.P1.lightened(0.12) if own else Color(0.92, 0.58, 0.32, 0.88)
	_draw_dashed_ring(layer, center, HEX_SIZE * 0.70, ring, 12)
	_draw_dashed_ring(layer, center, HEX_SIZE * 0.58, ring.darkened(0.08), 10)
	layer.draw_circle(center + Vector2(0, 4), 9.0, Color(0, 0, 0, 0.22))
	layer.draw_circle(center + Vector2(0, 5), 8.4, doll)
	layer.draw_circle(center + Vector2(-7, 3), 3.2, doll)
	layer.draw_circle(center + Vector2(7, 3), 3.2, doll)
	layer.draw_circle(center + Vector2(0, -8), 6.4, Color.WHITE)
	layer.draw_circle(center + Vector2(0, -8), 5.4, doll.lightened(0.18))
	layer.draw_circle(center + Vector2(-2.0, -9.0), 1.15, Color("1a1410"))
	layer.draw_circle(center + Vector2(2.0, -9.0), 1.15, Color("1a1410"))
	layer.draw_line(center + Vector2(-2.2, -5.6), center + Vector2(2.2, -5.6), Color("1a1410"), 1.1, true)
	var tag := "DOLL" if own else "BLIP"
	_draw_mark(layer, center + Vector2(0, -22), tag, Color.WHITE if own else Color("f7d7b0"))


func _draw_dashed_ring(layer: CanvasItem, center: Vector2, radius: float, color: Color, dashes: int) -> void:
	for i in dashes:
		var a0 := float(i) * TAU / float(dashes)
		var a1 := a0 + TAU / float(dashes) * 0.55
		layer.draw_arc(center, radius, a0, a1, 7, color, 2.6, true)


func _draw_token(layer: CanvasItem, center: Vector2, color: Color, tag: String) -> void:
	layer.draw_circle(center + Vector2(0, 3), 13.0, Color(0, 0, 0, 0.35))
	layer.draw_circle(center, 13.0, Color.WHITE)
	layer.draw_circle(center, 10.0, color)
	layer.draw_circle(center, 4.0, Color.WHITE)
	_draw_mark(layer, center + Vector2(0, -20), tag, Color.WHITE)


func _draw_mark(layer: CanvasItem, center: Vector2, text: String, color: Color) -> void:
	var font := Chrome.pixel_font()
	var size := 10
	var box := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size)
	layer.draw_string(font, center - box * 0.5 + Vector2(0, box.y * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


func pick_local(local: Vector2) -> Variant:
	var axial := HexMath.pixel_to_axial(local + _origin, HEX_SIZE)
	if Contract.on_board(axial.x, axial.y):
		return Contract.hex_dict(axial.x, axial.y)
	return null
