extends RigidBody3D
## Player-controlled ball. Rolls relative to the camera's facing direction.

signal dashed
signal jumped
## Emitted after the ball is put back at the start (R key or falling off).
signal respawned

const DashLaser := preload("res://scripts/dash_laser.gd")
const ShieldScript := preload("res://scripts/shield.gd")
const Sfx := preload("res://scripts/sfx.gd")

@export var camera_rig: Node3D
@export var roll_torque := 12.0
@export var push_force := 16.0
@export var air_control := 0.4
@export var max_speed := 40.0
@export var jump_impulse := 8.5
@export var jump_cooldown := 1.0
@export var dash_speed := 40.0
@export var dash_lift := 1.5
@export var dash_cooldown := 1.0
@export var fall_reset_height := -20.0
## Ceiling: above this height upward speed is bled off, so launches can't go forever.
@export var max_height := 120.0
## Hard speed cap in m/s (500 on the speedometer).
@export var top_speed := 100.0

@export_group("Block")
## Q: seconds the shield is up (including folding out and back).
@export var block_time := 1.0
@export var block_cooldown := 10.0
## Launch speed when a hit lands on the shield.
@export var parry_launch := 70.0

@export_group("Skid")
## Minimum speed before turning against your motion counts as a skid.
@export var skid_min_speed := 5.0
## How opposed input must be to velocity (-1 = fully reversed, 0 = sideways).
@export var skid_threshold := -0.3
@export var skid_brake_force := 35.0
## Speed at which the sparks reach full intensity.
@export var spark_full_speed := 60.0
## How fast the ball wheel-spins toward the pressed direction while skidding,
## as a multiple of its current rolling speed.
@export var skid_spin := 1.0
## How quickly the spin snaps over to the new direction.
@export var skid_spin_rate := 12.0

@onready var _sparks: GPUParticles3D = $Sparks

var _start_position: Vector3
var _reset_requested := false
var _dash_requested := false
var _radius := 0.5
var _jump_timer := 0.0
var _dash_timer := 0.0
var _skid_dir := Vector3.ZERO
var _last_facing := 0.0
var _knockback := Vector3.ZERO
var _knockback_effects := false
## PvP state (see the PvP section below).
var dead := false
var _stagger_timer := 0.0
var _status_timer := 0.0
var _status_color := Color.WHITE
## Seconds of shield left (0 = down), and seconds until Q works again.
var _block_timer := 0.0
var _block_cd := 0.0
var _shield: MeshInstance3D


func _ready() -> void:
	_start_position = global_position
	var shape := $CollisionShape3D.shape as SphereShape3D
	if shape:
		_radius = shape.radius
	_sparks.emitting = false
	_shield = ShieldScript.new()
	_shield.set("ball", self)
	add_child(_shield)
	_shield.call("setup", $Mesh)


func _process(delta: float) -> void:
	_update_status_glow(delta)
	# Sparks are top-level so they don't spin with the ball; keep them at the
	# leading edge of the contact patch.
	var pos := get_global_transform_interpolated().origin \
		+ Vector3.DOWN * _radius * 0.9 + _skid_dir * _radius * 0.6
	# Orient the emitter so local X = travel direction, local Z = up, local Y = sideways.
	# The material's flatness squashes spread along local Y, so the stream stays
	# tight side-to-side but still fans up and down.
	var emit_basis := Basis.IDENTITY
	if _skid_dir != Vector3.ZERO:
		emit_basis = Basis(_skid_dir, Vector3.UP.cross(_skid_dir), Vector3.UP)
	_sparks.global_transform = Transform3D(emit_basis, pos)


func _physics_process(delta: float) -> void:
	# Other players' balls are driven by the network (scripts/net/player_sync.gd).
	if not is_multiplayer_authority():
		return
	_jump_timer = maxf(_jump_timer - delta, 0.0)
	_dash_timer = maxf(_dash_timer - delta, 0.0)
	_block_cd = maxf(_block_cd - delta, 0.0)
	var controls := _controls_enabled()

	if controls and _block_cd == 0.0 and Input.is_action_just_pressed("block"):
		_start_block()

	if (controls and Input.is_action_just_pressed("reset_ball")) or global_position.y < fall_reset_height:
		_reset_requested = true

	var grounded := _is_grounded()
	var dir := _get_move_direction()

	if dir != Vector3.ZERO:
		# Only push while under the speed cap in the requested direction,
		# so speed gained from a dash is kept rather than clamped.
		if linear_velocity.dot(dir) < max_speed:
			var control := 1.0 if grounded else air_control
			# Torque around the axis perpendicular to movement makes the ball roll that way.
			apply_torque(Vector3.UP.cross(dir) * roll_torque * control)
			apply_central_force(dir * push_force * control)

	_update_skid(grounded, dir, delta)

	if controls and grounded and _jump_timer == 0.0 and Input.is_action_just_pressed("jump"):
		_jump_timer = jump_cooldown
		apply_central_impulse(Vector3.UP * jump_impulse)
		jumped.emit()
		Sfx.play_flat(get_tree(), "jump", -8.0)

	if controls and _dash_timer == 0.0 and Input.is_action_just_pressed("dash"):
		_dash_timer = dash_cooldown
		_dash_requested = true


## False while a menu has taken over input (e.g. the pause menu during an online match).
func _controls_enabled() -> bool:
	if dead or _stagger_timer > 0.0:
		return false
	var net := get_tree().root.get_node_or_null("Net")
	return not (net and net.get("input_blocked"))


# --- PvP ----------------------------------------------------------------------------
# Other players' balls join the "lock_targets" group (scripts/net/player_sync.gd), so
# every weapon can lock, paint, hit, mark, stagger and push them just like practice
# targets. These calls are forwarded to the host (scripts/arena.gd), which owns health.

## Weapon damage is tuned for practice targets; this scales it for 100 HP players.
const PVP_DAMAGE_SCALE := 4.0
## Weapon impulses are tuned for light cubes; players get pushed more gently.
const PVP_PUSH_SCALE := 0.3


func is_alive() -> bool:
	return not dead


func get_aim_point() -> Vector3:
	return global_position


func take_hit(amount: float, _pos: Vector3, _dir: Vector3) -> void:
	# The host decides what a shield blocks; this is just so the shooter sees it land.
	if is_blocking():
		_shield.call("hit_flash")
	var arena := _arena()
	if arena:
		arena.call("request_hit", get_multiplayer_authority(), amount * PVP_DAMAGE_SCALE)


func receive_impulse(impulse: Vector3) -> void:
	var arena := _arena()
	if arena:
		arena.call("request_push", get_multiplayer_authority(), impulse * PVP_PUSH_SCALE)


func mark(duration: float) -> void:
	var arena := _arena()
	if arena:
		arena.call("request_mark", get_multiplayer_authority(), duration)


func stagger(duration: float) -> void:
	var arena := _arena()
	if arena:
		arena.call("request_stagger", get_multiplayer_authority(), duration)


## Hidden, untouchable and uncontrollable while dead.
func set_dead(is_dead: bool) -> void:
	dead = is_dead
	visible = not is_dead
	$CollisionShape3D.set_deferred("disabled", is_dead)
	if is_multiplayer_authority():
		freeze = is_dead
	if is_dead:
		_sparks.emitting = false


## Local player only: come back to life at `pos`.
func respawn_at(pos: Vector3) -> void:
	_start_position = pos
	_reset_requested = true


## Local player only: stunned (Nova stagger). Frozen in place in mid-air, no moving,
## dashing, blocking or shooting, like a staggered practice target.
func stagger_controls(duration: float) -> void:
	_stagger_timer = maxf(_stagger_timer, duration)


func is_staggered() -> bool:
	return _stagger_timer > 0.0


# --- Block (Q) --------------------------------------------------------------------------
# Online, the host keeps track of who's shielded (scripts/arena.gd): hits on a shield do
# no damage and trigger a parry on the blocker's computer instead.

func is_blocking() -> bool:
	return _block_timer > 0.0


## 0 right after blocking, 1 when the shield is ready again.
func get_block_ready_ratio() -> float:
	return 1.0 - _block_cd / block_cooldown


func _start_block() -> void:
	_block_timer = block_time
	_block_cd = block_cooldown
	_show_block(block_time)
	var arena := _arena()
	if arena:
		arena.call("request_block", block_time)
	if _online():
		_net_block.rpc(block_time)


@rpc("authority", "call_remote", "reliable")
func _net_block(duration: float) -> void:
	_block_timer = duration
	_show_block(duration)


func _show_block(duration: float) -> void:
	_shield.call("play", duration)
	Sfx.play_at(get_tree(), "shield", global_position)


## Local player only: a hit landed on the shield. No damage; instead the shield bursts,
## a huge explosion goes off round the ball and it's thrown high into the air.
func on_parried() -> void:
	_shield.call("hit_flash")
	_shield.call("stop")
	_block_timer = 0.0
	_knockback += Vector3.UP * parry_launch
	_knockback_effects = true
	var weapon := get_node_or_null("Weapon")
	if weapon:
		weapon.call("spawn_explosion", {
			"position": global_position,
			"color": Color(0.55, 0.4, 1.0),
			"radius": 16.0,
			"damage": 14.0,
			"force": 70.0,
			"spark_count": 500,
			"spark_speed": 40.0,
			"chunk_count": 50,
			"light_energy": 500.0,
			"warp_strength": 0.5,
			"shock_time": 0.5,
			"sound": "parry",
		})
		weapon.call("shake", 1.0)


func _online() -> bool:
	var net := get_tree().root.get_node_or_null("Net")
	return net != null and net.get("online")


## Glow the ball to show a status (every computer): "mark" violet, "stagger" gold.
func show_status(kind: String, duration: float) -> void:
	_status_color = Color(0.6, 0.35, 1.0) if kind == "mark" else Color(1.0, 0.82, 0.2)
	_status_timer = maxf(_status_timer, duration)


func _arena() -> Node:
	var scene := get_tree().current_scene
	return scene if scene and scene.has_method("request_hit") else null


func _update_status_glow(delta: float) -> void:
	_status_timer = maxf(_status_timer - delta, 0.0)
	_stagger_timer = maxf(_stagger_timer - delta, 0.0)
	_block_timer = maxf(_block_timer - delta, 0.0)
	var mesh := $Mesh as MeshInstance3D
	if not mesh.mesh:
		return
	var mat := mesh.mesh.surface_get_material(0) as StandardMaterial3D
	if not mat:
		return
	mat.emission_enabled = _status_timer > 0.0
	if _status_timer > 0.0:
		mat.emission = _status_color
		mat.emission_energy_multiplier = 1.0 + 0.8 * sin(Time.get_ticks_msec() / 90.0)


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if not is_multiplayer_authority():
		return
	if _reset_requested:
		_reset_requested = false
		_dash_requested = false
		state.transform = Transform3D(Basis.IDENTITY, _start_position)
		state.linear_velocity = Vector3.ZERO
		state.angular_velocity = Vector3.ZERO
		reset_physics_interpolation()
		respawned.emit.call_deferred()
		return

	if _stagger_timer > 0.0:
		# Frozen: hold still, cancelling this step's gravity too.
		_knockback = Vector3.ZERO
		_dash_requested = false
		state.linear_velocity = -state.total_gravity * state.step
		state.angular_velocity = Vector3.ZERO
		return

	if _knockback != Vector3.ZERO:
		# Shoves like a dash: instant velocity change, spin matched so friction
		# doesn't eat it, and (optionally) the dash camera effects.
		var kicked := state.linear_velocity + _knockback
		_knockback = Vector3.ZERO
		state.linear_velocity = kicked
		state.angular_velocity = Vector3.UP.cross(Vector3(kicked.x, 0.0, kicked.z)) / _radius
		if _knockback_effects:
			dashed.emit()
		_knockback_effects = false

	if _dash_requested:
		_dash_requested = false
		# Redirect all horizontal speed toward the pressed direction, then add the burst.
		var dir := _get_dash_direction(state.linear_velocity)
		var current := state.linear_velocity
		var flat_speed := Vector2(current.x, current.z).length()
		var velocity := dir * (flat_speed + dash_speed)
		velocity.y = maxf(current.y, 0.0) + dash_lift
		state.linear_velocity = velocity
		# Spin the ball to match its new speed so friction doesn't eat the launch.
		var flat := Vector3(velocity.x, 0.0, velocity.z)
		state.angular_velocity = Vector3.UP.cross(flat) / _radius
		# Deferred: adding nodes mid physics callback isn't safe.
		_fire_laser.call_deferred(state.transform.origin, -dir)
		dashed.emit()
		var weapon := get_node_or_null("Weapon")
		if weapon:
			weapon.call_deferred("play_sound", "dash", state.transform.origin, -2.0)

	# Speed cap and height ceiling.
	var v := state.linear_velocity
	if v.length() > top_speed:
		v = v.normalized() * top_speed
	if state.transform.origin.y > max_height and v.y > 0.0:
		v.y *= 0.8
	state.linear_velocity = v


func _fire_laser(origin: Vector3, back_dir: Vector3) -> void:
	var laser := DashLaser.new()
	get_parent().add_child(laser)
	laser.fire(origin, back_dir)


## Turning hard against your motion brakes harder and throws sparks.
func _update_skid(grounded: bool, dir: Vector3, delta: float) -> void:
	var flat := Vector3(linear_velocity.x, 0.0, linear_velocity.z)
	var speed := flat.length()
	var skidding := false
	var intensity := 0.0

	if grounded and dir != Vector3.ZERO and speed > skid_min_speed:
		var facing := dir.normalized().dot(flat / speed)
		_last_facing = facing
		if facing < skid_threshold:
			skidding = true
			# Stronger the more reversed the input and the faster you're going.
			intensity = clampf(inverse_lerp(skid_threshold, -1.0, facing), 0.3, 1.0)
			intensity *= clampf(speed / max_speed, 0.4, 1.0)
			apply_central_force(-flat / speed * skid_brake_force * intensity)
			# Wheel-spin toward the pressed direction while still sliding the old way.
			var spin_goal := Vector3.UP.cross(dir.normalized()) * speed / _radius * skid_spin
			angular_velocity = angular_velocity.lerp(spin_goal, 1.0 - exp(-skid_spin_rate * delta))

	_sparks.emitting = skidding
	if skidding:
		_skid_dir = flat / speed
		# Sparks scale hard with speed: a trickle when slow, a firehose when flying.
		var hot := clampf(speed / spark_full_speed, 0.0, 1.0)
		var turn := inverse_lerp(skid_threshold, -1.0, clampf(_last_facing, -1.0, skid_threshold))
		_sparks.amount_ratio = clampf(lerpf(0.05, 1.0, pow(hot, 0.8)) * lerpf(0.5, 1.0, turn), 0.02, 1.0)
		# Spray out ahead of the ball, low along the floor, the way it's sliding.
		# Direction is in the emitter's local space (X = forward, Z = up); see _process.
		var mat := _sparks.process_material as ParticleProcessMaterial
		mat.direction = Vector3(1.0, 0.0, lerpf(0.25, 0.4, hot)).normalized()
		mat.initial_velocity_min = lerpf(4.0, 25.0, hot)
		mat.initial_velocity_max = lerpf(10.0, 55.0, hot)
		mat.spread = lerpf(15.0, 45.0, hot)
		mat.scale_min = lerpf(0.4, 0.8, hot)
		mat.scale_max = lerpf(0.8, 1.4, hot)


## Instantly changes the ball's velocity by `velocity_change`, like a dash
## (used for the railgun's kick). Applied on the next physics step.
## `dash_effects` also fires the dash camera effects (FOV kick, warp, camera lag).
func apply_knockback(velocity_change: Vector3, dash_effects := true) -> void:
	_knockback += velocity_change
	_knockback_effects = _knockback_effects or dash_effects


## 0 right after dashing, 1 when the dash is ready again.
func get_dash_ready_ratio() -> float:
	return 1.0 - _dash_timer / dash_cooldown


func _get_dash_direction(velocity: Vector3) -> Vector3:
	var dir := _get_move_direction()
	if dir != Vector3.ZERO:
		return dir.normalized()
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	if flat.length() > 1.0:
		return flat.normalized()
	return _get_camera_forward()


func _get_move_direction() -> Vector3:
	if not _controls_enabled():
		return Vector3.ZERO
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if input == Vector2.ZERO:
		return Vector3.ZERO

	var basis := camera_rig.global_basis if camera_rig else Basis.IDENTITY
	var right := Vector3(basis.x.x, 0.0, basis.x.z).normalized()
	return (right * input.x - _get_camera_forward() * input.y).limit_length(1.0)


func _get_camera_forward() -> Vector3:
	var basis := camera_rig.global_basis if camera_rig else Basis.IDENTITY
	return Vector3(-basis.z.x, 0.0, -basis.z.z).normalized()


func _is_grounded() -> bool:
	var from := global_position
	var to := from + Vector3.DOWN * (_radius + 0.15)
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [get_rid()]
	return not get_world_3d().direct_space_state.intersect_ray(query).is_empty()
