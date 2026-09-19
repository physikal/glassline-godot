extends RefCounted
## Locked Glassline v0 constants. Live HTTPS must keep these shapes.

const BOARD_Q := 9
const BOARD_R := 7
const TURN_CAP := 16
const DEFAULT_EXPOSURE := 50
const RECON_BASE := 0.35
const RECON_MOVED_BONUS := 0.25
const TERRAIN_SALT := "glassline-v0"

const STATUS_WAITING := "waiting"
const STATUS_READY := "ready"
const STATUS_ACTIVE := "active"
const STATUS_ENDED := "ended"

const PHASE_ACTION := "await_action"
const PHASE_END_TURN := "await_end_turn"

const SEAT_A := "a"
const SEAT_B := "b"

const TYPE_OPEN := "open"
const TYPE_BRUSH := "brush"
const TYPE_HARD := "hard"

const ACT_SELECT_HEX := "select_hex"
const ACT_START := "start"
const ACT_ATTACK := "attack"
const ACT_RECON := "recon"
const ACT_UAV := "uav"
const ACT_DECOY := "decoy"
const ACT_END_TURN := "end_turn"
const ACT_FORFEIT := "forfeit"

const EVENT_SNAPSHOT := "snapshot"
const EVENT_YOUR_TURN := "your_turn"

const WIN_DRAW := "draw"

const ACT_REJECT := "reject"
const DEFAULT_API_BASE := "https://glassline-api.vercel.app"

const MODE_PVP := "pvp"
const MODE_SP_JOB := "sp_job"

const END_KILL := "kill"
const END_STANDOFF := "standoff"
const END_LOSS := "loss"
const END_JOB := "job"
const END_JOB_FAIL := "job_fail"
const END_FORFEIT := "forfeit"
const END_DISCONNECT := "disconnect"

## Soft A4 — treat these snapshot/result tokens as forfeit chrome.
const FORFEIT_REASONS := ["forfeit", "disconnect", "disconnected", "ragequit"]

## Ability slot chrome (M5). Intent type stays `uav`.
const ABILITY_LABEL := "UAV"
const ABILITY_SLOT := "ABILITY"
## Ability #2 — toy doll decoy. Intent `{ type: "decoy" }`, no hex arg.
const DECOY_LABEL := "DECOY"
const DECOY_SLOT := "TOY DOLL"
const DECOY_COPY := "Plant a toy doll on a neighbor hex. Rivals see a soft blip. Once a hunt."

## Mock hideout stub until Coder's ledger / GET wallet exists.
const MOCK_WALLET_STUB := 24

## Marks sinks — hideout cosmetics. LIVE catalog lock (Coder 2026-09-19).
## GET /shop item.id + POST /shop/buy itemId. Sink 1 ★50 · sink 2 ★100.
const SHOP_STUB_ITEM_ID := "skin_hideout_stub"
const SHOP_STUB_ITEM_NAME := "GHILLIE RECOLOR"
const SHOP_STUB_KIND := "skin"
const SHOP_STUB_PRICE := 50
const SHOP_BANDANA_ITEM_ID := "skin_bandana_stub"
const SHOP_BANDANA_ITEM_NAME := "BANDANA RECOLOR"
const SHOP_BANDANA_KIND := "skin"
const SHOP_BANDANA_PRICE := 100
const SHOP_ERR_INSUFFICIENT := "insufficient_marks"
const SHOP_ERR_INVALID_BODY := "invalid_buy_body"
const SHOP_ERR_ALREADY_OWNED := "already_owned"
const SHOP_ERR_UNKNOWN_ITEM := "unknown_item"
const SHOP_ERR_UNAVAILABLE := "shop_unavailable"
const SHOP_ERR_NOT_OWNED := "not_owned"
## Hideout row copy — owned chrome is visual only. Equip is a separate suit toggle.
const SHOP_OWNED_COPY := "OWNED  ·  visual only"
const SHOP_EQUIP_COPY := "Tap to wear  ·  visual only"
const SHOP_EQUIPPED_COPY := "Wearing this  ·  visual only"
const SHOP_INSUFFICIENT_COPY := "Not enough Marks."

## Locked GD earn table (2026-09-18). Mock display grants only; LIVE ledger is Coder.
const MARKS_PVP_WIN := 25
const MARKS_PVP_LOSS := 3
const MARKS_STANDOFF := 8
const MARKS_JOB_T1 := 10
const MARKS_JOB_T2 := 15
const MARKS_JOB_T3 := 20
const MARKS_JOB_FAIL := 0
const MARKS_FORFEIT_WIN := 12
const MARKS_FORFEIT_LOSS := 0
const FORFEIT_GRACE_SEC := 30

## Rematch — same two seats, new matchId + terrain salt. Marks already final.
const REMATCH_NONE := "none"
const REMATCH_PENDING := "pending"
const REMATCH_WAITING := "waiting"
const REMATCH_ACCEPTED_A := "accepted_a"
const REMATCH_ACCEPTED_B := "accepted_b"
const REMATCH_READY := "ready"
const REMATCH_DECLINED := "declined"
const REMATCH_EXPIRED := "expired"
const REMATCH_TIMEOUT_SEC := 30
const REMATCH_TIMEOUT_MS := 30000
const REMATCH_ERR_UNAVAILABLE := "rematch_unavailable"
const REMATCH_ERR_NOT_ENDED := "match_not_ended"
const REMATCH_ERR_NOT_PVP := "rematch_not_pvp"
const REMATCH_PLAY_COPY := "PLAY AGAIN"
const REMATCH_DECLINE_COPY := "DECLINE"
const REMATCH_SETTLED_COPY := "Marks already settled."
const REMATCH_HINT_COPY := "Play again for a fresh drop. Wallet stays put."
const REMATCH_WAIT_COPY := "Waiting on your rival…"
const REMATCH_TIMER_COPY := "Answer in %ds"

## Soft A4 gaps — abandon CTA + grace countdown. Duration stays 30s.
const ABANDON_COPY := "ABANDON"
const ABANDON_ERR_UNAVAILABLE := "abandon_unavailable"
## Disconnect grace — not a turn clock. Rival drop vs local poll HOLD.
const GRACE_RIVAL_COPY := "Waiting on rival…  %s"
const GRACE_HOLD_COPY := "Reconnect  %s"


static func format_grace_clock(sec: float) -> String:
	var n := maxi(0, ceili(sec))
	return "%d:%02d" % [int(n / 60), n % 60]


const JOB_NAME_T1 := "Rooftop Rookie"
const JOB_NAME_T2 := "Warehouse Watch"
const JOB_NAME_T3 := "Night Contract"
const JOB_TIERS := [1, 2, 3]


static func job_name(tier: int) -> String:
	match tier:
		2:
			return JOB_NAME_T2
		3:
			return JOB_NAME_T3
		_:
			return JOB_NAME_T1


static func job_tier_delta(tier: int) -> int:
	match tier:
		2:
			return MARKS_JOB_T2
		3:
			return MARKS_JOB_T3
		_:
			return MARKS_JOB_T1


static func job_row_label(tier: int) -> String:
	## Hideout ladder copy: tier + name. Payout is a separate ★ chip.
	return "T%d  %s" % [clampi(tier, 1, 3), job_name(tier)]


static func job_bot_hex(tier: int) -> Dictionary:
	## LIVE src/bot.ts SP_BOT_HEX. Secret until UAV / kill.
	match clampi(tier, 1, 3):
		2:
			return hex_dict(7, 5)
		3:
			return hex_dict(8, 5)
		_:
			return hex_dict(8, 6)

static func on_board(q: int, r: int) -> bool:
	return q >= 0 and q < BOARD_Q and r >= 0 and r < BOARD_R


static func hex_dict(q: int, r: int) -> Dictionary:
	return {"q": q, "r": r}


static func hex_key(hex: Variant) -> String:
	if hex == null or not (hex is Dictionary):
		return ""
	return "%d,%d" % [int(hex.get("q", -1)), int(hex.get("r", -1))]


static func same_hex(a: Variant, b: Variant) -> bool:
	if a == null or b == null:
		return false
	if not (a is Dictionary) or not (b is Dictionary):
		return false
	return int(a.get("q", -99)) == int(b.get("q", -98)) and int(a.get("r", -99)) == int(b.get("r", -98))


static func other_seat(seat: String) -> String:
	return SEAT_B if seat == SEAT_A else SEAT_A


static func shop_stub_item() -> Dictionary:
	return _shop_item(SHOP_STUB_ITEM_ID, SHOP_STUB_ITEM_NAME, SHOP_STUB_KIND, SHOP_STUB_PRICE)


static func shop_bandana_item() -> Dictionary:
	return _shop_item(SHOP_BANDANA_ITEM_ID, SHOP_BANDANA_ITEM_NAME, SHOP_BANDANA_KIND, SHOP_BANDANA_PRICE)


static func _shop_item(item_id: String, item_name: String, kind: String, price: int) -> Dictionary:
	return {
		"id": item_id,
		"itemId": item_id,
		"name": item_name,
		"kind": kind,
		"price": price,
		"priceMarks": price,
		"cosmetic": true,
		"combat": false,
	}


static func shop_catalog_items() -> Array:
	## Mock + LIVE-lag fallback. Prefer LIVE items when Coder lists bandana.
	return [shop_stub_item(), shop_bandana_item()]


static func shop_item_by_id(item_id: String) -> Dictionary:
	var resolved := _canonical_shop_id(item_id)
	for entry in shop_catalog_items():
		if str(entry.get("id", "")) == resolved:
			return entry
	return {}


static func shop_item_price(item_id: String) -> int:
	var item := shop_item_by_id(item_id)
	if item.is_empty():
		return 0
	return int(item.get("price", 0))


static func _canonical_shop_id(item_id: String) -> String:
	if item_id in ["ghillie_recolor", ""]:
		return SHOP_STUB_ITEM_ID
	if item_id == "bandana_recolor":
		return SHOP_BANDANA_ITEM_ID
	return item_id


static func shop_catalog_stub(marks: int = 0, owned: Array = [], equipped: String = "") -> Dictionary:
	var owned_ids: Array = owned.duplicate()
	var skin: Variant = equipped if equipped != "" else null
	return {
		"items": shop_catalog_items(),
		"you": {
			"marks": marks,
			"owned": owned_ids,
			"equipped": skin,
			"equippedSkinId": skin,
		},
		"owned": owned_ids,
		"equipped": skin,
		"equippedSkinId": skin,
		"marks": marks,
	}


static func merge_live_shop_catalog(live: Dictionary) -> Dictionary:
	## Prefer LIVE when it already lists bandana (+1 SKU). Else keep LIVE rows
	## and append the missing mock SKU so ARMORY still shows two rows.
	var out: Dictionary = live.duplicate(true)
	var items: Variant = out.get("items", [])
	if not (items is Array):
		items = []
	var ids: Array = []
	var merged: Array = []
	for entry in items:
		if not (entry is Dictionary):
			continue
		merged.append(entry)
		var iid := str(entry.get("id", entry.get("itemId", "")))
		if iid != "" and not ids.has(iid):
			ids.append(iid)
	if ids.has(SHOP_BANDANA_ITEM_ID) and merged.size() >= 2:
		return out
	for stub in shop_catalog_items():
		var sid := str(stub.get("id", ""))
		if sid != "" and not ids.has(sid):
			merged.append(stub)
	out["items"] = merged
	return out


static func new_client_job_id() -> String:
	## UUID v4 for POST /jobs clientJobId. New id on every START click.
	return new_client_buy_id()


static func new_client_buy_id() -> String:
	## UUID v4 for POST /shop/buy clientBuyId. New id on every Buy click.
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var bytes := PackedByteArray()
	bytes.resize(16)
	for i in 16:
		bytes[i] = rng.randi_range(0, 255)
	bytes[6] = (bytes[6] & 0x0f) | 0x40
	bytes[8] = (bytes[8] & 0x3f) | 0x80
	var hex := bytes.hex_encode()
	return "%s-%s-%s-%s-%s" % [
		hex.substr(0, 8),
		hex.substr(8, 4),
		hex.substr(12, 4),
		hex.substr(16, 4),
		hex.substr(20, 12),
	]
