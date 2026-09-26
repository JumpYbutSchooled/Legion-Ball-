extends Control
## The menu panels shared by the main menu and the pause menu: a column of actions on
## the left and a page on the right: SETTINGS, CONTROLS, or ARMORY (weapon briefings),
## plus MODERATION in the pause menu for moderators (scripts/net/moderation.gd).
## Set `pause_mode` before adding it to switch the first action between
## "INITIATE SIMULATION" (main menu) and "RESUME" (pause menu).

## Practice on the map at scene (offline).
signal play_pressed(scene: String)
signal resume_pressed
signal main_menu_pressed
signal quit_pressed

const UIStyle := preload("res://scripts/ui/ui_style.gd")
const WeaponInfo := preload("res://scripts/weapon_info.gd")
const LobbyPanel := preload("res://scripts/ui/lobby_panel.gd")
const NetScript := preload("res://scripts/net/net.gd")
const ModScript := preload("res://scripts/net/moderation.gd")
const InputSetup := preload("res://scripts/input_setup.gd")
const TechFrame := preload("res://scripts/ui/tech_frame.gd")
const Sfx := preload("res://scripts/sfx.gd")
const SettingsScript := preload("res://scripts/settings.gd")
const MenuChat := preload("res://scripts/net/menu_chat.gd")
const GLOBAL_COLOR := Color(1.0, 0.72, 0.3)

var pause_mode := false

## Main menu only: the global chat connection, the open chat page's log, and messages
## that came in while another page was open.
var _chat: Node
var _chat_log: VBoxContainer
var _chat_status: Label
var _unread := 0

var _page_holder: PanelContainer
var _scroll: ScrollContainer
var _frame: Control
var _page_title: Label
var _page: Control
var _nav_buttons := {}
var _current_page := ""


func _ready() -> void:
	# Anchors and offsets both: anchors alone keep the old (zero) offsets, and the menu
	# stayed narrow instead of reaching the right edge of the screen.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
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
		_nav(nav, "play", "PRACTICE (SOLO)", func() -> void: _show_page("practice"))
		_nav(nav, "multiplayer", "MULTIPLAYER", func() -> void: _show_page("multiplayer"))
		_nav(nav, "chat", "GLOBAL CHAT", func() -> void: _show_page("chat"))
		_chat = MenuChat.new()
		_chat.name = "MenuChat"
		add_child(_chat)
		_chat.connect("message_received", _on_chat_message)
		_chat.connect("status_changed", _on_chat_status)
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
		# AI turrets on/off: anyone in practice; online, staff or a LAN game's host.
		_nav(nav, "turrets", "TURRETS: OFF", func() -> void:
			var m := _mod()
			if m:
				m.call("toggle_turrets"))
		var mod := _mod()
		_nav_buttons["turrets"].visible = mod != null and mod.call("can_toggle_turrets")
		if mod:
			mod.connect("mod_changed", func() -> void:
				_nav_buttons["turrets"].visible = mod.call("can_toggle_turrets"))
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
	_frame = TechFrame.new()
	_page_holder.add_child(_frame)
	# Back from a match (still connected): land on the lobby.
	_show_page("multiplayer" if online and not pause_mode else "armory", true)
	_intro.call_deferred()
	visibility_changed.connect(func() -> void:
		if is_visible_in_tree():
			_intro())


## Keeps the turrets button showing whether they're on (the server may take a moment).
func _process(_delta: float) -> void:
	var b: Button = _nav_buttons.get("turrets")
	if b and b.visible and is_visible_in_tree():
		var mod := _mod()
		var on: bool = mod != null and mod.call("turrets_enabled")
		b.text = "[ TURRETS: %s ]" % ("ON" if on else "OFF")


## With a controller, menus are driven by focus: put it on the first action.
func _focus_first() -> void:
	if not is_visible_in_tree() or get_viewport().gui_get_focus_owner():
		return
	for id in _nav_buttons:
		var b: Button = _nav_buttons[id]
		if b.visible:
			b.grab_focus()
			return


func _unhandled_input(event: InputEvent) -> void:
	# First controller press in a menu with nothing focused: start at the top.
	if (event is InputEventJoypadButton and event.pressed) or (event is InputEventJoypadMotion and absf(event.axis_value) > 0.5):
		_focus_first()


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
	if not Input.get_connected_joypads().is_empty():
		_focus_first.call_deferred()


func _nav(parent: Control, id: String, text: String, action: Callable) -> void:
	var b := Button.new()
	b.text = "[ " + text + " ]"
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override("font_size", 18)
	b.pressed.connect(action)
	parent.add_child(b)
	_nav_buttons[id] = b
	_animate_button(b)


## Hover (or controller focus): the button leans out with a tick sound and a quick
## brightness flicker; press: a squash, a white flash and a click.
static func _animate_button(b: Button) -> void:
	var hover := func() -> void:
		b.pivot_offset = Vector2(0.0, b.size.y / 2.0)
		var tw := b.create_tween().set_parallel().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(b, "scale", Vector2(1.04, 1.04), 0.18)
		b.modulate = Color(1.6, 1.6, 1.6)
		tw.tween_property(b, "modulate", Color.WHITE, 0.25).set_trans(Tween.TRANS_EXPO)
		ui_sound(b, "ui_hover", -14.0)
	var unhover := func() -> void:
		b.create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT) \
			.tween_property(b, "scale", Vector2.ONE, 0.2)
	b.mouse_entered.connect(hover)
	b.focus_entered.connect(hover)
	b.mouse_exited.connect(unhover)
	b.focus_exited.connect(unhover)
	b.button_down.connect(func() -> void:
		b.pivot_offset = Vector2(0.0, b.size.y / 2.0)
		var tw := b.create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(b, "scale", Vector2(0.96, 0.92), 0.06)
		tw.tween_property(b, "scale", Vector2(1.04, 1.04), 0.2)
		b.modulate = Color(2.2, 2.2, 2.2)
		b.create_tween().tween_property(b, "modulate", Color.WHITE, 0.3).set_trans(Tween.TRANS_EXPO)
		ui_sound(b, "ui_click", -8.0))


## A menu sound, unless turned off in settings.
static func ui_sound(node: Node, sound: String, volume_db := 0.0) -> void:
	if not node.is_inside_tree():
		return
	var tree := node.get_tree()
	if SettingsScript.read(tree, "ui_sounds"):
		Sfx.play_flat(tree, sound, volume_db, randf_range(0.97, 1.03))


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


func _show_page(id: String, quiet := false) -> void:
	var changed := id != _current_page
	_current_page = id
	_listening = {}
	if _scroll:
		_scroll.queue_free()
	_chat_log = null
	_chat_status = null
	# Pages scroll when they're taller than the window.
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_page_holder.add_child(scroll)
	# The tech frame stays drawn on top of the page.
	_page_holder.move_child(scroll, 0)
	_scroll = scroll
	if changed and not quiet:
		_frame.call("glitch")
		ui_sound(self, "ui_page", -10.0)
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
		"chat":
			_build_chat(box)
		"practice":
			_build_practice(box)
	_animate_page(box)
	for key in _nav_buttons:
		var b: Button = _nav_buttons[key]
		b.add_theme_color_override("font_color", UIStyle.ACCENT if key == id else UIStyle.TEXT)


func _header(parent: Control, title: String, sub: String) -> void:
	parent.add_child(UIStyle.label("// " + title, 26, UIStyle.ACCENT, true))
	parent.add_child(_wrapped(UIStyle.label(sub, 13, UIStyle.TEXT_DIM)))
	var line := ColorRect.new()
	line.color = UIStyle.ACCENT_DIM
	line.custom_minimum_size = Vector2(0, 1)
	parent.add_child(line)


# --- ARMORY -------------------------------------------------------------------

func _build_armory(box: VBoxContainer) -> void:
	_header(box, "ARMORY", "CRYSTAL WEAPON PLATFORMS  //  WEAPON KEYS OR MOUSE WHEEL + RMB")
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

	# Staff weapons only show for staff who have them (and haven't hidden them with 0).
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
	# Every line wraps: the page can't scroll sideways, so one long unwrapped line pushed
	# the whole panel off the right edge of the screen.
	detail.add_child(_wrapped(UIStyle.label("SLOT %02d  //  %s" % [slot + 1, info["tag"]], 13, color)))
	detail.add_child(_wrapped(UIStyle.label(info["name"], 34, Color.WHITE, true)))
	detail.add_child(_wrapped(UIStyle.label(info["summary"], 16, UIStyle.TEXT)))
	detail.add_child(UIStyle.label("OPERATION", 13, UIStyle.TEXT_DIM))
	for line in info["usage"]:
		detail.add_child(_wrapped(UIStyle.label("  > " + line, 15, UIStyle.TEXT)))
	detail.add_child(UIStyle.label("COMBO VECTOR", 13, UIStyle.TEXT_DIM))
	detail.add_child(_wrapped(UIStyle.label("  + " + info["combo"], 15, color)))
	_animate_page(detail)


## Lets a label wrap instead of widening its container.
func _wrapped(label: Label) -> Label:
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label


# --- PRACTICE -------------------------------------------------------------------

const MAP_BLURBS := {
	"res://scenes/arena.tscn": "Target range: cube stacks, drones and dummies to shoot at.",
	"res://scenes/arena_sprawl.tscn": "Huge walled sprawl: a hub, a ring road and six sectors.",
	"res://scenes/arena_coliseum.tscn": "Roman amphitheatre: sand floor, stone tiers, a colonnade.",
	"res://scenes/arena_box.tscn": "Literally just a big box. Pure movement and aim.",
	"res://scenes/arena_thunderdome.tscn": "Steel arena under a lightning-struck dome.",
	"res://scenes/arena_tunnels.tscn": "Underground maze of chambers and corridors. Close quarters.",
	"res://scenes/arena_city.tscn": "Night city: multi-floor garages, skybridges and towers.",
}


func _build_practice(box: VBoxContainer) -> void:
	_header(box, "PRACTICE", "SOLO  //  PICK A MAP  //  NOTHING CAN HURT YOU HERE")
	# AI turrets on the combat maps (also switchable from the pause menu).
	var net := get_tree().root.get_node_or_null("Net")
	if net:
		var turrets := _small_button("", func() -> void: pass)
		var label := func() -> void:
			turrets.text = "[ AI TURRETS: %s ]" % ("ON" if net.get("turrets_on") else "OFF")
		label.call()
		turrets.pressed.connect(func() -> void:
			net.set("turrets_on", not net.get("turrets_on"))
			label.call())
		box.add_child(turrets)
	for path in MAP_BLURBS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 16)
		box.add_child(row)
		var b := _small_button(NetScript.MAP_NAMES.get(path, path), func() -> void: play_pressed.emit(path))
		b.custom_minimum_size = Vector2(220, 0)
		row.add_child(b)
		row.add_child(_wrapped(UIStyle.label(MAP_BLURBS[path], 14, UIStyle.TEXT_DIM)))


# --- GLOBAL CHAT ----------------------------------------------------------------

func _build_chat(box: VBoxContainer) -> void:
	_header(box, "GLOBAL CHAT", "EVERY ONLINE SERVER  //  YOU POST AS YOUR PILOT NAME, TAGGED MENU")
	_unread = 0
	_update_chat_nav()
	_chat_status = UIStyle.label("", 12, UIStyle.TEXT_DIM)
	box.add_child(_chat_status)
	_on_chat_status(_chat.get("status"))
	_chat_log = VBoxContainer.new()
	_chat_log.add_theme_constant_override("separation", 4)
	_chat_log.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(_chat_log)
	for entry in _chat.get("history"):
		_chat_line(entry)
	if (_chat.get("history") as Array).is_empty():
		_chat_log.add_child(UIStyle.label("No messages yet. Say hi.", 14, UIStyle.TEXT_DIM))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	var input := LineEdit.new()
	input.placeholder_text = "message everyone online..."
	input.max_length = 120
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(input)
	var send := func() -> void:
		if input.text.strip_edges() != "":
			_chat.call("send", input.text)
			input.text = ""
			ui_sound(self, "ui_click", -10.0)
	input.text_submitted.connect(func(_t: String) -> void: send.call())
	row.add_child(_small_button("SEND", send))


func _on_chat_message(entry: Dictionary) -> void:
	if _chat_log and is_instance_valid(_chat_log):
		if _chat_log.get_child_count() == 1 and _chat_log.get_child(0) is Label:
			_chat_log.get_child(0).queue_free()  # The "no messages" note.
		_chat_line(entry)
		# Keep the newest in view.
		if _scroll:
			(func() -> void: _scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)).call_deferred()
	else:
		_unread += 1
		_update_chat_nav()


func _on_chat_status(text: String) -> void:
	if _chat_status and is_instance_valid(_chat_status):
		var hints := {
			"CONNECTING": "LINK  //  CONNECTING TO SERVER 1 (can take a minute if it's asleep)...",
			"LINKED": "LINK  //  ONLINE",
			"OUT OF DATE": "LINK  //  YOUR GAME IS OUT OF DATE: restart it to update",
		}
		_chat_status.text = hints.get(text, "LINK  //  " + text)
		_chat_status.add_theme_color_override("font_color", UIStyle.ACCENT if text == "LINKED" else UIStyle.TEXT_DIM)


func _update_chat_nav() -> void:
	var b: Button = _nav_buttons.get("chat")
	if b:
		b.text = "[ GLOBAL CHAT (%d) ]" % _unread if _unread > 0 else "[ GLOBAL CHAT ]"


## One chat line, formatted like the in-game chat box.
func _chat_line(entry: Dictionary) -> void:
	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("normal_font_size", 15)
	label.add_theme_font_override("normal_font", UIStyle.font())
	label.add_theme_font_override("bold_font", UIStyle.font(true))
	var esc := func(s: String) -> String: return s.replace("[", "[lb]")
	var text := "[color=#%s][b][%s][/b][/color] " % [GLOBAL_COLOR.to_html(false), esc.call(String(entry.get("server", "?")))]
	if String(entry.get("title", "")) != "":
		text += "[color=#%s][b][%s][/b][/color] " % [Color(entry.get("title_color", Color.WHITE)).to_html(false), esc.call(String(entry["title"]))]
	text += "[color=#%s][b]%s[/b][/color]: " % [Color(entry.get("color", Color.WHITE)).to_html(false), esc.call(String(entry.get("name", "?")))]
	text += "[color=#%s]%s[/color]" % [UIStyle.TEXT.to_html(false), esc.call(String(entry.get("text", "")))]
	label.text = text
	_chat_log.add_child(label)
	while _chat_log.get_child_count() > MenuChat.HISTORY:
		_chat_log.get_child(0).free()


# --- CONTROLS -----------------------------------------------------------------

## Fixed controls (not rebindable), listed under the key bindings.
const FIXED_CONTROLS := [
	["MOUSE", "Aim / orbit camera (click to lock the mouse)"],
	["MOUSE WHEEL", "Browse weapons (hologram selector); RMB confirms"],
	["CTRL + WHEEL", "Zoom camera"],
	["ESC", "Pause menu / close chat"],
]

## The key binding being changed: {"action", "slot"} (empty when not listening).
var _listening := {}
## Controls page buttons: [action, slot, button].
var _bind_buttons: Array = []


func _build_controls(box: VBoxContainer) -> void:
	_header(box, "CONTROLS", "CLICK A KEY TO CHANGE IT  //  ESC CANCELS, BACKSPACE CLEARS")
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 6)
	box.add_child(grid)
	_bind_buttons.clear()
	for entry in InputSetup.REBINDABLE:
		if entry is String:
			# Section heading across the three columns.
			grid.add_child(UIStyle.label("\n" + entry, 13, UIStyle.TEXT_DIM))
			grid.add_child(Control.new())
			grid.add_child(Control.new())
			continue
		grid.add_child(UIStyle.label(entry[1], 15, UIStyle.TEXT))
		for slot in InputSetup.SLOTS:
			var b := _small_button("", _start_listening.bind(entry[0], slot))
			b.custom_minimum_size = Vector2(170, 0)
			grid.add_child(b)
			_bind_buttons.append([entry[0], slot, b])
	_refresh_bind_buttons()
	var reset := _small_button("RESET ALL CONTROLS", func() -> void:
		InputSetup.reset_all()
		_listening = {}
		_refresh_bind_buttons())
	box.add_child(reset)

	box.add_child(UIStyle.label("\nOTHER CONTROLS", 13, UIStyle.TEXT_DIM))
	var fixed := GridContainer.new()
	fixed.columns = 2
	fixed.add_theme_constant_override("h_separation", 36)
	fixed.add_theme_constant_override("v_separation", 6)
	box.add_child(fixed)
	for entry in FIXED_CONTROLS:
		fixed.add_child(UIStyle.label(entry[0], 15, UIStyle.ACCENT, true))
		fixed.add_child(UIStyle.label(entry[1], 15, UIStyle.TEXT))
	box.add_child(UIStyle.label("\nCONTROLLER", 13, UIStyle.TEXT_DIM))
	var pad := GridContainer.new()
	pad.columns = 4
	pad.add_theme_constant_override("h_separation", 24)
	pad.add_theme_constant_override("v_separation", 6)
	box.add_child(pad)
	for entry in InputSetup.PAD_HELP:
		pad.add_child(UIStyle.label(entry[0], 15, UIStyle.ACCENT, true))
		pad.add_child(UIStyle.label(entry[1], 15, UIStyle.TEXT))
	box.add_child(UIStyle.label("\nCOMBAT NOTES", 13, UIStyle.TEXT_DIM))
	var notes := UIStyle.label(
		"MARKED targets (Swarm) take 1.5x damage from everything for 3s.\n"
		+ "STAGGERED targets and players (Nova) freeze in place for 1.2s.\n"
		+ "Scatter and Nova launch you; Tether reels you back in.", 15, UIStyle.TEXT)
	notes.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(notes)


func _start_listening(action: String, slot: int) -> void:
	_listening = {"action": action, "slot": slot}
	_refresh_bind_buttons()


## Every binding button shows its current key (in place, so the page doesn't scroll).
func _refresh_bind_buttons() -> void:
	for entry in _bind_buttons:
		var b: Button = entry[2]
		if not is_instance_valid(b):
			continue
		var events := InputSetup.kbm_events(entry[0])
		var listening: bool = _listening.get("action", "") == entry[0] and _listening.get("slot", -1) == entry[1]
		var text := "PRESS A KEY..." if listening else (InputSetup.event_label(events[entry[1]]) if entry[1] < events.size() else "-")
		b.text = "[ " + text + " ]"
		b.add_theme_color_override("font_color", UIStyle.ACCENT if listening else UIStyle.TEXT)


## While changing a binding, the next key or mouse button goes to it (and nowhere else).
func _input(event: InputEvent) -> void:
	if _listening.is_empty() or not is_visible_in_tree():
		return
	var key := event as InputEventKey
	var mouse := event as InputEventMouseButton
	if key and (not key.pressed or key.echo):
		return
	if mouse and (not mouse.pressed or mouse.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]):
		return
	if not key and not mouse:
		return
	get_viewport().set_input_as_handled()
	var action: String = _listening["action"]
	var slot: int = _listening["slot"]
	_listening = {}
	if key and key.keycode == KEY_ESCAPE:
		pass  # Cancel.
	elif key and key.keycode in [KEY_BACKSPACE, KEY_DELETE]:
		InputSetup.clear(action, slot)
	else:
		InputSetup.bind(action, slot, event)
	_refresh_bind_buttons()


# --- MODERATION ---------------------------------------------------------------

func _mod() -> Node:
	return get_tree().root.get_node_or_null("Mod")


func _update_mod_nav() -> void:
	var mod := _mod()
	# Testers get the page too (with just their own tools).
	var on: bool = mod != null and int(mod.call("my_level")) >= 1
	_nav_buttons["moderation"].visible = on
	if not on and _current_page == "moderation":
		_show_page("armory")
	elif on and _current_page == "moderation" and is_inside_tree():
		# Staff state changed (a freeze, a weapon lock...): show it.
		_show_page("moderation", true)


## Keeps the player list on the moderation page current.
func _on_roster_changed() -> void:
	if _current_page == "moderation" and is_inside_tree():
		_show_page("moderation", true)


## Staff tools, by level: testers (1) jump to players; moderators (2) also bring, slay,
## freeze, mute, kick, ban, announce, end the match and switch maps; the owner (3) also
## launches players, kills or heals everyone, freezes everyone, low gravity, and picks
## which weapons everyone may use. The server checks every request itself.
func _build_moderation(box: VBoxContainer) -> void:
	_header(box, "MODERATION", "STAFF TOOLS  //  WHAT YOU SEE DEPENDS ON YOUR ROLE")
	var mod := _mod()
	var net := get_tree().root.get_node_or_null("Net")
	var level: int = mod.call("my_level") if mod else 0
	if not mod or not net or level < 1:
		box.add_child(UIStyle.label("Staff tools are not active.", 15, UIStyle.TEXT_DIM))
		return
	var owner_tools: bool = level >= 3 and mod.call("is_owner")
	var gold := Color(1.0, 0.78, 0.25)
	var players: Dictionary = net.get("players")
	var me: int = net.call("local_id")
	var ids := players.keys()
	ids.sort()
	var others := 0
	for id in ids:
		if id == me:
			continue
		others += 1
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var swatch := ColorRect.new()
		swatch.color = net.call("player_color", id)
		swatch.custom_minimum_size = Vector2(10, 18)
		row.add_child(swatch)
		var name_label := UIStyle.label(String(players[id]["name"]), 16, UIStyle.TEXT)
		name_label.custom_minimum_size = Vector2(170, 0)
		row.add_child(name_label)
		var title := ModScript.title_of(players[id])
		var title_label := UIStyle.label("[%s]" % title[0] if not title.is_empty() else "", 14, title[1] if not title.is_empty() else UIStyle.TEXT)
		title_label.custom_minimum_size = Vector2(80, 0)
		row.add_child(title_label)
		var buttons := HFlowContainer.new()
		buttons.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		buttons.add_theme_constant_override("h_separation", 8)
		buttons.add_theme_constant_override("v_separation", 6)
		row.add_child(buttons)
		buttons.add_child(_small_button("GOTO", func() -> void: mod.call("goto", id)))
		if level >= 2:
			buttons.add_child(_small_button("BRING", func() -> void: mod.call("bring", id)))
			if mod.call("can_act_on", players[id]):
				var is_frozen: bool = mod.call("is_frozen", id)
				var is_muted: bool = mod.call("is_muted", id)
				buttons.add_child(_small_button("SLAY", func() -> void: mod.call("slay", id)))
				buttons.add_child(_small_button("UNFREEZE" if is_frozen else "FREEZE", func() -> void: mod.call("set_frozen", id, not is_frozen)))
				buttons.add_child(_small_button("UNMUTE" if is_muted else "MUTE", func() -> void: mod.call("set_muted", id, not is_muted)))
				buttons.add_child(_small_button("KICK", func() -> void: mod.call("kick", id)))
				buttons.add_child(_small_button("BAN", func() -> void: mod.call("ban", id)))
		if owner_tools:
			var launch := _small_button("LAUNCH", func() -> void: mod.call("launch", id))
			launch.add_theme_color_override("font_color", gold)
			buttons.add_child(launch)
		box.add_child(row)
	if others == 0:
		box.add_child(UIStyle.label("No other players on this server.", 15, UIStyle.TEXT_DIM))

	var help := "GOTO jumps you to a player.\n"
	if level >= 2:
		var actions := _flow(box)
		actions.add_child(_small_button("END MATCH", func() -> void: mod.call("end_match")))
		actions.add_child(_small_button("BRING ALL", func() -> void: mod.call("bring", 0)))
		# Announcement: a banner on everyone's screen.
		var say := HBoxContainer.new()
		say.add_theme_constant_override("separation", 10)
		box.add_child(say)
		var text := LineEdit.new()
		text.placeholder_text = "announcement for everyone on the server..."
		text.max_length = 100
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		say.add_child(text)
		var send := func() -> void:
			mod.call("announce", text.text)
			text.text = ""
		text.text_submitted.connect(func(_t: String) -> void: send.call())
		say.add_child(_small_button("ANNOUNCE", send))
		help += "BRING / SLAY / FREEZE / MUTE act on one player; BRING ALL on everyone.\n" \
			+ "SLAY kills without changing scores. MUTE keeps them out of chat.\n" \
			+ "END MATCH resets scores and starts a new round.\n"
	if owner_tools:
		box.add_child(UIStyle.label("\nOWNER", 13, gold))
		var powers := _flow(box)
		var low: bool = mod.get("low_gravity")
		for entry in [
			["KILL ALL", func() -> void: mod.call("kill_all")],
			["HEAL ALL", func() -> void: mod.call("heal_all")],
			["FREEZE ALL", func() -> void: mod.call("set_frozen", 0, true)],
			["UNFREEZE ALL", func() -> void: mod.call("set_frozen", 0, false)],
			["LOW GRAVITY: %s" % ("ON" if low else "OFF"), func() -> void: mod.call("toggle_low_gravity")],
		]:
			var b := _small_button(entry[0], entry[1])
			b.add_theme_color_override("font_color", gold)
			powers.add_child(b)
		# Weapon lock: pick exactly which weapons everyone else may use.
		var mask: int = mod.get("allowed_weapons")
		box.add_child(UIStyle.label("ALLOWED WEAPONS  (click to lock / unlock; yours always work)", 13, UIStyle.TEXT_DIM))
		var guns := _flow(box)
		for slot in 8:
			var info := WeaponInfo.get_entry(slot)
			var allowed := (mask & (1 << slot)) != 0
			var b := _small_button("%d %s: %s" % [slot + 1, info["name"], "ON" if allowed else "LOCKED"],
				func() -> void: mod.call("set_weapons", mask ^ (1 << slot)))
			b.add_theme_color_override("font_color", info["color"] if allowed else Color(1.0, 0.3, 0.3))
			guns.add_child(b)
		guns.add_child(_small_button("ALL ON", func() -> void: mod.call("set_weapons", ModScript.ALL_WEAPONS)))
		guns.add_child(_small_button("ALL LOCKED", func() -> void: mod.call("set_weapons", 0)))
		help += "LAUNCH flings a player skyward. KILL ALL / HEAL ALL / FREEZE ALL affect everyone else.\n" \
			+ "Locked weapons holster and can't be picked; lock all to disarm everyone.\n"
	if level >= 2:
		box.add_child(UIStyle.label("\nSWITCH MAP  (now: %s)" % NetScript.MAP_NAMES.get(net.get("map_scene"), "?"), 13, UIStyle.TEXT_DIM))
		var maps := _flow(box)
		for path in NetScript.MAP_NAMES:
			maps.add_child(_small_button(NetScript.MAP_NAMES[path], func() -> void: mod.call("switch_map", path)))
		help += "SWITCH MAP moves everyone to that map now (scores reset).\n" \
			+ "Bans, mutes and freezes last until this server restarts or goes to sleep.\n"
	box.add_child(UIStyle.label(help, 12, UIStyle.TEXT_DIM))


func _flow(box: Control) -> HFlowContainer:
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 10)
	flow.add_theme_constant_override("v_separation", 8)
	box.add_child(flow)
	return flow

func _small_button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = "[ " + text + " ]"
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.pressed.connect(action)
	_animate_button(b)
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
	_slider(grid, s, "MUSIC VOLUME", "music_volume", 0.0, 1.0, 0.05, "%.2f")
	_toggle(grid, s, "MENU SOUNDS", "ui_sounds")
	_toggle(grid, s, "MAP BUILD-IN", "map_intro")
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
