extends Node2D
## Interactive 9×7 axial board (BOARD_Q=9 cols × BOARD_R=7 rows, 63 hexes).
## Printed table terrain is a visual placeholder; MatchAPI / snapshot still
## owns revealed types, tokens, and hit/miss.

const HexMath := preload("res://scripts/hex_math.gd")
const Contract := preload("res://types/contract.gd")
const Chrome := preload("res://scripts/chrome.gd")
const Snapshot := preload("res://types/snapshot.gd")

signal hex_clicked(q: int, r: int)
signal hex_hovered(q: int, r: int)

const HEX_SIZE := 40.0
const PREVIEW_YOU := Vector2i(2, 2)
const PREVIEW_RIVAL := Vector2i(6, 4)

## Inner 7×5 printed plate (rim stays unknown until the snapshot reveals it).
## 1=open  2=brush  3=hard
const TABLE_INNER := [
	[1, 2, 3, 1, 2, 3, 1],
	[2, 1, 1, 3, 1, 2, 3],
	[1, 3, 2, 1, 1, 3, 2],
	[3, 1, 2, 3, 1, 1, 2],
	[2, 3, 1, 1, 2, 3, 1],
]

var _terrain: Dictionary = {}
var _you_hex: Variant = null
var _enemy_hex: Variant = null
var _selected: Variant = null
var _hover: Variant = null
var _highlights: Dictionary = {} # "q,r" -> Color
var _origin := Vector2.ZERO
var _preview_tokens: bool = true


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
	_preview_tokens = snap.status() == Contract.STATUS_READY
	queue_redraw()


func set_hover(hex: Variant) -> void:
	_hover = hex
	queue_redraw()


func table_kind(q: int, r: int) -> String:
	if q <= 0 or q >= Contract.BOARD_Q - 1 or r <= 0 or r >= Contract.BOARD_R - 1:
		return "unknown"
	var row: Array = TABLE_INNER[r - 1]
	var cell := int(row[q - 1])
	match cell:
		2:
			return Contract.TYPE_BRUSH
		3:
			return Contract.TYPE_HARD
		_:
			return Contract.TYPE_OPEN


func cell_kind(q: int, r: int) -> String:
	var key := "%d,%d" % [q, r]
	if _terrain.has(key):
		return str(_terrain[key])
	return table_kind(q, r)


func _draw() -> void:
	var corners := HexMath.hex_corners(HEX_SIZE - 1.2)
	var thick := HexMath.hex_corners(HEX_SIZE - 0.4)
	for q in Contract.BOARD_Q:
		for r in Contract.BOARD_R:
			var center := HexMath.axial_to_pixel(q, r, HEX_SIZE) - _origin
			var key := "%d,%d" % [q, r]
			var kind := cell_kind(q, r)
			var fill := Chrome.terrain_color(kind)
			var shade := 0.03 * float((q * 13 + r * 7) % 5 - 2)
			fill = fill.lightened(shade)
			var body := PackedVector2Array()
			var under := PackedVector2Array()
			for p in corners:
				body.append(center + p)
			for p in thick:
				under.append(center + p + Vector2(0, 3))
			draw_colored_polygon(under, fill.darkened(0.38))
			draw_colored_polygon(body, fill)
			_stamp(center, kind, fill)
			var outline := Color(0.12, 0.09, 0.07, 0.9)
			if kind != "unknown":
				outline = Chrome.HEX_LINE
			if Contract.same_hex(_selected, Contract.hex_dict(q, r)):
				outline = Color("e23b3b")
			elif Contract.same_hex(_hover, Contract.hex_dict(q, r)):
				outline = Color.WHITE
			draw_polyline(body + PackedVector2Array([body[0]]), outline, 2.4, true)
			if _highlights.has(key):
				draw_arc(center, HEX_SIZE * 0.72, 0.0, TAU, 28, _highlights[key], 3.0, true)
	_draw_tokens()


func _stamp(center: Vector2, kind: String, fill: Color) -> void:
	match kind:
		Contract.TYPE_BRUSH:
			_bush(center + Vector2(-6, 6), 8.5)
			_bush(center + Vector2(8, -1), 7.2)
			_bush(center + Vector2(0, 3), 5.4)
		Contract.TYPE_HARD:
			_rock(center + Vector2(-5, 4), Vector2(13, 9), fill)
			_rock(center + Vector2(6, -4), Vector2(10, 8), fill.lightened(0.1))
			_rock(center + Vector2(1, 7), Vector2(7, 5), fill.darkened(0.06))
		Contract.TYPE_OPEN:
			draw_circle(center + Vector2(-9, 7), 1.8, fill.darkened(0.2))
			draw_circle(center + Vector2(8, -5), 1.5, fill.darkened(0.14))
			draw_circle(center + Vector2(3, 9), 1.4, fill.darkened(0.22))
			draw_circle(center + Vector2(-4, -7), 1.6, Color("7eb24a"))
			draw_circle(center + Vector2(6, 6), 1.2, Color("8fbf5a"))
		_:
			_draw_mark(center, "?", Color("d8d8de"))


func _bush(pos: Vector2, radius: float) -> void:
	draw_circle(pos + Vector2(0, 2), radius, Color("3d6a28"))
	draw_circle(pos + Vector2(-2, 0), radius * 0.78, Color("5a8f34"))
	draw_circle(pos + Vector2(2, -1), radius * 0.7, Color("7cb34a"))
	draw_circle(pos + Vector2(-1, -2), radius * 0.28, Color("c6e08a"))


func _rock(pos: Vector2, size: Vector2, fill: Color) -> void:
	var rect := Rect2(pos - size * 0.5, size)
	draw_rect(rect, fill.darkened(0.28))
	draw_rect(Rect2(rect.position + Vector2(1, 1), size - Vector2(3, 4)), fill.lightened(0.12))
	draw_rect(Rect2(rect.position + Vector2(2, 1), Vector2(size.x * 0.35, 2)), Color("d5dbe2"))


func _draw_tokens() -> void:
	var you: Variant = _you_hex
	if you == null and _preview_tokens:
		you = Contract.hex_dict(PREVIEW_YOU.x, PREVIEW_YOU.y)
	var rival: Variant = _enemy_hex
	if rival == null and _preview_tokens:
		rival = Contract.hex_dict(PREVIEW_RIVAL.x, PREVIEW_RIVAL.y)
	if you != null:
		_draw_token(_center_of(you), Chrome.P1, "P1")
	if rival != null and not Contract.same_hex(rival, you):
		_draw_token(_center_of(rival), Chrome.P2, "P2")


func _center_of(hex: Variant) -> Vector2:
	return HexMath.axial_to_pixel(int(hex["q"]), int(hex["r"]), HEX_SIZE) - _origin


func _draw_token(center: Vector2, color: Color, tag: String) -> void:
	draw_circle(center + Vector2(0, 3), 13.0, Color(0, 0, 0, 0.35))
	draw_circle(center, 13.0, Color.WHITE)
	draw_circle(center, 10.0, color)
	draw_circle(center, 4.0, Color.WHITE)
	_draw_mark(center + Vector2(0, -20), tag, Color.WHITE)


func _draw_mark(center: Vector2, text: String, color: Color) -> void:
	var font := Chrome.pixel_font()
	var size := 10
	var box := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size)
	draw_string(font, center - box * 0.5 + Vector2(0, box.y * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


func pick_local(local: Vector2) -> Variant:
	var axial := HexMath.pixel_to_axial(local + _origin, HEX_SIZE)
	if Contract.on_board(axial.x, axial.y):
		return Contract.hex_dict(axial.x, axial.y)
	return null
