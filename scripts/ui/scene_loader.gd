extends CanvasLayer
## Scene changes with a loading card instead of a frozen frame (a service, /root/Loader,
## from scripts/services.gd). Building a map takes a second or so; without this the old
## picture just hangs there. go() shows the card first (one frame online, so the server
## isn't kept waiting; a quick fade offline), then changes scene, and fades the card away
## once the new scene is up and its shaders have been warmed (scripts/shader_warmup.gd).
## Dedicated servers (headless) change straight away.

const UIStyle := preload("res://scripts/ui/ui_style.gd")
## How long to keep the card up after the new scene appears (the warm-up's length).
const SETTLE := 0.7

var _root: Control
var _bg: ColorRect
var _label: Label
var _sub: Label
var _bar: ColorRect
var _busy := false
var _waiting_for: Node
var _settle := -1.0
var _t := 0.0


## Change to `path` with the loading card (or directly, if there's no Loader / no screen).
static func go(tree: SceneTree, path: String) -> void:
	var loader := tree.root.get_node_or_null("Loader")
	if not loader or DisplayServer.get_name() == "headless":
		tree.change_scene_to_file(path)
		return
	loader.call("_go", path)


func _ready() -> void:
	layer = 120
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.visible = false
	add_child(_root)
	_bg = ColorRect.new()
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.color = Color(0.01, 0.02, 0.035)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_bg)
	_label = UIStyle.label("LOADING", 40, Color.WHITE, true)
	_root.add_child(_label)
	_sub = UIStyle.label("", 15, UIStyle.ACCENT, true)
	_root.add_child(_sub)
	_bar = ColorRect.new()
	_bar.color = UIStyle.ACCENT
	_root.add_child(_bar)


func _go(path: String) -> void:
	if _busy:
		get_tree().change_scene_to_file(path)
		return
	_busy = true
	# (Loaded here, not preloaded: net.gd preloads this script.)
	var map_names: Dictionary = load("res://scripts/net/net.gd").MAP_NAMES
	var name: String = map_names.get(path, "")
	_sub.text = ("//  " + name) if name != "" else "//  BALLISTIC"
	_sub.add_theme_color_override("font_color", UIStyle.ACCENT)
	_bar.color = UIStyle.ACCENT
	_root.visible = true
	_t = 0.0
	_layout()
	var net := get_tree().root.get_node_or_null("Net")
	var online: bool = net != null and net.get("online")
	if online:
		# One frame of the card, then load (the server's already moving on).
		_root.modulate.a = 1.0
		await get_tree().process_frame
	else:
		_root.modulate.a = 0.0
		var tw := create_tween()
		tw.tween_property(_root, "modulate:a", 1.0, 0.16).set_trans(Tween.TRANS_SINE)
		await tw.finished
		await get_tree().process_frame
	var old := get_tree().current_scene
	get_tree().change_scene_to_file(path)
	_waiting_for = old
	_settle = -1.0


func _layout() -> void:
	var view := _root.get_viewport_rect().size
	_label.position = Vector2(64, view.y - 140)
	_sub.position = Vector2(68, view.y - 88)
	_bar.size = Vector2(0, 3)
	_bar.position = Vector2(68, view.y - 56)


func _process(delta: float) -> void:
	if not _busy:
		return
	_t += delta
	_layout()
	# A scanning bar under the text while it's up.
	var k := fposmod(_t * 0.9, 1.0)
	_bar.size.x = 260.0 * (0.25 + 0.75 * sin(k * PI))
	_bar.position.x = 68.0 + 260.0 * k * 0.6
	_label.text = "LOADING" + ".".repeat(int(_t * 3.0) % 4)
	var scene := get_tree().current_scene
	if _settle < 0.0:
		# Waiting for the new scene to replace the old one.
		if scene and scene != _waiting_for:
			_settle = SETTLE if scene.has_method("player_ball") else 0.1
		return
	_settle -= delta
	if _settle <= 0.0 and _root.modulate.a >= 1.0:
		var tw := create_tween()
		tw.tween_property(_root, "modulate:a", 0.0, 0.35).set_trans(Tween.TRANS_SINE)
		tw.tween_callback(func() -> void:
			_root.visible = false
			_busy = false)
		_root.modulate.a = 0.999  # only start the fade once
