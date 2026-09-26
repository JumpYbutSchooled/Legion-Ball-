extends "res://scripts/weapons/simple_weapon.gd"
## VELOCITY CANNON (Momentum / Speed): one wide blade under the ball like a ram. Its shot
## hits as hard as you're moving: a tickle standing still, over half a health bar at
## top speed (the meter shows your speed).

@export var base_damage := 1.0
## Extra damage at top speed (100 m/s = 500 on the speedometer).
@export var speed_damage := 14.0


func _build() -> void:
	cooldown = 0.9
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
	var k := clampf(ball().linear_velocity.length() / 100.0, 0.0, 1.0)
	var from := tip()
	var dir: Vector3 = (manager.aim_point - from).normalized()
	var shot := hitscan(from, dir, 400.0, base_damage + speed_damage * k, lerpf(5.0, 50.0, k))
	tracer(from, shot["end"], lerpf(0.1, 0.6, k), lerpf(5.0, 24.0, k))
	flash_at(from, dir, 0.6 + k)
	for hit in shot["hits"]:
		manager.spawn_explosion({"position": hit["position"], "color": color, "radius": lerpf(1.0, 4.0, k),
			"damage": 0.0, "force": 0.0, "spark_count": int(lerpf(20, 160, k)), "light_energy": lerpf(20, 160, k)})
	manager.play_sound("rail" if k > 0.6 else "zap", from, lerpf(-8.0, 2.0, k))
	manager.shake(0.2 + k * 0.6)
