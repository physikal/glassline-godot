extends Node
## Client-side seat binding. Never stores enemy secrets the snapshot did not give.

const Snapshot := preload("res://types/snapshot.gd")

const HANDLE := "Specter7"
const RIVAL := "RivalSniper"

var match_id: String = ""
var player_id: String = ""
var seat: String = ""
var dummy_player_id: String = ""
var last_snapshot: Dictionary = {}
var marks: int = 0
var ghillie: bool = false


func reset_match() -> void:
	match_id = ""
	player_id = ""
	seat = ""
	dummy_player_id = ""
	last_snapshot = {}


func apply_snapshot(snap: Dictionary) -> void:
	last_snapshot = snap.duplicate(true)
	var you: Variant = snap.get("you", {})
	if you is Dictionary:
		marks = int(you.get("marks", marks))
		if str(you.get("seat", "")) != "":
			seat = str(you.get("seat", seat))


func typed_snapshot() -> Snapshot:
	return Snapshot.from_dict(last_snapshot) as Snapshot
