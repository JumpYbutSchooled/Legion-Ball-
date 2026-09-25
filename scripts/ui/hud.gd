extends CanvasLayer
## Multiplayer HUD: health bar (bottom-left), kill feed (top-right), Tab scoreboard,
## "ELIMINATED" overlay while dead, and the winner banner. Reads everything from the
## arena's signals and the Net roster. Added by the arena for the local player online.

const UIStyle := preload("res://scripts/ui/ui_style.gd")
const ModScript := preload("res://scripts/net/moderation.gd")
const FEED_TIME := 5.0
const FEED_MAX := 5

var arena: Node

var _net: Node
var _health_fill: ColorRect
var _health_text: Label
var _feed: VBoxContainer
var _board: PanelContainer
var _board_rows: VBoxContainer
var _center: Label
var _center_sub: Label
var _respawn_left := 0.0
var _feed_items: Array = []  # [label, time_left]


func _ready() -> void:
	layer = 5
	_net = get_tree().root.get_node_or_null("Net")
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UIStyle.make_theme()
	add_child(root)

	# Health bar, bottom-left.
	var hp_box := VBoxContainer.new()
	hp_box.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	hp_box.position = Vector2(28, -70)
	root.add_child(hp_box)
	_health_text = UIStyle.label("INTEGRITY 100", 13, UIStyle.ACCENT)
	hp_box.add_child(_health_text)
	var bar_bg := ColorRect.new()
	bar_bg.color = Color(0.0, 0.05, 0.08, 0.7)
	bar_bg.custom_minimum_size = Vector2(260, 8)
	hp_box.add_child(bar_bg)
	_health_fill = ColorRect.new()
	_health_fill.color = UIStyle.ACCENT
	_health_fill.size = Vector2(260, 8)
	bar_bg.add_child(_health_fill)

	# Kill feed, top-right.
	_feed = VBoxContainer.new()
	_feed.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_feed.position = Vector2(-380, 24)
	_feed.custom_minimum_size = Vector2(356, 0)
	_feed.alignment = BoxContainer.ALIGNMENT_BEGIN
	root.add_child(_feed)

	# Center overlay: eliminated / winner.
	_center = UIStyle.label("", 44, Color.WHITE, true)
	_center.set_anchors_preset(Control.PRESET_CENTER)
	_center.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_center.custom_minimum_size = Vector2(900, 0)
	_center.position = Vector2(-450, -120)
	root.add_child(_center)
	_center_sub = UIStyle.label("", 16, UIStyle.ACCENT)
	_center_sub.set_anchors_preset(Control.PRESET_CENTER)
	_center_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_center_sub.custom_minimum_size = Vector2(900, 0)
	_center_sub.position = Vector2(-450, -58)
	root.add_child(_center_sub)

	# Scoreboard (hold Tab).
	_board = PanelContainer.new()
	_board.set_anchors_preset(Control.PRESET_CENTER)
	_board.custom_minimum_size = Vector2(520, 0)
	_board.position = Vector2(-260, -200)
	_board.visible = false
	root.add_child(_board)
	_board_rows = VBoxContainer.new()
	_board_rows.add_theme_constant_override("separation", 6)
	_board.add_child(_board_rows)

	if arena:
		arena.connect("health_changed", _on_health)
		arena.connect("player_killed", _on_killed)
		arena.connect("player_respawned", _on_respawned)
		arena.connect("match_over", _on_match_over)


func _process(delta: float) -> void:
	_board.visible = Input.is_action_pressed("scoreboard")
	if _board.visible:
		_rebuild_board()
	for i in range(_feed_items.size() - 1, -1, -1):
		_feed_items[i][1] -= delta
		var item: Label = _feed_items[i][0]
		item.modulate.a = clampf(_feed_items[i][1], 0.0, 1.0)
		if _feed_items[i][1] <= 0.0:
			item.queue_free()
			_feed_items.remove_at(i)
	if _respawn_left > 0.0:
		_respawn_left -= delta
		_center_sub.text = "RESPAWNING IN %.1f" % maxf(_respawn_left, 0.0)


func _on_health(id: int, hp: float) -> void:
	if id != multiplayer.get_unique_id():
		return
	var k := clampf(hp / 100.0, 0.0, 1.0)
	var goal_color := UIStyle.ACCENT.lerp(Color(1.0, 0.25, 0.2), 1.0 - k)
	var hurt := 260.0 * k < _health_fill.size.x
	# The bar slides to its new length; taking damage flashes it white first.
	var tw := _health_fill.create_tween().set_parallel().set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_property(_health_fill, "size:x", 260.0 * k, 0.35)
	if hurt:
		_health_fill.color = Color.WHITE
		tw.tween_property(_health_fill, "color", goal_color, 0.3)
		_health_text.pivot_offset = Vector2(0, _health_text.size.y / 2.0)
		_health_text.scale = Vector2(1.15, 1.15)
		tw.tween_property(_health_text, "scale", Vector2.ONE, 0.3)
	else:
		tw.tween_property(_health_fill, "color", goal_color, 0.3)
	_health_text.text = "INTEGRITY %d" % int(maxf(hp, 0.0))


func _on_killed(victim: int, attacker: int) -> void:
	var line := UIStyle.label("%s  >>  %s" % [_name(attacker), _name(victim)], 15, Color.WHITE)
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	line.custom_minimum_size = Vector2(356, 0)
	if attacker == multiplayer.get_unique_id() or victim == multiplayer.get_unique_id():
		line.add_theme_color_override("font_color", UIStyle.ACCENT)
	_feed.add_child(line)
	_feed_items.append([line, FEED_TIME])
	# Slides in from the right edge.
	line.pivot_offset = Vector2(356, 0)
	line.scale = Vector2(0.3, 1.0)
	line.create_tween().set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT) \
		.tween_property(line, "scale", Vector2.ONE, 0.35)
	while _feed_items.size() > FEED_MAX:
		_feed_items[0][0].queue_free()
		_feed_items.remove_at(0)
	if victim == multiplayer.get_unique_id():
		_center.text = "ELIMINATED"
		_center.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
		_center_sub.text = "BY " + _name(attacker)
		_respawn_left = arena.call("get_rules")["respawn_time"]
		_slam_in(_center)


## Big text slams in: starts huge and see-through, snaps to size.
func _slam_in(label: Label) -> void:
	label.pivot_offset = label.size / 2.0
	label.scale = Vector2(2.2, 2.2)
	label.modulate.a = 0.0
	var tw := label.create_tween().set_parallel().set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_property(label, "scale", Vector2.ONE, 0.4)
	tw.tween_property(label, "modulate:a", 1.0, 0.2)


func _on_respawned(id: int) -> void:
	if id == multiplayer.get_unique_id():
		_center.text = ""
		_center_sub.text = ""
		_respawn_left = 0.0


func _on_match_over(winner: int) -> void:
	_respawn_left = 0.0
	var me := winner == multiplayer.get_unique_id()
	_center.text = "VICTORY" if me else _name(winner) + " WINS"
	_center.add_theme_color_override("font_color", UIStyle.ACCENT if me else Color.WHITE)
	_center_sub.text = "RETURNING TO LOBBY..."
	_slam_in(_center)
	_board.visible = true
	_rebuild_board()


func _rebuild_board() -> void:
	for child in _board_rows.get_children():
		child.queue_free()
	_board_rows.add_child(UIStyle.label("// SCOREBOARD   FIRST TO %d" % int(arena.call("get_rules")["kills_to_win"]), 16, UIStyle.ACCENT, true))
	if not _net:
		return
	var roster: Dictionary = _net.get("players")
	var ids := roster.keys()
	ids.sort_custom(func(a: int, b: int) -> bool: return int(roster[a]["kills"]) > int(roster[b]["kills"]))
	for id in ids:
		var row := HBoxContainer.new()
		var swatch := ColorRect.new()
		swatch.color = _net.call("player_color", id)
		swatch.custom_minimum_size = Vector2(8, 18)
		row.add_child(swatch)
		var name_label := UIStyle.label("  " + String(roster[id]["name"]), 16, Color.WHITE if id == multiplayer.get_unique_id() else UIStyle.TEXT)
		name_label.custom_minimum_size = Vector2(210, 0)
		row.add_child(name_label)
		# Staff title in its own colour (gold OWNER, cyan MOD, green TESTER).
		var title := ModScript.title_of(roster[id])
		var title_label := UIStyle.label("[%s]" % title[0] if not title.is_empty() else "", 13, title[1] if not title.is_empty() else UIStyle.TEXT)
		title_label.custom_minimum_size = Vector2(90, 0)
		row.add_child(title_label)
		row.add_child(UIStyle.label("%3d K   %3d D" % [int(roster[id]["kills"]), int(roster[id]["deaths"])], 16, UIStyle.TEXT))
		_board_rows.add_child(row)


func _name(id: int) -> String:
	return _net.call("player_name", id) if _net else "?"
