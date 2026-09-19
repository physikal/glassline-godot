extends RefCounted
## Hideout shop bag. Catalog + wallet + owned/equipped cosmetics.
## Client displays only — never `marks -=` on a buy.

const Contract := preload("res://types/contract.gd")

var raw: Dictionary = {}
var marks: Variant = null
var items: Array = []
var owned: Array = []
var equipped: String = ""
var error: String = ""
var ok: bool = true


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
	parsed.marks = _read_marks(bag, root)
	return parsed


static func _has_error(bag: Dictionary) -> bool:
	return str(bag.get("error", "")) != "" or str(bag.get("reason", "")) == Contract.SHOP_ERR_INSUFFICIENT


static func _read_error(bag: Dictionary) -> String:
	var result: Variant = bag.get("result", {})
	if result is Dictionary and str(result.get("type", "")) == Contract.ACT_REJECT:
		return str(result.get("reason", "rejected"))
	var err := str(bag.get("error", ""))
	if err != "":
		return err
	var reason := str(bag.get("reason", ""))
	if reason in [
		Contract.SHOP_ERR_INSUFFICIENT,
		Contract.SHOP_ERR_ALREADY_OWNED,
		Contract.SHOP_ERR_UNKNOWN_ITEM,
		Contract.SHOP_ERR_UNAVAILABLE,
	]:
		return reason
	return ""


static func _read_items(bag: Dictionary, root: Dictionary) -> Array:
	for source in [bag, root]:
		var list: Variant = source.get("items", source.get("catalog", []))
		if list is Array and not list.is_empty():
			return list.duplicate()
		var shop: Variant = source.get("shop", {})
		if shop is Dictionary:
			var nested: Variant = shop.get("items", [])
			if nested is Array and not nested.is_empty():
				return nested.duplicate()
	return [Contract.shop_stub_item()]


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
	for source in [bag, root]:
		var you: Variant = source.get("you", {})
		if you is Dictionary:
			var eq := _as_id(you.get("equipped", null))
			if eq != "":
				return eq
			var cosmetics: Variant = you.get("cosmetics", {})
			if cosmetics is Dictionary:
				eq = _as_id(cosmetics.get("equipped", null))
				if eq != "":
					return eq
		var eq_top := _as_id(source.get("equipped", null))
		if eq_top != "":
			return eq_top
		var shop: Variant = source.get("shop", {})
		if shop is Dictionary:
			var eq_shop := _as_id(shop.get("equipped", null))
			if eq_shop != "":
				return eq_shop
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


func has_marks() -> bool:
	return marks != null


func balance() -> int:
	return int(marks) if has_marks() else 0


func stub_item() -> Dictionary:
	for entry in items:
		if entry is Dictionary and str(entry.get("itemId", "")) == Contract.SHOP_STUB_ITEM_ID:
			return entry
	if not items.is_empty() and items[0] is Dictionary:
		return items[0]
	return Contract.shop_stub_item()


func price() -> int:
	var item := stub_item()
	if item.has("priceMarks"):
		return int(item.get("priceMarks"))
	if item.has("price"):
		return int(item.get("price"))
	return Contract.SHOP_STUB_PRICE


func item_id() -> String:
	return str(stub_item().get("itemId", Contract.SHOP_STUB_ITEM_ID))


func item_name() -> String:
	return str(stub_item().get("name", Contract.SHOP_STUB_ITEM_NAME))


func owns_stub() -> bool:
	return owned.has(item_id()) or owned.has(Contract.SHOP_STUB_ITEM_ID)


func is_equipped() -> bool:
	var id := item_id()
	return equipped == id or equipped == Contract.SHOP_STUB_ITEM_ID


func is_insufficient() -> bool:
	return error == Contract.SHOP_ERR_INSUFFICIENT


func is_unavailable() -> bool:
	return error == Contract.SHOP_ERR_UNAVAILABLE or error == "http_404" or error.begins_with("http_404")


func can_afford() -> bool:
	return balance() >= price()


static func row_action_text(owned: bool) -> String:
	## Owned chrome is OWNED (visual toggle), never EQUIPPED / stowed.
	return "OWNED" if owned else "BUY"


static func row_status_text(owned: bool, can_buy: bool) -> String:
	if owned:
		return Contract.SHOP_OWNED_COPY
	if not can_buy:
		return Contract.SHOP_INSUFFICIENT_COPY
	return ""


static func row_buy_enabled(owned: bool, can_buy: bool, buying: bool = false) -> bool:
	if buying:
		return false
	if owned:
		return true
	return can_buy
