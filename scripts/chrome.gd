extends RefCounted
## Chunky hideout / war-table HUD helpers — toy pixel-cartoon, not mil-sim.

const Contract := preload("res://types/contract.gd")

const WOOD := Color("6b4428")
const WOOD_DARK := Color("2a1c14")
const WOOD_MID := Color("4a2e1c")
const INK := Color("1a1410")
const CREAM := Color("f4efe4")
const TEAL := Color("2f8f78")
const PLAY_GREEN := Color("2f9e4f")
const LOADOUT_BLUE := Color("1f6feb")
const JOBS_WHITE := Color("f3f3f3")
const ATTACK_RED := Color("c23b3b")
const RECON_BLUE := Color("1f6feb")
const ABILITY_PURPLE := Color("6b4ac7")
const HIGH_GOLD := Color("c9a24a")
const OPEN := Color("e6d4a0")
const BRUSH := Color("7cb34a")
const HARD := Color("9aa3ad")
const UNKNOWN := Color("2c2c34")
const FIRE_ORANGE := Color("f0a020")
const P1 := Color("3ecf8e")
const P2 := Color("f08a2a")
const HEX_LINE := Color("f2e6c4")


static func pixel_font() -> Font:
	var loaded = load("res://assets/fonts/PressStart2P-Regular.ttf")
	if loaded is Font:
		return loaded
	return ThemeDB.fallback_font


static func apply_label(label: Label, size: int, color: Color = CREAM, pixel := false) -> void:
	if pixel:
		label.add_theme_font_override("font", pixel_font())
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.65))
	label.add_theme_constant_override("outline_size", 4 if pixel else 2)


static func flat(bg: Color, radius: int = 14, border: Color = Color(0, 0, 0, 0), bw: int = 0) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.set_corner_radius_all(radius)
	box.set_border_width_all(bw)
	box.border_color = border
	box.content_margin_left = 16
	box.content_margin_right = 16
	box.content_margin_top = 10
	box.content_margin_bottom = 10
	return box


static func chunk_button(text: String, bg: Color, fg: Color, min_size: Vector2 = Vector2(220, 64)) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = min_size
	button.add_theme_font_override("font", pixel_font())
	button.add_theme_font_size_override("font_size", 12)
	button.add_theme_color_override("font_color", fg)
	button.add_theme_color_override("font_hover_color", fg)
	button.add_theme_color_override("font_pressed_color", fg)
	button.add_theme_color_override("font_disabled_color", Color(fg, 0.45))
	button.add_theme_stylebox_override("normal", flat(bg, 18, bg.lightened(0.25), 3))
	button.add_theme_stylebox_override("hover", flat(bg.lightened(0.08), 18, Color.WHITE, 3))
	button.add_theme_stylebox_override("pressed", flat(bg.darkened(0.12), 18, bg.darkened(0.3), 3))
	button.add_theme_stylebox_override("disabled", flat(bg.darkened(0.35), 18, bg.darkened(0.5), 3))
	return button


static func action_button(kind: String, text: String, bg: Color, fg: Color, min_size: Vector2 = Vector2(220, 64)) -> Button:
	var button := chunk_button(text, bg, fg, min_size)
	button.icon = make_icon(kind, fg, 28)
	button.add_theme_constant_override("h_separation", 10)
	button.add_theme_constant_override("icon_max_width", 28)
	return button


static func terrain_color(kind: String) -> Color:
	match kind:
		Contract.TYPE_OPEN:
			return OPEN
		Contract.TYPE_BRUSH:
			return BRUSH
		Contract.TYPE_HARD:
			return HARD
		_:
			return UNKNOWN


static func make_wood_texture(width: int = 320, height: int = 180) -> Texture2D:
	var img := Image.create(width, height, false, Image.FORMAT_RGB8)
	var noise := FastNoiseLite.new()
	noise.seed = 11
	noise.noise_type = FastNoiseLite.TYPE_VALUE
	noise.frequency = 0.045
	var dark := Color("24160f")
	var mid := Color("3d2618")
	var lite := Color("5a3a22")
	for y in height:
		for x in width:
			var n := noise.get_noise_2d(float(x) * 0.22, float(y) * 3.4)
			var ring := 0.06 * sin(float(x) * 0.11 + float(y) * 0.04)
			var t := clampf(0.52 + n * 0.34 + ring, 0.0, 1.0)
			var c: Color
			if t < 0.45:
				c = dark.lerp(mid, t / 0.45)
			else:
				c = mid.lerp(lite, (t - 0.45) / 0.55)
			img.set_pixel(x, y, c)
	var tex := ImageTexture.create_from_image(img)
	return tex


static func make_icon(kind: String, color: Color, px: int = 28) -> Texture2D:
	var img := Image.create(px, px, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	match kind:
		"attack":
			_icon_crosshair(img, color)
		"recon":
			_icon_binoculars(img, color)
		"ability":
			_icon_star(img, color)
		"highground":
			_icon_layers(img, color)
		"clock":
			_icon_clock(img, color)
		_:
			_icon_star(img, color)
	return ImageTexture.create_from_image(img)


static func make_face(kind: String, px: int = 44) -> Texture2D:
	var img := Image.create(px, px, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var cx := px / 2
	var cy := px / 2
	if kind == "p2":
		_fill_circle(img, cx, cy, 20, Color("2a2a30"))
		_fill_circle(img, cx, cy, 17, Color("3a3a42"))
		_fill_circle(img, cx, cy + 2, 12, Color("e6c39a"))
		_fill_rect(img, cx - 16, cy - 16, 32, 8, Color("2a2a30"))
		_fill_rect(img, cx - 6, cy - 4, 4, 4, INK)
		_fill_rect(img, cx + 3, cy - 4, 4, 4, INK)
		_fill_rect(img, cx - 3, cy + 5, 7, 2, Color("c23b3b"))
	else:
		_fill_circle(img, cx, cy, 20, Color("1d6b54"))
		_fill_circle(img, cx, cy + 1, 15, Color("e6c39a"))
		_fill_rect(img, cx - 12, cy - 16, 24, 8, Color("5a3a22"))
		_fill_rect(img, cx - 6, cy - 4, 4, 4, INK)
		_fill_rect(img, cx + 3, cy - 4, 4, 4, INK)
		_fill_rect(img, cx - 3, cy + 5, 7, 2, Color("c45a4a"))
	return ImageTexture.create_from_image(img)


static func hex_swatch(fill: Color, px: int = 22) -> Control:
	var dot := _HexSwatch.new()
	dot.fill = fill
	dot.custom_minimum_size = Vector2(px, px)
	dot.size = Vector2(px, px)
	return dot


class _HexSwatch extends Control:
	var fill: Color = Color.WHITE

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var radius := minf(size.x, size.y) * 0.46
		var center := size * 0.5
		var pts := PackedVector2Array()
		for i in 6:
			var angle := deg_to_rad(60.0 * float(i) - 30.0)
			pts.append(center + Vector2(cos(angle), sin(angle)) * radius)
		draw_colored_polygon(pts, fill)
		draw_polyline(pts + PackedVector2Array([pts[0]]), Color("1a1410"), 1.6, true)


static func _icon_crosshair(img: Image, color: Color) -> void:
	var c := 14
	_stroke_circle(img, c, c, 8, color)
	_stroke_circle(img, c, c, 3, color)
	_fill_rect(img, c - 1, 2, 3, 6, color)
	_fill_rect(img, c - 1, 20, 3, 6, color)
	_fill_rect(img, 2, c - 1, 6, 3, color)
	_fill_rect(img, 20, c - 1, 6, 3, color)


static func _icon_binoculars(img: Image, color: Color) -> void:
	_stroke_circle(img, 9, 15, 7, color)
	_stroke_circle(img, 19, 15, 7, color)
	_fill_circle(img, 9, 15, 3, color)
	_fill_circle(img, 19, 15, 3, color)
	_fill_rect(img, 12, 12, 5, 3, color)
	_fill_rect(img, 6, 6, 5, 4, color)
	_fill_rect(img, 18, 6, 5, 4, color)


static func _icon_star(img: Image, color: Color) -> void:
	var cx := 14.0
	var cy := 14.0
	for i in 5:
		var a := deg_to_rad(-90.0 + float(i) * 72.0)
		var b := deg_to_rad(-90.0 + float(i) * 72.0 + 36.0)
		_line(img, cx + cos(a) * 11.0, cy + sin(a) * 11.0, cx + cos(b) * 4.5, cy + sin(b) * 4.5, color)
		var c := deg_to_rad(-90.0 + float(i + 1) * 72.0)
		_line(img, cx + cos(b) * 4.5, cy + sin(b) * 4.5, cx + cos(c) * 11.0, cy + sin(c) * 11.0, color)
	_fill_circle(img, 14, 14, 3, color)


static func _icon_layers(img: Image, color: Color) -> void:
	_hex_outline(img, 14, 20, 7, color)
	_hex_outline(img, 14, 14, 7, color)
	_hex_outline(img, 14, 8, 7, color)


static func _icon_clock(img: Image, color: Color) -> void:
	_stroke_circle(img, 14, 14, 10, color)
	_fill_rect(img, 13, 8, 2, 7, color)
	_fill_rect(img, 13, 13, 7, 2, color)


static func _hex_outline(img: Image, cx: int, cy: int, radius: int, color: Color) -> void:
	var prev := Vector2.ZERO
	for i in 7:
		var angle := deg_to_rad(60.0 * float(i % 6) - 30.0)
		var pt := Vector2(cx, cy) + Vector2(cos(angle), sin(angle)) * float(radius)
		if i > 0:
			_line(img, prev.x, prev.y, pt.x, pt.y, color)
		prev = pt


static func _px(img: Image, x: int, y: int, color: Color) -> void:
	if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
		return
	img.set_pixel(x, y, color)


static func _fill_rect(img: Image, x: int, y: int, w: int, h: int, color: Color) -> void:
	for yy in range(y, y + h):
		for xx in range(x, x + w):
			_px(img, xx, yy, color)


static func _fill_circle(img: Image, cx: int, cy: int, radius: int, color: Color) -> void:
	var r2 := radius * radius
	for y in range(cy - radius, cy + radius + 1):
		for x in range(cx - radius, cx + radius + 1):
			var dx := x - cx
			var dy := y - cy
			if dx * dx + dy * dy <= r2:
				_px(img, x, y, color)


static func _stroke_circle(img: Image, cx: int, cy: int, radius: int, color: Color) -> void:
	var r2 := radius * radius
	var inner := (radius - 2) * (radius - 2)
	for y in range(cy - radius, cy + radius + 1):
		for x in range(cx - radius, cx + radius + 1):
			var d := (x - cx) * (x - cx) + (y - cy) * (y - cy)
			if d <= r2 and d >= inner:
				_px(img, x, y, color)


static func _line(img: Image, x0: float, y0: float, x1: float, y1: float, color: Color) -> void:
	var steps := maxi(1, int(maxi(absi(int(x1 - x0)), absi(int(y1 - y0)))))
	for i in steps + 1:
		var t := float(i) / float(steps)
		_px(img, int(round(lerpf(x0, x1, t))), int(round(lerpf(y0, y1, t))), color)
		_px(img, int(round(lerpf(x0, x1, t))) + 1, int(round(lerpf(y0, y1, t))), color)
