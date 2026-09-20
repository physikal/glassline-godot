extends Control
## End-turn exposure doll. Display is snapshot you.exposurePct (server).
## Same hideout operative crop — paper-doll read, not a blocky avatar.

const Chrome := preload("res://scripts/chrome.gd")
const ArtPack := preload("res://scripts/art_pack.gd")
const Contract := preload("res://types/contract.gd")

var exposure_pct: float = 50.0
var equipped_skin_id: String = ""


func _ready() -> void:
	if custom_minimum_size.x < 88.0 or custom_minimum_size.y < 118.0:
		custom_minimum_size = Vector2(88, 118)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()


func set_exposure(value: float) -> void:
	exposure_pct = clampf(value, 0.0, 100.0)
	queue_redraw()


func bind_server_pct(value: float) -> void:
	## A2: doll follows server you.exposurePct only.
	set_exposure(value)


func bind_equipped(item_id: String) -> void:
	## Same id as hideout operative. Empty = teal jacket. Never invent an id.
	if equipped_skin_id == item_id:
		return
	equipped_skin_id = item_id
	queue_redraw()


func _draw() -> void:
	var w := size.x
	var h := size.y
	if w < 8.0 or h < 8.0:
		return
	draw_rect(Rect2(0, 0, w, h), Color(0.16, 0.10, 0.07, 0.42), true)
	draw_rect(Rect2(1, 1, w - 2, h - 2), Color("3d2618"), false, 2.0)
	var plate := ArtPack.doll_texture(equipped_skin_id)
	if plate:
		var pad := 6.0
		var dest := Rect2(pad, 18.0, w - pad * 2.0, h - 24.0)
		draw_texture_rect(plate, dest, false)
	else:
		_draw_fallback(w, h)
	var cover_h := h * ((100.0 - exposure_pct) / 100.0) * 0.72
	if cover_h > 2.0:
		draw_rect(Rect2(4, h - cover_h, w - 8, cover_h - 4), Color(0.24, 0.42, 0.18, 0.55))
	var font := Chrome.pixel_font()
	var tag := "%d%%" % int(exposure_pct)
	draw_string(font, Vector2(8, 14), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Chrome.HIGH_GOLD)


func _draw_fallback(w: float, h: float) -> void:
	var cx := w * 0.5
	var s := minf(w / 88.0, h / 118.0)
	var skin := Color("e6c39a")
	var teal := Color("1d6b54")
	draw_circle(Vector2(cx, h * 0.26), 13.0 * s, skin)
	draw_rect(Rect2(cx - 16.0 * s, h * 0.36, 32.0 * s, 28.0 * s), teal)
	draw_rect(Rect2(cx - 10.0 * s, h * 0.62, 8.0 * s, 20.0 * s), Color("1e2430"))
	draw_rect(Rect2(cx + 2.0 * s, h * 0.62, 8.0 * s, 20.0 * s), Color("1e2430"))
