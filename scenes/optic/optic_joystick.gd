extends Control
## Mobile-first toy thumb stick. Display-only aim nudge — Fire stays a separate tap.

const Chrome := preload("res://scripts/chrome.gd")

signal stick_changed(offset: Vector2)

const WELL := 220.0
const KNOB := 96.0
const TRAVEL := 58.0

var _well: TextureRect
var _knob: TextureRect
var _dragging: bool = false
var offset: Vector2 = Vector2.ZERO


func _ready() -> void:
	custom_minimum_size = Vector2(WELL, WELL)
	size = Vector2(WELL, WELL)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_well = TextureRect.new()
	_well.texture = Chrome.make_optic_stick_well(int(WELL))
	_well.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_well.set_anchors_preset(PRESET_FULL_RECT)
	_well.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_well.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_well)
	_knob = TextureRect.new()
	_knob.texture = Chrome.make_optic_stick_knob(int(KNOB))
	_knob.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_knob.size = Vector2(KNOB, KNOB)
	_knob.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_knob)
	_place_knob()


func pose(value: Vector2) -> void:
	offset = value.limit_length(1.0)
	_place_knob()
	stick_changed.emit(offset)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_dragging = true
			_aim_at(event.position)
			accept_event()
		else:
			_dragging = false
			pose(Vector2.ZERO)
			accept_event()
	elif event is InputEventMouseMotion and _dragging:
		_aim_at(event.position)
		accept_event()


func _aim_at(local: Vector2) -> void:
	var delta := local - size * 0.5
	if delta.length() > TRAVEL:
		delta = delta.normalized() * TRAVEL
	pose(delta / TRAVEL)


func _place_knob() -> void:
	if _knob == null:
		return
	var center := size * 0.5
	_knob.position = center + offset * TRAVEL - Vector2(KNOB, KNOB) * 0.5
