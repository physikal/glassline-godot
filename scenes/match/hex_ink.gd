extends Node2D
## Draws hex outlines + tokens above Sprite2D terrain faces.

var board


func _draw() -> void:
	if board != null:
		board.render_ink(self)
