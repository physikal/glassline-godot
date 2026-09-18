extends Node
## Facade: MockMatchServer (default) or LiveMatchClient.
## Scenes call only these methods so the live swap is drop-in.

signal match_event(player_id: String, event_name: String, snapshot: Dictionary)

const ActionResult := preload("res://types/action_result.gd")


func _ready() -> void:
	MockMatchServer.match_event.connect(_relay)
	LiveMatchClient.match_event.connect(_relay)


func _relay(player_id: String, event_name: String, snapshot: Dictionary) -> void:
	match_event.emit(player_id, event_name, snapshot)


func using_live() -> bool:
	return ClientSession.use_live_api()


func create_match(opts: Dictionary = {}) -> Dictionary:
	if using_live():
		return LiveMatchClient.create_match(opts)
	return MockMatchServer.create_match(opts)


func wallet() -> Dictionary:
	if using_live():
		return LiveMatchClient.wallet()
	return MockMatchServer.wallet()


func create_job(tier: int = 1) -> Dictionary:
	if using_live():
		return LiveMatchClient.create_job(tier)
	return MockMatchServer.create_job(tier)


func get_job(job_id: String) -> Dictionary:
	if using_live():
		return LiveMatchClient.get_job(job_id)
	return MockMatchServer.get_job(job_id)


func heartbeat() -> Dictionary:
	if using_live():
		return LiveMatchClient.heartbeat()
	return {"ok": true, "mock": true}


func join(match_id: String, token: String) -> Dictionary:
	if using_live():
		return LiveMatchClient.join(match_id, token)
	return MockMatchServer.join(match_id, token)


func get_snapshot(match_id: String, player_id: String) -> Dictionary:
	if using_live():
		return LiveMatchClient.get_snapshot(match_id, player_id)
	return MockMatchServer.get_snapshot(match_id, player_id)


func reconnect() -> Dictionary:
	## A2: re-GET the caller snapshot and replace client state. No local merge.
	if ClientSession.match_id == "" or ClientSession.player_id == "":
		return {}
	var fresh: Dictionary = get_snapshot(ClientSession.match_id, ClientSession.player_id)
	if not fresh.is_empty():
		ClientSession.apply_snapshot(fresh)
	return fresh


func apply_action(match_id: String, player_id: String, action: Dictionary) -> ActionResult:
	if using_live():
		return LiveMatchClient.apply_action(match_id, player_id, action)
	return MockMatchServer.apply_action(match_id, player_id, action)


func clear_all() -> void:
	LiveMatchClient.clear_all()
	MockMatchServer.clear_all()


func start_events() -> void:
	if using_live() and ClientSession.match_id != "" and ClientSession.join_token != "":
		LiveMatchClient.start_events(ClientSession.match_id, ClientSession.join_token)


func stop_events() -> void:
	LiveMatchClient.stop_events()


func health() -> Dictionary:
	if using_live():
		return LiveMatchClient.health()
	return {"ok": true, "mock": true}
