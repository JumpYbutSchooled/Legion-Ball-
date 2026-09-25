extends RefCounted
## Every input action the game uses, defined in code rather than only in project.godot,
## so new or changed keybinds can ship in an update (project.godot can't be updated).
## apply() adds any action that's missing and gives it its default keys if it has none;
## it never touches actions that already have bindings.

const KEYS := {
	"move_forward": [KEY_W, KEY_UP],
	"move_back": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"jump": [KEY_SPACE],
	"dash": [KEY_F],
	"weapon_1": [KEY_1],
	"weapon_2": [KEY_2],
	"weapon_3": [KEY_3],
	"weapon_4": [KEY_4],
	"weapon_5": [KEY_5],
	"weapon_6": [KEY_6],
	"toggle_weapon": [KEY_QUOTELEFT],
	"reset_ball": [KEY_R],
	"zoom_in": [KEY_I],
	"zoom_out": [KEY_O],
	"camera_left": [],
	"camera_right": [KEY_E],
	"block": [KEY_Q],
	"scoreboard": [KEY_TAB],
}

## Keys that moved to another action: stripped from their old action on every start.
## Q used to orbit the camera; it's the shield now.
const REMOVED := {
	"camera_left": [KEY_Q],
}

const MOUSE := {
	"fire": [MOUSE_BUTTON_LEFT],
}


static func apply() -> void:
	for action in REMOVED:
		if InputMap.has_action(action):
			for ev in InputMap.action_get_events(action):
				var key := ev as InputEventKey
				if key and REMOVED[action].has(key.physical_keycode):
					InputMap.action_erase_event(action, ev)
	for action in KEYS:
		if _needs_events(action):
			for key in KEYS[action]:
				var ev := InputEventKey.new()
				ev.physical_keycode = key
				InputMap.action_add_event(action, ev)
	for action in MOUSE:
		if _needs_events(action):
			for button in MOUSE[action]:
				var ev := InputEventMouseButton.new()
				ev.button_index = button
				InputMap.action_add_event(action, ev)


static func _needs_events(action: String) -> bool:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.2)
		return true
	return InputMap.action_get_events(action).is_empty()
