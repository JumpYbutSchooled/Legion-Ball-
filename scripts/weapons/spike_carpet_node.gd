extends Node3D
## SPIKE CARPET: a line of crystal spikes along the ground from here to `end_point`.
## Anyone else rolling over it (owner's copy checks) is cut and chilled every tick.

var manager: Node
var visual_only := false
var lifetime := 6.0
var end_point := Vector3.ZERO
var color := Color(0.5, 0.6, 0.2)
var damage := 1.0

var _t := 0.0
var _tick := 0.0


func _ready() -> void:
	top_level = true
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 1.2
	var line := end_point - global_position
	var count := clampi(int(line.length() / 1.2), 2, 30)
	for i in count:
		var spike := MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = 0.35
		cone.height = 1.1
		cone.radial_segments = 4
		spike.mesh = cone
		spike.material_override = mat
		spike.position = line * (float(i) / (count - 1)) + Vector3(randf_range(-0.4, 0.4), 0.5, randf_range(-0.4, 0.4))
		spike.rotation = Vector3(randf_range(-0.2, 0.2), randf() * TAU, randf_range(-0.2, 0.2))
		add_child(spike)


func _physics_process(delta: float) -> void:
	_t += delta
	if _t >= lifetime:
		queue_free()
		return
	scale = Vector3(1.0, minf(_t / 0.2, 1.0) * clampf((lifetime - _t) / 0.3, 0.05, 1.0), 1.0)
	if visual_only or not manager:
		return
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = 0.3
	for t in get_tree().get_nodes_in_group("lock_targets"):
		if not t.call("is_alive"):
			continue
		var p: Vector3 = t.call("get_aim_point")
		var closest := Geometry3D.get_closest_point_to_segment(p, global_position, end_point)
		if p.distance_to(closest) <= 1.8 and p.y - closest.y < 2.5:
			manager.call("hit_object", t, damage, p, Vector3.UP, 2.0)
			manager.call("apply_status", t, "chill", 0.6, Vector3(0.5, 0, 0))
