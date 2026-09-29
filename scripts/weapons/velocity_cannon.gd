extends "res://scripts/weapons/simple_weapon.gd"
## VELOCITY CANNON (Momentum / Speed): one wide blade under the ball like a ram. Fires an
## actual bolt that travels at 1.5x your speed (a floor at MIN_SPEED so it's never
## motionless), and hits as hard as you're moving: a tickle standing still, over a
## quarter health bar at top speed (half its old damage, since it can now be dodged in
## flight instead of landing instantly).

@export var base_damage := 0.5
## Extra damage at top speed (100 m/s = 500 on the speedometer).
@export var speed_damage := 7.0
## The bolt's speed is 1.5x the ball's, but never slower than this (m/s).
@export var min_speed := 20.0


func _build() -> void:
	cooldown = 0.9
	lock_on = true
	lock_radius_px = 16.0
	crosshair_shape = "chevron"
	add_blade(1.0, 0.0, {"arc_radius": 0.5, "tip": Vector3(0.0, -0.6, -2.2), "max_width": 0.75, "max_thickness": 0.2, "segments": 6})


func _crosshair_extra(info: Dictionary) -> void:
	info["meter"] = ball().linear_velocity.length() / 100.0


func _update(_delta: float) -> void:
	if manager and manager.ball:
		_set_param("charge_glow", clampf(manager.ball.linear_velocity.length() / 100.0, 0.0, 1.0) * 2.0)


func _fire(_pressed: bool, just: bool, _released: bool, _hit: Dictionary, _delta: float) -> void:
	if not just or not can_fire():
		return
	start_cooldown()
	kick(0)
	var speed := ball().linear_velocity.length()
	var k := clampf(speed / 100.0, 0.0, 1.0)
	var from := tip()
	var dir: Vector3 = (target_point() - from).normalized()
	spawn("res://scripts/weapons/crystal_shot.gd", {
		"position": from, "velocity": dir * maxf(speed, min_speed) * 1.5,
		"damage": base_damage + speed_damage * k, "impulse": lerpf(5.0, 50.0, k),
		"size": lerpf(0.2, 0.45, k), "color": color, "lifetime": 3.0,
	})
	flash_at(from, dir, 0.6 + k)
	manager.play_sound("rail" if k > 0.6 else "zap", from, lerpf(-8.0, 2.0, k))
	manager.shake(0.2 + k * 0.6)
