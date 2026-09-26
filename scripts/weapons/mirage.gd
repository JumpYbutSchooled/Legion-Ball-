extends "res://scripts/weapons/simple_weapon.gd"
## MIRAGE (Brawler / Close Quarters): two ghostly blades trailing behind at angles.
## Press: two decoy balls in your colour peel off to either side and roll away for 5s.
## They're lock targets for everyone, so locks, missiles and aim assist can jump to them.


func _build() -> void:
	cooldown = 12.0
	crosshair_shape = "diamond"
	add_blade(1.0, 25.0, {"arc_radius": 0.6, "tip": Vector3(1.0, 0.4, 1.9), "max_width": 0.2, "max_thickness": 0.06, "segments": 7})
	add_blade(-1.0, 25.0, {"arc_radius": 0.6, "tip": Vector3(1.0, 0.4, 1.9), "max_width": 0.2, "max_thickness": 0.06, "segments": 7})


func _update(_delta: float) -> void:
	# Faint and flickering, like a heat haze.
	_set_param("charge_glow", 0.6 + 0.4 * sin(Time.get_ticks_msec() / 90.0))


func _fire(_pressed: bool, just: bool, _released: bool, _hit: Dictionary, _delta: float) -> void:
	if not just or not can_fire():
		return
	start_cooldown()
	var b := ball()
	var flat := Vector3(aim_dir().x, 0.0, aim_dir().z).normalized()
	var net := get_tree().root.get_node_or_null("Net")
	var tint: Color = net.call("player_color", manager.get_multiplayer_authority()) if net else color
	for side in [-1.0, 1.0]:
		var dir := flat.rotated(Vector3.UP, side * 0.6)
		spawn("res://scripts/weapons/decoy.gd", {
			"position": b.global_position + dir * 1.5, "direction": dir, "speed": 40.0,
			"lifetime": 7.0, "tint": tint,
		})
	for i in _blades.size():
		kick(i)
	manager.spawn_warp(b.global_position, 0.25, 3.0)
	manager.play_sound("unshatter", b.global_position, -2.0)
