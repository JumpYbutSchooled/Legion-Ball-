extends Node3D
## ARC PYLON: a crystal fork planted in the ground. Every `interval` seconds (the owner's
## copy decides) it zaps the nearest other player or target within `radius` it can see,
## with a lightning bolt everyone sees.

var manager: Node
var visual_only := false
var lifetime := 8.0
var radius := 16.0
var interval := 0.4
var damage := 1.5
var color := Color(0.85, 1.0, 0.3)

var _t := 0.0
var _tick := 0.0
var _mat: StandardMaterial3D


func _ready() -> void:
	top_level = true
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.albedo_color = color * 2.0
	for x in [-0.35, 0.35]:
		var prong := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.18, 2.6, 0.18)
		prong.mesh = box
		prong.material_override = _mat
		prong.position = Vector3(x, 1.3, 0.0)
		add_child(prong)
	var base := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.5
	cyl.bottom_radius = 0.7
	cyl.height = 0.4
	base.mesh = cyl
	base.material_override = _mat
	base.position = Vector3(0, 0.2, 0)
	add_child(base)
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = radius - 0.1
	torus.outer_radius = radius
	var faint := StandardMaterial3D.new()
	faint.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	faint.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	faint.albedo_color = Color(color, 0.3)
	ring.mesh = torus
	ring.material_override = faint
	ring.position = Vector3(0, 0.1, 0)
	add_child(ring)


func _physics_process(delta: float) -> void:
	_t += delta
	_mat.albedo_color = color * (1.8 + 0.6 * sin(_t * 20.0))
	if _t >= lifetime:
		queue_free()
		return
	if visual_only or not manager:
		return
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = interval
	var top := global_position + Vector3.UP * 2.6
	var best: Node3D = null
	var best_d := radius
	for t in get_tree().get_nodes_in_group("lock_targets"):
		if not t.call("is_alive"):
			continue
		var p: Vector3 = t.call("get_aim_point")
		var d := p.distance_to(global_position)
		if d > best_d:
			continue
		var sight: Dictionary = manager.call("raycast", top, p)
		if not sight.is_empty() and sight["collider"] != t:
			continue
		best = t
		best_d = d
	if best:
		var p: Vector3 = best.call("get_aim_point")
		manager.call("spawn_beam", top, (p - top).normalized(), top.distance_to(p), 0.25, 0.12, 14.0, color)
		manager.call("spawn_light", p, 20.0, 5.0, 0.1, color)
		manager.call("hit_object", best, damage, p, (p - top).normalized(), 3.0)
		manager.call("play_sound", "zap", top, -6.0)
