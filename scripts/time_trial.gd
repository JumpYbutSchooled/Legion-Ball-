extends Node3D
## Time trial (solo, from the Practice page): a run through a ring of checkpoints on any
## map, against the clock. The checkpoints are the map's own spawn points (places a ball
## can always get to), joined nearest-first into a route that ends back at the start. The
## next one is a bright column of light, the ones after it faint. The clock starts when you
## first move; R (reset) starts the run again. Bronze, silver and gold times come from the
## route's length; your best time and medal for each map are kept in your career
## (profile.gd record_trial), and a new medal pays experience.
## Added by the arena for the local player when the menu asks for one (Engine meta
## "time_trial").

const UIStyle := preload("res://scripts/ui/ui_style.gd")
const Sfx := preload("res://scripts/sfx.gd")
const RADIUS := 7.0
## Average speeds (m/s) a medal's time is worked out from, plus a few seconds to get going.
const PACE := {"gold": 46.0, "silver": 33.0, "bronze": 22.0}
const COLORS := {"gold": Color(1.0, 0.85, 0.3), "silver": Color(0.8, 0.86, 0.92), "bronze": Color(0.85, 0.55, 0.3), "": Color(0.6, 0.7, 0.78)}

var ball: RigidBody3D
var map_path := ""

var _route: Array[Vector3] = []
var _gates: Array[MeshInstance3D] = []
var _next := 0
var _time := 0.0
var _running := false
var _done := false
var _length := 0.0
var _label: Label
var _sub: Label
var _profile: Node


func _ready() -> void:
	_profile = get_tree().root.get_node_or_null("Profile")
	var scene := get_tree().current_scene
	var spots: Array = scene.call("_map_spawns") if scene and scene.has_method("_map_spawns") else []
	if spots.size() < 3:
		# The training arena has no spawn points of its own: a ring round the middle.
		spots = []
		for i in 8:
			spots.append(Vector3(sin(TAU * i / 8.0), 0.0, cos(TAU * i / 8.0)) * 110.0 + Vector3.UP)
	_plan(spots)
	_build_gates()
	var layer := CanvasLayer.new()
	layer.layer = 6
	add_child(layer)
	_label = UIStyle.label("", 26, Color.WHITE, true)
	_sub = UIStyle.label("", 14, UIStyle.TEXT_DIM, true)
	var i := 0
	for l in [_label, _sub]:
		l.set_anchors_preset(Control.PRESET_CENTER_TOP)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.custom_minimum_size = Vector2(900, 0)
		l.position = Vector2(-450, 22 + i * 36)
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
		l.add_theme_constant_override("outline_size", 6)
		layer.add_child(l)
		i += 1
	if ball:
		ball.connect("respawned", _restart)
	_restart()


## The route: from the start (the first spawn, where practice puts you) to whichever
## checkpoint is nearest each time, then home.
func _plan(spots: Array) -> void:
	var left := spots.duplicate()
	var at: Vector3 = left.pop_front()
	var start := at
	while not left.is_empty():
		var best := 0
		for i in left.size():
			if at.distance_to(left[i]) < at.distance_to(left[best]):
				best = i
		_length += at.distance_to(left[best])
		at = left.pop_at(best)
		_route.append(at)
	_length += at.distance_to(start)
	_route.append(start)


func medal_time(medal: String) -> float:
	return _length / float(PACE[medal]) + 4.0


func _build_gates() -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = RADIUS
	mesh.bottom_radius = RADIUS
	mesh.height = 60.0
	mesh.radial_segments = 24
	mesh.cap_top = false
	mesh.cap_bottom = false
	for p in _route:
		var gate := MeshInstance3D.new()
		gate.mesh = mesh
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		gate.material_override = mat
		gate.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		gate.position = p + Vector3.UP * 29.0
		add_child(gate)
		_gates.append(gate)


func _restart() -> void:
	_next = 0
	_time = 0.0
	_running = false
	_done = false
	_show_gates()


func _show_gates() -> void:
	for i in _gates.size():
		var mat := _gates[i].material_override as StandardMaterial3D
		_gates[i].visible = i >= _next and not _done
		var ahead := i - _next
		mat.albedo_color = Color(0.35, 0.95, 1.0, 0.34) if ahead == 0 else Color(0.35, 0.95, 1.0, 0.05 if ahead > 1 else 0.1)


func _physics_process(delta: float) -> void:
	if not ball or _done:
		return
	if not _running and ball.linear_velocity.length() > 1.5:
		_running = true
	if _running:
		_time += delta
	var to := ball.global_position - _route[_next]
	if Vector2(to.x, to.z).length() <= RADIUS + 0.5 and absf(to.y) < 12.0 and _running:
		_next += 1
		Sfx.play_flat(get_tree(), "ui_page", -6.0, 1.0 + 0.5 * float(_next) / _route.size())
		if _next >= _route.size():
			_finish()
		else:
			_show_gates()


func _finish() -> void:
	_done = true
	_running = false
	_show_gates()
	var medal := ""
	for m in ["gold", "silver", "bronze"]:
		if _time <= medal_time(m):
			medal = m
			break
	var result: Dictionary = _profile.call("record_trial", map_path, _time, medal) if _profile else {}
	Sfx.play_flat(get_tree(), "infinity" if medal != "" else "ui_click", -6.0)
	_label.text = "FINISHED  %s%s" % [_clock(_time), "   ·   %s" % medal.to_upper() if medal != "" else ""]
	_label.add_theme_color_override("font_color", COLORS[medal])
	_sub.text = ("NEW BEST!  " if result.get("best", false) else "") + "PRESS %s TO RUN IT AGAIN" % load("res://scripts/input_setup.gd").key_label("reset_ball")


func _process(_delta: float) -> void:
	if _done:
		return
	var best: Dictionary = (_profile.get("trials") as Dictionary).get(map_path, {}) if _profile else {}
	_label.text = "TIME TRIAL  %s   CHECKPOINT %d / %d" % [_clock(_time), _next, _route.size()]
	_label.add_theme_color_override("font_color", Color.WHITE)
	_sub.text = "GOLD %s   SILVER %s   BRONZE %s%s" % [_clock(medal_time("gold")), _clock(medal_time("silver")), _clock(medal_time("bronze")),
		"    ·    YOUR BEST %s" % _clock(float(best["time"])) if best.has("time") else ""]


static func _clock(t: float) -> String:
	return "%d:%05.2f" % [int(t / 60.0), fmod(t, 60.0)]
