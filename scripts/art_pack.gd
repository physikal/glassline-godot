extends RefCounted
## Production pixel-cartoon chrome (toy-spy). Visual slots only — no combat / SKUs.

const Chrome := preload("res://scripts/chrome.gd")
const Contract := preload("res://types/contract.gd")

const WOOD := Color("6b4428")
const WOOD_LIGHT := Color("8a5a32")
const WOOD_DARK := Color("3d2618")
const METAL := Color("3a3e44")
const METAL_LITE := Color("6a7178")
const STEEL := Color("9aa3ad")
const INK := Color("1a1410")
const TEAL := Color("2f8f78")
const TEAL_DARK := Color("1d6b54")
const GOLD := Color("c9a24a")
const CREAM := Color("f4efe4")
const LOCK_INK := Color("2a241c")
const SILHOUETTE := Color("2c241c")


static func rifle_texture(family: String, state: String = "owned", width: int = 200, height: int = 52) -> Texture2D:
	var img := Image.create(width, height, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var gid := Contract.canonical_gun_id(family)
	if gid == "":
		gid = Contract.GUN_FIELDBOLT
	var locked := state == "locked" or state == "empty"
	_draw_hooks(img, state == "equipped")
	if state == "empty":
		return ImageTexture.create_from_image(img)
	match gid:
		Contract.GUN_RAILFRAME:
			_draw_railframe(img, locked)
		Contract.GUN_CRESCENT:
			_draw_crescent(img, locked)
		_:
			_draw_fieldbolt(img, locked)
	if locked:
		_draw_lock(img)
	return ImageTexture.create_from_image(img)


static func rifle_held_texture(family: String, width: int = 168, height: int = 44) -> Texture2D:
	return rifle_texture(family, "owned", width, height)


static func rifle_family_plate(width: int = 720, height: int = 420) -> Texture2D:
	## Labeled family still — full-color silhouettes, in-fiction names.
	var img := Image.create(width, height, false, Image.FORMAT_RGBA8)
	img.fill(Color("2a1c14"))
	_fill_rect(img, 8, 8, width - 16, height - 16, Color("3d2618"))
	_fill_rect(img, 14, 14, width - 28, height - 28, Color("24160f"))
	var families := Contract.gun_family_ids()
	var row_h := int((height - 80) / 3.0)
	for i in families.size():
		var gid := str(families[i])
		var y := 56 + i * row_h
		_fill_rect(img, 28, y, width - 56, row_h - 12, Color("3d2618"))
		_fill_rect(img, 32, y + 4, width - 64, row_h - 20, Color("2a1c14"))
		var rifle := rifle_texture(gid, "owned", 220, 52)
		var rimg := rifle.get_image()
		if rimg:
			img.blit_rect(rimg, Rect2i(0, 0, rimg.get_width(), rimg.get_height()), Vector2i(48, y + 18))
		_label(img, 290, y + 22, Contract.gun_family_name(gid), GOLD)
		_label(img, 290, y + 40, Contract.gun_family_hint(gid), CREAM)
	_label(img, 28, 24, "RIFLE FAMILIES", GOLD)
	return ImageTexture.create_from_image(img)


static func optic_ring_color(family: String) -> Color:
	match Contract.canonical_gun_id(family):
		Contract.GUN_RAILFRAME:
			return Color("3a4a52")
		Contract.GUN_CRESCENT:
			return Color("4a3220")
		_:
			return Color("2a2218")


static func optic_accent(family: String) -> Color:
	match Contract.canonical_gun_id(family):
		Contract.GUN_RAILFRAME:
			return TEAL
		Contract.GUN_CRESCENT:
			return Color("c45a4a")
		_:
			return GOLD


static func make_shop_icon(item_id: String, px: int = 22) -> Texture2D:
	var img := Image.create(px, px, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var id := Contract._canonical_shop_id(item_id)
	if id == Contract.SHOP_STUB_ITEM_ID:
		_fill_circle(img, 11, 12, 8, Color("3d6a28"))
		_fill_circle(img, 7, 9, 4, Color("5a8f34"))
		_fill_circle(img, 15, 10, 4, Color("7cb34a"))
	elif id == Contract.SHOP_BANDANA_ITEM_ID:
		_fill_rect(img, 3, 8, 16, 6, Color("c45a4a"))
		_fill_rect(img, 4, 9, 14, 2, Color("e8b8a0"))
		_fill_rect(img, 16, 12, 4, 6, Color("c45a4a"))
	elif id == Contract.SHOP_POSTER_ITEM_ID:
		_fill_rect(img, 4, 2, 14, 18, GOLD)
		_fill_rect(img, 6, 4, 10, 14, Color("f3e6c8"))
		_fill_circle(img, 11, 9, 3, TEAL)
	else:
		_fill_circle(img, 11, 11, 6, GOLD)
	return ImageTexture.create_from_image(img)


static func _sx(img: Image) -> float:
	return float(img.get_width()) / 200.0


static func _sy(img: Image) -> float:
	return float(img.get_height()) / 52.0


static func _rect_s(img: Image, x: float, y: float, w: float, h: float, color: Color) -> void:
	_fill_rect(img, int(x * _sx(img)), int(y * _sy(img)), maxi(1, int(w * _sx(img))), maxi(1, int(h * _sy(img))), color)


static func _circ_s(img: Image, cx: float, cy: float, radius: float, color: Color) -> void:
	_fill_circle(img, int(cx * _sx(img)), int(cy * _sy(img)), maxi(1, int(radius * minf(_sx(img), _sy(img)))), color)


static func _draw_hooks(img: Image, equipped: bool) -> void:
	## Plate pegs — gold when equipped, brass otherwise. No shelf bar.
	var hook := Color("e0b84a") if equipped else Color("c4a05a")
	var shade := hook.darkened(0.28)
	_rect_s(img, 22, 1, 10, 7, shade)
	_rect_s(img, 24, 0, 6, 10, hook)
	_rect_s(img, 164, 1, 10, 7, shade)
	_rect_s(img, 166, 0, 6, 10, hook)


static func _draw_fieldbolt(img: Image, locked: bool) -> void:
	## Plate olive bolt — chunky toy silhouette, wood-olive stock.
	var stock := _ink(Color("6e7a38"), locked)
	var stock_l := _ink(Color("8a9648"), locked)
	var stock_d := _ink(Color("4a5424"), locked)
	var barrel := _ink(Color("2a2c2e"), locked)
	var scope := _ink(Color("1c1e20"), locked)
	var steel := _ink(Color("6a7074"), locked)
	_rect_s(img, 8, 18, 40, 22, stock)
	_rect_s(img, 12, 22, 14, 14, stock_l)
	_rect_s(img, 38, 28, 16, 18, stock_d)
	_rect_s(img, 42, 30, 8, 12, stock_l)
	_rect_s(img, 46, 16, 38, 16, steel)
	_rect_s(img, 50, 18, 28, 8, _ink(STEEL, locked))
	_rect_s(img, 80, 18, 100, 10, barrel)
	_rect_s(img, 176, 16, 18, 14, barrel)
	_rect_s(img, 178, 14, 6, 18, barrel)
	_rect_s(img, 54, 4, 46, 13, scope)
	_circ_s(img, 60, 10, 5, _ink(Color("7ec8b0"), locked))
	_rect_s(img, 92, 6, 8, 8, scope)


static func _draw_railframe(img: Image, locked: bool) -> void:
	## Plate teal chassis — same toy weight, boxier stock. No rail salad.
	var chassis := _ink(Color("2a8a8a"), locked)
	var lite := _ink(Color("4ab0b0"), locked)
	var dark := _ink(Color("1a5a5a"), locked)
	var barrel := _ink(Color("1c1e22"), locked)
	var accent := _ink(Color("3ecf8e"), locked)
	_rect_s(img, 6, 16, 36, 20, chassis)
	_rect_s(img, 10, 20, 12, 12, lite)
	_rect_s(img, 8, 20, 12, 6, dark)
	_rect_s(img, 34, 14, 44, 18, chassis)
	_rect_s(img, 38, 16, 34, 8, lite)
	_rect_s(img, 40, 28, 18, 18, dark)
	_rect_s(img, 42, 30, 12, 12, barrel)
	_rect_s(img, 36, 26, 30, 4, accent)
	_rect_s(img, 76, 16, 100, 12, barrel)
	_rect_s(img, 172, 14, 20, 16, barrel)
	_rect_s(img, 48, 2, 36, 13, chassis)
	_rect_s(img, 52, 4, 28, 8, lite)
	_rect_s(img, 76, 6, 8, 6, accent)


static func _draw_crescent(img: Image, locked: bool) -> void:
	## Plate tan long-cutout — thumbhole stock, toy-spy not OEM.
	var wood := _ink(Color("c4a05a"), locked)
	var wood_l := _ink(Color("dcc07a"), locked)
	var wood_d := _ink(Color("8a6a32"), locked)
	var metal := _ink(Color("5a5248"), locked)
	var barrel := _ink(Color("2e2822"), locked)
	_rect_s(img, 4, 14, 40, 22, wood)
	_rect_s(img, 8, 18, 28, 12, wood_l)
	var hx0 := int(14 * _sx(img))
	var hy0 := int(20 * _sy(img))
	var hx1 := int(28 * _sx(img))
	var hy1 := int(30 * _sy(img))
	for yy in range(hy0, hy1):
		for xx in range(hx0, hx1):
			if xx >= 0 and yy >= 0 and xx < img.get_width() and yy < img.get_height():
				img.set_pixel(xx, yy, Color(0, 0, 0, 0))
	_rect_s(img, 8, 30, 12, 14, wood_d)
	_rect_s(img, 40, 16, 28, 14, metal)
	_rect_s(img, 66, 18, 108, 9, barrel)
	_rect_s(img, 170, 16, 22, 13, barrel)
	_rect_s(img, 46, 2, 48, 13, _ink(Color("4a3220"), locked))
	_rect_s(img, 50, 4, 40, 8, _ink(Color("6a4a28"), locked))
	_rect_s(img, 88, 6, 8, 6, _ink(Color("e07060"), locked))


static func _draw_lock(img: Image) -> void:
	var cx := img.get_width() / 2
	var cy := img.get_height() / 2 + 2
	_fill_rect(img, cx - 7, cy - 2, 14, 12, GOLD)
	_fill_rect(img, cx - 5, cy, 10, 8, INK)
	_stroke_circle(img, cx, cy - 4, 5, GOLD)
	_fill_rect(img, cx - 1, cy + 2, 3, 4, GOLD)


static func _ink(color: Color, locked: bool) -> Color:
	if not locked:
		return color
	return Color("7a6a58").lerp(color.darkened(0.25), 0.35)


static func _label(img: Image, x: int, y: int, text: String, color: Color) -> void:
	## Tiny block caps for family plates. Not a full font — capture stills use Labels.
	var cursor := x
	for i in text.length():
		var ch := text.substr(i, 1)
		if ch == " ":
			cursor += 6
			continue
		_fill_rect(img, cursor, y, 4, 7, color)
		cursor += 6


static func _fill_rect(img: Image, x: int, y: int, w: int, h: int, color: Color) -> void:
	for yy in range(y, y + h):
		for xx in range(x, x + w):
			if xx < 0 or yy < 0 or xx >= img.get_width() or yy >= img.get_height():
				continue
			img.set_pixel(xx, yy, color)


static func _fill_circle(img: Image, cx: int, cy: int, radius: int, color: Color) -> void:
	var r2 := radius * radius
	for y in range(cy - radius, cy + radius + 1):
		for x in range(cx - radius, cx + radius + 1):
			if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
				continue
			var dx := x - cx
			var dy := y - cy
			if dx * dx + dy * dy <= r2:
				img.set_pixel(x, y, color)


static func _stroke_circle(img: Image, cx: int, cy: int, radius: int, color: Color) -> void:
	var r2 := radius * radius
	var inner := (radius - 2) * (radius - 2)
	for y in range(cy - radius, cy + radius + 1):
		for x in range(cx - radius, cx + radius + 1):
			if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
				continue
			var d := (x - cx) * (x - cx) + (y - cy) * (y - cy)
			if d <= r2 and d >= inner:
				img.set_pixel(x, y, color)
