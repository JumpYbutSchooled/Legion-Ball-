extends "res://scripts/weapons/simple_weapon.gd"
## SEEKER DRONE (Fortress / Area Denial): a small detached blade pair hovering above-left.
## Press to launch a drone that orbits you for 10s, firing at whatever you're aiming
## nearest. It keeps fighting while you switch weapons.


func _build() -> void:
	cooldown = 14.0
	crosshair_shape = "ring"
	var shape := {"arc_radius": 0.3, "tip": Vector3(0.9, 1.5, -0.4), "max_width": 0.16, "max_thickness": 0.12, "segments": 5}
	add_blade(-1.0, 20.0, shape)
	add_blade(-1.0, -20.0, shape)


func _fire(_pressed: bool, just: bool, _released: bool, _hit: Dictionary, _delta: float) -> void:
	if not just or not can_fire():
		return
	start_cooldown()
	for i in _blades.size():
		kick(i)
	spawn("res://scripts/weapons/seeker_drone_node.gd", {
		"position": ball().global_position + Vector3.UP * 2.0, "color": color,
		"lifetime": deploy_time(10.0),
	})
	manager.play_sound("equip", ball().global_position, 0.0)
