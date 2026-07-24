extends RefCounted
## UITheme — the modern look for the Flatline Sessions sequels.
##
## Where the 1988-flavored original deliberately pixel-crushed everything into a
## 320x200 EGA frame, the sequels render clean at a native 1920x1080 canvas in
## full 32-bit color: flat panels, rounded corners, generous spacing, one neon
## accent per game. All built in code so a fresh checkout needs no imported
## theme resources.

const BG := Color("0a0e14")            # near-black blue — the app backdrop
const PANEL := Color("121826")         # raised surface
const PANEL_BORDER := Color("232b3a")
const TEXT := Color("d5dce6")          # primary body text
const TEXT_DIM := Color("8a94a6")      # secondary / captions
const ACCENT := Color("e05fd0")        # game III: hot violet (simstim neon)
const ACCENT_DIM := Color("7a2f6e")
const DANGER := Color("e05561")

static func build() -> Theme:
	var th := Theme.new()
	th.default_font_size = 24

	# Flat, rounded buttons with an accent hover.
	var normal := _box(PANEL, PANEL_BORDER)
	var hover := _box(Color("1a2233"), ACCENT)
	var pressed := _box(Color("0d1420"), ACCENT_DIM)
	var disabled := _box(Color("0e131d"), Color("1a2029"))
	th.set_stylebox("normal", "Button", normal)
	th.set_stylebox("hover", "Button", hover)
	th.set_stylebox("pressed", "Button", pressed)
	th.set_stylebox("disabled", "Button", disabled)
	th.set_stylebox("focus", "Button", _box_transparent(ACCENT_DIM))
	th.set_color("font_color", "Button", TEXT)
	th.set_color("font_hover_color", "Button", ACCENT)
	th.set_color("font_pressed_color", "Button", ACCENT)
	th.set_color("font_disabled_color", "Button", TEXT_DIM)

	# Panels (dialog box, menus).
	th.set_stylebox("panel", "Panel", _box(PANEL, PANEL_BORDER))

	# Line edits.
	var le := _box(Color("0d1420"), PANEL_BORDER)
	th.set_stylebox("normal", "LineEdit", le)
	th.set_stylebox("focus", "LineEdit", _box(Color("0d1420"), ACCENT))
	th.set_color("font_color", "LineEdit", TEXT)
	th.set_color("caret_color", "LineEdit", ACCENT)

	th.set_color("font_color", "Label", TEXT)

	# Sliders (settings — music volume). Only the track + fill are themed; the
	# grabber icon falls back to the default theme so it stays visible.
	var track := StyleBoxFlat.new()
	track.bg_color = Color("0d1420")
	track.border_color = PANEL_BORDER
	track.set_border_width_all(1)
	track.set_corner_radius_all(4)
	track.content_margin_top = 6
	track.content_margin_bottom = 6
	th.set_stylebox("slider", "HSlider", track)
	var fill := StyleBoxFlat.new()
	fill.bg_color = ACCENT_DIM
	fill.set_corner_radius_all(4)
	fill.content_margin_top = 6
	fill.content_margin_bottom = 6
	th.set_stylebox("grabber_area", "HSlider", fill)
	var fill_hi: StyleBoxFlat = fill.duplicate()
	fill_hi.bg_color = ACCENT
	th.set_stylebox("grabber_area_highlight", "HSlider", fill_hi)

	return th

## A rounded flat StyleBoxFlat with a hairline border and comfy 1080p padding.
static func _box(bg: Color, border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 9
	sb.content_margin_bottom = 9
	return sb

static func _box_transparent(border: Color) -> StyleBoxFlat:
	var sb := _box(Color(0, 0, 0, 0), border)
	sb.set_border_width_all(2)
	return sb
