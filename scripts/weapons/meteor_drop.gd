extends "res://scripts/weapons/simple_weapon.gd"
## METEOR DROP (Skyborne / Mobility): three heavy blades pointing down under the ball.
## In the air, press to slam straight down; the crater's size and damage grow with how
## far you fell. On the ground, press to leap up first.

var _slamming := false
var _start_height := 0.0


func _build() -> void:
	cooldown = 2.5
	crosshair_shape = "chevron"
	var shape := {"arc_radius": 0.5, "tip": Vector3(0.0, -2.2, -0.5), "max_width": 0.4, "max_thickness": 0.3, "segments": 7}
	add_blade(1.0, 0.0, shape)
	add_blade(1.0, 30.0, shape)
	add_blade(-1.0, 30.0, shape)


func _fire(_pressed: bool, just: bool, _released: bool, _hit: Dictionary, _delta: float) -> void:
	var b := ball()
	var ground: Dictionary = manager.raycast(b.global_position, b.global_position + Vector3.DOWN * 1.2)
	if _slamming:
		if not ground.is_empty():
			_impact(ground["position"])
		return
	if not just or not can_fire():
		return
	if ground.is_empty():
		_slamming = true
		_start_height = b.global_position.y
		manager.push_ball(Vector3(0.0, -maxf(b.linear_velocity.y, 0.0) - 90.0, 0.0))
		manager.play_sound("dash", b.global_position, 0.0)
	else:
		start_cooldown(0.6)
		manager.push_ball(Vector3.UP * 26.0)
		manager.play_sound("jump", b.global_position, 0.0)
	for i in _blades.size():
		kick(i)


func _impact(pos: Vector3) -> void:
	_slamming = false
	start_cooldown()
	var fall := clampf(_start_height - pos.y, 0.0, 120.0)
	var k := clampf(fall / 60.0, 0.15, 1.0)
	manager.spawn_explosion({
		"position": pos + Vector3.UP * 0.3, "color": color, "radius": lerpf(5.0, 15.0, k),
		"damage": lerpf(3.0, 12.0, k), "force": lerpf(20.0, 60.0, k), "flat_sparks": true,
		"spark_count": int(lerpf(150, 500, k)), "chunk_count": int(lerpf(15, 50, k)),
		"light_energy": lerpf(150, 500, k), "warp_strength": lerpf(0.2, 0.5, k), "sound": "land_slam",
	})
	var b := ball()
	b.linear_velocity = Vector3(b.linear_velocity.x, 0.0, b.linear_velocity.z)
	manager.push_ball(Vector3.UP * 6.0)
	manager.shake(lerpf(0.5, 1.0, k))
