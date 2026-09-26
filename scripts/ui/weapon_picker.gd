extends Control
## The Armory's weapon picker: pressing one of your six loadout slots opens this window,
## a grid of every weapon (a picture of its blades, grouped by combo group). Hover one
## for its full details (weapon_tooltip); press it to put it in that slot (a weapon you
## already carry swaps places). Esc, B / Circle, or a click outside the window closes it.

signal picked(slot: int, id: String)

const UIStyle := preload("res://scripts/ui/ui_style.gd")
const WeaponInfo := preload("res://scripts/weapon_info.gd")
const WeaponIcons := preload("res://scripts/ui/weapon_icons.gd")
const TILE := 72.0

## Loadout slot being filled (0-5).
var slot := 0
## The loadout as it is now (to mark weapons already carried).
var loadout: Array = []
## Renders the pictures (shared, owned by the menu).
var icons: Node

var _tiles := {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	# Dim everything behind; a click out here closes the window.
	var shade := ColorRect.new()
	shade.color = Color(0.0, 0.01, 0.02, 0.72)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.gui_input.connect(func(e: InputEvent) -> void:
		var click := e as InputEventMouseButton
		if click and click.pressed:
			close())
	add_child(shade)

	var window := PanelContainer.new()
	var style := UIStyle.panel_box(UIStyle.ACCENT, Color(0.02, 0.04, 0.07, 0.96))
	style.set_content_margin_all(18)
	window.add_theme_stylebox_override("panel", style)
	window.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	window.grow_horizontal = Control.GROW_DIRECTION_BOTH
	window.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(window)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	window.add_child(column)
	var current: String = loadout[slot] if slot < loadout.size() else ""
	column.add_child(UIStyle.label("// SLOT %d  //  %s" % [slot + 1, WeaponInfo.by_id(current).get("name", "EMPTY")], 18, UIStyle.ACCENT, true))
	column.add_child(UIStyle.label("HOVER FOR DETAILS  //  PRESS TO EQUIP  //  ESC TO CLOSE", 11, UIStyle.TEXT_DIM))

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(8 * (TILE + 8) + 24, minf(get_viewport_rect().size.y - 220.0, 620.0))
	column.add_child(scroll)
	var groups := VBoxContainer.new()
	groups.add_theme_constant_override("separation", 8)
	groups.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(groups)
	var first: Button = null
	for g in WeaponInfo.GROUPS:
		var group: Dictionary = WeaponInfo.GROUPS[g]
		groups.add_child(UIStyle.label(group["name"], 13, group["color"], true))
		var grid := HFlowContainer.new()
		grid.add_theme_constant_override("h_separation", 8)
		grid.add_theme_constant_override("v_separation", 8)
		groups.add_child(grid)
		for id in WeaponInfo.in_group(g):
			if not WeaponInfo.is_built(id):
				continue
			var tile := _tile(id)
			grid.add_child(tile)
			if not first or id == current:
				first = tile
	var close_button := Button.new()
	close_button.text = "[ CLOSE ]"
	close_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	close_button.pressed.connect(close)
	column.add_child(close_button)
	if icons:
		icons.connect("icon_ready", _on_icon_ready)
	if first:
		first.grab_focus.call_deferred()


func _tile(id: String) -> Button:
	var info := WeaponInfo.by_id(id)
	var color: Color = info["color"]
	var tile := WeaponTile.new()
	tile.weapon_id = id
	tile.custom_minimum_size = Vector2(TILE, TILE)
	tile.focus_mode = Control.FOCUS_ALL
	var normal := UIStyle.panel_box(Color(color, 0.55), Color(color.darkened(0.8), 0.9))
	normal.set_content_margin_all(2)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.border_color = Color.WHITE
	hover.set_border_width_all(2)
	hover.bg_color = Color(color.darkened(0.6), 0.95)
	tile.add_theme_stylebox_override("normal", normal)
	tile.add_theme_stylebox_override("hover", hover)
	tile.add_theme_stylebox_override("pressed", hover)
	tile.add_theme_stylebox_override("focus", hover)
	var picture := TextureRect.new()
	picture.name = "Picture"
	picture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	picture.offset_left = 3
	picture.offset_top = 3
	picture.offset_right = -3
	picture.offset_bottom = -3
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	picture.texture = icons.call("request", id) if icons else null
	tile.add_child(picture)
	# Until the picture's rendered: the weapon's initials.
	var initials := UIStyle.label(_initials(info["name"]), 16, color, true)
	initials.name = "Initials"
	initials.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	initials.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	initials.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	initials.mouse_filter = Control.MOUSE_FILTER_IGNORE
	initials.visible = picture.texture == null
	tile.add_child(initials)
	# Already carried: its key number in the corner.
	var carried := loadout.find(id)
	if carried >= 0:
		var badge := UIStyle.label(str(carried + 1), 13, Color.WHITE, true)
		badge.position = Vector2(5, 2)
		badge.add_theme_color_override("font_outline_color", Color.BLACK)
		badge.add_theme_constant_override("outline_size", 4)
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tile.add_child(badge)
	tile.tooltip_text = id  # Any text: the real tooltip is built by the tile.
	tile.pressed.connect(func() -> void: _pick(id))
	_tiles[id] = tile
	return tile


func _initials(weapon_name: String) -> String:
	var out := ""
	for word in weapon_name.split(" ", false):
		out += word.substr(0, 1)
	return out.substr(0, 3)


func _on_icon_ready(id: String) -> void:
	var tile: Button = _tiles.get(id)
	if not tile or not is_instance_valid(tile):
		return
	var picture: TextureRect = tile.get_node("Picture")
	picture.texture = WeaponIcons.cached(id)
	tile.get_node("Initials").visible = picture.texture == null


func _pick(id: String) -> void:
	picked.emit(slot, id)
	close()


func close() -> void:
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


## A picker tile: its tooltip is a full briefing card in the weapon's colour.
class WeaponTile extends Button:
	var weapon_id := ""

	func _make_custom_tooltip(_for_text: String) -> Object:
		return WeaponTooltip.build(weapon_id)


## The hover card: name, group, what it does, how to use it, what it combos with.
class WeaponTooltip:
	const UIStyle := preload("res://scripts/ui/ui_style.gd")
	const WeaponInfo := preload("res://scripts/weapon_info.gd")

	static func build(id: String) -> Control:
		var info := WeaponInfo.by_id(id)
		var color: Color = info.get("color", Color.WHITE)
		var panel := PanelContainer.new()
		var style := UIStyle.panel_box(color, Color(0.03, 0.02, 0.06, 0.97))
		style.set_border_width_all(2)
		style.set_content_margin_all(12)
		panel.add_theme_stylebox_override("panel", style)
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 3)
		column.custom_minimum_size = Vector2(340, 0)
		panel.add_child(column)
		column.add_child(_line(info.get("name", id), 18, color, true))
		var group_name: String = WeaponInfo.GROUPS[info["group"]]["name"] if info.has("group") else "STAFF WEAPON"
		column.add_child(_line("%s  //  %s" % [group_name, info.get("tag", "")], 11, UIStyle.TEXT_DIM))
		column.add_child(_line(info.get("summary", ""), 13, Color.WHITE))
		if info.has("usage"):
			column.add_child(_line("OPERATION", 11, color.lightened(0.3), true))
			for line in info["usage"]:
				column.add_child(_line("  > " + line, 12, UIStyle.TEXT))
		column.add_child(_line("COMBO", 11, color.lightened(0.3), true))
		column.add_child(_line("  + " + String(info.get("combo", "")), 12, color))
		var partners := WeaponInfo.partners(id)
		if not partners.is_empty():
			var names: Array[String] = []
			for p in partners:
				names.append(WeaponInfo.by_id(p)["name"])
			column.add_child(_line("WORKS WITH  " + ", ".join(PackedStringArray(names)), 11, UIStyle.TEXT_DIM))
		column.add_child(_line("PRESS TO EQUIP", 11, Color(1.0, 0.85, 0.3), true))
		return panel

	static func _line(text: String, size: int, color: Color, bold := false) -> Label:
		var l := UIStyle.label(text, size, color, bold)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(340, 0)
		return l
