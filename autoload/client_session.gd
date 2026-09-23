extends Node
## Client-side seat binding. Never stores enemy secrets the snapshot did not give.

const Snapshot := preload("res://types/snapshot.gd")
const Contract := preload("res://types/contract.gd")
const MarksPayout := preload("res://types/marks_payout.gd")
const Shop := preload("res://types/shop.gd")

const HANDLE := "Specter7"
const RIVAL := "RivalSniper"
const PLAYER_STORE := "user://glassline_player.json"

var match_id: String = ""
var player_id: String = ""
var seat: String = ""
var dummy_player_id: String = ""
var join_token: String = ""
var dummy_token: String = ""
## Durable LIVE identity from POST /players. Survives reset_match.
var player_token: String = ""
var durable_player_id: String = ""
var last_snapshot: Dictionary = {}
## Display cache of server Marks. Never treat as a writable ledger.
var marks: int = 0
var last_payout: Dictionary = {}
var match_mode: String = Contract.MODE_PVP
var job_id: String = ""
var job_tier: int = 1
var client_job_id: String = ""
## Private lobby invite. Cleared on reset_match / cancel.
var lobby_id: String = ""
var lobby_code: String = ""
var lobby_seat: String = ""
## Quick Match queue. Cleared on reset_match / cancel / timeout.
var queueing: bool = false
var ghillie: bool = false
var bandana: bool = false
var poster: bool = false
## Cosmetic display cache from shop snapshot. Visual only — no combat.
var owned_cosmetics: Array = []
var equipped_cosmetic: String = ""
var equipped_decor: String = ""
## Visual gun rack. Starter Fieldbolt owned-by-default until Coder gun SKUs.
var owned_guns: Array = [Contract.GUN_FIELDBOLT]
var equipped_gun: String = Contract.GUN_FIELDBOLT
## Gun parts. Empty id = bare default. Feel is chrome, never a hit roll.
var owned_parts: Array = []
var equipped_optic: String = ""
var equipped_stock: String = ""
var equipped_barrel: String = ""
var feel_wobble_scale: float = Contract.WOBBLE_SCALE_BASE
var feel_shot_window_ms: int = Contract.SHOT_WINDOW_BASE_MS
var feel_wobble_from_server: bool = false
var feel_window_from_server: bool = false
## Display cache of server you.exposureFloor. Missing payload → start 50.
## Never written back. Cosmetics and operativeLevel do not compute it.
var exposure_floor: int = Contract.EXPOSURE_FLOOR_START
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
	job_id = ""
	job_tier = 1
	client_job_id = ""
	lobby_id = ""
	lobby_code = ""
	lobby_seat = ""
	queueing = false
	## player_token / durable_player_id / marks stay — LIVE wallet is per player.


func bind_marks(balance: int) -> void:
	## Display bind only. Callers must pass a server/mock snapshot value.
	marks = balance


func bind_exposure_floor_payload(bag: Dictionary) -> void:
	## Read the server percent when the payload carries it. Otherwise 50.
	## Does not write a percent and does not read operativeLevel.
	exposure_floor = Contract.exposure_floor_from_payload(bag)


func bind_player(bag: Dictionary) -> void:
	## Keep the POST /players token. Marks bind only if the payload has them.
	var token := str(bag.get("token", ""))
	if token != "":
		player_token = token
	var pid := str(bag.get("playerId", ""))
	if pid != "":
		durable_player_id = pid
	if bag.has("marks"):
		bind_marks(int(bag.get("marks")))
	bind_exposure_floor_payload(bag)


func persist_player() -> void:
	if player_token == "":
		return
	var file := FileAccess.open(PLAYER_STORE, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify({
		"playerId": durable_player_id,
		"token": player_token,
	}))
	file.close()


func load_player() -> void:
	if player_token != "":
		return
	if not FileAccess.file_exists(PLAYER_STORE):
		return
	var file := FileAccess.open(PLAYER_STORE, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is Dictionary:
		player_token = str(parsed.get("token", ""))
		durable_player_id = str(parsed.get("playerId", ""))


func player_bearer() -> String:
	return player_token


func apply_shop(bag: Dictionary) -> void:
	## Bind Marks + cosmetics from a shop / buy snapshot. Never marks -=.
	## LIVE GET /shop is catalog-only — do not wipe wallet/owned when omitted.
	var shop = Shop.from_any(bag)
	if shop.has_marks():
		bind_marks(shop.balance())
	if shop.owned_present:
		owned_cosmetics = shop.owned.duplicate()
	else:
		## LIVE buy 200 infers item.id only — merge so SKU 2 does not wipe SKU 1.
		for item_id in shop.owned:
			var sid := str(item_id)
			if sid != "" and not owned_cosmetics.has(sid):
				owned_cosmetics.append(sid)
	if shop.equipped_present:
		equipped_cosmetic = str(shop.equipped)
	if shop.equipped_decor_present:
		equipped_decor = str(shop.equipped_decor)
	if shop.owned_guns_present:
		owned_guns = shop.owned_guns.duplicate()
	else:
		for gid in shop.owned_guns:
			var gun_id := str(gid)
			if gun_id != "" and not owned_guns.has(gun_id):
				owned_guns.append(gun_id)
	if shop.equipped_gun_present:
		equipped_gun = str(shop.equipped_gun)
	if shop.owned_parts_present:
		owned_parts = shop.owned_parts.duplicate()
	else:
		for pid in shop.owned_parts:
			var part_id := str(pid)
			if part_id != "" and not owned_parts.has(part_id):
				owned_parts.append(part_id)
	if shop.equipped_optic_present:
		equipped_optic = str(shop.equipped_optic)
	if shop.equipped_stock_present:
		equipped_stock = str(shop.equipped_stock)
	if shop.equipped_barrel_present:
		equipped_barrel = str(shop.equipped_barrel)
	_sync_cosmetic_flags()
	_sync_gun_stub()
	_sync_part_stub()
	_bind_part_feel(bag)
	bind_exposure_floor_payload(bag)


func owns_cosmetic(item_id: String) -> bool:
	if Contract.is_gun_chrome(item_id):
		return owns_gun(item_id)
	if Contract.is_part_chrome(item_id):
		return owns_part(item_id)
	return owned_cosmetics.has(item_id)


func is_equipped(item_id: String) -> bool:
	if Contract.is_gun_chrome(item_id):
		var gid := Contract.canonical_gun_id(item_id)
		return gid != "" and Contract.canonical_gun_id(equipped_gun) == gid and owns_gun(gid)
	if Contract.is_part_chrome(item_id):
		var pid := Contract.canonical_part_id(item_id)
		return pid != "" and _equipped_part(Contract.part_slot(pid)) == pid and owns_part(pid)
	if Contract.is_decor_chrome(item_id):
		return equipped_decor == item_id
	return equipped_cosmetic == item_id


func bind_equip_local(item_id: String, slot: String = "") -> void:
	## Visual toggle after a successful mock persist / LIVE local-only equip.
	var use_gun := slot == Contract.GUN_SLOT or Contract.is_gun_chrome(item_id)
	var use_decor := slot == "decor" or Contract.is_decor_chrome(item_id)
	var use_part := Contract.is_part_slot(slot) or Contract.is_part_chrome(item_id)
	if item_id != "" and not owns_cosmetic(item_id):
		return
	if use_gun:
		equipped_gun = Contract.canonical_gun_id(item_id)
		_sync_gun_stub()
		return
	if use_part:
		var part_slot := slot if Contract.is_part_slot(slot) else Contract.part_slot(item_id)
		_set_equipped_part(part_slot, Contract.canonical_part_id(item_id))
		_sync_part_stub()
		_bind_part_feel({})
		return
	if use_decor:
		equipped_decor = item_id
	else:
		equipped_cosmetic = item_id
	_sync_cosmetic_flags()


func _sync_cosmetic_flags() -> void:
	ghillie = is_equipped(Contract.SHOP_STUB_ITEM_ID)
	bandana = is_equipped(Contract.SHOP_BANDANA_ITEM_ID)
	## Wall art binds equippedDecorId. Coexists with skin. Unequip decor hides it.
	poster = is_equipped(Contract.SHOP_POSTER_ITEM_ID)


func _sync_gun_stub() -> void:
	## Starter bolt is always owned. Harvest gun ids from the shop owned bag.
	for item_id in owned_cosmetics:
		var harvested := Contract.canonical_gun_id(str(item_id))
		if harvested != "" and not owned_guns.has(harvested):
			owned_guns.append(harvested)
	if not owned_guns.has(Contract.GUN_FIELDBOLT):
		owned_guns.append(Contract.GUN_FIELDBOLT)
	var gid := Contract.canonical_gun_id(equipped_gun)
	if gid != "" and not owns_gun(gid):
		## Unowned id falls back to starter. Empty unequip stays empty.
		equipped_gun = Contract.GUN_FIELDBOLT
	elif gid != "":
		equipped_gun = gid


func owns_gun(item_id: String) -> bool:
	var gid := Contract.canonical_gun_id(item_id)
	if gid == "":
		return false
	if gid == Contract.GUN_FIELDBOLT:
		return true
	return owned_guns.has(gid)


func equipped_gun_id() -> String:
	var gid := Contract.canonical_gun_id(equipped_gun)
	return gid if owns_gun(gid) else Contract.GUN_FIELDBOLT


func _sync_part_stub() -> void:
	for item_id in owned_cosmetics:
		var harvested := Contract.canonical_part_id(str(item_id))
		if harvested != "" and not owned_parts.has(harvested):
			owned_parts.append(harvested)
	equipped_optic = _kept_part(equipped_optic)
	equipped_stock = _kept_part(equipped_stock)
	equipped_barrel = _kept_part(equipped_barrel)


func _kept_part(item_id: String) -> String:
	var pid := Contract.canonical_part_id(item_id)
	if pid == "":
		return ""
	return pid if owns_part(pid) else ""


func owns_part(item_id: String) -> bool:
	var pid := Contract.canonical_part_id(item_id)
	if pid == "":
		return false
	return owned_parts.has(pid) or owned_cosmetics.has(pid)


func _equipped_part(slot: String) -> String:
	match slot:
		Contract.PART_SLOT_OPTIC:
			return Contract.canonical_part_id(equipped_optic)
		Contract.PART_SLOT_STOCK:
			return Contract.canonical_part_id(equipped_stock)
		Contract.PART_SLOT_BARREL:
			return Contract.canonical_part_id(equipped_barrel)
		_:
			return ""


func _set_equipped_part(slot: String, item_id: String) -> void:
	match slot:
		Contract.PART_SLOT_OPTIC:
			equipped_optic = item_id
		Contract.PART_SLOT_STOCK:
			equipped_stock = item_id
		Contract.PART_SLOT_BARREL:
			equipped_barrel = item_id


func equipped_optic_id() -> String:
	return _kept_part(equipped_optic)


func equipped_stock_id() -> String:
	return _kept_part(equipped_stock)


func equipped_barrel_id() -> String:
	return _kept_part(equipped_barrel)


func part_slot_state(item_id: String) -> String:
	var pid := Contract.canonical_part_id(item_id)
	if pid == "":
		return "empty"
	if _equipped_part(Contract.part_slot(pid)) == pid and owns_part(pid):
		return "equipped"
	if owns_part(pid):
		return "owned"
	return "empty"


func attack_wobble_scale() -> float:
	## Server wobbleScale when the snapshot named a number. Else Design juice.
	return feel_wobble_scale


func attack_shot_window_sec() -> float:
	return float(feel_shot_window_ms) / 1000.0


func _bind_part_feel(bag: Dictionary) -> void:
	var you: Dictionary = {}
	var named: Variant = bag.get("you", {})
	if named is Dictionary:
		you = named
	var root: Dictionary = bag
	var snap: Variant = bag.get("snapshot", null)
	if snap is Dictionary and not snap.is_empty():
		root = snap
		var snap_you: Variant = root.get("you", {})
		if you.is_empty() and snap_you is Dictionary:
			you = snap_you
	var wobble_present := false
	var wobble_value: Variant = null
	if you.has("wobbleScale") and Contract.feel_number(you.get("wobbleScale")):
		wobble_present = true
		wobble_value = you.get("wobbleScale")
	elif root.has("wobbleScale") and Contract.feel_number(root.get("wobbleScale")) and not you.has("wobbleScale"):
		wobble_present = true
		wobble_value = root.get("wobbleScale")
	var window_present := false
	var window_value: Variant = null
	if you.has("shotWindowMs") and Contract.feel_number(you.get("shotWindowMs")):
		window_present = true
		window_value = you.get("shotWindowMs")
	elif root.has("shotWindowMs") and Contract.feel_number(root.get("shotWindowMs")) and not you.has("shotWindowMs"):
		window_present = true
		window_value = root.get("shotWindowMs")
	feel_wobble_from_server = wobble_present
	feel_window_from_server = window_present
	feel_wobble_scale = Contract.resolve_wobble_scale(
		wobble_present, wobble_value, equipped_stock_id() != "", equipped_barrel_id() != ""
	)
	feel_shot_window_ms = Contract.resolve_shot_window_ms(
		window_present, window_value, equipped_optic_id() != ""
	)


func gun_slot_state(item_id: String) -> String:
	## Highlight uses the worn id. Hands / optic still fall back via equipped_gun_id().
	var gid := Contract.canonical_gun_id(item_id)
	if gid == "":
		return "empty"
	var worn := Contract.canonical_gun_id(equipped_gun)
	if worn == gid and owns_gun(gid):
		return "equipped"
	if owns_gun(gid):
		return "owned"
	return "locked"


func apply_snapshot(snap: Dictionary) -> void:
	## A2: full replace. Never merge invented terrain tags or lastAction.hit.
	last_snapshot = snap.duplicate(true)
	var kind := str(snap.get("kind", snap.get("mode", "")))
	if kind != "":
		match_mode = Contract.MODE_SP_JOB if kind in ["sp_job", "job"] else kind
	var job: Variant = snap.get("job", {})
	if job is Dictionary:
		if str(job.get("jobId", "")) != "":
			job_id = str(job.get("jobId"))
		if job.has("tier"):
			job_tier = int(job.get("tier", job_tier))
	var you: Variant = snap.get("you", {})
	if you is Dictionary:
		if str(you.get("seat", "")) != "":
			seat = str(you.get("seat", seat))
		## A2: wallet is snapshot you.marks only. Replace — never invent / keep a local grant.
		bind_marks(int(you.get("marks", 0)))
		if you.has("owned") or you.has("equipped") or you.has("equippedSkinId") \
				or you.has("equippedDecorId") or you.has("cosmetics") \
				or you.has("equippedGunId") or you.has("ownedGuns") or you.has("ownedGunIds") \
				or you.has("equippedOpticId") or you.has("equippedStockId") or you.has("equippedBarrelId") \
				or you.has("ownedParts") or you.has("ownedPartIds") \
				or you.has("wobbleScale") or you.has("shotWindowMs"):
			apply_shop({
				"you": you,
				"owned": you.get("owned", owned_cosmetics),
				"equipped": you.get("equippedSkinId", you.get("equipped", equipped_cosmetic)),
				"equippedSkinId": you.get("equippedSkinId", you.get("equipped", equipped_cosmetic)),
				"equippedDecorId": you.get("equippedDecorId", equipped_decor),
				"equippedGunId": you.get("equippedGunId", equipped_gun),
				"ownedGuns": you.get("ownedGuns", you.get("ownedGunIds", owned_guns)),
				"equippedOpticId": you.get("equippedOpticId", null) if you.has("equippedOpticId") else equipped_optic,
				"equippedStockId": you.get("equippedStockId", null) if you.has("equippedStockId") else equipped_stock,
				"equippedBarrelId": you.get("equippedBarrelId", null) if you.has("equippedBarrelId") else equipped_barrel,
				"ownedParts": you.get("ownedParts", you.get("ownedPartIds", owned_parts)),
				"wobbleScale": you.get("wobbleScale", null) if you.has("wobbleScale") else null,
				"shotWindowMs": you.get("shotWindowMs", null) if you.has("shotWindowMs") else null,
			})
	else:
		bind_marks(0)
	bind_exposure_floor_payload(snap)
	var payout = MarksPayout.from_any(snap)
	var why: String = MarksPayout.display_reason(snap, is_job())
	if payout.has_delta() or why != "":
		last_payout = {
			"marks": marks,
			"marksDelta": payout.marks_delta,
			"reason": why,
		}


func is_job() -> bool:
	return match_mode == Contract.MODE_SP_JOB


func is_practice() -> bool:
	return match_mode == Contract.MODE_PRACTICE


func typed_snapshot() -> Snapshot:
	return Snapshot.from_dict(last_snapshot) as Snapshot


func last_server_hit() -> Variant:
	## Null unless the snapshot lastAction carried hit. Never invent true.
	return typed_snapshot().last_hit()


func terrain_keys() -> PackedStringArray:
	var keys := PackedStringArray()
	for key in typed_snapshot().terrain_map().keys():
		keys.append(str(key))
	keys.sort()
	return keys


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
