extends CanvasLayer
## Combat feedback for the local player (added by local_view.gd):
##   - hit markers: a white X that pops on the crosshair when your shot lands, and a
##     bigger red one (with a crunch) when it kills
##   - damage direction: a red arc at the edge of the screen pointing where a hit came from
##   - low health: the screen's edges pulse red below a third of your health
##   - FPS and ping, top right (Settings: SHOW FPS / PING)
## Each can be turned off in Settings.

const UIStyle := preload("res://scripts/ui/ui_style.gd")
const HIT_TIME := 0.22
const KILL_TIME := 0.5
const ARC_TIME := 1.3

var ball: RigidBody3D

var _draw_layer: Control
var _vignette: ColorRect
var _perf: Label
var _fly_tag: Label
var _hit_t := 99.0
var _hit_size := 1.0
var _kill_t := 99.0
var _arcs: Array = []  # [world position, age]
var _low := 0.0
var _settings: Node
var _arena: Node


func _ready() -> void:
	layer = 4
	_settings = get_tree().root.get_node_or_null("Settings")
	_vignette = ColorRect.new()
	_vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = _vignette_shader()
	_vignette.material = mat
	_vignette.visible = false
	add_child(_vignette)
	_draw_layer = Control.new()
	_draw_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_draw_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_draw_layer.draw.connect(_draw_feedback)
	add_child(_draw_layer)
	_perf = UIStyle.label("", 11, UIStyle.TEXT_DIM)
	_perf.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_perf.offset_left = -170
	_perf.offset_right = -10
	_perf.offset_top = 4
	_perf.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_perf)
	_fly_tag = UIStyle.label("// FLYING  -  SPACE UP, C DOWN, V TO LAND", 13, Color(1.0, 0.78, 0.25), true)
	_fly_tag.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_fly_tag.offset_top = -150
	_fly_tag.offset_left = -260
	_fly_tag.offset_right = 260
	_fly_tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_fly_tag.visible = false
	add_child(_fly_tag)
	if ball:
		var weapon := ball.get_node_or_null("Weapon")
		if weapon and weapon.has_signal("damage_dealt"):
			weapon.connect("damage_dealt", _on_hit)
	_hook_arena.call_deferred()


func _hook_arena() -> void:
	if not is_inside_tree():
		return
	var scene := get_tree().current_scene
	if not scene or not scene.has_signal("player_killed"):
		return
	_arena = scene
	_arena.connect("player_killed", _on_killed)
	_arena.connect("health_changed", _on_health)
	if _arena.has_signal("hurt_from"):
		_arena.connect("hurt_from", _on_hurt)


func _on_hit(amount: float) -> void:
	if not _setting("hit_markers"):
		return
	_hit_t = 0.0
	_hit_size = clampf(0.8 + amount / 40.0, 0.8, 1.6)
	var sfx := get_tree().root.get_node_or_null("Sfx")
	if sfx:
		sfx.call("play_ui", "ui_click", -10.0, 2.2)


func _on_killed(victim: int, attacker: int) -> void:
	var me := _my_id()
	if attacker != me or victim == me or not _setting("hit_markers"):
		return
	_kill_t = 0.0
	var sfx := get_tree().root.get_node_or_null("Sfx")
	if sfx:
		sfx.call("play_ui", "shatter", -8.0, 1.3)


func _on_hurt(pos: Vector3) -> void:
	if not _setting("damage_indicators"):
		return
	_arcs.append([pos, 0.0])
	while _arcs.size() > 6:
		_arcs.pop_front()


func _on_health(id: int, hp: float) -> void:
	if id != _my_id() or not _arena:
		return
	var full: float = _arena.call("max_health_of", id) if _arena.has_method("max_health_of") else 100.0
	_low = clampf(1.0 - hp / (full * 0.35), 0.0, 1.0) if hp > 0.0 else 0.0


func _my_id() -> int:
	return int(ball.call("player_id")) if ball and ball.has_method("player_id") else multiplayer.get_unique_id()


func _setting(key: String) -> bool:
	return _settings == null or bool(_settings.call("get_value", key))


func _process(delta: float) -> void:
	_hit_t += delta
	_kill_t += delta
	for arc in _arcs:
		arc[1] += delta
	_arcs = _arcs.filter(func(a: Array) -> bool: return a[1] < ARC_TIME)
	# Low health: a pulse at the edges, faster the lower you are.
	var show: bool = _low > 0.0 and _setting("damage_indicators") and ball and not ball.get("dead")
	_vignette.visible = show
	if show:
		var pulse := 0.75 + 0.25 * sin(Time.get_ticks_msec() / 1000.0 * lerpf(3.0, 9.0, _low))
		(_vignette.material as ShaderMaterial).set_shader_parameter("amount", _low * pulse)
	_fly_tag.visible = ball != null and bool(ball.get("flying"))
	if _setting("show_fps"):
		var net := get_tree().root.get_node_or_null("Net")
		var ping: int = net.get("ping_ms") if net and net.get("online") else -1
		_perf.text = "FPS %d" % Engine.get_frames_per_second() + ("   PING %d ms" % ping if ping >= 0 else "")
		_perf.visible = true
	else:
		_perf.visible = false
	_draw_layer.queue_redraw()


func _draw_feedback() -> void:
	var c := _draw_layer.size / 2.0
	# Hit marker: four short strokes round the crosshair, popping out and fading.
	if _hit_t < HIT_TIME:
		var k := _hit_t / HIT_TIME
		_draw_x(c, (9.0 + 5.0 * k) * _hit_size, 7.0 * _hit_size, Color(1, 1, 1, 1.0 - k), 2.0)
	if _kill_t < KILL_TIME:
		var k := _kill_t / KILL_TIME
		_draw_x(c, 12.0 + 10.0 * k, 12.0, Color(1.0, 0.25, 0.2, 1.0 - k * k), 3.5)
	# Where hits came from: an arc on a ring round the middle, toward the attacker.
	var cam := get_viewport().get_camera_3d()
	if not cam or not ball:
		return
	var radius := minf(_draw_layer.size.x, _draw_layer.size.y) * 0.28
	for arc in _arcs:
		var to: Vector3 = arc[0] - ball.global_position
		var fwd := -cam.global_basis.z
		var right := cam.global_basis.x
		var flat_fwd := Vector2(fwd.x, fwd.z).normalized()
		var flat_right := Vector2(right.x, right.z).normalized()
		var flat_to := Vector2(to.x, to.z)
		if flat_to.length() < 0.1:
			continue
		# Screen angle: straight up is ahead, right is right.
		var ang := atan2(flat_to.dot(flat_right), flat_to.dot(flat_fwd)) - PI / 2.0
		var fade := 1.0 - float(arc[1]) / ARC_TIME
		_draw_layer.draw_arc(c, radius, ang - 0.32, ang + 0.32, 20, Color(1.0, 0.2, 0.15, 0.85 * fade), 6.0, true)
		_draw_layer.draw_arc(c, radius + 7.0, ang - 0.18, ang + 0.18, 12, Color(1.0, 0.45, 0.35, 0.6 * fade), 3.0, true)


func _draw_x(c: Vector2, gap: float, length: float, col: Color, width: float) -> void:
	for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
		var dir: Vector2 = d.normalized()
		_draw_layer.draw_line(c + dir * gap, c + dir * (gap + length), col, width, true)


static func _vignette_shader() -> Shader:
	var s := Shader.new()
	s.code = """
shader_type canvas_item;
uniform float amount = 0.0;
void fragment() {
	vec2 d = UV - vec2(0.5);
	float edge = smoothstep(0.35, 0.75, length(d * vec2(1.0, 0.8)) * 1.35);
	COLOR = vec4(0.85, 0.05, 0.03, edge * amount * 0.6);
}
"""
	return s
