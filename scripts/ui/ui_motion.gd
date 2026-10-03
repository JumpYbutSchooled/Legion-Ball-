extends Node
## Smooth motion for every button in the game (a service, scripts/services.gd): each one
## eases a little bigger and brighter on hover or controller focus, squishes when
## pressed and springs back. Buttons are hooked as they're created (SceneTree
## node_added), so no menu needs to do anything. A button with the "ui_motion" meta
## already set (the main menu's nav buttons, which have their own lean-out) is skipped.

const HOVER_SCALE := 1.035
const PRESS_SCALE := 0.95
const HOVER_TIME := 0.16


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if DisplayServer.get_name() == "headless":
		return
	get_tree().node_added.connect(_on_node_added)


func _on_node_added(node: Node) -> void:
	if node is BaseButton:
		# Next frame: whoever made it has finished setting it up (and may opt out).
		_hook.call_deferred(node)


func _hook(node: Variant) -> void:
	# Untyped: it may have been freed before this ran.
	if not is_instance_valid(node):
		return
	var b := node as BaseButton
	if b.has_meta("ui_motion") or b is CheckButton or b is CheckBox:
		return
	b.set_meta("ui_motion", true)
	b.mouse_entered.connect(_to.bind(b, HOVER_SCALE, 1.12))
	b.focus_entered.connect(_to.bind(b, HOVER_SCALE, 1.12))
	b.mouse_exited.connect(_rest.bind(b))
	b.focus_exited.connect(_rest.bind(b))
	b.button_down.connect(_to.bind(b, PRESS_SCALE, 1.2, 0.07))
	b.button_up.connect(_release.bind(b))
	b.resized.connect(func() -> void: b.pivot_offset = b.size * 0.5)
	b.pivot_offset = b.size * 0.5


## Ease `b` to `scale_to` and brightness `glow`.
func _to(b: BaseButton, scale_to: float, glow: float, time := HOVER_TIME) -> void:
	if not is_instance_valid(b) or not b.is_inside_tree() or b.disabled:
		return
	var old: Tween = b.get_meta("ui_tween") if b.has_meta("ui_tween") else null
	if old and old.is_valid():
		old.kill()
	var t := b.create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	t.tween_property(b, "scale", Vector2.ONE * scale_to, time)
	t.tween_property(b, "self_modulate", Color(glow, glow, glow), time)
	b.set_meta("ui_tween", t)


func _rest(b: BaseButton) -> void:
	if is_instance_valid(b) and not b.is_hovered() and not b.has_focus():
		_to(b, 1.0, 1.0)


## Let go: spring back past normal (a little overshoot), to the hover size if still on it.
func _release(b: BaseButton) -> void:
	if not is_instance_valid(b) or not b.is_inside_tree():
		return
	var still := b.is_hovered() or b.has_focus()
	var old: Tween = b.get_meta("ui_tween") if b.has_meta("ui_tween") else null
	if old and old.is_valid():
		old.kill()
	var t := b.create_tween().set_parallel().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	t.tween_property(b, "scale", Vector2.ONE * (HOVER_SCALE if still else 1.0), 0.28)
	t.tween_property(b, "self_modulate", Color.WHITE * (1.12 if still else 1.0), 0.28)
	b.set_meta("ui_tween", t)
