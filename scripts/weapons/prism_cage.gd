extends "res://scripts/weapons/simple_weapon.gd"
## PRISM CAGE (Frost / Control): four short blades meeting in a box frame in front.
## Fires a slow crystal orb; the first player or target it hits is locked in a crystal
## cage for 2s (held in place, still able to shoot).


func _build() -> void:
	cooldown = 5.0
	lock_on = true
	lock_radius_px = 18.0
	crosshair_shape = "cross"
	var shape := {"arc_radius": 0.5, "tip": Vector3(0.9, 0.0, -1.5), "max_width": 0.26, "max_thickness": 0.22, "segments": 6}
	for roll in [45.0, -45.0]:
		for side in [1.0, -1.0]:
			add_blade(side, roll, shape)


func _fire(_pressed: bool, just: bool, _released: bool, _hit: Dictionary, _delta: float) -> void:
	if not just or not can_fire():
		return
	start_cooldown()
	for i in _blades.size():
		kick(i)
	var from := ball().global_position + aim_dir() * 1.6
	spawn("res://scripts/weapons/crystal_shot.gd", {
		"position": from, "velocity": aim_dir() * 55.0, "target_path": lock_path(), "turn_rate": 2.5, "damage": 2.0, "impulse": 2.0,
		"lifetime": 5.0, "size": 0.6, "color": color, "status": "cage", "status_time": 2.0,
		"spawn_script": "res://scripts/weapons/cage_fx.gd", "spawn_on_hit": true,
		"spawn_props": {"color": color, "lifetime": 2.0},
	})
	flash_at(from, aim_dir())
	manager.play_sound("shield", from, -4.0)
