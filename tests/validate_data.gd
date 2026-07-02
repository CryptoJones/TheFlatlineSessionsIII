extends SceneTree
## validate_data — headless integrity check for the story scaffold.
##
## Run:  godot --headless --path . --script res://tests/validate_data.gd
## Fails (exit 1) if any chapter, room graph, NPC dialog, quest, item, or
## cyberspace reference is broken — so the whole scaffold stays traversable
## while content grows. Pure FileAccess/JSON: no autoloads needed.

var errors: Array = []

func _initialize() -> void:
	var chapters = _json("res://data/chapters.json")
	var quests = _json("res://data/quests.json")
	var items = _json("res://data/items.json")
	var shops = _json("res://data/shops.json")
	var dbs = _json("res://data/cyberspace/databases.json")
	if chapters == null or not chapters.has("chapters"):
		_err("data/chapters.json missing or invalid")
		return _finish()
	var quest_defs: Dictionary = quests.get("quests", {}) if quests != null else {}
	var item_defs: Dictionary = items.get("items", {}) if items != null else {}
	var shop_defs: Dictionary = shops.get("shops", {}) if shops != null else {}
	var setters := _collect_flag_setters(chapters, dbs)

	for ch in chapters["chapters"]:
		var cid := str(ch.get("id", "?"))
		var rooms_path := str(ch.get("rooms", ""))
		var qid := str(ch.get("quest", ""))
		if qid == "" or not quest_defs.has(qid):
			_err("%s: quest '%s' not in data/quests.json" % [cid, qid])
		var rd = _json(rooms_path)
		if rd == null or not rd.has("rooms"):
			_err("%s: rooms file '%s' missing/invalid" % [cid, rooms_path])
			continue
		var rooms: Dictionary = rd["rooms"]
		var start := str(rd.get("start", ""))
		if not rooms.has(start):
			_err("%s: start room '%s' not in %s" % [cid, start, rooms_path])
		for rid in rooms:
			var r: Dictionary = rooms[rid]
			for dir in r.get("exits", {}):
				var dest := str(r["exits"][dir])
				if not rooms.has(dest):
					_err("%s: room %s exit %s -> missing room '%s'" % [cid, rid, dir, dest])
			for npc in r.get("npcs", []):
				var p := "res://data/npcs/%s.json" % str(npc)
				var nd = _json(p)
				if nd == null or not nd.has("nodes"):
					_err("%s: room %s npc '%s' — bad/missing %s" % [cid, rid, npc, p])
				else:
					_check_dialog(str(npc), nd)
			for pk in r.get("pickups", []):
				if not item_defs.has(str(pk.get("item", ""))):
					_err("%s: room %s pickup item '%s' not in items.json" % [cid, rid, str(pk.get("item", ""))])
			if r.has("shop") and not shop_defs.has(str(r["shop"])):
				_err("%s: room %s shop '%s' not in shops.json" % [cid, rid, str(r["shop"])])
		# Quest steps must be completable: every step flag needs a known setter.
		if quest_defs.has(qid):
			for st in quest_defs[qid].get("steps", []):
				var flag := str(st.get("flag", ""))
				if flag == "":
					_err("%s: quest %s has a step with no flag" % [cid, qid])
				elif not setters.has(flag):
					_err("%s: quest %s step flag '%s' has no setter (dialog set_flag / on_enter_flag / grant / pickup / cracked_db)" % [cid, qid, flag])

	# Shop stock must exist in items.json.
	for sid in shop_defs:
		for iid in shop_defs[sid].get("stock", []):
			if not item_defs.has(str(iid)):
				_err("shop %s stocks unknown item '%s'" % [sid, iid])
	_finish()

## Every flag anything in the data can set.
func _collect_flag_setters(chapters: Dictionary, dbs) -> Dictionary:
	var setters := {}
	# Dialog nodes: set_flag + grant (granted_<item>). Walk every npc file.
	var dir := DirAccess.open("res://data/npcs")
	if dir != null:
		for fn in dir.get_files():
			if not fn.ends_with(".json"):
				continue
			var nd = _json("res://data/npcs/" + fn)
			if nd == null:
				continue
			for nid in nd.get("nodes", {}):
				var n: Dictionary = nd["nodes"][nid]
				if n.has("set_flag"):
					setters[str(n["set_flag"])] = true
				if n.has("grant"):
					setters["granted_" + str(n["grant"])] = true
	# Rooms: on_enter_flag + pickups. Chapter starts: flags.
	for ch in chapters.get("chapters", []):
		for f in ch.get("start", {}).get("flags", []):
			setters[str(f)] = true
		var rd = _json(str(ch.get("rooms", "")))
		if rd == null:
			continue
		for rid in rd.get("rooms", {}):
			var r: Dictionary = rd["rooms"][rid]
			if r.has("on_enter_flag"):
				setters[str(r["on_enter_flag"])] = true
			for pk in r.get("pickups", []):
				setters["took_" + str(pk.get("item", ""))] = true
				setters["granted_" + str(pk.get("item", ""))] = true
	# Cyberspace: cracked_<id> + optional set_flag.
	if dbs != null:
		for d in dbs.get("databases", []):
			setters["cracked_" + str(d.get("id", ""))] = true
			if d.has("set_flag"):
				setters[str(d["set_flag"])] = true
	return setters

## Dialog graph sanity: start exists, every option's next exists.
func _check_dialog(npc: String, nd: Dictionary) -> void:
	var nodes: Dictionary = nd.get("nodes", {})
	if not nodes.has(str(nd.get("start", ""))):
		_err("npc %s: start node '%s' missing" % [npc, str(nd.get("start", ""))])
	for nid in nodes:
		for o in nodes[nid].get("options", []):
			var nxt := str(o.get("next", ""))
			if not nodes.has(nxt):
				_err("npc %s: node %s option -> missing node '%s'" % [npc, nid, nxt])

func _json(path: String):
	if not FileAccess.file_exists(path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))

func _err(msg: String) -> void:
	errors.append(msg)

func _finish() -> void:
	if errors.is_empty():
		print("validate_data: OK — scaffold is consistent.")
		quit(0)
	else:
		for e in errors:
			printerr("validate_data: " + e)
		printerr("validate_data: %d error(s)." % errors.size())
		quit(1)
