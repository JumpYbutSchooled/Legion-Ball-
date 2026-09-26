extends "res://scripts/weapons/simple_weapon.gd"
## TIME DILATOR (Frost / Control): six tiny blades orbiting in a halo above the ball.
## Press to spread a 12m bubble round you for 4s: everyone else inside is slowed, and
## their shots crawl through it at half speed. Yours don't.

var _spin := 0.0


func _build() -> void:
	cooldown = 10.0
	crosshair_shape = "ring"
	crosshair_radius = 14.0
	var shape := {"arc_radius": 0.3, "tip": Vector3(0.5, 1.0, -0.2), "max_width": 0.1, "max_thickness": 0.08, "segments": 5}
	for roll in [-40.0, 0.0, 40.0]:
		for side in [1.0, -1.0]:
			add_blade(side, roll, shape)


func _update(delta: float) -> void:
	# The halo turns, faster while the bubble is up.
	_spin += delta * (6.0 if _cooldown > cooldown - 4.0 else 1.5)
	for i in _blades.size():
		_blades[i].rotation.z = _spin + TAU * i / _blades.size()


func _fire(_pressed: bool, just: bool, _released: bool, _hit: Dictionary, _delta: float) -> void:
	if not just or not can_fire():
		return
	start_cooldown()
	spawn("res://scripts/weapons/time_field.gd", {
		"position": ball().global_position, "color": color, "radius": 25.0, "lifetime": 4.0,
		"owner_peer": manager.get_multiplayer_authority(),
	})
	manager.spawn_warp(ball().global_position, 0.3, 25.0)
	manager.play_sound("infinity", ball().global_position, -2.0)
	manager.shake(0.3)
