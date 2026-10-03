extends SubViewport
## Removes the freeze the first time a kill (or blast) happens on a map: the effects'
## shaders and GPU pipelines would otherwise be built at that moment. The arena adds this
## when a map loads; it renders one copy of each kill effect in a small hidden view (its
## own world, far from anything, same anti-aliasing as the screen) for a few frames, so
## everything is built while the map is still loading in, then frees itself.
## (Shaders written as files are also pre-built at export by the Shader Baker; this
## catches the materials made in code and the pipelines.)

const ShardBurst := preload("res://scripts/shard_burst.gd")
const Explosion := preload("res://scripts/explosion.gd")
const FrameShader := preload("res://shaders/impact_frame.gdshader")
const BladeDepthShader := preload("res://shaders/blade_depth.gdshader")
const ShieldDepthShader := preload("res://shaders/shield_depth.gdshader")
## Rendered for this long (the effects need a few frames to spawn all their parts).
const LIFE := 0.6
## Far below everything, so nothing reacts to these copies (camera shake, sounds).
const AT := Vector3(0.0, -5000.0, 0.0)

var _t := 0.0


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
	for shader in [BladeDepthShader, ShieldDepthShader]:
		var box := MeshInstance3D.new()
		box.mesh = BoxMesh.new()
		var mat := ShaderMaterial.new()
		mat.shader = shader
		box.material_override = mat
		add_child(box)
		box.global_position = AT + Vector3(0.0, -1.0, -5.0)


func _process(delta: float) -> void:
	_t += delta
	if _t >= LIFE:
		queue_free()
