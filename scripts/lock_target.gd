extends AnimatableBody3D
## Something the (future) lock-on can pick: every target joins the "lock_targets" group.
## Three kinds:
## - DRONE: hovers, bobs and drifts round a slow circle.
## - DUMMY: a disc on a post that stands still and can't be destroyed; it just flashes.
## - GROUND: slides back and forth between its start and path_end, spinning.
## Drones and ground targets shatter into shards after enough hits, then respawn.
## Status effects (for weapon combos):
## - Marked (Swarm missiles): takes mark_multiplier x damage from everything; pulses violet.
## - Staggered (Nova blast): frozen in place; flickers gold.

enum Kind { DRONE, DUMMY, GROUND }

const GROUP := "lock_targets"
const ShardBurst := preload("res://scripts/shard_burst.gd")

@export var kind := Kind.DRONE
@export var max_health := 12.0
@export var respawn_time := 4.0
@export var color := Color(0.9, 0.2, 0.18)

@export_group("Drone")
@export var drift_radius := 3.0
@export var drift_speed := 0.5
@export var bob_height := 0.4

@export_group("Ground")
## World position the ground target slides to (and back from).
@export var path_end := Vector3.ZERO
@export var slide_speed := 5.0

@export_group("Status")
@export var mark_multiplier := 1.5
@export var mark_color := Color(0.6, 0.35, 1.0)
@export var stagger_color := Color(1.0, 0.82, 0.2)

var _mark_timer := 0.0
var _stagger_timer := 0.0
var _home: Vector3
var _health := 0.0
var _t := 0.0
var _flash := 0.0
var _respawn_timer := 0.0
var _mat: StandardMaterial3D
var _visual: Node3D
var _shapes: Array[CollisionShape3D] = []


func _ready() -> void:
	add_to_group(GROUP)
	_home = global_position
	_health = max_health
	_build()


## For the lock-on: false while shattered and waiting to respawn.
func is_alive() -> bool:
	return _respawn_timer <= 0.0


## Where to aim: the middle of the part worth hitting (the disc, for dummies).
func get_aim_point() -> Vector3:
	if kind == Kind.DUMMY:
		return global_position + Vector3(0, 2.3, 0)
	return global_position


func take_hit(amount: float, _pos: Vector3, _dir: Vector3) -> void:
	if not is_alive():
		return
	_flash = 1.0
	if kind == Kind.DUMMY:
		return
	if is_marked():
		amount *= mark_multiplier
	_health -= amount
	if _health <= 0.0:
		_shatter()


## Marked targets take extra damage from every weapon for `duration` seconds.
func mark(duration: float) -> void:
	if is_alive():
		_mark_timer = maxf(_mark_timer, duration)


## Staggered targets stop moving for `duration` seconds.
func stagger(duration: float) -> void:
	if is_alive():
		_stagger_timer = maxf(_stagger_timer, duration)


## Weapon statuses (weapon.gd apply_status): anything that holds a player holds a target.
func take_status(kind: String, duration: float, _data := Vector3.ZERO) -> void:
	if kind in ["freeze", "cage", "pin", "dilate"]:
		stagger(duration)


func is_marked() -> bool:
	return _mark_timer > 0.0


func is_staggered() -> bool:
	return _stagger_timer > 0.0


## Puts the target back at its start, whole and at full health.
func reset() -> void:
	_health = max_health
	_respawn_timer = 0.0
	_t = 0.0
	_flash = 0.0
	_mark_timer = 0.0
	_stagger_timer = 0.0
	visible = true
	global_position = _home
	for shape in _shapes:
		shape.set_deferred("disabled", false)


func _shatter() -> void:
	# Kill feedback: impact frames + hitstop (scripts/ui/impact_frames.gd).
	get_tree().call_group("impact_frames", "trigger", get_aim_point(), color)
	var burst := ShardBurst.new()
	burst.color = color
	get_parent().add_child(burst)
	burst.global_position = global_position + _visual.position
	_respawn_timer = respawn_time
	_mark_timer = 0.0
	_stagger_timer = 0.0
	visible = false
	for shape in _shapes:
		shape.set_deferred("disabled", true)


func _physics_process(delta: float) -> void:
	if _respawn_timer > 0.0:
		_respawn_timer -= delta
		if _respawn_timer <= 0.0:
			reset()
		return

	_mark_timer = maxf(_mark_timer - delta, 0.0)
	if _stagger_timer > 0.0:
		# Frozen: skip movement. _t pauses too, so it resumes without a jump.
		_stagger_timer = maxf(_stagger_timer - delta, 0.0)
		return

	_t += delta
	match kind:
		Kind.DRONE:
			global_position = _home + Vector3(
				cos(_t * drift_speed) * drift_radius,
				sin(_t * 1.7) * bob_height,
				sin(_t * drift_speed) * drift_radius
			)
			_visual.rotate_y(delta * 0.8)
		Kind.GROUND:
			var length := maxf(_home.distance_to(path_end), 0.01)
			# Eased ping-pong between the two ends.
			var k := 0.5 - 0.5 * cos(_t * slide_speed / length * PI)
			global_position = _home.lerp(path_end, k)
			_visual.rotate_y(delta * 3.0)


func _process(delta: float) -> void:
	_flash = move_toward(_flash, 0.0, delta * 6.0)
	var glow := color
	var energy := 0.4
	var now := Time.get_ticks_msec() / 1000.0
	if is_staggered():
		glow = stagger_color
		energy = 1.5 + 1.5 * absf(sin(now * 18.0))
	elif is_marked():
		glow = mark_color
		energy = 1.2 + 1.0 * (0.5 + 0.5 * sin(now * 8.0))
	_mat.emission = glow
	_mat.emission_energy_multiplier = energy + _flash * 5.0


func _build() -> void:
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = color
	_mat.roughness = 0.5
	_mat.emission_enabled = true
	_mat.emission = color
	var grey := StandardMaterial3D.new()
	grey.albedo_color = Color(0.5, 0.5, 0.5)
	grey.roughness = 0.8

	_visual = Node3D.new()
	add_child(_visual)

	match kind:
		Kind.DRONE:
			var core := SphereMesh.new()
			core.radius = 0.6
			core.height = 1.2
			core.radial_segments = 6
			core.rings = 4
			_add_mesh(core, _mat, Transform3D.IDENTITY)
			var ring := TorusMesh.new()
			ring.inner_radius = 0.8
			ring.outer_radius = 0.95
			ring.rings = 8
			ring.ring_segments = 4
			_add_mesh(ring, _mat, Transform3D(Basis(Vector3.RIGHT, deg_to_rad(20)), Vector3.ZERO))
			_add_shape(_sphere_shape(0.75), Vector3.ZERO)
		Kind.DUMMY:
			var post := CylinderMesh.new()
			post.top_radius = 0.12
			post.bottom_radius = 0.16
			post.height = 1.6
			post.radial_segments = 6
			_add_mesh(post, grey, Transform3D(Basis.IDENTITY, Vector3(0, 0.8, 0)))
			var disc := CylinderMesh.new()
			disc.top_radius = 0.8
			disc.bottom_radius = 0.8
			disc.height = 0.15
			disc.radial_segments = 8
			# Stood on edge so the face points along Z.
			var face := Basis(Vector3.RIGHT, deg_to_rad(90))
			_add_mesh(disc, _mat, Transform3D(face, Vector3(0, 2.3, 0)))
			var post_box := BoxShape3D.new()
			post_box.size = Vector3(0.3, 1.6, 0.3)
			_add_shape(post_box, Vector3(0, 0.8, 0))
			var disc_box := BoxShape3D.new()
			disc_box.size = Vector3(1.6, 1.6, 0.2)
			_add_shape(disc_box, Vector3(0, 2.3, 0))
		Kind.GROUND:
			# Radial 4, rings 2: an octahedron.
			var body := SphereMesh.new()
			body.radius = 0.7
			body.height = 1.4
			body.radial_segments = 4
			body.rings = 2
			_add_mesh(body, _mat, Transform3D.IDENTITY)
			_add_shape(_sphere_shape(0.7), Vector3.ZERO)


func _add_mesh(source: PrimitiveMesh, mat: Material, xform: Transform3D) -> void:
	# Split every triangle apart so normals come out flat: hard-edged polygons.
	var st := SurfaceTool.new()
	st.create_from(source, 0)
	st.deindex()
	st.generate_normals()
	st.set_material(mat)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.transform = xform
	_visual.add_child(mi)


func _add_shape(shape: Shape3D, offset: Vector3) -> void:
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position = offset
	add_child(col)
	_shapes.append(col)


func _sphere_shape(radius: float) -> SphereShape3D:
	var s := SphereShape3D.new()
	s.radius = radius
	return s
