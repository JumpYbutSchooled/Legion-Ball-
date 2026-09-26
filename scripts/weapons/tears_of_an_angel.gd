extends "res://scripts/weapons/blade_weapon.gd"
## Slot 8 (moderators and the owner): Tears of an Angel, a white Swarm with no limits.
## Hold fire to lock targets anywhere on screen: no range limit and no line of sight
## needed, and no cap (a target can be locked again and again). The crosshair counts
## the locks. Release and the missiles leave one by one in quick succession, each on
## its own, alternating blades. They fly twice as fast as Swarm's, steer and glance
## round walls to reach their target, and each hit does 25 damage.
## Parryable, but a parried tear kills whoever fired it (scripts/arena.gd).

## Twice Swarm's missile speed.
const MISSILE_SPEED := 190.0

@export var paint_radius_px := 190.0
@export var paint_interval := 0.12
## Only so the counter stays readable; for play it's effectively unlimited.
@export var max_locks := 99
## Seconds between missiles once released.
@export var launch_interval := 0.06
@export var cooldown := 0.8
## x4 online (ball.gd PVP_DAMAGE_SCALE) = 25 damage per hit.
@export var missile_damage := 6.25
## Long enough to cross any map.
@export var missile_lifetime := 8.0

## Locked targets, in lock order (the same target can appear many times).
var locks: Array[Node3D] = []
var _painting := false
var _paint_timer := 0.0
var _cooldown := 0.0
var _was_pressed := false
var _next_blade := 0
## Missiles still to launch: [target or null, aim point].
var _queue: Array = []
var _launch_timer := 0.0


func _build() -> void:
	var shape := {
		"arc_radius": 0.75,
		"tip": Vector3(0.3, 0.0, -1.8),
		"max_width": 0.22,
		"max_thickness": 0.16,
		"segments": 8,
	}
	# Two pairs of wings raised behind the ball.
	for angle in [35.0, 60.0]:
		for side in [1.0, -1.0]:
			add_blade(side, angle, shape)


func handle_fire(pressed: bool, _hit: Dictionary, delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	var released := _was_pressed and not pressed
	_was_pressed = pressed
	_prune()
	_fire_queue(delta)
	if not is_ready():
		_painting = false
		locks.clear()
		return
	if pressed and _cooldown == 0.0 and _queue.is_empty():
		if not _painting:
			_painting = true
			_paint_timer = 0.0
		_paint_timer -= delta
		if _paint_timer <= 0.0 and locks.size() < max_locks:
			_paint_timer = paint_interval
			_lock_next()
	elif released and _painting:
		_release()


func _on_exit() -> void:
	_painting = false
	locks.clear()


func get_crosshair() -> Dictionary:
	# Where the locked targets are, once each (the counter says how many missiles).
	var marks: Array[Vector2] = []
	var seen := {}
	for target in locks:
		if seen.has(target):
			continue
		seen[target] = true
		var p: Vector3 = target.call("get_aim_point")
		if not manager.camera.is_position_behind(p):
			marks.append(manager.screen_pos(p))
	return {
		"kind": "tears",
		"radius": paint_radius_px,
		"painting": _painting,
		"count": locks.size(),
		"marks": marks,
		"ready": _cooldown == 0.0 and _queue.is_empty(),
	}


func _update(_delta: float) -> void:
	# Blades brighten as the locks pile up.
	_set_param("charge_glow", clampf(float(locks.size()) / 12.0, 0.0, 1.0) * 1.6)


func _prune() -> void:
	for i in range(locks.size() - 1, -1, -1):
		var t = locks[i]
		if not is_instance_valid(t) or not t.call("is_alive"):
			locks.remove_at(i)


## Locks the next target: one not locked yet if there is one, else another missile on
## the one nearest the middle. Anywhere on screen, any distance, walls or not.
func _lock_next() -> void:
	var found: Array = manager.targets_on_screen(paint_radius_px)
	if found.is_empty():
		return
	var pick: Dictionary = found[0]
	for entry in found:
		if not locks.has(entry["target"]):
			pick = entry
			break
	locks.append(pick["target"])
	manager.spawn_light(pick["point"], 10.0, 3.0, 0.08, color)
	manager.play_sound("equip", global_position, -18.0)


func _release() -> void:
	_painting = false
	_cooldown = cooldown
	var aim: Vector3 = manager.aim_point
	if locks.is_empty():
		# Nothing locked: a pair straight down the crosshair.
		_queue = [[null, aim], [null, aim]]
	else:
		for target in locks:
			_queue.append([target, aim])
	locks.clear()
	_launch_timer = 0.0


## Missiles leave one at a time, each on its own.
func _fire_queue(delta: float) -> void:
	if _queue.is_empty():
		return
	_launch_timer -= delta
	while _launch_timer <= 0.0 and not _queue.is_empty():
		_launch_timer += launch_interval
		var entry: Array = _queue.pop_front()
		_launch_one(entry[0], entry[1])


func _launch_one(target: Node3D, aim: Vector3) -> void:
	var blade := _blades[_next_blade]
	kick(_next_blade)
	_next_blade = (_next_blade + 1) % _blades.size()
	var tip: Vector3 = blade.to_global(blade.call("get_tip"))
	var goal := aim
	if target and is_instance_valid(target):
		goal = target.call("get_aim_point")
	var toward := (goal - tip).normalized()
	var out := (tip - global_position).normalized()
	var launch := (toward + out * 0.6 + Vector3.UP * 0.4).normalized()
	manager.spawn_missile({
		"position": tip,
		"color": color,
		"speed": MISSILE_SPEED,
		"turn_rate": 30.0,
		"lifetime": missile_lifetime,
		"damage": missile_damage,
		"mark_time": 0.0,
		"avoid_walls": true,
		"direct_hit": true,
		"parry_kills": true,
		"aim_point": goal,
		"has_aim_point": true,
		"velocity": launch * MISSILE_SPEED,
		"target_path": String(target.get_path()) if target and is_instance_valid(target) else "",
	})
	manager.spawn_beam(tip, launch, 0.8, 0.4, 0.05, 16.0, color)
	manager.spawn_light(tip, 24.0, 6.0, 0.05, color)
	manager.play_sound("missile", tip, -9.0)
	manager.shake(0.12)


func refill() -> void:
	_cooldown = 0.0
	_queue.clear()
