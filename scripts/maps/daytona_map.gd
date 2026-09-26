extends "res://scripts/maps/speedway_map.gd"
## "Daytona 500": the World Center of Racing. A 31-degree banked superspeedway round an
## infield with Lake Lloyd in the middle, pit road and its garages down the front
## stretch, a scoring pylon, and light towers. A pack of stock cars is lined up on the
## front stretch for the start, two by two.

const SEED := 500


func _setup() -> void:
	_rng.seed = SEED
	straight = 380.0
	turn_radius = 150.0
	track_width = 36.0
	turn_bank = deg_to_rad(31.0)


func _decorate() -> void:
	# Lake Lloyd: a sunken pool in the back half of the infield with a sandy rim.
	var water := glow(Color(0.1, 0.45, 0.8), 0.6)
	box(Vector3(20.0, -1.4, -40.0), Vector3(200.0, 1.0, 90.0), water)
	for side: float in [-1.0, 1.0]:
		box(Vector3(20.0, 0.2, -40.0 + side * 47.0), Vector3(204.0, 1.2, 4.0), solid(Color(0.8, 0.72, 0.5)))
	for side: float in [-1.0, 1.0]:
		box(Vector3(20.0 + side * 102.0, 0.2, -40.0), Vector3(4.0, 1.2, 94.0), solid(Color(0.8, 0.72, 0.5)))
	# Pit road: a lane inside the front stretch with the pit wall, and garages behind.
	var pit_z := turn_radius - track_width / 2.0 - 22.0
	box(Vector3(0.0, 0.05, pit_z), Vector3(straight * 0.8, 0.3, 16.0), _apron)
	box(Vector3(0.0, 1.0, pit_z + 9.0), Vector3(straight * 0.8, 2.0, 1.0), _wall)
	for i in 6:
		var x := lerpf(-straight * 0.32, straight * 0.32, i / 5.0)
		box(Vector3(x, 5.0, pit_z - 26.0), Vector3(40.0, 10.0, 18.0), panel(Color(0.7, 0.72, 0.76), Color(0.9, 0.2, 0.2), 4.0))
	# Scoring pylon: a tall lit tower near the start line.
	pillar(Vector2(-30.0, pit_z - 50.0), 0.0, 6.0, 46.0, panel(Color(0.12, 0.13, 0.16), Color(1.0, 0.75, 0.2), 2.0, 1.4, 0.5))
	# The field on the front stretch, two by two, in racing colours.
	var colors := [Color(1.0, 0.85, 0.1), Color(0.1, 0.35, 1.0), Color(0.95, 0.1, 0.1), Color(0.1, 0.8, 0.3),
		Color(1.0, 0.45, 0.05), Color(0.9, 0.9, 0.95), Color(0.6, 0.2, 0.9), Color(0.05, 0.05, 0.06)]
	for i in 8:
		var row := i / 2
		var lane := -1.0 if i % 2 == 0 else 1.0
		car(Vector2(-60.0 - row * 18.0, turn_radius + lane * 7.0), PI / 2.0, colors[i], 0.94 + lane * 7.0 * sin(straight_bank))
	for i in 6:
		var a := TAU * i / 6.0
		light_tower(Vector2(cos(a) * (straight / 2.0), sin(a) * (turn_radius - track_width / 2.0 - 60.0)), 44.0)
	# Turrets in the infield.
	for p in [Vector2(-120, -60), Vector2(120, -60), Vector2(-150, 40), Vector2(150, 40)]:
		_turrets.append(Vector3(p.x, 0.0, p.y))
