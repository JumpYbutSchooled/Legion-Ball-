extends Node3D
## TIME DILATOR's bubble: follows its owner for `lifetime` seconds. Inside it, other
## players are chilled (the owner's copy sends the status every half second) and other
## players' projectiles fly at half speed (every projectile asks factor() each step, on
## every computer, so the owner of a shot sees the same slowdown).

var manager: Node
var visual_only := false
var radius := 12.0
var lifetime := 4.0
var color := Color(0.55, 0.6, 1.0)
## Peer id of whoever made it (their own shots aren't slowed).
var owner_peer := 0

var _t := 0.0
var _tick := 0.0
var _shell: MeshInstance3D
var _mat: StandardMaterial3D


## How fast a shot from `shooter` moves at `pos`: 0.5 inside someone else's field, else 1.
static func factor(tree: SceneTree, pos: Vector3, shooter: int) -> float:
	if not tree:
		return 1.0
	for f in tree.get_nodes_in_group("time_fields"):
		if int(f.get("owner_peer")) != shooter and (f as Node3D).global_position.distance_to(pos) <= float(f.get("radius")):
			return 0.5
	return 1.0


func _ready() -> void:
	top_level = true
	add_to_group("time_fields")
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat.albedo_color = Color(color, 0.12)
	_shell = MeshInstance3D.new()
	_shell.mesh = sphere
	_shell.material_override = _mat
	_shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_shell.scale = Vector3.ONE * radius
	add_child(_shell)


func _physics_process(delta: float) -> void:
	_t += delta
	if _t >= lifetime:
		queue_free()
		return
	if manager and manager.ball:
		global_position = manager.ball.global_position
	# Shimmer, fading out at the end.
	_mat.albedo_color = Color(color, (0.1 + 0.05 * sin(_t * 12.0)) * clampf((lifetime - _t) * 2.0, 0.0, 1.0))
	if visual_only or not manager:
		return
	_tick -= delta
	if _tick <= 0.0:
		_tick = 0.5
		for t in get_tree().get_nodes_in_group("lock_targets"):
			if t.call("is_alive") and (t.call("get_aim_point") as Vector3).distance_to(global_position) <= radius:
				manager.call("apply_status", t, "chill", 0.7, Vector3(0.5, 0, 0))
