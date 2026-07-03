extends SceneTree
## playthrough — headless whole-game traversal for sequel scaffolds.
##
## Run:
##   godot --headless --path . --script res://tests/playthrough.gd
##
## This does not solve narrative puzzles. It proves every chapter can be loaded,
## every authored room is reachable through exits, and the runtime-facing
## references a player can hit during normal exploration resolve.

const BG_DIR := "res://assets/backgrounds_hd/"
const MUSIC_DIR := "res://assets/audio/music/"
const VOID_ROOM := "1337"
const VOID_ART := "res://assets/ui/void.png"

var errors: Array[String] = []


func _initialize() -> void:
	var chapters = _json("res://data/chapters.json")
	var quests = _json("res://data/quests.json")
	var items = _json("res://data/items.json")
	var shops = _json("res://data/shops.json")
	var dbs = _json("res://data/cyberspace/databases.json")
	if chapters == null or not chapters.has("chapters"):
		_err("data/chapters.json missing or invalid")
		return _finish()
	if not _exists(VOID_ART):
		_err("hidden room art missing: %s" % VOID_ART)
	var quest_defs: Dictionary = quests.get("quests", {}) if quests != null else {}
	var item_defs: Dictionary = items.get("items", {}) if items != null else {}
	var shop_defs: Dictionary = shops.get("shops", {}) if shops != null else {}
	var music_tracks := _collect_music_tracks(chapters)
	for track in music_tracks:
		var path := MUSIC_DIR + str(track) + ".ogg"
		if not _exists(path):
			_err("music track missing: %s" % path)

	for ch in chapters.get("chapters", []):
		_check_chapter(ch, quest_defs, item_defs, shop_defs, dbs)

	_check_cyberspace(dbs)
	_check_hidden_room_hooks()
	_finish()


func _check_chapter(ch: Dictionary, quest_defs: Dictionary, item_defs: Dictionary, shop_defs: Dictionary, dbs) -> void:
	var cid := str(ch.get("id", "?"))
	var rooms_path := str(ch.get("rooms", ""))
	var rd = _json(rooms_path)
	if rd == null or not rd.has("rooms"):
		_err("%s: rooms file '%s' missing/invalid" % [cid, rooms_path])
		return
	var rooms: Dictionary = rd["rooms"]
	var start := str(rd.get("start", ""))
	if not rooms.has(start):
		_err("%s: start room '%s' not present" % [cid, start])
		return
	var reached := _walk_rooms(start, rooms)
	for rid in rooms:
		if not reached.has(rid):
			_err("%s: room '%s' is unreachable from start '%s'" % [cid, rid, start])
	for rid in reached.keys():
		var r: Dictionary = rooms[rid]
		_check_room(cid, rid, r, rooms, item_defs, shop_defs)
	var qid := str(ch.get("quest", ""))
	if qid == "" or not quest_defs.has(qid):
		_err("%s: quest '%s' missing from data/quests.json" % [cid, qid])
	else:
		_check_quest(cid, qid, quest_defs[qid], rooms, dbs)


func _walk_rooms(start: String, rooms: Dictionary) -> Dictionary:
	var reached := {}
	var queue: Array[String] = [start]
	while not queue.is_empty():
		var rid: String = queue.pop_front()
		if reached.has(rid):
			continue
		reached[rid] = true
		var r: Dictionary = rooms.get(rid, {})
		for dir in r.get("exits", {}):
			var dest := str(r["exits"][dir])
			if rooms.has(dest) and not reached.has(dest):
				queue.append(dest)
	return reached


func _check_room(cid: String, rid: String, r: Dictionary, rooms: Dictionary, item_defs: Dictionary, shop_defs: Dictionary) -> void:
	if str(r.get("name", "")).strip_edges() == "":
		_err("%s: room %s has no name" % [cid, rid])
	if str(r.get("desc", "")).strip_edges() == "":
		_err("%s: room %s has no description" % [cid, rid])
	if str(r.get("bg", "")) != "" and not _exists(BG_DIR + str(r["bg"]) + ".png"):
		_err("%s: room %s background missing: %s%s.png" % [cid, rid, BG_DIR, str(r["bg"])])
	for dir in r.get("exits", {}):
		var dest := str(r["exits"][dir])
		if not rooms.has(dest):
			_err("%s: room %s exit %s -> missing room '%s'" % [cid, rid, dir, dest])
		elif rooms[dest].has("requires_flag") and str(rooms[dest].get("locked_text", "")).strip_edges() == "":
			_err("%s: room %s gated exit %s -> %s has no locked_text" % [cid, rid, dir, dest])
	for npc in r.get("npcs", []):
		var p := "res://data/npcs/%s.json" % str(npc)
		var nd = _json(p)
		if nd == null or not nd.has("nodes"):
			_err("%s: room %s npc '%s' bad/missing dialog file" % [cid, rid, npc])
		else:
			_check_dialog(str(npc), nd)
	for pk in r.get("pickups", []):
		var iid := str(pk.get("item", ""))
		if not item_defs.has(iid):
			_err("%s: room %s pickup item '%s' not in items.json" % [cid, rid, iid])
	if r.has("shop") and not shop_defs.has(str(r["shop"])):
		_err("%s: room %s shop '%s' not in shops.json" % [cid, rid, str(r["shop"])])
	if r.has("music") and not _exists(MUSIC_DIR + str(r["music"]) + ".ogg"):
		_err("%s: room %s explicit music '%s' missing" % [cid, rid, str(r["music"])])


func _check_dialog(npc: String, nd: Dictionary) -> void:
	var nodes: Dictionary = nd.get("nodes", {})
	var start := str(nd.get("start", ""))
	if not nodes.has(start):
		_err("npc %s: start node '%s' missing" % [npc, start])
	for nid in nodes:
		var n: Dictionary = nodes[nid]
		if str(n.get("text", "")).strip_edges() == "":
			_err("npc %s: node %s has no text" % [npc, nid])
		for o in n.get("options", []):
			var nxt := str(o.get("next", ""))
			if not nodes.has(nxt):
				_err("npc %s: node %s option -> missing node '%s'" % [npc, nid, nxt])


func _check_quest(cid: String, qid: String, q: Dictionary, rooms: Dictionary, dbs) -> void:
	var setters := {}
	for rid in rooms:
		var r: Dictionary = rooms[rid]
		if r.has("on_enter_flag"):
			setters[str(r["on_enter_flag"])] = true
		for pk in r.get("pickups", []):
			setters["took_" + str(pk.get("item", ""))] = true
			setters["granted_" + str(pk.get("item", ""))] = true
	for npc_file in _npc_files():
		var nd = _json("res://data/npcs/" + npc_file)
		if nd == null:
			continue
		for nid in nd.get("nodes", {}):
			var n: Dictionary = nd["nodes"][nid]
			if n.has("set_flag"):
				setters[str(n["set_flag"])] = true
			if n.has("grant"):
				setters["granted_" + str(n["grant"])] = true
	if dbs != null:
		for d in dbs.get("databases", []):
			setters["cracked_" + str(d.get("id", ""))] = true
			if d.has("set_flag"):
				setters[str(d["set_flag"])] = true
	for st in q.get("steps", []):
		var flag := str(st.get("flag", ""))
		if flag == "":
			_err("%s: quest %s has a step with no flag" % [cid, qid])
		elif not setters.has(flag):
			_err("%s: quest %s step flag '%s' has no reachable setter" % [cid, qid, flag])


func _check_cyberspace(dbs) -> void:
	if dbs == null:
		_err("data/cyberspace/databases.json missing or invalid")
		return
	var ids := {}
	for d in dbs.get("databases", []):
		var id := str(d.get("id", ""))
		if id == "":
			_err("cyberspace database with blank id")
			continue
		ids[id] = true
		if d.has("bg"):
			var bg := "res://assets/cyberspace/%s.png" % str(d["bg"])
			if not _exists(bg):
				_err("cyberspace db %s art missing: %s" % [id, bg])
	for d in dbs.get("databases", []):
		if d.has("requires") and not ids.has(str(d["requires"])):
			_err("cyberspace db %s requires missing db '%s'" % [str(d.get("id", "")), str(d["requires"])])


func _check_hidden_room_hooks() -> void:
	var game := FileAccess.get_file_as_string("res://src/core/Game.gd")
	var audio := FileAccess.get_file_as_string("res://src/core/AudioManager.gd")
	for needle in ["HIDDEN_ROOM := \"1337\"", "VOID_TRACKS", "_show_void_room", "_void_nowplaying"]:
		if not game.contains(needle):
			_err("hidden room hook missing in Game.gd: %s" % needle)
	for needle in ["play_playlist", "next_track", "prev_track", "current_track"]:
		if not audio.contains(needle):
			_err("hidden room playlist hook missing in AudioManager.gd: %s" % needle)


func _collect_music_tracks(chapters: Dictionary) -> Dictionary:
	var tracks := {
		"title": true,
		"streets": true,
		"shops": true,
		"cyberspace": true,
		"ice_combat": true,
	}
	var audio := FileAccess.get_file_as_string("res://src/core/AudioManager.gd")
	var in_map := false
	for line in audio.split("\n"):
		var t := line.strip_edges()
		if t.begins_with("const CHAPTER_TRACKS"):
			in_map = true
			continue
		if in_map and t.begins_with("}"):
			break
		if not in_map:
			continue
		var parts := t.split("\"")
		if parts.size() >= 4:
			tracks[str(parts[3])] = true
	return tracks


func _npc_files() -> Array[String]:
	var files: Array[String] = []
	var dir := DirAccess.open("res://data/npcs")
	if dir == null:
		return files
	for fn in dir.get_files():
		if fn.ends_with(".json"):
			files.append(fn)
	return files


func _json(path: String):
	if not _exists(path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))


func _exists(path: String) -> bool:
	return FileAccess.file_exists(path) or ResourceLoader.exists(path)


func _err(msg: String) -> void:
	errors.append(msg)


func _finish() -> void:
	if errors.is_empty():
		print("PLAYTHROUGH: PASS")
		quit(0)
	else:
		for e in errors:
			printerr("PLAYTHROUGH: " + e)
		printerr("PLAYTHROUGH: FAIL - %d error(s)." % errors.size())
		quit(1)
