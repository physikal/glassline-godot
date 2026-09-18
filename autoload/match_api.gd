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


func create_match() -> Dictionary:
	if using_live():
		return LiveMatchClient.create_match()
	return MockMatchServer.create_match()


func join(match_id: String, token: String) -> Dictionary:
	if using_live():
		return LiveMatchClient.join(match_id, token)
	return MockMatchServer.join(match_id, token)


func get_snapshot(match_id: String, player_id: String) -> Dictionary:
	if using_live():
		return LiveMatchClient.get_snapshot(match_id, player_id)
	return MockMatchServer.get_snapshot(match_id, player_id)


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
