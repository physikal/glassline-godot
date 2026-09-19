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
var ghillie: bool = false
var bandana: bool = false
## Cosmetic display cache from shop snapshot. Visual only — no combat.
var owned_cosmetics: Array = []
var equipped_cosmetic: String = ""
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
	## player_token / durable_player_id / marks stay — LIVE wallet is per player.


func bind_marks(balance: int) -> void:
	## Display bind only. Callers must pass a server/mock snapshot value.
	marks = balance


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
	_sync_cosmetic_flags()


func owns_cosmetic(item_id: String) -> bool:
	return owned_cosmetics.has(item_id)


func is_equipped(item_id: String) -> bool:
	return equipped_cosmetic == item_id


func bind_equip_local(item_id: String) -> void:
	## Visual toggle after a successful mock persist / LIVE local-only equip.
	if item_id != "" and not owns_cosmetic(item_id):
		return
	equipped_cosmetic = item_id
	_sync_cosmetic_flags()


func _sync_cosmetic_flags() -> void:
	ghillie = is_equipped(Contract.SHOP_STUB_ITEM_ID)
	bandana = is_equipped(Contract.SHOP_BANDANA_ITEM_ID)


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
		if you.has("owned") or you.has("equipped") or you.has("equippedSkinId") or you.has("cosmetics"):
			apply_shop({
				"you": you,
				"owned": you.get("owned", owned_cosmetics),
				"equipped": you.get("equippedSkinId", you.get("equipped", equipped_cosmetic)),
				"equippedSkinId": you.get("equippedSkinId", you.get("equipped", equipped_cosmetic)),
			})
	else:
		bind_marks(0)
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
