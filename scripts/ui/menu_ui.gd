extends Control
## The menu panels shared by the main menu and the pause menu: a column of actions on
## the left and a page on the right: SETTINGS, CONTROLS, or ARMORY (weapon briefings),
## plus MODERATION in the pause menu for moderators (scripts/net/moderation.gd).
## Set `pause_mode` before adding it to switch the first action between
## "INITIATE SIMULATION" (main menu) and "RESUME" (pause menu).

signal play_pressed
signal resume_pressed
signal main_menu_pressed
signal quit_pressed

const UIStyle := preload("res://scripts/ui/ui_style.gd")
const WeaponInfo := preload("res://scripts/weapon_info.gd")
const LobbyPanel := preload("res://scripts/ui/lobby_panel.gd")
const NetScript := preload("res://scripts/net/net.gd")
const ModScript := preload("res://scripts/net/moderation.gd")

var pause_mode := false

var _page_holder: PanelContainer
var _page_title: Label
var _page: Control
var _nav_buttons := {}
var _current_page := ""


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 64
	row.offset_right = -64
	row.offset_top = 184
	row.offset_bottom = -36
	row.add_theme_constant_override("separation", 28)
	add_child(row)

	var nav := VBoxContainer.new()
	nav.custom_minimum_size = Vector2(330, 0)
	nav.add_theme_constant_override("separation", 10)
	row.add_child(nav)
	var net := get_tree().root.get_node_or_null("Net")
	var online: bool = net != null and net.get("online")
	if pause_mode:
		_nav(nav, "resume", "RESUME SIMULATION", func() -> void: resume_pressed.emit())
	else:
		_nav(nav, "play", "PRACTICE (SOLO)", func() -> void: play_pressed.emit())
		_nav(nav, "multiplayer", "MULTIPLAYER", func() -> void: _show_page("multiplayer"))
	_nav(nav, "armory", "ARMORY", func() -> void: _show_page("armory"))
	_nav(nav, "controls", "CONTROLS", func() -> void: _show_page("controls"))
	_nav(nav, "settings", "SETTINGS", func() -> void: _show_page("settings"))
	if pause_mode:
		# Shown once the server accepts your moderator code, which can be after this is built.
		_nav(nav, "moderation", "MODERATION", func() -> void: _show_page("moderation"))
		_update_mod_nav()
		var mod := _mod()
		if mod:
			mod.connect("mod_changed", _update_mod_nav)
		if net:
			net.connect("roster_changed", _on_roster_changed)
	if pause_mode:
		var leave_text := "LEAVE MATCH" if online else "ABORT TO MAIN MENU"
		_nav(nav, "menu", leave_text, func() -> void: main_menu_pressed.emit())
	else:
		_nav(nav, "quit", "TERMINATE", func() -> void: quit_pressed.emit())

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	nav.add_child(spacer)
	var f := FileAccess.open("res://version.txt", FileAccess.READ)
	var version := f.get_as_text().strip_edges() if f else "?"
	var link := "ONLINE" if online else "LOCAL"
	nav.add_child(UIStyle.label("SYS.LINK    %s\nBUILD       %s\nNODE        LB-01" % [link, version], 12, UIStyle.TEXT_DIM))

	_page_holder = PanelContainer.new()
	_page_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_page_holder)
	# Back from a match (still connected): land on the lobby.
	_show_page("multiplayer" if online and not pause_mode else "armory")
	_intro.call_deferred()
	visibility_changed.connect(func() -> void:
		if is_visible_in_tree():
			_intro())


## Buttons sweep in one after another; the page panel unfolds.
func _intro() -> void:
	var i := 0
	for id in _nav_buttons:
		var b: Button = _nav_buttons[id]
		b.pivot_offset = Vector2(0.0, b.size.y / 2.0)
		b.modulate.a = 0.0
		b.scale = Vector2(0.6, 1.0)
		var tw := b.create_tween().set_parallel().set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
		tw.tween_property(b, "modulate:a", 1.0, 0.35).set_delay(i * 0.05)
		tw.tween_property(b, "scale", Vector2.ONE, 0.45).set_delay(i * 0.05)
		i += 1
	_page_holder.pivot_offset = Vector2(0.0, 0.0)
	_page_holder.modulate.a = 0.0
	_page_holder.scale = Vector2(1.0, 0.92)
	var tw := _page_holder.create_tween().set_parallel().set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_property(_page_holder, "modulate:a", 1.0, 0.4).set_delay(0.12)
	tw.tween_property(_page_holder, "scale", Vector2.ONE, 0.5).set_delay(0.12)


func _nav(parent: Control, id: String, text: String, action: Callable) -> void:
	var b := Button.new()
	b.text = "[ " + text + " ]"
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override("font_size", 18)
	b.pressed.connect(action)
	parent.add_child(b)
	_nav_buttons[id] = b
	_animate_button(b)


## Hover: the button leans out a little; press: a quick squash.
static func _animate_button(b: Button) -> void:
	b.mouse_entered.connect(func() -> void:
		b.pivot_offset = Vector2(0.0, b.size.y / 2.0)
		b.create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT) \
			.tween_property(b, "scale", Vector2(1.04, 1.04), 0.18))
	b.mouse_exited.connect(func() -> void:
		b.create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT) \
			.tween_property(b, "scale", Vector2.ONE, 0.2))
	b.button_down.connect(func() -> void:
		b.pivot_offset = Vector2(0.0, b.size.y / 2.0)
		var tw := b.create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(b, "scale", Vector2(0.96, 0.92), 0.06)
		tw.tween_property(b, "scale", Vector2(1.04, 1.04), 0.2))


## Page contents cascade in, line by line.
func _animate_page(box: Control) -> void:
	var i := 0
	for child in box.get_children():
		var item := child as CanvasItem
		if not item:
			continue
		item.modulate.a = 0.0
		var tw := item.create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tw.tween_property(item, "modulate:a", 1.0, 0.25).set_delay(minf(i * 0.035, 0.4))
		i += 1


func _show_page(id: String) -> void:
	_current_page = id
	for child in _page_holder.get_children():
		child.queue_free()
	# Pages scroll when they're taller than the window.
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_page_holder.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 14)
	scroll.add_child(box)
	match id:
		"multiplayer":
			_header(box, "MULTIPLAYER", "FREE-FOR-ALL ARENA  //  2-%d PILOTS" % NetScript.MAX_PLAYERS)
			box.add_child(LobbyPanel.new())
		"armory":
			_build_armory(box)
		"controls":
			_build_controls(box)
		"settings":
			_build_settings(box)
		"moderation":
			_build_moderation(box)
	_animate_page(box)
	for key in _nav_buttons:
		var b: Button = _nav_buttons[key]
		b.add_theme_color_override("font_color", UIStyle.ACCENT if key == id else UIStyle.TEXT)


func _header(parent: Control, title: String, sub: String) -> void:
	parent.add_child(UIStyle.label("// " + title, 26, UIStyle.ACCENT, true))
	parent.add_child(UIStyle.label(sub, 13, UIStyle.TEXT_DIM))
	var line := ColorRect.new()
	line.color = UIStyle.ACCENT_DIM
	line.custom_minimum_size = Vector2(0, 1)
	parent.add_child(line)


# --- ARMORY -------------------------------------------------------------------

func _build_armory(box: VBoxContainer) -> void:
	_header(box, "ARMORY", "SIX CRYSTAL WEAPON PLATFORMS  //  KEYS 1-6 OR MOUSE WHEEL + RMB")
	var split := HBoxContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_theme_constant_override("separation", 20)
	box.add_child(split)

	var list := VBoxContainer.new()
	list.custom_minimum_size = Vector2(230, 0)
	list.add_theme_constant_override("separation", 6)
	split.add_child(list)
	var detail := VBoxContainer.new()
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.add_theme_constant_override("separation", 8)
	split.add_child(detail)

	# Owner weapons only show for the owner.
	for slot in WeaponInfo.unlocked_count(get_tree()):
		var info := WeaponInfo.get_entry(slot)
		var b := Button.new()
		b.text = "%02d  %s" % [slot + 1, info["name"]]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_color_override("font_color", info["color"])
		b.add_theme_color_override("font_hover_color", Color.WHITE)
		b.pressed.connect(_show_weapon.bind(detail, slot))
		list.add_child(b)
		_animate_button(b)
	_show_weapon(detail, 0)


func _show_weapon(detail: VBoxContainer, slot: int) -> void:
	for child in detail.get_children():
		child.queue_free()
	var info := WeaponInfo.get_entry(slot)
	var color: Color = info["color"]
	var bar := ColorRect.new()
	bar.color = color
	bar.custom_minimum_size = Vector2(0, 3)
	detail.add_child(bar)
	detail.add_child(UIStyle.label("SLOT %02d  //  %s" % [slot + 1, info["tag"]], 13, color))
	detail.add_child(UIStyle.label(info["name"], 34, Color.WHITE, true))
	var summary := UIStyle.label(info["summary"], 16, UIStyle.TEXT)
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_child(summary)
	detail.add_child(UIStyle.label("OPERATION", 13, UIStyle.TEXT_DIM))
	for line in info["usage"]:
		detail.add_child(UIStyle.label("  > " + line, 15, UIStyle.TEXT))
	detail.add_child(UIStyle.label("COMBO VECTOR", 13, UIStyle.TEXT_DIM))
	var combo := UIStyle.label("  + " + info["combo"], 15, color)
	combo.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_child(combo)
	_animate_page(detail)


# --- CONTROLS -----------------------------------------------------------------

const CONTROLS := [
	["W A S D / ARROWS", "Roll (relative to the camera)"],
	["SPACE", "Jump (1s cooldown)"],
	["Q", "Shield for 1s: blocks all damage. A hit on it strikes back (damage + 5s stun), launches you, explodes and resets the cooldown (6s)"],
	["F", "Dash: redirect all speed where you steer, +40 (in the air, look down to dash down)"],
	["S (against motion)", "Skid: hard brake with sparks"],
	["MOUSE", "Aim / orbit camera (click to lock the mouse)"],
	["LMB", "Fire equipped weapon"],
	["1 - 6", "Equip weapon directly"],
	["MOUSE WHEEL", "Browse weapons (hologram selector)"],
	["RMB", "Confirm the browsed weapon"],
	["`", "Holster / draw weapon"],
	["I / O", "Zoom camera in / out (or CTRL + WHEEL)"],
	["E", "Rotate camera"],
	["R", "Reset (ball, cubes and targets)"],
	["ESC", "Pause menu"],
]


func _build_controls(box: VBoxContainer) -> void:
	_header(box, "CONTROLS", "INPUT MAP  //  KEYBOARD + MOUSE")
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 36)
	grid.add_theme_constant_override("v_separation", 9)
	box.add_child(grid)
	for entry in CONTROLS:
		grid.add_child(UIStyle.label(entry[0], 15, UIStyle.ACCENT, true))
		grid.add_child(UIStyle.label(entry[1], 15, UIStyle.TEXT))
	box.add_child(UIStyle.label("\nCOMBAT NOTES", 13, UIStyle.TEXT_DIM))
	var notes := UIStyle.label(
		"MARKED targets (Swarm) take 1.5x damage from everything for 3s.\n"
		+ "STAGGERED targets and players (Nova) freeze in place for 1.2s.\n"
		+ "Scatter and Nova launch you; Tether reels you back in.", 15, UIStyle.TEXT)
	notes.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(notes)


# --- MODERATION ---------------------------------------------------------------

func _mod() -> Node:
	return get_tree().root.get_node_or_null("Mod")


func _update_mod_nav() -> void:
	var mod := _mod()
	var on: bool = mod != null and mod.call("can_moderate")
	_nav_buttons["moderation"].visible = on
	if not on and _current_page == "moderation":
		_show_page("armory")


## Keeps the player list on the moderation page current.
func _on_roster_changed() -> void:
	if _current_page == "moderation" and is_inside_tree():
		_show_page("moderation")


func _build_moderation(box: VBoxContainer) -> void:
	_header(box, "MODERATION", "KICK OR BAN PLAYERS ON THIS SERVER")
	var mod := _mod()
	var net := get_tree().root.get_node_or_null("Net")
	if not mod or not net or not mod.call("can_moderate"):
		box.add_child(UIStyle.label("Moderator tools are not active.", 15, UIStyle.TEXT_DIM))
		return
	var players: Dictionary = net.get("players")
	var me: int = net.call("local_id")
	var ids := players.keys()
	ids.sort()
	var others := 0
	for id in ids:
		if id == me:
			continue
		others += 1
		var is_mod: bool = players[id].get("mod", false)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var swatch := ColorRect.new()
		swatch.color = net.call("player_color", id)
		swatch.custom_minimum_size = Vector2(10, 18)
		row.add_child(swatch)
		var name_label := UIStyle.label(String(players[id]["name"]), 16, UIStyle.TEXT)
		name_label.custom_minimum_size = Vector2(200, 0)
		row.add_child(name_label)
		var title := ModScript.title_of(players[id])
		var title_label := UIStyle.label("[%s]" % title[0] if not title.is_empty() else "", 14, title[1] if not title.is_empty() else UIStyle.TEXT)
		title_label.custom_minimum_size = Vector2(90, 0)
		row.add_child(title_label)
		if not is_mod:
			row.add_child(_small_button("KICK", func() -> void: mod.call("kick", id)))
			row.add_child(_small_button("BAN", func() -> void: mod.call("ban", id)))
		box.add_child(row)
	if others == 0:
		box.add_child(UIStyle.label("No other players on this server.", 15, UIStyle.TEXT_DIM))
	box.add_child(_small_button("END MATCH", func() -> void: mod.call("end_match")))
	box.add_child(UIStyle.label(
		"END MATCH resets everyone's score and starts a new round.\n"
		+ "Bans last until this server restarts or goes to sleep.", 12, UIStyle.TEXT_DIM))


func _small_button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = "[ " + text + " ]"
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.pressed.connect(action)
	return b


# --- SETTINGS -----------------------------------------------------------------

func _settings() -> Node:
	return get_tree().root.get_node_or_null("Settings")


func _build_settings(box: VBoxContainer) -> void:
	_header(box, "SETTINGS", "CALIBRATION  //  SAVED AUTOMATICALLY")
	var s := _settings()
	if not s:
		box.add_child(UIStyle.label("Settings service offline.", 15, UIStyle.TEXT_DIM))
		return
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 14)
	box.add_child(grid)
	_slider(grid, s, "MOUSE SENSITIVITY", "mouse_sensitivity", 0.2, 3.0, 0.05, "%.2fx")
	_slider(grid, s, "FIELD OF VIEW", "fov", 55.0, 100.0, 1.0, "%d")
	_slider(grid, s, "MOTION BLUR", "motion_blur", 0.0, 1.5, 0.05, "%.2f")
	_slider(grid, s, "SCREEN EFFECTS", "screen_effects", 0.0, 1.5, 0.05, "%.2fx")
	_slider(grid, s, "CAMERA SHAKE", "camera_shake", 0.0, 2.0, 0.05, "%.2fx")
	_toggle(grid, s, "IMPACT FRAMES", "impact_frames")
	_toggle(grid, s, "FULLSCREEN", "fullscreen")
	_toggle(grid, s, "V-SYNC", "vsync")

	# Staff code (owner, moderator or tester): online servers check it when you join.
	var mod_row := HBoxContainer.new()
	mod_row.add_theme_constant_override("separation", 24)
	box.add_child(mod_row)
	mod_row.add_child(UIStyle.label("STAFF CODE", 15, UIStyle.TEXT))
	var code := LineEdit.new()
	code.secret = true
	code.text = s.call("get_value", "mod_code")
	code.placeholder_text = "owner, moderator or tester code"
	code.custom_minimum_size = Vector2(260, 0)
	code.text_changed.connect(func(t: String) -> void: s.call("set_value", "mod_code", t.strip_edges()))
	mod_row.add_child(code)
	var mod := _mod()
	var title: Array = ModScript.TITLES.get(mod.get("role"), []) if mod else []
	if not title.is_empty():
		mod_row.add_child(UIStyle.label(title[0] + " ACTIVE", 15, title[1]))
	box.add_child(UIStyle.label("Checked by the server the next time you join an online server.", 12, UIStyle.TEXT_DIM))

	var reset := Button.new()
	reset.text = "[ RESTORE DEFAULTS ]"
	reset.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	reset.pressed.connect(func() -> void:
		s.call("reset_defaults")
		_show_page("settings"))
	box.add_child(reset)


func _slider(grid: GridContainer, s: Node, title: String, key: String, lo: float, hi: float, step: float, fmt: String) -> void:
	grid.add_child(UIStyle.label(title, 15, UIStyle.TEXT))
	var slider := HSlider.new()
	slider.min_value = lo
	slider.max_value = hi
	slider.step = step
	slider.value = s.call("get_value", key)
	slider.custom_minimum_size = Vector2(260, 20)
	grid.add_child(slider)
	var value := UIStyle.label(fmt % slider.value, 15, UIStyle.ACCENT)
	value.custom_minimum_size = Vector2(70, 0)
	grid.add_child(value)
	slider.value_changed.connect(func(v: float) -> void:
		value.text = fmt % v
		s.call("set_value", key, v))


func _toggle(grid: GridContainer, s: Node, title: String, key: String) -> void:
	grid.add_child(UIStyle.label(title, 15, UIStyle.TEXT))
	var check := CheckButton.new()
	check.button_pressed = s.call("get_value", key)
	grid.add_child(check)
	var state := UIStyle.label("ON" if check.button_pressed else "OFF", 15, UIStyle.ACCENT)
	grid.add_child(state)
	check.toggled.connect(func(on: bool) -> void:
		state.text = "ON" if on else "OFF"
		s.call("set_value", key, on))
