extends CanvasLayer
## Quick moderation (Numpad Enter, rebindable "mod_quick"): a small panel on the right
## listing staff actions on numpad keys 1-9; press one and it happens, the panel closes.
## Only the actions your role allows are listed (the server checks every one anyway).
## In practice everyone gets the practice set (fly, gold shield, launch, low gravity).

const UIStyle := preload("res://scripts/ui/ui_style.gd")
const NetScript := preload("res://scripts/net/net.gd")
const OPEN_TIME := 8.0

var ball: RigidBody3D

var _panel: PanelContainer
var _list: VBoxContainer
var _actions := {}  # numpad digit -> Callable
var _open_left := 0.0


func _ready() -> void:
	layer = 6
	_panel = PanelContainer.new()
	var style := UIStyle.panel_box(Color(1.0, 0.78, 0.25), Color(0.02, 0.04, 0.07, 0.9))
	style.set_content_margin_all(12)
	_panel.add_theme_stylebox_override("panel", style)
	_panel.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	_panel.visible = false
	add_child(_panel)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 4)
	_panel.add_child(_list)


func _process(delta: float) -> void:
	if _panel.visible:
		_open_left -= delta
		if _open_left <= 0.0:
			_panel.visible = false
		var view := _panel.get_viewport_rect().size
		_panel.position = Vector2(view.x - _panel.size.x - 24.0, (view.y - _panel.size.y) / 2.0)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("mod_quick"):
		if _panel.visible:
			_panel.visible = false
		else:
			_open()
		get_viewport().set_input_as_handled()
		return
	var key := event as InputEventKey
	if not _panel.visible or not key or not key.pressed or key.echo:
		return
	if key.physical_keycode == KEY_ESCAPE:
		_panel.visible = false
		get_viewport().set_input_as_handled()
		return
	var digit := key.physical_keycode - KEY_KP_0
	if digit >= 1 and digit <= 9 and _actions.has(digit):
		get_viewport().set_input_as_handled()
		_panel.visible = false
		(_actions[digit] as Callable).call()
		var sfx := get_tree().root.get_node_or_null("Sfx")
		if sfx:
			sfx.call("play_ui", "ui_click", -6.0)


func _open() -> void:
	_build()
	if _actions.is_empty():
		return
	_panel.visible = true
	_open_left = OPEN_TIME


## The actions for this player right now, on fixed numpad keys.
func _build() -> void:
	for child in _list.get_children():
		child.queue_free()
	_actions.clear()
	var net := get_tree().root.get_node_or_null("Net")
	var mod := get_tree().root.get_node_or_null("Mod")
	if not mod:
		return
	var online: bool = net != null and net.get("online")
	var gold := Color(1.0, 0.78, 0.25)
	_list.add_child(UIStyle.label("// QUICK %s" % ("MODERATION" if online else "ADMIN"), 14, gold, true))
	var entries: Array = []
	if not online:
		var low: bool = mod.get("low_gravity")
		entries = [
			[1, "FLY %s" % ("OFF" if ball and ball.get("flying") else "ON"), func() -> void: _toggle_fly()],
			[2, "GOLD SHIELD", func() -> void: mod.call("practice_toggle_god")],
			[3, "LAUNCH ME", func() -> void: mod.call("practice_launch")],
			[7, "LOW GRAVITY %s" % ("OFF" if low else "ON"), func() -> void: mod.call("practice_set_gravity", not low)],
		]
	else:
		var level: int = mod.call("my_level")
		var owner: bool = mod.call("is_owner")
		if level >= 2:
			entries.append([1, "FLY %s" % ("OFF" if ball and ball.get("flying") else "ON"), func() -> void: _toggle_fly()])
		if owner:
			entries.append([2, "GOLD SHIELD", func() -> void: mod.call("toggle_god_shield")])
		if level >= 2:
			entries.append([3, "BRING ALL", func() -> void: mod.call("bring", 0)])
		if owner:
			entries.append([4, "HEAL ALL", func() -> void: mod.call("heal_all")])
			entries.append([5, "FREEZE ALL", func() -> void: mod.call("set_frozen", 0, true)])
			entries.append([6, "UNFREEZE ALL", func() -> void: mod.call("set_frozen", 0, false)])
			var low: bool = mod.get("low_gravity")
			entries.append([7, "LOW GRAVITY %s" % ("OFF" if low else "ON"), func() -> void: mod.call("toggle_low_gravity")])
		# While the owner's on the server, only they change the match.
		var runs_match: bool = owner or not mod.call("owner_present")
		if level >= 1 and runs_match:
			entries.append([8, "NEXT MAP", func() -> void: mod.call("switch_map", _next_map(net))])
		if level >= 2 and runs_match:
			entries.append([9, "END MATCH", func() -> void: mod.call("end_match")])
	for e in entries:
		_actions[e[0]] = e[2]
		_list.add_child(UIStyle.label("[NUM %d]  %s" % [e[0], e[1]], 14, UIStyle.TEXT))
	_list.add_child(UIStyle.label("NUMPAD 0: FULL MENU", 11, UIStyle.TEXT_DIM))


func _toggle_fly() -> void:
	if ball:
		ball.call("set_flying", not ball.get("flying"))


func _next_map(net: Node) -> String:
	var maps: Array = NetScript.COMBAT_MAPS
	var i := maps.find(net.get("map_scene"))
	return maps[(i + 1) % maps.size()]
