extends Node
## Game settings, saved to user://settings.cfg. Autoloaded as "Settings".
## Read with get_value(key); change with set_value(key, value) (saves and emits `changed`).
## Window settings (fullscreen, vsync) are applied here; everything else is read by
## the nodes that use it (camera rig, motion blur, impact frames).

signal changed

const PATH := "user://settings.cfg"
const UIStyle := preload("res://scripts/ui/ui_style.gd")
const Graphics := preload("res://scripts/graphics.gd")
const DEFAULTS := {
	## Multiplier on the base mouse sensitivity.
	"mouse_sensitivity": 1.0,
	"fov": 70.0,
	"motion_blur": 0.5,
	## Multiplier on the speed/dash warp effects.
	"screen_effects": 1.0,
	## Multiplier on camera shake.
	"camera_shake": 1.0,
	"impact_frames": true,
	## Background music volume, 0..1 (scripts/music.gd).
	"music_volume": 0.6,
	## Menu hover/click sounds.
	"ui_sounds": true,
	## The wireframe build-in when a map loads (scripts/map_intro.gd).
	"map_intro": true,
	## The last version whose "what's new" message was shown (main_menu.gd).
	"last_seen_version": "",
	## The first-time tutorial has been finished (or skipped from the welcome panel).
	"tutorial_done": false,
	## Weapon ids for keys 1-6 (weapon_info.gd; empty = the default six). Set in the Armory.
	"loadout": [],
	"player_name": "PLAYER",
	## Last address typed into Join, remembered for next time.
	"last_join_ip": "127.0.0.1",
	## Online server last joined (index into Net.SERVER_URLS).
	"last_server": 0,
	## Moderator code, sent to online servers when joining; the server checks it
	## (scripts/net/moderation.gd). Empty for normal players.
	"mod_code": "",
	## Staff weapons shown in the picker and on keys 7-8 (key 0 toggles).
	"show_staff_weapons": true,
	"fullscreen": false,
	## WINDOWED, BORDERLESS (fills the screen) or FULLSCREEN (exclusive). Replaces the old
	## fullscreen on/off (still read once, from older settings files).
	"window_mode": "",
	## Window size when windowed.
	"resolution": "1600x900",
	## Size of menus and the HUD (1 = normal; Steam Deck starts at 1.2).
	"ui_scale": 0.0,
	## Graphics (graphics.gd): a preset, and the options it sets (each can be changed after).
	"graphics_preset": "HIGH",
	"shadows": true,
	"aa": "MSAA 2X",
	"ssao": true,
	"ssr": false,
	"ssil": false,
	"render_scale": 1.0,
	## Frame cap (0 = none).
	"max_fps": 0,
	## Volumes, 0..1 (music_volume is above).
	"master_volume": 1.0,
	"sfx_volume": 1.0,
	## The speedometer's tier-change sounds (shatter / infinity), 0..1.
	"speedometer_volume": 1.0,
	## Feedback and HUD extras.
	"hit_markers": true,
	"damage_indicators": true,
	"speed_trails": true,
	"show_fps": false,
	## The minimap (top left; M toggles it). Some maps never have one (map has_minimap()).
	"show_minimap": true,
	"invert_mouse_y": false,
	## Aim the camera by tilting a controller with a gyro (DualSense, DualShock 4, Switch Pro).
	"motion_controls": false,
	"motion_sensitivity": 1.0,
	"motion_invert_y": false,
	## Controller right stick: turn (yaw) and look up/down (pitch) speeds.
	"pad_yaw_sensitivity": 1.0,
	"pad_pitch_sensitivity": 1.0,
	## Menu and HUD accent colour (ui_style.gd ACCENTS).
	"ui_color": "CYAN",
	"vsync": true,
}

var _values := {}


func _ready() -> void:
	var file := ConfigFile.new()
	var loaded := file.load(PATH)
	# A damaged settings file (a crash mid-save): fall back to the last good copy.
	if loaded != OK and FileAccess.file_exists(PATH + ".bak"):
		loaded = file.load(PATH + ".bak")
	if loaded == OK:
		for key in DEFAULTS:
			_values[key] = file.get_value("settings", key, DEFAULTS[key])
	# Older settings: fullscreen on/off becomes the window mode.
	if String(get_value("window_mode")) == "":
		_values["window_mode"] = "BORDERLESS" if get_value("fullscreen") else "WINDOWED"
	if float(get_value("ui_scale")) <= 0.0:
		_values["ui_scale"] = 1.2 if OS.get_environment("SteamDeck") == "1" else 1.0
	_apply_window()
	UIStyle.set_accent(String(get_value("ui_color")))
	(func() -> void: Graphics.apply(get_tree())).call_deferred()


func get_value(key: String) -> Variant:
	return _values.get(key, DEFAULTS[key])


func set_value(key: String, value: Variant) -> void:
	_values[key] = value
	# A preset sets every option it covers.
	if key == "graphics_preset" and Graphics.PRESETS.has(value):
		var preset: Dictionary = Graphics.PRESETS[value]
		for k in preset:
			_values[k] = preset[k]
	_save()
	if key in ["fullscreen", "vsync", "window_mode", "resolution", "ui_scale"]:
		_apply_window()
	if key == "ui_color":
		UIStyle.set_accent(String(value))
	if is_inside_tree():
		Graphics.apply(get_tree())
	changed.emit()


func reset_defaults() -> void:
	_values.clear()
	_save()
	_apply_window()
	UIStyle.set_accent(String(get_value("ui_color")))
	Graphics.apply(get_tree())
	changed.emit()


## Written to a temporary file, then swapped in (the old one kept as .bak), so a crash
## or power cut halfway through a save can't wipe everyone's settings.
func _save() -> void:
	var file := ConfigFile.new()
	for key in DEFAULTS:
		file.set_value("settings", key, get_value(key))
	if file.save(PATH + ".tmp") != OK:
		return
	var dir := DirAccess.open("user://")
	if not dir:
		return
	if dir.file_exists(PATH.get_file()):
		dir.copy(PATH, PATH + ".bak")
	dir.rename(PATH + ".tmp", PATH)


func _apply_window() -> void:
	# Leave the window alone in headless runs (tests, exports without a display).
	if DisplayServer.get_name() == "headless":
		return
	var mode := DisplayServer.WINDOW_MODE_WINDOWED
	match String(get_value("window_mode")):
		"BORDERLESS":
			mode = DisplayServer.WINDOW_MODE_FULLSCREEN
		"FULLSCREEN":
			mode = DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	if DisplayServer.window_get_mode() != mode:
		DisplayServer.window_set_mode(mode)
	if mode == DisplayServer.WINDOW_MODE_WINDOWED:
		var parts := String(get_value("resolution")).split("x")
		if parts.size() == 2 and parts[0].is_valid_int() and parts[1].is_valid_int():
			var want := Vector2i(int(parts[0]), int(parts[1]))
			var screen := DisplayServer.screen_get_usable_rect().size
			want = Vector2i(mini(want.x, screen.x), mini(want.y, screen.y))
			if DisplayServer.window_get_size() != want:
				DisplayServer.window_set_size(want)
				DisplayServer.window_set_position(DisplayServer.screen_get_usable_rect().position + (screen - want) / 2)
	var tree := get_tree() if is_inside_tree() else null
	if tree:
		tree.root.content_scale_factor = clampf(float(get_value("ui_scale")), 0.6, 2.0)
	var vsync: bool = get_value("vsync")
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)


## Safe lookup from anywhere: falls back to the default if the autoload isn't there.
static func read(tree: SceneTree, key: String) -> Variant:
	var node := tree.root.get_node_or_null("Settings") if tree else null
	if node:
		return node.call("get_value", key)
	return DEFAULTS[key]
