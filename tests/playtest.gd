extends Node
## Headless playtest — ships with every scaffolded game.
##
## Everything it expects is derived from the game's OWN data (which systems have
## content, which music files exist, whether the chapter quests require scenes),
## so it needs no editing per game.
##
## Two passes:
##   1. RUNTIME — boots the real game scene and drives it through the whole state
##      machine (splash -> title -> chapters -> story cards -> explore -> dialog ->
##      menus -> matrix -> void room), so runtime errors actually surface.
##   2. AUDIT — walks the story graph: room reachability, dead ends, orphan dialog
##      nodes, broken option links, dialogs that can never end, quest flags with no
##      setter, engine features the content never reaches, soundtrack cues that can
##      never play, and pacing.
##
##   godot --headless --path . res://tests/playtest.tscn

const WorldScript = preload("res://src/world/World.gd")

const CHAPTERS := "res://data/chapters.json"
const NPC_DIR := "res://data/npcs/"
const ROOMS_DIR := "res://data/rooms/"
const ITEMS := "res://data/items.json"
const SHOPS := "res://data/shops.json"
const QUESTS := "res://data/quests.json"
const DBS := "res://data/cyberspace/databases.json"

const MUSIC_DIR := "res://assets/audio/music/"

var errors: Array[String] = []
var notes: Array[String] = []
var chapters: Array = []
var game: Control
var rooms_seen := 0
var dialogs_driven := 0
var cues_played := {}          # cue id -> true, recorded from AudioManager
var softlocks_found := 0         # impatient-reader failures; gates its success note
var action_labels := {}        # action-bar button text seen in play
var feature_counts := {}       # filled by _audit_features, read by _audit_action_bar


## Everything under user:// before the run, restored byte-for-byte afterwards.
## The playtest boots the REAL game, and the real game writes to the same
## user:// folder the player's copy uses: it rolls the autosave on every room,
## and some games record endings or settings. Without this, one test run
## overwrites the developer's own saved game.
var _user_snapshot := {}
var _user_restored := false
const USER_SKIP := ["logs", "shader_cache", "objectdb_snapshots", "vulkan"]


func _ready() -> void:
	_snapshot_user_dir()
	print("playtest: start")
	var doc = _json(CHAPTERS)
	chapters = (doc.get("chapters", []) if doc != null else [])
	print("playtest: %d chapters loaded" % chapters.size())
	await _drive_runtime()
	print("playtest: runtime pass done; auditing")
	_audit_rooms()
	_audit_dialogs()
	_audit_quests()
	_audit_features()
	_audit_action_bar()
	_audit_soundtrack()
	_audit_text_sizes()
	await _audit_action_bar_fit()
	await _audit_dialog_scroll()
	await _audit_dialog_paging()
	_audit_story_art()
	if softlocks_found == 0:
		_note("impatient reader: every chapter it could play stays finishable using legal moves only")
	_report()


# ------------------------------------------------------------------ runtime pass
func _drive_runtime() -> void:
	var packed: PackedScene = load("res://scenes/Boot.tscn")
	if packed == null:
		_err("cannot load res://scenes/Boot.tscn")
		return
	game = packed.instantiate()
	add_child(game)
	# Belt and braces with the user-data guard: never roll the autosave in a test.
	if "_autosave" in game:
		game._autosave = false
	await get_tree().process_frame
	await get_tree().process_frame
	# Record every cue that actually plays, so the soundtrack audit is empirical
	# rather than a guess about which code paths are reachable.
	AudioManager.track_changed.connect(func(t: String) -> void: cues_played[t] = true)
	_note("booted Boot.tscn (state=%d)" % game._state)

	# Skip the ident and the dedication, then land on chapter select.
	game._go_title()
	await get_tree().process_frame
	game._go_chapters()
	await get_tree().process_frame
	_note("state machine reached chapter select")

	for ch in chapters:
		await _drive_chapter(str(ch.get("id", "")))
	for ch in chapters:
		await _drive_impatient_reader(str(ch.get("id", "")))

	# Global menus / systems that don't belong to one chapter.
	game._open_inventory()
	game._open_quest_log()
	game._hint()
	game._open_net()
	game._open_net_news()
	game._open_net_messages()
	game._go_matrix()
	await get_tree().process_frame
	game._jack_out()
	game._show_void_room()
	await get_tree().process_frame
	game._void_skip()
	await get_tree().process_frame
	_note("drove menus, net, matrix and the void room")


func _drive_chapter(cid: String) -> void:
	if cid == "":
		return
	print("  driving chapter %s" % cid)
	game._start_chapter(cid)
	await get_tree().process_frame
	if GameState.current_chapter != cid:
		_err("start_chapter('%s') left current_chapter='%s'" % [cid, GameState.current_chapter])
		return
	# Step through the intro story cards, then enter the room graph.
	var pages: Array = game._story_pages
	if pages.size() > 1:
		game._story_next()
		await get_tree().process_frame
	game._go_explore()
	await get_tree().process_frame
	if not game._world.has_room(GameState.current_room):
		_err("%s: start room '%s' not in room graph" % [cid, GameState.current_room])
		return
	game._refresh_room()
	game._hint()
	await get_tree().process_frame

	# A chapter must not be concludable by walking through it: visit every room
	# without playing a single scene, and the gate has to stay shut.
	var qid := str(game._current_chapter().get("quest", ""))
	var scenes_required := _requires_scenes(qid)
	for rid in game._world.rooms:
		GameState.current_room = str(rid)
		game._refresh_room()
	if scenes_required and (game._quests.is_complete(GameState, qid) or _conclude_offered()):
		_err("%s: chapter can be concluded by walking the rooms, without playing any scene" % cid)

	# Walk every room in the chapter and open every conversation in it.
	for rid in game._world.rooms:
		GameState.current_room = str(rid)
		game._refresh_room()
		rooms_seen += 1
		for child in game._button_bar.get_children():
			if child is Button:
				action_labels[(child as Button).text] = true
		var room: Dictionary = game._world.rooms[rid]
		for npc in room.get("npcs", []):
			# ...and it stays shut until the LAST scene has been heard out.
			if scenes_required and GameState.has_flag("heard_" + str(npc)) == false and game._quests.is_complete(GameState, qid):
				_err("%s: chapter goal completed before scene '%s' was played" % [cid, npc])
			game._go_dialog(str(npc))
			await get_tree().process_frame
			_drive_dialog(str(npc))
			game._end_dialog()
	await get_tree().process_frame
	GameState.current_room = str(game._world.rooms.keys()[-1])
	game._refresh_room()
	if scenes_required and (not game._quests.is_complete(GameState, qid) or not _conclude_offered()):
		_err("%s: every scene played but 'Conclude chapter' is still not offered (open step: %s)" % [cid, game._quests.objective(GameState, qid)])
	# Finish the chapter: exercise the quest check and the outro story cards.
	game._check_quest()
	game._conclude_chapter()
	await get_tree().process_frame
	if game._story_pages.size() > 1:
		game._story_next()
		await get_tree().process_frame
	game._go_chapters()
	await get_tree().process_frame


## The reader who skips ahead. Uses ONLY legal moves (the same _try_move a click
## makes — no teleporting): always pushes east, talks only when there is nothing
## else to do, and backtracks west for anything missed. Whatever they do, the
## chapter must stay finishable. Teleporting tests cannot see a soft-lock — this
## is the one that catches "walked past a required scene into a room with no
## way back".
func _drive_impatient_reader(cid: String) -> void:
	if cid == "":
		return
	game._start_chapter(cid)
	await get_tree().process_frame
	game._go_explore()
	await get_tree().process_frame
	var qid := str(game._current_chapter().get("quest", ""))
	if not _walk_and_talk_only(qid):
		_note("%s: impatient reader skipped — the quest needs more than walking and talking" % cid)
		game._go_chapters()
		await get_tree().process_frame
		return
	var backtracking := false
	var guard := 0
	while not game._quests.is_complete(GameState, qid) and guard < 600:
		guard += 1
		var here: String = GameState.current_room
		if not backtracking:
			game._try_move("east")
			if GameState.current_room != here:
				continue
		var talked := false
		for npc in game._world.room(here).get("npcs", []):
			if not GameState.has_flag("heard_" + str(npc)):
				game._go_dialog(str(npc))
				await get_tree().process_frame
				_drive_dialog(str(npc))
				game._end_dialog()
				talked = true
		if talked:
			backtracking = false
			continue
		# nothing left to do here and the goal is still open: go back for it
		backtracking = true
		game._try_move("west")
		if GameState.current_room == here:
			softlocks_found += 1
			_err("%s: SOFT-LOCK in room '%s' — goal still open (%s), nothing to do here, and no way back" % [cid, here, game._quests.objective(GameState, qid)])
			return
	if not game._quests.is_complete(GameState, qid):
		softlocks_found += 1
		_err("%s: impatient reader never finished the chapter (stuck in '%s')" % [cid, GameState.current_room])
		return
	game._refresh_room()
	if not _conclude_offered():
		_err("%s: impatient reader finished every objective but Conclude is not offered" % cid)
	game._go_chapters()
	await get_tree().process_frame


## True when the chapter quest makes at least one conversation mandatory.
func _requires_scenes(qid: String) -> bool:
	for st in game._quests.steps(qid):
		if str(st.get("flag", "")).begins_with("heard_"):
			return true
	return false


## True when every quest step is met by entering a room or hearing a scene out —
## the only things the impatient reader knows how to do.
func _walk_and_talk_only(qid: String) -> bool:
	var enter_flags := {}
	for rid in game._world.rooms:
		enter_flags[str(game._world.rooms[rid].get("on_enter_flag", ""))] = true
	var steps: Array = game._quests.steps(qid)
	for st in steps:
		var flag := str(st.get("flag", ""))
		if not (flag.begins_with("heard_") or enter_flags.has(flag)):
			return false
	return not steps.is_empty()


func _conclude_offered() -> bool:
	for child in game._button_bar.get_children():
		if child is Button and not child.is_queued_for_deletion() and (child as Button).text.begins_with("Conclude chapter"):
			return true
	return false


func _drive_dialog(npc: String) -> void:
	var dlg = game._dialog
	if dlg == null:
		_err("dialog for '%s' did not load" % npc)
		return
	dialogs_driven += 1
	var guard := 0
	while not dlg.is_terminal() and guard < 2000:
		guard += 1
		if not dlg.choose(0):
			_err("dialog '%s' choose(0) refused at node '%s'" % [npc, dlg.current_id()])
			return
	if guard >= 2000:
		_err("dialog '%s' did not terminate within 2000 choices (possible loop)" % npc)
	# choose() was driven directly; let the game react to the node it landed on
	# the way it does after a real click (arrival hooks, heard_<npc>, quest check).
	game._refresh_dialog()


# -------------------------------------------------------------------- audit pass
func _audit_rooms() -> void:
	var total := 0
	for ch in chapters:
		var cid := str(ch.get("id", ""))
		var w = WorldScript.new()
		if not w.load_file(str(ch.get("rooms", ""))):
			_err("%s: cannot load rooms '%s'" % [cid, str(ch.get("rooms", ""))])
			continue
		total += w.rooms.size()
		var reached := {}
		var queue: Array[String] = [w.start_id]
		while not queue.is_empty():
			var rid: String = queue.pop_front()
			if reached.has(rid):
				continue
			reached[rid] = true
			for dir in w.exits(rid):
				var dest := str(w.exits(rid)[dir])
				if w.has_room(dest) and not reached.has(dest):
					queue.append(dest)
		for rid in w.rooms:
			if not reached.has(rid):
				_err("%s: room '%s' unreachable from start '%s'" % [cid, rid, w.start_id])
		for rid in w.rooms:
			var r: Dictionary = w.rooms[rid]
			var ex: Dictionary = r.get("exits", {})
			if ex.is_empty():
				_note("%s: dead-end room '%s' (no exits)" % [cid, rid])
			if r.has("requires_flag") and str(r.get("locked_text", "")).strip_edges() == "":
				_err("%s: gated room '%s' has no locked_text" % [cid, rid])
	_note("room graph: %d rooms across %d chapters" % [total, chapters.size()])


func _audit_dialogs() -> void:
	var files := DirAccess.get_files_at("res://data/npcs")
	var nodes_total := 0
	var words_total := 0
	var terminals := 0
	for fn in files:
		if not fn.ends_with(".json"):
			continue
		var d = _json(NPC_DIR + fn)
		if d == null:
			_err("npc %s: unparseable JSON" % fn)
			continue
		var nodes: Dictionary = d.get("nodes", {})
		var start := str(d.get("start", ""))
		if not nodes.has(start):
			_err("npc %s: start node '%s' missing" % [fn, start])
			continue
		nodes_total += nodes.size()
		var has_terminal := false
		var reached := {}
		var stack: Array[String] = [start]
		# Engines that gate the entry node on a flag ("start_gates") make those
		# nodes roots too — they are reached without any option pointing at them.
		for g in d.get("start_gates", []):
			if typeof(g) == TYPE_DICTIONARY and nodes.has(str(g.get("start", ""))):
				stack.append(str(g.get("start", "")))
		while not stack.is_empty():
			var nid: String = stack.pop_back()
			if reached.has(nid):
				continue
			reached[nid] = true
			var n: Dictionary = nodes[nid]
			words_total += _node_text(n).split(" ", false).size()
			var opts: Array = n.get("options", [])
			if opts.is_empty():
				has_terminal = true
			for o in opts:
				if str(o.get("text", "")).strip_edges() == "":
					_err("npc %s: node %s has an option with empty text" % [fn, nid])
				if not o.has("next"):
					_err("npc %s: node %s option '%s' has no 'next'"
						% [fn, nid, str(o.get("text", ""))])
					continue
				var nxt := str(o.get("next", ""))
				if nxt != "" and not nodes.has(nxt):
					_err("npc %s: node %s option -> missing node '%s'" % [fn, nid, nxt])
				elif nxt != "" and not reached.has(nxt):
					stack.append(nxt)
		if not has_terminal:
			_err("npc %s: no terminal node — the conversation can never end" % fn)
		else:
			terminals += 1
		for nid in nodes:
			if not reached.has(nid):
				_err("npc %s: orphan node '%s' unreachable from start" % [fn, nid])
			if _node_text(nodes[nid]).strip_edges() == "":
				_err("npc %s: node %s has empty text" % [fn, nid])
	_note("dialogs: %d files, %d nodes, %d words, %d end cleanly"
		% [files.size(), nodes_total, words_total, terminals])


## A node's text, or all of its "random_text" lines for engines that pick one.
func _node_text(n: Dictionary) -> String:
	var t := str(n.get("text", ""))
	for line in n.get("random_text", []):
		t += " " + str(line)
	return t


func _audit_quests() -> void:
	var setters := {}
	for fn in DirAccess.get_files_at("res://data/rooms"):
		if not fn.ends_with(".json"):
			continue
		var d = _json(ROOMS_DIR + fn)
		if d == null:
			continue
		for rid in (d.get("rooms", {}) as Dictionary):
			var r: Dictionary = d["rooms"][rid]
			if r.has("on_enter_flag"):
				setters[str(r["on_enter_flag"])] = true
			for pk in r.get("pickups", []):
				setters["took_" + str(pk.get("item", ""))] = true
				setters["granted_" + str(pk.get("item", ""))] = true
			# games that add room interactions (an Inspect action) set flags there too
			for it in r.get("interactions", []):
				if typeof(it) == TYPE_DICTIONARY and it.has("set_flag"):
					setters[str(it["set_flag"])] = true
	# slotting a chip (item "slot": true) sets slotted_<item id> in engines with a socket
	for iid in _dict_of(ITEMS, "items"):
		if bool(_dict_of(ITEMS, "items")[iid].get("slot", false)):
			setters["slotted_" + str(iid)] = true
	# chapter start flags and cracked databases are setters as well
	for ch in chapters:
		for f in ch.get("start", {}).get("flags", []):
			setters[str(f)] = true
	for d in _list_of(DBS, "databases"):
		setters["cracked_" + str(d.get("id", ""))] = true
		if d.has("set_flag"):
			setters[str(d["set_flag"])] = true
	for fn in DirAccess.get_files_at("res://data/npcs"):
		if not fn.ends_with(".json"):
			continue
		var d = _json(NPC_DIR + fn)
		if d == null:
			continue
		for nid in (d.get("nodes", {}) as Dictionary):
			var n: Dictionary = d["nodes"][nid]
			if n.has("set_flag"):
				setters[str(n["set_flag"])] = true
			if n.has("grant"):
				setters["granted_" + str(n["grant"])] = true
			# a conversation heard to its end sets heard_<npc id>
			if (n.get("options", []) as Array).is_empty():
				setters["heard_" + fn.get_basename()] = true

	var qdoc = _json(QUESTS)
	var quests: Dictionary = (qdoc.get("quests", {}) if qdoc != null else {})
	var steps := 0
	for qid in quests:
		for st in quests[qid].get("steps", []):
			steps += 1
			var flag := str(st.get("flag", ""))
			if flag == "":
				_err("quest %s: step with no flag" % qid)
			elif not setters.has(flag):
				_err("quest %s: step flag '%s' has no setter anywhere" % [qid, flag])
	_note("quests: %d quests, %d steps, %d flag setters" % [quests.size(), steps, setters.size()])


func _audit_features() -> void:
	var rooms := 0
	var matrix_rooms := 0
	var net_rooms := 0
	var shop_rooms := 0
	var pickup_rooms := 0
	for fn in DirAccess.get_files_at("res://data/rooms"):
		if not fn.ends_with(".json"):
			continue
		var d = _json(ROOMS_DIR + fn)
		if d == null:
			continue
		for rid in (d.get("rooms", {}) as Dictionary):
			rooms += 1
			var r: Dictionary = d["rooms"][rid]
			if r.get("matrix", false):
				matrix_rooms += 1
			if r.get("net", false):
				net_rooms += 1
			if r.has("shop"):
				shop_rooms += 1
			if r.has("pickups"):
				pickup_rooms += 1
	var items: Dictionary = _dict_of(ITEMS, "items")
	var shops: Dictionary = _dict_of(SHOPS, "shops")
	var dbs: Array = _list_of(DBS, "databases")
	feature_counts = {"items": items.size(), "matrix": matrix_rooms, "net": net_rooms, "shop": shop_rooms, "pickups": pickup_rooms}
	_note("features: items=%d shops=%d databases=%d | rooms with matrix=%d net=%d shop=%d pickups=%d"
		% [items.size(), shops.size(), dbs.size(), matrix_rooms, net_rooms, shop_rooms, pickup_rooms])
	if matrix_rooms == 0 and items.is_empty():
		_note("engine features unused: no room has matrix=true and no hardware item "
			+ "exists, so _has_deck() is never true and the cyberspace mini-game / ICE "
			+ "combat can never be entered (their cues are assigned to rooms instead)")
	elif dbs.is_empty():
		_note("engine features unused: no cyberspace databases authored, so ICE combat never starts")


func _audit_action_bar() -> void:
	# Systems this game has no content for must not be offered in the UI at all.
	var forbidden := {}
	if int(feature_counts.get("items", 0)) == 0 and int(feature_counts.get("pickups", 0)) == 0:
		forbidden["Items"] = "no items, software or skills exist"
	if int(feature_counts.get("shop", 0)) == 0:
		forbidden["Shop"] = "no room has a shop"
	if int(feature_counts.get("net", 0)) == 0:
		forbidden["NET"] = "no room has net/pax"
	if int(feature_counts.get("matrix", 0)) == 0:
		forbidden["Jack In"] = "no room has matrix"
	for label in forbidden:
		if action_labels.has(label):
			_err("action bar offers '%s' but %s" % [label, forbidden[label]])
	_note("action bar offered: %s" % ", ".join(PackedStringArray(action_labels.keys())))


## Every Text Size setting must hold every room description unclipped, and every
## dialog passage must fit outright at the default size (a passage may scroll
## only at the sizes above it). Drives the real
## layout code against the real content, so a long new passage or a new size
## fails here instead of in front of a reader. Never touches settings.cfg.
func _audit_text_sizes() -> void:
	if game == null:
		return
	var descs: Array = []
	var passages: Array = []
	for fn in DirAccess.get_files_at(ROOMS_DIR):
		if fn.ends_with(".json"):
			_collect_strings(_json(ROOMS_DIR + fn), "desc", descs)
	for fn in DirAccess.get_files_at(NPC_DIR):
		if fn.ends_with(".json"):
			_collect_strings(_json(NPC_DIR + fn), "text", passages)
	var keep: float = game._text_scale
	for opt in game.TEXT_SCALES:
		game._text_scale = float(opt[1])
		game._apply_text_scale()
		var min_view := 99999
		for d in descs:
			game._desc_lbl.text = d
			if not game._layout_explore():
				_err("text size '%s': room description is clipped: %s…" % [opt[0], str(d).left(60)])
			min_view = mini(min_view, int(game._bg_rect.size.y))
		var max_panel := 0
		var scrolling := 0
		# (a paging engine has no scroller; _audit_dialog_paging covers it)
		for t in (passages if "_dialog_scroll" in game else []):
			game._dialog_text.text = t
			if not game._layout_dialog():
				scrolling += 1
				if float(opt[1]) <= game.TEXT_SCALE_DEFAULT:
					_err("text size '%s': dialog passage needs scrolling at a default-or-smaller size: %s…" % [opt[0], str(t).left(60)])
			max_panel = maxi(max_panel, int(game._dialog_panel.size.y))
			if game._dialog_panel.position.y < 0 or game._dialog_panel.position.y + game._dialog_panel.size.y > 1080:
				_err("text size '%s': dialog panel leaves the canvas: %s…" % [opt[0], str(t).left(60)])
		_note("text size %-11s  smallest plate %4dpx   tallest dialog panel %4dpx   passages that scroll %d" % [opt[0], min_view, max_panel, scrolling])
	game._text_scale = keep
	game._apply_text_scale()
	_note("text sizes: %d room descriptions x %d dialog passages x %d sizes fit" % [descs.size(), passages.size(), game.TEXT_SCALES.size()])


## Every action must stay on screen and clickable at every Text Size. Renders a
## real frame for every room of every chapter at every size, then checks each
## action-bar button against the canvas edge and the status strip. The height
## audit above cannot see this: a row of actions that runs off the right edge
## leaves Load / Settings / Menu unreachable while every height still "fits".
func _audit_action_bar_fit() -> void:
	if game == null:
		return
	var keep: float = game._text_scale
	var checked := 0
	var max_rows := 1
	for ch in chapters:
		var cid := str(ch.get("id", ""))
		game._start_chapter(cid)
		await get_tree().process_frame
		game._go_explore()
		for rid in game._world.rooms:
			GameState.current_room = str(rid)
			for opt in game.TEXT_SCALES:
				game._text_scale = float(opt[1])
				game._apply_text_scale()
				game._refresh_room()
				await get_tree().process_frame
				checked += 1
				var bar: Control = game._button_bar
				var rows := {}
				for b in bar.get_children():
					if not (b is Button) or b.is_queued_for_deletion() or not b.visible:
						continue
					var r: Rect2 = (b as Control).get_global_rect()
					rows[int(r.position.y)] = true
					if r.end.x > game.VIEW_X + game.VIEW_W + 1 or r.end.y > game.STATUS_Y + 1:
						_err("%s/%s at '%s': action '%s' is off screen (ends at %d,%d)" % [cid, rid, opt[0], (b as Button).text, int(r.end.x), int(r.end.y)])
				max_rows = maxi(max_rows, rows.size())
		game._go_chapters()
		await get_tree().process_frame
	game._text_scale = keep
	game._apply_text_scale()
	_note("action bar: %d room x size layouts rendered, every action on screen (up to %d rows)" % [checked, max_rows])


## Engines that PAGE long passages behind a "Next" button instead of scrolling
## them: every page of every node, at every Text Size, is rendered for real and
## its caption bar must stay on screen with every button below the text and
## above the bottom edge. (Scrolling engines are covered by the audits above.)
func _audit_dialog_paging() -> void:
	if game == null or not game.has_method("_render_dialog_page"):
		return
	var keep: float = game._text_scale
	var pages_checked := 0
	var max_pages := 1
	for fn in DirAccess.get_files_at(NPC_DIR):
		if not fn.ends_with(".json"):
			continue
		var npc: String = fn.get_basename()
		var d = _json(NPC_DIR + fn)
		if d == null:
			continue
		for opt in game.TEXT_SCALES:
			game._text_scale = float(opt[1])
			game._apply_text_scale()
			game._go_dialog(npc)
			await get_tree().process_frame
			for nid in (d.get("nodes", {}) as Dictionary):
				game._dialog._current = str(nid)
				if game.has_method("_apply_dialog_mode"):
					game._apply_dialog_mode(game._dialog.current_ui_mode())
				game._dialog_page = 0
				game._render_dialog_page()
				var n_pages: int = int(game._dialog_pages)
				max_pages = maxi(max_pages, n_pages)
				for pg in n_pages:
					game._dialog_page = pg
					game._render_dialog_page()
					await get_tree().process_frame
					pages_checked += 1
					var panel: Rect2 = game._dialog_panel.get_global_rect()
					var text: Rect2 = game._dialog_text.get_global_rect()
					# A paging engine keeps its choices on screen by shrinking the text
					# box, so an overfilled page shows up as lines silently cut off.
					var label: Label = game._dialog_text
					var want: int = label.get_line_count() - label.lines_skipped
					if label.max_lines_visible >= 0:
						want = mini(want, label.max_lines_visible)
					if label.get_visible_line_count() < want:
						_err("%s/%s page %d at '%s': text clipped — %d of %d lines visible" % [npc, nid, pg + 1, opt[0], label.get_visible_line_count(), want])
					if panel.position.y < -1 or panel.end.y > 1081:
						_err("%s/%s page %d at '%s': caption bar leaves the screen" % [npc, nid, pg + 1, opt[0]])
					for b in game._dialog_options.get_children():
						if not (b is Button) or b.is_queued_for_deletion():
							continue
						var r: Rect2 = (b as Control).get_global_rect()
						if r.end.y > 1081:
							_err("%s/%s page %d at '%s': button '%s' is below the screen" % [npc, nid, pg + 1, opt[0], (b as Button).text.left(30)])
						elif r.position.y < text.end.y - 1:
							_err("%s/%s page %d at '%s': button '%s' covers the text" % [npc, nid, pg + 1, opt[0], (b as Button).text.left(30)])
			game._end_dialog()
			await get_tree().process_frame
	game._text_scale = keep
	game._apply_text_scale()
	_note("dialog paging: %d pages rendered across every size, all on screen (up to %d pages a node)" % [pages_checked, max_pages])


## A passage too tall for the screen must really scroll: send the dialog actual
## mouse-wheel events and check the reader can reach the end, that the "more
## below" cue clears once they have, and that the next passage starts at the top.
func _audit_dialog_scroll() -> void:
	if game == null or not ("_dialog_scroll" in game):
		return
	var keep: float = game._text_scale
	game._text_scale = float(game.TEXT_SCALES[-1][1])
	game._apply_text_scale()
	var probe := ""
	for i in 60:
		probe += "Line %d of a passage far too tall for any screen.\n\n" % i
	game._dialog_text.text = probe
	if game._layout_dialog():
		_err("dialog scroll: an over-tall passage was reported as fitting")
	game._dialog_layer.visible = true
	await get_tree().process_frame
	await get_tree().process_frame
	var sc: ScrollContainer = game._dialog_scroll
	var bar := sc.get_v_scroll_bar()
	if not game._dialog_more.visible:
		_err("dialog scroll: no 'more below' cue on a passage that scrolls")
	# push_input takes window coordinates; the canvas is stretched into the window
	var pt: Vector2 = get_viewport().get_final_transform() * (sc.global_position + sc.size * 0.5)
	var guard := 0
	while sc.scroll_vertical < int(bar.max_value - bar.page) and guard < 400:
		guard += 1
		for pressed in [true, false]:
			var ev := InputEventMouseButton.new()
			ev.button_index = MOUSE_BUTTON_WHEEL_DOWN
			ev.pressed = pressed
			ev.position = pt
			ev.global_position = pt
			ev.factor = 1.0
			get_viewport().push_input(ev)
		await get_tree().process_frame
	if sc.scroll_vertical < int(bar.max_value - bar.page):
		_err("dialog scroll: mouse wheel stalled at %d of %d" % [sc.scroll_vertical, int(bar.max_value - bar.page)])
	elif game._dialog_more.visible:
		_err("dialog scroll: 'more below' cue still showing at the end of the passage")
	else:
		_note("dialog scroll: wheel reached the end of an over-tall passage in %d notches; cue cleared" % guard)
	game._dialog_text.text = "Short."
	game._layout_dialog()
	if sc.scroll_vertical != 0 or game._dialog_more.visible:
		_err("dialog scroll: the next passage did not reset to the top")
	game._dialog_layer.visible = false
	game._text_scale = keep
	game._apply_text_scale()


## Every chapter intro/outro story card must carry a plate that actually loads:
## a card with no art renders as a bare text panel, and nothing else notices.
func _audit_story_art() -> void:
	var cards := 0
	for ch in chapters:
		for pair in [["intro", "intro_art"], ["outro", "outro_art"]]:
			var pages: Array = ch.get(pair[0], [])
			var art: Array = ch.get(pair[1], [])
			# An art-light game (no plates yet) legitimately has art-less cards.
			if art.is_empty() and not _chapter_has_plates(ch):
				continue
			# A shorter list is fine — the engine holds the last plate for the
			# remaining cards. What must not happen is a card with no plate at all.
			if art.is_empty() and not pages.is_empty():
				_err("%s: %d %s cards but no %s plate" % [ch.get("id", "?"), pages.size(), pair[0], pair[1]])
			for path in art:
				cards += 1
				if Assets.load_texture(str(path)) == null:
					_err("%s: %s plate does not load: %s" % [ch.get("id", "?"), pair[1], path])
	_note("story cards: %d intro/outro cards carry a loadable plate" % cards)


func _chapter_has_plates(ch: Dictionary) -> bool:
	var d = _json(str(ch.get("rooms", "")))
	if d == null:
		return false
	for rid in (d.get("rooms", {}) as Dictionary):
		if Assets.background(str(d["rooms"][rid].get("bg", ""))) != null:
			return true
	return false


func _collect_strings(node, key: String, out: Array) -> void:
	if node is Dictionary:
		for k in node:
			if k == key and node[k] is String and node[k] != "":
				out.append(node[k])
			else:
				_collect_strings(node[k], key, out)
	elif node is Array:
		for v in node:
			_collect_strings(v, key, out)


func _audit_soundtrack() -> void:
	# Empirical: the drive walked every room and concluded every chapter, so any
	# cue that never fired is unreachable in normal play.
	var tracks := {}
	for fn in DirAccess.get_files_at(MUSIC_DIR):
		# exported games list "<name>.ogg.import"; source trees list "<name>.ogg"
		var base := str(fn).trim_suffix(".import")
		if base.ends_with(".ogg"):
			tracks[base.trim_suffix(".ogg")] = true
	if tracks.is_empty():
		_note("soundtrack: no music shipped yet (asset-light)")
	for t in tracks:
		if cues_played.has(t):
			_note("cue '%s' PLAYED during the drive" % t)
		else:
			# Not an error here: a combat or cyberspace cue only fires inside a
			# system this drive may not enter. A game can tighten this to _err.
			_note("cue '%s' shipped but never played during the drive" % t)


# ------------------------------------------------------------------------ helpers
func _json(path: String):
	if not FileAccess.file_exists(path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))


func _dict_of(path: String, key: String) -> Dictionary:
	var d = _json(path)
	return (d.get(key, {}) if d != null else {})


func _list_of(path: String, key: String) -> Array:
	var d = _json(path)
	return (d.get(key, []) if d != null else [])


func _err(m: String) -> void:
	errors.append(m)


func _note(m: String) -> void:
	notes.append(m)


func _report() -> void:
	print("\n===== PLAYTEST REPORT =====")
	print("-- notes --")
	for n in notes:
		print("  · " + n)
	if errors.is_empty():
		print("-- errors -- none")
		print("\nPLAYTEST: PASS  (%d rooms walked, %d conversations driven)"
			% [rooms_seen, dialogs_driven])
		_restore_user_dir()
		get_tree().quit(0)
	else:
		print("-- errors (%d) --" % errors.size())
		for e in errors:
			printerr("  ! " + e)
		printerr("\nPLAYTEST: FAIL — %d error(s)" % errors.size())
		_restore_user_dir()
		get_tree().quit(1)


# ------------------------------------------------------------ user-data guard
func _snapshot_user_dir(dir: String = "user://") -> void:
	for f in DirAccess.get_files_at(dir):
		_user_snapshot[dir.path_join(f)] = FileAccess.get_file_as_bytes(dir.path_join(f))
	for sub_dir in DirAccess.get_directories_at(dir):
		if not USER_SKIP.has(sub_dir):
			_snapshot_user_dir(dir.path_join(sub_dir))


## Delete what the run created, rewrite what it changed. Idempotent.
func _restore_user_dir() -> void:
	if _user_restored:
		return
	_user_restored = true
	_remove_new_files("user://")
	for path in _user_snapshot:
		var before: PackedByteArray = _user_snapshot[path]
		if FileAccess.file_exists(path) and FileAccess.get_file_as_bytes(path) == before:
			continue
		DirAccess.make_dir_recursive_absolute(str(path).get_base_dir())
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f != null:
			f.store_buffer(before)
			f.close()


func _remove_new_files(dir: String) -> void:
	for f in DirAccess.get_files_at(dir):
		var path := dir.path_join(f)
		if not _user_snapshot.has(path):
			DirAccess.remove_absolute(path)
	for sub_dir in DirAccess.get_directories_at(dir):
		if not USER_SKIP.has(sub_dir):
			_remove_new_files(dir.path_join(sub_dir))


func _exit_tree() -> void:
	_restore_user_dir()   # also on an early quit
