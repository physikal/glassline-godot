extends RefCounted
## Canon-faithful painted sprites cropped from assets/canon/.
## No rectangle rifles. No circle/rect hex icons. Visual slots only.

const Contract := preload("res://types/contract.gd")

const RIFLE_FIELDBOLT := "res://assets/art_v2/rifle_fieldbolt_plate.png"
const RIFLE_FIELDBOLT_LOCKED := "res://assets/art_v2/rifle_fieldbolt_plate_locked.png"
const RIFLE_RAILFRAME := "res://assets/art_v2/rifle_railframe_plate.png"
const RIFLE_RAILFRAME_LOCKED := "res://assets/art_v2/rifle_railframe_plate_locked.png"
const RIFLE_CRESCENT := "res://assets/art_v2/rifle_crescent_plate.png"
const RIFLE_CRESCENT_LOCKED := "res://assets/art_v2/rifle_crescent_plate_locked.png"
const RIFLE_HELD := "res://assets/art_v2/rifle_held_plate.png"
const DOLL_TEAL := "res://assets/art_v2/doll_teal_plate.png"
const DOLL_GHILLIE := "res://assets/art_v2/doll_ghillie_plate.png"
const FACE_TEAL := "res://assets/art_v2/face_teal_plate.png"
const FACE_GHILLIE := "res://assets/art_v2/face_ghillie_plate.png"
const HEX_OPEN := "res://assets/art_v2/hex_open_legend.png"
const HEX_BRUSH := "res://assets/art_v2/hex_brush_legend.png"
const HEX_HARD := "res://assets/art_v2/hex_hard_legend.png"
const HEX_UNKNOWN := "res://assets/art_v2/hex_unknown_legend.png"
const STAMP_BRUSH := "res://assets/art_v2/stamp_brush.png"
const STAMP_ROCK := "res://assets/art_v2/stamp_rock.png"
const TILE_BRUSH := "res://assets/art_v2/hex_brush_tile.png"
const TILE_HARD := "res://assets/art_v2/hex_hard_tile.png"
const TILE_OPEN := "res://assets/art_v2/hex_open_tile.png"
const TILE_UNKNOWN := "res://assets/art_v2/hex_unknown_tile.png"

## Plate-pixel hang points on the 1280×720 hideout (olive / tan / teal).
const RACK_POS := {
	"gun_fieldbolt": Vector2(24, 192),
	"gun_railframe": Vector2(24, 252),
	"gun_crescent": Vector2(24, 318),
}


static func tex(path: String) -> Texture2D:
	## Prefer the PNG pixels. ResourceLoader placeholders have come back white.
	if FileAccess.file_exists(path):
		var img := Image.new()
		if img.load(path) == OK:
			return ImageTexture.create_from_image(img)
	var loaded = load(path)
	if loaded is Texture2D:
		return loaded
	return null


static func rifle_texture(family: String, state: String = "owned") -> Texture2D:
	var gid := Contract.canonical_gun_id(family)
	var locked := state == "locked" or state == "empty"
	match gid:
		Contract.GUN_RAILFRAME:
			return tex(RIFLE_RAILFRAME_LOCKED if locked else RIFLE_RAILFRAME)
		Contract.GUN_CRESCENT:
			return tex(RIFLE_CRESCENT_LOCKED if locked else RIFLE_CRESCENT)
		_:
			return tex(RIFLE_FIELDBOLT_LOCKED if locked else RIFLE_FIELDBOLT)


static func rifle_held_texture() -> Texture2D:
	return tex(RIFLE_HELD)


static func doll_texture(skin_id: String) -> Texture2D:
	if skin_id == Contract.SHOP_STUB_ITEM_ID:
		return tex(DOLL_GHILLIE)
	return tex(DOLL_TEAL)


static func face_texture(kind: String) -> Texture2D:
	if kind == "ghillie" or kind == "p2":
		return tex(FACE_GHILLIE)
	return tex(FACE_TEAL)


static func hex_legend(kind: String) -> Texture2D:
	match kind:
		Contract.TYPE_OPEN:
			return tex(HEX_OPEN)
		Contract.TYPE_BRUSH:
			return tex(HEX_BRUSH)
		Contract.TYPE_HARD:
			return tex(HEX_HARD)
		_:
			return tex(HEX_UNKNOWN)


static func hex_stamp(kind: String) -> Texture2D:
	## Full painted hex-map face. Never a 26px legend icon / white square.
	return hex_tile(kind)


static func hex_tile(kind: String, variant: int = 0) -> Texture2D:
	## Tileable stamp: one painted face per kind. `variant` is ignored.
	match kind:
		Contract.TYPE_BRUSH:
			return tex(TILE_BRUSH)
		Contract.TYPE_HARD:
			return tex(TILE_HARD)
		Contract.TYPE_OPEN:
			return tex(TILE_OPEN)
		_:
			return tex(TILE_UNKNOWN)


static func rack_position(family: String) -> Vector2:
	var gid := Contract.canonical_gun_id(family)
	if RACK_POS.has(gid):
		return RACK_POS[gid]
	return Vector2(24, 192)


static func optic_accent(family: String) -> Color:
	## Fieldbolt family continuum — warm brass, not a second HUD dialect.
	match Contract.canonical_gun_id(family):
		Contract.GUN_RAILFRAME:
			return Color("c4a86a")
		Contract.GUN_CRESCENT:
			return Color("2f8f78")
		_:
			return Color("9aaa40")
