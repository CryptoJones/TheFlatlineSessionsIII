extends RefCounted
## SaveSystem — multi-slot, named JSON saves under user://saves/<slug>.json.
##
## Each file holds { "meta": {name, saved_at, chapter, room, player, credits},
## "state": <GameState> } so the load menu can show a real list of save points.
## A reserved "quicksave" slug backs F5/F9.

const SAVE_DIR := "user://saves/"
const QUICK_SLUG := "quicksave"
const AUTO_SLUG := "autosave"


static func _ensure_dir() -> void:
	if not DirAccess.dir_exists_absolute(SAVE_DIR):
		DirAccess.make_dir_recursive_absolute(SAVE_DIR)


static func _slug(display_name: String) -> String:
	var s := display_name.strip_edges().to_lower()
	var out := ""
	for ch in s:
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9"):
			out += ch
		elif ch == " " or ch == "-" or ch == "_":
			out += "_"
	out = out.lstrip("_").rstrip("_")
	return out if out != "" else "save"


static func _path(slug: String) -> String:
	return SAVE_DIR + slug + ".json"


static func save_as(display_name: String) -> bool:
	return _write(_slug(display_name), display_name)


static func quicksave() -> bool:
	return _write(QUICK_SLUG, "Quicksave")


## Rolling autosave slot, refreshed automatically as the player progresses.
static func autosave() -> bool:
	return _write(AUTO_SLUG, "Autosave")


static func _write(slug: String, display_name: String) -> bool:
	_ensure_dir()
	var f := FileAccess.open(_path(slug), FileAccess.WRITE)
	if f == null:
		push_warning("SaveSystem: cannot write %s" % _path(slug))
		return false
	var data := {
		"meta": {
			"name": display_name,
			"saved_at": Time.get_datetime_string_from_system(false, true),
			"chapter": GameState.current_chapter,
			"room": GameState.current_room,
			"player": GameState.player_name,
			"credits": GameState.credits,
		},
		"state": GameState.to_dict(),
	}
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	return true


## Every save on disk, newest first.
static func list_saves() -> Array:
	_ensure_dir()
	var out: Array = []
	var d := DirAccess.open(SAVE_DIR)
	if d == null:
		return out
	for fn in d.get_files():
		if not fn.ends_with(".json"):
			continue
		var slug := fn.get_basename()
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(_path(slug)))
		if typeof(parsed) != TYPE_DICTIONARY:
			continue
		var meta = parsed.get("meta", {})
		out.append({
			"slug": slug,
			"name": str(meta.get("name", slug)),
			"saved_at": str(meta.get("saved_at", "")),
			"chapter": str(meta.get("chapter", "")),
			"room": str(meta.get("room", "")),
			"player": str(meta.get("player", "")),
			"credits": int(meta.get("credits", 0)),
		})
	out.sort_custom(func(a, b): return str(a["saved_at"]) > str(b["saved_at"]))
	return out


static func load_slug(slug: String) -> bool:
	var p := _path(slug)
	if not FileAccess.file_exists(p):
		return false
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(p))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("SaveSystem: corrupt save %s" % slug)
		return false
	var state = parsed.get("state", null)
	if typeof(state) != TYPE_DICTIONARY:
		return false
	GameState.from_dict(state)
	return true


static func delete_slug(slug: String) -> bool:
	var d := DirAccess.open(SAVE_DIR)
	if d == null:
		return false
	if d.file_exists(slug + ".json"):
		return d.remove(slug + ".json") == OK
	return false


static func has_any() -> bool:
	return not list_saves().is_empty()
