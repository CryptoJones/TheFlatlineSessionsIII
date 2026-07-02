extends Node
## GameState — canonical, save-serializable world state (autoload singleton).
##
## Same single-serialization-point design as the original engine, extended for
## the sequels' chapter/PoV structure: the player IS the current chapter's PoV
## character, and progress is tracked per chapter plus a global flag pool.

# --- PoV character (set by the active chapter) ---
var player_name: String = ""
var credits: int = 0
var health: int = 100
var constitution: int = 1000         # matrix-run stamina for deck chapters

# --- Inventory & skills ---
var inventory: Array[String] = []
var skills: Dictionary = {}          # skill_name -> level (int)
var software: Dictionary = {}        # warez id -> { "rating": int }

# --- Story / chapters ---
var current_chapter: String = ""     # chapter id from data/chapters.json
var chapters_done: Array = []        # chapter ids completed
var current_room: String = ""
var story_flags: Dictionary = {}     # flag_name -> bool/int
var game_minutes: int = 0            # in-world clock

func reset() -> void:
	player_name = ""
	credits = 0
	health = 100
	constitution = 1000
	inventory.clear()
	skills.clear()
	software.clear()
	current_chapter = ""
	current_room = ""
	story_flags.clear()
	game_minutes = 0
	# NOTE: chapters_done intentionally survives reset() — finishing a chapter
	# unlocks the next across "new chapter" starts. full_reset() wipes it too.

func full_reset() -> void:
	reset()
	chapters_done.clear()

func to_dict() -> Dictionary:
	return {
		"player_name": player_name,
		"credits": credits,
		"health": health,
		"constitution": constitution,
		"inventory": inventory.duplicate(),
		"skills": skills.duplicate(true),
		"software": software.duplicate(true),
		"current_chapter": current_chapter,
		"chapters_done": chapters_done.duplicate(),
		"current_room": current_room,
		"story_flags": story_flags.duplicate(true),
		"game_minutes": game_minutes,
	}

func from_dict(d: Dictionary) -> void:
	full_reset()
	for key in d:
		if not (key in self):
			continue
		var cur = get(key)
		if cur is Array:
			# set() can't put an untyped JSON array into a typed field like
			# inventory: Array[String]; .assign() coerces the elements instead.
			(cur as Array).assign(d[key] if d[key] is Array else [])
		else:
			set(key, d[key])

## Convenience used by dialog/quest hooks.
func set_flag(flag: String) -> void:
	if flag != "":
		story_flags[flag] = true

func has_flag(flag: String) -> bool:
	return bool(story_flags.get(flag, false))
