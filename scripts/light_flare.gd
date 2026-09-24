extends MeshInstance3D
## One-shot lens-flare burst: pops in, then fades and shrinks. Always faces the camera,
## and sits slightly toward it so surfaces it's spawned on don't cut it off.
## Set position before adding it to the tree. Frees itself when done.

const FlareShader := preload("res://shaders/light_flare.gdshader")
const ASPECT := 3.0

@export var size := 1.0
@export var lifetime := 0.12
@export var color := Color(0.4, 0.85, 1.0)
@export var intensity := 5.0

var _t := 0.0
var _mat: ShaderMaterial


func _ready() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(ASPECT, 1.0)
	mesh = quad
	_mat = ShaderMaterial.new()
	_mat.shader = FlareShader
	_mat.set_shader_parameter("color", color)
	_mat.set_shader_parameter("intensity", intensity)
	_mat.set_shader_parameter("aspect", ASPECT)
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF

	var camera := get_viewport().get_camera_3d()
	if camera:
		global_position += (camera.global_position - global_position).normalized() * 0.6
	_update()


func _process(delta: float) -> void:
	_t += delta
	if _t >= lifetime:
		queue_free()
		return
	_update()


func _update() -> void:
	var k := _t / lifetime
	# Snap open fast, then shrink a little as it fades.
	var open := ease(minf(k * 5.0, 1.0), 0.3)
	scale = Vector3.ONE * size * lerpf(0.5, 1.0, open) * lerpf(1.0, 0.8, k)
	_mat.set_shader_parameter("fade", pow(1.0 - k, 1.5))
