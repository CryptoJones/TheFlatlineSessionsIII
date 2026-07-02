extends RefCounted
## Chapters — the sequels' PoV/chapter spine (data/chapters.json).
##
## The novels jump between point-of-view characters, so the game does too: each
## chapter is one PoV slice with its own room graph, quest, starting kit, and
## intro/outro story pages. Chapters unlock in order; finishing one unlocks the
## next. Pure data/logic — the UI reads these and drives Game.gd states.
##
## chapters.json shape:
## {
##   "game": "display name",
##   "chapters": [ {
##     "id": "ch01", "title": "...", "pov": "turner", "pov_name": "Turner",
##     "pov_desc": "one-liner for the select screen",
##     "rooms": "res://data/rooms/ch01_turner.json",
##     "quest": "q01_...",                 # main quest id in data/quests.json
##     "intro": ["page", ...], "outro": ["page", ...],
##     "start": { "credits": 0, "items": [], "software": {}, "skills": {},
##                "flags": [], "minutes": 480 }
##   }, ... ]
## }

const CHAPTERS_PATH := "res://data/chapters.json"

var game_title: String = ""
var chapters: Array = []

func load_data() -> bool:
	if not FileAccess.file_exists(CHAPTERS_PATH):
		push_warning("Chapters: missing %s" % CHAPTERS_PATH)
		return false
	var d = JSON.parse_string(FileAccess.get_file_as_string(CHAPTERS_PATH))
	if typeof(d) != TYPE_DICTIONARY or not d.has("chapters"):
		push_warning("Chapters: bad %s" % CHAPTERS_PATH)
		return false
	game_title = str(d.get("game", ""))
	chapters = d["chapters"]
	return not chapters.is_empty()

func count() -> int:
	return chapters.size()

func at(index: int) -> Dictionary:
	if index < 0 or index >= chapters.size():
		return {}
	return chapters[index]

func by_id(id: String) -> Dictionary:
	for c in chapters:
		if str(c.get("id", "")) == id:
			return c
	return {}

func index_of(id: String) -> int:
	for i in chapters.size():
		if str(chapters[i].get("id", "")) == id:
			return i
	return -1

## A chapter is playable once every chapter before it is done.
func is_unlocked(state, id: String) -> bool:
	var idx := index_of(id)
	if idx < 0:
		return false
	for i in idx:
		if not state.chapters_done.has(str(chapters[i].get("id", ""))):
			return false
	return true

func is_done(state, id: String) -> bool:
	return state.chapters_done.has(id)

## Apply a chapter's starting kit to a fresh GameState (call after reset()).
func begin(state, id: String) -> bool:
	var c := by_id(id)
	if c.is_empty():
		return false
	var start: Dictionary = c.get("start", {})
	state.current_chapter = id
	state.player_name = str(c.get("pov_name", "?"))
	state.credits = int(start.get("credits", 0))
	state.game_minutes = int(start.get("minutes", 480))
	for it in start.get("items", []):
		if not state.inventory.has(str(it)):
			state.inventory.append(str(it))
	var sw: Dictionary = start.get("software", {})
	for sid in sw:
		state.software[sid] = { "rating": int(sw[sid]) }
	var sk: Dictionary = start.get("skills", {})
	for s in sk:
		state.skills[s] = int(sk[s])
	for f in start.get("flags", []):
		state.set_flag(str(f))
	return true

## Mark a chapter finished (idempotent).
func finish(state, id: String) -> void:
	if not state.chapters_done.has(id):
		state.chapters_done.append(id)
