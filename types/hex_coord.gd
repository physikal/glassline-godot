extends RefCounted
## Axial hex {q,r} matching the locked contract.

var q: int = 0
var r: int = 0


func _init(p_q: int = 0, p_r: int = 0) -> void:
	q = p_q
	r = p_r


func to_dict() -> Dictionary:
	return {"q": q, "r": r}


func key() -> String:
	return "%d,%d" % [q, r]


func equals_dict(d: Variant) -> bool:
	if d == null or not (d is Dictionary):
		return false
	return q == int(d.get("q", -99)) and r == int(d.get("r", -98))


static func from_dict(d: Dictionary):
	return new(int(d.get("q", 0)), int(d.get("r", 0)))


static func try_from(d: Variant):
	if d == null or not (d is Dictionary):
		return null
	return from_dict(d)
