extends MeshInstance3D
## A flare in the shape of a blade: a glowing shell of the blade's own mesh that swells
## and fades. Add it as a child of the blade so it follows every move. Frees itself.

const FlareShader := preload("res://shaders/blade_flare.gdshader")

@export var color := Color(0.3, 0.8, 1.0)
@export var lifetime := 0.4
@export var intensity := 8.0
## Shell offset from the blade at the start and end of the flare.
@export var grow_start := 0.02
@export var grow_end := 0.14

var _t := 0.0
var _mat: ShaderMaterial


func _ready() -> void:
	_mat = ShaderMaterial.new()
	_mat.shader = FlareShader
	_mat.set_shader_parameter("color", color)
	_mat.set_shader_parameter("intensity", intensity)
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
	_mat.set_shader_parameter("grow", lerpf(grow_start, grow_end, ease(k, 0.4)))
	_mat.set_shader_parameter("fade", pow(1.0 - k, 1.6))
