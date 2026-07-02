extends RefCounted
## Quests — flag-driven quest/objective tracking (data/quests.json).
##
## A quest is an ordered list of steps; each step is satisfied by one story
## flag. Flags get set by dialog nodes (set_flag), room entry (on_enter_flag),
## item grants (granted_<item>), and cracked databases (cracked_<db id>) — so
## quests need no logic of their own, just the right flag names. Pure data.
##
## quests.json shape:
## { "quests": { "q01_...": {
##     "name": "...", "desc": "one-line goal for the log",
##     "steps": [ { "text": "objective line", "flag": "flag_that_completes_it" }, ... ]
## } } }

const QUESTS_PATH := "res://data/quests.json"

var quests: Dictionary = {}

func load_data() -> bool:
	if not FileAccess.file_exists(QUESTS_PATH):
		push_warning("Quests: missing %s" % QUESTS_PATH)
		return false
	var d = JSON.parse_string(FileAccess.get_file_as_string(QUESTS_PATH))
	if typeof(d) != TYPE_DICTIONARY or not d.has("quests"):
		push_warning("Quests: bad %s" % QUESTS_PATH)
		return false
	quests = d["quests"]
	return true

func quest(id: String) -> Dictionary:
	return quests.get(id, {})

func quest_name(id: String) -> String:
	return str(quest(id).get("name", id))

func steps(id: String) -> Array:
	return quest(id).get("steps", [])

func step_done(state, step: Dictionary) -> bool:
	return state.has_flag(str(step.get("flag", "")))

## Index of the first unfinished step, or step count when all are done.
func current_step(state, id: String) -> int:
	var ss := steps(id)
	for i in ss.size():
		if not step_done(state, ss[i]):
			return i
	return ss.size()

func is_complete(state, id: String) -> bool:
	var ss := steps(id)
	return not ss.is_empty() and current_step(state, id) >= ss.size()

## One-line objective for the HUD: the current step's text (or done-message).
func objective(state, id: String) -> String:
	var ss := steps(id)
	if ss.is_empty():
		return ""
	var i := current_step(state, id)
	if i >= ss.size():
		return "Chapter goal complete."
	return str(ss[i].get("text", ""))
