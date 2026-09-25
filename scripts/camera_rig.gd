extends Node3D
## Orbit camera that follows a target.
## Click to capture the mouse, move the mouse to orbit, I / O (or Ctrl + wheel) to zoom.
## Q / E also orbit with the keyboard.
## Also drives the speed warp effect (FOV kick + screen shader) and lags vertically on jumps.
## Sensitivity, FOV, shake and effect strength come from the player's Settings.

const SettingsScript := preload("res://scripts/settings.gd")

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
@export var max_speed_fov := 30.0
@export var dash_fov_kick := 35.0
@export var max_fov := 120.0
@export var warp_start_speed := 18.0
@export var warp_full_speed := 55.0
## Warp shader strength at top speed.
@export var speed_warp_strength := 1.5
## Warp shader strength at the peak of a dash.
@export var dash_warp_strength := 3.0
@export var dash_kick_decay := 2.2
@export var shockwave_time := 0.28

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
var _warp := 0.0
var _shock := 1.0  # Shockwave progress, 0 -> 1. 1 means inactive.
var _jump_lag := 0.0
var _dash_lag := 0.0
var _pivot_height := 0.0
var _sensitivity_scale := 1.0
var _shake_scale := 1.0
var _effects_scale := 1.0
var _trauma := 0.0
var _shake_time := 0.0
var _noise := FastNoiseLite.new()
## Rushing-air loop, louder and higher the faster the ball goes.
var _wind: AudioStreamPlayer


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
	base_fov = SettingsScript.read(tree, "fov")
	_shake_scale = SettingsScript.read(tree, "camera_shake")
	_effects_scale = SettingsScript.read(tree, "screen_effects")


func _ready() -> void:
	# Moved in _process, so it must not be physics-interpolated.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
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


func _on_dashed() -> void:
	_dash_kick = 1.0
	_shock = 0.0
	_dash_lag = 1.0


func _process(delta: float) -> void:
	if target:
		var goal := target.get_global_transform_interpolated().origin
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

	var turn := Input.get_axis("camera_left", "camera_right")
	rotation.y -= turn * key_turn_speed * delta
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
	if target is RigidBody3D:
		speed = (target as RigidBody3D).linear_velocity.length()
	_update_shake(delta, speed)

	var speed_amount := clampf(inverse_lerp(warp_start_speed, warp_full_speed, speed), 0.0, 1.0)
	_update_wind(speed)
	_dash_kick = move_toward(_dash_kick, 0.0, dash_kick_decay * delta)
	_shock = minf(_shock + delta / shockwave_time, 1.0)

	var goal := maxf(speed_amount * speed_warp_strength, ease(_dash_kick, 0.5) * dash_warp_strength) * _effects_scale
	# Hit instantly on the way up, ease down.
	if goal > _warp:
		_warp = goal
	else:
		_warp = lerpf(_warp, goal, 1.0 - exp(-7.0 * delta))

	var fov_kick := speed_amount * max_speed_fov + ease(_dash_kick, 0.5) * dash_fov_kick
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
	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sens := mouse_sensitivity * _sensitivity_scale
		rotation.y -= event.relative.x * sens
		_pitch.rotation.x = clampf(
			_pitch.rotation.x - event.relative.y * sens,
			deg_to_rad(min_pitch_deg),
			deg_to_rad(max_pitch_deg)
		)


func _zoom(amount: float) -> void:
	_spring_arm.spring_length = clampf(_spring_arm.spring_length + amount, min_distance, max_distance)
