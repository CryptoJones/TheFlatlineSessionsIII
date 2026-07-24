extends SceneTree
## Reports story-density metrics for the twelve-chapter campaign.

func _initialize() -> void:
	var chapters = _json("res://data/chapters.json")
	var quests = _json("res://data/quests.json")
	var total_words := 0
	var total_steps := 0
	var total_interactions := 0
	var total_pages := 0
	for ch in chapters.get("chapters", []):
		var cid := str(ch.get("id", ""))
		var words := _words(" ".join(ch.get("intro", []))) + _words(" ".join(ch.get("outro", [])))
		var qid := str(ch.get("quest", ""))
		var steps: Array = quests.get("quests", {}).get(qid, {}).get("steps", [])
		var rooms = _json(str(ch.get("rooms", "")))
		var interactions := 0
		var pages := 0
		for room in rooms.get("rooms", {}).values():
			words += _words(str(room.get("desc", "")))
			for interaction in room.get("interactions", []):
				interactions += 1
				pages += (interaction.get("pages", []) as Array).size()
				words += _words(" ".join(interaction.get("pages", [])))
			for npc in room.get("npcs", []):
				var dialog = _json("res://data/npcs/%s.json" % str(npc))
				for node in dialog.get("nodes", {}).values():
					words += _words(str(node.get("text", "")))
					words += _words(" ".join(node.get("random_text", [])))
		print("CONTENT: %s  steps=%d interactions=%d pages=%d visible_words=%d" % [
			cid, steps.size(), interactions, pages, words])
		total_steps += steps.size()
		total_interactions += interactions
		total_pages += pages
		total_words += words
	print("CONTENT: TOTAL steps=%d interactions=%d pages=%d visible_words=%d" % [
		total_steps, total_interactions, total_pages, total_words])
	quit(0)

func _words(value: String) -> int:
	return value.strip_edges().split(" ", false).size()

func _json(path: String) -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}
