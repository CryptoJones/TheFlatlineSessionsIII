extends Control
## Game — the chapter-based adventure loop for the Flatline Sessions sequels.
##
## Boot is an empty Control named "Main" with this script; every widget is built
## in code on a native 1920x1080 canvas in full 32-bit color (modern look: flat
## panels, rounded corners, one neon accent — see src/ui/UITheme.gd). Flow:
##   TITLE -> CHAPTER SELECT -> (intro pages) -> EXPLORE <-> DIALOG / MENU
## Each chapter locks the player to one of the novel's PoV characters and ends
## when its main quest completes (outro pages, next chapter unlocks).

enum State { TITLE, CHAPTERS, EXPLORE, DIALOG, MENU }

# Preloaded (not class_name globals) so the game runs without a prebuilt
# .godot global-class cache — i.e. on a fresh checkout before any editor open.
const World = preload("res://src/world/World.gd")
const DialogEngine = preload("res://src/world/DialogEngine.gd")
const SaveSystem = preload("res://src/core/SaveSystem.gd")
const Catalog = preload("res://src/econ/Catalog.gd")
const Matrix = preload("res://src/cyber/Matrix.gd")
const Chapters = preload("res://src/story/Chapters.gd")
const Quests = preload("res://src/story/Quests.gd")
const UITheme = preload("res://src/ui/UITheme.gd")

const NPC_DIR := "res://data/npcs/"
const TITLE_COVER := "res://assets/ui/cover.png"
const VIEW_X := 36
const VIEW_Y := 30
const VIEW_W := 1848
const VIEW_H := 636
const MINUTES_PER_MOVE := 3

var _state: int = State.TITLE
var _world: World
var _dialog: DialogEngine
var _dialog_npc: String = ""
var _chapters: Chapters
var _quests: Quests
var _catalog: Catalog
var _matrix: Matrix

# Layers
var _title_layer: Control
var _chapters_layer: Control
var _explore_layer: Control
var _dialog_layer: Control
var _menu_layer: Control

# Chapter-select widgets
var _chapters_list: VBoxContainer
var _chapters_scroll: ScrollContainer

# Menu (shop / net / cyberspace / saves / quest log) widgets
var _menu_title: Label
var _menu_info: Label
var _menu_list: VBoxContainer
var _menu_img: TextureRect
var _menu_scroll: ScrollContainer
var _combat_db: String = ""           # database id currently under ICE attack
var _combat_ice: int = 0              # remaining ICE strength this run

# Explore widgets
var _bg_rect: TextureRect
var _bg_placeholder: ColorRect
var _bg_room_glyph: Label
var _room_name_lbl: Label
var _desc_lbl: Label
var _status_lbl: Label
var _objective_lbl: Label
var _toast_lbl: Label
var _button_bar: HBoxContainer

# Dialog widgets
var _dialog_name: Label
var _dialog_text: Label
var _dialog_options: VBoxContainer

var _save_name_edit: LineEdit
# Story-pager: long narrative one beat at a time with a Next button.
var _story_pages: Array = []
var _story_idx := 0
var _story_title := ""
var _story_art := ""
var _story_final: Array = []   # [[label, Callable], ...] shown on the last page


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UITheme.build()
	_chapters = Chapters.new()
	if not _chapters.load_data():
		push_error("Game: failed to load data/chapters.json")
	_quests = Quests.new()
	_quests.load_data()
	_world = World.new()
	_catalog = Catalog.new()
	_catalog.load_data()
	_matrix = Matrix.new()
	_matrix.load_data()
	_build_title_layer()
	_build_chapters_layer()
	_build_explore_layer()
	_build_dialog_layer()
	_build_menu_layer()
	_go_title()


# ---------------------------------------------------------------- layer builders

func _full_control(name: String) -> Control:
	var c := Control.new()
	c.name = name
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(c)
	return c

func _fsize(node: Control, size: int) -> void:
	node.add_theme_font_size_override("font_size", size)

func _build_title_layer() -> void:
	_title_layer = _full_control("Title")
	var bg := ColorRect.new()
	bg.color = UITheme.BG
	bg.size = Vector2(1920, 1080)
	_title_layer.add_child(bg)
	# Cover art renders clean and full-res when present (art comes later).
	var tex: Texture2D = Assets.load_texture(TITLE_COVER)
	if tex != null:
		var tr := TextureRect.new()
		tr.texture = tex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tr.clip_contents = true
		tr.size = Vector2(1920, 1080)
		_title_layer.add_child(tr)
	else:
		var series := Label.new()
		series.text = "THE FLATLINE SESSIONS"
		series.position = Vector2(0, 288)
		series.size = Vector2(1920, 72)
		series.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		series.add_theme_color_override("font_color", UITheme.TEXT_DIM)
		_fsize(series, 30)
		_title_layer.add_child(series)
		var t := Label.new()
		t.text = _chapters.game_title if _chapters.game_title != "" else "II"
		t.position = Vector2(0, 384)
		t.size = Vector2(1920, 180)
		t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		t.add_theme_color_override("font_color", UITheme.ACCENT)
		_fsize(t, 64)
		_title_layer.add_child(t)
		var rule := ColorRect.new()
		rule.color = UITheme.ACCENT_DIM
		rule.position = Vector2(600, 588)
		rule.size = Vector2(720, 6)
		_title_layer.add_child(rule)
	var prompt := Label.new()
	prompt.text = "PRESS ANY KEY"
	prompt.position = Vector2(0, 876)
	prompt.size = Vector2(1920, 90)
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	prompt.add_theme_color_override("font_color", UITheme.TEXT)
	prompt.add_theme_color_override("font_outline_color", UITheme.BG)
	prompt.add_theme_constant_override("outline_size", 10)
	_fsize(prompt, 30)
	_title_layer.add_child(prompt)
	var blink := create_tween().set_loops()
	blink.tween_property(prompt, "modulate:a", 0.15, 0.7).set_trans(Tween.TRANS_SINE)
	blink.tween_property(prompt, "modulate:a", 1.0, 0.7).set_trans(Tween.TRANS_SINE)
	var ver := Label.new()
	ver.text = "v" + str(ProjectSettings.get_setting("application/config/version", ""))
	ver.position = Vector2(0, 1014)
	ver.size = Vector2(1896, 48)
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ver.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	_fsize(ver, 20)
	_title_layer.add_child(ver)

func _build_chapters_layer() -> void:
	_chapters_layer = _full_control("ChapterSelect")
	_chapters_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = UITheme.BG
	bg.size = Vector2(1920, 1080)
	_chapters_layer.add_child(bg)
	var head := Label.new()
	head.text = _chapters.game_title
	head.position = Vector2(72, 42)
	head.size = Vector2(1776, 72)
	head.add_theme_color_override("font_color", UITheme.ACCENT)
	_fsize(head, 36)
	_chapters_layer.add_child(head)
	var sub := Label.new()
	sub.text = "CHAPTERS — the story passes between its players. Finish one to unlock the next."
	sub.position = Vector2(72, 120)
	sub.size = Vector2(1776, 48)
	sub.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	_fsize(sub, 20)
	_chapters_layer.add_child(sub)
	_chapters_scroll = ScrollContainer.new()
	_chapters_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_chapters_scroll.position = Vector2(72, 186)
	_chapters_scroll.size = Vector2(1776, 774)
	_chapters_layer.add_child(_chapters_scroll)
	_chapters_list = VBoxContainer.new()
	_chapters_list.custom_minimum_size = Vector2(1722, 0)
	_chapters_list.add_theme_constant_override("separation", 10)
	_chapters_scroll.add_child(_chapters_list)
	var foot := HBoxContainer.new()
	foot.position = Vector2(72, 984)
	foot.size = Vector2(1776, 72)
	foot.add_theme_constant_override("separation", 16)
	_chapters_layer.add_child(foot)
	var loadb := Button.new()
	loadb.text = "Load game"
	loadb.pressed.connect(_open_load_menu)
	foot.add_child(loadb)
	var quitb := Button.new()
	quitb.text = "Quit"
	quitb.pressed.connect(_do_quit)
	foot.add_child(quitb)

func _refresh_chapters_list() -> void:
	for c in _chapters_list.get_children():
		c.queue_free()
	for i in _chapters.count():
		var ch: Dictionary = _chapters.at(i)
		var id := str(ch.get("id", ""))
		var done := _chapters.is_done(GameState, id)
		var unlocked := _chapters.is_unlocked(GameState, id)
		var mark := "✓" if done else ("▸" if unlocked else "·")
		var label := "%s  %02d — %s        [%s]" % [mark, i + 1, str(ch.get("title", "")), str(ch.get("pov_name", ""))]
		if unlocked:
			var b := Button.new()
			b.text = label + ("    (replay)" if done else "")
			b.tooltip_text = str(ch.get("pov_desc", ""))
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.custom_minimum_size = Vector2(1722, 0)
			b.pressed.connect(_start_chapter.bind(id))
			_chapters_list.add_child(b)
		else:
			var l := Label.new()
			l.text = label + "    — locked"
			l.custom_minimum_size = Vector2(1722, 0)
			l.add_theme_color_override("font_color", Color(UITheme.TEXT_DIM, 0.6))
			_chapters_list.add_child(l)

func _build_explore_layer() -> void:
	_explore_layer = _full_control("Explore")
	_explore_layer.mouse_filter = Control.MOUSE_FILTER_PASS
	var screen := ColorRect.new()
	screen.color = UITheme.BG
	screen.size = Vector2(1920, 1080)
	_explore_layer.add_child(screen)
	# Scene view: a clean framed plate (or a hue-keyed placeholder until art lands).
	var frame := Panel.new()
	frame.position = Vector2(VIEW_X - 6, VIEW_Y - 6)
	frame.size = Vector2(VIEW_W + 12, VIEW_H + 12)
	_explore_layer.add_child(frame)
	_bg_placeholder = ColorRect.new()
	_bg_placeholder.color = Color("141a28")
	_bg_placeholder.position = Vector2(VIEW_X, VIEW_Y)
	_bg_placeholder.size = Vector2(VIEW_W, VIEW_H)
	_explore_layer.add_child(_bg_placeholder)
	_bg_room_glyph = Label.new()
	_bg_room_glyph.position = Vector2(VIEW_X, VIEW_Y + 240)
	_bg_room_glyph.size = Vector2(VIEW_W, 156)
	_bg_room_glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bg_room_glyph.add_theme_color_override("font_color", Color(1, 1, 1, 0.08))
	_fsize(_bg_room_glyph, 84)
	_explore_layer.add_child(_bg_room_glyph)
	_bg_rect = TextureRect.new()
	_bg_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bg_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_bg_rect.clip_contents = true
	# LINEAR filter: the sequels render plates clean at full res (no retro crush).
	_bg_rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_bg_rect.position = Vector2(VIEW_X, VIEW_Y)
	_bg_rect.size = Vector2(VIEW_W, VIEW_H)
	_explore_layer.add_child(_bg_rect)
	_room_name_lbl = Label.new()
	_room_name_lbl.position = Vector2(VIEW_X, 690)
	_room_name_lbl.size = Vector2(VIEW_W, 60)
	_room_name_lbl.add_theme_color_override("font_color", UITheme.ACCENT)
	_fsize(_room_name_lbl, 30)
	_explore_layer.add_child(_room_name_lbl)
	_desc_lbl = Label.new()
	_desc_lbl.position = Vector2(VIEW_X, 756)
	_desc_lbl.size = Vector2(VIEW_W, 162)
	_desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc_lbl.add_theme_color_override("font_color", UITheme.TEXT)
	_fsize(_desc_lbl, 22)
	_explore_layer.add_child(_desc_lbl)
	_button_bar = HBoxContainer.new()
	_button_bar.position = Vector2(VIEW_X, 924)
	_button_bar.size = Vector2(VIEW_W, 72)
	_button_bar.add_theme_constant_override("separation", 12)
	_explore_layer.add_child(_button_bar)
	# Status strip.
	var status_bg := ColorRect.new()
	status_bg.color = Color("0d1118")
	status_bg.position = Vector2(0, 1014)
	status_bg.size = Vector2(1920, 66)
	_explore_layer.add_child(status_bg)
	_status_lbl = Label.new()
	_status_lbl.position = Vector2(36, 1020)
	_status_lbl.size = Vector2(1080, 54)
	_status_lbl.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	_fsize(_status_lbl, 20)
	_explore_layer.add_child(_status_lbl)
	_objective_lbl = Label.new()
	_objective_lbl.position = Vector2(1128, 1020)
	_objective_lbl.size = Vector2(756, 54)
	_objective_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_objective_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_objective_lbl.add_theme_color_override("font_color", UITheme.ACCENT)
	_fsize(_objective_lbl, 20)
	_explore_layer.add_child(_objective_lbl)
	_toast_lbl = Label.new()
	_toast_lbl.position = Vector2(VIEW_X, 300)
	_toast_lbl.size = Vector2(VIEW_W, 72)
	_toast_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_lbl.add_theme_color_override("font_color", UITheme.ACCENT)
	_toast_lbl.add_theme_color_override("font_outline_color", UITheme.BG)
	_toast_lbl.add_theme_constant_override("outline_size", 10)
	_fsize(_toast_lbl, 32)
	_toast_lbl.visible = false
	_explore_layer.add_child(_toast_lbl)

func _build_dialog_layer() -> void:
	_dialog_layer = _full_control("Dialog")
	_dialog_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	var panel := Panel.new()
	panel.position = Vector2(24, 684)
	panel.size = Vector2(1872, 378)
	_dialog_layer.add_child(panel)
	_dialog_name = Label.new()
	_dialog_name.position = Vector2(36, 18)
	_dialog_name.size = Vector2(1800, 48)
	_dialog_name.add_theme_color_override("font_color", UITheme.ACCENT)
	_fsize(_dialog_name, 24)
	panel.add_child(_dialog_name)
	_dialog_text = Label.new()
	_dialog_text.position = Vector2(36, 72)
	_dialog_text.size = Vector2(1800, 132)
	_dialog_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_dialog_text.add_theme_color_override("font_color", UITheme.TEXT)
	_fsize(_dialog_text, 24)
	panel.add_child(_dialog_text)
	_dialog_options = VBoxContainer.new()
	_dialog_options.position = Vector2(36, 210)
	_dialog_options.size = Vector2(1800, 156)
	_dialog_options.add_theme_constant_override("separation", 6)
	panel.add_child(_dialog_options)

func _build_menu_layer() -> void:
	# One reusable full-screen list panel: shops, net terminal, cyberspace,
	# saves, quest log, and the story pager all render through this.
	_menu_layer = _full_control("Menu")
	_menu_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	var panel := Panel.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_menu_layer.add_child(panel)
	_menu_img = TextureRect.new()
	_menu_img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_menu_img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_menu_img.clip_contents = true
	_menu_img.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_menu_img.position = Vector2(48, 36)
	_menu_img.size = Vector2(1824, 450)
	_menu_img.visible = false
	panel.add_child(_menu_img)
	_menu_title = Label.new()
	_menu_title.size = Vector2(1800, 66)
	_menu_title.add_theme_color_override("font_color", UITheme.ACCENT)
	_fsize(_menu_title, 32)
	panel.add_child(_menu_title)
	_menu_info = Label.new()
	_menu_info.size = Vector2(1800, 48)
	_menu_info.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	_fsize(_menu_info, 20)
	panel.add_child(_menu_info)
	_menu_scroll = ScrollContainer.new()
	_menu_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_menu_scroll.follow_focus = false
	panel.add_child(_menu_scroll)
	_menu_list = VBoxContainer.new()
	_menu_list.custom_minimum_size = Vector2(1770, 0)
	_menu_list.add_theme_constant_override("separation", 8)
	_menu_scroll.add_child(_menu_list)


# ---------------------------------------------------------------- menu plumbing

func _menu_begin(title: String, info: String, img_path := "", big_art := false) -> void:
	_state = State.MENU
	_show_only(_menu_layer)
	var art_h := 570 if big_art else 450
	if img_path != "":
		var t: Texture2D = Assets.load_texture(img_path)
		_menu_img.texture = t
		_menu_img.visible = t != null
	else:
		_menu_img.visible = false
	_menu_img.size = Vector2(1824, art_h)
	var top: int = (art_h + 60) if _menu_img.visible else 42
	_menu_title.position = Vector2(60, top)
	_menu_info.position = Vector2(60, top + 72)
	_menu_scroll.position = Vector2(60, top + 132)
	_menu_scroll.size = Vector2(1800, 1044 - (top + 132))
	_menu_title.text = title
	_menu_info.text = info
	for c in _menu_list.get_children():
		c.queue_free()
	_menu_scroll.set_deferred("scroll_vertical", 0)

func _menu_label(text: String, dim := false) -> void:
	var l := Label.new()
	l.text = text
	l.custom_minimum_size = Vector2(1758, 0)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_color", UITheme.TEXT_DIM if dim else UITheme.TEXT)
	_fsize(l, 22)
	_menu_list.add_child(l)

func _menu_button(text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(1758, 0)
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_fsize(b, 22)
	if cb.is_valid():
		b.pressed.connect(cb)
	else:
		b.disabled = true
	_menu_list.add_child(b)


# ---------------------------------------------------------------- shops

func _open_shop(shop_id: String, info: String) -> void:
	var shop: Dictionary = _catalog.shop(shop_id)
	_menu_begin(shop.get("name", "Shop"),
		info if info != "" else "Credits: %d" % GameState.credits)
	_menu_label("— FOR SALE —", true)
	for iid in shop.get("stock", []):
		var nm: String = _catalog.item_name(iid)
		var pr: int = _catalog.price(iid)
		if _catalog.owned(GameState, iid):
			_menu_button("[owned] %s" % nm, Callable())
		elif _catalog.can_buy(GameState, iid):
			_menu_button("Buy: %s — %d cr   · %s" % [nm, pr, _catalog.item(iid).get("desc", "")],
				_buy.bind(shop_id, iid))
		else:
			_menu_button("(need %d cr) %s" % [pr, nm], Callable())
	if shop.get("buys", false) and not GameState.inventory.is_empty():
		_menu_label("— SELL (half price) —", true)
		for iid in GameState.inventory:
			if _catalog.can_sell(GameState, iid):
				_menu_button("Sell: %s — +%d cr" % [_catalog.item_name(iid), _catalog.sell_value(iid)],
					_sell.bind(shop_id, iid))
	_menu_button("« Back", _go_explore)

func _buy(shop_id: String, iid: String) -> void:
	var nm: String = _catalog.item_name(iid)
	if _catalog.buy(GameState, iid):
		_check_quest()
		_open_shop(shop_id, "Bought %s.  Credits: %d" % [nm, GameState.credits])
	else:
		_open_shop(shop_id, "Can't afford %s." % nm)

func _sell(shop_id: String, iid: String) -> void:
	var nm: String = _catalog.item_name(iid)
	if _catalog.sell(GameState, iid):
		_open_shop(shop_id, "Sold %s.  Credits: %d" % [nm, GameState.credits])
	else:
		_open_shop(shop_id, "Can't sell that here.")


# ---------------------------------------------------------------- inventory / quest log

func _open_inventory() -> void:
	_menu_begin("%s — Gear" % GameState.player_name,
		"Credits: %d    HP: %d" % [GameState.credits, GameState.health])
	_menu_label("— ITEMS —", true)
	if GameState.inventory.is_empty():
		_menu_label("   (nothing yet)")
	else:
		for iid in GameState.inventory:
			var d: String = str(_catalog.item(iid).get("desc", ""))
			_menu_label("   %s%s" % [_catalog.item_name(iid), ("  ·  " + d) if d != "" else ""])
	if not GameState.software.is_empty():
		_menu_label("— SOFTWARE —", true)
		for sid in GameState.software:
			_menu_label("   %s  (rating %d)" % [_catalog.item_name(sid), int(GameState.software[sid].get("rating", 1))])
	if not GameState.skills.is_empty():
		_menu_label("— SKILLS —", true)
		for sk in GameState.skills:
			_menu_label("   %s  L%d" % [sk, int(GameState.skills[sk])])
	_menu_button("« Back", _go_explore)

func _open_quest_log() -> void:
	var ch := _current_chapter()
	var qid := str(ch.get("quest", ""))
	_menu_begin("Chapter %02d — %s" % [_chapters.index_of(GameState.current_chapter) + 1, str(ch.get("title", ""))],
		"Playing as %s — %s" % [str(ch.get("pov_name", "")), str(ch.get("pov_desc", ""))])
	if qid == "" or _quests.quest(qid).is_empty():
		_menu_label("(no quest data for this chapter)")
	else:
		_menu_label(_quests.quest_name(qid))
		_menu_label(str(_quests.quest(qid).get("desc", "")), true)
		_menu_label("")
		var steps := _quests.steps(qid)
		var cur := _quests.current_step(GameState, qid)
		for i in steps.size():
			var mark := "✓" if i < cur else ("▸" if i == cur else "·")
			_menu_label("  %s  %s" % [mark, str(steps[i].get("text", ""))],  i > cur)
	_menu_button("« Back", _go_explore)


# ---------------------------------------------------------------- NET terminal

func _open_net() -> void:
	var hh := int(GameState.game_minutes / 60.0) % 24
	var mm := GameState.game_minutes % 60
	_menu_begin("NET — public access",
		"Logged in: %s        %02d:%02d" % [GameState.player_name, hh, mm])
	_menu_button("News feeds", _open_net_news)
	_menu_button("Message boards", _open_net_messages)
	_menu_button("« Log off", _go_explore)

func _open_net_news() -> void:
	_menu_begin("NET — news", "")
	var d = _load_json("res://data/pax/news.json")
	var news: Array = d.get("news", []) if d != null else []
	for item in news:
		_menu_label(str(item.get("headline", "")))
		if str(item.get("body", "")) != "":
			_menu_label(str(item.get("body", "")), true)
	_menu_button("« Back", _open_net)

func _open_net_messages() -> void:
	_menu_begin("NET — boards", "")
	var d = _load_json("res://data/pax/bbs.json")
	var msgs: Array = d.get("messages", []) if d != null else []
	for m in msgs:
		_menu_label("TO: %s    FROM: %s" % [m.get("to", ""), m.get("from", "")])
		_menu_label(str(m.get("body", "")), true)
	_menu_button("« Back", _open_net)

## Load + parse a committed JSON data file (owned content; ships with the game).
func _load_json(path: String):
	if not FileAccess.file_exists(path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))


# ---------------------------------------------------------------- cyberspace

func _has_deck() -> bool:
	for iid in GameState.inventory:
		if _catalog.item(iid).get("type", "") == "hardware":
			return true
	return false

func _go_matrix() -> void:
	_open_matrix_nav("Jacking in...")

func _open_matrix_nav(info := "") -> void:
	AudioManager.play("cyberspace")
	_menu_begin("CYBERSPACE",
		info if info != "" else "CON %d    The grid unfolds beneath you." % GameState.constitution,
		_matrix.art("CYBER_grid"))
	_menu_label("Pick a target to run:")
	for d in _matrix.for_chapter(GameState.current_chapter):
		var did: String = d.get("id", "")
		var nm: String = d.get("name", "?")
		if d.has("requires") and not _matrix.is_cracked(GameState, str(d["requires"])):
			continue
		if d.has("requires_flag") and not GameState.has_flag(str(d["requires_flag"])):
			continue
		if _matrix.is_cracked(GameState, did):
			_menu_button("[cracked] %s" % nm, _open_db_access.bind(did, ""))
		else:
			var tag: String = "  (AI: %s)" % str(d.get("ai", "")) if d.has("ai") else ""
			_menu_button("Run: %s  —  ICE %d%s" % [nm, int(d.get("ice", 0)), tag],
				_approach_db.bind(did))
	_menu_button("« Jack out", _jack_out)

func _approach_db(id: String) -> void:
	var d: Dictionary = _matrix.db(id)
	_combat_db = id
	_combat_ice = int(d.get("ice", 0))
	_open_combat("You close on the %s. Its ICE flares awake." % str(d.get("name", "fortress")))

func _open_combat(info := "") -> void:
	AudioManager.play("ice_combat")
	var d: Dictionary = _matrix.db(_combat_db)
	_menu_begin(str(d.get("name", "ICE")), "ICE %d        CON %d" % [_combat_ice, GameState.constitution],
		_matrix.art(str(d.get("bg", "CYBER_fortress"))))
	if info != "":
		_menu_label(info)
	_menu_button("Attack the ICE  (your software hits for %d)" % _matrix.player_attack(GameState), _combat_attack)
	_menu_button("« Break off and jack out", _jack_out)

func _combat_attack() -> void:
	var d: Dictionary = _matrix.db(_combat_db)
	var atk: int = _matrix.player_attack(GameState)
	var bite: int = _matrix.ice_bite(d)
	_combat_ice -= atk
	if _combat_ice <= 0:
		_db_break(_combat_db)
		return
	GameState.constitution -= bite
	if GameState.constitution <= 0:
		_flatline()
		return
	_open_combat("You hit for %d; the ICE bites back for %d." % [atk, bite])

func _db_break(id: String) -> void:
	GameState.story_flags["cracked_" + id] = true
	var d: Dictionary = _matrix.db(id)
	if d.has("set_flag"):
		GameState.set_flag(str(d["set_flag"]))
	_check_quest()
	_open_db_access(id, "ICE shattered. You're in.")

func _open_db_access(id: String, info := "") -> void:
	var d: Dictionary = _matrix.db(id)
	_menu_begin(str(d.get("name", "Database")),
		info if info != "" else "Cracked.    CON %d" % GameState.constitution,
		_matrix.art(str(d.get("bg", "CYBER_fortress"))))
	_menu_label(str(d.get("content", "")))
	_menu_button("« Back to the matrix", _open_matrix_nav)
	_menu_button("« Jack out", _jack_out)

func _flatline() -> void:
	GameState.constitution = 100   # thrown out hard, not a game over
	_combat_db = ""
	_menu_begin("FLATLINE", "The ICE put you down.", _matrix.art("CYBER_ice"))
	_menu_label("The ice closes over your icon and your heart stutters. You rip the trodes off just in time — slammed back into the meat, shaking, still breathing.")
	_menu_button("« Come to (jack out)", _jack_out)

func _jack_out() -> void:
	_combat_db = ""
	_go_explore()


# ---------------------------------------------------------------- story pager

## Present `pages` one beat at a time with a "Next »" button, then show the
## `final` choice buttons ([[label, Callable], ...]) on the last page.
func _begin_story(title: String, art: String, pages: Array, final: Array) -> void:
	_story_title = title
	_story_art = art
	_story_pages = pages if not pages.is_empty() else [""]
	_story_final = final
	_story_idx = 0
	_show_story_page()

func _show_story_page() -> void:
	_menu_begin(_story_title, "· %d / %d ·" % [_story_idx + 1, _story_pages.size()], _story_art, true)
	_menu_label(str(_story_pages[_story_idx]))
	if _story_idx < _story_pages.size() - 1:
		_menu_button("Next »", _story_next)
	else:
		for fb in _story_final:
			_menu_button(str(fb[0]), fb[1])

func _story_next() -> void:
	_story_idx += 1
	_show_story_page()


# ---------------------------------------------------------------- chapter flow

func _current_chapter() -> Dictionary:
	return _chapters.by_id(GameState.current_chapter)

func _start_chapter(id: String) -> void:
	var ch := _chapters.by_id(id)
	if ch.is_empty():
		return
	GameState.reset()
	_chapters.begin(GameState, id)
	if not _world.load_file(str(ch.get("rooms", ""))):
		push_error("Game: failed to load rooms for chapter %s" % id)
		_go_chapters()
		return
	GameState.current_room = _world.start_id
	var intro: Array = ch.get("intro", [])
	if intro.is_empty():
		_go_explore()
	else:
		_begin_story("Chapter %02d — %s" % [_chapters.index_of(id) + 1, str(ch.get("title", ""))],
			str(ch.get("art", "")), intro, [["» Begin", _go_explore]])

## Called after anything that can set a flag: completes the chapter's main
## quest when its last step lands (the Conclude button then appears in explore).
func _check_quest() -> void:
	var ch := _current_chapter()
	if ch.is_empty():
		return
	var qid := str(ch.get("quest", ""))
	if qid == "" or GameState.has_flag("concluded_" + str(ch.get("id", ""))):
		return
	if _quests.is_complete(GameState, qid) and not GameState.has_flag("questdone_" + qid):
		GameState.set_flag("questdone_" + qid)
		_toast("Chapter goal complete.")

func _conclude_chapter() -> void:
	var ch := _current_chapter()
	var id := str(ch.get("id", ""))
	GameState.set_flag("concluded_" + id)
	_chapters.finish(GameState, id)
	var outro: Array = ch.get("outro", [])
	_begin_story("Chapter %02d — %s" % [_chapters.index_of(id) + 1, str(ch.get("title", ""))],
		str(ch.get("art", "")), outro if not outro.is_empty() else ["(end of chapter)"],
		[["» Continue", _go_chapters]])


# ---------------------------------------------------------------- state switches

func _show_only(active: Control) -> void:
	for layer in [_title_layer, _chapters_layer, _explore_layer, _dialog_layer, _menu_layer]:
		layer.visible = (layer == active)

func _go_title() -> void:
	_state = State.TITLE
	_show_only(_title_layer)
	AudioManager.play("title")

func _go_chapters() -> void:
	_state = State.CHAPTERS
	_show_only(_chapters_layer)
	_refresh_chapters_list()

func _go_explore() -> void:
	_state = State.EXPLORE
	_show_only(_explore_layer)
	_refresh_room()

func _go_dialog(npc_id: String) -> void:
	_dialog = DialogEngine.new()
	if not _dialog.load_file(NPC_DIR + npc_id + ".json"):
		return
	_dialog_npc = npc_id
	_state = State.DIALOG
	_explore_layer.visible = true   # keep room behind the panel
	_dialog_layer.visible = true
	_title_layer.visible = false
	_chapters_layer.visible = false
	_menu_layer.visible = false
	_refresh_dialog()


# ---------------------------------------------------------------- explore render

func _refresh_room() -> void:
	var id := GameState.current_room
	var r := _world.room(id)
	_room_name_lbl.text = r.get("name", id)
	var tex := Assets.background(r.get("bg", ""))
	_bg_rect.texture = tex
	_bg_rect.visible = tex != null
	# Until a plate is painted: a quiet per-room tinted panel + watermark name.
	_bg_placeholder.visible = tex == null
	_bg_room_glyph.visible = tex == null
	if tex == null:
		_bg_placeholder.color = _placeholder_color(id)
		_bg_room_glyph.text = str(r.get("name", id))
	# Entering a room can advance the story.
	if r.has("on_enter_flag"):
		GameState.set_flag(str(r["on_enter_flag"]))
		_check_quest()
	_desc_lbl.text = r.get("desc", "")
	_rebuild_buttons(r)
	_refresh_status()
	AudioManager.play(AudioManager.for_room(r))

## Placeholder plate tint: a stable dark hue keyed off the room id, so every
## room reads distinct before its art exists.
func _placeholder_color(room_id: String) -> Color:
	var h := float(abs(room_id.hash()) % 360) / 360.0
	return Color.from_hsv(h, 0.35, 0.14)

func _rebuild_buttons(r: Dictionary) -> void:
	for c in _button_bar.get_children():
		c.queue_free()
	var dir_abbr := { "north": "N", "south": "S", "east": "E", "west": "W" }
	var exits: Dictionary = r.get("exits", {})
	for dir in ["west", "north", "south", "east"]:
		if not exits.has(dir):
			continue
		var dest: String = exits[dir]
		var b := Button.new()
		b.text = dir_abbr.get(dir, dir)
		b.tooltip_text = "Go %s to %s" % [dir, _world.room(dest).get("name", dest)]
		b.pressed.connect(_try_move.bind(dir))
		_button_bar.add_child(b)
	# Talk actions for NPCs in the room.
	for npc in r.get("npcs", []):
		var b := Button.new()
		b.text = "Talk: %s" % _npc_label(str(npc))
		b.pressed.connect(_go_dialog.bind(str(npc)))
		_button_bar.add_child(b)
	# Pickups (quest items lying in the world). Taken-state rides story_flags.
	for p in r.get("pickups", []):
		var iid := str(p.get("item", ""))
		if GameState.has_flag("took_" + iid):
			continue
		var b := Button.new()
		b.text = str(p.get("label", "Take " + _catalog.item_name(iid)))
		b.pressed.connect(_do_pickup.bind(iid))
		_button_bar.add_child(b)
	if r.has("shop"):
		var shopb := Button.new()
		shopb.text = "Shop"
		shopb.pressed.connect(_open_shop.bind(String(r["shop"]), ""))
		_button_bar.add_child(shopb)
	if r.get("net", false) or r.get("pax", false):
		var netb := Button.new()
		netb.text = "NET"
		netb.pressed.connect(_open_net)
		_button_bar.add_child(netb)
	if r.get("matrix", false) and _has_deck():
		var jb := Button.new()
		jb.text = "Jack In"
		jb.pressed.connect(_go_matrix)
		_button_bar.add_child(jb)
	var qb2 := Button.new()
	qb2.text = "Quest"
	qb2.pressed.connect(_open_quest_log)
	_button_bar.add_child(qb2)
	var invb := Button.new()
	invb.text = "Items"
	invb.pressed.connect(_open_inventory)
	_button_bar.add_child(invb)
	# Chapter conclude — appears once the main quest is complete.
	var ch := _current_chapter()
	var qid := str(ch.get("quest", ""))
	if qid != "" and _quests.is_complete(GameState, qid):
		var cb := Button.new()
		cb.text = "Conclude chapter »"
		cb.add_theme_color_override("font_color", UITheme.ACCENT)
		cb.pressed.connect(_conclude_chapter)
		_button_bar.add_child(cb)
	var sb := Button.new()
	sb.text = "Save"
	sb.pressed.connect(_do_save)
	_button_bar.add_child(sb)
	var lb := Button.new()
	lb.text = "Load"
	lb.pressed.connect(_do_load)
	_button_bar.add_child(lb)
	var mb := Button.new()
	mb.text = "Menu"
	mb.tooltip_text = "Back to chapter select"
	mb.pressed.connect(_go_chapters)
	_button_bar.add_child(mb)

func _npc_label(npc_id: String) -> String:
	# Cheap display name: dialog files carry "name"; fall back to the id.
	var d = _load_json(NPC_DIR + npc_id + ".json")
	if d != null and typeof(d) == TYPE_DICTIONARY:
		return str(d.get("name", npc_id))
	return npc_id

func _do_pickup(iid: String) -> void:
	if not GameState.inventory.has(iid):
		GameState.inventory.append(iid)
	GameState.set_flag("took_" + iid)
	GameState.set_flag("granted_" + iid)
	_toast("Taken: %s" % _catalog.item_name(iid))
	_check_quest()
	_refresh_room()

func _refresh_status() -> void:
	var hh := int(GameState.game_minutes / 60.0) % 24
	var mm := GameState.game_minutes % 60
	var loc: String = _world.room(GameState.current_room).get("name", GameState.current_room)
	var con := "   CON %d" % GameState.constitution if _has_deck() else ""
	_status_lbl.text = "%s   ·   %d cr%s   ·   %s   ·   %02d:%02d" % [
		GameState.player_name, GameState.credits, con, loc, hh, mm]
	var ch := _current_chapter()
	var qid := str(ch.get("quest", ""))
	_objective_lbl.text = ("» " + _quests.objective(GameState, qid)) if qid != "" else ""


# ---------------------------------------------------------------- actions

func _try_move(direction: String) -> void:
	if _state != State.EXPLORE:
		return
	var dest := _world.move(GameState.current_room, direction)
	if dest == "":
		return
	var dr := _world.room(dest)
	# Quest-gated doors: a room can require a flag before it lets you in.
	if dr.has("requires_flag") and not GameState.has_flag(str(dr["requires_flag"])):
		_toast(str(dr.get("locked_text", "You can't go that way yet.")))
		return
	GameState.current_room = dest
	GameState.game_minutes += MINUTES_PER_MOVE
	_refresh_room()

# ---- Save / Load ----------------------------------------------------------------

func _do_save() -> void:
	_open_save_menu()

func _open_save_menu() -> void:
	_menu_begin("SAVE GAME", "Name this save, then press Save:")
	var suggested := "%s - %s" % [GameState.player_name, _room_name(GameState.current_room)]
	_save_name_edit = LineEdit.new()
	_save_name_edit.text = suggested
	_save_name_edit.custom_minimum_size = Vector2(1758, 64)
	_save_name_edit.max_length = 40
	_menu_list.add_child(_save_name_edit)
	_menu_button("» Save", _commit_save)
	var saves := SaveSystem.list_saves()
	if not saves.is_empty():
		_menu_label("— or overwrite an existing save —", true)
		for s in saves:
			_menu_button("%s   (%s)" % [s["name"], s["saved_at"]], _commit_save_named.bind(str(s["name"])))
	_menu_button("« Cancel", _go_explore)
	_save_name_edit.grab_focus()
	_save_name_edit.select_all()

func _commit_save() -> void:
	var nm := _save_name_edit.text.strip_edges() if _save_name_edit != null else ""
	if nm == "":
		nm = GameState.player_name
	_commit_save_named(nm)

func _commit_save_named(nm: String) -> void:
	if SaveSystem.save_as(nm):
		_go_explore()
		_toast("Saved: %s" % nm)
	else:
		_toast("Save failed.")

func _do_load() -> void:
	_open_load_menu()

func _open_load_menu() -> void:
	_menu_begin("LOAD GAME", "Pick a save point:")
	var saves := SaveSystem.list_saves()
	if saves.is_empty():
		_menu_label("No saves yet — use Save first.")
	else:
		for s in saves:
			_menu_button("▸ %s  —  %s, %s, %d cr  (%s)" % [
					s["name"], s["chapter"], str(s["room"]), int(s["credits"]), s["saved_at"]],
				_do_load_slug.bind(str(s["slug"])))
			_menu_button("        ✕ delete \"%s\"" % s["name"], _confirm_delete.bind(str(s["slug"]), str(s["name"])))
	_menu_button("« Cancel", _cancel_menu)

## Cancel destination depends on where the menu was opened from.
func _cancel_menu() -> void:
	if GameState.current_chapter != "" and _world.has_room(GameState.current_room):
		_go_explore()
	else:
		_go_chapters()

func _do_load_slug(slug: String) -> void:
	if SaveSystem.load_slug(slug) and _restore_loaded_state():
		_go_explore()
		_toast("Game loaded.")
	else:
		_toast("Load failed — save is corrupt.")
		_go_chapters()

## Rebuild the chapter's world for a loaded save; reject anything invalid.
func _restore_loaded_state() -> bool:
	var ch := _chapters.by_id(GameState.current_chapter)
	if ch.is_empty():
		return false
	if not _world.load_file(str(ch.get("rooms", ""))):
		return false
	if not _world.has_room(GameState.current_room):
		GameState.current_room = _world.start_id
	GameState.credits = clampi(GameState.credits, 0, 1_000_000_000)
	GameState.health = clampi(GameState.health, 0, 100)
	GameState.constitution = clampi(GameState.constitution, 0, 2000)
	GameState.game_minutes = maxi(GameState.game_minutes, 0)
	return true

func _confirm_delete(slug: String, display_name: String) -> void:
	_menu_begin("DELETE SAVE?", "This cannot be undone.")
	_menu_label("Permanently delete this save?")
	_menu_label("    \"%s\"" % display_name)
	_menu_button("«  No — keep it", _open_load_menu)
	_menu_button("✕  YES, delete it", _really_delete.bind(slug, display_name))

func _really_delete(slug: String, display_name: String) -> void:
	SaveSystem.delete_slug(slug)
	_open_load_menu()
	_toast("Deleted: %s" % display_name)

func _quicksave() -> void:
	if SaveSystem.quicksave():
		_toast("Quicksaved.")
	else:
		_toast("Quicksave failed.")

func _quickload() -> void:
	if SaveSystem.load_slug(SaveSystem.QUICK_SLUG) and _restore_loaded_state():
		_go_explore()
		_toast("Quickloaded.")
	else:
		_toast("No quicksave found.")

func _room_name(rid: String) -> String:
	if rid == "":
		return "?"
	return _world.room(rid).get("name", rid)

func _do_quit() -> void:
	get_tree().quit()

## Briefly flash a centered message over the scene, then fade it out.
func _toast(msg: String) -> void:
	if _toast_lbl == null:
		return
	_toast_lbl.text = msg
	_toast_lbl.modulate.a = 1.0
	_toast_lbl.visible = true
	var tw := create_tween()
	tw.tween_interval(1.2)
	tw.tween_property(_toast_lbl, "modulate:a", 0.0, 0.8)
	tw.tween_callback(func() -> void: _toast_lbl.visible = false)


# ---------------------------------------------------------------- dialog render

func _refresh_dialog() -> void:
	_dialog_name.text = _dialog.npc_name
	_dialog_text.text = _dialog.current_text()
	# Node arrival hooks: item grant (once), flag set, credit delta (once).
	var grant := _dialog.current_grant()
	if grant != "" and not GameState.has_flag("granted_" + grant):
		GameState.set_flag("granted_" + grant)
		if not GameState.inventory.has(grant):
			GameState.inventory.append(grant)
		_toast("Received: %s" % _catalog.item_name(grant))
	var sf := _dialog.current_set_flag()
	if sf != "":
		GameState.set_flag(sf)
	var cr := _dialog.current_credits()
	if cr != 0:
		var paid_flag := "paid_%s_%s" % [_dialog_npc, _dialog.current_id()]
		if not GameState.has_flag(paid_flag):
			GameState.set_flag(paid_flag)
			GameState.credits = maxi(0, GameState.credits + cr)
	_check_quest()
	for c in _dialog_options.get_children():
		c.queue_free()
	var opts := _dialog.current_options(GameState)
	for o in opts:
		var b := Button.new()
		b.text = "> " + str(o.get("text", ""))
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_fsize(b, 22)
		b.pressed.connect(_on_dialog_option.bind(int(o["_idx"])))
		_dialog_options.add_child(b)
	if _dialog.is_terminal(GameState):
		var b := Button.new()
		b.text = "(end conversation)"
		_fsize(b, 22)
		b.pressed.connect(_end_dialog)
		_dialog_options.add_child(b)

func _on_dialog_option(raw_index: int) -> void:
	if _dialog.choose(raw_index):
		_refresh_dialog()

func _end_dialog() -> void:
	_go_explore()


# ---------------------------------------------------------------- input

func _unhandled_input(event: InputEvent) -> void:
	match _state:
		State.TITLE:
			if (event is InputEventKey and event.pressed) \
					or (event is InputEventMouseButton and event.pressed):
				_go_chapters()
				get_viewport().set_input_as_handled()
		State.EXPLORE:
			if event is InputEventKey and event.pressed and not event.echo:
				_handle_explore_key(event.keycode)
		State.MENU:
			if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
				_cancel_menu()
				get_viewport().set_input_as_handled()

func _handle_explore_key(keycode: int) -> void:
	match keycode:
		KEY_UP, KEY_W:
			_try_move("north")
		KEY_DOWN, KEY_S:
			_try_move("south")
		KEY_LEFT, KEY_A:
			_try_move("west")
		KEY_RIGHT, KEY_D:
			_try_move("east")
		KEY_I:
			_open_inventory()
		KEY_Q:
			_open_quest_log()
		KEY_F5:
			_quicksave()
		KEY_F9:
			_quickload()
