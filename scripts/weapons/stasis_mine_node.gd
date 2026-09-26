extends Node3D
## STASIS MINE: a crystal charge stuck where it landed. Arms after a moment; when anyone
## else rolls within `trigger_radius` (the owner's copy watches), it goes off: a blast
## that staggers everyone in it. Removed on every screen when it goes off.

var manager: Node
var visual_only := false
var trigger_radius := 12.0
var lifetime := 40.0
var color := Color(0.2, 0.45, 1.0)

var _t := 0.0
var _mat: StandardMaterial3D


func _ready() -> void:
	top_level = true
	add_to_group("stasis_mines")
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.albedo_color = color * 2.5
	var gem := MeshInstance3D.new()
	var mesh := PrismMesh.new()
	mesh.size = Vector3(0.7, 0.7, 0.7)
	gem.mesh = mesh
	gem.material_override = _mat
	add_child(gem)


func _physics_process(delta: float) -> void:
	_t += delta
	# Pulses: slow while arming, quick once armed.
	var armed := _t > 0.8
	_mat.albedo_color = color * (1.5 + 1.5 * sin(_t * (14.0 if armed else 4.0)))
	if _t >= lifetime:
		queue_free()
		return
	if visual_only or not manager or not armed:
		return
	for t in get_tree().get_nodes_in_group("lock_targets"):
		if t.call("is_alive") and (t.call("get_aim_point") as Vector3).distance_to(global_position) <= trigger_radius:
			_detonate()
			return


func _detonate() -> void:
	manager.call("spawn_explosion", {
		"position": global_position, "color": color, "radius": 16.0, "damage": 5.0,
		"force": 28.0, "stagger_time": 1.8, "spark_count": 220, "light_energy": 140.0,
		"warp_strength": 0.25, "sound": "boom",
	})
	manager.call("despawn_node", self)
