extends Node3D
## SEEKER DRONE: a small crystal drone orbiting its owner for `lifetime` seconds. The
## owner's copy fires at whatever the owner is aiming nearest (a target near the
## crosshair it can see, within `range`), every `interval` seconds.

var manager: Node
var visual_only := false
var lifetime := 10.0
var interval := 0.45
var damage := 0.9
var shot_range := 70.0
var color := Color(0.45, 0.5, 0.6)

var _t := 0.0
var _tick := 0.0
var _body: MeshInstance3D


func _ready() -> void:
	top_level = true
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = 0.7
	mat.roughness = 0.3
	mat.emission_enabled = true
	mat.emission = color.lerp(Color(1.0, 0.3, 0.2), 0.5)
	mat.emission_energy_multiplier = 1.5
	_body = MeshInstance3D.new()
	var prism := PrismMesh.new()
	prism.size = Vector3(0.6, 0.4, 0.9)
	_body.mesh = prism
	_body.material_override = mat
	add_child(_body)


func _physics_process(delta: float) -> void:
	_t += delta
	if _t >= lifetime or not manager or not is_instance_valid(manager.ball):
		queue_free()
		return
	# Orbit above the owner.
	var center: Vector3 = manager.ball.global_position
	var a := _t * 2.2
	global_position = center + Vector3(cos(a) * 2.2, 2.0 + sin(_t * 3.0) * 0.3, sin(a) * 2.2)
	_body.rotation.y = -a
	if visual_only:
		return
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = interval
	var found: Array = manager.call("targets_on_screen", 260.0, shot_range, true)
	if found.is_empty():
		return
	var target: Node3D = found[0]["target"]
	var p: Vector3 = target.call("get_aim_point")
	var dir := (p - global_position).normalized()
	var hit: Dictionary = manager.call("raycast", global_position, p + dir * 0.5)
	var end: Vector3 = hit["position"] if not hit.is_empty() else p
	manager.call("spawn_beam", global_position, dir, global_position.distance_to(end), 0.08, 0.1, 8.0, color.lerp(Color(1, 0.3, 0.2), 0.5))
	if not hit.is_empty():
		manager.call("hit_object", hit["collider"], damage, end, dir, 2.0)
	manager.call("play_sound", "zap", global_position, -14.0)
