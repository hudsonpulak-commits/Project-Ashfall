class_name UIStyle
extends RefCounted
## Pixel-style UI theme: hard edges, 1px borders, flat colours, no rounding.
## If res://assets/fonts/ui_font.ttf (or .otf/.fnt) exists it is used, so a
## pixel font can be dropped in without code changes (see docs/ART_GUIDE.md).

const BG := Color("#17140e")
const BG_ALPHA := Color(0.09, 0.08, 0.055, 0.88)
const BORDER := Color("#7a6232")
const BORDER_HI := Color("#d8b468")
const TEXT := Color("#f3ead2")
const TEXT_DIM := Color("#b8ab88")
const SLOT := Color("#2a2418")
const ACCENT := Color("#e8c050")
const FONT_SIZE := 11


static func box(bg: Color = BG_ALPHA, border: Color = BORDER, w: int = 1, pad: int = 3) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(w)
	s.set_corner_radius_all(0)
	s.anti_aliasing = false
	s.set_content_margin_all(pad)
	return s


static func make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = FONT_SIZE
	for p in ["res://assets/fonts/ui_font.ttf", "res://assets/fonts/ui_font.otf", "res://assets/fonts/ui_font.fnt"]:
		if ResourceLoader.exists(p):
			t.default_font = load(p)
			break
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_outline_color", "Label", Color.BLACK)
	t.set_constant("outline_size", "Label", 0)
	t.set_stylebox("normal", "Button", box(Color("#2e2618"), BORDER, 1, 3))
	t.set_stylebox("hover", "Button", box(Color("#3a3020"), BORDER_HI, 1, 3))
	t.set_stylebox("pressed", "Button", box(Color("#4a3c22"), BORDER_HI, 1, 3))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_stylebox("disabled", "Button", box(Color("#201c14"), Color("#4a3c22"), 1, 3))
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", ACCENT)
	t.set_color("font_pressed_color", "Button", ACCENT)
	t.set_stylebox("panel", "PanelContainer", box())
	t.set_stylebox("panel", "Panel", box())
	return t
