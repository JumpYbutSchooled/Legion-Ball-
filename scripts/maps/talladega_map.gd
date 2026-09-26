extends "res://scripts/maps/speedway_map.gd"
## "Talladega": the biggest, fastest oval there is. Longer straights, wider turns and
## steeper 33-degree banking than Daytona. "The Big One" has just happened on the back
## stretch: a pile of wrecked cars strewn across the track (cover, and ramps if you hit
## them right). The infield is packed with campers, and a flag-stand gantry spans the
## front stretch high enough to fly under.

const SEED := 2023


func _setup() -> void:
	_rng.seed = SEED
	straight = 520.0
	turn_radius = 185.0
	track_width = 42.0
	turn_bank = deg_to_rad(33.0)
	stand_tiers = 11
	_asphalt = checker(Color(0.13, 0.13, 0.15), Color(0.16, 0.16, 0.18), 8.0)
	_wall = panel(Color(0.85, 0.86, 0.9), Color(0.85, 0.15, 0.15), 6.0)


func _decorate() -> void:
	# The Big One: cars spun, stacked and flipped across the back stretch.
	var colors := [Color(1.0, 0.85, 0.1), Color(0.1, 0.35, 1.0), Color(0.95, 0.1, 0.1), Color(0.1, 0.8, 0.3),
		Color(1.0, 0.45, 0.05), Color(0.9, 0.9, 0.95), Color(0.6, 0.2, 0.9), Color(0.2, 0.9, 0.9)]
	for i in 14:
		var x := _rng.randf_range(-120.0, 80.0)
		var z := -turn_radius + _rng.randf_range(-track_width / 2.0 + 5.0, track_width / 2.0 - 5.0)
		var y := 0.94 + (-(z + turn_radius)) * sin(straight_bank) * 0.5
		var flipped := _rng.randf() < 0.3
		car(Vector2(x, z), _rng.randf() * TAU, colors[i % colors.size()], y + (2.4 if flipped else 0.0), PI if flipped else _rng.randf_range(-0.15, 0.15))
	# A couple piled on top of each other against the wall.
	car(Vector2(-20.0, -turn_radius - track_width / 2.0 + 6.0), 0.4, colors[2], 1.5, 0.3)
	car(Vector2(-18.0, -turn_radius - track_width / 2.0 + 7.0), 1.2, colors[0], 4.2, -0.2)
	# Flag stand: a gantry over the front stretch.
	var z := turn_radius
	for side: float in [-1.0, 1.0]:
		pillar(Vector2(40.0, z + side * (track_width / 2.0 + 3.0)), 0.0, 2.5, 26.0, _stand)
	box(Vector3(40.0, 27.0, z), Vector3(6.0, 3.0, track_width + 10.0), panel(Color(0.15, 0.16, 0.2), Color(1.0, 1.0, 1.0), 2.0, 1.0), 0.0, 0.0, false)
	# Infield campers, in rows.
	for row in 3:
		for i in 9:
			var x := lerpf(-straight * 0.4, straight * 0.4, i / 8.0) + _rng.randf_range(-6.0, 6.0)
			var cz := -60.0 + row * 45.0
			var tint := Color.from_hsv(_rng.randf(), 0.25, 0.9)
			box(Vector3(x, 2.5, cz), Vector3(8.0, 5.0, 18.0), solid(tint), _rng.randf_range(-0.2, 0.2))
	for i in 8:
		var a := TAU * i / 8.0
		light_tower(Vector2(cos(a) * (straight / 2.0 + 20.0), sin(a) * (turn_radius - track_width / 2.0 - 70.0)), 50.0)
	for p in [Vector2(-180, -30), Vector2(180, -30), Vector2(-60, 75), Vector2(60, 75)]:
		_turrets.append(Vector3(p.x, 0.0, p.y))
