extends MeshInstance3D
## Drives the camera motion blur quad. Must be a child of the Camera3D.
## Feeds the shader this frame's and last frame's world->clip matrices, and masks
## a circle around the ball so it stays sharp.

const BlurShader := preload("res://shaders/motion_blur.gdshader")
const SettingsScript := preload("res://scripts/settings.gd")

@export var ball: Node3D
@export_range(0.0, 2.0) var strength := 0.5
@export var max_blur := 0.04
## World-space radius around the ball kept sharp (covers the blades).
@export var mask_world_radius := 2.2

var _mat: ShaderMaterial
var _prev := Projection.IDENTITY
var _has_prev := false


func _ready() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(2, 2)
	mesh = quad
	_mat = ShaderMaterial.new()
	_mat.shader = BlurShader
	# Draw first among transparents, so everything transparent lands on top unblurred.
	_mat.render_priority = Material.RENDER_PRIORITY_MIN
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The vertex shader places it in clip space; never let it get frustum-culled.
	extra_cull_margin = 16384.0
	# After the camera rig has moved the camera this frame.
	process_priority = 1000
	# Strength follows the player's Motion Blur setting.
	strength = SettingsScript.read(get_tree(), "motion_blur")
	var settings := get_tree().root.get_node_or_null("Settings")
	if settings:
		settings.connect("changed", func() -> void:
			strength = SettingsScript.read(get_tree(), "motion_blur"))


func _process(_delta: float) -> void:
	var camera := get_parent() as Camera3D
	if not camera:
		return
	var curr := camera.get_camera_projection() * Projection(camera.global_transform.affine_inverse())
	if not _has_prev:
		_prev = curr
		_has_prev = true
	_mat.set_shader_parameter("curr_view_proj", curr)
	_mat.set_shader_parameter("prev_view_proj", _prev)
	_mat.set_shader_parameter("strength", strength)
	# The pass costs a full-screen read with 10 samples a pixel: skip it when the camera
	# has barely moved since last frame, since there'd be nothing to smear.
	var moved := (curr.x - _prev.x).length() + (curr.y - _prev.y).length() \
		+ (curr.z - _prev.z).length() + (curr.w - _prev.w).length()
	visible = strength > 0.0 and moved > 0.002
	_mat.set_shader_parameter("max_blur", max_blur)
	_prev = curr

	var ball_pos := ball.get_global_transform_interpolated().origin if ball else Vector3.ZERO
	if ball and not camera.is_position_behind(ball_pos):
		var size := camera.get_viewport().get_visible_rect().size
		var center := camera.unproject_position(ball_pos)
		var edge := camera.unproject_position(ball_pos + camera.global_basis.x * mask_world_radius)
		_mat.set_shader_parameter("mask_center", center / size)
		_mat.set_shader_parameter("mask_radius", center.distance_to(edge) / size.y)
	else:
		_mat.set_shader_parameter("mask_radius", 0.0)