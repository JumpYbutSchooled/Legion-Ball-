extends "res://scripts/weapons/simple_weapon.gd"
## BLINK EDGE (Skyborne / Mobility): two thin blades swept back along the sides. Press
## to teleport up to 15m where you're looking (stopping short of walls), keeping your
## speed, and leave a slash along the way that cuts everyone on the line.

@export var distance := 15.0
@export var damage := 5.0


func _build() -> void:
	cooldown = 2.0
	crosshair_shape = "chevron"
	var shape := {"arc_radius": 0.6, "tip": Vector3(0.7, 0.1, 2.4), "max_width": 0.12, "max_thickness": 0.1, "segments": 9}
	for side in [1.0, -1.0]:
		add_blade(side, 0.0, shape)


func _fire(_pressed: bool, just: bool, _released: bool, _hit: Dictionary, _delta: float) -> void:
	if not just or not can_fire():
		return
	start_cooldown()
	var b := ball()
	var from := b.global_position
	var dir := look_dir()
	var wall: Dictionary = manager.raycast(from, from + dir * distance)
	var to: Vector3 = from + dir * distance
	if not wall.is_empty() and not (wall["collider"] as Object).has_method("take_hit"):
		to = wall["position"] - dir * 1.0
	# Cut everyone along the line.
	for t in targets_near((from + to) * 0.5, from.distance_to(to) * 0.5 + 2.0):
		var p: Vector3 = t.call("get_aim_point")
		if p.distance_to(Geometry3D.get_closest_point_to_segment(p, from, to)) <= 2.0:
			manager.hit_object(t, damage, p, dir, 12.0)
	manager.spawn_beam(from, dir, from.distance_to(to), 0.35, 0.25, 16.0, color)
	manager.spawn_warp(from, 0.2, 2.5)
	manager.spawn_warp(to, 0.2, 2.5)
	var speed := b.linear_velocity.length()
	b.call("teleport", to)
	# Keep going, in the new direction.
	manager.push_ball(dir * maxf(speed, 20.0))
	manager.play_sound("dash", to, 0.0)
	for i in _blades.size():
		kick(i)
