extends SubViewport
## Removes the freeze the first time a kill (or blast) happens on a map: the effects'
## shaders and GPU pipelines would otherwise be built at that moment. The arena adds this
## when a map loads; it renders one copy of each kill effect in a small hidden view (its
## own world, far from anything, same anti-aliasing as the screen) for a few frames, so
## everything is built while the map is still loading in, then frees itself.
## (Shaders written as files are also pre-built at export by the Shader Baker; this
## catches the materials made in code and the pipelines.)
## It also sweeps a hidden wide-angle camera round the map itself (a second small view onto
## the real world), so every surface's pipelines are built under the loading card rather
## than the first time you roll round a corner and see it.

const ShardBurst := preload("res://scripts/shard_burst.gd")
const Explosion := preload("res://scripts/explosion.gd")
const FrameShader := preload("res://shaders/impact_frame.gdshader")
const BladeDepthShader := preload("res://shaders/blade_depth.gdshader")
const ShieldDepthShader := preload("res://shaders/shield_depth.gdshader")
const BladeMesh := preload("res://scripts/energy_blade_mesh.gd")
const BladeFlare := preload("res://scripts/weapons/blade_flare.gd")
const MotionBlurShader := preload("res://shaders/motion_blur.gdshader")
## Rendered for this long (the effects need a few frames to spawn all their parts).
const LIFE := 0.6
## Far below everything, so nothing reacts to these copies (camera shake, sounds).
const AT := Vector3(0.0, -5000.0, 0.0)

var _t := 0.0
var _sweep: SubViewport
var _sweep_cam: Camera3D
## Where the sweep looks from: above the map's middle, and down at floor level.
const SWEEP_FROM := [Vector3(0.0, 25.0, 0.0), Vector3(0.0, 4.0, 0.0)]


func _ready() -> void:
	size = Vector2i(320, 180)
	own_world_3d = true
	transparent_bg = true
	render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var main := get_tree().root
	msaa_3d = main.msaa_3d
	screen_space_aa = main.screen_space_aa
	use_taa = main.use_taa
	var env_node := get_tree().current_scene.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if env_node and env_node.environment:
		var env := WorldEnvironment.new()
		env.environment = env_node.environment
		add_child(env)
	var cam := Camera3D.new()
	cam.position = AT
	add_child(cam)
	cam.make_current()
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.8, 0.4, 0.0)
	sun.shadow_enabled = true
	add_child(sun)
	# A kill: the shard burst...
	var burst := ShardBurst.new()
	burst.count = 6
	add_child(burst)
	burst.global_position = AT + Vector3(-1.5, 0.0, -6.0)
	# ...a blast (visual only, silent)...
	var blast := Explosion.new()
	blast.visual_only = true
	blast.sound = ""
	blast.radius = 2.0
	blast.spark_count = 20
	blast.chunk_count = 4
	blast.light_energy = 0.0
	blast.warp_strength = 0.0
	add_child(blast)
	blast.global_position = AT + Vector3(1.5, 0.0, -8.0)
	# ...the impact frames' full-screen effect, and the solid stand-ins it draws blades
	# and shields with.
	var quad := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(2, 2)
	quad.mesh = qm
	var frame_mat := ShaderMaterial.new()
	frame_mat.shader = FrameShader
	frame_mat.render_priority = Material.RENDER_PRIORITY_MAX
	quad.material_override = frame_mat
	quad.extra_cull_margin = 16384.0
	cam.add_child(quad)
	quad.position = Vector3(0, 0, -1)
	# The map sweep: same world as the screen, same anti-aliasing, a wide lens.
	_sweep = SubViewport.new()
	_sweep.size = Vector2i(480, 270)
	_sweep.world_3d = main.world_3d
	_sweep.msaa_3d = main.msaa_3d
	_sweep.screen_space_aa = main.screen_space_aa
	_sweep.use_taa = main.use_taa
	_sweep.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_sweep)
	_sweep_cam = Camera3D.new()
	_sweep_cam.fov = 110.0
	_sweep_cam.far = 6000.0
	_sweep.add_child(_sweep_cam)
	_sweep_cam.make_current()
	# What appears the moment the map intro ends: a weapon's pentagons (see-through, so their
	# own pipeline), its equip flare, the flash light that rides with it, and the camera's
	# motion blur.
	var blade := BladeMesh.new()
	add_child(blade)
	blade.global_position = AT + Vector3(0.0, 0.0, -4.0)
	var flare := BladeFlare.new()
	flare.mesh = blade.mesh
	flare.lifetime = LIFE
	blade.add_child(flare)
	var omni := OmniLight3D.new()
	omni.omni_range = 10.0
	omni.light_energy = 4.0
	add_child(omni)
	omni.global_position = AT + Vector3(0.0, 1.0, -3.0)
	var blur := MeshInstance3D.new()
	var blur_quad := QuadMesh.new()
	blur_quad.size = Vector2(2, 2)
	blur.mesh = blur_quad
	var blur_mat := ShaderMaterial.new()
	blur_mat.shader = MotionBlurShader
	blur_mat.render_priority = Material.RENDER_PRIORITY_MIN
	blur.material_override = blur_mat
	blur.extra_cull_margin = 16384.0
	cam.add_child(blur)
	blur.position = Vector3(0, 0, -1)
	for shader in [BladeDepthShader, ShieldDepthShader]:
		var box := MeshInstance3D.new()
		box.mesh = BoxMesh.new()
		var mat := ShaderMaterial.new()
		mat.shader = shader
		box.material_override = mat
		add_child(box)
		box.global_position = AT + Vector3(0.0, -1.0, -5.0)


## Draws a copy of each of these (the map's merged pieces, made ahead of the build-in), tiny
## and in front of the hidden camera, so their shaders are built now.
func add_samples(meshes: Array) -> void:
	var i := 0
	for m in meshes:
		var src := m as MeshInstance3D
		if not src:
			continue
		var copy := MeshInstance3D.new()
		copy.mesh = src.mesh
		copy.material_override = src.material_override
		copy.cast_shadow = src.cast_shadow
		add_child(copy)
		var aabb := src.mesh.get_aabb()
		var fit := 1.5 / maxf(aabb.get_longest_axis_size(), 0.01)
		copy.global_transform = Transform3D(Basis().scaled(Vector3.ONE * fit), AT + Vector3((i % 7) - 3.0, (i / 7 % 5) - 2.0, -9.0) - aabb.get_center() * fit)
		i += 1


func _process(delta: float) -> void:
	_t += delta
	# Round the compass (and up / down) from each sweep point in turn.
	if _sweep_cam:
		var k := clampf(_t / LIFE, 0.0, 0.999)
		var from: Vector3 = SWEEP_FROM[int(k * SWEEP_FROM.size())]
		var turn := fmod(k * SWEEP_FROM.size(), 1.0)
		_sweep_cam.global_position = from
		_sweep_cam.global_rotation = Vector3(sin(turn * TAU * 3.0) * 0.6 - 0.25, turn * TAU * 2.0, 0.0)
	if _t >= LIFE:
		queue_free()
