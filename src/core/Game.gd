extends Control
## Game — the chapter-based adventure loop for the Flatline Sessions sequels.
##
## Boot is an empty Control named "Main" with this script; every widget is built
## in code on a native 1920x1080 canvas in full 32-bit color (modern look: flat
## panels, rounded corners, one neon accent — see src/ui/UITheme.gd). Flow:
##   TITLE -> CHAPTER SELECT -> (intro pages) -> EXPLORE <-> DIALOG / MENU
## Each chapter locks the player to one of the novel's PoV characters and ends
## when its main quest completes (outro pages, next chapter unlocks).

enum State { TITLE, CHAPTERS, EXPLORE, DIALOG, MENU, DEDICATION }

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
## Shown as a quiet fade-in card before the title, every boot.
const DEDICATION_TEXT := "Dedicated to William Gibson and all other Science Fiction authors; past, present, and future."
## Player preferences (autosave flag) — same file AudioManager keeps music in.
const SETTINGS_PATH := "user://settings.cfg"
const VIEW_X := 36
const VIEW_Y := 30
const VIEW_W := 1848
const VIEW_H := 636
const MINUTES_PER_MOVE := 3
const HIDDEN_ROOM := "1337"
const VOID_IMAGE := "res://assets/ui/void.png"
const VOID_TRACKS := [
	"title",
	"streets",
	"shops",
	"cyberspace",
	"ice_combat",
	"ch01_the_smoke",
	"ch02_dog_solitude",
	"ch03_florida",
	"ch04_malibu",
	"ch05_oracle_lost_tech",
	"ch06_the_work",
	"ch07_the_aleph",
	"ch08_the_loas_price",
	"ch09_underground",
	"ch10_the_switch",
	"ch11_siege_dog_solitude",
	"ch12_mona_lisa_underdrive",
]
const TRACK_TITLES := {
	"title": "THE FLATLINE SESSIONS III",
	"streets": "Dome Snow",
	"shops": "Junkyard Retail",
	"cyberspace": "Aleph Weather",
	"ice_combat": "3Jane Recursion",
	"ch01_the_smoke": "The Smoke",
	"ch02_dog_solitude": "Dog Solitude",
	"ch03_florida": "Florida",
	"ch04_malibu": "Malibu",
	"ch05_oracle_lost_tech": "The Oracle of Lost Technology",
	"ch06_the_work": "The Work",
	"ch07_the_aleph": "The Aleph",
	"ch08_the_loas_price": "The Loa's Price",
	"ch09_underground": "Underground",
	"ch10_the_switch": "The Switch",
	"ch11_siege_dog_solitude": "The Siege of Dog Solitude",
	"ch12_mona_lisa_underdrive": "Mona Lisa Underdrive",
}

var _state: int = State.TITLE
var _autosave := true                 # rolling autosave, on by default
var _world: World
var _dialog: DialogEngine
var _dialog_npc: String = ""
var _chapters: Chapters
var _quests: Quests
var _catalog: Catalog
var _matrix: Matrix

# Layers
var _dedication_layer: Control
var _dedication_tween: Tween
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
var _story_art = ""
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
	AudioManager.track_changed.connect(_on_track_changed)
	_load_prefs()
	_build_dedication_layer()
	_build_title_layer()
	_build_chapters_layer()
	_build_explore_layer()
	_build_dialog_layer()
	_build_menu_layer()
	_go_dedication()


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

func _build_dedication_layer() -> void:
	_dedication_layer = _full_control("Dedication")
	var bg := ColorRect.new()
	bg.color = UITheme.BG
	bg.size = Vector2(1920, 1080)
	_dedication_layer.add_child(bg)
	# A short accent tick sits just above the dedication line.
	var rule := ColorRect.new()
	rule.color = UITheme.ACCENT_DIM
	rule.position = Vector2(860, 456)
	rule.size = Vector2(200, 4)
	_dedication_layer.add_child(rule)
	var ded := Label.new()
	ded.text = DEDICATION_TEXT
	ded.position = Vector2(360, 492)
	ded.size = Vector2(1200, 240)
	ded.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ded.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	ded.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ded.add_theme_color_override("font_color", UITheme.TEXT)
	_fsize(ded, 40)
	_dedication_layer.add_child(ded)

func _build_title_layer() -> void:
	_title_layer = _full_control("Title")
	var bg := ColorRect.new()
	bg.color = UITheme.BG
	bg.size = Vector2(1920, 1080)
	_title_layer.add_child(bg)
	# Cover art fills behind the title (clean, full-res).
	var tex: Texture2D = Assets.load_texture(TITLE_COVER)
	if tex != null:
		var tr := TextureRect.new()
		tr.texture = tex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tr.clip_contents = true
		tr.size = Vector2(1920, 1080)
		_title_layer.add_child(tr)
	# The title ALWAYS renders on top of the cover — the cover art carries no
	# lettering, so the game name lives here, outlined to read over any plate.
	# game_title is the full "THE FLATLINE SESSIONS II — COUNT BINARY"; split it
	# on the em dash into a main line + accent subtitle so it fits and reads big.
	var full := _chapters.game_title if _chapters.game_title != "" else "THE FLATLINE SESSIONS II"
	var main_line := full
	var sub_line := ""
	var dash := full.find("—")
	if dash != -1:
		main_line = full.substr(0, dash).strip_edges()
		sub_line = full.substr(dash + 1).strip_edges()
	var series := Label.new()
	series.text = main_line
	series.position = Vector2(0, 132)
	series.size = Vector2(1920, 72)
	series.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	series.add_theme_color_override("font_color", UITheme.TEXT)
	series.add_theme_color_override("font_outline_color", UITheme.BG)
	series.add_theme_constant_override("outline_size", 10)
	_fsize(series, 44)
	_title_layer.add_child(series)
	if sub_line != "":
		var t := Label.new()
		t.text = sub_line
		t.position = Vector2(0, 210)
		t.size = Vector2(1920, 110)
		t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		t.add_theme_color_override("font_color", UITheme.ACCENT)
		t.add_theme_color_override("font_outline_color", UITheme.BG)
		t.add_theme_constant_override("outline_size", 12)
		_fsize(t, 72)
		_title_layer.add_child(t)
	var rule := ColorRect.new()
	rule.color = UITheme.ACCENT
	rule.position = Vector2(660, 338)
	rule.size = Vector2(600, 4)
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
	# The title cover sits behind the list as a faint wash — atmosphere, not a
	# focal point, so it never competes with the chapter text.
	var cover: Texture2D = Assets.load_texture(TITLE_COVER)
	if cover != null:
		var cr := TextureRect.new()
		cr.texture = cover
		cr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		cr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		cr.clip_contents = true
		cr.size = Vector2(1920, 1080)
		cr.modulate = Color(1, 1, 1, 0.18)
		_chapters_layer.add_child(cr)
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
func _begin_story(title: String, art, pages: Array, final: Array) -> void:
	_story_title = title
	_story_art = art
	_story_pages = pages if not pages.is_empty() else [""]
	_story_final = final
	_story_idx = 0
	_show_story_page()

func _show_story_page() -> void:
	_menu_begin(_story_title, "· %d / %d ·" % [_story_idx + 1, _story_pages.size()], _story_art_path(), true)
	_menu_label(str(_story_pages[_story_idx]))
	if _story_idx < _story_pages.size() - 1:
		_menu_button("Next »", _story_next)
	else:
		for fb in _story_final:
			_menu_button(str(fb[0]), fb[1])

func _story_art_path() -> String:
	if typeof(_story_art) == TYPE_ARRAY:
		var art_list: Array = _story_art
		if art_list.is_empty():
			return ""
		return str(art_list[mini(_story_idx, art_list.size() - 1)])
	return str(_story_art)

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
		var intro_art = ch.get("intro_art", ch.get("art", ""))
		_begin_story("Chapter %02d — %s" % [_chapters.index_of(id) + 1, str(ch.get("title", ""))],
			intro_art, intro, [["» Begin", _go_explore]])

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
	_autosave_now()
	var outro: Array = ch.get("outro", [])
	var outro_art = ch.get("outro_art", ch.get("art", ""))
	_begin_story("Chapter %02d — %s" % [_chapters.index_of(id) + 1, str(ch.get("title", ""))],
		outro_art, outro if not outro.is_empty() else ["(end of chapter)"],
		[["» Continue", _go_chapters]])


# ---------------------------------------------------------------- state switches

func _show_only(active: Control) -> void:
	for layer in [_dedication_layer, _title_layer, _chapters_layer, _explore_layer, _dialog_layer, _menu_layer]:
		layer.visible = (layer == active)

## Boot card: fade the Gibson dedication up, hold, fade out, then hand off to the
## title. Any key/click during it skips straight to the title (see _unhandled_input).
func _go_dedication() -> void:
	_state = State.DEDICATION
	_show_only(_dedication_layer)
	_dedication_layer.modulate.a = 0.0
	if _dedication_tween != null and _dedication_tween.is_valid():
		_dedication_tween.kill()
	_dedication_tween = create_tween()
	_dedication_tween.tween_property(_dedication_layer, "modulate:a", 1.0, 1.0)
	_dedication_tween.tween_interval(2.4)
	_dedication_tween.tween_property(_dedication_layer, "modulate:a", 0.0, 0.8)
	_dedication_tween.tween_callback(_go_title)

func _go_title() -> void:
	if _dedication_tween != null and _dedication_tween.is_valid():
		_dedication_tween.kill()
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
	if GameState.current_room == HIDDEN_ROOM:
		_show_void_room()
		return
	var id := GameState.current_room
	var r := _world.room(id)
	_room_name_lbl.text = r.get("name", id)
	var tex := Assets.background(r.get("bg", ""))
	_bg_rect.texture = tex
	_bg_rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_bg_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
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
	# Every room entry is a natural checkpoint — roll the autosave here so moves,
	# pickups, and dialog exits (all of which funnel back through _refresh_room)
	# are captured without the player ever opening the Save menu.
	_autosave_now()

func _show_void_room() -> void:
	_room_name_lbl.text = "1337"
	var tex := Assets.load_texture(VOID_IMAGE)
	_bg_rect.texture = tex
	_bg_rect.visible = tex != null
	_bg_rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_bg_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_bg_placeholder.visible = tex == null
	_bg_room_glyph.visible = tex == null
	if tex == null:
		_bg_placeholder.color = Color("050609")
		_bg_room_glyph.text = "1337"
	_desc_lbl.text = "You slipped through a crack in the matrix into a room that's on no map. The exits have been sanded off. The only thing still answering is the soundtrack."
	for c in _button_bar.get_children():
		c.queue_free()
	var loadb := Button.new()
	loadb.text = "Load"
	loadb.pressed.connect(_do_load)
	_fsize(loadb, 22)
	_button_bar.add_child(loadb)
	var quitb := Button.new()
	quitb.text = "Quit"
	quitb.pressed.connect(_do_quit)
	_fsize(quitb, 22)
	_button_bar.add_child(quitb)
	var prevb := Button.new()
	prevb.text = "◀"
	prevb.tooltip_text = "Previous soundtrack cut"
	prevb.pressed.connect(_void_skip.bind(false))
	_fsize(prevb, 22)
	_button_bar.add_child(prevb)
	var nextb := Button.new()
	nextb.text = "▶"
	nextb.tooltip_text = "Next soundtrack cut"
	nextb.pressed.connect(_void_skip.bind(true))
	_fsize(nextb, 22)
	_button_bar.add_child(nextb)
	var gearb := Button.new()
	gearb.text = "⚙"
	gearb.tooltip_text = "Settings"
	gearb.pressed.connect(_open_settings)
	_fsize(gearb, 22)
	_button_bar.add_child(gearb)
	_status_lbl.text = "%s   ·   1337 cr   CON 1337   ·   1337   ·   13:37" % GameState.player_name
	_objective_lbl.text = ""
	AudioManager.play_playlist(VOID_TRACKS)
	_room_name_lbl.text = _void_nowplaying()

func _void_nowplaying() -> String:
	var track := AudioManager.current_track()
	if track == "":
		return "1337"
	return "1337  ·  " + str(TRACK_TITLES.get(track, track))

func _void_skip(next := true) -> void:
	if next:
		AudioManager.next_track()
	else:
		AudioManager.prev_track()
	_room_name_lbl.text = _void_nowplaying()

func _on_track_changed(_track: String) -> void:
	if GameState.current_room == HIDDEN_ROOM and _room_name_lbl != null:
		_room_name_lbl.text = _void_nowplaying()

## Placeholder plate tint: a stable dark hue keyed off the room id, so every
## room reads distinct before its art exists.
func _placeholder_color(room_id: String) -> Color:
	var h := float(abs(room_id.hash()) % 360) / 360.0
	return Color.from_hsv(h, 0.35, 0.14)

func _rebuild_buttons(r: Dictionary) -> void:
	for c in _button_bar.get_children():
		c.queue_free()
	# Compass stays fixed every room: all four directions always show, but only
	# the room's real exits are live — the rest sit visibly dimmed and unclickable.
	var dir_abbr := { "north": "N", "south": "S", "east": "E", "west": "W" }
	var exits: Dictionary = r.get("exits", {})
	for dir in ["west", "north", "south", "east"]:
		var b := Button.new()
		b.text = dir_abbr.get(dir, dir)
		if exits.has(dir):
			var dest: String = exits[dir]
			b.tooltip_text = "Go %s to %s" % [dir, _world.room(dest).get("name", dest)]
			b.pressed.connect(_try_move.bind(dir))
		else:
			b.disabled = true
			b.tooltip_text = "No exit %s" % dir
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
	var gear := Button.new()
	gear.text = "⚙"
	gear.tooltip_text = "Settings"
	gear.pressed.connect(_open_settings)
	_button_bar.add_child(gear)
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
	_menu_button("« Cancel (Esc)", _cancel_menu)
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
	# The way back comes FIRST so it can never scroll out of sight under a
	# long save list — mid-story that means straight back to the running game.
	_menu_button("« Back (Esc)", _cancel_menu)
	var saves := SaveSystem.list_saves()
	if saves.is_empty():
		_menu_label("No saves yet — use Save first.")
	else:
		for s in saves:
			_menu_button("▸ %s  —  %s, %s, %d cr  (%s)" % [
					s["name"], s["chapter"], str(s["room"]), int(s["credits"]), s["saved_at"]],
				_do_load_slug.bind(str(s["slug"])))
			_menu_button("        ✕ delete \"%s\"" % s["name"], _confirm_delete.bind(str(s["slug"]), str(s["name"])))
	_menu_button("« Back (Esc)", _cancel_menu)

## Cancel destination depends on where the menu was opened from.
func _cancel_menu() -> void:
	if GameState.current_chapter != "" and (GameState.current_room == HIDDEN_ROOM
			or _world.has_room(GameState.current_room)):
		_go_explore()
	else:
		_go_chapters()

# ---- Settings -------------------------------------------------------------------

func _open_settings() -> void:
	_menu_begin("SETTINGS", "Changes apply immediately and are remembered.")
	var cb := CheckButton.new()
	cb.text = "Music"
	cb.button_pressed = AudioManager.enabled
	cb.toggled.connect(_set_music_enabled)
	_fsize(cb, 22)
	_menu_list.add_child(cb)
	var ab := CheckButton.new()
	ab.text = "Autosave"
	ab.button_pressed = _autosave
	ab.toggled.connect(_set_autosave_enabled)
	_fsize(ab, 22)
	_menu_list.add_child(ab)
	_menu_button("« Back (Esc)", _cancel_menu)

func _set_music_enabled(on: bool) -> void:
	AudioManager.set_music_enabled(on)
	if on and _state == State.MENU and _world.has_room(GameState.current_room):
		# resume the room's cue right away rather than waiting for a room change
		AudioManager.play(AudioManager.for_room(_world.room(GameState.current_room)))

func _set_autosave_enabled(on: bool) -> void:
	_autosave = on
	_save_prefs()
	if on:
		_autosave_now()   # capture the current spot the moment it's switched on

## Roll the autosave when enabled and we're actually inside a chapter (never on
## the title, and never in the hidden room 1337).
func _autosave_now() -> void:
	if not _autosave or GameState.current_chapter == "" or GameState.current_room == HIDDEN_ROOM:
		return
	SaveSystem.autosave()

func _load_prefs() -> void:
	var cf := ConfigFile.new()
	if cf.load(SETTINGS_PATH) == OK:
		_autosave = bool(cf.get_value("game", "autosave", true))

func _save_prefs() -> void:
	var cf := ConfigFile.new()
	cf.load(SETTINGS_PATH)
	cf.set_value("game", "autosave", _autosave)
	cf.save(SETTINGS_PATH)

func _do_load_slug(slug: String) -> void:
	if SaveSystem.load_slug(slug) and _restore_loaded_state():
		_go_explore()
		_toast("Game loaded.")
	else:
		_toast("Load failed — save is corrupt.")
		_go_chapters()

## Rebuild the chapter's world for a loaded save; hacked saves go to room 1337.
func _restore_loaded_state() -> bool:
	var tampered := false
	var ch := _chapters.by_id(GameState.current_chapter)
	if ch.is_empty():
		tampered = true
	elif not _world.load_file(str(ch.get("rooms", ""))):
		tampered = true
	elif GameState.current_room != HIDDEN_ROOM and not _world.has_room(GameState.current_room):
		tampered = true
	if GameState.credits < 0 or GameState.credits > 1_000_000_000:
		tampered = true
	if GameState.health < 0 or GameState.health > 100:
		tampered = true
	if GameState.constitution < 0 or GameState.constitution > 2000:
		tampered = true
	if GameState.game_minutes < 0:
		tampered = true
	for iid in GameState.inventory:
		if _catalog.item(str(iid)).is_empty():
			tampered = true
			break
	GameState.credits = clampi(GameState.credits, 0, 1_000_000_000)
	GameState.health = clampi(GameState.health, 0, 100)
	GameState.constitution = clampi(GameState.constitution, 0, 2000)
	GameState.game_minutes = maxi(GameState.game_minutes, 0)
	if tampered:
		push_warning("Load: tampered or invalid save - banished to room 1337")
		GameState.current_room = HIDDEN_ROOM
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
		State.DEDICATION:
			if (event is InputEventKey and event.pressed) \
					or (event is InputEventMouseButton and event.pressed):
				_go_title()
				get_viewport().set_input_as_handled()
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
