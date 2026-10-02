extends Node3D
## Orbit camera that follows a target.
## Click to capture the mouse, move the mouse to orbit, I / O (or Ctrl + wheel) to zoom.
## Q / E also orbit with the keyboard.
## Also drives the speed warp effect (FOV kick + screen shader) and lags vertically on jumps.
## Sensitivity, FOV, shake and effect strength come from the player's Settings.

const SettingsScript := preload("res://scripts/settings.gd")
const InputSetup := preload("res://scripts/input_setup.gd")
## Right stick: full tilt turns this many radians a second (times the controller yaw /
## pitch sensitivity settings).
const PAD_YAW_SPEED := 3.2
const PAD_PITCH_SPEED := 2.2
const PAD_DEADZONE := 0.18
## Motion controls: gyro turn rate (radians a second) below this is treated as noise.
const GYRO_DEADZONE := 0.02
## Pitch the camera returns to when recentred (R3).
const RECENTER_PITCH := -0.25
## NAME CREATOR's freecam (moderation.gd), metres a second.
const FREECAM_SPEED := 40.0
## Killcam: after we're killed online, the camera holds where we died for this long, then
## follows whoever killed us until we respawn (arena.gd RESPAWN_TIME is 3s).
const KILLCAM_DELAY := 1.0

@export var target: Node3D
@export var warp_rect: CanvasItem
@export var follow_speed := 12.0
@export var mouse_sensitivity := 0.0035
@export var key_turn_speed := 2.5
@export var min_pitch_deg := -80.0
@export var max_pitch_deg := 45.0
## How much the camera pivot rises when looking up (1 = camera height stays level).
@export var look_up_lift := 0.65
@export var min_distance := 3.0
@export var max_distance := 30.0
@export var zoom_step := 1.0
## Zoom speed with the I / O keys, in metres per second.
@export var key_zoom_speed := 12.0

@export_group("Jump Lag")
## Vertical follow speed right after a jump (lower = more lag).
@export var jump_follow_speed := 2.5
## Seconds for the vertical follow to recover to normal.
@export var jump_lag_time := 0.8

@export_group("Dash Lag")
## Horizontal follow speed right after a dash (lower = ball pulls further ahead).
@export var dash_follow_speed := 2.5
## Seconds for the horizontal follow to recover to normal.
@export var dash_lag_time := 0.7
## Furthest the camera may trail the ball horizontally, so high speeds don't lose it.
@export var max_follow_gap := 6.0

@export_group("Warp")
@export var base_fov := 70.0
@export var max_speed_fov := 40.0
@export var dash_fov_kick := 48.0
@export var max_fov := 132.0
@export var warp_start_speed := 18.0
@export var warp_full_speed := 55.0
## Warp shader strength at top speed.
@export var speed_warp_strength := 2.8
## Warp shader strength at the peak of a dash.
@export var dash_warp_strength := 5.5
@export var dash_kick_decay := 2.2
@export var shockwave_time := 0.42

@export_group("Shake")
## Max lens offset from shot shake (at full trauma).
@export var shot_shake_offset := 0.14
## How fast shot shake dies away (trauma per second).
@export var shake_decay := 4.0
## Speed where the speed rumble starts, and where it's at full strength.
@export var speed_shake_start := 25.0
@export var speed_shake_full := 75.0
@export var speed_shake_offset := 0.16
@export var shake_frequency := 30.0

@onready var _pitch: Node3D = $Pitch
@onready var _spring_arm: SpringArm3D = $Pitch/SpringArm3D
@onready var _camera: Camera3D = $Pitch/SpringArm3D/Camera3D

var _dash_kick := 0.0
## Extra warp from explosions going off near the camera, fades away.
var _blast_warp := 0.0
var _warp := 0.0
var _shock := 1.0  # Shockwave progress, 0 -> 1. 1 means inactive.
var _jump_lag := 0.0
var _dash_lag := 0.0
var _pivot_height := 0.0
var _sensitivity_scale := 1.0
var _pad_yaw_scale := 1.0
var _pad_pitch_scale := 1.0
var _shake_scale := 1.0
var _effects_scale := 1.0
var _motion := false
var _motion_scale := 1.0
var _motion_invert := false
var _invert_y := false
## NAME CREATOR's freecam: on while true, _process() flies the rig itself instead of
## following target. min/max pitch and the zoom distance are relaxed while it's on, and
## restored when it turns off.
var freecam := false
var _freecam_min_pitch := 0.0
var _freecam_max_pitch := 0.0
var _freecam_spring := 0.0
## Killcam: the killer's ball we're following instead of target (null = our own ball), and
## the killer we'll switch to once _killcam_wait runs out.
var _spectating: Node3D = null
var _pending_killer: Node3D = null
var _killcam_wait := 0.0
var _arena: Node = null
## Which controller's motion sensors we've switched on (-1 = none).
var _gyro_device := -1
var _trauma := 0.0
var _shake_time := 0.0
var _noise := FastNoiseLite.new()
## Rushing-air loop, louder and higher the faster the ball goes.
var _wind: AudioStreamPlayer


## An explosion went off at pos: the closer (in blast radii), the harder the screen
## warps, rings with a shockwave and shakes.
func blast_nearby(pos: Vector3, radius: float) -> void:
	if not _camera:
		return
	var reach := radius * 5.0 + 10.0
	var k := clampf(1.0 - _camera.global_position.distance_to(pos) / reach, 0.0, 1.0)
	if k <= 0.0:
		return
	var size := clampf(radius / 8.0, 0.35, 1.6)
	_blast_warp = maxf(_blast_warp, k * k * 3.2 * size)
	add_shake(k * 0.9 * size)
	if k > 0.25:
		_shock = 0.0


## Adds a jolt of shake (0..1). Squared when applied, so small hits stay subtle.
func add_shake(amount: float) -> void:
	_trauma = minf(_trauma + amount, 1.0)


func _update_shake(delta: float, speed: float) -> void:
	_trauma = move_toward(_trauma, 0.0, shake_decay * delta)
	var speed_amount := clampf(inverse_lerp(speed_shake_start, speed_shake_full, speed), 0.0, 1.0)
	var magnitude := _trauma * _trauma * shot_shake_offset + speed_amount * speed_amount * speed_shake_offset
	_shake_time += delta * shake_frequency
	# Smooth noise on two separate tracks so horizontal and vertical wobble independently.
	magnitude *= _shake_scale
	_camera.h_offset = _noise.get_noise_1d(_shake_time) * magnitude
	_camera.v_offset = _noise.get_noise_1d(_shake_time + 1000.0) * magnitude


## Pulls in the player's settings (sensitivity, FOV, shake, effects strength).
func _apply_settings() -> void:
	var tree := get_tree()
	_sensitivity_scale = SettingsScript.read(tree, "mouse_sensitivity")
	_pad_yaw_scale = SettingsScript.read(tree, "pad_yaw_sensitivity")
	_pad_pitch_scale = SettingsScript.read(tree, "pad_pitch_sensitivity")
	base_fov = SettingsScript.read(tree, "fov")
	_shake_scale = SettingsScript.read(tree, "camera_shake")
	_effects_scale = SettingsScript.read(tree, "screen_effects")
	_motion = SettingsScript.read(tree, "motion_controls")
	_motion_scale = SettingsScript.read(tree, "motion_sensitivity")
	_motion_invert = SettingsScript.read(tree, "motion_invert_y")
	_invert_y = SettingsScript.read(tree, "invert_mouse_y")


func _ready() -> void:
	# Moved in _process, so it must not be physics-interpolated.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_to_group("camera_rig")
	# A small ball instead of a thin ray: the camera stays a little off walls and ceilings,
	# so it can't end up in them and show what's behind (the Backrooms' low ceiling).
	if _spring_arm.shape == null:
		var probe := SphereShape3D.new()
		probe.radius = 0.35
		_spring_arm.shape = probe
	_apply_settings()
	var settings := get_tree().root.get_node_or_null("Settings")
	if settings:
		settings.connect("changed", _apply_settings)
	# Noise sampled at shake_frequency steps per second; frequency 1 keeps it jittery.
	_noise.frequency = 1.0
	_pivot_height = _pitch.position.y
	if target:
		global_position = target.global_position
		if target is CollisionObject3D:
			_spring_arm.add_excluded_object(target.get_rid())
		if target.has_signal("dashed"):
			target.connect("dashed", _on_dashed)
		if target.has_signal("jumped"):
			target.connect("jumped", func() -> void: _jump_lag = 1.0)
		if target.has_signal("rifted"):
			# Through a rift: jump to the far side and turn the view with the ball.
			target.connect("rifted", func(turn: Basis, to: Vector3) -> void:
				var fwd := turn * (-global_basis.z)
				var flat := Vector2(fwd.x, fwd.z)
				if flat.length() > 0.2:
					rotation.y = atan2(-flat.x, -flat.y)
				global_position = to
				reset_physics_interpolation())
		if target.has_signal("wrapped"):
			# A looping map moved the ball to the far side: jump with it, no sweep across.
			target.connect("wrapped", func(offset: Vector3) -> void:
				global_position += offset
				reset_physics_interpolation())
	_connect_arena.call_deferred()


## Killcam: listen for kills and respawns on the arena we're part of (an ancestor: the
## arena spawns our local view).
func _connect_arena() -> void:
	var node := get_parent()
	while node and not node.has_signal("player_killed"):
		node = node.get_parent()
	_arena = node
	if _arena:
		_arena.connect("player_killed", _on_player_killed)
		_arena.connect("player_respawned", _on_player_respawned)


func _on_player_killed(victim: int, attacker: int) -> void:
	if victim != multiplayer.get_unique_id() or attacker == victim or freecam:
		return
	if not _arena.call("is_online"):
		return  # Practice: nobody to watch.
	var killer: Node3D = _arena.call("player_ball", attacker)
	if killer and killer != target:
		_pending_killer = killer
		_killcam_wait = KILLCAM_DELAY


func _on_player_respawned(id: int) -> void:
	if id != multiplayer.get_unique_id():
		return
	_pending_killer = null
	if _spectating:
		_stop_spectating()
		if target:
			global_position = target.global_position
			reset_physics_interpolation()


## Switches the camera to the killer's ball, turned to look at them from the side we
## died on.
func _start_spectating(killer: Node3D) -> void:
	_spectating = killer
	if killer is CollisionObject3D:
		_spring_arm.add_excluded_object(killer.get_rid())
	if target:
		var d := killer.global_position - target.global_position
		if Vector2(d.x, d.z).length() > 1.0:
			rotation.y = atan2(-d.x, -d.z)
	global_position = killer.get_global_transform_interpolated().origin
	reset_physics_interpolation()


func _stop_spectating() -> void:
	if is_instance_valid(_spectating) and _spectating is CollisionObject3D:
		_spring_arm.remove_excluded_object(_spectating.get_rid())
	_spectating = null


## What the camera follows: the killer while the killcam is on (unless they've died too),
## otherwise our own ball.
func _followed() -> Node3D:
	if _spectating and is_instance_valid(_spectating) and not _spectating.get("dead"):
		return _spectating
	return target


func _on_dashed() -> void:
	_dash_kick = 1.0
	_shock = 0.0
	_dash_lag = 1.0


## moderation.gd's practice_toggle_freecam() calls this (scripts.camera_rig is in the
## "camera_rig" group). First-person while it's on: zoomed all the way in, full pitch
## range, and target is left untouched so following resumes right where it left off.
func set_freecam(on: bool) -> void:
	if freecam == on:
		return
	freecam = on
	if on:
		_freecam_min_pitch = min_pitch_deg
		_freecam_max_pitch = max_pitch_deg
		_freecam_spring = _spring_arm.spring_length
		min_pitch_deg = -89.0
		max_pitch_deg = 89.0
		_spring_arm.spring_length = 0.0
	else:
		min_pitch_deg = _freecam_min_pitch
		max_pitch_deg = _freecam_max_pitch
		_spring_arm.spring_length = _freecam_spring


## Moves the rig itself in the direction it's looking (full pitch, not just yaw), WASD /
## left stick to move, jump / dash for up and down. No collision: flies straight through
## walls, for lining up shots the ball couldn't reach.
func _freecam_move(delta: float) -> void:
	var basis := _pitch.global_transform.basis
	var move := -basis.z * Input.get_axis("move_back", "move_forward") + basis.x * Input.get_axis("move_left", "move_right")
	if Input.is_action_pressed("jump"):
		move += Vector3.UP
	if Input.is_action_pressed("dash"):
		move += Vector3.DOWN
	if move.length() > 0.0:
		global_position += move.normalized() * FREECAM_SPEED * delta


func _process(delta: float) -> void:
	if _pending_killer:
		_killcam_wait -= delta
		if _killcam_wait <= 0.0:
			var killer := _pending_killer
			_pending_killer = null
			if is_instance_valid(killer) and not killer.get("dead"):
				_start_spectating(killer)
	var follow := _followed()
	if freecam:
		_freecam_move(delta)
	elif follow:
		var goal := follow.get_global_transform_interpolated().origin
		# Horizontal follow slows right after a dash so the ball pulls away, then catches up.
		_dash_lag = move_toward(_dash_lag, 0.0, delta / dash_lag_time)
		var h_speed := lerpf(follow_speed, dash_follow_speed, _dash_lag)
		var flat_t := 1.0 - exp(-h_speed * delta)
		# Vertical follow slows right after a jump, then eases back.
		_jump_lag = move_toward(_jump_lag, 0.0, delta / jump_lag_time)
		var v_speed := lerpf(follow_speed, jump_follow_speed, _jump_lag)
		var v_t := 1.0 - exp(-v_speed * delta)
		global_position = Vector3(
			lerpf(global_position.x, goal.x, flat_t),
			lerpf(global_position.y, goal.y, v_t),
			lerpf(global_position.z, goal.z, flat_t)
		)
		var gap := Vector2(goal.x - global_position.x, goal.z - global_position.z)
		if gap.length() > max_follow_gap:
			var pull := gap - gap.limit_length(max_follow_gap)
			global_position.x += pull.x
			global_position.z += pull.y

	# Camera keys are ignored while typing in chat (or in the pause menu).
	var net := get_tree().root.get_node_or_null("Net")
	if not (net and net.get("input_blocked")):
		var turn := Input.get_axis("camera_left", "camera_right")
		rotation.y -= turn * key_turn_speed * delta
		_pad_look(delta)
		_gyro_look(delta)
		if Input.is_action_just_pressed("recenter_camera"):
			_recenter()
		# Hold I / O to zoom in / out.
		var zoom := Input.get_axis("zoom_in", "zoom_out")
		if zoom != 0.0:
			_zoom(zoom * key_zoom_speed * delta)

	# Looking up would swing the camera under the floor (and the spring arm would
	# then crush it against the ball). Raise the pivot instead, so the camera stays
	# behind the ball at about the same height and just tilts up.
	var look_up := maxf(_pitch.rotation.x, 0.0)
	_pitch.position.y = _pivot_height + _spring_arm.spring_length * sin(look_up) * look_up_lift

	_update_warp(delta)


func _update_warp(delta: float) -> void:
	var speed := 0.0
	# Watching the killer: no speed warp or wind from our own (dead) ball.
	if target is RigidBody3D and not _spectating:
		speed = (target as RigidBody3D).linear_velocity.length()
	_update_shake(delta, speed)

	var speed_amount := clampf(inverse_lerp(warp_start_speed, warp_full_speed, speed), 0.0, 1.0)
	_update_wind(speed)
	_dash_kick = move_toward(_dash_kick, 0.0, dash_kick_decay * delta)
	_shock = minf(_shock + delta / shockwave_time, 1.0)

	var goal := maxf(speed_amount * speed_warp_strength, ease(_dash_kick, 0.5) * dash_warp_strength) * _effects_scale
	_blast_warp = move_toward(_blast_warp, 0.0, delta * 7.0)
	goal += _blast_warp * _effects_scale
	# Hit instantly on the way up, ease down.
	if goal > _warp:
		_warp = goal
	else:
		_warp = lerpf(_warp, goal, 1.0 - exp(-7.0 * delta))

	var fov_kick := speed_amount * max_speed_fov + ease(_dash_kick, 0.5) * dash_fov_kick + _blast_warp * 2.5
	var fov_goal := base_fov + fov_kick * minf(_effects_scale, 1.0)
	var fov_rate := 60.0 if fov_goal > _camera.fov else 7.0
	_camera.fov = minf(lerpf(_camera.fov, fov_goal, 1.0 - exp(-fov_rate * delta)), max_fov)

	if warp_rect:
		var mat := warp_rect.material as ShaderMaterial
		if mat:
			mat.set_shader_parameter("strength", _warp)
			mat.set_shader_parameter("shock_progress", _shock if _effects_scale > 0.0 else 1.0)
		warp_rect.visible = _effects_scale > 0.0 and (_warp > 0.01 or _shock < 1.0)


func _update_wind(speed: float) -> void:
	if _wind == null:
		var sfx := get_tree().root.get_node_or_null("Sfx")
		if sfx:
			_wind = sfx.call("make_flat_loop", "wind", self)
		if _wind == null:
			return
	var k := clampf(inverse_lerp(8.0, 100.0, speed), 0.0, 1.0)
	if k > 0.0 and not _wind.playing:
		_wind.play()
	elif k == 0.0 and _wind.playing:
		_wind.stop()
	_wind.volume_db = linear_to_db(k * 0.7 + 0.0001) + _dash_kick * 4.0
	_wind.pitch_scale = lerpf(0.7, 1.8, k) + _dash_kick * 0.3


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			# Plain wheel browses weapons (scripts/ui/weapon_selector.gd); Ctrl+wheel zooms.
			MOUSE_BUTTON_WHEEL_UP:
				if event.ctrl_pressed:
					_zoom(-zoom_step)
			MOUSE_BUTTON_WHEEL_DOWN:
				if event.ctrl_pressed:
					_zoom(zoom_step)
	elif event.is_action_pressed("ui_cancel") and not event is InputEventJoypadButton:
		# (Not the controller's B: that's the shield.)
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sens := mouse_sensitivity * _sensitivity_scale
		rotation.y -= event.relative.x * sens
		_pitch.rotation.x = clampf(
			_pitch.rotation.x - event.relative.y * sens * (-1.0 if _invert_y else 1.0),
			deg_to_rad(min_pitch_deg),
			deg_to_rad(max_pitch_deg)
		)


## Right stick orbits the camera (any connected controller), with a curve so small tilts
## aim finely.
func _pad_look(delta: float) -> void:
	# The controller weapon wheel has the right stick (ui/weapon_selector.gd).
	if InputSetup.wheel_open:
		return
	var stick := Vector2(Input.get_joy_axis(0, JOY_AXIS_RIGHT_X), Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y))
	if stick.length() < PAD_DEADZONE:
		return
	stick = stick.normalized() * inverse_lerp(PAD_DEADZONE, 1.0, minf(stick.length(), 1.0))
	stick *= stick.length()
	rotation.y -= stick.x * PAD_YAW_SPEED * _pad_yaw_scale * delta
	_pitch.rotation.x = clampf(
		_pitch.rotation.x - stick.y * PAD_PITCH_SPEED * _pad_pitch_scale * delta * (-1.0 if _invert_y else 1.0),
		deg_to_rad(min_pitch_deg),
		deg_to_rad(max_pitch_deg)
	)


## Motion controls: the controller's gyro turns the camera like a mouse would, 1:1 with how
## far you turn it (times the sensitivity). Tilt left/right to turn, up/down to look.
func _gyro_look(delta: float) -> void:
	var pads := Input.get_connected_joypads()
	if not _motion or pads.is_empty():
		if _gyro_device >= 0:
			Input.set_joy_motion_sensors_enabled(_gyro_device, false)
			_gyro_device = -1
		return
	var device: int = pads[0]
	if not Input.has_joy_motion_sensors(device):
		return
	if _gyro_device != device:
		Input.set_joy_motion_sensors_enabled(device, true)
		_gyro_device = device
	var gyro := Input.get_joy_gyroscope(device)
	# Yaw: turning the controller flat (y), plus rolling it (z), so it works however it's held.
	var yaw := gyro.y + gyro.z
	var pitch := gyro.x * (-1.0 if _motion_invert else 1.0)
	if absf(yaw) > GYRO_DEADZONE:
		rotation.y += yaw * _motion_scale * delta
	if absf(pitch) > GYRO_DEADZONE:
		_pitch.rotation.x = clampf(_pitch.rotation.x + pitch * _motion_scale * delta,
			deg_to_rad(min_pitch_deg), deg_to_rad(max_pitch_deg))


## R3: point the camera the way the ball is rolling (or keep facing if it's still) and
## level it out, for when motion aiming has drifted.
func _recenter() -> void:
	var body := target as RigidBody3D
	if body:
		var v := body.linear_velocity
		if Vector2(v.x, v.z).length() > 2.0:
			rotation.y = atan2(-v.x, -v.z)
	_pitch.rotation.x = RECENTER_PITCH


## Remembers whether the player is on a controller or mouse and keyboard.
func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf(event.axis_value) > 0.3):
		InputSetup.using_pad = true
	elif event is InputEventKey or event is InputEventMouseButton:
		InputSetup.using_pad = false


func _zoom(amount: float) -> void:
	_spring_arm.spring_length = clampf(_spring_arm.spring_length + amount, min_distance, max_distance)
