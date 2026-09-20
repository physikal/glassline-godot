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


static func rifle_texture(family: String, state: String = "owned", width: int = 168, height: int = 48) -> Texture2D:
	var img := Image.create(width, height, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var gid := Contract.canonical_gun_id(family)
	if gid == "":
		gid = Contract.GUN_FIELDBOLT
	var locked := state == "locked" or state == "empty"
	_draw_hooks(img, locked)
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
	elif state == "equipped":
		_gold_frame(img)
	return ImageTexture.create_from_image(img)


static func rifle_held_texture(family: String, width: int = 132, height: int = 40) -> Texture2D:
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


static func _draw_hooks(img: Image, dim: bool) -> void:
	var hook := Color("8a6a48") if dim else Color("c9a24a")
	var w := img.get_width()
	var h := img.get_height()
	_fill_rect(img, 6, 2, 10, 5, hook)
	_fill_rect(img, 8, 1, 6, 9, hook)
	_fill_rect(img, w - 16, 2, 10, 5, hook)
	_fill_rect(img, w - 14, 1, 6, 9, hook)
	_fill_rect(img, 4, h - 5, w - 8, 4, hook.darkened(0.20))


static func _draw_fieldbolt(img: Image, locked: bool) -> void:
	## Classic wood bolt — Remington 700 / M24 family, toy silhouette.
	var wood := _ink(Color("c48a4a"), locked)
	var wood_l := _ink(Color("e0b06a"), locked)
	var metal := _ink(Color("6a7178"), locked)
	var barrel := _ink(Color("3a3e44"), locked)
	var scope := _ink(Color("2a2e32"), locked)
	_fill_rect(img, 6, 16, 28, 18, wood)
	_fill_rect(img, 10, 18, 10, 12, wood_l)
	_fill_rect(img, 28, 24, 14, 16, wood)
	_fill_rect(img, 30, 26, 8, 12, wood_l)
	_fill_rect(img, 36, 14, 32, 14, metal)
	_fill_rect(img, 40, 16, 22, 8, _ink(STEEL, locked))
	_fill_rect(img, 54, 6, 6, 12, _ink(STEEL, locked))
	_fill_circle(img, 57, 6, 4, _ink(STEEL, locked))
	_fill_rect(img, 66, 16, 86, 10, barrel)
	_fill_rect(img, 148, 14, 12, 14, barrel)
	_fill_rect(img, 42, 4, 32, 10, scope)
	_fill_rect(img, 70, 6, 8, 6, _ink(TEAL, locked))
	_fill_rect(img, 44, 6, 6, 6, _ink(Color("8fd4c4"), locked))


static func _draw_railframe(img: Image, locked: bool) -> void:
	## Chassis bolt — AI AX / AWM-class, chunky toy frame. No rail salad.
	var chassis := _ink(Color("4a545c"), locked)
	var lite := _ink(Color("8a949c"), locked)
	var accent := _ink(Color("3ecf8e"), locked)
	var barrel := _ink(Color("2a2e32"), locked)
	_fill_rect(img, 6, 16, 22, 14, chassis)
	_fill_rect(img, 8, 18, 8, 18, lite)
	_fill_rect(img, 4, 20, 10, 6, chassis)
	_fill_rect(img, 24, 12, 40, 16, chassis)
	_fill_rect(img, 28, 14, 32, 8, lite)
	_fill_rect(img, 30, 26, 16, 16, chassis)
	_fill_rect(img, 32, 28, 12, 12, barrel)
	_fill_rect(img, 26, 24, 28, 4, accent)
	_fill_rect(img, 62, 14, 86, 12, barrel)
	_fill_rect(img, 144, 12, 14, 16, barrel)
	_fill_rect(img, 40, 2, 30, 12, chassis)
	_fill_rect(img, 42, 4, 26, 8, lite)
	_fill_rect(img, 64, 6, 8, 6, accent)


static func _draw_crescent(img: Image, locked: bool) -> void:
	## Long cutout — SVD / Dragunov-class thumbhole, toy-spy not OEM.
	var wood := _ink(Color("b87a3a"), locked)
	var wood_l := _ink(Color("d4a05a"), locked)
	var metal := _ink(Color("5a5248"), locked)
	var barrel := _ink(Color("3a332c"), locked)
	_fill_rect(img, 4, 12, 32, 20, wood)
	_fill_rect(img, 8, 16, 24, 12, wood_l)
	for yy in range(18, 28):
		for xx in range(12, 24):
			if xx >= 0 and yy >= 0 and xx < img.get_width() and yy < img.get_height():
				img.set_pixel(xx, yy, Color("3a2a1c") if locked else Color(0, 0, 0, 0))
	_fill_rect(img, 8, 28, 10, 12, wood)
	_fill_rect(img, 32, 14, 24, 14, metal)
	_fill_rect(img, 54, 16, 100, 8, barrel)
	_fill_rect(img, 148, 14, 16, 12, barrel)
	_fill_rect(img, 36, 2, 44, 12, _ink(Color("4a3220"), locked))
	_fill_rect(img, 38, 4, 40, 8, _ink(Color("6a4a28"), locked))
	_fill_rect(img, 74, 6, 8, 6, _ink(Color("e07060"), locked))


static func _draw_lock(img: Image) -> void:
	var cx := img.get_width() / 2
	var cy := img.get_height() / 2 + 2
	_fill_rect(img, cx - 7, cy - 2, 14, 12, GOLD)
	_fill_rect(img, cx - 5, cy, 10, 8, INK)
	_stroke_circle(img, cx, cy - 4, 5, GOLD)
	_fill_rect(img, cx - 1, cy + 2, 3, 4, GOLD)


static func _gold_frame(img: Image) -> void:
	var w := img.get_width()
	var h := img.get_height()
	_fill_rect(img, 0, 0, w, 2, GOLD)
	_fill_rect(img, 0, h - 2, w, 2, GOLD)
	_fill_rect(img, 0, 0, 2, h, GOLD)
	_fill_rect(img, w - 2, 0, 2, h, GOLD)


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
