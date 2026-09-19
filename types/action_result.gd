extends RefCounted
## POST /matches/:id/actions response.
## Live: { ok, snapshot, result: ActionResult }
## Mock also fills ok/error/event so scenes stay the same.

const Contract := preload("res://types/contract.gd")
const MarksPayout := preload("res://types/marks_payout.gd")

var ok: bool = false
var error: String = ""
var snapshot: Dictionary = {}
var event: String = Contract.EVENT_SNAPSHOT
## Locked union: select_hex|start|attack|recon|uav|decoy|end_turn|reject
var result: Dictionary = {}


func to_dict() -> Dictionary:
	return {
		"ok": ok,
		"error": error,
		"snapshot": snapshot,
		"event": event,
		"result": result,
	}


static func from_dict(d: Dictionary):
	return from_http(200 if bool(d.get("ok", false)) else 400, d)


static func from_http(status: int, d: Dictionary):
	var parsed = new()
	var snap: Variant = d.get("snapshot", {})
	if snap is Dictionary:
		parsed.snapshot = snap
	elif d.has("matchId") and d.has("status"):
		parsed.snapshot = d.duplicate(true)
	var res: Variant = d.get("result", {})
	if res is Dictionary:
		parsed.result = res
	elif d.has("lastAction") and d.get("lastAction") is Dictionary:
		parsed.result = d.get("lastAction")
	if str(parsed.result.get("type", "")) == Contract.ACT_REJECT:
		parsed.ok = false
		parsed.error = str(parsed.result.get("reason", "rejected"))
		parsed.event = Contract.EVENT_SNAPSHOT
		return parsed
	if d.has("ok"):
		parsed.ok = bool(d.get("ok", false))
	else:
		parsed.ok = status >= 200 and status < 300 and parsed.snapshot.has("matchId")
	parsed.error = str(d.get("error", ""))
	if parsed.error == "" and not parsed.ok:
		parsed.error = "http_%d" % status
	parsed.event = str(d.get("event", Contract.EVENT_SNAPSHOT))
	return parsed


static func fail(code: String, snap: Dictionary = {}):
	var parsed = new()
	parsed.ok = false
	parsed.error = code
	parsed.snapshot = snap
	parsed.event = Contract.EVENT_SNAPSHOT
	parsed.result = {"type": Contract.ACT_REJECT, "reason": code}
	return parsed


func payout():
	var from_result = MarksPayout.from_any(result)
	if from_result.has_marks() or from_result.has_delta() or from_result.reason != "":
		return from_result
	return MarksPayout.from_any(snapshot)


static func ok_result(snap: Dictionary, event_name: String = Contract.EVENT_SNAPSHOT):
	var parsed = new()
	parsed.ok = true
	parsed.error = ""
	parsed.snapshot = snap
	parsed.event = event_name
	var last: Variant = snap.get("lastAction", {})
	if last is Dictionary:
		parsed.result = last
	return parsed
