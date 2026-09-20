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
	draw_rect(Rect2(0, 0, w, h), Color(0.16, 0.10, 0.07, 0.55), true)
	draw_rect(Rect2(1, 1, w - 2, h - 2), Chrome.HIGH_GOLD, false, 2.0)
	var cx := w * 0.5
	var s := minf(w / 88.0, h / 118.0)
	var skin := Color("e6c39a")
	var teal := Color("1d6b54")
	var teal_l := Color("2f8f78")
	var navy := Color("1e2430")
	var boot := Color("3d2618")
	var hair := Color("5a3a22")
	var ghillie := equipped_skin_id == Contract.SHOP_STUB_ITEM_ID
	var bandana := equipped_skin_id == Contract.SHOP_BANDANA_ITEM_ID
	if ghillie:
		## Leafy hood + face peek — lobby-ghillie plate.
		draw_circle(Vector2(cx, h * 0.28), 16.0 * s, Color("3d6a28"))
		draw_circle(Vector2(cx - 10.0 * s, h * 0.18), 9.0 * s, Color("5a8f34"))
		draw_circle(Vector2(cx + 10.0 * s, h * 0.20), 8.5 * s, Color("7cb34a"))
		draw_circle(Vector2(cx, h * 0.12), 8.0 * s, Color("6aa03a"))
		draw_circle(Vector2(cx + 1.0 * s, h * 0.30), 8.0 * s, skin)
		draw_rect(Rect2(cx - 3.4 * s, h * 0.27, 2.4 * s, 2.4 * s), Chrome.INK)
		draw_rect(Rect2(cx + 2.2 * s, h * 0.27, 2.4 * s, 2.4 * s), Chrome.INK)
		draw_rect(Rect2(cx - 14.0 * s, h * 0.38, 28.0 * s, 28.0 * s), Color("4a8f32"))
		draw_circle(Vector2(cx - 13.0 * s, h * 0.42), 7.0 * s, Color("5a8f34"))
		draw_circle(Vector2(cx + 13.0 * s, h * 0.44), 6.5 * s, Color("7cb34a"))
		draw_circle(Vector2(cx, h * 0.48), 6.0 * s, Color("3d6a28"))
	else:
		## Teal hoodie kid — lobby-canon plate.
		draw_rect(Rect2(cx - 12.0 * s, h * 0.10, 24.0 * s, 8.0 * s), hair)
		draw_rect(Rect2(cx - 10.0 * s, h * 0.11, 20.0 * s, 5.0 * s), Color("3d2618"))
		draw_circle(Vector2(cx, h * 0.26), 11.0 * s, skin)
		draw_rect(Rect2(cx - 11.0 * s, h * 0.18, 22.0 * s, 5.0 * s), teal_l)
		draw_rect(Rect2(cx - 2.0 * s, h * 0.19, 4.0 * s, 3.0 * s), Color.WHITE)
		draw_rect(Rect2(cx - 4.0 * s, h * 0.24, 2.6 * s, 2.6 * s), Chrome.INK)
		draw_rect(Rect2(cx + 2.0 * s, h * 0.24, 2.6 * s, 2.6 * s), Chrome.INK)
		if bandana:
			draw_rect(Rect2(cx - 12.0 * s, h * 0.20, 24.0 * s, 6.0 * s), Color("c45a4a"))
			draw_rect(Rect2(cx + 10.0 * s, h * 0.24, 6.0 * s, 8.0 * s), Color("c45a4a"))
		draw_rect(Rect2(cx - 14.0 * s, h * 0.36, 28.0 * s, 26.0 * s), teal)
		draw_rect(Rect2(cx - 10.0 * s, h * 0.38, 20.0 * s, 8.0 * s), teal_l)
		draw_circle(Vector2(cx, h * 0.44), 4.5 * s, skin)
		draw_circle(Vector2(cx - 6.0 * s, h * 0.42), 2.0 * s, Color.WHITE)
	draw_rect(Rect2(cx - 10.0 * s, h * 0.62, 8.0 * s, 20.0 * s), navy)
	draw_rect(Rect2(cx + 2.0 * s, h * 0.62, 8.0 * s, 20.0 * s), navy)
	draw_rect(Rect2(cx - 10.0 * s, h * 0.80, 8.0 * s, 5.0 * s), boot)
	draw_rect(Rect2(cx + 2.0 * s, h * 0.80, 8.0 * s, 5.0 * s), boot)
	var cover_h := h * ((100.0 - exposure_pct) / 100.0) * 0.72
	if cover_h > 2.0:
		draw_rect(Rect2(2, h - cover_h, w - 4, cover_h - 2), Color("3d6a28"))
		draw_circle(Vector2(w * 0.24, h - 10.0), 9.0, Color("5a8f34"))
		draw_circle(Vector2(w * 0.76, h - 8.0), 8.0, Color("7cb34a"))
		draw_circle(Vector2(w * 0.50, h - 6.0), 6.0, Color("6aa03a"))
	var font := Chrome.pixel_font()
	var tag := "%d%%" % int(exposure_pct)
	draw_string(font, Vector2(8, 14), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Chrome.HIGH_GOLD)
