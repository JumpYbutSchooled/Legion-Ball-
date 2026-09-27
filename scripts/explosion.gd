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
## Anyone whose camera is within this many metres gets impact frames when it goes off
## (0 = none), styled as weapon `impact_frame_id`. The player who set it off also
## gets the hitstop. (Pillars of God.)
@export var impact_frame_range := 0.0
@export var impact_frame_id := "pillars_of_god"
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
var _shock2: MeshInstance3D
var _shock2_mat: ShaderMaterial
var _core: MeshInstance3D
var _core_mat: StandardMaterial3D
var _ring: MeshInstance3D
var _ring_mat: StandardMaterial3D

## White-hot flash at the centre, gone in a blink.
const CORE_TIME := 0.16
## How long the smoke hangs around (the blast frees itself after).
const SMOKE_TIME := 2.6
## Sparks per blast compared to a weapon's spark_count.
const SPARK_BOOST := 2.0

# Shared by every blast: the soft round puff texture and the particle materials (colour
# comes from each blast's own colour ramp, through vertex colour).
static var _puff_tex: GradientTexture2D
## Blasts alive right now. When lots go off together (Swarm volleys) the extra layers are
## thinned out so the frame rate holds.
static var _live := 0
static var _cache := {}
static var _meshes := {}
const BUSY := 5

## 1 = full effects, lower when many blasts are going at once.
var _detail := 1.0
static var _glow_mat: StandardMaterial3D
static var _smoke_mat: StandardMaterial3D


func _ready() -> void:
	_shared()
	_live += 1
	_detail = clampf(float(BUSY) / float(_live), 0.25, 1.0)
	if not visual_only:
		_blast()
	if impact_frame_range > 0.0:
		var cam := get_viewport().get_camera_3d()
		if cam and cam.global_position.distance_to(global_position) <= impact_frame_range:
			get_tree().call_group("impact_frames", "trigger", global_position, color, impact_frame_id, not visual_only)
	if spark_count > 0:
		_spawn_sparks()
	if chunk_count > 0:
		var chunks := ShardBurst.new()
		chunks.color = color
		chunks.count = int(chunk_count * 1.6)
		chunks.speed = spark_speed * 0.5
		chunks.lifetime = 1.6
		add_child(chunks)
	_spawn_core()
	_spawn_fireball()
	if _live <= BUSY:
		_spawn_smoke()
	_spawn_embers()
	_spawn_shock()
	_spawn_ground_ring()
	get_tree().call_group("camera_rig", "blast_nearby", global_position, radius)
	if sound != "":
		# Every computer makes its own copy of the blast, so no need to send the sound.
		Sfx.play_at(get_tree(), sound, global_position, lerpf(-6.0, 6.0, clampf(radius / 16.0, 0.0, 1.0)), clampf(8.0 / radius, 0.7, 1.3))
	if manager:
		if warp_strength > 0.0:
			# A sharp inner pop, then a wide slow ripple. Not sent: every computer makes its
			# own copy of the blast (and with it these).
			manager.call("_warp", global_position, warp_strength * 1.5, radius * 0.8)
			manager.call("_warp", global_position, warp_strength, radius * 1.8)
		manager.spawn_light(global_position + Vector3.UP * 0.5, light_energy, radius * 5.0, 0.45, color)


func _exit_tree() -> void:
	_live -= 1


func _process(delta: float) -> void:
	_t += delta
	if _shock:
		var k := minf(_t / shock_time, 1.0)
		_shock.scale = Vector3.ONE * radius * 2.0 * ease(k, 0.3)
		_shock_mat.set_shader_parameter("fade", 1.0 - k)
		if k >= 1.0:
			_shock.queue_free()
			_shock = null
	if _shock2:
		# Slower, wider echo of the first shell.
		var k2 := minf(_t / (shock_time * 2.2), 1.0)
		_shock2.scale = Vector3.ONE * radius * 3.4 * ease(k2, 0.25)
		_shock2_mat.set_shader_parameter("fade", (1.0 - k2) * 0.35)
		if k2 >= 1.0:
			_shock2.queue_free()
			_shock2 = null
	if _core:
		var kc := minf(_t / CORE_TIME, 1.0)
		_core.scale = Vector3.ONE * radius * lerpf(0.25, 0.75, ease(kc, 0.4))
		_core_mat.albedo_color = Color(2.2, 2.2, 2.2, 0.7).lerp(Color(color.r * 3.0, color.g * 3.0, color.b * 3.0, 0.0), kc)
		if kc >= 1.0:
			_core.queue_free()
			_core = null
	if _ring:
		var kr := minf(_t / (shock_time * 1.8), 1.0)
		var r := radius * 2.8 * ease(kr, 0.3)
		_ring.scale = Vector3(r, 1.0 + r * 0.05, r)
		_ring_mat.albedo_color = Color(color.r * 4.0, color.g * 4.0, color.b * 4.0, 1.0 - kr)
		if kr >= 1.0:
			_ring.queue_free()
			_ring = null
	if _t > maxf(spark_lifetime, SMOKE_TIME) + 0.3:
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
	var made: Array = _cached("sparks", _make_sparks)
	var process: ParticleProcessMaterial = made[0]
	var spark_mesh: BoxMesh = made[1]
	var sparks := GPUParticles3D.new()
	sparks.amount = maxi(int(spark_count * lerpf(1.0, SPARK_BOOST, _detail)), 1)
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
	var sphere := _mesh("shell")
	_shock_mat = ShaderMaterial.new()
	_shock_mat.shader = ShockShader
	_shock_mat.set_shader_parameter("color", color)
	_shock = MeshInstance3D.new()
	_shock.mesh = sphere
	_shock.material_override = _shock_mat
	_shock.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_shock.scale = Vector3.ONE * 0.01
	add_child(_shock)
	if _live <= BUSY:
		_spawn_shock2()


func _spawn_shock2() -> void:
	var sphere := _mesh("shell")
	_shock2_mat = ShaderMaterial.new()
	_shock2_mat.shader = ShockShader
	_shock2_mat.set_shader_parameter("color", color.lerp(Color.WHITE, 0.25))
	_shock2_mat.set_shader_parameter("intensity", 1.2)
	_shock2 = MeshInstance3D.new()
	_shock2.mesh = sphere
	_shock2.material_override = _shock2_mat
	_shock2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_shock2.scale = Vector3.ONE * 0.01
	add_child(_shock2)


## Blinding white ball at the centre that swells and turns the blast's colour.
func _spawn_core() -> void:
	var sphere := _mesh("core")
	_core_mat = StandardMaterial3D.new()
	_core_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_core_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_core_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_core_mat.albedo_color = Color(2.2, 2.2, 2.2, 0.7)
	_core = MeshInstance3D.new()
	_core.mesh = sphere
	_core.material_override = _core_mat
	_core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_core.scale = Vector3.ONE * radius * 0.35
	add_child(_core)


## Flat glowing ring racing out along the ground.
func _spawn_ground_ring() -> void:
	var torus := _mesh("ring")
	_ring_mat = StandardMaterial3D.new()
	_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ring_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_ring_mat.albedo_color = Color(color.r * 4.0, color.g * 4.0, color.b * 4.0)
	_ring = MeshInstance3D.new()
	_ring.mesh = torus
	_ring.material_override = _ring_mat
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.scale = Vector3(0.01, 1.0, 0.01)
	add_child(_ring)


## Meshes every blast shares (they're only ever scaled).
static func _mesh(kind: String) -> Mesh:
	if not _meshes.has(kind):
		match kind:
			"ring":
				var torus := TorusMesh.new()
				torus.inner_radius = 0.93
				torus.outer_radius = 1.0
				torus.rings = 48
				torus.ring_segments = 6
				_meshes[kind] = torus
			_:
				var sphere := SphereMesh.new()
				sphere.radius = 0.5
				sphere.height = 1.0
				sphere.radial_segments = 32 if kind == "shell" else 20
				sphere.rings = 16 if kind == "shell" else 10
				_meshes[kind] = sphere
	return _meshes[kind]


static func _shared() -> void:
	if _puff_tex:
		return
	var soft := Gradient.new()
	soft.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	soft.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.75), Color(1, 1, 1, 0)])
	_puff_tex = GradientTexture2D.new()
	_puff_tex.gradient = soft
	_puff_tex.fill = GradientTexture2D.FILL_RADIAL
	_puff_tex.fill_from = Vector2(0.5, 0.5)
	_puff_tex.fill_to = Vector2(1.0, 0.5)
	_puff_tex.width = 64
	_puff_tex.height = 64
	_glow_mat = StandardMaterial3D.new()
	_glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_glow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_glow_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_glow_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	_glow_mat.vertex_color_use_as_albedo = true
	_glow_mat.albedo_texture = _puff_tex
	_glow_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	# Soft edges where puffs cut into the floor and walls (no hard straight lines).
	_glow_mat.proximity_fade_enabled = true
	_glow_mat.proximity_fade_distance = 2.5
	_smoke_mat = _glow_mat.duplicate() as StandardMaterial3D
	_smoke_mat.blend_mode = BaseMaterial3D.BLEND_MODE_MIX


## Particle system of soft billboard puffs, emitting all at once.
func _puffs(kind: String, count: int, lifetime: float, make: Callable) -> GPUParticles3D:
	var made: Array = _cached(kind, func() -> Array:
		var parts: Array = make.call()
		return _puff_look(parts[0], parts[1], parts[2]))
	var p := GPUParticles3D.new()
	p.amount = maxi(count, 1)
	p.lifetime = lifetime
	p.one_shot = true
	p.explosiveness = 1.0
	p.randomness = 0.4
	p.fixed_fps = 60
	# Only see-through (not glowing) puffs need sorting; sorting costs every frame.
	if made[1].material == _smoke_mat:
		p.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	p.process_material = made[0]
	p.draw_pass_1 = made[1]
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-radius * 4.0, -radius * 2.0, -radius * 4.0), Vector3(radius * 8.0, radius * 8.0, radius * 8.0))
	add_child(p)
	p.emitting = true
	return p


## Materials and textures for a blast are built once per look (weapon colour, size...) and
## reused by every later blast that looks the same: much cheaper when lots go off.
func _cached(kind: String, make: Callable) -> Array:
	var key := "%s|%s|%.2f|%s|%.1f" % [kind, color.to_html(), radius, flat_sparks, spark_speed]
	if not _cache.has(key):
		if _cache.size() > 256:
			_cache.clear()
		_cache[key] = make.call()
	return _cache[key]


## [process material, quad] for a puff system: `ramp` colours spread evenly over its life.
func _puff_look(process: ParticleProcessMaterial, mat: StandardMaterial3D, ramp: Array) -> Array:
	var gradient := Gradient.new()
	var offsets := PackedFloat32Array()
	var colors := PackedColorArray()
	for i in ramp.size():
		offsets.append(float(i) / float(ramp.size() - 1))
		colors.append(ramp[i])
	gradient.offsets = offsets
	gradient.colors = colors
	var ramp_tex := GradientTexture1D.new()
	ramp_tex.gradient = gradient
	ramp_tex.use_hdr = true
	process.color_ramp = ramp_tex
	process.angle_min = 0.0
	process.angle_max = 360.0
	var quad := QuadMesh.new()
	quad.material = mat
	return [process, quad]


func _grow_curve(from: float, to: float) -> CurveTexture:
	var curve := Curve.new()
	# Points are clamped to the curve's range, which is 0-1 unless widened.
	curve.max_value = maxf(1.0, maxf(from, to))
	curve.add_point(Vector2(0, from))
	curve.add_point(Vector2(1, to))
	var tex := CurveTexture.new()
	tex.curve = curve
	return tex


## Rolling ball of fire: big glowing puffs thrown out that stall and burn out.
func _spawn_fireball() -> void:
	_puffs("fireball", clampi(int(radius * 6.0 * _detail), 6, 70), 0.75, func() -> Array:
		var process := ParticleProcessMaterial.new()
		process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		process.emission_sphere_radius = radius * 0.15
		process.direction = Vector3.UP
		process.spread = 180.0
		if flat_sparks:
			process.flatness = 0.6
		process.initial_velocity_min = radius * 0.8
		process.initial_velocity_max = radius * 2.2
		process.damping_min = radius * 2.5
		process.damping_max = radius * 4.0
		process.gravity = Vector3(0, 1.5, 0)
		process.scale_min = radius * 0.22
		process.scale_max = radius * 0.45
		process.scale_curve = _grow_curve(0.5, 1.2)
		var c := color
		return [process, _glow_mat, [
			Color(2.0, 1.8, 1.5, 0.6),
			Color(c.r * 2.4 + 0.3, c.g * 1.8 + 0.15, c.b * 1.8, 0.6),
			Color(c.r * 1.2, c.g * 0.7, c.b * 0.7, 0.3),
			Color(c.r * 0.3, c.g * 0.15, c.b * 0.15, 0.0),
		]])


## Dark smoke that billows out and drifts up after the flash.
func _spawn_smoke() -> void:
	_puffs("smoke", clampi(int(radius * 3.5), 8, 40), SMOKE_TIME, func() -> Array:
		var process := ParticleProcessMaterial.new()
		process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		process.emission_sphere_radius = radius * 0.3
		process.direction = Vector3.UP
		process.spread = 180.0
		if flat_sparks:
			process.flatness = 0.5
		process.initial_velocity_min = radius * 0.4
		process.initial_velocity_max = radius * 1.4
		process.damping_min = radius * 0.6
		process.damping_max = radius * 1.2
		process.gravity = Vector3(0, 2.2, 0)
		process.scale_min = radius * 0.4
		process.scale_max = radius * 0.8
		process.scale_curve = _grow_curve(0.4, 1.6)
		var tint := color.lerp(Color(0.18, 0.16, 0.15), 0.75)
		return [process, _smoke_mat, [
			Color(tint.r, tint.g, tint.b, 0.0),
			Color(tint.r, tint.g, tint.b, 0.75),
			Color(0.16, 0.15, 0.15, 0.55),
			Color(0.05, 0.05, 0.06, 0.0),
		]])


## Glowing embers that float and swirl after the blast.
func _spawn_embers() -> void:
	_puffs("embers", clampi(int(radius * 22.0 * _detail), 20, 260), 2.2, func() -> Array:
		var process := ParticleProcessMaterial.new()
		process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		process.emission_sphere_radius = radius * 0.3
		process.direction = Vector3.UP
		process.spread = 180.0
		process.initial_velocity_min = spark_speed * 0.15
		process.initial_velocity_max = spark_speed * 0.6
		process.damping_min = 3.0
		process.damping_max = 6.0
		process.gravity = Vector3(0, -2.5, 0)
		process.turbulence_enabled = true
		process.turbulence_noise_strength = 2.0
		process.turbulence_noise_scale = 3.0
		process.turbulence_influence_min = 0.05
		process.turbulence_influence_max = 0.2
		process.scale_min = 0.12
		process.scale_max = 0.35
		process.scale_curve = _grow_curve(1.0, 0.0)
		return [process, _glow_mat, [
			Color(5.0, 5.0, 5.0, 1.0),
			Color(color.r * 5.0, color.g * 5.0, color.b * 5.0, 1.0),
			Color(color.r * 3.0, color.g * 3.0, color.b * 3.0, 0.8),
			Color(color.r, color.g, color.b, 0.0),
		]])


## [process material, mesh] for the sparks.
func _make_sparks() -> Array:
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
	return [process, spark_mesh]
