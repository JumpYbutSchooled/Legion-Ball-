extends "res://scripts/weapons/simple_weapon.gd"
## SKYLANCE (Skyborne / Mobility): one spear on top pointing straight forward. Hold to
## throw it and ride it: it carries you along behind it, running through anyone in its
## way. Let go to drop off (you keep the speed); it snaps after 1.6s or at a wall.

var _spear: Node3D = null


func _build() -> void:
	cooldown = 3.0
	crosshair_shape = "diamond"
	add_blade(-1.0, 90.0, {"arc_radius": 0.3, "tip": Vector3(0.0, 0.9, -4.2), "max_width": 0.3, "max_thickness": 0.3, "segments": 8})


func _fire(pressed: bool, just: bool, released: bool, _hit: Dictionary, _delta: float) -> void:
	if _spear and not is_instance_valid(_spear):
		_spear = null
	if released and _spear:
		_spear.set("carry", false)
		_spear = null
	if not just or not can_fire():
		return
	start_cooldown()
	kick(0)
	var dir := aim_dir()
	_spear = spawn("res://scripts/weapons/crystal_shot.gd", {
		"position": ball().global_position + dir * 2.0 + Vector3.UP * 0.6, "velocity": dir * 55.0,
		"damage": 6.0, "impulse": 25.0, "pierce": true, "carry": pressed, "lifetime": 1.6,
		"size": 0.35, "color": color,
	})
	manager.play_sound("tether", ball().global_position, -2.0)
	manager.shake(0.4)
