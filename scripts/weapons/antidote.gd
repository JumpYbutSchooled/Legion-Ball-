extends "res://scripts/weapons/simple_weapon.gd"
## ANTIDOTE (Medical / Support): the only weapon that works while you're stunned, and the
## only one you can swap to while stunned (weapon.gd). Press: if a stunned ally is in
## range - found through walls, no need for precise aim - it cures them; otherwise it
## cures you. 2 in the magazine, 60s to reload both.

const RANGE := 120.0
const MAG := 2

var ammo := MAG
var reloading := false
var _reload_t := 0.0


func _build() -> void:
	lock_on = true
	lock_radius_px = 60.0
	lock_range = RANGE
	lock_through_walls = true
	crosshair_shape = "cross"
	add_blade(1.0, 0.0, {"arc_radius": 0.4, "tip": Vector3(0.2, 0.4, -2.0), "max_width": 0.14, "max_thickness": 0.1, "segments": 6})


## Finds the nearest stunned ally (not the usual enemy lock).
func _update_lock() -> void:
	lock_target = null
	if not manager.camera:
		return
	for entry in manager.ally_targets_on_screen(lock_radius_px, lock_range):
		var target: Node3D = entry["target"]
		if target != manager.ball and target.call("is_staggered"):
			lock_target = target
			lock_screen = entry["screen"]
			return


func _crosshair_extra(info: Dictionary) -> void:
	info["meter"] = float(ammo) / MAG
	info["ready"] = not reloading and ammo > 0


func _update(delta: float) -> void:
	if reloading:
		_reload_t += delta
		if _reload_t >= 60.0:
			reloading = false
			ammo = MAG
			flash(Color(0.4, 1.0, 0.6))


func _fire(_pressed: bool, just: bool, _released: bool, _hit: Dictionary, _delta: float) -> void:
	if not just or reloading or ammo <= 0:
		return
	ammo -= 1
	if ammo <= 0:
		reloading = true
		_reload_t = 0.0
	kick(0)
	if lock_target and is_instance_valid(lock_target):
		manager.cure(lock_target)
		manager.spawn_beam(tip(), (lock_target.global_position - tip()).normalized(), tip().distance_to(lock_target.global_position), 0.15, 0.2, 10.0, color)
	else:
		manager.cure(ball())
	manager.spawn_light(ball().global_position, 20.0, 6.0, 0.15, color)
	manager.play_sound("shield", ball().global_position, 0.0)
