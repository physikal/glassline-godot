extends Control
## End-turn exposure doll. Display is snapshot you.exposurePct (server).
## Chrome wash follows you.equippedSkinId — visual only. No combat / exposure math.

const Chrome := preload("res://scripts/chrome.gd")
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
	draw_rect(Rect2(0, 0, w, h), Color(0.10, 0.07, 0.05, 0.62), true)
	draw_rect(Rect2(1, 1, w - 2, h - 2), Chrome.HIGH_GOLD, false, 2.0)
	var cx := w * 0.5
	var s := minf(w / 88.0, h / 118.0)
	var body := Color("e6c39a")
	var shirt := Color("1d6b54")
	var pants := Color("2a241c")
	var ghillie := equipped_skin_id == Contract.SHOP_STUB_ITEM_ID
	var bandana := equipped_skin_id == Contract.SHOP_BANDANA_ITEM_ID
	if ghillie:
		shirt = Color("4a8f32")
	elif bandana:
		shirt = Color("8a3a28")
	if ghillie:
		## Full leafy hood with a face peek — same chrome read as hideout plate.
		draw_circle(Vector2(cx, h * 0.24), 8.0 * s, body)
		draw_circle(Vector2(cx, h * 0.16), 14.0 * s, Color("3d6a28"))
		draw_circle(Vector2(cx - 8.0 * s, h * 0.12), 7.0 * s, Color("5a8f34"))
		draw_circle(Vector2(cx + 8.0 * s, h * 0.13), 6.5 * s, Color("7cb34a"))
		draw_circle(Vector2(cx, h * 0.08), 6.0 * s, Color("6aa03a"))
		draw_circle(Vector2(cx + 1.0 * s, h * 0.26), 5.0 * s, body)
		draw_rect(Rect2(cx - 3.0 * s, h * 0.22, 2.0 * s, 2.0 * s), Chrome.INK)
		draw_rect(Rect2(cx + 2.0 * s, h * 0.22, 2.0 * s, 2.0 * s), Chrome.INK)
	else:
		draw_circle(Vector2(cx, h * 0.22), 9.0 * s, body)
		draw_rect(Rect2(cx - 10.0 * s, h * 0.10, 20.0 * s, 7.0 * s), Color("5a3a22"))
		draw_rect(Rect2(cx - 8.0 * s, h * 0.11, 16.0 * s, 4.0 * s), Color("3d2618"))
		draw_rect(Rect2(cx - 3.5 * s, h * 0.20, 2.4 * s, 2.4 * s), Chrome.INK)
		draw_rect(Rect2(cx + 1.4 * s, h * 0.20, 2.4 * s, 2.4 * s), Chrome.INK)
		draw_rect(Rect2(cx - 2.0 * s, h * 0.26, 4.5 * s, 1.6 * s), Color("c45a4a"))
	if bandana:
		draw_rect(Rect2(cx - 10.0 * s, h * 0.16, 20.0 * s, 5.5 * s), Color("c45a4a"))
		draw_rect(Rect2(cx + 8.0 * s, h * 0.20, 5.0 * s, 7.0 * s), Color("c45a4a"))
	draw_rect(Rect2(cx - 10.0 * s, h * 0.30, 20.0 * s, 24.0 * s), shirt)
	draw_circle(Vector2(cx, h * 0.38), 4.0 * s, body)
	if ghillie:
		draw_circle(Vector2(cx - 10.0 * s, h * 0.32), 6.0 * s, Color("5a8f34"))
		draw_circle(Vector2(cx + 10.0 * s, h * 0.34), 5.5 * s, Color("7cb34a"))
		draw_circle(Vector2(cx, h * 0.36), 5.0 * s, Color("3d6a28"))
	draw_rect(Rect2(cx - 8.0 * s, h * 0.54, 7.0 * s, 18.0 * s), pants)
	draw_rect(Rect2(cx + 1.0 * s, h * 0.54, 7.0 * s, 18.0 * s), pants)
	draw_rect(Rect2(cx - 8.0 * s, h * 0.70, 7.0 * s, 4.0 * s), Color("3d2618"))
	draw_rect(Rect2(cx + 1.0 * s, h * 0.70, 7.0 * s, 4.0 * s), Color("3d2618"))
	var cover_h := h * ((100.0 - exposure_pct) / 100.0) * 0.72
	if cover_h > 2.0:
		draw_rect(Rect2(2, h - cover_h, w - 4, cover_h - 2), Color("3d6a28"))
		draw_circle(Vector2(w * 0.24, h - 10.0), 9.0, Color("5a8f34"))
		draw_circle(Vector2(w * 0.76, h - 8.0), 8.0, Color("7cb34a"))
		draw_circle(Vector2(w * 0.50, h - 6.0), 6.0, Color("6aa03a"))
	var font := Chrome.pixel_font()
	var tag := "%d%%" % int(exposure_pct)
	draw_string(font, Vector2(8, 14), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Chrome.HIGH_GOLD)
