extends Node3D
## Explosion shared by the weapons (railgun impact, Nova blast, Swarm missiles).
## On spawn it damages everything with take_hit() in range, throws rigid bodies outward
## (both falling off with distance) and can mark/stagger targets. Then it plays: a burst
## of glowing sparks that bounce off the map, crystal chunks, an expanding shockwave
## shell, a screen warp, and a light + lens flare.
## Spawn it during a physics step (the blast queries the physics world in _ready).
## Set position before adding it to the tree. Frees itself when done.

const ShardBurst := preload("res://scripts/shard_burst.gd")
const ShockShader := preload("res://shaders/shockwave.gdshader")
const Sfx := preload("res://scripts/sfx.gd")

@export var radius := 7.0
@export var damage := 12.0
## Full damage anywhere in the radius instead of falling off toward the edge.
@export var full_damage := false
## Goes through players' shields and can't be parried (staff weapons).
@export var unblockable := false
## Outward impulse on rigid bodies at the center (falls to 0 at the edge).
@export var force := 30.0
@export var color := Color(1.0, 0.5, 0.1)
@export var shock_time := 0.35
@export var spark_count := 250
@export var spark_speed := 28.0
@export var spark_lifetime := 1.3
@export var chunk_count := 30
@export var light_energy := 250.0
@export var warp_strength := 0.35
## Seconds of mark (Swarm) / stagger (Nova) applied to targets in range; 0 = none.
@export var mark_time := 0.0
@export var stagger_time := 0.0
## Keep sparks close to horizontal (a ring rather than a ball), for ground blasts.
@export var flat_sparks := false
## Sound to play (scripts/sfx.gd name). Louder the bigger the blast.
@export var sound := "boom"

## The weapon manager, for the shared light/flare/warp helpers.
var manager: Node
## Physics bodies the blast should ignore (the ball).
var exclude: Array[RID] = []
## Another player's explosion shown on this computer: looks the same, hurts nothing.
var visual_only := false

var _t := 0.0
var _shock: MeshInstance3D
var _shock_mat: ShaderMaterial


func _ready() -> void:
	if not visual_only:
		_blast()
	if spark_count > 0:
		_spawn_sparks()
	if chunk_count > 0:
		var chunks := ShardBurst.new()
		chunks.color = color
		chunks.count = chunk_count
		chunks.speed = spark_speed * 0.45
		chunks.lifetime = 1.4
		add_child(chunks)
	_spawn_shock()
	if sound != "":
		# Every computer makes its own copy of the blast, so no need to send the sound.
		Sfx.play_at(get_tree(), sound, global_position, lerpf(-6.0, 6.0, clampf(radius / 16.0, 0.0, 1.0)), clampf(8.0 / radius, 0.7, 1.3))
	if manager:
		if warp_strength > 0.0:
			manager.spawn_warp(global_position, warp_strength, radius * 0.9)
		manager.spawn_light(global_position + Vector3.UP * 0.5, light_energy, radius * 5.0, 0.4, color)


func _process(delta: float) -> void:
	_t += delta
	if _shock:
		var k := minf(_t / shock_time, 1.0)
		_shock.scale = Vector3.ONE * radius * 2.0 * ease(k, 0.3)
		_shock_mat.set_shader_parameter("fade", 1.0 - k)
		if k >= 1.0:
			_shock.queue_free()
			_shock = null
	if _t > maxf(spark_lifetime, 1.4) + 0.3:
		queue_free()


func _blast() -> void:
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY, global_position)
	query.exclude = exclude
	var seen := {}
	for result in get_world_3d().direct_space_state.intersect_shape(query, 64):
		var body: Object = result["collider"]
		if seen.has(body):
			continue
		seen[body] = true
		# Measure to the part that matters (a dummy's disc, not the foot of its post).
		var body_pos: Vector3 = (body as Node3D).global_position
		if body.has_method("get_aim_point"):
			body_pos = body.call("get_aim_point")
		var offset := body_pos - global_position
		var falloff := clampf(1.0 - offset.length() / radius, 0.0, 1.0)
		if falloff <= 0.0:
			continue
		var dir := offset.normalized() if offset.length() > 0.01 else Vector3.UP
		# Status first, so a mark applied by this blast already counts for its damage.
		if mark_time > 0.0 and body.has_method("mark"):
			body.call("mark", mark_time)
		if stagger_time > 0.0 and body.has_method("stagger"):
			body.call("stagger", stagger_time)
		if damage > 0.0 and body.has_method("take_hit"):
			var dealt := damage if full_damage else damage * falloff
			if unblockable and body.has_method("take_unblockable_hit"):
				body.call("take_unblockable_hit", dealt, body_pos, dir)
			else:
				body.call("take_hit", dealt, body_pos, dir)
			if manager:
				manager.call("report_damage", body, dealt, body_pos)
		if body.has_method("receive_impulse"):
			# Players are pushed through the network.
			body.call("receive_impulse", (dir + Vector3.UP * 0.4).normalized() * force * falloff)
			continue
		var rigid := body as RigidBody3D
		if rigid and force > 0.0:
			rigid.sleeping = false
			# A little upward bias so things get thrown, not just slid.
			rigid.apply_central_impulse((dir + Vector3.UP * 0.4).normalized() * force * falloff)


func _spawn_sparks() -> void:
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1))
	curve.add_point(Vector2(1, 0))
	var scale_tex := CurveTexture.new()
	scale_tex.curve = curve

	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.3, 1.0])
	gradient.colors = PackedColorArray([
		Color(4.0, 4.0, 4.0),
		Color(color.r * 3.0, color.g * 3.0, color.b * 3.0),
		Color(color.r * 0.3, color.g * 0.3, color.b * 0.3, 0.0),
	])
	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient
	ramp.use_hdr = true

	var process := ParticleProcessMaterial.new()
	process.particle_flag_align_y = true
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.4
	if flat_sparks:
		# Emit in the horizontal plane: a ring blowing outward.
		process.direction = Vector3.RIGHT
		process.spread = 180.0
		process.flatness = 0.85
	else:
		process.direction = Vector3.UP
		process.spread = 180.0
	process.initial_velocity_min = spark_speed * 0.3
	process.initial_velocity_max = spark_speed
	process.gravity = Vector3(0, -14, 0)
	process.damping_min = 2.0
	process.damping_max = 5.0
	process.scale_min = 0.6
	process.scale_max = 1.6
	process.scale_curve = scale_tex
	process.color_ramp = ramp
	process.collision_mode = ParticleProcessMaterial.COLLISION_RIGID
	process.collision_bounce = 0.5
	process.collision_friction = 0.2

	var spark_mat := StandardMaterial3D.new()
	spark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spark_mat.vertex_color_use_as_albedo = true
	var spark_mesh := BoxMesh.new()
	spark_mesh.size = Vector3(0.05, 0.45, 0.05)
	spark_mesh.material = spark_mat

	var sparks := GPUParticles3D.new()
	sparks.amount = spark_count
	sparks.lifetime = spark_lifetime
	sparks.one_shot = true
	sparks.explosiveness = 1.0
	sparks.fixed_fps = 120
	sparks.collision_base_size = 0.03
	sparks.process_material = process
	sparks.draw_pass_1 = spark_mesh
	sparks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sparks.visibility_aabb = AABB(Vector3(-40, -10, -40), Vector3(80, 50, 80))
	add_child(sparks)
	sparks.emitting = true


func _spawn_shock() -> void:
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.radial_segments = 32
	sphere.rings = 16
	_shock_mat = ShaderMaterial.new()
	_shock_mat.shader = ShockShader
	_shock_mat.set_shader_parameter("color", color)
	_shock = MeshInstance3D.new()
	_shock.mesh = sphere
	_shock.material_override = _shock_mat
	_shock.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_shock.scale = Vector3.ONE * 0.01
	add_child(_shock)
