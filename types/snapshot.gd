extends RefCounted
## Caller-scoped snapshot. Wrap a contract dictionary; do not invent fields.

const Contract := preload("res://types/contract.gd")
const MarksPayout := preload("res://types/marks_payout.gd")

var raw: Dictionary = {}


static func from_dict(d: Dictionary):
	var snap = new()
	snap.raw = d.duplicate(true)
	return snap


func to_dict() -> Dictionary:
	return raw.duplicate(true)


func match_id() -> String:
	return str(raw.get("matchId", ""))


func status() -> String:
	return str(raw.get("status", ""))


func turn_index() -> int:
	return int(raw.get("turnIndex", 0))


func turn_cap() -> int:
	return int(raw.get("turnCap", Contract.TURN_CAP))


func whose_turn() -> Variant:
	return raw.get("whoseTurn", null)


func phase() -> Variant:
	return raw.get("phase", null)


func uav_remaining() -> int:
	if raw.has("uavRemaining"):
		return int(raw.get("uavRemaining", 0))
	if raw.has("uavAvailable"):
		return 1 if bool(raw.get("uavAvailable", false)) else 0
	return 0


func decoy_available() -> bool:
	## Caller-scoped. Prefer you.decoyAvailable; never invent a charge.
	var you_state := you()
	if you_state.has("decoyAvailable"):
		return bool(you_state.get("decoyAvailable", false))
	if you_state.has("decoyRemaining"):
		return int(you_state.get("decoyRemaining", 0)) > 0
	if raw.has("decoyAvailable"):
		return bool(raw.get("decoyAvailable", false))
	return false


func smoke_available() -> bool:
	## Fail closed. Missing smokeAvailable (any casing) is not a charge.
	var found := _smoke_field("smokeAvailable")
	if not bool(found.get("present", false)):
		return false
	return _smoke_truthy(found.get("value"))


func smoke_active() -> bool:
	## Turns-remaining or bool. Missing / ended → no toast and no hex tint.
	if status() == Contract.STATUS_ENDED:
		return false
	var found := _smoke_field("smokeActive")
	if not bool(found.get("present", false)):
		return false
	return _smoke_truthy(found.get("value"))


func smoke_fields_present() -> bool:
	## Availability must be named. Active-only does not light the chip.
	return bool(_smoke_field("smokeAvailable").get("present", false))


func operative_level_present() -> bool:
	## Exact you.operativeLevel. Snake case, xp, and enemy.operativeLevel do not count.
	return bool(_you_exact("operativeLevel").get("present", false))


func operative_level() -> int:
	## Exact you.operativeLevel. Missing → -1. Never derived from xp or the gear floor.
	var found := _you_exact("operativeLevel")
	if not bool(found.get("present", false)):
		return -1
	return _operative_level_number(found.get("value"))


func xp_present() -> bool:
	## Exact you.xp. Does not unlock SMOKE and does not imply a level.
	var found := _you_exact("xp")
	if not bool(found.get("present", false)):
		return false
	var n: Variant = Contract._as_operative_int(found.get("value"))
	return n != null and int(n) >= 0


func xp_value() -> int:
	## Exact you.xp. Missing or junk → -1. The hideout bar uses the session bind.
	if not xp_present():
		return -1
	return int(Contract._as_operative_int(you().get("xp")))


func smoke_charge_exact_present() -> bool:
	## Exact you.smokeAvailable. The L5 gate does not accept an alias.
	return bool(_you_exact("smokeAvailable").get("present", false))


func smoke_charge_exact() -> bool:
	var found := _you_exact("smokeAvailable")
	if not bool(found.get("present", false)):
		return false
	return _smoke_truthy(found.get("value"))


func smoke_chrome() -> String:
	## Lit only when exact you.operativeLevel >= 5 and exact you.smokeAvailable is true.
	## Below L5 the chip stays locked even if a charge is also set.
	## A missing level does not light a charge. A missing charge at L5+ is not invented.
	var below := operative_level_present() and operative_level() < Contract.SMOKE_UNLOCK_LEVEL
	if below:
		return Contract.SMOKE_CHROME_LOCKED
	if not operative_level_present():
		if smoke_charge_exact():
			return Contract.SMOKE_CHROME_LOCKED
		if smoke_charge_exact_present():
			return Contract.SMOKE_CHROME_SPENT
		return Contract.SMOKE_CHROME_ABSENT
	if not smoke_charge_exact_present():
		return Contract.SMOKE_CHROME_ABSENT
	if smoke_charge_exact():
		return Contract.SMOKE_CHROME_AVAILABLE
	return Contract.SMOKE_CHROME_SPENT


func smoke_lock_toast() -> String:
	## One soft line. The contract has no lock-reason field.
	return Contract.SMOKE_LOCKED_TOAST


func decoy_charge_exact_present() -> bool:
	## Exact you.decoyAvailable. The L3 gate does not accept decoyRemaining or an alias.
	return bool(_you_exact("decoyAvailable").get("present", false))


func decoy_charge_exact() -> bool:
	var found := _you_exact("decoyAvailable")
	if not bool(found.get("present", false)):
		return false
	return _smoke_truthy(found.get("value"))


func decoy_chrome() -> String:
	## Lit only when exact you.operativeLevel >= 3 and exact you.decoyAvailable is true.
	## Below L3 the chip stays locked even if a charge is also set.
	## A missing level does not light a charge. A missing charge at L3+ is not invented.
	var below := operative_level_present() and operative_level() < Contract.DECOY_UNLOCK_LEVEL
	if below:
		return Contract.DECOY_CHROME_LOCKED
	if not operative_level_present():
		if decoy_charge_exact():
			return Contract.DECOY_CHROME_LOCKED
		if decoy_charge_exact_present():
			return Contract.DECOY_CHROME_SPENT
		return Contract.DECOY_CHROME_ABSENT
	if not decoy_charge_exact_present():
		return Contract.DECOY_CHROME_ABSENT
	if decoy_charge_exact():
		return Contract.DECOY_CHROME_AVAILABLE
	return Contract.DECOY_CHROME_SPENT


func decoy_lock_toast() -> String:
	## One soft line. LIVE reject is "reach operative L3"; the toast capitalizes it.
	return Contract.DECOY_LOCKED_TOAST


func enemy_smoke_active() -> bool:
	## enemy.smokeActive only. Never you.* and never a secret hex.
	## Missing / ended → false. Does not light your toast.
	if status() == Contract.STATUS_ENDED:
		return false
	var bag := enemy()
	for key in bag.keys():
		var norm := str(key).to_lower().replace("_", "")
		if norm == "smokeactive":
			return _smoke_truthy(bag[key])
	return false


func _smoke_field(canonical: String) -> Dictionary:
	## you.* first, then top-level. smokeAvailable / smoke_available / SmokeAvailable.
	return _you_or_top_field(canonical)


func _you_exact(key: String) -> Dictionary:
	## you.<key> only. No top-level, enemy, or casing alias.
	var bag := you()
	if bag.has(key):
		return {"present": true, "value": bag[key]}
	return {"present": false}


func _you_or_top_field(canonical: String) -> Dictionary:
	## you.* first, then top-level. Underscores and casing do not matter.
	## Smoke active/available puff fields still use this. The L5 gate does not.
	var want := canonical.to_lower().replace("_", "")
	var bags: Array = [you(), raw]
	for bag in bags:
		if not (bag is Dictionary):
			continue
		var dict: Dictionary = bag
		for key in dict.keys():
			var norm := str(key).to_lower().replace("_", "")
			if norm == want:
				return {"present": true, "value": dict[key]}
	return {"present": false}


func _operative_level_number(value: Variant) -> int:
	if value == null or value is bool:
		return -1
	if value is int or value is float:
		return int(value)
	if value is String:
		var text := str(value).strip_edges()
		if text.is_valid_int():
			return int(text)
		if text.is_valid_float():
			return int(float(text))
	return -1


func _smoke_truthy(value: Variant) -> bool:
	if value == null:
		return false
	if value is bool:
		return bool(value)
	if value is int or value is float:
		return float(value) > 0.0
	if value is String:
		var text := str(value).strip_edges().to_lower()
		if text in ["1", "true", "yes"]:
			return true
		if text.is_valid_float():
			return float(text) > 0.0
	return false


func you_decoy_hex() -> Variant:
	## Owner marker. Null unless the snapshot named you.decoyHex.
	if status() == Contract.STATUS_ENDED:
		return null
	var you_state := you()
	if you_state.has("decoyHex"):
		return you_state.get("decoyHex", null)
	return null


func enemy_decoy_soft_hex() -> Variant:
	## Soft blip only while live. Null on expiry / decoyCleared / match end.
	if status() == Contract.STATUS_ENDED:
		return null
	return enemy().get("decoySoftHex", null)


func kind() -> String:
	var value := str(raw.get("kind", ""))
	if value != "":
		return Contract.MODE_SP_JOB if value in ["sp_job", "job"] else value
	return mode()


func mode() -> String:
	var kind_value := str(raw.get("kind", ""))
	if kind_value in ["sp_job", "job"]:
		return Contract.MODE_SP_JOB
	if kind_value == Contract.MODE_PRACTICE:
		var named := str(raw.get("mode", raw.get("matchMode", "")))
		## kind/mode disagreement is not a practice hunt — do not fall through to PvP chrome.
		if named != "" and named != Contract.MODE_PRACTICE:
			return Contract.MODE_PVP
		return Contract.MODE_PRACTICE
	if kind_value == Contract.MODE_PVP:
		return Contract.MODE_PVP
	var value := str(raw.get("mode", raw.get("matchMode", "")))
	if value == "":
		var job_obj: Variant = raw.get("job", null)
		if job_obj is Dictionary and not job_obj.is_empty():
			return Contract.MODE_SP_JOB
		if bool(raw.get("spJob", false)) or str(raw.get("jobId", "")) != "":
			return Contract.MODE_SP_JOB
		return Contract.MODE_PVP
	if value in ["job", "sp", "spJob", "sp_job"]:
		return Contract.MODE_SP_JOB
	return value


func is_job() -> bool:
	return mode() == Contract.MODE_SP_JOB


func is_practice() -> bool:
	return mode() == Contract.MODE_PRACTICE


func enemy_is_bot() -> bool:
	## Chrome only. Absent means a human rival — never invent a bot.
	var bag := enemy()
	if bag.has("isBot"):
		return bool(bag.get("isBot", false))
	if bag.has("bot"):
		return bool(bag.get("bot", false))
	return false


func enemy_placed() -> bool:
	var bag := enemy()
	if bag.has("placed"):
		return bool(bag.get("placed", false))
	return false


func job() -> Dictionary:
	var value: Variant = raw.get("job", {})
	return value if value is Dictionary else {}


func job_tier() -> int:
	var bag := job()
	if bag.has("tier"):
		return int(bag.get("tier", 1))
	return int(raw.get("jobTier", raw.get("tier", 1)))


func payout():
	return MarksPayout.from_any(raw)


func marks_delta() -> Variant:
	var pay = MarksPayout.from_any(raw)
	return pay.marks_delta


func table_marks_delta() -> int:
	## Earn-table Δ from endReason + winner vs seat. Display only.
	## Practice is blind to that table — always Δ0.
	return MarksPayout.table_delta(raw, you_seat(), is_job(), is_practice())


func end_reason() -> String:
	var why: String = MarksPayout.display_reason(raw, is_job())
	if why != "":
		return why
	var pay = MarksPayout.from_any(raw)
	if str(pay.reason) != "":
		return str(pay.reason)
	return str(raw.get("endReason", raw.get("reason", "")))


func is_forfeit() -> bool:
	return MarksPayout.is_forfeit_payload(raw)


func you() -> Dictionary:
	var value: Variant = raw.get("you", {})
	return value if value is Dictionary else {}


func enemy() -> Dictionary:
	var value: Variant = raw.get("enemy", {})
	return value if value is Dictionary else {}


func terrain() -> Array:
	var value: Variant = raw.get("terrain", [])
	return value if value is Array else []


func last_action() -> Variant:
	return raw.get("lastAction", null)


func last_hit() -> Variant:
	## Server lastAction.hit only. Null if the snapshot did not say hit.
	var last: Variant = last_action()
	if last is Dictionary and last.has("hit"):
		return last.get("hit")
	return null


func last_high_ground_applied() -> Variant:
	## Server lastAction.highGroundApplied only. Null if omitted.
	var last: Variant = last_action()
	if last is Dictionary and last.has("highGroundApplied"):
		return last.get("highGroundApplied")
	return null


func last_cover_applied() -> Variant:
	## Server lastAction.coverApplied only. Null if omitted — never invent.
	var last: Variant = last_action()
	if last is Dictionary and last.has("coverApplied"):
		return last.get("coverApplied")
	return null


func last_hit_chance() -> Variant:
	## Server lastAction.hitChance only. Null if omitted — never invent.
	var last: Variant = last_action()
	if last is Dictionary and last.has("hitChance"):
		return last.get("hitChance")
	return null


func winner() -> Variant:
	return raw.get("winner", null)


func you_hex() -> Variant:
	return you().get("hex", null)


func you_placed() -> bool:
	var you_state := you()
	if you_state.has("placed"):
		return bool(you_state.get("placed", false))
	return you_state.get("hex", null) != null


func you_seat() -> String:
	return str(you().get("seat", ""))


func you_marks() -> int:
	return int(you().get("marks", 0))


func you_equipped_decor_id() -> String:
	## Caller-scoped poster id. Empty unless the snapshot named it. Never invent.
	var you_state := you()
	if you_state.has("equippedDecorId"):
		var value: Variant = you_state.get("equippedDecorId")
		if value == null:
			return ""
		if value is Dictionary:
			return str(value.get("itemId", value.get("id", "")))
		return str(value)
	var cosmetics: Variant = you_state.get("cosmetics", {})
	if cosmetics is Dictionary and cosmetics.has("equippedDecorId"):
		var worn: Variant = cosmetics.get("equippedDecorId")
		if worn == null:
			return ""
		return str(worn)
	return ""


func you_equipped_gun_id() -> String:
	## Caller-scoped gun id. Empty unless the snapshot named it. Never invent.
	var you_state := you()
	if you_state.has("equippedGunId"):
		var value: Variant = you_state.get("equippedGunId")
		if value == null:
			return ""
		if value is Dictionary:
			return Contract.canonical_gun_id(str(value.get("itemId", value.get("id", ""))))
		return Contract.canonical_gun_id(str(value))
	var cosmetics: Variant = you_state.get("cosmetics", {})
	if cosmetics is Dictionary and cosmetics.has("equippedGunId"):
		var worn: Variant = cosmetics.get("equippedGunId")
		if worn == null:
			return ""
		return Contract.canonical_gun_id(str(worn))
	return ""


func you_equipped_part_id(key: String) -> String:
	## Caller-scoped part id. Empty unless the snapshot named that key. Never invent.
	var you_state := you()
	if you_state.has(key):
		return Contract.canonical_part_id(_as_item_id(you_state.get(key)))
	var cosmetics: Variant = you_state.get("cosmetics", {})
	if cosmetics is Dictionary and cosmetics.has(key):
		return Contract.canonical_part_id(_as_item_id(cosmetics.get(key)))
	return ""


func you_equipped_optic_id() -> String:
	return you_equipped_part_id("equippedOpticId")


func you_equipped_stock_id() -> String:
	return you_equipped_part_id("equippedStockId")


func you_equipped_barrel_id() -> String:
	return you_equipped_part_id("equippedBarrelId")


func you_wobble_scale() -> Variant:
	## Server you.wobbleScale only. Null when omitted or not a number.
	return _you_feel_number("wobbleScale")


func you_shot_window_sec() -> Variant:
	## Server you.shotWindowSec only. Null when omitted or not a number.
	return _you_feel_number("shotWindowSec")


func _you_feel_number(key: String) -> Variant:
	var you_state := you()
	if not you_state.has(key):
		return null
	var value: Variant = you_state.get(key)
	if not Contract.feel_number(value):
		return null
	return value


func _as_item_id(value: Variant) -> String:
	if value == null:
		return ""
	if value is Dictionary:
		return str(value.get("itemId", value.get("id", "")))
	return str(value)


func you_equipped_skin_id() -> String:
	## Caller-scoped chrome id. Empty unless the snapshot named it. Never invent.
	var you_state := you()
	for key in ["equippedSkinId", "equipped"]:
		if you_state.has(key):
			var value: Variant = you_state.get(key)
			if value == null:
				return ""
			if value is Dictionary:
				return str(value.get("itemId", value.get("id", "")))
			return str(value)
	var cosmetics: Variant = you_state.get("cosmetics", {})
	if cosmetics is Dictionary and cosmetics.has("equipped"):
		var worn: Variant = cosmetics.get("equipped")
		if worn == null:
			return ""
		return str(worn)
	return ""


func you_exposure() -> float:
	return float(you().get("exposurePct", Contract.DEFAULT_EXPOSURE))


func you_exposure_floor_present() -> bool:
	return you().has("exposureFloor")


func you_exposure_floor() -> int:
	## Server you.exposureFloor only. Missing / 0 / unknown → 50. Never a client step.
	var you_state := you()
	if not you_state.has("exposureFloor"):
		return Contract.EXPOSURE_FLOOR_START
	return Contract.exposure_floor_or_start(you_state.get("exposureFloor"), true)


func you_moved_last_turn() -> bool:
	return bool(you().get("movedLastTurn", false))


func you_high_ground_active() -> bool:
	## Server you.highGroundActive only. Missing / FoW / OPEN / BRUSH → false.
	## Never invent from local hex or terrain_map().
	var you_state := you()
	if not you_state.has("highGroundActive"):
		return false
	return bool(you_state.get("highGroundActive", false))


func enemy_visible_hex() -> Variant:
	return enemy().get("visibleHex", null)


func enemy_soft_hot() -> int:
	return int(enemy().get("softHotTurnsLeft", 0))


func is_your_turn() -> bool:
	return status() == Contract.STATUS_ACTIVE and str(whose_turn()) == you_seat()


func terrain_map() -> Dictionary:
	## Revealed OPEN/BRUSH/HARD only. Missing / unknown is FoW — never invent.
	var mapped := {}
	for entry in terrain():
		if not (entry is Dictionary):
			continue
		if not entry.has("type"):
			continue
		var kind := str(entry.get("type", ""))
		if kind != Contract.TYPE_OPEN and kind != Contract.TYPE_BRUSH and kind != Contract.TYPE_HARD:
			continue
		mapped[Contract.hex_key(entry)] = kind
	return mapped


func rematch() -> Dictionary:
	var value: Variant = raw.get("rematch", {})
	return value if value is Dictionary else {}


func rematch_status() -> String:
	var st := str(rematch().get("status", Contract.REMATCH_NONE))
	if st == Contract.REMATCH_PENDING or st in [Contract.REMATCH_ACCEPTED_A, Contract.REMATCH_ACCEPTED_B]:
		return Contract.REMATCH_WAITING
	return st


func rematch_new_match_id() -> String:
	var bag := rematch()
	var mid := str(bag.get("newMatchId", bag.get("matchId", "")))
	if mid != "":
		return mid
	## LIVE POST ready body is the dict itself: { status: ready, matchId, joinToken }.
	if str(raw.get("status", "")) == Contract.REMATCH_READY and raw.has("joinToken"):
		return str(raw.get("matchId", ""))
	return ""


func rematch_you_accepted() -> bool:
	var bag := rematch()
	if bag.has("youAccepted"):
		return bool(bag.get("youAccepted", false))
	var st := str(bag.get("status", ""))
	var seat := you_seat()
	if st == Contract.REMATCH_ACCEPTED_A:
		return seat == Contract.SEAT_A
	if st == Contract.REMATCH_ACCEPTED_B:
		return seat == Contract.SEAT_B
	return rematch_status() == Contract.REMATCH_READY


func rematch_opponent_accepted() -> bool:
	var bag := rematch()
	if bag.has("opponentAccepted"):
		return bool(bag.get("opponentAccepted", false))
	var st := str(bag.get("status", ""))
	var seat := you_seat()
	if st == Contract.REMATCH_ACCEPTED_A:
		return seat == Contract.SEAT_B
	if st == Contract.REMATCH_ACCEPTED_B:
		return seat == Contract.SEAT_A
	return rematch_status() == Contract.REMATCH_READY


func rematch_expires_at() -> String:
	return str(rematch().get("expiresAt", rematch().get("deadline", "")))


func rematch_offered() -> bool:
	if is_job() or status() != Contract.STATUS_ENDED:
		return false
	return rematch_status() in [
		Contract.REMATCH_WAITING,
		Contract.REMATCH_PENDING,
		Contract.REMATCH_ACCEPTED_A,
		Contract.REMATCH_ACCEPTED_B,
	]


func rematch_ready() -> bool:
	return rematch_status() == Contract.REMATCH_READY and rematch_new_match_id() != ""


func rematch_leave() -> bool:
	return rematch_status() in [Contract.REMATCH_DECLINED, Contract.REMATCH_EXPIRED]


func _parse_iso_unix(value: Variant) -> float:
	if value == null:
		return 0.0
	if value is float or value is int:
		var n := float(value)
		if n > 1.0e12:
			return n / 1000.0
		return n
	var text := str(value)
	if text == "":
		return 0.0
	if text.is_valid_float():
		var n2 := float(text)
		if n2 > 1.0e12:
			return n2 / 1000.0
		return n2
	var iso := text
	if iso.ends_with("Z"):
		iso = iso.substr(0, iso.length() - 1)
	if "T" in iso:
		var parsed := Time.get_unix_time_from_datetime_string(iso)
		if parsed > 0:
			return float(parsed)
	return 0.0


func enemy_disconnected_at() -> Variant:
	var enemy_state := enemy()
	for key in ["disconnectedAt", "disconnected_at"]:
		if enemy_state.has(key) and enemy_state.get(key) != null and str(enemy_state.get(key, "")) != "":
			return enemy_state.get(key)
	for key in ["disconnectedAt", "disconnected_at"]:
		if raw.has(key) and raw.get(key) != null and str(raw.get(key, "")) != "":
			return raw.get(key)
	var presence: Variant = raw.get("presence", {})
	if presence is Dictionary:
		var enemy_p: Variant = presence.get("enemy", presence)
		if enemy_p is Dictionary:
			for key in ["disconnectedAt", "disconnected_at"]:
				if enemy_p.has(key) and enemy_p.get(key) != null:
					return enemy_p.get(key)
	return null


func grace_ends_at() -> Variant:
	for key in ["graceEndsAt", "grace_ends_at"]:
		if raw.has(key) and raw.get(key) != null and str(raw.get(key, "")) != "":
			return raw.get(key)
	var grace: Variant = raw.get("grace", {})
	if grace is Dictionary:
		for key in ["endsAt", "expiresAt", "graceEndsAt"]:
			if grace.has(key) and grace.get(key) != null:
				return grace.get(key)
	if enemy_disconnected_at() == null:
		return null
	var unix := _parse_iso_unix(enemy_disconnected_at())
	if unix <= 0.0:
		return null
	return unix + float(Contract.FORFEIT_GRACE_SEC)


func grace_remaining_sec() -> float:
	if status() != Contract.STATUS_ACTIVE:
		return 0.0
	if raw.has("graceRemainingSec"):
		return maxf(0.0, float(raw.get("graceRemainingSec", 0)))
	var grace: Variant = raw.get("grace", {})
	if grace is Dictionary and grace.has("remainingSec"):
		return maxf(0.0, float(grace.get("remainingSec", 0)))
	if grace_ends_at() == null:
		return 0.0
	var unix := _parse_iso_unix(grace_ends_at())
	if unix <= 0.0:
		return 0.0
	return maxf(0.0, unix - Time.get_unix_time_from_system())


func in_grace() -> bool:
	if status() != Contract.STATUS_ACTIVE:
		return false
	if enemy_disconnected_at() != null:
		return true
	if raw.has("graceEndsAt") or raw.has("graceRemainingSec"):
		return true
	var grace: Variant = raw.get("grace", {})
	return grace is Dictionary and not grace.is_empty()
