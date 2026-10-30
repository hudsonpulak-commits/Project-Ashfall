class_name UIStyle
extends RefCounted
## Pixel-style UI theme: hard edges, 1px borders, flat colours, no rounding.
## If res://assets/fonts/ui_font.ttf (or .otf/.fnt) exists it is used, so a
## pixel font can be dropped in without code changes (see docs/ART_GUIDE.md).

const BG := Color("#2a2a30")
const BG_ALPHA := Color(0.165, 0.165, 0.19, 0.9)
const BORDER := Color("#54535b")
const BORDER_HI := Color("#c8c0b0")
const TEXT := Color("#e2dccb")
const TEXT_DIM := Color("#8a878a")
const SLOT := Color("#2a2a30")
const ACCENT := Color("#c8c0b0")
const EMBER := Color("#e8843a")   # restyle batch 07: focus / alerts only
const FONT_SIZE := 12


## restyle batch 07: 9-slice from assets/ui/kit (nearest-filtered by the theme owner).
static var _tex_cache: Dictionary = {}
static func tex(name: String, m: int, pad: int = -1) -> StyleBox:   # r2: content margin = texture margin
	var key := "%s/%d/%d" % [name, m, pad]
	if _tex_cache.has(key):
		return _tex_cache[key]
	var p := "res://assets/ui/kit/%s.png" % name
	if not ResourceLoader.exists(p):
		return box()
	var s := StyleBoxTexture.new()
	s.texture = load(p)
	s.texture_margin_left = m
	s.texture_margin_top = m
	s.texture_margin_right = m
	s.texture_margin_bottom = m
	s.set_content_margin_all(m if pad < 0 else pad)
	_tex_cache[key] = s
	return s


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
			var f = load(p)
			if f is FontFile:
				(f as FontFile).antialiasing = TextServer.FONT_ANTIALIASING_NONE
				(f as FontFile).hinting = TextServer.HINTING_NONE
			t.default_font = f
			break
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_outline_color", "Label", Color.BLACK)
	t.set_constant("outline_size", "Label", 0)
	t.set_stylebox("normal", "Button", tex("button_normal", 4))
	t.set_stylebox("hover", "Button", tex("button_hover", 4))
	t.set_stylebox("pressed", "Button", tex("button_pressed", 4))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_stylebox("disabled", "Button", tex("button_disabled", 4))
	t.set_color("font_disabled_color", "Button", TEXT_DIM)
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", ACCENT)
	t.set_color("font_pressed_color", "Button", ACCENT)
	t.set_stylebox("panel", "PanelContainer", tex("panel", 6))
	t.set_stylebox("panel", "Panel", tex("panel", 6))
	return t
