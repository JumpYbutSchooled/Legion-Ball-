extends "res://scripts/weapons/simple_weapon.gd"
## HUNTER'S SIGIL (Hunter / Mark): a single blade standing straight up like an antenna.
## Press to tag the target nearest the crosshair, at any range, walls or not: you see a
## sigil and a beam of light over them through walls for 6s (only you), and they're
## MARKED for 3s (1.5x damage from everything).

const SigilMark := preload("res://scripts/weapons/sigil_mark.gd")

var lock_target: Node3D = null
var lock_screen := Vector2.ZERO


func _build() -> void:
	cooldown = 4.0
	crosshair_shape = "cross"
	crosshair_radius = 14.0
	add_blade(1.0, 0.0, {"arc_radius": 0.3, "tip": Vector3(0.0, 2.6, 0.2), "max_width": 0.1, "max_thickness": 0.08, "segments": 9})


func _crosshair_extra(info: Dictionary) -> void:
	if lock_target and is_instance_valid(lock_target):
		info["locked"] = true
		info["lock_pos"] = lock_screen


func _fire(_pressed: bool, just: bool, _released: bool, _hit: Dictionary, _delta: float) -> void:
	lock_target = null
	var found: Array = manager.targets_on_screen(140.0)
	if not found.is_empty():
		lock_target = found[0]["target"]
		lock_screen = found[0]["screen"]
	if not just or not can_fire() or not lock_target:
		return
	start_cooldown()
	kick(0)
	var p: Vector3 = lock_target.call("get_aim_point")
	var mark := SigilMark.new()
	mark.color = color
	lock_target.add_child(mark)
	if lock_target.has_method("mark"):
		lock_target.call("mark", 3.0)
	manager.spawn_beam(tip(), (p - tip()).normalized(), tip().distance_to(p), 0.05, 0.15, 6.0, color)
	manager.spawn_light(p, 30.0, 6.0, 0.2, color)
	manager.play_sound("tether", tip(), -6.0)
