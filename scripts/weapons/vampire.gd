extends "res://scripts/weapons/simple_weapon.gd"
## VAMPIRE (Medical / Support): one curved fang blade. Press while locked onto an enemy
## in range to latch on and drain them for up to 3s, healing yourself for what you take
## and stunning them the whole time. Dashing cuts the drain short. When it ends (or is
## cut short) you're flung backward, away from them, at high speed. 5s reload.

const RANGE := 30.0
const DRAIN_TIME := 3.0
const TICK := 0.5
const DRAIN_PER_TICK := 6.0
const FLING_SPEED := 60.0

var _channeling := false
var _time := 0.0
var _tick_timer := 0.0
var _target: Node3D = null


func _build() -> void:
	cooldown = 5.0
	lock_on = true
	lock_radius_px = 20.0
	lock_range = RANGE
	crosshair_shape = "cross"
	add_blade(1.0, -15.0, {"arc_radius": 0.6, "tip": Vector3(0.8, -0.2, -2.6), "max_width": 0.22, "max_thickness": 0.12, "segments": 8})


func _fire(_pressed: bool, just: bool, _released: bool, _hit: Dictionary, delta: float) -> void:
	if _channeling:
		_time += delta
		if not _target or not is_instance_valid(_target) or not _target.call("is_alive"):
			_end_channel()
			return
		_tick_timer -= delta
		if _tick_timer <= 0.0:
			_tick_timer = TICK
			manager.hit_object(_target, DRAIN_PER_TICK, _target.call("get_aim_point"), Vector3.ZERO, 0.0)
			manager.heal(ball(), DRAIN_PER_TICK)
			manager.apply_status(_target, "freeze", TICK + 0.1)
			manager.spawn_beam(tip(), (_target.global_position - tip()).normalized(), tip().distance_to(_target.global_position), 0.12, 0.1, 8.0, color)
		if _time >= DRAIN_TIME or Input.is_action_just_pressed("dash"):
			_end_channel()
		return
	if just and can_fire() and lock_target and is_instance_valid(lock_target):
		start_cooldown()
		_channeling = true
		_time = 0.0
		_tick_timer = 0.0
		_target = lock_target
		kick(0)
		manager.play_sound("tether", ball().global_position, -4.0)


func _end_channel() -> void:
	_channeling = false
	var dir := -look_dir()
	if _target and is_instance_valid(_target):
		var away := ball().global_position - _target.global_position
		away.y = 0.0
		if away.length() > 0.1:
			dir = away.normalized()
	manager.push_ball(dir * FLING_SPEED)
	manager.spawn_warp(ball().global_position, 0.3, 4.0)
	manager.play_sound("dash", ball().global_position, 0.0)
	_target = null
