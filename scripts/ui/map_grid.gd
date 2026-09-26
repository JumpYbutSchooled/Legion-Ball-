extends GridContainer
## Smash-style map select: a grid of map tiles, each a picture of the map
## (res://textures/maps/, from tools/make_map_thumbs.gd) with its name along the bottom,
## plus an optional RANDOM tile. Voters' tokens (little discs in their colours) sit on
## the tile they picked, and your own pick is outlined. Used by the end-of-match vote
## (hud.gd) and the Practice page (menu_ui.gd).

signal picked(path: String)
signal hovered(path: String)

const UIStyle := preload("res://scripts/ui/ui_style.gd")
const NetScript := preload("res://scripts/net/net.gd")
const RANDOM := "random"

## Scene paths to show (and RANDOM, if wanted), in order.
var maps: Array = []
var tile_size := Vector2(170, 100)

var _tiles := {}
var _selected := ""


func _ready() -> void:
	add_theme_constant_override("h_separation", 8)
	add_theme_constant_override("v_separation", 8)
	for path in maps:
		var tile := _tile(path)
		add_child(tile)
		_tiles[path] = tile


## The tile for map `path` (focus it for controllers).
func tile(path: String) -> Button:
	return _tiles.get(path)


## Outline `path` as your pick.
func select(path: String) -> void:
	_selected = path
	for p in _tiles:
		(_tiles[p] as Button).get_node("Frame").visible = p == path


## Voters' colours on each tile: {path: [Color, ...]}.
func set_tokens(tokens: Dictionary) -> void:
	for p in _tiles:
		var row: HBoxContainer = (_tiles[p] as Button).get_node("Tokens")
		for child in row.get_children():
			child.queue_free()
		for c in tokens.get(p, []):
			var token := Panel.new()
			token.custom_minimum_size = Vector2(14, 14)
			var sb := StyleBoxFlat.new()
			sb.bg_color = c
			sb.set_corner_radius_all(7)
			sb.border_color = Color.BLACK
			sb.set_border_width_all(2)
			token.add_theme_stylebox_override("panel", sb)
			token.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(token)


static func thumb_path(path: String) -> String:
	var key := path.get_file().get_basename().trim_prefix("arena_")
	if key == "arena":
		key = "training"  # scenes/arena.tscn, the target range.
	return "res://textures/maps/%s.png" % key


static func map_name(path: String) -> String:
	return "RANDOM" if path == RANDOM else String(NetScript.MAP_NAMES.get(path, path.get_file()))


func _tile(path: String) -> Button:
	var b := Button.new()
	b.custom_minimum_size = tile_size
	b.focus_mode = Control.FOCUS_ALL
	b.clip_contents = true
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.06, 0.09, 0.95)
	style.border_color = UIStyle.ACCENT_DIM
	style.set_border_width_all(1)
	var hover := style.duplicate() as StyleBoxFlat
	hover.border_color = UIStyle.ACCENT
	hover.set_border_width_all(2)
	b.add_theme_stylebox_override("normal", style)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.add_theme_stylebox_override("focus", hover)
	var picture := TextureRect.new()
	picture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var thumb := thumb_path(path)
	if path != RANDOM and ResourceLoader.exists(thumb):
		picture.texture = load(thumb)
	b.add_child(picture)
	if path == RANDOM:
		var q := UIStyle.label("?", 48, UIStyle.ACCENT, true)
		q.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		q.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		q.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(q)
	# Name strip along the bottom.
	var strip := ColorRect.new()
	strip.color = Color(0.0, 0.0, 0.0, 0.7)
	strip.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	strip.offset_top = -22
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(strip)
	var label := UIStyle.label(map_name(path), 12, Color.WHITE, true)
	label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	label.offset_top = -21
	label.offset_left = 6
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(label)
	# Voter tokens along the top.
	var tokens := HBoxContainer.new()
	tokens.name = "Tokens"
	tokens.position = Vector2(4, 4)
	tokens.add_theme_constant_override("separation", 3)
	tokens.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(tokens)
	# Your pick: a bright frame.
	var frame := Panel.new()
	frame.name = "Frame"
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var fs := StyleBoxFlat.new()
	fs.draw_center = false
	fs.border_color = Color.WHITE
	fs.set_border_width_all(3)
	frame.add_theme_stylebox_override("panel", fs)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.visible = false
	b.add_child(frame)
	b.pressed.connect(func() -> void: picked.emit(path))
	b.mouse_entered.connect(func() -> void: hovered.emit(path))
	b.focus_entered.connect(func() -> void: hovered.emit(path))
	return b
