extends "res://scripts/weapons/simple_weapon.gd"
## ARBALEST (Marksman / Long Range): a crossbow: a horizontal bow of two blades over one
## straight stock. Fires a heavy bolt that shoves its target hard; if there's a wall behind
## them (within 22 m, along the shove) they're slammed into it and PINNED there for 2s.


func _build() -> void:
	cooldown = 2.0
	lock_on = true
	lock_radius_px = 16.0
	crosshair_shape = "cross"
	crosshair_radius = 12.0
	var bow := {"arc_radius": 0.4, "tip": Vector3(1.5, 0.35, -1.4), "max_width": 0.14, "max_thickness": 0.1, "segments": 8}
	for side in [1.0, -1.0]:
		add_blade(side, 0.0, bow)
	add_blade(1.0, 90.0, {"arc_radius": 0.2, "tip": Vector3(0.0, 0.25, -2.8), "max_width": 0.14, "max_thickness": 0.14, "segments": 6})


func _fire(_pressed: bool, just: bool, _released: bool, _hit: Dictionary, _delta: float) -> void:
	if not just or not can_fire():
		return
	start_cooldown()
	for i in _blades.size():
		kick(i)
	var from := tip(2)
	var dir: Vector3 = (target_point() - from).normalized()
	spawn("res://scripts/weapons/crystal_shot.gd", {
		"position": from, "velocity": dir * 520.0, "target_path": lock_path(), "turn_rate": 3.0, "gravity": 2.0, "damage": 7.0, "impulse": 170.0,
		"pin": 2.0, "lifetime": 5.0, "size": 0.2, "color": color,
	})
	flash_at(from, dir, 1.0)
	manager.play_sound("rail", from, -6.0)
	manager.knockback(dir, 10.0)
