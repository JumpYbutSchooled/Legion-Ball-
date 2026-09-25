extends Node3D
## Spawns stacks of pushable cubes and rebuilds them whenever the ball resets.

## Each entry: [base position, layout]. Layouts: "tower", "pyramid", "wall".
const STACKS := [
	[Vector3(0, 0, 40), "wall"],
	[Vector3(-10, 0, 46), "pyramid"],
	[Vector3(10, 0, 46), "tower"],
	[Vector3(-35, 0, 62), "wall"],
	[Vector3(35, 0, 62), "pyramid"],
	[Vector3(24, 0, 30), "tower"],
]

## Render layer the cubes draw on, so the spark height map can see just them.
const CUBE_LAYER := 4

@export var ball: Node
@export var cube_size := 1.0
@export var cube_mass := 0.6
@export var color := Color(0.62, 0.62, 0.62)

var _mesh: BoxMesh
var _shape: BoxShape3D
var _physics_mat: PhysicsMaterial


func _ready() -> void:
	_mesh = BoxMesh.new()
	_mesh.size = Vector3.ONE * cube_size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.7
	_mesh.material = mat
	_shape = BoxShape3D.new()
	_shape.size = Vector3.ONE * cube_size
	_physics_mat = PhysicsMaterial.new()
	_physics_mat.friction = 0.8
	_physics_mat.bounce = 0.1

	if ball and ball.has_signal("respawned"):
		ball.connect("respawned", respawn)
	respawn()
	_add_spark_collider()


## GPU sparks only bounce off particle colliders, and there are too many cubes to give
## each its own box (Godot uses at most 32 at once). Instead one height map, redrawn
## every frame from the cubes alone (their own render layer), catches sparks on them.
func _add_spark_collider() -> void:
	var field := GPUParticlesCollisionHeightField3D.new()
	field.size = Vector3(120, 30, 120)
	field.resolution = GPUParticlesCollisionHeightField3D.RESOLUTION_512
	field.update_mode = GPUParticlesCollisionHeightField3D.UPDATE_MODE_ALWAYS
	field.heightfield_mask = CUBE_LAYER
	field.position = Vector3(0, 13, 45)
	# Not a child of this node: respawn() clears all children.
	get_parent().add_child.call_deferred(field)


func respawn() -> void:
	for child in get_children():
		child.queue_free()
	for stack in STACKS:
		for offset in _layout(stack[1]):
			_spawn_cube(stack[0] + offset)


func _layout(kind: String) -> Array[Vector3]:
	# Small gaps so cubes don't start interpenetrating.
	var step := cube_size + 0.002
	var half := cube_size / 2.0 + 0.002
	var pts: Array[Vector3] = []
	match kind:
		"tower":
			for y in 5:
				pts.append(Vector3(0, y * step + half, 0))
		"pyramid":
			for row in 4:
				var count := 4 - row
				for i in count:
					pts.append(Vector3((i - (count - 1) / 2.0) * step, row * step + half, 0))
		"wall":
			for y in 3:
				for x in 4:
					pts.append(Vector3((x - 1.5) * step, y * step + half, 0))
	return pts


func _spawn_cube(pos: Vector3) -> void:
	var body := RigidBody3D.new()
	body.mass = cube_mass
	body.physics_material_override = _physics_mat
	var col := CollisionShape3D.new()
	col.shape = _shape
	body.add_child(col)
	var mesh := MeshInstance3D.new()
	mesh.mesh = _mesh
	mesh.layers = CUBE_LAYER
	body.add_child(mesh)
	add_child(body)
	body.global_position = global_position + pos
