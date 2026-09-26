extends "res://scripts/weapons/simple_weapon.gd"
## STASIS MINE (Frost / Control): two stubby blades pointing down at the floor. Throw a
## mine; it sticks where it lands and arms. Anyone else who rolls near it sets it off:
## a blast that STAGGERS everyone in it. Two out at once; a third replaces the oldest.

var _mines: Array = []


func _build() -> void:
	cooldown = 1.5
	crosshair_shape = "chevron"
	var shape := {"arc_radius": 0.4, "tip": Vector3(0.25, -1.2, -0.4), "max_width": 0.28, "max_thickness": 0.24, "segments": 5}
	for side in [1.0, -1.0]:
		add_blade(side, 0.0, shape)


func _crosshair_extra(info: Dictionary) -> void:
	_prune()
	info["count"] = "%d/2" % _mines.size()


func _prune() -> void:
	_mines = _mines.filter(func(m) -> bool: return is_instance_valid(m))


func _fire(_pressed: bool, just: bool, _released: bool, _hit: Dictionary, _delta: float) -> void:
	if not just or not can_fire():
		return
	start_cooldown()
	_prune()
	if _mines.size() >= 2:
		manager.despawn_node(_mines.pop_front())
	for i in _blades.size():
		kick(i)
	var from := ball().global_position + aim_dir() * 1.2
	# Lobbed: the mine is left where the shot comes down.
	var shot := spawn("res://scripts/weapons/crystal_shot.gd", {
		"position": from, "velocity": aim_dir() * 45.0 + Vector3.UP * 8.0, "gravity": 22.0,
		"damage": 0.0, "impulse": 0.0, "lifetime": 3.0, "size": 0.25, "color": color,
	})
	# Place the mine where it lands: the shot tells us by where it ends up.
	if shot:
		shot.tree_exiting.connect(_place.bind(shot))
	manager.play_sound("equip", from, -8.0)


func _place(shot: Node3D) -> void:
	# The shot is leaving the tree, which is busy: add the mine a moment later.
	_spawn_mine.call_deferred(shot.global_position)


func _spawn_mine(pos: Vector3) -> void:
	if not is_inside_tree():
		return
	var mine := spawn("res://scripts/weapons/stasis_mine_node.gd", {"position": pos, "color": color})
	if mine:
		_mines.append(mine)
