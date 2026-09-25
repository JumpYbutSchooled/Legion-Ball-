extends MeshInstance3D
## The block shield (Q). The ball's polygons lift off and fly outward, then widen until
## they lock together into a glowing shell; it holds, then the faces shrink and fall
## back onto the ball. Built from the ball's own Goldberg faces (goldberg_ball_mesh.gd).
## Top-level: it follows the ball but doesn't spin with it while it rolls.

const ShieldShader := preload("res://shaders/shield.gdshader")

## Seconds for the faces to fly out, and to widen into a shell.
const OUT_TIME := 0.14
const GROW_TIME := 0.1
## Seconds to fold back into the ball at the end.
const RETRACT_TIME := 0.2

var ball: Node3D
var color := Color(0.55, 0.4, 1.0)

var _mat: ShaderMaterial
var _t := -1.0
var _duration := 1.0
var _flash := 0.0


func setup(source: MeshInstance3D) -> void:
	mesh = source.call("build_shell_mesh")
	_mat = ShaderMaterial.new()
	_mat.shader = ShieldShader
	_mat.set_shader_parameter("color", color)
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	# The mesh sits on the ball's surface at rest; the shader pushes it well outside.
	extra_cull_margin = 2.0
	visible = false


## Raise the shield for `duration` seconds (retract included).
func play(duration: float) -> void:
	_duration = maxf(duration, OUT_TIME + GROW_TIME + RETRACT_TIME)
	_t = 0.0
	visible = true
	if ball:
		global_basis = ball.global_basis


## Drop it early: jump straight to the retract.
func stop() -> void:
	if _t >= 0.0:
		_t = maxf(_t, _duration - RETRACT_TIME)


## A hit landed on it.
func hit_flash() -> void:
	_flash = 1.0


func _process(delta: float) -> void:
	if _t < 0.0:
		return
	_t += delta
	_flash = move_toward(_flash, 0.0, delta * 3.0)
	if ball:
		global_position = ball.get_global_transform_interpolated().origin
	var out := clampf(_t / OUT_TIME, 0.0, 1.0)
	var grow := clampf((_t - OUT_TIME) / GROW_TIME, 0.0, 1.0)
	var back := clampf((_t - (_duration - RETRACT_TIME)) / RETRACT_TIME, 0.0, 1.0)
	# Retract: the shell breaks into faces first, then they sink back into the ball.
	grow = minf(grow, 1.0 - clampf(back * 2.0, 0.0, 1.0))
	out = minf(out, 1.0 - back)
	_mat.set_shader_parameter("out_amount", out)
	_mat.set_shader_parameter("grow", grow)
	_mat.set_shader_parameter("flash", _flash)
	_mat.set_shader_parameter("fade", clampf(out * 3.0, 0.0, 1.0))
	if _t >= _duration:
		_t = -1.0
		visible = false
