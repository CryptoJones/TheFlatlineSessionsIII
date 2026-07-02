extends RefCounted
## Catalog — items/shops data + buy/sell economy logic.
##
## Pure logic with NO autoload dependency: every mutating/query call takes the
## `state` object (the GameState autoload in-game, or a plain instance in the
## headless data check). Call load_data() once, then buy()/sell()/etc.

const ITEMS_PATH := "res://data/items.json"
const SHOPS_PATH := "res://data/shops.json"

var items: Dictionary = {}
var shops: Dictionary = {}

func load_data() -> void:
	items = _load(ITEMS_PATH).get("items", {})
	shops = _load(SHOPS_PATH).get("shops", {})

func _load(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_warning("Catalog: missing %s" % path)
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	return d if typeof(d) == TYPE_DICTIONARY else {}

func item(id: String) -> Dictionary:
	return items.get(id, {})

func item_name(id: String) -> String:
	return item(id).get("name", id)

func shop(id: String) -> Dictionary:
	return shops.get(id, {})

func price(id: String) -> int:
	return int(item(id).get("price", 0))

## Already owned? Skills land in state.skills, software in .software, the
## rest (hardware/misc/key items) in .inventory.
func owned(state, id: String) -> bool:
	var it := item(id)
	match it.get("type", ""):
		"skill": return state.skills.has(it.get("skill", id))
		"software": return state.software.has(id)
		_: return state.inventory.has(id)

func can_buy(state, id: String) -> bool:
	return not item(id).is_empty() and not owned(state, id) and state.credits >= price(id)

func buy(state, id: String) -> bool:
	if not can_buy(state, id):
		return false
	state.credits -= price(id)
	var it := item(id)
	match it.get("type", ""):
		"skill":
			var s: String = it.get("skill", id)
			state.skills[s] = max(int(state.skills.get(s, 0)), int(it.get("rating", 1)))
		"software":
			state.software[id] = { "rating": int(it.get("rating", 1)) }
		_:
			if not state.inventory.has(id):
				state.inventory.append(id)
	return true

## Resale is half list price (fences don't pay retail).
func sell_value(id: String) -> int:
	return int(price(id) / 2.0)

## Only tangible inventory is sellable — and never quest-key items.
func can_sell(state, id: String) -> bool:
	return state.inventory.has(id) and not bool(item(id).get("key", false))

func sell(state, id: String) -> bool:
	if not can_sell(state, id):
		return false
	state.inventory.erase(id)
	state.credits += sell_value(id)
	return true
