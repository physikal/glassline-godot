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
const JOBS_ORANGE := Color("e87a22")
const ATTACK_RED := Color("c23b3b")
const RECON_BLUE := Color("1f6feb")
const ABILITY_PURPLE := Color("6b4ac7")
## Spent SMOKE plate. Grey muted wood — not a darkened purple.
const SMOKE_SPENT := Color("6d675e")
const SMOKE_SPENT_INK := Color("e4ddd2")
const DECOY_CARAMEL := Color("c46b3a")
const HIGH_GOLD := Color("c9a24a")
## Bandana recolor wash — toy chrome tint, not a new plate / mil-sim art.
const BANDANA_WASH := Color(0.76, 0.32, 0.20, 0.24)
## Hideout poster frame — chunky toy-spy wall art, not an ops board.
const POSTER_PAPER := Color("f3e6c8")
const POSTER_INK := Color("3a2a1c")
const POSTER_TEAL := Color("2f8f78")
const POSTER_STAR := Color("e8b84a")
const COIN_GOLD := Color("f0c44a")
const GEM_PURPLE := Color("b45cff")
const XP_GREEN := Color("3dcf6e")
const OPEN := Color("e6d4a0")
const BRUSH := Color("7cb34a")
const HARD := Color("9aa3ad")
const UNKNOWN := Color("2c2c34")
const FIRE_ORANGE := Color("f0a020")
const P1 := Color("3ecf8e")
const P2 := Color("f08a2a")
## Hideout rack state. Painted green pegs — lobby-canon bolt language.
## Lit leaf / mid plate / deep green. Not a gold strip, not a grey wash.
const RACK_PEG_EQUIPPED := Color("7dce78")
const RACK_PEG_OWNED := Color("4e9a68")
const RACK_PEG_LOCKED := Color("2a5640")
const HEX_LINE := Color("f2e6c4")
const RAIL_CHIP_SIZE := Vector2(92, 64)
## Plate table under the baked ABILITY / HIGH GROUND keys. Matches the
## action-row wood so a cover does not read as a darker rivet panel.
const DESK := Color("3a2a1a")
const DESK_WELL := Color("211508")
const _ArtPack := preload("res://scripts/art_pack.gd")


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


static func marks_chip_text(balance: int) -> String:
	return "MARKS  ★%d" % balance


static func marks_star_text(balance: int) -> String:
	return "★%d" % balance


static func debug_status_ribbons() -> bool:
	## Soft P2: ARMORY / RACK inventory dumps are not production chrome.
	## Headless / capture can opt in with GLASSLINE_DEBUG_STATUS=1 or --debug-status.
	if OS.get_environment("GLASSLINE_DEBUG_STATUS") == "1":
		return true
	return "--debug-status" in OS.get_cmdline_user_args()


static func armory_debug_ribbon() -> String:
	return "ARMORY  ·  Fieldbolt owned  ·  Railframe ★%d  ·  Crescent ★%d  ·  visual only" % [
		Contract.GUN_RAILFRAME_PRICE,
		Contract.GUN_CRESCENT_PRICE,
	]


static func rack_debug_ribbon() -> String:
	return "RACK  ·  Fieldbolt equipped  ·  Railframe owned  ·  Crescent locked  ·  visual only"


static func rack_peg_color(state: String) -> Color:
	## Equipped is the lit leaf. Owned is the mid plate green. Locked stays deep green.
	match state:
		"equipped":
			return RACK_PEG_EQUIPPED
		"owned":
			return RACK_PEG_OWNED
		_:
			return RACK_PEG_LOCKED


static func mute_peg_state(owned: bool, equipped: bool) -> String:
	## Dim locked peg when the row is unowned. No gold strip, no juice cue.
	return part_row_peg_state(owned, equipped)


static func part_row_peg_state(owned: bool, equipped: bool) -> String:
	## Bright leaf / mid green only when the PARTS chip is worn or owned.
	## Unowned T1/T2/T3 rows use the locked peg — the dim mute, not a gold strip.
	if equipped:
		return "equipped"
	if owned:
		return "owned"
	return "locked"


static func rack_bolt_modulate(state: String) -> Color:
	## Theme the existing painted bolt. Locked is a green darken, not the grey wash.
	match state:
		"equipped":
			return Color(1.0, 1.06, 0.94)
		"locked", "empty":
			return Color(0.62, 0.78, 0.58)
		_:
			return Color.WHITE


static func part_slot_chip(item_id: String, state: String) -> PanelContainer:
	## Wood chip + toy glyph + green peg. No gold EQUIPPED strip. No combat copy.
	var equipped := state == "equipped"
	var chip := pill_chip(Color("24160f") if equipped else Color("1a140f"), Color("3d2a1c"))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(row)
	var peg := rack_peg(state if state != "" else "empty")
	peg.custom_minimum_size = Vector2(8, 16)
	row.add_child(peg)
	var icon := TextureRect.new()
	var ink := CREAM if equipped else Color(0.72, 0.66, 0.54, 0.85)
	icon.texture = make_icon(Contract.part_glyph(item_id), ink, 18)
	icon.custom_minimum_size = Vector2(18, 18)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon)
	var label := Label.new()
	label.text = Contract.part_name(item_id)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	apply_label(label, 8, ink, true)
	row.add_child(label)
	chip.set_meta("part_state", state)
	return chip


static func paint_rack_peg(peg: Panel, state: String) -> void:
	## Repaint a dowel in place. Unowned PARTS rows call this with the locked mute.
	if peg == null:
		return
	var fill := rack_peg_color(state)
	var box := flat(fill, 4, fill.darkened(0.42), 2)
	box.content_margin_left = 0
	box.content_margin_right = 0
	box.content_margin_top = 0
	box.content_margin_bottom = 0
	peg.add_theme_stylebox_override("panel", box)
	peg.set_meta("rack_peg_state", state)


static func rack_peg(state: String) -> Panel:
	## Short painted dowel on the bolt. No EQUIPPED / OWNED / LOCKED strip.
	var peg := Panel.new()
	peg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	peg.custom_minimum_size = Vector2(10, 20)
	paint_rack_peg(peg, state)
	return peg


static func chunk_button(text: String, bg: Color, fg: Color, min_size: Vector2 = Vector2(220, 64)) -> Button:
	return _styled_button(text, bg, fg, min_size, 18, 12)


static func paint_chunk_button(button: Button, bg: Color, fg: Color) -> void:
	## Restyle an existing chunk button (active BUY vs disabled / OWNED).
	if button == null:
		return
	var radius := 18
	button.add_theme_color_override("font_color", fg)
	button.add_theme_color_override("font_hover_color", fg)
	button.add_theme_color_override("font_pressed_color", fg)
	button.add_theme_color_override("font_disabled_color", Color(fg, 0.50))
	button.add_theme_stylebox_override("normal", flat(bg, radius, bg.lightened(0.22), 3))
	button.add_theme_stylebox_override("hover", flat(bg.lightened(0.08), radius, Color.WHITE, 3))
	button.add_theme_stylebox_override("pressed", flat(bg.darkened(0.12), radius, bg.darkened(0.3), 3))
	button.add_theme_stylebox_override("disabled", flat(bg.darkened(0.12), radius, bg.darkened(0.28), 3))


static func pill_chip(bg: Color = INK, border: Color = Color("3d2a1c")) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := flat(bg, 22, border, 2)
	box.content_margin_left = 12
	box.content_margin_right = 14
	box.content_margin_top = 7
	box.content_margin_bottom = 7
	panel.add_theme_stylebox_override("panel", box)
	return panel


static func float_box(bg: Color, radius: int = 16, border_px: int = 5) -> StyleBoxFlat:
	## Thick ink + drop. The plate sits on the desk, not inside a wood tray.
	var box := flat(bg, radius, INK, border_px)
	box.shadow_color = Color(0, 0, 0, 0.62)
	box.shadow_size = 10
	box.shadow_offset = Vector2(0, 6)
	return box


static func paint_float_panel(panel: Control, bg: Color, radius: int = 16, border_px: int = 5) -> void:
	if panel == null:
		return
	panel.add_theme_stylebox_override("panel", float_box(bg, radius, border_px))


static func paint_float_key(button: Button) -> void:
	## ATTACK / RECON weight. Same ink and drop as the locked floating keys.
	if button == null:
		return
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var box := button.get_theme_stylebox(state)
		if box is StyleBoxFlat:
			var heavy := (box as StyleBoxFlat).duplicate()
			heavy.set_border_width_all(6)
			heavy.border_color = INK
			heavy.set_corner_radius_all(18)
			heavy.shadow_color = Color(0, 0, 0, 0.58)
			heavy.shadow_size = 8
			heavy.shadow_offset = Vector2(0, 5)
			button.add_theme_stylebox_override(state, heavy)


static func dock_button(text: String, bg: Color, fg: Color, min_size: Vector2, icon_kind: String = "") -> Button:
	var radius := int(min_size.y * 0.5)
	var button := _styled_button(text, bg, fg, min_size, radius, 12 if min_size.x < 340 else 14)
	if icon_kind != "":
		button.icon = make_icon(icon_kind, fg, 26)
		button.add_theme_constant_override("h_separation", 12)
		button.add_theme_constant_override("icon_max_width", 26)
	return button


static func _styled_button(text: String, bg: Color, fg: Color, min_size: Vector2, radius: int, font_px: int) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = min_size
	button.add_theme_font_override("font", pixel_font())
	button.add_theme_font_size_override("font_size", font_px)
	button.add_theme_color_override("font_color", fg)
	button.add_theme_color_override("font_hover_color", fg)
	button.add_theme_color_override("font_pressed_color", fg)
	button.add_theme_color_override("font_disabled_color", Color(fg, 0.45))
	button.add_theme_stylebox_override("normal", flat(bg, radius, bg.lightened(0.22), 3))
	button.add_theme_stylebox_override("hover", flat(bg.lightened(0.08), radius, Color.WHITE, 3))
	button.add_theme_stylebox_override("pressed", flat(bg.darkened(0.12), radius, bg.darkened(0.3), 3))
	button.add_theme_stylebox_override("disabled", flat(bg.darkened(0.35), radius, bg.darkened(0.5), 3))
	return button


static func action_button(kind: String, text: String, bg: Color, fg: Color, min_size: Vector2 = Vector2(220, 64)) -> Button:
	return game_button(kind, text, bg, fg, min_size)


static func game_button(kind: String, text: String, bg: Color, fg: Color, min_size: Vector2 = Vector2(248, 76)) -> Button:
	## Chunky floating match key — thick ink, drop shadow, not a wood-tray inset.
	var button := _styled_button(text, bg, fg, min_size, 18, 13)
	if kind != "":
		button.icon = make_icon(kind, fg, 30)
		button.add_theme_constant_override("h_separation", 12)
		button.add_theme_constant_override("icon_max_width", 30)
	paint_float_key(button)
	return button


static func rail_chip(kind: String, text: String, bg: Color, fg: Color) -> Button:
	## Compact ability-rail key under ABILITY. Same thick ink outline as ATTACK / RECON.
	var button := _styled_button(text, bg, fg, RAIL_CHIP_SIZE, 16, 8)
	button.set_meta("rail_chip", true)
	button.clip_text = false
	if kind != "":
		button.icon = make_icon(kind, fg, 16)
		button.add_theme_constant_override("h_separation", 4)
		button.add_theme_constant_override("icon_max_width", 16)
	_tighten_rail_chip(button)
	return button


static func _tighten_rail_chip(button: Button) -> void:
	if button == null or not bool(button.get_meta("rail_chip", false)):
		return
	button.custom_minimum_size = RAIL_CHIP_SIZE
	button.size = RAIL_CHIP_SIZE
	button.add_theme_font_size_override("font_size", 8)
	button.add_theme_constant_override("icon_max_width", 16)
	button.add_theme_constant_override("h_separation", 4)
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var box := button.get_theme_stylebox(state)
		if box is StyleBoxFlat:
			var tight := (box as StyleBoxFlat).duplicate()
			## Same floating weight as ATTACK / RECON, sized for the three-chip rail.
			tight.set_border_width_all(5)
			tight.border_color = INK
			tight.set_corner_radius_all(14)
			tight.content_margin_left = 4
			tight.content_margin_right = 4
			tight.content_margin_top = 4
			tight.content_margin_bottom = 4
			tight.shadow_color = Color(0, 0, 0, 0.55)
			tight.shadow_size = 6
			tight.shadow_offset = Vector2(0, 4)
			button.add_theme_stylebox_override(state, tight)


static func paint_decoy_button(button: Button, chrome: String) -> void:
	## Locked (below L3) uses the same grey wood plate as a locked SMOKE chip.
	## Unlocked available / spent keep the caramel toy-doll key.
	if button == null:
		return
	var locked := chrome == Contract.DECOY_CHROME_LOCKED
	var lit := chrome == Contract.DECOY_CHROME_AVAILABLE
	var spent := chrome == Contract.DECOY_CHROME_SPENT
	button.set_meta("decoy_lit", lit)
	button.set_meta("decoy_locked", locked)
	if spent and bool(button.get_meta("rail_chip", false)):
		button.text = "%s\nSPENT" % Contract.DECOY_LABEL
	elif spent:
		button.text = "%s SPENT" % Contract.DECOY_LABEL
	else:
		button.text = Contract.DECOY_LABEL
	button.add_theme_font_size_override("font_size", 8 if bool(button.get_meta("rail_chip", false)) else 20)
	button.icon = make_icon("decoy", Color.WHITE, 14 if bool(button.get_meta("rail_chip", false)) else 30)
	if locked:
		button.tooltip_text = Contract.DECOY_TIP
		var radius := 18
		var edge := SMOKE_SPENT.lightened(0.18)
		button.add_theme_stylebox_override("normal", flat(SMOKE_SPENT, radius, edge, 3))
		button.add_theme_stylebox_override("hover", flat(SMOKE_SPENT.lightened(0.04), radius, edge, 3))
		button.add_theme_stylebox_override("pressed", flat(SMOKE_SPENT.darkened(0.06), radius, edge, 3))
		button.add_theme_stylebox_override("disabled", flat(SMOKE_SPENT, radius, edge, 3))
		button.add_theme_color_override("font_color", SMOKE_SPENT_INK)
		button.add_theme_color_override("font_hover_color", SMOKE_SPENT_INK)
		button.add_theme_color_override("font_pressed_color", SMOKE_SPENT_INK)
		button.add_theme_color_override("font_disabled_color", SMOKE_SPENT_INK)
		for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
			button.add_theme_color_override("icon_%s_color" % state, SMOKE_SPENT_INK)
		_tighten_rail_chip(button)
		return
	paint_chunk_button(button, DECOY_CARAMEL, Color.WHITE)
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		button.add_theme_color_override("icon_%s_color" % state, Color.WHITE)
	if lit:
		button.tooltip_text = Contract.DECOY_COPY
	elif spent:
		button.tooltip_text = Contract.DECOY_SPENT_COPY
	else:
		button.tooltip_text = Contract.DECOY_ABSENT_COPY
	_tighten_rail_chip(button)


static func smoke_chip() -> Button:
	## Ability chrome. Lit/muted is paint_smoke_chip — never a HIGH GROUND key.
	var button := game_button("smoke", Contract.SMOKE_LABEL, ABILITY_PURPLE, Color.WHITE, Vector2(248, 64))
	paint_smoke_chip(button, false)
	return button


static func paint_smoke_chip(button: Button, available: bool, locked: bool = false) -> void:
	## Lit hot purple only while the charge is unlocked.
	## Locked (below L5) and spent share the Soft P2 grey wood plate. Same puff.
	if button == null:
		return
	var lit := available and not locked
	button.set_meta("smoke_lit", lit)
	button.set_meta("smoke_locked", locked and not lit)
	button.text = Contract.SMOKE_LABEL
	var bg := ABILITY_PURPLE if lit else SMOKE_SPENT
	var fg := Color.WHITE if lit else SMOKE_SPENT_INK
	paint_chunk_button(button, bg, fg)
	## One white puff. Locked and spent multiply it by the grey ink — no second texture.
	var icon_px := 14 if bool(button.get_meta("rail_chip", false)) else 30
	button.icon = make_icon("smoke", Color.WHITE, icon_px)
	var icon_tint := Color.WHITE if lit else SMOKE_SPENT_INK
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		button.add_theme_color_override("icon_%s_color" % state, icon_tint)
	if not lit:
		## Locked stays tappable. Spent is disabled. Both keep this wood plate —
		## do not darken it back toward purple or fade the word out.
		var radius := 18
		var edge := SMOKE_SPENT.lightened(0.18)
		button.add_theme_stylebox_override("normal", flat(SMOKE_SPENT, radius, edge, 3))
		button.add_theme_stylebox_override("hover", flat(SMOKE_SPENT.lightened(0.04), radius, edge, 3))
		button.add_theme_stylebox_override("pressed", flat(SMOKE_SPENT.darkened(0.06), radius, edge, 3))
		button.add_theme_stylebox_override("disabled", flat(SMOKE_SPENT, radius, edge, 3))
		button.add_theme_color_override("font_color", SMOKE_SPENT_INK)
		button.add_theme_color_override("font_hover_color", SMOKE_SPENT_INK)
		button.add_theme_color_override("font_pressed_color", SMOKE_SPENT_INK)
		button.add_theme_color_override("font_disabled_color", SMOKE_SPENT_INK)
	if lit:
		button.tooltip_text = Contract.SMOKE_COPY
	elif locked:
		button.tooltip_text = Contract.SMOKE_LOCKED_TOAST
	else:
		button.tooltip_text = Contract.SMOKE_SPENT_COPY
	_tighten_rail_chip(button)


static func high_ground_chip(active: bool = false) -> Control:
	## Snapshot-bound plate chip — not a 4th action key. Never invent the bonus.
	## Floating plate: stacked hexes, thick ink, drop shadow over the desk.
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.custom_minimum_size = Vector2(300, 112)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	var icon := TextureRect.new()
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.custom_minimum_size = Vector2(56, 56)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon)
	var lbl := Label.new()
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.custom_minimum_size = Vector2(196, 72)
	row.add_child(lbl)
	panel.add_child(row)
	panel.set_meta("high_icon", icon)
	panel.set_meta("high_label", lbl)
	paint_high_ground_chip(panel, active)
	return panel


static func describe_attack_result(last: Dictionary) -> String:
	## Plate toast from server result fields only. Never invent cover / chance.
	## No IN COVER chip this slice — result chrome only.
	if bool(last.get("decoyCleared", false)):
		return _attack_result_line("Toy doll gone.", last)
	var head := "Shot hit." if bool(last.get("hit", false)) else "Shot missed."
	return _attack_result_line(head, last)


static func _attack_result_line(head: String, last: Dictionary) -> String:
	var bits: PackedStringArray = [head]
	if last.has("hitChance"):
		var pct := int(round(float(last.get("hitChance", 0.0)) * 100.0))
		bits.append("Chance %d%%." % pct)
	var mods: PackedStringArray = []
	if last.has("highGroundApplied"):
		if bool(last.get("highGroundApplied")):
			mods.append(Contract.HIGH_GROUND_APPLIED_COPY)
		else:
			mods.append(Contract.HIGH_GROUND_SKIPPED_COPY)
	if last.has("coverApplied"):
		if bool(last.get("coverApplied")):
			mods.append(Contract.COVER_APPLIED_COPY)
		else:
			mods.append(Contract.COVER_SKIPPED_COPY)
	if not mods.is_empty():
		bits.append("%s." % " · ".join(mods))
	## Soft P2: server fields stay the source of truth — do not stamp "(server)".
	return " ".join(bits)


static func describe_last_action(last: Dictionary) -> String:
	## Player-facing result toast. Server flags only; no debug suffix.
	var kind := str(last.get("type", ""))
	match kind:
		Contract.ACT_ATTACK:
			return describe_attack_result(last)
		Contract.ACT_RECON:
			var spotted: Variant = last.get("spotted", last.get("found", false))
			return "lastAction recon  spotted=%s" % str(spotted)
		Contract.ACT_REJECT:
			var reason := str(last.get("reason", ""))
			if reason == Contract.DECOY_LOCKED_REASON:
				return Contract.DECOY_LOCKED_TOAST
			return "lastAction reject  %s" % reason
		Contract.ACT_UAV:
			return "lastAction uav  revealed=%s" % str(last.get("revealed", false))
		Contract.ACT_DECOY:
			var planted: Variant = last.get("hex", null)
			if planted is Dictionary:
				return "lastAction decoy  planted Q%d R%d  (toy doll)" % [
					int(planted.get("q", 0)),
					int(planted.get("r", 0)),
				]
			return "lastAction decoy  planted  (toy doll)"
		Contract.ACT_SMOKE:
			return Contract.SMOKE_TOAST
		Contract.ACT_FORFEIT:
			return "lastAction forfeit  winner=%s" % str(last.get("winner", ""))
		Contract.ACT_END_TURN:
			return "lastAction end_turn  moved=%s" % str(last.get("moved", false))
		Contract.ACT_SELECT_HEX:
			return "lastAction select_hex  seat %s" % str(last.get("seat", ""))
		Contract.ACT_START:
			## Soft P2: seat-order dump is not player-facing board chrome.
			return ""
		_:
			return ""


static func mute_button_text(muted: bool) -> String:
	return "MUTE" if muted else "SOUND"


static func mute_button_tip(muted: bool) -> String:
	if muted:
		return "Sound off. Hunt stays readable."
	return "Toy clicks. Mute anytime."


static func paint_high_ground_chip(panel: Control, active: bool) -> void:
	## Lit + “+10%” only while snapshot you.highGroundActive. Muted otherwise.
	if panel == null:
		return
	## Thick ink always. Gold border read as a tray highlight. +10% only while lit.
	var bg := Color("2a2014") if active else Color("1c140e")
	var box := float_box(bg, 16, 6)
	box.content_margin_left = 12
	box.content_margin_right = 14
	box.content_margin_top = 10
	box.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", box)
	var icon: TextureRect = panel.get_meta("high_icon") if panel.has_meta("high_icon") else null
	var lbl: Label = panel.get_meta("high_label") if panel.has_meta("high_label") else null
	if icon:
		icon.texture = make_icon("high", Color("8fd15a") if active else Color("6a9a3c"), 56)
		icon.modulate = Color.WHITE
	if lbl:
		if active:
			lbl.text = "%s\n+10%% ACCURACY" % Contract.HIGH_GROUND_LABEL
			apply_label(lbl, 11, CREAM, true)
		else:
			lbl.text = Contract.HIGH_GROUND_LABEL
			apply_label(lbl, 11, CREAM, true)
	panel.tooltip_text = Contract.HIGH_GROUND_COPY if active else Contract.HIGH_GROUND_MUTED_COPY
	panel.set_meta("high_active", active)


static func plate_hotspot(min_size: Vector2) -> Button:
	## Invisible hit over the painted match-board key. Plate carries the weight.
	var button := Button.new()
	button.text = ""
	button.custom_minimum_size = min_size
	button.size = min_size
	button.flat = true
	var empty := StyleBoxEmpty.new()
	for style in ["normal", "hover", "pressed", "disabled", "focus"]:
		button.add_theme_stylebox_override(style, empty)
	button.add_theme_color_override("font_color", Color(0, 0, 0, 0))
	button.add_theme_color_override("font_hover_color", Color(0, 0, 0, 0))
	button.add_theme_color_override("font_pressed_color", Color(0, 0, 0, 0))
	button.add_theme_color_override("font_disabled_color", Color(0, 0, 0, 0))
	button.add_theme_color_override("icon_normal_color", Color(0, 0, 0, 0))
	return button


static func hex_stamp(kind: String) -> Texture2D:
	return _ArtPack.hex_stamp(kind)


static func hex_tile(kind: String, variant: int = 0) -> Texture2D:
	return _ArtPack.hex_tile(kind, variant)


static func hex_legend_tex(kind: String) -> Texture2D:
	return _ArtPack.hex_legend(kind)


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


static func grain_texture(base: Color, width: int = 128, height: int = 128) -> Texture2D:
	## Low-contrast desk grain. A flat ColorRect reads as an inset wood tray.
	var img := Image.create(width, height, false, Image.FORMAT_RGB8)
	var noise := FastNoiseLite.new()
	noise.seed = 19
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = 0.08
	for y in height:
		for x in width:
			var n := noise.get_noise_2d(float(x), float(y))
			var lift := 0.06 * n
			img.set_pixel(x, y, Color(
				clampf(base.r + lift, 0.0, 1.0),
				clampf(base.g + lift * 0.85, 0.0, 1.0),
				clampf(base.b + lift * 0.55, 0.0, 1.0)
			))
	return ImageTexture.create_from_image(img)


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
		"attack", "loadout":
			_icon_crosshair(img, color)
		"recon":
			_icon_binoculars(img, color)
		"ability", "star":
			_icon_star(img, color)
		"smoke", "puff":
			_icon_smoke_puff(img, color)
		"decoy":
			_icon_toy_doll(img, color)
		"clock":
			_icon_clock(img, color)
		"high", "highground":
			_icon_high_ground(img, color)
		"brush", "leaf":
			_icon_leaf(img, color)
		"play":
			_icon_play(img, color)
		"jobs":
			_icon_clipboard(img, color)
		"copy", "clipboard":
			_icon_clipboard(img, color)
		"share":
			_icon_share(img, color)
		"invite":
			_icon_ticket(img, color)
		"practice":
			_icon_practice(img, color)
		"quick", "queue":
			_icon_binoculars(img, color)
		"coin":
			_icon_coin(img, color)
		"gem":
			_icon_gem(img, color)
		"speaker", "sound":
			_icon_speaker(img, color, false)
		"speaker_off", "mute":
			_icon_speaker(img, color, true)
		"part_optic", "optic":
			_icon_toy_optic(img, color)
		"part_stock", "stock":
			_icon_toy_stock(img, color)
		"part_barrel", "barrel":
			_icon_toy_barrel(img, color)
		_:
			_icon_star(img, color)
	return ImageTexture.create_from_image(img)


static func make_face(kind: String, px: int = 44) -> Texture2D:
	## Same hideout operative crop — not a mushy circle next to painted wood.
	var plate: Texture2D = _ArtPack.face_texture("p2" if kind == "p2" else "p1")
	if plate:
		var src := plate.get_image()
		if src:
			if src.is_compressed():
				src.decompress()
			src.resize(px, px, Image.INTERPOLATE_NEAREST)
			return ImageTexture.create_from_image(src)
		return plate
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


static func make_optic_stick_well(px: int = 220) -> Texture2D:
	## Chunky toy well — same gray plastic weight as the plate plus-pad.
	var img := Image.create(px, px, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := px / 2
	_fill_circle(img, c, c, c - 1, Color("06090e"))
	_fill_circle(img, c, c, c - 6, Color("2a2c30"))
	_fill_circle(img, c, c, c - 14, Color("3a3c40"))
	_fill_circle(img, c, c, c - 22, Color("1c1e22"))
	_stroke_circle(img, c, c, c - 8, Color("5a5c60"))
	_stroke_circle(img, c, c, c - 20, Color("4a4c50"))
	_fill_circle(img, c, c, c - 36, Color("0c1016"))
	_stroke_circle(img, c, c, c - 38, Color("2a2c30"))
	return ImageTexture.create_from_image(img)


static func make_optic_stick_knob(px: int = 96) -> Texture2D:
	## Raised plastic thumb — gold ring matches FAR/MID plate chips.
	var img := Image.create(px, px, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := px / 2
	_fill_circle(img, c, c + 3, c - 2, Color("141618"))
	_fill_circle(img, c, c, c - 2, Color("2c2e32"))
	_fill_circle(img, c, c - 2, c - 8, Color("4a4c50"))
	_stroke_circle(img, c, c, c - 4, HIGH_GOLD)
	_stroke_circle(img, c, c, c - 7, Color("e8c86a"))
	_fill_circle(img, c - 8, c - 10, 12, Color("6a6c70"))
	_fill_circle(img, c, c + 2, 10, Color("1a1c20"))
	_stroke_circle(img, c, c + 2, 6, Color("c9a24a"))
	return ImageTexture.create_from_image(img)


static func make_hideout_poster(width: int = 96, height: int = 128) -> Texture2D:
	## Chunky toy-spy wall poster. Gold frame + cream paper. No maps / pins / ops board.
	var img := Image.create(width, height, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var wood := Color("3d2618")
	var gold := HIGH_GOLD
	var paper := POSTER_PAPER
	var ink := POSTER_INK
	var skin := Color("e6c39a")
	_fill_rect(img, 0, 0, width, height, wood)
	_fill_rect(img, 3, 3, width - 6, height - 6, gold)
	_fill_rect(img, 9, 9, width - 18, height - 18, Color("2a1c14"))
	_fill_rect(img, 12, 12, width - 24, height - 24, paper)
	## Corner tape — hideout pin-up, not a briefing board.
	var tape := Color("e8d08a")
	_fill_rect(img, 6, 6, 14, 6, tape)
	_fill_rect(img, width - 20, 6, 14, 6, tape)
	_fill_rect(img, 6, height - 12, 14, 6, tape)
	_fill_rect(img, width - 20, height - 12, 14, 6, tape)
	var cx := width / 2
	## Gold star badge
	_fill_circle(img, cx, 26, 8, POSTER_STAR)
	_fill_circle(img, cx, 26, 4, Color("fff3b0"))
	## Toy spy — teal beanie, chunky goggles, hoodie. Cozy, not mil-sim.
	_fill_circle(img, cx, 56, 16, POSTER_TEAL)
	_fill_circle(img, cx, 60, 14, skin)
	_fill_rect(img, cx - 14, 42, 28, 10, POSTER_TEAL)
	_fill_rect(img, cx - 13, 52, 11, 8, ink)
	_fill_rect(img, cx + 2, 52, 11, 8, ink)
	_fill_rect(img, cx - 10, 54, 5, 4, Color("8fd4c4"))
	_fill_rect(img, cx + 5, 54, 5, 4, Color("8fd4c4"))
	_fill_rect(img, cx - 2, 55, 4, 3, ink)
	_fill_rect(img, cx - 5, 66, 10, 3, Color("c45a4a"))
	_fill_rect(img, cx - 16, 74, 32, 22, POSTER_TEAL)
	_fill_rect(img, cx - 6, 76, 12, 10, skin)
	## Little binoculars doodle — toy spy, not a range card.
	_stroke_circle(img, cx - 10, height - 24, 6, ink)
	_stroke_circle(img, cx + 10, height - 24, 6, ink)
	_fill_circle(img, cx - 10, height - 24, 2, POSTER_TEAL)
	_fill_circle(img, cx + 10, height - 24, 2, POSTER_TEAL)
	_fill_rect(img, cx - 5, height - 26, 10, 4, ink)
	return ImageTexture.create_from_image(img)


static func make_hideout_rug(width: int = 480, height: int = 96) -> Texture2D:
	## Chunky toy rug for the hideout floor. Teal field, gold band, cream fringe.
	## Sits on lobby-canon wood. Not a map, not mil-sim camo.
	var img := Image.create(width, height, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var field := Color("1f6f62")
	var band := Color("c9a24a")
	var cream := POSTER_PAPER
	var ink := Color("14241f")
	var fringe := Color("f4efe4")
	var margin := 10
	_fill_rect(img, margin, 8, width - margin * 2, height - 16, ink)
	_fill_rect(img, margin + 4, 12, width - (margin + 4) * 2, height - 24, field)
	_fill_rect(img, margin + 10, 18, width - (margin + 10) * 2, 8, band)
	_fill_rect(img, margin + 10, height - 26, width - (margin + 10) * 2, 8, band)
	var cx := width / 2
	var cy := height / 2
	_fill_rect(img, cx - 18, cy - 10, 36, 20, cream)
	_fill_rect(img, cx - 6, cy - 16, 12, 32, cream)
	_fill_rect(img, cx - 4, cy - 4, 8, 8, band)
	var step := 14
	var x := margin
	while x < width - margin:
		_fill_rect(img, x, 2, 6, 8, fringe)
		_fill_rect(img, x, height - 10, 6, 8, fringe)
		x += step
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


static func _icon_smoke_puff(img: Image, color: Color) -> void:
	## Toy-spy puff. Soft clouds — not a canister or a terrain stamp.
	_fill_circle(img, 8, 16, 4, color)
	_fill_circle(img, 14, 12, 6, color)
	_fill_circle(img, 21, 16, 4, color)
	_fill_circle(img, 14, 16, 3, color.lightened(0.2))


static func _icon_toy_doll(img: Image, color: Color) -> void:
	## Stuffed toy dummy — cozy, not mil-sim smoke.
	_fill_circle(img, 14, 8, 5, color)
	_fill_circle(img, 14, 18, 7, color)
	_fill_rect(img, 6, 14, 4, 6, color)
	_fill_rect(img, 18, 14, 4, 6, color)
	_fill_circle(img, 12, 7, 1, INK)
	_fill_circle(img, 16, 7, 1, INK)
	_fill_rect(img, 13, 10, 3, 1, INK)


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


static func _fill_pointy_hex(img: Image, cx: float, cy: float, radius: float, color: Color) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var ap := radius * 0.8660254
	for y in h:
		for x in w:
			var dx := absf(float(x) + 0.5 - cx)
			var dy := absf(float(y) + 0.5 - cy)
			var slack := minf(ap - dx, ap - (dx * 0.5 + dy * 0.8660254))
			if slack >= 0.0:
				img.set_pixel(x, y, color)


static func _icon_high_ground(img: Image, color: Color) -> void:
	## Three stacked pointy hexes — the plate HIGH GROUND chip, not a mountain.
	var w := float(img.get_width())
	var h := float(img.get_height())
	var ink := Color(0.08, 0.06, 0.05, 1.0)
	var spots := [
		[w * 0.50, h * 0.74, w * 0.22],
		[w * 0.32, h * 0.46, w * 0.18],
		[w * 0.68, h * 0.46, w * 0.18],
		[w * 0.50, h * 0.22, w * 0.15],
	]
	for spot in spots:
		_fill_pointy_hex(img, spot[0], spot[1], spot[2] + 1.6, ink)
		_fill_pointy_hex(img, spot[0], spot[1], spot[2], color)


static func _icon_toy_optic(img: Image, color: Color) -> void:
	## Round toy glass. A spyglass lens, not a mil-dot scope.
	_stroke_circle(img, 14, 14, 9, color)
	_fill_circle(img, 14, 14, 5, color)
	_fill_circle(img, 12, 12, 2, Color("f4efe4"))
	_fill_rect(img, 20, 16, 6, 3, color)


static func _icon_toy_stock(img: Image, color: Color) -> void:
	## Chunky wooden shoulder rest. Cozy block, not a rifle stock schematic.
	_fill_rect(img, 6, 8, 16, 8, color)
	_fill_rect(img, 8, 16, 10, 8, color)
	_fill_rect(img, 16, 14, 6, 4, WOOD)


static func _icon_toy_barrel(img: Image, color: Color) -> void:
	## Short toy tube with a rounded cap. Not a muzzle device.
	_fill_rect(img, 4, 12, 16, 5, color)
	_fill_circle(img, 21, 14, 4, color)
	_fill_rect(img, 6, 13, 4, 2, Color("f4efe4"))


static func _icon_leaf(img: Image, color: Color) -> void:
	## Toy leaf on the wood plate. Stem stays wood, not the legend green swatch.
	_fill_circle(img, 16, 16, 7, color)
	_fill_circle(img, 10, 12, 5, color)
	_fill_rect(img, 13, 16, 3, 9, WOOD)


static func _icon_clock(img: Image, color: Color) -> void:
	_stroke_circle(img, 14, 14, 10, color)
	_fill_rect(img, 13, 8, 2, 7, color)
	_fill_rect(img, 13, 13, 7, 2, color)


static func _icon_play(img: Image, color: Color) -> void:
	for y in range(5, 24):
		var dy := absi(y - 14)
		var width := 13 - dy
		if width > 0:
			_fill_rect(img, 8, y, width, 1, color)


static func _icon_coin(img: Image, color: Color) -> void:
	_fill_circle(img, 14, 14, 10, color)
	_stroke_circle(img, 14, 14, 10, INK)
	_fill_circle(img, 14, 14, 4, Color("fff3b0"))


static func _icon_gem(img: Image, color: Color) -> void:
	_fill_rect(img, 13, 4, 3, 20, color)
	_fill_rect(img, 8, 8, 13, 12, color)
	_fill_rect(img, 10, 6, 9, 16, color)
	_fill_rect(img, 12, 10, 5, 5, Color(1, 1, 1, 0.45))


static func _icon_practice(img: Image, color: Color) -> void:
	## Quiet-hunt toy spy — beanie and round goggles. Not a sight, badge, or kit.
	_fill_rect(img, 6, 3, 14, 5, color)
	_fill_rect(img, 4, 7, 18, 3, color)
	_fill_circle(img, 13, 15, 8, color)
	_fill_rect(img, 5, 12, 16, 4, color)
	var lens := Color("f4efe4")
	_fill_circle(img, 9, 14, 3, lens)
	_fill_circle(img, 17, 14, 3, lens)
	_fill_circle(img, 9, 14, 1, color)
	_fill_circle(img, 17, 14, 1, color)


static func _icon_share(img: Image, color: Color) -> void:
	## Folded note leaving the table. Cozy slip, not a megaphone or QR.
	_fill_rect(img, 3, 8, 14, 14, color)
	_fill_rect(img, 5, 10, 10, 10, Color(0, 0, 0, 0.28))
	_fill_rect(img, 6, 12, 7, 2, color)
	_fill_rect(img, 6, 16, 5, 2, color)
	_fill_rect(img, 17, 13, 8, 3, color)
	_fill_rect(img, 21, 10, 3, 9, color)


static func _icon_ticket(img: Image, color: Color) -> void:
	## Wartable invite slip — cozy, not ranked queue chrome.
	_fill_rect(img, 4, 8, 20, 13, color)
	_fill_rect(img, 6, 10, 16, 9, Color(0, 0, 0, 0.28))
	_fill_rect(img, 8, 12, 8, 2, color)
	_fill_rect(img, 8, 16, 5, 2, color)
	_fill_circle(img, 20, 14, 3, color)
	_fill_circle(img, 20, 14, 1, INK)


static func _icon_speaker(img: Image, color: Color, off: bool) -> void:
	## Toy speaker. Live draws two sound bars. Muted draws a slash. No mic / radio kit.
	var s := mini(img.get_width(), img.get_height())
	var body_w := maxi(4, int(float(s) * 0.26))
	var body_h := maxi(5, int(float(s) * 0.34))
	var body_x := int(float(s) * 0.08)
	var body_y := int(float(s) * 0.33)
	_fill_rect(img, body_x, body_y, body_w, body_h, color)
	var cone_x := body_x + body_w - 1
	_fill_rect(img, cone_x, int(float(s) * 0.24), maxi(3, int(float(s) * 0.16)), int(float(s) * 0.52), color)
	_fill_rect(img, cone_x + int(float(s) * 0.12), int(float(s) * 0.14), maxi(2, int(float(s) * 0.12)), int(float(s) * 0.72), color)
	if off:
		_line(img, float(s) * 0.62, float(s) * 0.18, float(s) * 0.92, float(s) * 0.82, color)
		_line(img, float(s) * 0.68, float(s) * 0.16, float(s) * 0.98, float(s) * 0.80, color)
	else:
		_fill_rect(img, int(float(s) * 0.68), int(float(s) * 0.36), maxi(2, int(float(s) * 0.08)), int(float(s) * 0.28), color)
		_fill_rect(img, int(float(s) * 0.82), int(float(s) * 0.22), maxi(2, int(float(s) * 0.08)), int(float(s) * 0.56), color)


static func _icon_clipboard(img: Image, color: Color) -> void:
	_fill_rect(img, 7, 6, 15, 18, color)
	_fill_rect(img, 9, 8, 11, 14, Color(0, 0, 0, 0.28))
	_fill_rect(img, 10, 3, 9, 5, color)
	_fill_rect(img, 10, 11, 9, 2, color)
	_fill_rect(img, 10, 15, 9, 2, color)
	_fill_rect(img, 10, 19, 7, 2, color)


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
