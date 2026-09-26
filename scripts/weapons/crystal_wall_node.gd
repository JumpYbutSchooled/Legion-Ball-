extends StaticBody3D
## CRYSTAL WALL: a slab of crystal that rises out of the ground, solid for everyone
## (every computer builds the same one), blocking shots and players for `lifetime`
## seconds, then crumbles. `facing` is the direction it faces (flat).

var manager: Node
var visual_only := false
var lifetime := 5.0
var facing := Vector3.FORWARD
var color := Color(0.6, 0.45, 0.35)
var width := 30.0
var height := 14.0

var _t := 0.0
var _mesh: MeshInstance3D


func _ready() -> void:
	top_level = true
	var flat := Vector3(facing.x, 0.0, facing.z)
	if flat.length() < 0.01:
		flat = Vector3.FORWARD
	global_basis = Basis.looking_at(flat.normalized(), Vector3.UP)
	var box := BoxMesh.new()
	box.size = Vector3(width, height, 0.8)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(color, 0.85)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 0.8
	mat.roughness = 0.2
	_mesh = MeshInstance3D.new()
	_mesh.mesh = box
	_mesh.material_override = mat
	add_child(_mesh)
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = box.size
	shape.shape = box_shape
	add_child(shape)
	var sfx := get_tree().root.get_node_or_null("Sfx")
	if sfx:
		sfx.call("play", "shield", global_position, 0.0, 0.6)


func _process(delta: float) -> void:
	_t += delta
	# Rises out of the ground, sinks back at the end.
	var up := minf(_t / 0.25, 1.0) * clampf((lifetime - _t) / 0.3, 0.0, 1.0)
	_mesh.scale = Vector3(1.0, maxf(up, 0.02), 1.0)
	_mesh.position = Vector3(0.0, -height * 0.5 * (1.0 - up), 0.0)
	if _t >= lifetime:
		queue_free()
