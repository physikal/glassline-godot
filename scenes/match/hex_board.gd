extends Node2D
## Interactive 9×7 axial board. Terrain comes only from caller-scoped snapshot.

const HexMath := preload("res://scripts/hex_math.gd")
const Contract := preload("res://types/contract.gd")
const Chrome := preload("res://scripts/chrome.gd")
const Snapshot := preload("res://types/snapshot.gd")

signal hex_clicked(q: int, r: int)
signal hex_hovered(q: int, r: int)

const HEX_SIZE := 36.0

var _terrain: Dictionary = {}
var _you_hex: Variant = null
var _enemy_hex: Variant = null
var _selected: Variant = null
var _hover: Variant = null
var _highlights: Dictionary = {} # "q,r" -> Color
var _origin := Vector2.ZERO


func _ready() -> void:
	_origin = HexMath.axial_to_pixel(4, 3, HEX_SIZE)
	queue_redraw()


func board_size() -> Vector2:
	return HexMath.board_pixel_size(HEX_SIZE)


func apply_snapshot(snap: Snapshot, selected: Variant = null, extra_highlights: Dictionary = {}) -> void:
	_terrain = snap.terrain_map()
	_you_hex = snap.you_hex()
	_enemy_hex = snap.enemy_visible_hex()
	_selected = selected
	_highlights = extra_highlights
	queue_redraw()


func set_hover(hex: Variant) -> void:
	_hover = hex
	queue_redraw()


func _draw() -> void:
	var corners := HexMath.hex_corners(HEX_SIZE - 1.5)
	for q in Contract.BOARD_Q:
		for r in Contract.BOARD_R:
			var center := HexMath.axial_to_pixel(q, r, HEX_SIZE) - _origin
			var key := "%d,%d" % [q, r]
			var kind := str(_terrain.get(key, "unknown"))
			var fill := Chrome.terrain_color(kind)
			var pts := PackedVector2Array()
			for p in corners:
				pts.append(center + p)
			draw_colored_polygon(pts, fill)
			var outline := Color(0.12, 0.09, 0.07, 0.85)
			if Contract.same_hex(_selected, Contract.hex_dict(q, r)):
				outline = Color("e23b3b")
			elif Contract.same_hex(_hover, Contract.hex_dict(q, r)):
				outline = Color("f2e6c4")
			draw_polyline(pts + PackedVector2Array([pts[0]]), outline, 3.0, true)
			if kind == "unknown":
				_draw_mark(center, "?", Color("d8d8de"))
			elif kind == Contract.TYPE_BRUSH:
				draw_circle(center + Vector2(-8, 4), 5.0, fill.darkened(0.25))
				draw_circle(center + Vector2(7, -3), 4.0, fill.darkened(0.18))
			elif kind == Contract.TYPE_HARD:
				draw_rect(Rect2(center + Vector2(-7, -4), Vector2(10, 7)), fill.darkened(0.22))
			if _highlights.has(key):
				draw_arc(center, HEX_SIZE * 0.72, 0.0, TAU, 28, _highlights[key], 3.0, true)
			if Contract.same_hex(_you_hex, Contract.hex_dict(q, r)):
				_draw_token(center, Color("3ecf8e"))
			elif Contract.same_hex(_enemy_hex, Contract.hex_dict(q, r)):
				_draw_token(center, Color("f0a020"))


func _draw_token(center: Vector2, color: Color) -> void:
	draw_circle(center, 11.0, Color.WHITE)
	draw_circle(center, 8.0, color)


func _draw_mark(center: Vector2, text: String, color: Color) -> void:
	var font := ThemeDB.fallback_font
	var size := 14
	var box := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size)
	draw_string(font, center - box * 0.5 + Vector2(0, box.y * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


func pick_local(local: Vector2) -> Variant:
	var axial := HexMath.pixel_to_axial(local + _origin, HEX_SIZE)
	if Contract.on_board(axial.x, axial.y):
		return Contract.hex_dict(axial.x, axial.y)
	return null
