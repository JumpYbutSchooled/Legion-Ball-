extends "res://scripts/weapons/simple_weapon.gd"
## ARC PYLON (Fortress / Area Denial): two tall forks, one each side, pointing up.
## Press to plant a pylon at your feet: for 8s it zaps whoever is nearest within 96m.
## One at a time; a new one replaces the old.

var _pylon: Node3D = null


func _build() -> void:
	cooldown = 10.0
	crosshair_shape = "cross"
	var shape := {"arc_radius": 0.4, "tip": Vector3(0.9, 2.2, 0.2), "max_width": 0.15, "max_thickness": 0.12, "segments": 8}
	for side in [1.0, -1.0]:
		add_blade(side, 0.0, shape)


## Our pylon was parried (arena.gd): it shatters.
func break_pylon() -> void:
	if not _pylon or not is_instance_valid(_pylon):
		return
	var at := _pylon.global_position + Vector3.UP * 1.3
	manager.spawn_explosion({"position": at, "color": color, "radius": 2.5, "damage": 0.0, "force": 0.0,
		"spark_count": 80, "chunk_count": 14, "light_energy": 60.0, "warp_strength": 0.15, "sound": "zap"})
	manager.despawn_node(_pylon)
	_pylon = null


func _fire(_pressed: bool, just: bool, _released: bool, _hit: Dictionary, _delta: float) -> void:
	if not just or not can_fire():
		return
	var b := ball()
	var ground: Dictionary = manager.raycast(b.global_position, b.global_position + Vector3.DOWN * 30.0)
	if ground.is_empty():
		return
	start_cooldown()
	if _pylon and is_instance_valid(_pylon):
		manager.despawn_node(_pylon)
	for i in _blades.size():
		kick(i)
	_pylon = spawn("res://scripts/weapons/arc_pylon_node.gd", {
		"position": ground["position"], "color": color, "lifetime": deploy_time(8.0),
	})
	manager.play_sound("zap", ground["position"], 0.0)
