extends RefCounted
## Shared look for the "combat simulation" UI: monospace type, dark translucent panels
## with thin borders in the accent colour, bracketed buttons.

## The accent colours the player can pick (Settings "ui_color"), cyan by default.
const ACCENTS := {
	"CYAN": Color(0.35, 0.9, 1.0),
	"MAGENTA": Color(1.0, 0.35, 0.85),
	"LIME": Color(0.6, 1.0, 0.3),
	"AMBER": Color(1.0, 0.72, 0.25),
	"CRIMSON": Color(1.0, 0.33, 0.33),
	"VIOLET": Color(0.7, 0.52, 1.0),
	"WHITE": Color(0.93, 0.96, 1.0),
}
## The current accent (set_accent), and a see-through version of it for borders.
static var ACCENT := Color(0.35, 0.9, 1.0)
static var ACCENT_DIM := Color(0.35, 0.9, 1.0, 0.35)
## Border colour meaning "use ACCENT_DIM" (panel_box's default).
const _DEFAULT := Color(-1, -1, -1, -1)
const TEXT := Color(0.85, 0.95, 1.0)
const TEXT_DIM := Color(0.55, 0.7, 0.78)
const PANEL_BG := Color(0.02, 0.05, 0.08, 0.82)


## Switch every menu and HUD built from now on to accent `name` (a key of ACCENTS).
static func set_accent(name: String) -> void:
	var c: Color = ACCENTS.get(name, ACCENTS["CYAN"])
	ACCENT = c
	ACCENT_DIM = Color(c, 0.35)


static func font(bold := false) -> SystemFont:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Cascadia Mono", "Consolas", "JetBrains Mono", "Courier New", "monospace"])
	f.font_weight = 700 if bold else 400
	f.antialiasing = TextServer.FONT_ANTIALIASING_LCD
	return f


static func panel_box(border := _DEFAULT, bg := PANEL_BG) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = ACCENT_DIM if border == _DEFAULT else border
	sb.set_border_width_all(1)
	sb.set_content_margin_all(14)
	return sb


static func make_theme() -> Theme:
	var theme := Theme.new()
	theme.default_font = font()
	theme.default_font_size = 16

	theme.set_color("font_color", "Label", TEXT)

	var normal := panel_box(ACCENT_DIM, Color(0.03, 0.08, 0.11, 0.7))
	normal.set_content_margin_all(10)
	normal.content_margin_left = 16
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(ACCENT, 0.16)
	hover.border_color = ACCENT
	var pressed := hover.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(ACCENT, 0.3)
	# Focus (controller / keyboard): a bright outline just outside the button.
	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.border_color = ACCENT.lerp(Color.WHITE, 0.5)
	focus.set_border_width_all(2)
	focus.set_expand_margin_all(3)
	theme.set_stylebox("normal", "Button", normal)
	theme.set_stylebox("hover", "Button", hover)
	theme.set_stylebox("pressed", "Button", pressed)
	theme.set_stylebox("hover_pressed", "Button", pressed)
	theme.set_stylebox("focus", "Button", focus)
	theme.set_color("font_color", "Button", TEXT)
	theme.set_color("font_hover_color", "Button", ACCENT)
	theme.set_color("font_pressed_color", "Button", Color.WHITE)
	theme.set_color("font_hover_pressed_color", "Button", Color.WHITE)
	theme.set_constant("h_separation", "Button", 10)
	# Toggles are just the switch, no box behind them.
	var empty := StyleBoxEmpty.new()
	for state in ["normal", "hover", "pressed", "hover_pressed"]:
		theme.set_stylebox(state, "CheckButton", empty)
	theme.set_stylebox("focus", "CheckButton", focus)
	theme.set_stylebox("focus", "HSlider", focus)

	theme.set_stylebox("panel", "PanelContainer", panel_box())

	# Text fields: dark inset with a cyan underline-ish border, brighter when focused.
	var field := panel_box(ACCENT_DIM, Color(0.0, 0.02, 0.04, 0.8))
	field.set_content_margin_all(8)
	var field_focus := field.duplicate() as StyleBoxFlat
	field_focus.border_color = ACCENT
	theme.set_stylebox("normal", "LineEdit", field)
	theme.set_stylebox("focus", "LineEdit", field_focus)
	theme.set_color("font_color", "LineEdit", Color.WHITE)
	theme.set_color("font_placeholder_color", "LineEdit", TEXT_DIM)
	theme.set_color("caret_color", "LineEdit", ACCENT)

	# Slim sliders: a thin rail, a cyan fill and a small square grabber.
	var rail := StyleBoxFlat.new()
	rail.bg_color = Color(ACCENT, 0.15)
	rail.content_margin_top = 2
	rail.content_margin_bottom = 2
	var fill := rail.duplicate() as StyleBoxFlat
	fill.bg_color = ACCENT
	theme.set_stylebox("slider", "HSlider", rail)
	theme.set_stylebox("grabber_area", "HSlider", fill)
	theme.set_stylebox("grabber_area_highlight", "HSlider", fill)
	var grab := Image.create(12, 12, false, Image.FORMAT_RGBA8)
	grab.fill(Color.WHITE)
	var grab_tex := ImageTexture.create_from_image(grab)
	theme.set_icon("grabber", "HSlider", grab_tex)
	theme.set_icon("grabber_highlight", "HSlider", grab_tex)
	return theme


## A Label in the house style.
static func label(text: String, size := 16, color := TEXT, bold := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if bold:
		l.add_theme_font_override("font", font(true))
	return l
