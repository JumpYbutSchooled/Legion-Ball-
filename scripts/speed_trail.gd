extends MeshInstance3D
## A glowing ribbon streaming behind a fast ball, in its player's colour (arena.gd adds
## one to every ball). It records where the ball has been, faces the camera, fades toward
## its tail, and only shows above START_SPEED, wider and brighter the faster the ball goes.
## Settings: SPEED TRAILS.

const POINTS := 22
## Seconds between recorded points.
const STEP := 0.025
const START_SPEED := 22.0
const FULL_SPEED := 80.0
const MAX_WIDTH := 0.42

var ball: Node3D
var color := Color(0.35, 0.9, 1.0)
## A trail from the Locker (profile.gd TRAILS): its colours tail to head (empty: `color`
## all the way), or a rainbow running down it.
var colors: Array = []
var rainbow := false

var _points: Array[Vector3] = []
var _speeds: Array[float] = []
var _timer := 0.0
var _last := Vector3.ZERO
var _mesh := ImmediateMesh.new()
var _mat := StandardMaterial3D.new()
var _settings: Node


func _ready() -> void:
	top_level = true
	mesh = _mesh
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat.vertex_color_use_as_albedo = true
	material_override = _mat
	_settings = get_tree().root.get_node_or_null("Settings")
	if ball:
		_last = ball.global_position


## A looping map moved the ball to the far side: the trail comes with it.
func _on_wrapped(offset: Vector3) -> void:
	for i in _points.size():
		_points[i] += offset
	_last += offset


func _process(delta: float) -> void:
	_mesh.clear_surfaces()
	global_transform = Transform3D.IDENTITY
	if not ball or not is_instance_valid(ball) or not ball.visible or (_settings and not _settings.call("get_value", "speed_trails")):
		_points.clear()
		_speeds.clear()
		return
	if ball.has_signal("wrapped") and not ball.is_connected("wrapped", _on_wrapped):
		ball.connect("wrapped", _on_wrapped)
		ball.connect("rifted", func(_turn: Basis, _to: Vector3) -> void:
			_points.clear()
			_speeds.clear()
			_last = _to)
	var pos := ball.get_global_transform_interpolated().origin
	var speed := pos.distance_to(_last) / maxf(delta, 0.0001)
	_last = pos
	# A teleport or respawn: start over rather than streak across the map.
	if speed > 400.0:
		_points.clear()
		_speeds.clear()
	_timer -= delta
	if _timer <= 0.0:
		_timer = STEP
		_points.push_front(pos)
		_speeds.push_front(speed)
		if _points.size() > POINTS:
			_points.pop_back()
			_speeds.pop_back()
	elif not _points.is_empty():
		_points[0] = pos
	if _points.size() < 2:
		return
	var cam := get_viewport().get_camera_3d()
	if not cam:
		return
	var eye := cam.global_position
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	var drawn := 0
	for i in _points.size():
		var p := _points[i]
		var along := (_points[maxi(i - 1, 0)] - _points[mini(i + 1, _points.size() - 1)])
		if along.length() < 0.001:
			along = Vector3.FORWARD
		var side := along.cross(eye - p).normalized()
		var k := clampf(inverse_lerp(START_SPEED, FULL_SPEED, _speeds[i]), 0.0, 1.0)
		var fade := 1.0 - float(i) / (_points.size() - 1)
		var width := MAX_WIDTH * k * fade
		var tint := color
		if rainbow:
			tint = Color.from_hsv(fposmod(Time.get_ticks_msec() / 1400.0 - float(i) * 0.035, 1.0), 0.75, 1.0)
		elif colors.size() >= 2:
			tint = (colors[0] as Color).lerp(colors[1], fade)
		var col := Color(tint.r, tint.g, tint.b, k * fade * fade * 0.55)
		_mesh.surface_set_color(col)
		_mesh.surface_add_vertex(p + side * width)
		_mesh.surface_set_color(col)
		_mesh.surface_add_vertex(p - side * width)
		drawn += 2
	_mesh.surface_end()
