extends "res://scripts/weapons/simple_weapon.gd"
## GRAVITY WELL (Frost / Control): three blades curled into a ring on the left. Throw a
## singularity; where it lands (or after a second in the air) it becomes a well that
## drags every other player within 15m into it for 2.5s, then pops.


func _build() -> void:
	cooldown = 6.0
	lock_on = true
	crosshair_shape = "dot"
	var shape := {"arc_radius": 0.55, "tip": Vector3(0.2, 0.0, -1.3), "max_width": 0.22, "max_thickness": 0.16, "segments": 7}
	for roll in [0.0, 60.0, -60.0]:
		add_blade(-1.0, roll, shape)


func _fire(_pressed: bool, just: bool, _released: bool, _hit: Dictionary, _delta: float) -> void:
	if not just or not can_fire():
		return
	start_cooldown()
	for i in _blades.size():
		kick(i)
	var from := ball().global_position + aim_dir() * 1.5
	spawn("res://scripts/weapons/crystal_shot.gd", {
		"position": from, "velocity": aim_dir() * 80.0 + Vector3.UP * 4.0, "gravity": 10.0,
		"damage": 0.0, "impulse": 0.0, "lifetime": 1.6, "size": 0.5, "color": color,
		"spawn_script": "res://scripts/weapons/gravity_well_orb.gd",
		"spawn_props": {"color": color, "lifetime": 2.5, "radius": 28.0},
	})
	flash_at(from, aim_dir())
	manager.play_sound("implode", from, -4.0)
