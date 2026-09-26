extends "res://scripts/weapons/simple_weapon.gd"
## CRYSTAL SABER (Brawler / Close Quarters): one curved sword blade low on the right,
## sweeping forward. Press to swing: cuts everything in a wide arc in front (5.5m), and
## for the moment of the swing any shot that hits you is DEFLECTED back at the shooter
## (a parry that doesn't throw you around).

@export var damage := 5.0


func _build() -> void:
	cooldown = 1.0
	crosshair_shape = "chevron"
	crosshair_radius = 16.0
	add_blade(1.0, -35.0, {"arc_radius": 1.3, "tip": Vector3(0.9, -0.3, -2.8), "max_width": 0.32, "max_thickness": 0.12, "segments": 12})


func _fire(_pressed: bool, just: bool, _released: bool, _hit: Dictionary, _delta: float) -> void:
	if not just or not can_fire():
		return
	start_cooldown()
	kick(0)
	var b := ball()
	var center := b.global_position
	var fwd := aim_dir()
	# The deflect: the host treats us as shielded for the swing; the ball skips the
	# parry launch while deflect_timer runs.
	b.set("deflect_timer", 0.25)
	var arena := get_tree().current_scene
	if arena and arena.has_method("request_block"):
		arena.call("request_block", 0.2)
	for t in targets_near(center, 8.0):
		var p: Vector3 = t.call("get_aim_point")
		if (p - center).normalized().dot(fwd) > 0.1:
			manager.hit_object(t, damage, p, fwd, 18.0)
	for i in 7:
		var a := lerpf(-1.2, 1.2, i / 6.0)
		var d := fwd.rotated(Vector3.UP, a)
		manager.spawn_beam(center + d * 1.5, d, 5.5, 0.4, 0.1, 14.0, color)
	manager.play_sound("unequip", center, 0.0)
	manager.shake(0.25)
