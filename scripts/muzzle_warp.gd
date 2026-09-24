extends MeshInstance3D
## Short-lived expanding bubble of screen distortion. Frees itself when done.

const WarpShader := preload("res://shaders/muzzle_warp.gdshader")

@export var start_radius := 0.15
@export var end_radius := 1.0
@export var lifetime := 0.14
@export var strength := 0.07

var _t := 0.0
var _mat: ShaderMaterial


func _ready() -> void:
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.radial_segments = 16
	sphere.rings = 8
	mesh = sphere
	_mat = ShaderMaterial.new()
	_mat.shader = WarpShader
	material_override = _mat
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
	_mat.set_shader_parameter("strength", strength * (1.0 - k))
