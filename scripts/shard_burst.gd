extends Node3D
## One-shot burst of glowing polygon shards that fly out, tumble, fall and shrink away.
## Frees itself when done.

@export var count := 16
@export var lifetime := 0.9
@export var speed := 7.0
@export var gravity := 14.0
@export var color := Color(0.9, 0.2, 0.18)

var _t := 0.0
var _shards: Array[MeshInstance3D] = []
var _velocities: Array[Vector3] = []
var _spins: Array[Vector3] = []
var _sizes := PackedFloat32Array()


func _ready() -> void:
	# A 3-sided bipyramid: a small, sharp shard.
	var shape := SphereMesh.new()
	shape.radius = 0.14
	shape.height = 0.3
	shape.radial_segments = 3
	shape.rings = 1
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 2.5
	shape.material = mat

	for i in count:
		var shard := MeshInstance3D.new()
		shard.mesh = shape
		shard.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		shard.rotation = Vector3(randf(), randf(), randf()) * TAU
		add_child(shard)
		var dir := Vector3(randf_range(-1, 1), randf_range(0.2, 1.2), randf_range(-1, 1)).normalized()
		_shards.append(shard)
		_velocities.append(dir * speed * randf_range(0.5, 1.0))
		_spins.append(Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 12.0)
		_sizes.append(randf_range(0.6, 1.5))


func _process(delta: float) -> void:
	_t += delta
	if _t >= lifetime:
		queue_free()
		return
	var shrink := 1.0 - _t / lifetime
	for i in _shards.size():
		_velocities[i].y -= gravity * delta
		_shards[i].position += _velocities[i] * delta
		_shards[i].rotation += _spins[i] * delta
		_shards[i].scale = Vector3.ONE * _sizes[i] * shrink
