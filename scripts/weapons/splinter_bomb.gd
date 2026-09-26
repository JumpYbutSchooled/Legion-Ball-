extends "res://scripts/weapons/simple_weapon.gd"
## SPLINTER BOMB (Hunter / Mark): three short spikes fanned out on the left. Throws a
## crystal shard that sticks to whatever it hits (a player, a wall) and bursts 2s later.
## Marked targets take the usual 1.5x, so mark first.


func _build() -> void:
	cooldown = 2.5
	lock_on = true
	crosshair_shape = "diamond"
	var shape := {"arc_radius": 0.45, "tip": Vector3(0.3, 0.0, -1.2), "max_width": 0.18, "max_thickness": 0.16, "segments": 5}
	for roll in [30.0, 0.0, -30.0]:
		add_blade(-1.0, roll, shape)


func _fire(_pressed: bool, just: bool, _released: bool, _hit: Dictionary, _delta: float) -> void:
	if not just or not can_fire():
		return
	start_cooldown()
	for i in _blades.size():
		kick(i)
	var from := ball().global_position + aim_dir() * 1.4
	spawn("res://scripts/weapons/crystal_shot.gd", {
		"position": from, "velocity": aim_dir() * 110.0, "target_path": lock_path(), "turn_rate": 3.0, "gravity": 6.0, "damage": 1.0,
		"impulse": 1.0, "lifetime": 3.0, "size": 0.22, "color": color, "stick": true, "fuse": 2.0,
		"explosion": {"radius": 8.0, "damage": 6.0, "force": 25.0, "spark_count": 180,
			"chunk_count": 20, "light_energy": 160.0, "warp_strength": 0.25, "sound": "boom"},
	})
	flash_at(from, aim_dir(), 0.7)
	manager.play_sound("missile", from, -6.0)
