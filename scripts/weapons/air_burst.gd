extends "res://scripts/weapons/simple_weapon.gd"
## AIR BURST (Momentum / Speed): two short fins flared out behind the ball. Fire: a small
## burst of speed for you, and a short-range homing shot at the locked foe that hits them
## with your velocity: the faster you're going, the harder they're thrown.

## Speed you gain when firing (m/s, along where you look).
const BOOST := 8.0
## Metres the shot can travel, and how far its lock-on reaches.
const RANGE := 50.0


func _build() -> void:
	cooldown = 2.5
	lock_on = true
	lock_radius_px = 22.0
	lock_range = RANGE
	crosshair_shape = "ring"
	crosshair_radius = 14.0
	var fin := {"arc_radius": 0.4, "tip": Vector3(0.9, 0.5, 1.1), "max_width": 0.26, "max_thickness": 0.12, "segments": 6}
	for side in [1.0, -1.0]:
		add_blade(side, 0.0, fin)


func _crosshair_extra(info: Dictionary) -> void:
	info["meter"] = clampf(ball().linear_velocity.length() / 100.0, 0.0, 1.0)


func _fire(_pressed: bool, just: bool, _released: bool, _hit: Dictionary, _delta: float) -> void:
	if not just or not can_fire():
		return
	start_cooldown()
	var b := ball()
	var speed := b.linear_velocity.length()
	var from := b.global_position + look_dir() * 1.2
	var dir := aim_dir()
	# Players take pushes at ball.gd PVP_PUSH_SCALE: undo that so they get your full speed.
	spawn("res://scripts/weapons/crystal_shot.gd", {
		"position": from, "velocity": dir * maxf(speed + 40.0, 70.0), "target_path": lock_path(), "turn_rate": 8.0,
		"damage": 3.0, "impulse": speed / 0.3, "lifetime": RANGE / maxf(speed + 40.0, 70.0), "size": 0.3, "color": color,
		"explosion": {"radius": 3.0, "damage": 0.0, "force": 0.0, "spark_count": 90, "light_energy": 60.0, "color": color},
	})
	manager.push_ball(look_dir() * BOOST)
	for i in _blades.size():
		kick(i)
	manager.spawn_warp(from, 0.2, 3.0)
	manager.play_sound("zap", from, -2.0)
