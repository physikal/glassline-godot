extends RefCounted
## Hideout shop bag. Catalog + wallet + owned/equipped cosmetics.
## Client displays only — never `marks -=` on a buy.

const Contract := preload("res://types/contract.gd")

var raw: Dictionary = {}
var marks: Variant = null
var items: Array = []
var owned: Array = []
var equipped: String = ""
var equipped_decor: String = ""
var equipped_gun: String = ""
var owned_guns: Array = []
var equipped_optic: String = ""
var equipped_stock: String = ""
var equipped_barrel: String = ""
var owned_parts: Array = []
var wobble_scale: Variant = null
var shot_window_sec: Variant = null
var error: String = ""
var ok: bool = true
var owned_present: bool = false
var equipped_present: bool = false
var equipped_decor_present: bool = false
var equipped_gun_present: bool = false
var owned_guns_present: bool = false
var equipped_optic_present: bool = false
var equipped_stock_present: bool = false
var equipped_barrel_present: bool = false
var owned_parts_present: bool = false
var wobble_present: bool = false
var window_present: bool = false
var purchase_id: String = ""


static func from_any(payload: Variant):
	var parsed = new()
	if payload == null or not (payload is Dictionary):
		return parsed
	var bag: Dictionary = payload
	parsed.raw = bag.duplicate(true)
	parsed.ok = bool(bag.get("ok", not _has_error(bag)))
	parsed.error = _read_error(bag)
	if parsed.error != "":
		parsed.ok = false
	var root: Dictionary = bag
	var snap: Variant = bag.get("snapshot", null)
	if snap is Dictionary and not snap.is_empty():
		root = snap
	parsed.items = _read_items(bag, root)
	parsed.owned = _read_owned(bag, root)
	parsed.equipped = _read_equipped(bag, root)
	parsed.equipped_decor = _read_equipped_decor(bag, root)
	parsed.equipped_gun = _read_equipped_gun(bag, root)
	parsed.owned_guns = _read_owned_guns(bag, root)
	parsed.equipped_optic = _read_equipped_part(bag, root, "equippedOpticId")
	parsed.equipped_stock = _read_equipped_part(bag, root, "equippedStockId")
	parsed.equipped_barrel = _read_equipped_part(bag, root, "equippedBarrelId")
	parsed.owned_parts = _read_owned_parts(bag, root)
	parsed.marks = _read_marks(bag, root)
	var wobble := _read_feel(bag, root, "wobbleScale")
	var window := _read_feel(bag, root, "shotWindowSec")
	parsed.wobble_present = bool(wobble.get("present", false))
	parsed.window_present = bool(window.get("present", false))
	parsed.wobble_scale = wobble.get("value", null)
	parsed.shot_window_sec = window.get("value", null)
	parsed.owned_present = _has_owned(bag, root)
	parsed.equipped_present = _has_equipped(bag, root)
	parsed.equipped_decor_present = _has_equipped_decor(bag, root)
	parsed.equipped_gun_present = _has_equipped_gun(bag, root)
	parsed.owned_guns_present = _has_owned_guns(bag, root)
	parsed.equipped_optic_present = _has_part_field(bag, root, "equippedOpticId")
	parsed.equipped_stock_present = _has_part_field(bag, root, "equippedStockId")
	parsed.equipped_barrel_present = _has_part_field(bag, root, "equippedBarrelId")
	parsed.owned_parts_present = _has_owned_parts(bag, root)
	parsed.purchase_id = str(bag.get("purchaseId", root.get("purchaseId", "")))
	## LIVE buy 200: { ok, you.marks, purchaseId, item } — infer owned/equip.
	## Do not mark owned_present — apply_shop merges so a second SKU does not wipe the first.
	var bought: Variant = bag.get("item", root.get("item", null))
	if bought is Dictionary:
		var bought_item: Dictionary = _normalize_item(bought)
		if parsed.items.is_empty():
			parsed.items = [bought_item]
		var bought_id := _as_id(bought_item)
		if parsed.ok and bought_id != "":
			if not parsed.owned_present:
				parsed.owned = [bought_id]
			## Last buy auto-equips that slot only. Skin / decor / gun coexist.
			if Contract.is_decor_chrome(bought_id):
				if not parsed.equipped_decor_present:
					parsed.equipped_decor = bought_id
					parsed.equipped_decor_present = true
			elif Contract.is_gun_chrome(bought_id):
				var gid := Contract.canonical_gun_id(bought_id)
				if gid != "" and not parsed.owned_guns.has(gid):
					parsed.owned_guns.append(gid)
				if not parsed.equipped_gun_present and gid != "":
					parsed.equipped_gun = gid
					parsed.equipped_gun_present = true
			elif Contract.is_part_chrome(bought_id):
				var pid := Contract.canonical_part_id(bought_id)
				if pid != "" and not parsed.owned_parts.has(pid):
					parsed.owned_parts.append(pid)
				if pid != "" and not _part_slot_present(parsed, pid):
					_infer_part_equip(parsed, pid)
			elif not parsed.equipped_present:
				parsed.equipped = bought_id
				parsed.equipped_present = true
	for owned_id in parsed.owned:
		var harvested := Contract.canonical_gun_id(str(owned_id))
		if harvested != "" and not parsed.owned_guns.has(harvested):
			parsed.owned_guns.append(harvested)
		var part_id := Contract.canonical_part_id(str(owned_id))
		if part_id != "" and not parsed.owned_parts.has(part_id):
			parsed.owned_parts.append(part_id)
	return parsed


static func _has_error(bag: Dictionary) -> bool:
	return str(bag.get("error", "")) != "" \
		or str(bag.get("reason", "")) == Contract.SHOP_ERR_INSUFFICIENT \
		or str(bag.get("code", "")) == Contract.SHOP_ERR_INSUFFICIENT


static func _read_error(bag: Dictionary) -> String:
	var result: Variant = bag.get("result", {})
	if result is Dictionary and str(result.get("type", "")) == Contract.ACT_REJECT:
		return str(result.get("reason", "rejected"))
	var err := str(bag.get("error", ""))
	if err != "":
		return err
	var reason := str(bag.get("reason", ""))
	var code := str(bag.get("code", ""))
	for token in [err, reason, code]:
		if token in [
			Contract.SHOP_ERR_INSUFFICIENT,
			Contract.SHOP_ERR_ALREADY_OWNED,
			Contract.SHOP_ERR_UNKNOWN_ITEM,
			Contract.SHOP_ERR_UNAVAILABLE,
			Contract.SHOP_ERR_INVALID_BODY,
			Contract.SHOP_ERR_NOT_OWNED,
		]:
			return token
	return ""


static func _read_items(bag: Dictionary, root: Dictionary) -> Array:
	for source in [bag, root]:
		var list: Variant = source.get("items", source.get("catalog", []))
		if list is Array and not list.is_empty():
			return _normalize_items(list)
		var shop: Variant = source.get("shop", {})
		if shop is Dictionary:
			var nested: Variant = shop.get("items", [])
			if nested is Array and not nested.is_empty():
				return _normalize_items(nested)
	return Contract.shop_catalog_items()


static func _read_owned(bag: Dictionary, root: Dictionary) -> Array:
	var found: Array = []
	for source in [bag, root]:
		var you: Variant = source.get("you", {})
		if you is Dictionary:
			found = _as_id_list(you.get("owned", you.get("cosmetics", [])))
			if not found.is_empty():
				return found
			var cosmetics: Variant = you.get("cosmetics", {})
			if cosmetics is Dictionary:
				found = _as_id_list(cosmetics.get("owned", []))
				if not found.is_empty():
					return found
		found = _as_id_list(source.get("owned", []))
		if not found.is_empty():
			return found
		var shop: Variant = source.get("shop", {})
		if shop is Dictionary:
			found = _as_id_list(shop.get("owned", []))
			if not found.is_empty():
				return found
	return []


static func _read_equipped(bag: Dictionary, root: Dictionary) -> String:
	## Prefer Coder `you.equippedSkinId`. Fall back to last-buy `equipped`.
	for source in [bag, root]:
		var you: Variant = source.get("you", {})
		if you is Dictionary:
			if you.has("equippedSkinId"):
				return _as_id(you.get("equippedSkinId", null))
			var eq := _as_id(you.get("equipped", null))
			if eq != "":
				return eq
			var cosmetics: Variant = you.get("cosmetics", {})
			if cosmetics is Dictionary:
				if cosmetics.has("equippedSkinId"):
					return _as_id(cosmetics.get("equippedSkinId", null))
				eq = _as_id(cosmetics.get("equipped", null))
				if eq != "":
					return eq
		if source.has("equippedSkinId"):
			return _as_id(source.get("equippedSkinId", null))
		var eq_top := _as_id(source.get("equipped", null))
		if eq_top != "":
			return eq_top
		var shop: Variant = source.get("shop", {})
		if shop is Dictionary:
			if shop.has("equippedSkinId"):
				return _as_id(shop.get("equippedSkinId", null))
			var eq_shop := _as_id(shop.get("equipped", null))
			if eq_shop != "":
				return eq_shop
	return ""


static func _read_equipped_decor(bag: Dictionary, root: Dictionary) -> String:
	## Prefer Coder `you.equippedDecorId`. Never fall back to equippedSkinId.
	for source in [bag, root]:
		var you: Variant = source.get("you", {})
		if you is Dictionary:
			if you.has("equippedDecorId"):
				return _as_id(you.get("equippedDecorId", null))
			var cosmetics: Variant = you.get("cosmetics", {})
			if cosmetics is Dictionary and cosmetics.has("equippedDecorId"):
				return _as_id(cosmetics.get("equippedDecorId", null))
		if source.has("equippedDecorId"):
			return _as_id(source.get("equippedDecorId", null))
		var shop: Variant = source.get("shop", {})
		if shop is Dictionary and shop.has("equippedDecorId"):
			return _as_id(shop.get("equippedDecorId", null))
	return ""


static func _read_marks(bag: Dictionary, root: Dictionary) -> Variant:
	for source in [bag, root]:
		var you: Variant = source.get("you", {})
		if you is Dictionary and you.has("marks"):
			return int(you.get("marks"))
		if source.has("marks") and not (source.get("marks") is Dictionary):
			return int(source.get("marks"))
		var wallet: Variant = source.get("wallet", {})
		if wallet is Dictionary and wallet.has("marks"):
			return int(wallet.get("marks"))
	return null


static func _as_id_list(value: Variant) -> Array:
	var ids: Array = []
	if value is Array:
		for entry in value:
			var item_id := _as_id(entry)
			if item_id != "" and not ids.has(item_id):
				ids.append(item_id)
	elif value is Dictionary:
		var item_id := _as_id(value)
		if item_id != "":
			ids.append(item_id)
	elif value != null:
		var item_id := _as_id(value)
		if item_id != "":
			ids.append(item_id)
	return ids


static func _as_id(value: Variant) -> String:
	if value == null:
		return ""
	if value is Dictionary:
		return str(value.get("itemId", value.get("id", "")))
	return str(value)


static func _normalize_item(entry: Dictionary) -> Dictionary:
	var out: Dictionary = entry.duplicate(true)
	var item_id := _as_id(entry)
	if item_id != "":
		out["id"] = item_id
		out["itemId"] = item_id
	if out.has("price") and not out.has("priceMarks"):
		out["priceMarks"] = int(out.get("price"))
	return out


static func _normalize_items(list: Array) -> Array:
	var out: Array = []
	for entry in list:
		if entry is Dictionary:
			out.append(_normalize_item(entry))
	return out


static func _has_owned(bag: Dictionary, root: Dictionary) -> bool:
	for source in [bag, root]:
		var you: Variant = source.get("you", {})
		if you is Dictionary and (you.has("owned") or you.has("cosmetics")):
			return true
		if source.has("owned"):
			return true
	return false


static func _has_equipped(bag: Dictionary, root: Dictionary) -> bool:
	for source in [bag, root]:
		var you: Variant = source.get("you", {})
		if you is Dictionary and (you.has("equippedSkinId") or you.has("equipped") or you.has("cosmetics")):
			return true
		if source.has("equippedSkinId") or source.has("equipped"):
			return true
	return false


static func _has_equipped_decor(bag: Dictionary, root: Dictionary) -> bool:
	for source in [bag, root]:
		var you: Variant = source.get("you", {})
		if you is Dictionary and you.has("equippedDecorId"):
			return true
		if source.has("equippedDecorId"):
			return true
		var shop: Variant = source.get("shop", {})
		if shop is Dictionary and shop.has("equippedDecorId"):
			return true
	return false


static func _read_equipped_gun(bag: Dictionary, root: Dictionary) -> String:
	## Optional Coder `you.equippedGunId`. Absent → client stub (starter Fieldbolt).
	for source in [bag, root]:
		var you: Variant = source.get("you", {})
		if you is Dictionary and you.has("equippedGunId"):
			return Contract.canonical_gun_id(_as_id(you.get("equippedGunId", null)))
		var cosmetics: Variant = {}
		if you is Dictionary:
			cosmetics = you.get("cosmetics", {})
		if cosmetics is Dictionary and cosmetics.has("equippedGunId"):
			return Contract.canonical_gun_id(_as_id(cosmetics.get("equippedGunId", null)))
		if source.has("equippedGunId"):
			return Contract.canonical_gun_id(_as_id(source.get("equippedGunId", null)))
		var shop: Variant = source.get("shop", {})
		if shop is Dictionary and shop.has("equippedGunId"):
			return Contract.canonical_gun_id(_as_id(shop.get("equippedGunId", null)))
	return ""


static func _read_owned_guns(bag: Dictionary, root: Dictionary) -> Array:
	## Optional `ownedGuns` / `ownedGunIds`. Never read skin/decor `owned`.
	var found: Array = []
	for source in [bag, root]:
		var you: Variant = source.get("you", {})
		if you is Dictionary:
			found = _as_gun_id_list(you.get("ownedGuns", you.get("ownedGunIds", [])))
			if not found.is_empty():
				return found
			var cosmetics: Variant = you.get("cosmetics", {})
			if cosmetics is Dictionary:
				found = _as_gun_id_list(cosmetics.get("ownedGuns", cosmetics.get("ownedGunIds", [])))
				if not found.is_empty():
					return found
		found = _as_gun_id_list(source.get("ownedGuns", source.get("ownedGunIds", [])))
		if not found.is_empty():
			return found
		var shop: Variant = source.get("shop", {})
		if shop is Dictionary:
			found = _as_gun_id_list(shop.get("ownedGuns", shop.get("ownedGunIds", [])))
			if not found.is_empty():
				return found
	return []


static func _as_gun_id_list(value: Variant) -> Array:
	var ids: Array = []
	for item_id in _as_id_list(value):
		var gid := Contract.canonical_gun_id(str(item_id))
		if gid != "" and not ids.has(gid):
			ids.append(gid)
	return ids


static func _has_equipped_gun(bag: Dictionary, root: Dictionary) -> bool:
	for source in [bag, root]:
		var you: Variant = source.get("you", {})
		if you is Dictionary and you.has("equippedGunId"):
			return true
		if source.has("equippedGunId"):
			return true
		var shop: Variant = source.get("shop", {})
		if shop is Dictionary and shop.has("equippedGunId"):
			return true
	return false


static func _part_slot_present(parsed, part_id: String) -> bool:
	match Contract.part_slot(part_id):
		Contract.PART_SLOT_OPTIC:
			return parsed.equipped_optic_present
		Contract.PART_SLOT_STOCK:
			return parsed.equipped_stock_present
		Contract.PART_SLOT_BARREL:
			return parsed.equipped_barrel_present
		_:
			return true


static func _infer_part_equip(parsed, part_id: String) -> void:
	match Contract.part_slot(part_id):
		Contract.PART_SLOT_OPTIC:
			parsed.equipped_optic = part_id
			parsed.equipped_optic_present = true
		Contract.PART_SLOT_STOCK:
			parsed.equipped_stock = part_id
			parsed.equipped_stock_present = true
		Contract.PART_SLOT_BARREL:
			parsed.equipped_barrel = part_id
			parsed.equipped_barrel_present = true


static func _read_equipped_part(bag: Dictionary, root: Dictionary, key: String) -> String:
	## Optional Coder you.equippedOpticId / Stock / Barrel. Absent → empty, not invented.
	for source in [bag, root]:
		var you: Variant = source.get("you", {})
		if you is Dictionary and you.has(key):
			return Contract.canonical_part_id(_as_id(you.get(key, null)))
		var cosmetics: Variant = {}
		if you is Dictionary:
			cosmetics = you.get("cosmetics", {})
		if cosmetics is Dictionary and cosmetics.has(key):
			return Contract.canonical_part_id(_as_id(cosmetics.get(key, null)))
		if source.has(key):
			return Contract.canonical_part_id(_as_id(source.get(key, null)))
		var shop: Variant = source.get("shop", {})
		if shop is Dictionary and shop.has(key):
			return Contract.canonical_part_id(_as_id(shop.get(key, null)))
	return ""


static func _read_owned_parts(bag: Dictionary, root: Dictionary) -> Array:
	var found: Array = []
	for source in [bag, root]:
		var you: Variant = source.get("you", {})
		if you is Dictionary:
			found = _as_part_id_list(you.get("ownedParts", you.get("ownedPartIds", [])))
			if not found.is_empty():
				return found
			var cosmetics: Variant = you.get("cosmetics", {})
			if cosmetics is Dictionary:
				found = _as_part_id_list(cosmetics.get("ownedParts", cosmetics.get("ownedPartIds", [])))
				if not found.is_empty():
					return found
		found = _as_part_id_list(source.get("ownedParts", source.get("ownedPartIds", [])))
		if not found.is_empty():
			return found
		var shop: Variant = source.get("shop", {})
		if shop is Dictionary:
			found = _as_part_id_list(shop.get("ownedParts", shop.get("ownedPartIds", [])))
			if not found.is_empty():
				return found
	return []


static func _as_part_id_list(value: Variant) -> Array:
	var ids: Array = []
	for item_id in _as_id_list(value):
		var pid := Contract.canonical_part_id(str(item_id))
		if pid != "" and not ids.has(pid):
			ids.append(pid)
	return ids


static func _has_part_field(bag: Dictionary, root: Dictionary, key: String) -> bool:
	for source in [bag, root]:
		var you: Variant = source.get("you", {})
		if you is Dictionary and you.has(key):
			return true
		if source.has(key):
			return true
		var shop: Variant = source.get("shop", {})
		if shop is Dictionary and shop.has(key):
			return true
	return false


static func _has_owned_parts(bag: Dictionary, root: Dictionary) -> bool:
	for source in [bag, root]:
		var you: Variant = source.get("you", {})
		if you is Dictionary and (you.has("ownedParts") or you.has("ownedPartIds")):
			return true
		if source.has("ownedParts") or source.has("ownedPartIds"):
			return true
		var shop: Variant = source.get("shop", {})
		if shop is Dictionary and (shop.has("ownedParts") or shop.has("ownedPartIds")):
			return true
	return false


static func _read_feel(bag: Dictionary, root: Dictionary, key: String) -> Dictionary:
	## wobbleScale / shotWindowSec. Missing key is not a number. Null stays missing.
	for source in [bag, root]:
		var you: Variant = source.get("you", {})
		if you is Dictionary and you.has(key):
			var named: Variant = you.get(key)
			if Contract.feel_number(named):
				return {"present": true, "value": named}
			return {"present": false, "value": null}
		if source.has(key):
			var top: Variant = source.get(key)
			if Contract.feel_number(top):
				return {"present": true, "value": top}
			return {"present": false, "value": null}
	return {"present": false, "value": null}


static func _has_owned_guns(bag: Dictionary, root: Dictionary) -> bool:
	for source in [bag, root]:
		var you: Variant = source.get("you", {})
		if you is Dictionary and (you.has("ownedGuns") or you.has("ownedGunIds")):
			return true
		if source.has("ownedGuns") or source.has("ownedGunIds"):
			return true
		var shop: Variant = source.get("shop", {})
		if shop is Dictionary and (shop.has("ownedGuns") or shop.has("ownedGunIds")):
			return true
	return false


func has_marks() -> bool:
	return marks != null


func balance() -> int:
	return int(marks) if has_marks() else 0


func stub_item() -> Dictionary:
	return item_for(Contract.SHOP_STUB_ITEM_ID)


func item_for(item_id: String) -> Dictionary:
	var want := Contract._canonical_shop_id(item_id)
	for entry in items:
		if entry is Dictionary and _as_id(entry) == want:
			return entry
	var stub: Dictionary = Contract.shop_item_by_id(want)
	if not stub.is_empty():
		return stub
	if not items.is_empty() and items[0] is Dictionary:
		return items[0]
	return Contract.shop_stub_item()


func price() -> int:
	return price_of(Contract.SHOP_STUB_ITEM_ID)


func price_of(item_id: String) -> int:
	var item := item_for(item_id)
	if item.has("priceMarks"):
		return int(item.get("priceMarks"))
	if item.has("price"):
		return int(item.get("price"))
	return Contract.shop_item_price(item_id)


func item_id() -> String:
	var found := _as_id(stub_item())
	return found if found != "" else Contract.SHOP_STUB_ITEM_ID


func item_name() -> String:
	return name_of(Contract.SHOP_STUB_ITEM_ID)


func name_of(item_id: String) -> String:
	var item := item_for(item_id)
	var fallback := Contract.SHOP_STUB_ITEM_NAME
	var want := Contract._canonical_shop_id(item_id)
	if want == Contract.SHOP_BANDANA_ITEM_ID:
		fallback = Contract.SHOP_BANDANA_ITEM_NAME
	elif want == Contract.SHOP_POSTER_ITEM_ID:
		fallback = Contract.SHOP_POSTER_ITEM_NAME
	elif Contract.is_gun_chrome(want):
		fallback = Contract.gun_family_name(want)
	elif Contract.is_part_chrome(want):
		fallback = Contract.part_name(want)
	return str(item.get("name", fallback))


func has_item(item_id: String) -> bool:
	var want := Contract._canonical_shop_id(item_id)
	for entry in items:
		if entry is Dictionary and _as_id(entry) == want:
			return true
	return false


func owns_stub() -> bool:
	return owns(item_id()) or owns(Contract.SHOP_STUB_ITEM_ID)


func owns(item_id: String) -> bool:
	var want := Contract._canonical_shop_id(item_id)
	return owned.has(want) or owned.has(item_id)


func is_equipped() -> bool:
	var id := item_id()
	return equipped == id or equipped == Contract.SHOP_STUB_ITEM_ID


func is_insufficient() -> bool:
	return error == Contract.SHOP_ERR_INSUFFICIENT


func is_not_owned() -> bool:
	return error == Contract.SHOP_ERR_NOT_OWNED


func is_unavailable() -> bool:
	return error == Contract.SHOP_ERR_UNAVAILABLE or error == "http_404" or error.begins_with("http_404")


func can_afford() -> bool:
	return balance() >= price()


func catalog_pending(item_id: String) -> bool:
	## Gap-filled part row. Visible, but buy must not POST until the catalog lists it.
	var want := Contract._canonical_shop_id(item_id)
	for entry in items:
		if entry is Dictionary and _as_id(entry) == want:
			return bool(entry.get("pending", false))
	return false


static func row_action_text(owned: bool, equipped: bool = false) -> String:
	## Unowned → BUY. Owned → EQUIP / EQUIPPED (clear vs OWNED · visual only).
	if not owned:
		return "BUY"
	return "EQUIPPED" if equipped else "EQUIP"


static func row_status_text(owned: bool, can_buy: bool, equipped: bool = false) -> String:
	## Soft P2: this is the one hideout wear/buy status. Do not also toast Bought / wearing / visual.
	if owned:
		return Contract.SHOP_EQUIPPED_COPY if equipped else Contract.SHOP_OWNED_COPY
	if not can_buy:
		return Contract.SHOP_INSUFFICIENT_COPY
	return ""


static func row_buy_enabled(owned: bool, can_buy: bool, buying: bool = false) -> bool:
	if buying:
		return false
	if owned:
		return true
	return can_buy
