extends CanvasLayer
## The first-time tutorial (practice on the Training map, started from the main menu's
## welcome panel or the Practice page). One step at a time across the top of the screen,
## each showing the player's own key (or controller button), ticked off the moment they
## do it. At the end it marks the tutorial done (Settings tutorial_done).

const UIStyle := preload("res://scripts/ui/ui_style.gd")
const InputSetup := preload("res://scripts/input_setup.gd")
const Sfx := preload("res://scripts/sfx.gd")

## [title, what to do, the action whose key/button to show ("" = none)].
const STEPS := [
	["MOVE", "Roll around: %s", "move"],
	["JUMP", "Jump: %s", "jump"],
	["DASH", "Dash in the direction you're rolling: %s", "dash"],
	["GET FAST", "Hold a direction and keep dashing: get the speedometer past 200", ""],
	["FIRE", "Shoot the targets: %s  (weapons draw themselves)", "fire"],
	["SWITCH WEAPONS", "Pick another weapon: %s  (or scroll the mouse wheel)", "weapon_2"],
	["SHIELD", "Raise your shield: %s  (block a shot and it strikes back)", "block"],
	["HOLSTER", "Put your weapon away: %s  (online, holstered + fast = healing)", "toggle_weapon"],
]

var ball: RigidBody3D

var _step := 0
var _start := Vector3.ZERO
var _done_t := 0.0
var _title: Label
var _text: Label
var _count: Label
var _panel: PanelContainer


func _ready() -> void:
	layer = 7
	_panel = PanelContainer.new()
	var style := UIStyle.panel_box(UIStyle.ACCENT, Color(0.02, 0.04, 0.07, 0.88))
	style.set_content_margin_all(14)
	_panel.add_theme_stylebox_override("panel", style)
	_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_panel.custom_minimum_size = Vector2(620, 0)
	_panel.position = Vector2(-310, 40)
	add_child(_panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	_panel.add_child(col)
	var head := HBoxContainer.new()
	col.add_child(head)
	_title = UIStyle.label("", 20, UIStyle.ACCENT, true)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	_count = UIStyle.label("", 13, UIStyle.TEXT_DIM)
	head.add_child(_count)
	_text = UIStyle.label("", 17, Color.WHITE)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_text)
	col.add_child(UIStyle.label("TUTORIAL  //  ESC / START: pause menu (leave any time)", 11, UIStyle.TEXT_DIM))
	if ball:
		_start = ball.global_position
	_show()


func _key(action: String) -> String:
	if action == "move":
		return "[%s %s %s %s]" % [_one("move_forward"), _one("move_left"), _one("move_back"), _one("move_right")] if not InputSetup.using_pad else "[LEFT STICK]"
	return "[%s]" % _one(action)


func _one(action: String) -> String:
	if InputSetup.using_pad:
		for ev in InputMap.action_get_events(action):
			if ev is InputEventJoypadButton:
				var names := {JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",
					JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB", JOY_BUTTON_BACK: "BACK", JOY_BUTTON_START: "START"}
				return names.get((ev as InputEventJoypadButton).button_index, "PAD")
			if ev is InputEventJoypadMotion:
				return "RT" if (ev as InputEventJoypadMotion).axis == JOY_AXIS_TRIGGER_RIGHT else "LT"
	return InputSetup.key_label(action)


func _show() -> void:
	if _step >= STEPS.size():
		_title.text = "YOU'RE READY"
		_text.text = "That's everything you need. Try the other practice maps, or jump into MULTIPLAYER from the main menu."
		_count.text = ""
		return
	var s: Array = STEPS[_step]
	_title.text = "%s" % s[0]
	var action: String = s[2]
	_text.text = String(s[1]) % _key(action) if action != "" else String(s[1])
	_count.text = "STEP %d / %d" % [_step + 1, STEPS.size()]


func _physics_process(delta: float) -> void:
	if not ball or not is_instance_valid(ball):
		return
	if _step >= STEPS.size():
		_done_t += delta
		if _done_t > 8.0:
			_panel.modulate.a = move_toward(_panel.modulate.a, 0.0, delta)
		return
	var weapon: Node = ball.get_node_or_null("Weapon")
	var done := false
	match _step:
		0: done = ball.global_position.distance_to(_start) > 15.0
		1: done = Input.is_action_just_pressed("jump")
		2: done = Input.is_action_just_pressed("dash")
		3: done = ball.linear_velocity.length() * 5.0 > 200.0
		4: done = Input.is_action_just_pressed("fire") and weapon != null and weapon.call("is_drawn")
		5: done = weapon != null and int(weapon.get("current")) != 0
		6: done = Input.is_action_just_pressed("block")
		7: done = Input.is_action_just_pressed("toggle_weapon")
	if done:
		_step += 1
		Sfx.play_flat(get_tree(), "ui_click", -4.0, 1.2)
		_panel.pivot_offset = _panel.size / 2.0
		_panel.scale = Vector2(1.06, 1.06)
		_panel.create_tween().tween_property(_panel, "scale", Vector2.ONE, 0.25)
		if _step >= STEPS.size():
			var settings := get_tree().root.get_node_or_null("Settings")
			if settings:
				settings.call("set_value", "tutorial_done", true)
		_show()
