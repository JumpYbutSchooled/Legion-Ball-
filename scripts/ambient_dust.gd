extends GPUParticles3D
## Dust in the air, like Rocket League's arenas: soft specks drifting slowly around
## whatever camera is looking (it follows it), twinkling as they catch the light and
## blooming a little, tinted by the map's sun. GPU particles, so it costs next to nothing;
## graphics.gd adds it to every map (not on LOW).

const COUNT := 420
const BOX := Vector3(36.0, 18.0, 36.0)

var tint := Color(1.0, 0.95, 0.85)


func _ready() -> void:
	amount = COUNT
	lifetime = 9.0
	preprocess = 9.0  # already full when the map appears
	local_coords = false
	visibility_aabb = AABB(-BOX * 2.0, BOX * 4.0)
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = BOX * 0.5
	pm.direction = Vector3(0.3, 0.15, 0.2)
	pm.spread = 180.0
	pm.initial_velocity_min = 0.05
	pm.initial_velocity_max = 0.35
	pm.gravity = Vector3(0.0, -0.02, 0.0)
	# Lazy swirling.
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.6
	pm.turbulence_noise_scale = 6.0
	pm.turbulence_noise_speed_random = 0.4
	pm.turbulence_influence_min = 0.05
	pm.turbulence_influence_max = 0.12
	pm.scale_min = 0.5
	pm.scale_max = 1.6
	# Fade in, twinkle, fade out.
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.15, 0.3, 0.45, 0.6, 0.8, 1.0])
	fade.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0.9), Color(1, 1, 1, 0.45),
		Color(1, 1, 1, 1.0), Color(1, 1, 1, 0.5), Color(1, 1, 1, 0.85), Color(1, 1, 1, 0)])
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	pm.color_ramp = ramp
	process_material = pm
	# Each speck: a small soft dot facing the camera, glowing just past the bloom threshold.
	var quad := QuadMesh.new()
	quad.size = Vector2(0.09, 0.09)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(tint.r * 2.2, tint.g * 2.2, tint.b * 2.2, 0.7)
	mat.albedo_texture = _soft_dot()
	mat.disable_receive_shadows = true
	quad.material = mat
	draw_pass_1 = quad


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam:
		global_position = cam.global_position


## A round dot with a soft edge.
static func _soft_dot() -> Texture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.5), Color(1, 1, 1, 0)])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 32
	t.height = 32
	return t
