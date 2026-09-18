extends Node
## Client-side seat binding. Never stores enemy secrets the snapshot did not give.

const Snapshot := preload("res://types/snapshot.gd")
const Contract := preload("res://types/contract.gd")
const MarksPayout := preload("res://types/marks_payout.gd")

const HANDLE := "Specter7"
const RIVAL := "RivalSniper"

var match_id: String = ""
var player_id: String = ""
var seat: String = ""
var dummy_player_id: String = ""
var join_token: String = ""
var dummy_token: String = ""
var last_snapshot: Dictionary = {}
## Display cache of server Marks. Never treat as a writable ledger.
var marks: int = 0
var last_payout: Dictionary = {}
var match_mode: String = Contract.MODE_PVP
var ghillie: bool = false
## -1 follow project/env/export; 0 mock; 1 live
var live_override: int = -1


func reset_match() -> void:
	match_id = ""
	player_id = ""
	seat = ""
	dummy_player_id = ""
	join_token = ""
	dummy_token = ""
	last_snapshot = {}
	match_mode = Contract.MODE_PVP


func bind_marks(balance: int) -> void:
	## Display bind only. Callers must pass a server/mock snapshot value.
	marks = balance


func apply_snapshot(snap: Dictionary) -> void:
	last_snapshot = snap.duplicate(true)
	if str(snap.get("mode", "")) != "":
		match_mode = str(snap.get("mode"))
	var you: Variant = snap.get("you", {})
	if you is Dictionary:
		if str(you.get("seat", "")) != "":
			seat = str(you.get("seat", seat))
	var payout = MarksPayout.from_any(snap)
	if payout.has_marks():
		bind_marks(payout.balance())
	if payout.has_delta() or payout.reason != "":
		last_payout = {
			"marks": payout.marks,
			"marksDelta": payout.marks_delta,
			"reason": payout.reason,
		}


func is_job() -> bool:
	return match_mode == Contract.MODE_SP_JOB


func typed_snapshot() -> Snapshot:
	return Snapshot.from_dict(last_snapshot) as Snapshot


func use_live_api() -> bool:
	if live_override >= 0:
		return live_override == 1
	var env := OS.get_environment("GLASSLINE_USE_LIVE_API")
	if env != "":
		return env.to_lower() in ["1", "true", "yes", "on"]
	if OS.has_feature("use_live_api"):
		return true
	return bool(ProjectSettings.get_setting("glassline/use_live_api", false))


func api_base_url() -> String:
	var env := OS.get_environment("GLASSLINE_API_BASE")
	if env != "":
		return env.rstrip("/")
	var setting: Variant = ProjectSettings.get_setting("glassline/api_base_url", Contract.DEFAULT_API_BASE)
	return str(setting).rstrip("/")


func token_for(pid: String) -> String:
	if pid != "" and pid == dummy_player_id:
		return dummy_token
	return join_token
