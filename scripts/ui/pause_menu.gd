extends CanvasLayer
## In-game pause menu (Esc). Pauses the game and shows the shared menu panels
## (Resume / Armory / Controls / Settings / Abort to main menu) over a dimmed view.

const UIStyle := preload("res://scripts/ui/ui_style.gd")
const MenuUI := preload("res://scripts/ui/menu_ui.gd")
const MENU_SCENE := "res://scenes/menu.tscn"
const SceneLoader := preload("res://scripts/ui/scene_loader.gd")

var _root: Control
var _ui: Control
var _title: Label
var _dim: ColorRect
## Open (the root can still be visible for a moment while it fades out).
var _open := false
var _fade: Tween


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.theme = UIStyle.make_theme()
	_root.visible = false
	add_child(_root)

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.0, 0.02, 0.04, 0.45)
	_root.add_child(dim)
	_dim = dim
	var title := UIStyle.label("SIMULATION PAUSED", 48, Color.WHITE, true)
	title.position = Vector2(62, 44)
	_root.add_child(title)
	_title = title
	var sub := UIStyle.label("ALL SYSTEMS HOLDING  //  ESC TO RESUME", 15, UIStyle.ACCENT)
	sub.position = Vector2(68, 110)
	_root.add_child(sub)

	var ui := MenuUI.new()
	ui.pause_mode = true
	_root.add_child(ui)
	_ui = ui
	ui.resume_pressed.connect(resume)
	ui.main_menu_pressed.connect(func() -> void:
		resume()
		var net := _net()
		if net and net.get("online"):
			net.call("quit_to_menu")
		else:
			SceneLoader.go(get_tree(), MENU_SCENE))


func _unhandled_input(event: InputEvent) -> void:
	# Numpad 0 (rebindable): straight to the moderation page (Practice Admin offline).
	if event.is_action_pressed("mod_menu") and not _open and _staff_page_allowed():
		pause()
		_ui.call("_show_page", "moderation")
		get_viewport().set_input_as_handled()
		return
	var pad := event as InputEventJoypadButton
	if pad and pad.pressed and pad.button_index == JOY_BUTTON_START:
		if _open:
			resume()
		else:
			pause()
		get_viewport().set_input_as_handled()
		return
	# ui_cancel includes the controller's B, which is the shield in game: B only backs
	# out of the menu, it never opens it.
	if pad and not _open:
		return
	if event.is_action_pressed("ui_cancel"):
		if _open:
			resume()
		else:
			pause()
		get_viewport().set_input_as_handled()


func _staff_page_allowed() -> bool:
	var net := get_tree().root.get_node_or_null("Net")
	if not net or not net.get("online"):
		return true
	var mod := get_tree().root.get_node_or_null("Mod")
	return mod != null and int(mod.call("my_level")) >= 1


## Offline this freezes the game. Online the match can't stop for one player, so it
## just takes over input (your ball stops being controlled) while the menu is open.
func pause() -> void:
	_open = true
	_root.visible = true
	# The view dims, the title slides in and the menu swells softly into place.
	if _fade and _fade.is_valid():
		_fade.kill()
	_root.modulate.a = 0.0
	_title.position.x = 20.0
	_ui.pivot_offset = _root.size * 0.5
	_ui.scale = Vector2.ONE * 0.95
	_fade = _root.create_tween().set_parallel().set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	_fade.tween_property(_root, "modulate:a", 1.0, 0.22).set_trans(Tween.TRANS_SINE)
	_fade.tween_property(_title, "position:x", 62.0, 0.45)
	_fade.tween_property(_ui, "scale", Vector2.ONE, 0.45)
	var net := _net()
	if net and net.get("online"):
		net.set("input_blocked", true)
	else:
		get_tree().paused = true
	Engine.time_scale = 1.0
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func resume() -> void:
	_open = false
	# Back in control at once; the menu just fades away.
	if _fade and _fade.is_valid():
		_fade.kill()
	_fade = _root.create_tween().set_parallel().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_fade.tween_property(_root, "modulate:a", 0.0, 0.14)
	_fade.tween_property(_ui, "scale", Vector2.ONE * 0.97, 0.14)
	_fade.chain().tween_callback(func() -> void: _root.visible = false)
	get_tree().paused = false
	var net := _net()
	if net:
		net.set("input_blocked", false)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _net() -> Node:
	return get_tree().root.get_node_or_null("Net")
