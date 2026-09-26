extends "res://scripts/weapons/simple_weapon.gd"
## SONIC BOOM (Momentum / Speed): three swept-back blades in a chevron on top. Going
## fast (45 m/s+), press to fire your speed off as a shockwave: a cone 25m ahead hits
## everyone in it (harder the faster you were), and you slow right down.

@export var min_speed := 45.0
@export var reach := 45.0


func _build() -> void:
	cooldown = 1.5
	crosshair_shape = "chevron"
	crosshair_radius = 16.0
	var shape := {"arc_radius": 0.45, "tip": Vector3(0.0, 1.0, 1.8), "max_width": 0.25, "max_thickness": 0.1, "segments": 7}
	add_blade(1.0, 0.0, shape)
	add_blade(1.0, 35.0, {"arc_radius": 0.45, "tip": Vector3(0.8, 0.8, 1.6), "max_width": 0.22, "max_thickness": 0.1, "segments": 7})
	add_blade(-1.0, 35.0, {"arc_radius": 0.45, "tip": Vector3(0.8, 0.8, 1.6), "max_width": 0.22, "max_thickness": 0.1, "segments": 7})


func _crosshair_extra(info: Dictionary) -> void:
	var s := ball().linear_velocity.length()
	info["meter"] = s / min_speed
	info["ready"] = can_fire() and s >= min_speed


func _fire(_pressed: bool, just: bool, _released: bool, _hit: Dictionary, _delta: float) -> void:
	if not just or not can_fire():
		return
	var b := ball()
	var speed := b.linear_velocity.length()
	if speed < min_speed:
		manager.play_sound("unequip", b.global_position, -10.0)
		return
	start_cooldown()
	var k := clampf(speed / 100.0, 0.45, 1.0)
	var fwd := look_dir()
	var center := b.global_position
	for t in targets_near(center + fwd * reach * 0.5, reach * 0.6):
		var p: Vector3 = t.call("get_aim_point")
		var to := p - center
		if to.length() > reach or to.normalized().dot(fwd) < 0.6:
			continue
		var sight: Dictionary = manager.raycast(center, p)
		if not sight.is_empty() and sight["collider"] != t:
			continue
		manager.hit_object(t, lerpf(3.0, 11.0, k), p, fwd, lerpf(20.0, 55.0, k))
	# The boom: rings rolling out ahead, a pressure wave.
	for i in 4:
		manager.spawn_warp(center + fwd * (4.0 + i * 5.0), lerpf(0.2, 0.45, k), 3.0 + i * 1.5)
	manager.spawn_explosion({"position": center + fwd * 3.0, "color": color, "radius": 3.0,
		"damage": 0.0, "force": 0.0, "spark_count": 220, "spark_speed": 40.0, "light_energy": 200.0,
		"warp_strength": 0.4, "sound": "impact_boom"})
	for i in _blades.size():
		kick(i)
	b.linear_velocity *= 0.35
	manager.shake(0.8)
