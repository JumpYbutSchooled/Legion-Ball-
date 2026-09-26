extends "res://scripts/weapons/simple_weapon.gd"
## CRYSTAL WALL (Fortress / Area Denial): a flat slab of five blades side by side in
## front. Press to raise an 11m crystal wall 6m ahead, facing you: solid cover against
## shots and players for 5s.


func _build() -> void:
	cooldown = 8.0
	crosshair_shape = "cross"
	crosshair_radius = 14.0
	for x in [-0.9, -0.45, 0.0, 0.45, 0.9]:
		var side := 1.0 if x >= 0.0 else -1.0
		add_blade(side, 0.0, {"arc_radius": 0.25, "tip": Vector3(absf(x), -0.1, -1.9), "max_width": 0.22, "max_thickness": 0.08, "segments": 5})


func _fire(_pressed: bool, just: bool, _released: bool, _hit: Dictionary, _delta: float) -> void:
	if not just or not can_fire():
		return
	var dir := aim_dir()
	var flat := Vector3(dir.x, 0.0, dir.z).normalized()
	var spot := ball().global_position + flat * 6.0
	var ground: Dictionary = manager.raycast(spot + Vector3.UP * 3.0, spot + Vector3.DOWN * 20.0)
	if ground.is_empty():
		return  # Nothing to stand it on.
	start_cooldown()
	for i in _blades.size():
		kick(i)
	spawn("res://scripts/weapons/crystal_wall_node.gd", {
		"position": ground["position"] + Vector3.UP * 3.0, "facing": -flat, "color": color,
		"lifetime": deploy_time(5.0),
	})
	manager.shake(0.3)
