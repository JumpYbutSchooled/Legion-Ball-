extends "res://scripts/weapons/simple_weapon.gd"
## PLASMA NET (Fortress / Area Denial): two long blades spread wide like the arms of a
## net-gun. Fires a huge net woven of hexagons that stops about 50 m in front of you (or
## at the first wall) and hangs there in mid-air. Any foe that touches it is STUNNED for
## 4 s (once per net). The net lasts 20 s; firing again replaces it.

var _net_node: Node3D = null


func _build() -> void:
	cooldown = 12.0
	crosshair_shape = "ring"
	crosshair_radius = 16.0
	var arm := {"arc_radius": 0.45, "tip": Vector3(1.4, 0.5, -1.6), "max_width": 0.16, "max_thickness": 0.12, "segments": 8}
	for side in [1.0, -1.0]:
		add_blade(side, 0.0, arm)


func _fire(_pressed: bool, just: bool, _released: bool, _hit: Dictionary, _delta: float) -> void:
	if not just or not can_fire():
		return
	start_cooldown()
	for i in _blades.size():
		kick(i)
	var from := ball().global_position
	var dir := look_dir()
	var reach := 50.0
	var wall: Dictionary = manager.raycast(from, from + dir * reach)
	if not wall.is_empty():
		reach = maxf(from.distance_to(wall["position"]) - 1.5, 4.0)
	var pos := from + dir * reach
	if _net_node and is_instance_valid(_net_node):
		manager.despawn_node(_net_node)
	_net_node = spawn("res://scripts/weapons/plasma_net_node.gd", {
		"position": pos, "facing": -dir, "color": color, "lifetime": deploy_time(20.0),
	})
	manager.spawn_beam(from, dir, reach, 0.15, 0.25, 10.0, color)
	flash_at(tip(0), dir, 1.2)
	manager.play_sound("zap", from, -2.0)
