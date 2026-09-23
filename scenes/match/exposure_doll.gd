extends Control
## End-turn exposure doll. Display % is server you.exposureFloor.
## Missing floor fail-closes to 50. Paper-doll of the hideout operative — same plate.

const Chrome := preload("res://scripts/chrome.gd")
const ArtPack := preload("res://scripts/art_pack.gd")
const Contract := preload("res://types/contract.gd")

var exposure_pct: float = 50.0
var equipped_skin_id: String = ""
var _part_optic: String = ""
var _part_stock: String = ""
var _part_barrel: String = ""
var _paper: ColorRect
var _frame: ColorRect
var _banner: ColorRect
var _body: TextureRect
var _cover: ColorRect
var _pct: Label
var _parts: HBoxContainer


func _ready() -> void:
	if custom_minimum_size.x < 176.0 or custom_minimum_size.y < 168.0:
		custom_minimum_size = Vector2(176, 168)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(_on_resized)
	_build()
	_refresh()


func set_exposure(value: float) -> void:
	## Art-plate wash only. Match truth uses bind_floor.
	exposure_pct = clampf(value, 0.0, 100.0)
	_refresh()


func bind_floor(value: Variant, present: bool = true) -> void:
	## Server floor. 0 / missing / unknown stay at the start floor.
	exposure_pct = float(Contract.exposure_floor_or_start(value, present))
	_refresh()


func bind_server_pct(value: float) -> void:
	## Art captures paint a wash. The hunt doll uses bind_floor.
	set_exposure(value)


func displayed_floor() -> int:
	return int(round(exposure_pct))


func exposure_label() -> String:
	return Contract.EXPOSURE_FLOOR_LABEL % displayed_floor()


func bind_parts(optic_id: String, stock_id: String, barrel_id: String) -> void:
	## Equipped slot chips. Empty ids stay off the doll. Never a combat readout.
	_part_optic = optic_id
	_part_stock = stock_id
	_part_barrel = barrel_id
	_refresh_parts()


func bind_equipped(item_id: String) -> void:
	## Same id as hideout operative. Empty = teal jacket. Never invent an id.
	if equipped_skin_id == item_id and _body and _body.texture:
		_refresh()
		return
	equipped_skin_id = item_id
	_refresh()


func _on_resized() -> void:
	_refresh()


func _build() -> void:
	_frame = ColorRect.new()
	_frame.color = Color("3d2618")
	_frame.set_anchors_preset(PRESET_FULL_RECT)
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_frame)

	_paper = ColorRect.new()
	_paper.color = Color("f3e6c8")
	_paper.set_anchors_preset(PRESET_FULL_RECT)
	_paper.offset_left = 4
	_paper.offset_right = -4
	_paper.offset_top = 4
	_paper.offset_bottom = -4
	_paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_paper)

	_banner = ColorRect.new()
	_banner.color = Color("efe0b8")
	_banner.set_anchors_and_offsets_preset(PRESET_TOP_WIDE)
	_banner.offset_left = 4
	_banner.offset_right = -4
	_banner.offset_top = 4
	_banner.offset_bottom = 40
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_banner)

	_body = TextureRect.new()
	## Painted plate — linear keeps hideout proportions, not a nearest-neighbor brick.
	_body.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_body.set_anchors_preset(PRESET_FULL_RECT)
	_body.offset_left = 8
	_body.offset_right = -8
	_body.offset_top = 42
	_body.offset_bottom = -8
	_body.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_body.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_body)

	_cover = ColorRect.new()
	_cover.color = Color(0.22, 0.14, 0.08, 0.48)
	_cover.set_anchors_and_offsets_preset(PRESET_BOTTOM_WIDE)
	_cover.offset_left = 8
	_cover.offset_right = -8
	_cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_cover)

	_pct = Label.new()
	_pct.set_anchors_and_offsets_preset(PRESET_TOP_WIDE)
	_pct.offset_left = 4
	_pct.offset_right = -4
	_pct.offset_top = 6
	_pct.offset_bottom = 38
	_pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pct.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_pct.autowrap_mode = TextServer.AUTOWRAP_OFF
	_pct.clip_text = false
	Chrome.apply_label(_pct, 8, Chrome.INK, true)
	add_child(_pct)

	_parts = HBoxContainer.new()
	_parts.set_anchors_preset(PRESET_BOTTOM_WIDE)
	_parts.offset_left = 8
	_parts.offset_right = -8
	_parts.offset_top = -28
	_parts.offset_bottom = -6
	_parts.alignment = BoxContainer.ALIGNMENT_CENTER
	_parts.add_theme_constant_override("separation", 4)
	_parts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_parts.visible = false
	add_child(_parts)


func _refresh_parts() -> void:
	if _parts == null:
		return
	for child in _parts.get_children():
		child.queue_free()
	var any := false
	for item_id in [_part_optic, _part_stock, _part_barrel]:
		if item_id == "":
			continue
		any = true
		var icon := TextureRect.new()
		icon.texture = Chrome.make_icon(Contract.part_glyph(item_id), Chrome.CREAM, 16)
		icon.custom_minimum_size = Vector2(16, 16)
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_parts.add_child(icon)
		var peg := Chrome.rack_peg("equipped")
		peg.custom_minimum_size = Vector2(6, 14)
		_parts.add_child(peg)
	_parts.visible = any


func _refresh() -> void:
	if _body == null:
		_build()
	_body.texture = ArtPack.doll_texture(equipped_skin_id)
	if _pct:
		_pct.text = exposure_label()
	if _cover:
		var h := size.y
		if h < 8.0:
			h = custom_minimum_size.y
		## Wash only the covered (unexposed) slice — face + jacket stay readable.
		var cover_h := h * ((100.0 - exposure_pct) / 100.0) * 0.55
		_cover.offset_top = -maxf(0.0, cover_h)
		_cover.visible = cover_h > 2.0
