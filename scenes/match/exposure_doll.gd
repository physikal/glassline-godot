extends Control
## End-turn exposure doll. Display is snapshot you.exposurePct (server).
## Chrome wash follows you.equippedSkinId — visual only. No combat / exposure math.

const Chrome := preload("res://scripts/chrome.gd")
const Contract := preload("res://types/contract.gd")

var exposure_pct: float = 50.0
var equipped_skin_id: String = ""


func _ready() -> void:
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
	draw_rect(Rect2(0, 0, w, h), Color(0.10, 0.07, 0.05, 0.55), true)
	draw_rect(Rect2(1, 1, w - 2, h - 2), Color("2a1c14"), false, 2.0)
	var cx := w * 0.5
	var body := Color("e6c39a")
	var shirt := Color("1d6b54")
	var ghillie := equipped_skin_id == Contract.SHOP_STUB_ITEM_ID
	var bandana := equipped_skin_id == Contract.SHOP_BANDANA_ITEM_ID
	if ghillie:
		shirt = Color("4a8f32")
	elif bandana:
		shirt = Color("8a3a28")
	if ghillie:
		## Full leafy hood with a face peek — same chrome read as hideout plate.
		draw_circle(Vector2(cx, h * 0.24), 7.0, body)
		draw_circle(Vector2(cx, h * 0.16), 13.0, Color("3d6a28"))
		draw_circle(Vector2(cx - 8.0, h * 0.12), 6.5, Color("5a8f34"))
		draw_circle(Vector2(cx + 8.0, h * 0.13), 6.0, Color("7cb34a"))
		draw_circle(Vector2(cx, h * 0.08), 5.5, Color("6aa03a"))
		draw_circle(Vector2(cx + 1.0, h * 0.26), 4.5, body)
	else:
		draw_circle(Vector2(cx, h * 0.22), 8.0, body)
	if bandana:
		draw_rect(Rect2(cx - 9.0, h * 0.16, 18.0, 5.0), Color("c45a4a"))
	draw_rect(Rect2(cx - 8.0, h * 0.30, 16.0, 22.0), shirt)
	if ghillie:
		draw_circle(Vector2(cx - 9.0, h * 0.32), 5.5, Color("5a8f34"))
		draw_circle(Vector2(cx + 9.0, h * 0.34), 5.0, Color("7cb34a"))
		draw_circle(Vector2(cx, h * 0.36), 4.5, Color("3d6a28"))
	draw_rect(Rect2(cx - 6.0, h * 0.52, 5.0, 16.0), Color("3a332c"))
	draw_rect(Rect2(cx + 1.0, h * 0.52, 5.0, 16.0), Color("3a332c"))
	var cover_h := h * ((100.0 - exposure_pct) / 100.0) * 0.72
	if cover_h > 2.0:
		draw_rect(Rect2(2, h - cover_h, w - 4, cover_h - 2), Color("3d6a28"))
		draw_circle(Vector2(w * 0.24, h - 10.0), 9.0, Color("5a8f34"))
		draw_circle(Vector2(w * 0.76, h - 8.0), 8.0, Color("7cb34a"))
	var font := Chrome.pixel_font()
	var tag := "%d%%" % int(exposure_pct)
	draw_string(font, Vector2(8, 14), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Chrome.HIGH_GOLD)
