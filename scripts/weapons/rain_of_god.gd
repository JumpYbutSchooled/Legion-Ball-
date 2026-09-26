extends "res://scripts/weapons/blade_weapon.gd"
## Slot 7 (moderators and the owner): Rain of God. The Gatling with fifty blades instead of six,
## wrapped all the way round the ball, firing one after another at a huge rate.
## Locks like the railgun (the target nearest the circle's center, any range), but the
## lock ignores walls, and so do the shots: a locked target is hit directly, wherever it
## is. With no lock it's hitscan down the crosshair, like the Gatling. Unparryable: the
## hits go straight through shields (weapon.gd hit_object, unblockable).
## Kills play the railgun's impact frames (impact_frames.gd).

@export var gun_count := 50
@export var fire_interval := 0.02
@export var damage := 0.5
@export var hit_impulse := 3.0
@export var lock_radius_px := 70.0
@export var shot_shake := 0.12

var lock_target: Node3D = null
var lock_screen_pos := Vector2.ZERO

var _next := 0
var _cooldown := 0.0
var _shots := 0


func _build() -> void:
	# The Gatling's blades, but fifty: rows rolled round the forward axis, right then
	# left, which is also the firing order.
	kick_open = 0.14
	var rows := int(gun_count / 2.0)
	for i in rows:
		var angle := lerpf(85.0, -85.0, float(i) / maxf(rows - 1, 1))
		for side in [1.0, -1.0]:
			add_blade(side, angle)


func handle_fire(pressed: bool, hit: Dictionary, delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	_update_lock()
	if not pressed or not is_ready():
		return
	# Several shots per physics step when the fire interval is shorter than a step.
	while _cooldown <= 0.0:
		_cooldown += fire_interval
		_fire(hit)


func _update_lock() -> void:
	lock_target = null
	if not is_ready() or not manager.camera:
		return
	# No sight check: the lock sees through walls.
	var found: Array = manager.targets_on_screen(lock_radius_px, INF, false)
	if not found.is_empty():
		lock_target = found[0]["target"]
		lock_screen_pos = found[0]["screen"]


func _update(_delta: float) -> void:
	if not is_ready():
		lock_target = null


## Peer id of the player locked onto, so they get the red warning (lock_warning.gd).
func locked_peer() -> int:
	if lock_target and is_instance_valid(lock_target) and lock_target.has_method("is_blocking"):
		return lock_target.get_multiplayer_authority()
	return 0


func get_crosshair() -> Dictionary:
	return {
		"kind": "rail",
		"radius": lock_radius_px,
		"circle": true,
		"reloading": false,
		"charge": 0.0,
		"locked": lock_target != null and is_instance_valid(lock_target),
		"lock_pos": lock_screen_pos,
	}


func _fire(hit: Dictionary) -> void:
	var index := _next
	_next = (_next + 1) % _blades.size()
	_shots += 1
	kick(index)
	var blade := _blades[index]
	var tip: Vector3 = blade.to_global(blade.call("get_tip"))
	var target_hit := {}
	var aim: Vector3 = manager.aim_point
	if lock_target and is_instance_valid(lock_target):
		# Straight to the target, through anything in the way.
		aim = lock_target.call("get_aim_point")
		target_hit = {"collider": lock_target, "position": aim, "normal": (tip - aim).normalized()}
	elif not hit.is_empty():
		aim = hit["position"]
		target_hit = hit
	var shot_dir := (aim - tip).normalized()
	manager.spawn_beam(tip, shot_dir, tip.distance_to(aim), 0.07, 0.08, 4.0, color)
	# A flash on every few shots; fifty lights a second would be wasteful.
	if _shots % 5 == 0:
		manager.spawn_light(tip, 25.0, 8.0, 0.05, color)
	if not target_hit.is_empty():
		var pos: Vector3 = target_hit["position"]
		manager.spawn_beam(pos, target_hit["normal"], 0.3, 0.25, 0.05, 16.0, color)
		manager.hit_object(target_hit["collider"], damage, pos, shot_dir, hit_impulse, true)
	manager.shake(shot_shake)
	if _shots % 3 == 0:
		manager.play_sound("zap", tip, -12.0)


func refill() -> void:
	_cooldown = 0.0
