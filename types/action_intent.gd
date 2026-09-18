extends RefCounted
## POST /matches/:id/actions bodies. Client sends intents only.

const Contract := preload("res://types/contract.gd")

static func select_hex(q: int, r: int) -> Dictionary:
	return {"type": Contract.ACT_SELECT_HEX, "hex": Contract.hex_dict(q, r)}


static func start() -> Dictionary:
	return {"type": Contract.ACT_START}


static func attack(q: int, r: int) -> Dictionary:
	return {"type": Contract.ACT_ATTACK, "hex": Contract.hex_dict(q, r)}


static func recon(q: int, r: int) -> Dictionary:
	return {"type": Contract.ACT_RECON, "hex": Contract.hex_dict(q, r)}


static func uav() -> Dictionary:
	return {"type": Contract.ACT_UAV}


static func end_turn(exposure_pct: float, hex: Variant = null) -> Dictionary:
	var body := {"type": Contract.ACT_END_TURN, "exposurePct": exposure_pct}
	if hex != null:
		# Mock reads `hex`. Live API locked field is `move` (Zod strips the extra key).
		body["hex"] = hex
		body["move"] = hex
	return body
