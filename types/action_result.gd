extends RefCounted
## Spike response for POST /matches/:id/actions.
## Live HTTPS can return the same keys; SSE uses `event` + `snapshot`.

const Contract := preload("res://types/contract.gd")

var ok: bool = false
var error: String = ""
var snapshot: Dictionary = {}
var event: String = Contract.EVENT_SNAPSHOT


func to_dict() -> Dictionary:
	return {
		"ok": ok,
		"error": error,
		"snapshot": snapshot,
		"event": event,
	}


static func from_dict(d: Dictionary):
	var result = new()
	result.ok = bool(d.get("ok", false))
	result.error = str(d.get("error", ""))
	var snap: Variant = d.get("snapshot", {})
	result.snapshot = snap if snap is Dictionary else {}
	result.event = str(d.get("event", Contract.EVENT_SNAPSHOT))
	return result


static func fail(code: String, snap: Dictionary = {}):
	var result = new()
	result.ok = false
	result.error = code
	result.snapshot = snap
	result.event = Contract.EVENT_SNAPSHOT
	return result


static func ok_result(snap: Dictionary, event_name: String = Contract.EVENT_SNAPSHOT):
	var result = new()
	result.ok = true
	result.error = ""
	result.snapshot = snap
	result.event = event_name
	return result
