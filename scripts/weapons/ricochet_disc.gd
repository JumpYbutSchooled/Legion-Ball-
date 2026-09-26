extends "res://scripts/weapons/simple_weapon.gd"
## RICOCHET DISC (Marksman / Long Range): two blades forming a flat ring on the left.
## Throws a disc that homes on the lock and glances off walls up to three times, hitting
## 35% harder after each bounce. Bank it round corners.


func _build() -> void:
	cooldown = 1.2
	lock_on = true
	lock_radius_px = 20.0
	crosshair_shape = "ring"
	var shape := {"arc_radius": 0.7, "tip": Vector3(1.3, 0.0, -0.3), "max_width": 0.18, "max_thickness": 0.06, "segments": 9}
	add_blade(-1.0, 12.0, shape)
	add_blade(-1.0, -12.0, shape)


func _fire(_pressed: bool, just: bool, _released: bool, _hit: Dictionary, _delta: float) -> void:
	if not just or not can_fire():
		return
	start_cooldown()
	for i in _blades.size():
		kick(i)
	var from := ball().global_position + aim_dir() * 1.5
	spawn("res://scripts/weapons/crystal_shot.gd", {
		"position": from, "velocity": aim_dir() * 110.0, "target_path": lock_path(), "turn_rate": 4.0,
		"damage": 3.0, "impulse": 10.0, "bounces": 3, "bounce_bonus": 0.35, "lifetime": 6.0, "size": 0.35, "color": color,
	})
	flash_at(from, aim_dir(), 0.7)
	manager.play_sound("tether", from, -4.0)
