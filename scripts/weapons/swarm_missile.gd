extends Node3D
## Homing crystal missile fired by Swarm. Launches in `velocity`'s direction, then
## steers toward `target` (or `aim_point` if it has no target, or its target died),
## leaving a glowing trail. Explodes on
## contact with anything (or near its target), marking targets in the blast.
## Set position and velocity before adding it to the tree. Frees itself.

const WallRipple := preload("res://scripts/wall_ripple.gd")
const TimeField := preload("res://scripts/weapons/time_field.gd")

@export var speed := 95.0
## How fast it can turn toward its target, in radians per second (ramps up after launch).
@export var turn_rate := 18.0
## Inside this distance it stops curving and flies straight at the goal.
@export var terminal_distance := 10.0
## Detonates this close to the goal.
@export var fuse_distance := 2.0
@export var lifetime := 2.5
@export var damage := 2.5
@export var blast_radius := 2.5
@export var mark_time := 4.0
@export var color := Color(0.6, 0.35, 1.0)
## Tears of an Angel: fly straight through walls (a white ripple and warp on both faces
## of each one, wall_ripple.gd), only detonating on its target or something hittable.
@export var phase_walls := false
## Deal `damage` straight to what it hits (the blast is just for show) instead of
## splash damage.
@export var direct_hit := false
## A parried hit kills whoever fired it (ball.gd take_tears_hit).
@export var parry_kills := false

var velocity := Vector3.FORWARD
var target: Node3D = null
## Where to fly when there's no living target.
var aim_point := Vector3.ZERO
var has_aim_point := false
var manager: Node
## Another player's missile shown on this computer: flies and explodes, hurts nothing.
var visual_only := false

var _t := 0.0
var _exclude: Array[RID] = []


func _ready() -> void:
	# A small stretched octahedron that glows.
	var body := SphereMesh.new()
	body.radius = 0.16
	body.height = 0.32
	body.radial_segments = 4
	body.rings = 2
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(color.r * 3.0, color.g * 3.0, color.b * 3.0)
	body.material = mat
	var mesh := MeshInstance3D.new()
	mesh.mesh = body
	mesh.scale = Vector3(1.0, 1.0, 3.0)
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh)
	_add_trail()
	if manager:
		_exclude = [manager.ball.get_rid()]
	_face_velocity()


func _physics_process(delta: float) -> void:
	_t += delta
	if _t >= lifetime:
		_explode(global_position, null)
		return

	var goal := Vector3.ZERO
	var homing := false
	if is_instance_valid(target) and target.call("is_alive"):
		goal = target.call("get_aim_point")
		# Remember it, so the missile carries on to the spot if the target dies.
		aim_point = goal
		has_aim_point = true
		homing = true
	elif has_aim_point:
		goal = aim_point
		homing = true
	if homing:
		var want := (goal - global_position).normalized()
		var dir := velocity.normalized()
		# Loose right out of the launcher, then tighter and tighter turns.
		var rate := turn_rate * clampf(_t * 3.0, 0.2, 2.0)
		var angle := dir.angle_to(want)
		if global_position.distance_to(goal) < terminal_distance:
			dir = want
		elif angle > 0.001:
			var axis := dir.cross(want)
			if axis.length() > 0.0001:
				dir = dir.rotated(axis.normalized(), minf(angle, rate * delta))
		velocity = dir * speed
		if global_position.distance_to(goal) < fuse_distance:
			_explode(global_position, target if is_instance_valid(target) else null)
			return

	# Half speed inside someone else's Time Dilator field.
	var step := velocity * delta * TimeField.factor(get_tree(), global_position, manager.get_multiplayer_authority() if manager else 0)
	var from := global_position
	var space := get_world_3d().direct_space_state
	if phase_walls:
		# Walls don't stop it: only something hittable does. Ripples where it goes in and
		# where it comes out (every computer draws its own copy's).
		var struck := _first_hittable(space, from, from + step)
		WallRipple.pierce(get_parent(), space, from, from + step, _exclude)
		if not struck.is_empty():
			_explode(struck["position"], struck["collider"])
			return
		global_position += step
		_face_velocity()
		return
	var query := PhysicsRayQueryParameters3D.create(from, from + step)
	query.exclude = _exclude
	var hit := space.intersect_ray(query)
	if not hit.is_empty():
		var normal: Vector3 = hit["normal"]
		_explode(hit["position"] + normal * 0.2, hit["collider"])
		return
	global_position += step
	_face_velocity()


## The first thing along the segment that can take a hit (players, targets), looking
## past any walls in the way; {} if none.
func _first_hittable(space: PhysicsDirectSpaceState3D, a: Vector3, b: Vector3) -> Dictionary:
	var skip: Array[RID] = _exclude.duplicate()
	for i in 6:
		var query := PhysicsRayQueryParameters3D.create(a, b)
		query.exclude = skip
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			return {}
		if (hit["collider"] as Object).has_method("take_hit"):
			return hit
		skip.append(hit["rid"])
	return {}


func _face_velocity() -> void:
	if velocity.length() > 0.01:
		var up := Vector3.UP if absf(velocity.normalized().y) < 0.98 else Vector3.RIGHT
		global_basis = Basis.looking_at(velocity.normalized(), up)


func _explode(pos: Vector3, struck: Object = null) -> void:
	# Direct hits land on what they struck; the blast after is only for show.
	if direct_hit and struck and not visual_only and manager:
		var dir := velocity.normalized()
		if parry_kills and struck.has_method("take_tears_hit"):
			struck.call("take_tears_hit", damage, pos, dir)
			manager.call("report_damage", struck, damage, pos)
		elif struck.has_method("take_hit"):
			struck.call("take_hit", damage, pos, dir)
			manager.call("report_damage", struck, damage, pos)
	var props := {
		"position": pos,
		"color": color,
		"radius": blast_radius,
		"damage": 0.0 if direct_hit else damage,
		"force": 8.0,
		"mark_time": mark_time,
		"spark_count": 50,
		"spark_speed": 14.0,
		"chunk_count": 6,
		"light_energy": 40.0,
		"warp_strength": 0.08,
		"shock_time": 0.2,
	}
	if manager:
		# Not re-sent over the network: other players' copies of this missile explode
		# on their own screens.
		manager.call("spawn_explosion", props, false, visual_only)
	queue_free()


func _add_trail() -> void:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 1.0])
	gradient.colors = PackedColorArray([
		Color(color.r * 3.0, color.g * 3.0, color.b * 3.0, 1.0),
		Color(color.r, color.g, color.b, 0.0),
	])
	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient
	ramp.use_hdr = true
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1))
	curve.add_point(Vector2(1, 0))
	var scale_tex := CurveTexture.new()
	scale_tex.curve = curve

	var process := ParticleProcessMaterial.new()
	process.gravity = Vector3.ZERO
	process.spread = 180.0
	process.initial_velocity_min = 0.0
	process.initial_velocity_max = 0.6
	process.scale_curve = scale_tex
	process.color_ramp = ramp

	var dot_mat := StandardMaterial3D.new()
	dot_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dot_mat.vertex_color_use_as_albedo = true
	dot_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dot_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	var dot := QuadMesh.new()
	dot.size = Vector2(0.18, 0.18)
	dot.material = dot_mat

	var trail := GPUParticles3D.new()
	trail.amount = 60
	trail.lifetime = 0.4
	trail.local_coords = false
	trail.process_material = process
	trail.draw_pass_1 = dot
	trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	trail.visibility_aabb = AABB(Vector3(-50, -50, -50), Vector3(100, 100, 100))
	add_child(trail)
