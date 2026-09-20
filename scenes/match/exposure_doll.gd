extends Control
## End-turn exposure doll. Display is snapshot you.exposurePct (server).
## Same hideout operative crop — paper-doll read, not a blocky avatar.

const Chrome := preload("res://scripts/chrome.gd")
const ArtPack := preload("res://scripts/art_pack.gd")
const Contract := preload("res://types/contract.gd")

var exposure_pct: float = 50.0
var equipped_skin_id: String = ""
var _body: TextureRect
var _cover: ColorRect
var _pct: Label


func _ready() -> void:
	if custom_minimum_size.x < 88.0 or custom_minimum_size.y < 118.0:
		custom_minimum_size = Vector2(88, 118)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	_refresh()


func set_exposure(value: float) -> void:
	exposure_pct = clampf(value, 0.0, 100.0)
	_refresh()


func bind_server_pct(value: float) -> void:
	## A2: doll follows server you.exposurePct only.
	set_exposure(value)


func bind_equipped(item_id: String) -> void:
	## Same id as hideout operative. Empty = teal jacket. Never invent an id.
	if equipped_skin_id == item_id and _body and _body.texture:
		return
	equipped_skin_id = item_id
	_refresh()


func _build() -> void:
	var frame := ColorRect.new()
	frame.color = Color(0.16, 0.10, 0.07, 0.55)
	frame.set_anchors_preset(PRESET_FULL_RECT)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(frame)

	_body = TextureRect.new()
	_body.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_body.set_anchors_preset(PRESET_FULL_RECT)
	_body.offset_left = 4
	_body.offset_right = -4
	_body.offset_top = 16
	_body.offset_bottom = -4
	_body.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_body.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_body)

	_cover = ColorRect.new()
	_cover.color = Color(0.24, 0.42, 0.18, 0.50)
	_cover.set_anchors_and_offsets_preset(PRESET_BOTTOM_WIDE)
	_cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_cover)

	_pct = Label.new()
	_pct.position = Vector2(6, 2)
	_pct.size = Vector2(80, 16)
	Chrome.apply_label(_pct, 8, Chrome.HIGH_GOLD, true)
	add_child(_pct)


func _refresh() -> void:
	if _body == null:
		_build()
	_body.texture = ArtPack.doll_texture(equipped_skin_id)
	if _pct:
		_pct.text = "%d%%" % int(exposure_pct)
	if _cover:
		var h := size.y
		if h < 8.0:
			h = custom_minimum_size.y
		var cover_h := h * ((100.0 - exposure_pct) / 100.0) * 0.72
		_cover.offset_top = -maxf(0.0, cover_h)
		_cover.visible = cover_h > 2.0
