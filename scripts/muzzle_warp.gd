extends MeshInstance3D
## Short-lived expanding bubble of screen distortion. Frees itself when done.

const WarpShader := preload("res://shaders/muzzle_warp.gdshader")

@export var start_radius := 0.15
@export var end_radius := 1.0
@export var lifetime := 0.14
@export var strength := 0.07

var _t := 0.0

# Shared by every bubble (every shot makes one).
static var _shared_mat: ShaderMaterial
static var _sphere: SphereMesh


func _ready() -> void:
	if _shared_mat == null:
		_sphere = SphereMesh.new()
		_sphere.radius = 0.5
		_sphere.height = 1.0
		_sphere.radial_segments = 16
		_sphere.rings = 8
		_shared_mat = ShaderMaterial.new()
		_shared_mat.shader = WarpShader
		_shared_mat.render_priority = Material.RENDER_PRIORITY_MIN + 1
	mesh = _sphere
	# Drawn before the crystal blades: the warp re-draws a copy of the screen taken before
	# any see-through objects, so drawn after them it would erase any blade inside it.
	material_override = _shared_mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_update()


func _process(delta: float) -> void:
	_t += delta
	if _t >= lifetime:
		queue_free()
		return
	_update()


func _update() -> void:
	var k := _t / lifetime
	var r := lerpf(start_radius, end_radius, ease(k, 0.4))
	scale = Vector3.ONE * r * 2.0
	set_instance_shader_parameter("strength", strength * (1.0 - k))
