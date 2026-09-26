extends "res://scripts/weapons/simple_weapon.gd"
## SHARD MORTAR (Fortress / Area Denial): a short upright tube of four blades angled
## skyward. Lobs a heavy shell in a high arc toward the crosshair; it bursts on impact
## and throws out five bomblets that each go off where they land.


func _build() -> void:
	cooldown = 1.6
	crosshair_shape = "dot"
	var shape := {"arc_radius": 0.35, "tip": Vector3(0.35, 1.9, -0.5), "max_width": 0.2, "max_thickness": 0.18, "segments": 6}
	for roll in [25.0, -25.0]:
		for side in [1.0, -1.0]:
			add_blade(side, roll, shape)


func _fire(_pressed: bool, just: bool, _released: bool, _hit: Dictionary, _delta: float) -> void:
	if not just or not can_fire():
		return
	start_cooldown()
	for i in _blades.size():
		kick(i)
	var from := ball().global_position + Vector3.UP * 2.0
	var to: Vector3 = manager.aim_point
	var flat := Vector3(to.x - from.x, 0.0, to.z - from.z)
	var gravity := 25.0
	# Aim the arc at the crosshair: about a second and a half of flight, less up close.
	var t := clampf(flat.length() / 40.0, 0.6, 1.8)
	var v := flat / t
	v.y = (to.y - from.y) / t + 0.5 * gravity * t
	var bomblet := {"gravity": gravity, "damage": 0.0, "lifetime": 3.0, "size": 0.15, "color": color,
		"explosion": {"radius": 3.5, "damage": 2.0, "force": 12.0, "spark_count": 50, "light_energy": 50.0, "sound": "boom"}}
	spawn("res://scripts/weapons/crystal_shot.gd", {
		"position": from, "velocity": v, "gravity": gravity, "damage": 2.0, "impulse": 4.0,
		"lifetime": 4.0, "size": 0.4, "color": color, "split": 5, "split_props": bomblet,
		"explosion": {"radius": 5.0, "damage": 4.0, "force": 22.0, "spark_count": 150,
			"chunk_count": 16, "light_energy": 150.0, "warp_strength": 0.25, "sound": "boom"},
	})
	flash_at(from, v.normalized(), 1.0)
	manager.play_sound("shotgun", from, -2.0)
	manager.shake(0.4)
