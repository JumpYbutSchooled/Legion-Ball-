extends "res://scripts/weapons/simple_weapon.gd"
## ASPRINT (Momentum / Speed): one long spike straight ahead, like a lance. Lock onto a foe
## and fire: you go to top speed instantly and fly at them, homing, as the bullet. Hitting
## them deals heavy damage and throws them. (Needs a lock; your dash and other weapons are
## off while you fly.)

const MAX_TIME := 2.5
## Speed you're flung at, as a multiple of your top speed.
const SPEED_MULT := 1.25
const HIT_DAMAGE := 25.0

var _rushing := false


func _build() -> void:
	cooldown = 9.0
	lock_on = true
	lock_radius_px = 24.0
	lock_range = 250.0
	crosshair_shape = "cross"
	add_blade(1.0, 0.0, {"arc_radius": 0.3, "tip": Vector3(0.0, 0.1, -3.2), "max_width": 0.2, "max_thickness": 0.2, "segments": 7})


func _fire(_pressed: bool, just: bool, _released: bool, _hit: Dictionary, _delta: float) -> void:
	if not just or not can_fire() or _rushing:
		return
	if not lock_target or not is_instance_valid(lock_target):
		manager.play_sound("ui_hover", ball().global_position, -8.0)
		return
	start_cooldown()
	var b := ball()
	_rushing = true
	if not b.is_connected("rush_ended", _on_rush_ended):
		b.connect("rush_ended", _on_rush_ended)
	b.call("start_rush", aim_dir(), float(b.get("top_speed")) * SPEED_MULT, MAX_TIME, lock_target)
	kick(0)
	manager.spawn_warp(b.global_position, 0.4, 6.0)
	manager.play_sound("rail", b.global_position, 0.0)
	manager.shake(0.5)


func _on_rush_ended(pos: Vector3, hit: Node3D, _into_wall: bool) -> void:
	if not _rushing:
		return
	_rushing = false
	if hit and hit.has_method("take_hit"):
		var dir := ball().linear_velocity.normalized()
		manager.hit_object(hit, HIT_DAMAGE, pos, dir, 150.0)
		manager.spawn_explosion({"position": pos, "color": color, "radius": 5.0, "damage": 4.0, "force": 30.0,
			"spark_count": 260, "chunk_count": 24, "light_energy": 200.0, "warp_strength": 0.4, "sound": "boom"})
		manager.shake(0.9)
