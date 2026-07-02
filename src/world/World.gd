extends RefCounted
## World — loads an authored room graph (data/rooms/*.json) and answers queries
## about rooms and exits. Pure data/logic. In the sequels each CHAPTER has its
## own room file, so load_file() is called on every chapter start.

var start_id: String = ""
var rooms: Dictionary = {}     # id -> { name, bg, desc, npcs?, exits, ... }

func load_file(path: String) -> bool:
	start_id = ""
	rooms = {}
	if not FileAccess.file_exists(path):
		push_warning("World: missing room file '%s'" % path)
		return false
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("rooms"):
		push_warning("World: bad room file '%s'" % path)
		return false
	start_id = parsed.get("start", "")
	rooms = parsed["rooms"]
	return rooms.has(start_id)

func has_room(id: String) -> bool:
	return rooms.has(id)

func room(id: String) -> Dictionary:
	return rooms.get(id, {})

func exits(id: String) -> Dictionary:
	return room(id).get("exits", {})

## Resolve a move from room `id` in `direction`; returns the destination id or
## "" if there is no exit that way.
func move(id: String, direction: String) -> String:
	return exits(id).get(direction, "")
