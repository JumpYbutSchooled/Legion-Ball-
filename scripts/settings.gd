extends Node
## Game settings, saved to user://settings.cfg. Autoloaded as "Settings".
## Read with get_value(key); change with set_value(key, value) (saves and emits `changed`).
## Window settings (fullscreen, vsync) are applied here; everything else is read by
## the nodes that use it (camera rig, motion blur, impact frames).

signal changed

const PATH := "user://settings.cfg"
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
	"vsync": true,
}

var _values := {}


func _ready() -> void:
	var file := ConfigFile.new()
	if file.load(PATH) == OK:
		for key in DEFAULTS:
			_values[key] = file.get_value("settings", key, DEFAULTS[key])
	_apply_window()


func get_value(key: String) -> Variant:
	return _values.get(key, DEFAULTS[key])


func set_value(key: String, value: Variant) -> void:
	_values[key] = value
	_save()
	if key == "fullscreen" or key == "vsync":
		_apply_window()
	changed.emit()


func reset_defaults() -> void:
	_values.clear()
	_save()
	_apply_window()
	changed.emit()


func _save() -> void:
	var file := ConfigFile.new()
	for key in DEFAULTS:
		file.set_value("settings", key, get_value(key))
	file.save(PATH)


func _apply_window() -> void:
	# Leave the window alone in headless runs (tests, exports without a display).
	if DisplayServer.get_name() == "headless":
		return
	var full: bool = get_value("fullscreen")
	var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if full else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != mode:
		DisplayServer.window_set_mode(mode)
	var vsync: bool = get_value("vsync")
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)


## Safe lookup from anywhere: falls back to the default if the autoload isn't there.
static func read(tree: SceneTree, key: String) -> Variant:
	var node := tree.root.get_node_or_null("Settings") if tree else null
	if node:
		return node.call("get_value", key)
	return DEFAULTS[key]
