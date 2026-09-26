extends AnimatableBody3D
## MIRAGE's decoy: a fake ball in its owner's colour that rolls off in `direction` at
## `speed` for `lifetime` seconds. It's a lock target on every computer, so enemy locks,
## missiles and lock-on shots can jump to it; anything that hits it pops it (on that
## computer).

var manager: Node
var visual_only := false
var direction := Vector3.FORWARD
var speed := 26.0
var lifetime := 5.0
var tint := Color(0.5, 0.35, 0.7)

var _t := 0.0
var _alive := true
var _mesh: MeshInstance3D


func _ready() -> void:
	top_level = true
	sync_to_physics = false
	add_to_group("lock_targets")
	add_to_group("decoys")
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.12, 0.13, 0.16)
	mat.metallic = 0.6
	mat.roughness = 0.35
	mat.emission_enabled = true
	mat.emission = tint
	mat.emission_energy_multiplier = 0.6
	_mesh = MeshInstance3D.new()
	_mesh.mesh = sphere
	_mesh.material_override = mat
	add_child(_mesh)
	var shape := CollisionShape3D.new()
	var s := SphereShape3D.new()
	s.radius = 0.5
	shape.shape = s
	add_child(shape)
	direction.y = 0.0
	direction = direction.normalized() if direction.length() > 0.01 else Vector3.FORWARD


func _physics_process(delta: float) -> void:
	_t += delta
	if _t >= lifetime or not _alive:
		queue_free()
		return
	# Rolls along, gently weaving; turns away from walls.
	var weave := direction.rotated(Vector3.UP, sin(_t * 2.5) * 0.4)
	var step := weave * speed * delta
	var space := get_world_3d().direct_space_state
	var ahead := PhysicsRayQueryParameters3D.create(global_position, global_position + weave * 2.0)
	ahead.exclude = [get_rid()]
	var wall := space.intersect_ray(ahead)
	if not wall.is_empty():
		direction = direction.bounce(wall["normal"]).normalized()
		direction.y = 0.0
	var down := PhysicsRayQueryParameters3D.create(global_position + step, global_position + step + Vector3.DOWN * 3.0)
	down.exclude = [get_rid()]
	var ground := space.intersect_ray(down)
	var pos := global_position + step
	if not ground.is_empty():
		pos.y = ground["position"].y + 0.5
	global_position = pos
	_mesh.rotate(weave.cross(Vector3.UP).normalized() * -1.0, speed * delta / 0.5)


func is_alive() -> bool:
	return _alive


func get_aim_point() -> Vector3:
	return global_position


## Any hit pops it.
func take_hit(_amount: float, _pos: Vector3, _dir: Vector3) -> void:
	if not _alive:
		return
	_alive = false
	remove_from_group("lock_targets")
	remove_from_group("decoys")
	var sfx := get_tree().root.get_node_or_null("Sfx")
	if sfx:
		sfx.call("play", "shatter", global_position, -6.0)
	if manager:
		manager.call("_light", global_position, 25.0, 5.0, 0.12, tint)
