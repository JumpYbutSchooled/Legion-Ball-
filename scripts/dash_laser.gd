extends MeshInstance3D
## Glowing stretched octahedron (8-sided die shape) that shoots out behind the ball
## on a dash and flies backward while it fades. Spawned by the ball; frees itself when done.

const LaserShader := preload("res://shaders/dash_laser.gdshader")

@export var length := 10.0
@export var width := 0.7
## Where the widest point sits along the beam (0 = at the ball, 1 = at the tail).
@export_range(0.0, 1.0) var widest_at := 0.15
## Time for the beam to shoot out to full length.
@export var extend_time := 0.09
@export var lifetime := 0.7
## How fast the whole beam flies backward, in m/s.
@export var shoot_speed := 25.0
## Glow brightness (the shader's default is 2.5).
@export var intensity := 2.5
@export var color := Color(0.3, 0.8, 1.0)

var _t := 0.0
var _origin: Vector3
var _x: Vector3
var _y: Vector3
var _z: Vector3

# Shared by every beam: one material, and one mesh per widest_at shape. Guns spawn dozens
# of these a second, so building a fresh mesh and material each time adds up.
static var _shared_mat: ShaderMaterial
static var _meshes := {}


func fire(origin: Vector3, back_dir: Vector3) -> void:
	var key := snappedf(widest_at, 0.01)
	if not _meshes.has(key):
		_meshes[key] = _build_octahedron()
	mesh = _meshes[key]
	if _shared_mat == null:
		_shared_mat = ShaderMaterial.new()
		_shared_mat.shader = LaserShader
	material_override = _shared_mat
	set_instance_shader_parameter("intensity", intensity)
	set_instance_shader_parameter("color", color)
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# Local Y runs along the beam, from the ball (-0.5) to the tail (+0.5).
	_origin = origin
	_y = back_dir.normalized()
	var side := Vector3.UP if absf(_y.y) < 0.99 else Vector3.RIGHT
	_x = _y.cross(side).normalized()
	_z = _x.cross(_y)
	_update()


func _process(delta: float) -> void:
	_t += delta
	_origin += _y * shoot_speed * delta
	if _t >= lifetime:
		queue_free()
		return
	_update()


func _update() -> void:
	var grow := ease(clampf(_t / extend_time, 0.0, 1.0), 0.4)
	var fade := 1.0 - clampf((_t - extend_time) / (lifetime - extend_time), 0.0, 1.0)
	var beam_len := maxf(length * grow, 0.01)
	# Thins out as it fades.
	var w := width * lerpf(0.3, 1.0, fade)
	global_transform = Transform3D(Basis(_x * w, _y * beam_len, _z * w), _origin + _y * beam_len * 0.5)
	set_instance_shader_parameter("fade", fade)


func _build_octahedron() -> ArrayMesh:
	var front := Vector3(0, -0.5, 0)
	var back := Vector3(0, 0.5, 0)
	var mid_y := -0.5 + widest_at
	var ring := [
		Vector3(0.5, mid_y, 0), Vector3(0, mid_y, 0.5),
		Vector3(-0.5, mid_y, 0), Vector3(0, mid_y, -0.5),
	]

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 4:
		var a: Vector3 = ring[i]
		var b: Vector3 = ring[(i + 1) % 4]
		_add_flat_tri(st, front, b, a)
		_add_flat_tri(st, back, a, b)
	return st.commit()


func _add_flat_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	# One normal per face keeps the facets crisp.
	var n := (b - a).cross(c - a).normalized()
	var center := (a + b + c) / 3.0
	if n.dot(center) < 0.0:
		n = -n
	st.set_normal(n)
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)
