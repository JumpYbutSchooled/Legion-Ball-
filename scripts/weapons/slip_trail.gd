extends Node3D
## SLIPSTREAM's trail: one glowing segment from here to `to_point`, lasting `lifetime`.
## Its owner rolling along it gets pushed faster the way they're going; anyone else
## crossing it gets cut (the owner's copy decides both).

var manager: Node
var visual_only := false
var to_point := Vector3.ZERO
var lifetime := 6.0
var color := Color(0.1, 1.0, 0.8)
var damage := 0.8

var _t := 0.0
var _tick := 0.0
var _mat: StandardMaterial3D


func _ready() -> void:
	top_level = true
	var span := to_point - global_position
	var length := maxf(span.length(), 0.3)
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.albedo_color = Color(color.r * 2.0, color.g * 2.0, color.b * 2.0, 0.7)
	var strip := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.9, 0.08, length)
	strip.mesh = box
	strip.material_override = _mat
	strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(strip)
	if span.length() > 0.05:
		var up := Vector3.UP if absf(span.normalized().y) < 0.95 else Vector3.RIGHT
		global_transform = Transform3D(Basis.looking_at(span.normalized(), up), global_position + span * 0.5)


func _physics_process(delta: float) -> void:
	_t += delta
	if _t >= lifetime:
		queue_free()
		return
	_mat.albedo_color.a = 0.7 * clampf((lifetime - _t) / 1.0, 0.0, 1.0)
	if visual_only or not manager:
		return
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = 0.2
	var start := global_position + global_basis.z * _half_length()
	var end := global_position - global_basis.z * _half_length()
	var ball: RigidBody3D = manager.ball
	var bp := ball.global_position
	if bp.distance_to(Geometry3D.get_closest_point_to_segment(bp, start, end)) < 2.2:
		var v := ball.linear_velocity
		if v.length() > 5.0 and v.length() < 95.0:
			manager.call("push_ball", v.normalized() * 1.6)
	for t in get_tree().get_nodes_in_group("lock_targets"):
		if not t.call("is_alive"):
			continue
		var p: Vector3 = t.call("get_aim_point")
		if p.distance_to(Geometry3D.get_closest_point_to_segment(p, start, end)) < 1.6:
			manager.call("hit_object", t, damage, p, Vector3.UP, 1.0)


func _half_length() -> float:
	var box := (get_child(0) as MeshInstance3D).mesh as BoxMesh
	return box.size.z * 0.5
