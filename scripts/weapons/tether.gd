extends "res://scripts/weapons/blade_weapon.gd"
## Slot 4: Tether, a grapple. One long thin blade over the top of the ball.
## Press fire on something in range to hook it with a beam; hold to reel in; release
## to let go and keep the momentum, for flinging. The hook sticks to moving targets and
## cubes, and hooked cubes get yanked toward you.
## The beam behaves like a taut elastic rope: its length winds in at reel_speed, and
## the further you're stretched past that length the harder it pulls, while moving
## away from the hook is resisted, so you swing round it instead of drifting off.
## The beam thins, brightens and thrums as tension builds.
## Holding fire while nothing's in range keeps trying: the moment something under the
## crosshair comes into range, it hooks.
## Slam: while hooked (or just after letting go), hit the ground coming down fast enough
## and it detonates round you, bigger the faster you land. Anyone caught in it dies.
## Combos: reel into a target and finish with Scatter; fling off a wall into a dash.

const LaserShader := preload("res://shaders/dash_laser.gdshader")

@export var max_range := 120.0
## How fast the rope winds in, in m/s.
@export var reel_speed := 28.0
## Constant pull toward the hook while reeling.
@export var pull_accel := 30.0
## Extra pull per metre the rope is stretched past its current length.
@export var stiffness := 80.0
## Extra pull per m/s you're moving away from the hook while stretched.
@export var damping := 16.0
## Cap on the rope's pull, in m/s^2.
@export var max_accel := 200.0
## Most the rope can pull you upward, in m/s^2 on top of cancelling gravity. Kept low so
## the tether swings and hauls you, but can't be used to fly.
@export var max_lift := 6.0
## The rope snaps after this many seconds hooked.
@export var max_hook_time := 3.0
## Seconds after letting go (or the rope snapping) before it can hook again.
@export var rehook_delay := 0.6
## Lets go automatically this close to the anchor.
@export var release_distance := 2.0
## Impulse per second pulling a hooked rigid body toward the ball (scaled by tension).
@export var yank_force := 35.0
@export var beam_width := 0.13

@export_group("Slam")
## Downward speed (m/s) needed to slam, and the speed where the slam is at full size.
@export var slam_speed := 20.0
@export var slam_full_speed := 60.0
## Seconds after letting go that a landing still counts as a slam.
@export var slam_grace := 1.0
## Slam damage anywhere in the blast. x4 online (ball.gd PVP_DAMAGE_SCALE) is 100, a full
## health bar: one shot. Shields and spawn protection still stop it.
@export var slam_damage := 25.0

## 0 slack .. 1 at max pull.
var tension := 0.0
var _rope_length := 0.0
var _thrum := 0.0

var _anchor_body: Node3D = null
## True when hooked to a moving body (vs. a fixed point on the static map).
var _on_body := false
## Anchor in the body's local space (or world space if it's the static map).
var _anchor_local := Vector3.ZERO
var _attached := false
var _was_pressed := false
## While held without a hook, keep trying to hook. Off after reeling all the way in,
## so it doesn't instantly re-hook the same spot; a fresh press turns it back on.
var _auto_hook := false
## Seconds left in which a hard landing slams.
var _slam_window := 0.0
var _fall_speed := 0.0
var _hook_time := 0.0
var _rehook := 0.0
var _line: MeshInstance3D
var _line_mat: ShaderMaterial


func _build() -> void:
	# Rolled 90 degrees: the crescent arches over the top of the ball.
	add_blade(1.0, 90.0, {
		"arc_radius": 0.75,
		"tip": Vector3(0.1, 0.0, -3.6),
		"max_width": 0.18,
		"max_thickness": 0.14,
		"segments": 10,
	})
	# The tether beam: a thin glowing cylinder stretched from the tip to the anchor.
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.5
	cyl.bottom_radius = 0.5
	cyl.height = 1.0
	cyl.radial_segments = 6
	cyl.rings = 1
	_line_mat = ShaderMaterial.new()
	_line_mat.shader = LaserShader
	_line = MeshInstance3D.new()
	_line.set_instance_shader_parameter("color", color)
	_line.set_instance_shader_parameter("intensity", 5.0)
	_line.set_instance_shader_parameter("fade", 1.0)
	_line.mesh = cyl
	_line.material_override = _line_mat
	_line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_line.top_level = true
	_line.visible = false
	add_child(_line)


func handle_fire(pressed: bool, hit: Dictionary, delta: float) -> void:
	var just_pressed := pressed and not _was_pressed
	_was_pressed = pressed
	if just_pressed:
		_auto_hook = true
	if not is_ready():
		_detach()
		return
	_rehook = maxf(_rehook - delta, 0.0)
	if pressed and not _attached and _auto_hook and _rehook == 0.0:
		_try_attach(hit)
	elif not pressed and _attached:
		_detach()
	if _attached:
		_hook_time += delta
		if _hook_time >= max_hook_time:
			# Snaps: a fresh press is needed to hook again.
			_detach()
			_auto_hook = false
		else:
			_reel(delta)


func _physics_process(delta: float) -> void:
	if not manager or not manager.is_multiplayer_authority():
		return
	_slam_window = maxf(_slam_window - delta, 0.0)
	if _attached:
		_slam_window = slam_grace
	var ball: RigidBody3D = manager.ball
	if _slam_window <= 0.0 or ball.get("dead"):
		_fall_speed = 0.0
		return
	# Landing: fast downward last step, and now there's ground right under the ball.
	var falling := -ball.linear_velocity.y
	var ground: Dictionary = manager.raycast(ball.global_position, ball.global_position + Vector3.DOWN * 0.9)
	if not ground.is_empty() and _fall_speed >= slam_speed:
		_slam(ground["position"], _fall_speed)
		_fall_speed = 0.0
		return
	_fall_speed = falling


func _slam(pos: Vector3, speed: float) -> void:
	var k := clampf(inverse_lerp(slam_speed, slam_full_speed, speed), 0.0, 1.0)
	_detach()
	_auto_hook = false
	_slam_window = 0.0
	manager.spawn_explosion({
		"position": pos + Vector3.UP * 0.3,
		"color": color,
		"radius": lerpf(6.0, 14.0, k),
		"damage": slam_damage,
		"full_damage": true,
		"force": lerpf(25.0, 60.0, k),
		"spark_count": int(lerpf(150.0, 400.0, k)),
		"spark_speed": lerpf(20.0, 38.0, k),
		"chunk_count": int(lerpf(15.0, 40.0, k)),
		"light_energy": lerpf(150.0, 400.0, k),
		"warp_strength": lerpf(0.2, 0.45, k),
		"flat_sparks": true,
		"sound": "land_slam",
	})
	# Stop dead on impact (no rubber-ball rebound), then a hop off the crater.
	var ball: RigidBody3D = manager.ball
	var v := ball.linear_velocity
	ball.linear_velocity = Vector3(v.x, 0.0, v.z)
	manager.push_ball(Vector3.UP * lerpf(5.0, 10.0, k))
	manager.shake(lerpf(0.6, 1.0, k))


func _on_exit() -> void:
	_detach()


func get_crosshair() -> Dictionary:
	var aim: Vector3 = manager.aim_point
	var in_range: bool = aim.distance_to(manager.ball.global_position) <= max_range
	var info := {"kind": "tether", "in_range": in_range, "attached": _attached, "tension": tension}
	if _attached:
		info["anchor_screen"] = manager.screen_pos(_anchor_world())
	return info


func _update(delta: float) -> void:
	# The tip opens up like jaws while hooked, wider under tension.
	var goal_open := (0.35 + tension * 0.15) if _attached else 0.0
	tip_open = move_toward(tip_open, goal_open, delta * 2.5)
	if not _attached or (_on_body and not is_instance_valid(_anchor_body)):
		_line.visible = false
		tension = 0.0
		return
	var tip: Vector3 = _blades[0].to_global(_blades[0].call("get_tip"))
	var anchor := _anchor_world()
	var span := anchor - tip
	var length := span.length()
	if length < 0.01:
		_line.visible = false
		return
	_line.visible = visible
	var y := span / length
	var x := y.cross(Vector3.UP if absf(y.y) < 0.99 else Vector3.RIGHT).normalized()
	var z := x.cross(y)
	# Taut rope: thinner and brighter under tension, and it thrums sideways.
	_thrum += delta * 55.0
	var w := beam_width * lerpf(1.3, 0.7, tension)
	var wobble := x * sin(_thrum) * 0.04 * tension
	_line.global_transform = Transform3D(Basis(x * w, y * length, z * w), tip + span * 0.5 + wobble)
	_line.set_instance_shader_parameter("intensity", 4.0 + tension * 10.0)


func _try_attach(hit: Dictionary) -> void:
	if hit.is_empty():
		return
	var pos: Vector3 = hit["position"]
	if pos.distance_to(manager.ball.global_position) > max_range:
		return
	var body := hit["collider"] as Node3D
	# Stick to anything that moves (targets, cubes); the static map is a fixed point.
	_on_body = body is RigidBody3D or body is AnimatableBody3D
	if _on_body:
		_anchor_body = body
		_anchor_local = body.to_local(pos)
	else:
		_anchor_body = null
		_anchor_local = pos
	_attached = true
	# The rope starts exactly as long as the gap, then winds in from there.
	_rope_length = pos.distance_to(manager.ball.global_position)
	kick(0)
	var normal: Vector3 = hit["normal"]
	manager.spawn_beam(pos, normal, 0.8, 0.5, 0.1, 16.0, color)
	manager.spawn_light(pos + normal * 0.2, 30.0, 6.0, 0.1, color)
	manager.shake(0.4)
	manager.play_sound("tether", global_position, -4.0)


func _detach() -> void:
	if _attached:
		_rehook = rehook_delay
	_attached = false
	_hook_time = 0.0
	_on_body = false
	_anchor_body = null
	tension = 0.0
	if _line:
		_line.visible = false


func _anchor_world() -> Vector3:
	if _on_body and is_instance_valid(_anchor_body):
		return _anchor_body.to_global(_anchor_local)
	return _anchor_local


func _reel(delta: float) -> void:
	# Let go if the hooked body was removed or the hooked target shattered.
	if _on_body and not is_instance_valid(_anchor_body):
		_detach()
		return
	if _on_body and _anchor_body.has_method("is_alive") and not _anchor_body.call("is_alive"):
		_detach()
		return
	var ball: RigidBody3D = manager.ball
	var anchor := _anchor_world()
	var to_anchor := anchor - ball.global_position
	var dist := to_anchor.length()
	if dist < release_distance:
		_detach()
		_auto_hook = false
		return
	var dir := to_anchor / dist

	# Elastic rope: wind the length in, then pull by how far past it we're stretched.
	_rope_length = maxf(release_distance, _rope_length - reel_speed * delta)
	var stretch := dist - _rope_length
	var accel := pull_accel
	if stretch > 0.0:
		accel += stretch * stiffness
		var closing := ball.linear_velocity.dot(dir)  # Negative = moving away.
		if closing < 0.0:
			accel += -closing * damping
	accel = minf(accel, max_accel)
	tension = clampf(accel / max_accel, 0.0, 1.0)
	var pull := dir * accel
	# Cap the upward part: enough to swing and climb a little, never enough to fly.
	var gravity := float(ProjectSettings.get_setting("physics/3d/default_gravity"))
	pull.y = minf(pull.y, gravity + max_lift)
	ball.apply_central_force(pull * ball.mass)
	# A faint rumble while it's really hauling.
	if tension > 0.5:
		manager.shake((tension - 0.5) * 0.04)

	# Hooked cubes get dragged toward the ball too, harder under tension.
	var rigid: RigidBody3D = _anchor_body as RigidBody3D if _on_body else null
	if rigid:
		rigid.sleeping = false
		rigid.apply_impulse(-dir * yank_force * (0.3 + tension) * delta, anchor - rigid.global_position)
