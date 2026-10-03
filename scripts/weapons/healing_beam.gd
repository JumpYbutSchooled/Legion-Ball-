extends "res://scripts/weapons/simple_weapon.gd"
## HEALING BEAM (Medical / Support): fire at an ally (or yourself) to heal 5 HP/s,
## spreading to other allies nearby - while draining 5 HP/s from you (never lethal). 3s
## of charge per magazine, then a 10s reload. Infinite range: any ally you can see.

const HEAL_PER_SEC := 5.0
const SELF_DRAIN_PER_SEC := 5.0
const SPREAD_RADIUS := 15.0
const MAG_TIME := 3.0
const RELOAD_TIME := 10.0
const RANGE := 100000.0
const TICK := 0.5

var ammo := MAG_TIME
var reloading := false
var _reload_t := 0.0
var _tick_timer := 0.0


func _build() -> void:
	lock_on = true
	lock_radius_px = 18.0
	lock_range = RANGE
	crosshair_shape = "ring"
	add_blade(1.0, 0.0, {"arc_radius": 0.5, "tip": Vector3(0.3, 0.3, -2.4), "max_width": 0.15, "max_thickness": 0.1, "segments": 8})


## Allies (or ourself), not the usual enemy lock.
func _update_lock() -> void:
	lock_target = null
	if not manager.camera:
		return
	var found: Array = manager.ally_targets_on_screen(lock_radius_px, lock_range)
	if not found.is_empty():
		lock_target = found[0]["target"]
		lock_screen = found[0]["screen"]


func _crosshair_extra(info: Dictionary) -> void:
	info["meter"] = ammo / MAG_TIME
	info["ready"] = not reloading and ammo > 0.0


func _update(delta: float) -> void:
	if reloading:
		_reload_t += delta
		if _reload_t >= RELOAD_TIME:
			reloading = false
			ammo = MAG_TIME
			flash(Color(0.3, 1.0, 0.5))
	_set_param("charge_glow", 1.0 if not reloading and ammo > 0.0 else 0.0)


func _fire(pressed: bool, just: bool, _released: bool, _hit: Dictionary, delta: float) -> void:
	if just and reloading:
		manager.play_sound("ui_hover", ball().global_position, -8.0)
	if not pressed or reloading or ammo <= 0.0:
		return
	var t := lock_target
	if not t or not is_instance_valid(t) or not t.call("is_alive") or not manager.is_ally(t):
		return
	ammo = maxf(ammo - delta, 0.0)
	if ammo <= 0.0:
		reloading = true
		_reload_t = 0.0
	_tick_timer -= delta
	if _tick_timer <= 0.0:
		_tick_timer = TICK
		manager.heal(t, HEAL_PER_SEC * TICK)
		manager.heal(ball(), -SELF_DRAIN_PER_SEC * TICK)
		for other in get_tree().get_nodes_in_group("lock_targets"):
			if other == t or not other.call("is_alive") or not manager.is_ally(other):
				continue
			if other.global_position.distance_to(t.global_position) <= SPREAD_RADIUS:
				manager.heal(other, HEAL_PER_SEC * TICK * 0.5)
	manager.spawn_beam(tip(), (t.global_position - tip()).normalized(), tip().distance_to(t.global_position), 0.1, 0.15, 6.0, color)
