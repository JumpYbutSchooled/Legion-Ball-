extends "res://scripts/weapons/simple_weapon.gd"
## SPIKE CARPET (Fortress / Area Denial): a row of small teeth along the bottom. Press to
## lay a 20m line of crystal spikes along the ground ahead of you for 6s; anyone rolling
## over it is cut and slowed.


func _build() -> void:
	cooldown = 7.0
	crosshair_shape = "chevron"
	for x in [0.2, 0.6]:
		for side in [1.0, -1.0]:
			add_blade(side, 0.0, {"arc_radius": 0.3, "tip": Vector3(x, -0.95, -0.9), "max_width": 0.14, "max_thickness": 0.12, "segments": 4})


func _fire(_pressed: bool, just: bool, _released: bool, _hit: Dictionary, _delta: float) -> void:
	if not just or not can_fire():
		return
	var b := ball()
	var dir := aim_dir()
	var flat := Vector3(dir.x, 0.0, dir.z).normalized()
	var start: Dictionary = manager.raycast(b.global_position + flat * 2.0, b.global_position + flat * 2.0 + Vector3.DOWN * 20.0)
	if start.is_empty():
		return
	start_cooldown()
	for i in _blades.size():
		kick(i)
	var from: Vector3 = start["position"]
	# Run along the ground; stop at a wall (players in the way don't count: that's the point).
	var to := from + flat * 40.0
	var skip: Array[RID] = [b.get_rid()]
	for i in 6:
		var query := PhysicsRayQueryParameters3D.create(from + Vector3.UP * 0.5, to + Vector3.UP * 0.5)
		query.exclude = skip
		var wall := get_world_3d().direct_space_state.intersect_ray(query)
		if wall.is_empty():
			break
		if (wall["collider"] as Object).has_method("take_hit"):
			skip.append(wall["rid"])
			continue
		to = wall["position"] - flat * 0.5 + Vector3.DOWN * 0.5
		break
	spawn("res://scripts/weapons/spike_carpet_node.gd", {
		"position": from, "end_point": to, "color": color, "lifetime": deploy_time(6.0),
	})
	manager.play_sound("shatter", from, -4.0)
