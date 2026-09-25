extends "res://scripts/weapons/blade_weapon.gd"
## Slot 5: Nova, a charged blast around the ball. Four blades crossed in an X (the lower
## pair shallower so they clear the floor). Hold fire to charge: the blades spread open
## wider and wider and glow; release to detonate. The blast grows with charge: it
## damages and throws everything nearby and staggers targets (they freeze in place).
## - On the ground it launches the ball high into the air.
## - In the air it throws the ball straight down; hitting the ground sets off a much
##   bigger blast (the slam).
## Combos: stagger drones so the Railgun can't miss; launch up, then slam back down.

@export var charge_time := 1.2
## 0 = no cooldown: detonate again as soon as you've charged.
@export var cooldown := 0.0
## Blast radius, damage, force and ball launch at no charge and at full charge.
@export var radius_min := 4.0
@export var radius_max := 12.0
@export var damage_min := 3.0
@export var damage_max := 9.0
@export var force_min := 10.0
@export var force_max := 40.0
@export var launch_min := 28.0
@export var launch_max := 70.0
## Shorter than it used to be: 2s frozen was a guaranteed railgun kill.
@export var stagger_time := 1.2
## Only blasts charged at least this much stagger (with no cooldown, tapping it would
## otherwise stun-lock anyone nearby).
@export var stagger_min_charge := 0.6
## How far the blades open up at full charge.
@export var charge_spread := 0.55
@export var charge_open := 0.5

@export_group("Air slam")
## Downward speed when detonated in the air.
@export var slam_speed_min := 65.0
@export var slam_speed_max := 100.0
@export var slam_radius_min := 10.0
@export var slam_radius_max := 16.0
@export var slam_damage_min := 8.0
@export var slam_damage_max := 16.0
## Height above the ground that counts as "in the air".
@export var air_height := 1.6

var charge := 0.0
var _charging := false
var _cooldown := 0.0
var _was_pressed := false
## The blast pop: the blades fling wide open, then settle.
var _burst := 0.0
var _hum: AudioStreamPlayer3D
# Air slam in progress (local player only).
var _slamming := false
var _slam_charge := 0.0
var _slam_timer := 0.0


func _build() -> void:
	var shape := {
		"arc_radius": 0.85,
		"tip": Vector3(0.35, 0.0, -1.8),
		"max_width": 0.3,
		"max_thickness": 0.24,
		"segments": 8,
	}
	for angle in [55.0, -28.0]:
		for side in [1.0, -1.0]:
			add_blade(side, angle, shape)


func handle_fire(pressed: bool, _hit: Dictionary, delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	var released := _was_pressed and not pressed
	_was_pressed = pressed
	if not is_ready():
		_charging = false
		return
	if pressed and _cooldown == 0.0:
		_charging = true
		charge = minf(charge + delta / charge_time, 1.0)
	elif released and _charging:
		_detonate()


func _on_exit() -> void:
	_charging = false


func get_crosshair() -> Dictionary:
	return {
		"kind": "nova",
		"charge": charge,
		"ready": _cooldown == 0.0,
		"cooldown": 1.0 - _cooldown / cooldown if cooldown > 0.0 else 1.0,
	}


func get_net_charge() -> float:
	return charge if _charging else 0.0


func apply_net_charge(c: float) -> void:
	charge = c


func _update(delta: float) -> void:
	var local: bool = not manager or manager.is_multiplayer_authority()
	if not _charging and local:
		charge = move_toward(charge, 0.0, delta * 3.0)
	_burst = move_toward(_burst, 0.0, delta * 2.5)
	var c := charge * charge
	var pop := ease(_burst, 0.4)
	# Open up like the other weapons do: facets spread, tips splay, glow builds.
	_set_param("charge_spread", c * charge_spread + pop * 0.5)
	_set_param("charge_glow", c * 1.5 + pop * 2.0)
	tip_open = c * charge_open + pop * 0.6
	_update_hum()


func _update_hum() -> void:
	if _hum == null and is_inside_tree():
		var sfx := get_tree().root.get_node_or_null("Sfx")
		if sfx:
			_hum = sfx.call("make_loop", "charge", self)
	if not _hum:
		return
	var on := visible and charge > 0.02
	if on and not _hum.playing:
		_hum.play()
	elif not on and _hum.playing:
		_hum.stop()
	_hum.volume_db = lerpf(-26.0, -8.0, charge)
	_hum.pitch_scale = lerpf(0.9, 2.6, charge)


func _physics_process(delta: float) -> void:
	if not _slamming or not manager or not manager.is_multiplayer_authority():
		return
	_slam_timer -= delta
	var ball: RigidBody3D = manager.ball
	if ball.get("dead") or _slam_timer <= 0.0:
		_slamming = false
		return
	var ground: Dictionary = manager.raycast(ball.global_position, ball.global_position + Vector3.DOWN * 1.0)
	if not ground.is_empty():
		_slamming = false
		_slam(ground["position"])


func _detonate() -> void:
	var k := charge
	_charging = false
	charge = 0.0
	_cooldown = cooldown
	_burst = 1.0
	for i in _blades.size():
		kick(i)

	var ball: RigidBody3D = manager.ball
	var pos := ball.global_position
	var in_air: bool = manager.raycast(pos, pos + Vector3.DOWN * air_height).is_empty()
	manager.spawn_explosion({
		"position": pos,
		"color": color,
		"radius": lerpf(radius_min, radius_max, k),
		"damage": lerpf(damage_min, damage_max, k),
		"force": lerpf(force_min, force_max, k),
		"stagger_time": stagger_time if k >= stagger_min_charge else 0.0,
		"spark_count": int(lerpf(80.0, 260.0, k)),
		"spark_speed": lerpf(14.0, 30.0, k),
		"chunk_count": int(lerpf(8.0, 24.0, k)),
		"light_energy": lerpf(80.0, 260.0, k),
		"warp_strength": lerpf(0.15, 0.4, k),
		"flat_sparks": not in_air,
		"sound": "nova",
	})

	if in_air:
		# Thrown straight down; the real blast comes when it hits the ground.
		var v := ball.linear_velocity
		manager.push_ball(Vector3(0.0, -maxf(v.y, 0.0) - lerpf(slam_speed_min, slam_speed_max, k), 0.0))
		_slamming = true
		_slam_charge = k
		_slam_timer = 4.0
	else:
		manager.push_ball(Vector3.UP * lerpf(launch_min, launch_max, k))
	manager.shake(lerpf(0.5, 1.0, k))


func _slam(ground_pos: Vector3) -> void:
	var k := _slam_charge
	manager.spawn_explosion({
		"position": ground_pos + Vector3.UP * 0.3,
		"color": color,
		"radius": lerpf(slam_radius_min, slam_radius_max, k),
		"damage": lerpf(slam_damage_min, slam_damage_max, k),
		"force": lerpf(45.0, 80.0, k),
		"stagger_time": stagger_time,
		"spark_count": int(lerpf(300.0, 550.0, k)),
		"spark_speed": lerpf(30.0, 45.0, k),
		"chunk_count": int(lerpf(30.0, 60.0, k)),
		"light_energy": lerpf(300.0, 600.0, k),
		"warp_strength": 0.5,
		"shock_time": 0.5,
		"flat_sparks": true,
		"sound": "land_slam",
	})
	# Stop dead on impact (no rubber-ball rebound), then a small hop off the crater.
	var ball: RigidBody3D = manager.ball
	var v := ball.linear_velocity
	ball.linear_velocity = Vector3(v.x, 0.0, v.z)
	manager.push_ball(Vector3.UP * 6.0)
	manager.shake(1.0)
	_burst = 1.0
