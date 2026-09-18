extends RefCounted
## Chunky hideout HUD helpers — match lobby-canon language, not mil-sim.

const Contract := preload("res://types/contract.gd")

const WOOD := Color("6b4428")
const WOOD_DARK := Color("2a1c14")
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
const OPEN := Color("e2d2a4")
const BRUSH := Color("7eaf55")
const HARD := Color("8b9098")
const UNKNOWN := Color("2a2a32")
const FIRE_ORANGE := Color("f0a020")


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
	button.add_theme_font_size_override("font_size", 14)
	button.add_theme_color_override("font_color", fg)
	button.add_theme_color_override("font_hover_color", fg)
	button.add_theme_color_override("font_pressed_color", fg)
	button.add_theme_color_override("font_disabled_color", Color(fg, 0.45))
	button.add_theme_stylebox_override("normal", flat(bg, 18, bg.lightened(0.25), 3))
	button.add_theme_stylebox_override("hover", flat(bg.lightened(0.08), 18, Color.WHITE, 3))
	button.add_theme_stylebox_override("pressed", flat(bg.darkened(0.12), 18, bg.darkened(0.3), 3))
	button.add_theme_stylebox_override("disabled", flat(bg.darkened(0.35), 18, bg.darkened(0.5), 3))
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
