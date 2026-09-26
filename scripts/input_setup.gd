extends RefCounted
## Every input action the game uses, defined in code rather than only in project.godot,
## so new or changed keybinds can ship in an update (project.godot can't be updated).
## apply() adds any action that's missing and gives it its default keys if it has none,
## then applies the player's own bindings (Settings > Controls, saved in SAVE_PATH).
## Each action has up to SLOTS bindings (e.g. W and Up).

const SAVE_PATH := "user://keybinds.cfg"
const SLOTS := 2

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
	# Staff weapons, and showing/hiding them.
	"weapon_7": [KEY_7],
	"weapon_8": [KEY_8],
	"toggle_staff_weapons": [KEY_0],
	# Owner only: gold invincibility shield.
	"god_shield": [KEY_G],
	"toggle_weapon": [KEY_QUOTELEFT],
	"reload": [KEY_T],
	"reset_ball": [KEY_R],
	"zoom_in": [KEY_I],
	"zoom_out": [KEY_O],
	"camera_left": [],
	"camera_right": [KEY_E],
	"block": [KEY_Q],
	"scoreboard": [KEY_TAB],
	"chat": [KEY_SLASH],
}

## Keys bound to their right-hand copy only (so left Shift stays free).
const RIGHT_KEYS := {
	"chat_global": [KEY_SHIFT],
}

## Keys that moved to another action: stripped from their old action on every start.
## Q used to orbit the camera; it's the shield now.
const REMOVED := {
	"camera_left": [KEY_Q],
}

const MOUSE := {
	"fire": [MOUSE_BUTTON_LEFT],
}

## Controller defaults (Xbox layout names). Buttons, and [axis, direction] for sticks and
## triggers. These sit alongside the keyboard slots: rebinding keys never removes them.
## The right stick turns the camera directly (camera_rig.gd); Start pauses (pause_menu.gd).
const JOY_BUTTONS := {
	"jump": [JOY_BUTTON_A],
	"dash": [JOY_BUTTON_X],
	"block": [JOY_BUTTON_B],
	"toggle_weapon": [JOY_BUTTON_Y],
	"weapon_prev": [JOY_BUTTON_LEFT_SHOULDER],
	"weapon_next": [JOY_BUTTON_RIGHT_SHOULDER],
	"zoom_in": [JOY_BUTTON_DPAD_UP],
	"zoom_out": [JOY_BUTTON_DPAD_DOWN],
	"scoreboard": [JOY_BUTTON_BACK],
}
const JOY_AXES := {
	"move_forward": [[JOY_AXIS_LEFT_Y, -1.0]],
	"move_back": [[JOY_AXIS_LEFT_Y, 1.0]],
	"move_left": [[JOY_AXIS_LEFT_X, -1.0]],
	"move_right": [[JOY_AXIS_LEFT_X, 1.0]],
	"fire": [[JOY_AXIS_TRIGGER_RIGHT, 1.0]],
	"reload": [[JOY_AXIS_TRIGGER_LEFT, 1.0]],
}
## Controller-only actions (not on the Controls page; keyboard uses the mouse wheel).
const PAD_ONLY := ["weapon_prev", "weapon_next"]

## True while the last input came from a controller (set by camera_rig.gd): firing then
## doesn't need a captured mouse.
static var using_pad := false


## Shown on the Controls page under the key bindings.
const PAD_HELP := [
	["LEFT STICK", "Roll"], ["RIGHT STICK", "Camera"], ["A", "Jump"], ["X", "Dash"],
	["B", "Shield"], ["Y", "Holster / draw"], ["RT", "Fire"], ["LT", "Reload / vent"],
	["LB / RB", "Previous / next weapon"], ["D-PAD UP / DOWN", "Zoom"],
	["BACK", "Scoreboard"], ["START", "Pause menu"],
]

## Everything the player can rebind, in the order the Controls page lists it:
## [action, label]; a lone string starts a new section.
const REBINDABLE := [
	"MOVEMENT",
	["move_forward", "Roll forward"],
	["move_back", "Roll back / skid"],
	["move_left", "Roll left"],
	["move_right", "Roll right"],
	["jump", "Jump"],
	["dash", "Dash"],
	["block", "Shield"],
	["reset_ball", "Reset"],
	"COMBAT",
	["fire", "Fire"],
	["reload", "Reload / vent"],
	["toggle_weapon", "Holster / draw"],
	["weapon_1", "Gatling"],
	["weapon_2", "Railgun"],
	["weapon_3", "Scatter"],
	["weapon_4", "Tether"],
	["weapon_5", "Nova"],
	["weapon_6", "Swarm"],
	["weapon_7", "Rain of God (staff)"],
	["weapon_8", "Pillars of God (owner)"],
	["toggle_staff_weapons", "Hide / show staff weapons"],
	["god_shield", "Gold shield (owner)"],
	"CAMERA & HUD",
	["camera_left", "Rotate camera left"],
	["camera_right", "Rotate camera right"],
	["zoom_in", "Zoom in"],
	["zoom_out", "Zoom out"],
	["scoreboard", "Scoreboard"],
	["chat", "Server chat"],
	["chat_global", "Global chat"],
]


static func apply() -> void:
	for action in REMOVED:
		if InputMap.has_action(action):
			for ev in InputMap.action_get_events(action):
				var key := ev as InputEventKey
				if key and REMOVED[action].has(key.physical_keycode):
					InputMap.action_erase_event(action, ev)
	for action in KEYS:
		if _needs_events(action):
			_add_defaults(action)
	for action in RIGHT_KEYS:
		if _needs_events(action):
			_add_defaults(action)
	for action in MOUSE:
		if _needs_events(action):
			_add_defaults(action)
	for action in PAD_ONLY:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.2)
	_load_saved()
	# Controller bindings go on after the saved keys, so every action always has them.
	for action in JOY_BUTTONS.keys() + JOY_AXES.keys():
		if InputMap.has_action(action) and _pad_events(action).is_empty():
			_add_pad_defaults(action)


static func _is_pad(ev: InputEvent) -> bool:
	return ev is InputEventJoypadButton or ev is InputEventJoypadMotion


static func _add_pad_defaults(action: String) -> void:
	for button in JOY_BUTTONS.get(action, []):
		var ev := InputEventJoypadButton.new()
		ev.button_index = button
		ev.device = -1
		InputMap.action_add_event(action, ev)
	for axis in JOY_AXES.get(action, []):
		var ev := InputEventJoypadMotion.new()
		ev.axis = axis[0]
		ev.axis_value = axis[1]
		ev.device = -1
		InputMap.action_add_event(action, ev)


## An action's keyboard and mouse bindings (the rebindable slots), without controller ones.
static func kbm_events(action: String) -> Array[InputEvent]:
	var out: Array[InputEvent] = []
	if InputMap.has_action(action):
		for ev in InputMap.action_get_events(action):
			if not _is_pad(ev):
				out.append(ev)
	return out


static func _pad_events(action: String) -> Array[InputEvent]:
	var out: Array[InputEvent] = []
	if InputMap.has_action(action):
		for ev in InputMap.action_get_events(action):
			if _is_pad(ev):
				out.append(ev)
	return out


static func _needs_events(action: String) -> bool:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.2)
		return true
	return InputMap.action_get_events(action).is_empty()


static func _add_defaults(action: String) -> void:
	for key in KEYS.get(action, []):
		var ev := InputEventKey.new()
		ev.physical_keycode = key
		InputMap.action_add_event(action, ev)
	for key in RIGHT_KEYS.get(action, []):
		var ev := InputEventKey.new()
		ev.physical_keycode = key
		ev.location = KEY_LOCATION_RIGHT
		InputMap.action_add_event(action, ev)
	for button in MOUSE.get(action, []):
		var ev := InputEventMouseButton.new()
		ev.button_index = button
		InputMap.action_add_event(action, ev)


# --- Player's own bindings ------------------------------------------------------------

## Bind slot `slot` (0 or 1) of `action` to `event`. The same key is taken off any other
## action first, so one key never does two things.
static func bind(action: String, slot: int, event: InputEvent) -> void:
	var ev := _clean(event)
	if not ev:
		return
	for entry in REBINDABLE:
		if entry is Array and entry[0] != action:
			for other in InputMap.action_get_events(entry[0]):
				if _same(other, ev):
					InputMap.action_erase_event(entry[0], other)
	var events := kbm_events(action)
	# Already bound in the other slot: just keep one copy.
	events = events.filter(func(e: InputEvent) -> bool: return not _same(e, ev))
	if slot < events.size():
		events[slot] = ev
	else:
		events.append(ev)
	_set_events(action, events)
	save()


static func clear(action: String, slot: int) -> void:
	var events := kbm_events(action)
	if slot < events.size():
		events.remove_at(slot)
		_set_events(action, events)
		save()


## Every action back to its default keys.
static func reset_all() -> void:
	for entry in REBINDABLE:
		if entry is Array:
			InputMap.action_erase_events(entry[0])
			_add_defaults(entry[0])
			_add_pad_defaults(entry[0])
	DirAccess.remove_absolute(SAVE_PATH)


static func save() -> void:
	var file := ConfigFile.new()
	for entry in REBINDABLE:
		if entry is Array:
			var saved: Array = []
			for ev in kbm_events(entry[0]):
				saved.append(_to_dict(ev))
			file.set_value("binds", entry[0], saved)
	file.save(SAVE_PATH)


static func _load_saved() -> void:
	var file := ConfigFile.new()
	if file.load(SAVE_PATH) != OK:
		return
	for action in file.get_section_keys("binds"):
		if not InputMap.has_action(action):
			continue
		var events: Array = []
		for d in file.get_value("binds", action, []):
			var ev := _from_dict(d)
			if ev:
				events.append(ev)
		_set_events(action, events)


## Replaces an action's key/mouse slots; its controller bindings are kept.
static func _set_events(action: String, events: Array) -> void:
	var pad := _pad_events(action)
	InputMap.action_erase_events(action)
	for i in mini(events.size(), SLOTS):
		InputMap.action_add_event(action, events[i])
	for ev in pad:
		InputMap.action_add_event(action, ev)


## Just the key (by position on the keyboard, so it works on any layout) or mouse button.
static func _clean(event: InputEvent) -> InputEvent:
	var key := event as InputEventKey
	if key:
		var ev := InputEventKey.new()
		ev.physical_keycode = key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
		# Only Shift/Ctrl/Alt keep left vs right apart (so right Shift can be its own key).
		if ev.physical_keycode in [KEY_SHIFT, KEY_CTRL, KEY_ALT]:
			ev.location = key.location
		return ev
	var mouse := event as InputEventMouseButton
	if mouse:
		var ev := InputEventMouseButton.new()
		ev.button_index = mouse.button_index
		return ev
	return null


static func _same(a: InputEvent, b: InputEvent) -> bool:
	if a is InputEventKey and b is InputEventKey:
		return a.physical_keycode == b.physical_keycode and a.location == b.location
	if a is InputEventMouseButton and b is InputEventMouseButton:
		return a.button_index == b.button_index
	return false


static func _to_dict(ev: InputEvent) -> Dictionary:
	if ev is InputEventKey:
		return {"key": int(ev.physical_keycode if ev.physical_keycode != KEY_NONE else ev.keycode), "loc": int(ev.location)}
	if ev is InputEventMouseButton:
		return {"mouse": int(ev.button_index)}
	return {}


static func _from_dict(d: Dictionary) -> InputEvent:
	if d.has("key"):
		var ev := InputEventKey.new()
		ev.physical_keycode = int(d["key"]) as Key
		ev.location = int(d.get("loc", 0)) as KeyLocation
		return ev
	if d.has("mouse"):
		var ev := InputEventMouseButton.new()
		ev.button_index = int(d["mouse"]) as MouseButton
		return ev
	return null


# --- Names ----------------------------------------------------------------------------

## "Q", "Right Shift", "Mouse Right"... ("-" if unbound).
static func event_label(ev: InputEvent) -> String:
	var key := ev as InputEventKey
	if key:
		var code := key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
		var shown := DisplayServer.keyboard_get_keycode_from_physical(code) if key.physical_keycode != KEY_NONE else code
		var text := OS.get_keycode_string(shown)
		if text == "":
			text = OS.get_keycode_string(code)
		match key.location:
			KEY_LOCATION_LEFT:
				text = "Left " + text
			KEY_LOCATION_RIGHT:
				text = "Right " + text
		return text.to_upper()
	var mouse := ev as InputEventMouseButton
	if mouse:
		var names := {
			MOUSE_BUTTON_LEFT: "MOUSE LEFT", MOUSE_BUTTON_RIGHT: "MOUSE RIGHT",
			MOUSE_BUTTON_MIDDLE: "MOUSE MIDDLE", MOUSE_BUTTON_XBUTTON1: "MOUSE 4",
			MOUSE_BUTTON_XBUTTON2: "MOUSE 5",
		}
		return names.get(mouse.button_index, "MOUSE %d" % mouse.button_index)
	return "-"


## The first key bound to `action`, for on-screen hints ("SHIELD [Q]").
static func key_label(action: String) -> String:
	var events := kbm_events(action)
	return event_label(events[0]) if not events.is_empty() else "-"
