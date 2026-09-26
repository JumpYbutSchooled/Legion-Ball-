extends CanvasLayer
## Multiplayer HUD: health bar (bottom-left), kill feed (top-right), Tab scoreboard,
## "ELIMINATED" overlay while dead, and the winner banner. Reads everything from the
## arena's signals and the Net roster. Added by the arena for the local player online.

const UIStyle := preload("res://scripts/ui/ui_style.gd")
const ModScript := preload("res://scripts/net/moderation.gd")
const Killstreak := preload("res://scripts/ui/killstreak.gd")
const NetScript := preload("res://scripts/net/net.gd")
const MapGrid := preload("res://scripts/ui/map_grid.gd")
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
var _streak: Control
var _locked_label: Label
var _announce: Label
var _announce_left := 0.0
## End-of-match vote (map grid + mode): the panel, the grid, the mode buttons, our picks.
var _vote_box: PanelContainer
var _vote_grid: GridContainer
var _mode_buttons: Array[Button] = []
var _vote_options: Array = []
var _my_vote := -1
var _my_mode := -1
var _vote_left := 0.0
var _vote_title: Label
## Team game: the score across the top.
var _team_label: RichTextLabel


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

	# Shown while the owner has locked everyone's weapons.
	_locked_label = UIStyle.label("// WEAPONS LOCKED BY OWNER", 14, Color(1.0, 0.78, 0.25), true)
	_locked_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_locked_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_locked_label.custom_minimum_size = Vector2(400, 0)
	_locked_label.position = Vector2(-200, 92)
	_locked_label.visible = false
	root.add_child(_locked_label)
	# Staff announcements: a banner across the top for a few seconds.
	_announce = UIStyle.label("", 22, Color.WHITE, true)
	_announce.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_announce.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_announce.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_announce.custom_minimum_size = Vector2(900, 0)
	_announce.position = Vector2(-450, 120)
	_announce.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_announce.add_theme_constant_override("outline_size", 6)
	root.add_child(_announce)
	var mod_node := get_tree().root.get_node_or_null("Mod")
	if mod_node:
		mod_node.connect("announced", _on_announced)

	# Killstreak skull, top-centre.
	_streak = Killstreak.new()
	_streak.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_streak.position = Vector2(-80, 18)
	root.add_child(_streak)

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

	# The vote for the next round, filling the lower part of the screen (end of a match).
	_vote_box = PanelContainer.new()
	_vote_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_vote_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_vote_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_vote_box.offset_bottom = -24
	_vote_box.visible = false
	root.add_child(_vote_box)

	# Team score, top-centre (team games only).
	_team_label = RichTextLabel.new()
	_team_label.bbcode_enabled = true
	_team_label.fit_content = true
	_team_label.scroll_active = false
	_team_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_team_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_team_label.custom_minimum_size = Vector2(420, 0)
	_team_label.position = Vector2(-210, 8)
	_team_label.add_theme_font_override("normal_font", UIStyle.font(true))
	_team_label.add_theme_font_size_override("normal_font_size", 22)
	_team_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_team_label.visible = false
	root.add_child(_team_label)

	if arena:
		arena.connect("health_changed", _on_health)
		arena.connect("player_killed", _on_killed)
		arena.connect("player_respawned", _on_respawned)
		arena.connect("match_over", _on_match_over)
		arena.connect("vote_opened", _on_vote_opened)
		arena.connect("vote_state", _on_vote_state)
		arena.connect("team_scores_changed", _on_team_scores)
		if arena.call("is_team_game"):
			_team_label.visible = true
			_streak.position.y = 50.0
			_on_team_scores(arena.get("team_scores"))


func _process(delta: float) -> void:
	var mod := get_tree().root.get_node_or_null("Mod")
	_update_staff_status(mod, delta)
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
	if _vote_box.visible:
		_vote_left = maxf(_vote_left - delta, 0.0)
		_refresh_vote()


## One line of whatever staff have imposed on us: frozen, weapons locked or restricted,
## low gravity. And the announcement banner fading out.
func _update_staff_status(mod: Node, delta: float) -> void:
	_announce_left = maxf(_announce_left - delta, 0.0)
	_announce.modulate.a = clampf(_announce_left, 0.0, 1.0)
	var parts: Array[String] = []
	if mod:
		if mod.call("is_frozen", multiplayer.get_unique_id()):
			parts.append("FROZEN BY STAFF")
		if mod.call("my_guns_locked"):
			parts.append("WEAPONS LOCKED")
		elif mod.call("staff_role") != "owner" and not (mod.get("locked_ids") as Array).is_empty():
			parts.append("WEAPONS RESTRICTED")
		if mod.get("low_gravity"):
			parts.append("LOW GRAVITY")
	_locked_label.visible = not parts.is_empty()
	_locked_label.text = "// " + "  //  ".join(parts)


func _on_announced(text: String, by: String) -> void:
	_announce.text = "%s\n— %s" % [text, by]
	_announce_left = 6.0
	_slam_in(_announce)
	var sfx := get_tree().root.get_node_or_null("Sfx")
	if sfx:
		sfx.call("play_ui", "ui_page", -4.0)


## The vote opens: every map as a tile (plus RANDOM), and the two modes above them. Click,
## or move with the arrows / D-pad and press Enter / A. The mouse is freed to click.
func _on_vote_opened(options: Array) -> void:
	for child in _vote_box.get_children():
		child.queue_free()
	_vote_options = options
	_my_vote = -1
	_my_mode = -1
	_vote_left = arena.call("get_rules").get("end_delay", 12.0)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	_vote_box.add_child(column)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	column.add_child(head)
	_vote_title = UIStyle.label("", 16, UIStyle.ACCENT, true)
	_vote_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_vote_title)
	_mode_buttons.clear()
	for i in NetScript.MODES.size():
		var b := Button.new()
		b.text = "[ %s ]" % NetScript.MODE_NAMES[NetScript.MODES[i]]
		b.pressed.connect(_vote_mode.bind(i))
		head.add_child(b)
		_mode_buttons.append(b)
	var grid := MapGrid.new()
	grid.maps = options
	grid.columns = 6
	grid.tile_size = Vector2(150, 88)
	grid.picked.connect(func(path: String) -> void: _vote(options.find(path)))
	column.add_child(grid)
	_vote_grid = grid
	column.add_child(UIStyle.label("CLICK A MAP AND A MODE  //  ARROWS OR D-PAD + ENTER / A", 11, UIStyle.TEXT_DIM))
	_vote_box.visible = true
	_center_sub.text = ""  # The vote panel says it all (and would cover it).
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var here: String = _net.get("map_scene") if _net else ""
	var first := grid.tile(here) if grid.tile(here) else grid.tile(options[0])
	if first:
		first.grab_focus.call_deferred()
	_refresh_vote()


func _on_vote_state(map_votes: Dictionary, mode_votes: Dictionary) -> void:
	if not _vote_grid or not is_instance_valid(_vote_grid):
		return
	var tokens := {}
	for peer in map_votes:
		var i: int = map_votes[peer]
		if i >= 0 and i < _vote_options.size():
			var path: String = _vote_options[i]
			if not tokens.has(path):
				tokens[path] = []
			tokens[path].append(_net.call("player_color", peer) if _net else Color.WHITE)
	_vote_grid.call("set_tokens", tokens)
	var counts := [0, 0]
	for peer in mode_votes:
		var m: int = mode_votes[peer]
		if m >= 0 and m < counts.size():
			counts[m] += 1
	for i in _mode_buttons.size():
		_mode_buttons[i].text = "[ %s ]%s" % [NetScript.MODE_NAMES[NetScript.MODES[i]], "  " + "■".repeat(counts[i]) if counts[i] > 0 else ""]


func _vote(index: int) -> void:
	if index < 0 or _my_vote == index:
		return
	_my_vote = index
	arena.call("cast_vote", index)
	if _vote_grid:
		_vote_grid.call("select", _vote_options[index])
	_click()


func _vote_mode(index: int) -> void:
	if _my_mode == index:
		return
	_my_mode = index
	arena.call("cast_mode_vote", index)
	for i in _mode_buttons.size():
		_mode_buttons[i].add_theme_color_override("font_color", UIStyle.ACCENT if i == index else UIStyle.TEXT)
	_click()


func _click() -> void:
	var sfx := get_tree().root.get_node_or_null("Sfx")
	if sfx:
		sfx.call("play_ui", "ui_click", -8.0)


func _refresh_vote() -> void:
	if _vote_title:
		_vote_title.text = "// NEXT ROUND: PICK A MAP AND A MODE   %ds" % ceili(_vote_left)


## Team game: "RED 12 — 9 BLUE" across the top.
func _on_team_scores(scores: Array) -> void:
	if scores.size() < 2:
		return
	var red := NetScript.TEAM_COLORS[0].to_html(false)
	var blue := NetScript.TEAM_COLORS[1].to_html(false)
	_team_label.text = "[center][color=#%s]RED %d[/color]  [color=#%s]—[/color]  [color=#%s]%d BLUE[/color][/center]" % [red, scores[0], UIStyle.TEXT_DIM.to_html(false), blue, scores[1]]

func _on_health(id: int, hp: float) -> void:
	if id != multiplayer.get_unique_id():
		return
	var full: float = arena.call("max_health_of", id) if arena else 100.0
	var k := clampf(hp / full, 0.0, 1.0)
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
	# Nobody to blame (fell off the map): "NAME  >>  THE VOID".
	var solo := attacker == victim
	var text := "%s  >>  THE VOID" % _name(victim) if solo else "%s  >>  %s" % [_name(attacker), _name(victim)]
	var line := UIStyle.label(text, 15, Color.WHITE)
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
	if attacker == multiplayer.get_unique_id() and not solo:
		_streak.call("add_kill")
	if victim == multiplayer.get_unique_id():
		_streak.call("reset")
		_center.text = "ELIMINATED"
		_center.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
		_center_sub.text = "LOST TO THE VOID" if solo else "BY " + _name(attacker)
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
	if winner == -1 or winner == -2:
		# A team won (-1 red, -2 blue; bots' ids are -1000 and below).
		var team := -1 - winner
		me = _net != null and int(_net.call("team_of", multiplayer.get_unique_id())) == team
		_center.text = "VICTORY" if me else "%s TEAM WINS" % NetScript.TEAM_NAMES[team]
	_center.add_theme_color_override("font_color", UIStyle.ACCENT if me else Color.WHITE)
	var dedicated_server: bool = _net != null and not _net.call("is_host")
	_center_sub.text = "VOTE FOR THE NEXT MAP" if dedicated_server else "RETURNING TO LOBBY..."
	_slam_in(_center)
	_board.visible = true
	_rebuild_board()


func _rebuild_board() -> void:
	for child in _board_rows.get_children():
		child.queue_free()
	var rules: Dictionary = arena.call("get_rules")
	var teams: bool = rules.get("mode", "ffa") == "teams"
	var time := int(arena.call("match_time"))
	_board_rows.add_child(UIStyle.label("// SCOREBOARD  //  %s  //  FIRST TO %d" % [NetScript.MODE_NAMES["teams" if teams else "ffa"], int(rules["kills_to_win"])], 16, UIStyle.ACCENT, true))
	_board_rows.add_child(UIStyle.label("MATCH TIME  %02d:%02d" % [time / 60, time % 60], 14, UIStyle.TEXT))
	if not _net:
		return
	var roster: Dictionary = _net.get("players")
	var ids := roster.keys()
	ids.sort_custom(func(a: int, b: int) -> bool: return int(roster[a]["kills"]) > int(roster[b]["kills"]))
	if not teams:
		for id in ids:
			_board_row(id, roster)
		return
	var scores: Array = arena.get("team_scores")
	for team in 2:
		_board_rows.add_child(UIStyle.label("%s TEAM  %d" % [NetScript.TEAM_NAMES[team], scores[team]], 15, NetScript.TEAM_COLORS[team], true))
		for id in ids:
			if int(_net.call("team_of", id)) == team:
				_board_row(id, roster)


func _board_row(id: int, roster: Dictionary) -> void:
	var row := HBoxContainer.new()
	var swatch := ColorRect.new()
	swatch.color = _net.call("player_color", id)
	swatch.custom_minimum_size = Vector2(8, 18)
	row.add_child(swatch)
	var name_label := UIStyle.label("  " + String(roster[id]["name"]), 16, Color.WHITE if id == multiplayer.get_unique_id() else UIStyle.TEXT)
	name_label.custom_minimum_size = Vector2(210, 0)
	row.add_child(name_label)
	# Staff title in its own colour (gold OWNER, cyan MOD, green TESTER), or BOT.
	var title := ModScript.title_of(roster[id])
	var tag := "[%s]" % title[0] if not title.is_empty() else ("[BOT]" if roster[id].get("bot", false) else "")
	var title_label := UIStyle.label(tag, 13, title[1] if not title.is_empty() else UIStyle.TEXT_DIM)
	title_label.custom_minimum_size = Vector2(90, 0)
	row.add_child(title_label)
	row.add_child(UIStyle.label("%3d K   %3d D" % [int(roster[id]["kills"]), int(roster[id]["deaths"])], 16, UIStyle.TEXT))
	_board_rows.add_child(row)

func _name(id: int) -> String:
	return _net.call("player_name", id) if _net else "?"
