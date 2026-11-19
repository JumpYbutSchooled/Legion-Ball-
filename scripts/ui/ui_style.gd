extends RefCounted
## The game's interface style, shared by every menu and the HUD: one clean sans-serif
## typeface (wide-spaced capitals for headings), dark frosted-glass panels with a hairline
## edge, and solid, quiet buttons that light up in the accent colour: a soft fill and edge
## on hover, a full fill with dark text when pressed. No brackets, no decoration that
## isn't information. The big panels are "liquid glass" (glass(): the game blurred behind
## them), and buttons ease in and out on hover and press (ui_motion.gd).

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
## Border colour meaning "the usual hairline" (panel_box's default).
const _DEFAULT := Color(-1, -1, -1, -1)
const TEXT := Color(0.93, 0.95, 0.98)
const TEXT_DIM := Color(0.6, 0.67, 0.74)
## Text on a filled accent button.
const TEXT_ON_ACCENT := Color(0.03, 0.05, 0.08)
const PANEL_BG := Color(0.035, 0.05, 0.075, 0.8)
## The hairline round panels and resting buttons.
const HAIRLINE := Color(1.0, 1.0, 1.0, 0.1)
## Corner rounding: big panels, and buttons / fields / small boxes.
const PANEL_RADIUS := 12
const RADIUS := 6
const GlassShader := preload("res://shaders/glass.gdshader")
## Typefaces, best first: a DIN-style face that ships with Windows, then the usual
## system sans-serifs elsewhere (Steam Deck, Linux).
const FACES := ["Bahnschrift", "Segoe UI", "Inter", "Noto Sans", "DejaVu Sans", "Liberation Sans", "sans-serif"]

static var _fonts := {}


## Switch every menu and HUD built from now on to accent `name` (a key of ACCENTS).
static func set_accent(name: String) -> void:
	var c: Color = ACCENTS.get(name, ACCENTS["CYAN"])
	ACCENT = c
	ACCENT_DIM = Color(c, 0.35)


static func font(bold := false) -> SystemFont:
	var key := "b" if bold else "r"
	if not _fonts.has(key):
		var f := SystemFont.new()
		f.font_names = PackedStringArray(FACES)
		f.font_weight = 700 if bold else 400
		f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
		f.hinting = TextServer.HINTING_LIGHT
		f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO
		_fonts[key] = f
	return _fonts[key]


## The heading face: bold capitals, spaced out a little.
static func heading(spacing := 2) -> Font:
	var key := "h%d" % spacing
	if not _fonts.has(key):
		var f := FontVariation.new()
		f.base_font = font(true)
		f.spacing_glyph = spacing
		_fonts[key] = f
	return _fonts[key]


static func panel_box(border := _DEFAULT, bg := PANEL_BG, radius := RADIUS) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = HAIRLINE if border == _DEFAULT else border
	sb.set_border_width_all(1)
	sb.set_content_margin_all(14)
	sb.set_corner_radius_all(radius)
	sb.corner_detail = 8
	sb.anti_aliasing = true
	return sb


## Makes panel (a PanelContainer, or any Control drawing a "panel" style) liquid glass:
## the game behind it blurred and tinted, bent a little at the rounded edges, with a lit
## rim (shaders/glass.gdshader). tint is the glass colour (its alpha: how much it covers
## what's behind), rim the edge colour. Returns panel.
static func glass(panel: Control, tint := Color(0.03, 0.045, 0.07, 0.66), rim := _DEFAULT, margin := 22, radius := PANEL_RADIUS) -> Control:
	var shape := StyleBoxFlat.new()
	shape.bg_color = Color.WHITE  # only the shape: the shader draws the inside
	shape.set_corner_radius_all(radius)
	shape.corner_detail = 12
	shape.set_content_margin_all(margin)
	panel.add_theme_stylebox_override("panel", shape)
	var mat := ShaderMaterial.new()
	mat.shader = GlassShader
	mat.set_shader_parameter("tint", tint)
	mat.set_shader_parameter("rim", Color(1.0, 1.0, 1.0, 0.22) if rim == _DEFAULT else rim)
	mat.set_shader_parameter("radius", float(radius))
	panel.material = mat
	var fit := func() -> void: mat.set_shader_parameter("size", panel.size)
	panel.resized.connect(fit)
	fit.call()
	return panel


## A button's box: `fill` inside, `edge` round it (`bar` > 0: a thick accent bar down the
## left instead of an edge all round, for lists).
static func button_box(fill: Color, edge: Color, bar := 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.border_color = edge
	if bar > 0:
		sb.border_width_left = bar
	else:
		sb.set_border_width_all(1)
	sb.set_corner_radius_all(RADIUS)
	sb.corner_detail = 6
	sb.anti_aliasing = true
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 9
	sb.content_margin_bottom = 9
	return sb


static func make_theme() -> Theme:
	var theme := Theme.new()
	theme.default_font = font()
	theme.default_font_size = 16

	theme.set_color("font_color", "Label", TEXT)

	# Buttons: quiet at rest, the accent on hover, filled when pressed.
	var normal := button_box(Color(1, 1, 1, 0.06), HAIRLINE)
	var hover := button_box(Color(ACCENT, 0.2), Color(ACCENT, 0.9))
	var pressed := button_box(ACCENT, ACCENT)
	var disabled := button_box(Color(1, 1, 1, 0.025), Color(1, 1, 1, 0.05))
	# Focus (controller / keyboard): a bright outline just outside the button.
	var focus := StyleBoxFlat.new()
	focus.set_corner_radius_all(RADIUS + 2)
	focus.corner_detail = 6
	focus.draw_center = false
	focus.border_color = ACCENT.lerp(Color.WHITE, 0.4)
	focus.set_border_width_all(2)
	focus.set_expand_margin_all(2)
	for kind in ["Button", "OptionButton", "MenuButton"]:
		theme.set_stylebox("normal", kind, normal)
		theme.set_stylebox("hover", kind, hover)
		theme.set_stylebox("pressed", kind, pressed)
		theme.set_stylebox("hover_pressed", kind, pressed)
		theme.set_stylebox("disabled", kind, disabled)
		theme.set_stylebox("focus", kind, focus)
		theme.set_font("font", kind, font(true))
		theme.set_font_size("font_size", kind, 15)
		theme.set_color("font_color", kind, TEXT)
		theme.set_color("font_hover_color", kind, Color.WHITE)
		theme.set_color("font_focus_color", kind, Color.WHITE)
		theme.set_color("font_pressed_color", kind, TEXT_ON_ACCENT)
		theme.set_color("font_hover_pressed_color", kind, TEXT_ON_ACCENT)
		theme.set_color("font_disabled_color", kind, Color(TEXT_DIM, 0.55))
		theme.set_constant("h_separation", kind, 10)
	# Toggles are just the switch, no box behind them.
	var empty := StyleBoxEmpty.new()
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		theme.set_stylebox(state, "CheckButton", empty)
	theme.set_stylebox("focus", "CheckButton", focus)
	theme.set_stylebox("focus", "HSlider", focus)
	_switch_icons(theme)

	theme.set_stylebox("panel", "PanelContainer", panel_box(_DEFAULT, PANEL_BG, PANEL_RADIUS))
	theme.set_stylebox("panel", "PopupPanel", panel_box(_DEFAULT, Color(0.04, 0.055, 0.08, 0.97)))
	theme.set_stylebox("panel", "PopupMenu", panel_box(_DEFAULT, Color(0.04, 0.055, 0.08, 0.97)))
	theme.set_stylebox("hover", "PopupMenu", button_box(Color(ACCENT, 0.2), Color(0, 0, 0, 0)))
	theme.set_stylebox("panel", "TooltipPanel", panel_box(_DEFAULT, Color(0.04, 0.055, 0.08, 0.97)))
	theme.set_color("font_color", "TooltipLabel", TEXT)

	# Text fields: a dark inset, the accent round it when it has focus.
	var field := panel_box(HAIRLINE, Color(0.0, 0.01, 0.025, 0.7))
	field.set_content_margin_all(9)
	field.content_margin_left = 12
	var field_focus := field.duplicate() as StyleBoxFlat
	field_focus.border_color = ACCENT
	for kind in ["LineEdit", "TextEdit"]:
		theme.set_stylebox("normal", kind, field)
		theme.set_stylebox("focus", kind, field_focus)
		theme.set_stylebox("read_only", kind, field)
		theme.set_color("font_color", kind, Color.WHITE)
		theme.set_color("font_placeholder_color", kind, Color(TEXT_DIM, 0.7))
		theme.set_color("caret_color", kind, ACCENT)
		theme.set_color("selection_color", kind, Color(ACCENT, 0.35))

	# Sliders: a thin rail, the accent up to a round knob.
	var rail := StyleBoxFlat.new()
	rail.set_corner_radius_all(3)
	rail.bg_color = Color(1, 1, 1, 0.12)
	rail.content_margin_top = 3
	rail.content_margin_bottom = 3
	var fill := rail.duplicate() as StyleBoxFlat
	fill.bg_color = ACCENT
	theme.set_stylebox("slider", "HSlider", rail)
	theme.set_stylebox("grabber_area", "HSlider", fill)
	theme.set_stylebox("grabber_area_highlight", "HSlider", fill)
	var knob := _disc(16, Color.WHITE)
	theme.set_icon("grabber", "HSlider", knob)
	theme.set_icon("grabber_highlight", "HSlider", knob)

	# Progress bars: the same rail and fill.
	var bar_bg := rail.duplicate() as StyleBoxFlat
	bar_bg.set_corner_radius_all(4)
	var bar_fill := fill.duplicate() as StyleBoxFlat
	bar_fill.set_corner_radius_all(4)
	theme.set_stylebox("background", "ProgressBar", bar_bg)
	theme.set_stylebox("fill", "ProgressBar", bar_fill)

	# Scroll bars: slim and out of the way.
	var track := StyleBoxFlat.new()
	track.bg_color = Color(1, 1, 1, 0.04)
	track.set_corner_radius_all(3)
	track.content_margin_left = 3
	track.content_margin_right = 3
	var thumb := StyleBoxFlat.new()
	thumb.bg_color = Color(1, 1, 1, 0.28)
	thumb.set_corner_radius_all(3)
	var thumb_hot := thumb.duplicate() as StyleBoxFlat
	thumb_hot.bg_color = ACCENT
	for kind in ["VScrollBar", "HScrollBar"]:
		theme.set_stylebox("scroll", kind, track)
		theme.set_stylebox("grabber", kind, thumb)
		theme.set_stylebox("grabber_highlight", kind, thumb_hot)
		theme.set_stylebox("grabber_pressed", kind, thumb_hot)
	return theme


## A soft-edged disc.
static func _disc(size: int, color: Color) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := Vector2(size, size) * 0.5
	for y in size:
		for x in size:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(c)
			img.set_pixel(x, y, Color(color, clampf(size * 0.5 - 0.5 - d, 0.0, 1.0) * color.a))
	return ImageTexture.create_from_image(img)


## The on / off switch for toggles: a pill with a knob at one end, lit in the accent when on.
static func _switch_icons(theme: Theme) -> void:
	var w := 44
	var h := 24
	for on in [false, true]:
		var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
		var track := ACCENT if on else Color(1, 1, 1, 0.16)
		var knob_x := w - h * 0.5 if on else h * 0.5
		for y in h:
			for x in w:
				var p := Vector2(x + 0.5, y + 0.5)
				# Distance to the pill's centre line.
				var cx := clampf(p.x, h * 0.5, w - h * 0.5)
				var d := p.distance_to(Vector2(cx, h * 0.5))
				var a := clampf(h * 0.5 - 0.5 - d, 0.0, 1.0)
				var col := Color(track, track.a * a)
				var k := clampf(h * 0.5 - 3.5 - p.distance_to(Vector2(knob_x, h * 0.5)), 0.0, 1.0)
				var knob := TEXT_ON_ACCENT if on else Color(0.9, 0.93, 0.97)
				col = col.lerp(Color(knob, 1.0), k)
				img.set_pixel(x, y, col)
		var tex := ImageTexture.create_from_image(img)
		for state in ["checked", "checked_disabled"] if on else ["unchecked", "unchecked_disabled"]:
			theme.set_icon(state, "CheckButton", tex)


## A Label in the house style.
static func label(text: String, size := 16, color := TEXT, bold := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if bold:
		l.add_theme_font_override("font", heading(1) if size >= 20 else font(true))
	return l


## A small caption in wide-spaced capitals (section names, field labels).
static func caption(text: String, color := TEXT_DIM) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_override("font", heading(2))
	return l
