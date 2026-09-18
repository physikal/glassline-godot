extends Control
## End-turn exposure doll. Display is snapshot you.exposurePct (server).
## Art stub — soft gap, owner Godot for polish. Not mil-sim. Not a Marks grant.

const Chrome := preload("res://scripts/chrome.gd")

var exposure_pct: float = 50.0


func _ready() -> void:
	custom_minimum_size = Vector2(72, 96)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()


func set_exposure(value: float) -> void:
	exposure_pct = clampf(value, 0.0, 100.0)
	queue_redraw()


func bind_server_pct(value: float) -> void:
	## A2: doll follows server you.exposurePct only.
	set_exposure(value)


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
	draw_circle(Vector2(cx, h * 0.22), 8.0, body)
	draw_rect(Rect2(cx - 8.0, h * 0.30, 16.0, 22.0), shirt)
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
