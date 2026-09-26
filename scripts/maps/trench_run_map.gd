extends "res://scripts/maps/map_builder.gd"
## "Trench Run": the surface of a battle station out in space. A vast grey plate covered
## in panel lines and machinery blocks, split down the middle by THE trench: 700 m long,
## 36 wide and 32 deep, its walls crusted with pipes and vents, with catwalks spanning it
## here and there. The exhaust port waits at the far end. Gun towers stand on the
## surface either side. Nothing out past the edge but stars: fall off and you're gone.

const SEED := 1977
const HALF_X := 200.0
const HALF_Z := 400.0
const TRENCH_W := 36.0
const TRENCH_D := 32.0
const PLATE := 6.0

var _hull := panel(Color(0.42, 0.44, 0.47), Color(0.3, 0.32, 0.35), 6.0)
var _hull_dark := panel(Color(0.3, 0.32, 0.35), Color(0.22, 0.24, 0.27), 4.0)
var _greeble := panel(Color(0.5, 0.52, 0.55), Color(0.35, 0.37, 0.4), 2.0)
var _light_blue := glow(Color(0.5, 0.75, 1.0), 3.0)
var _light_red := glow(Color(1.0, 0.25, 0.2), 4.0)
var _star := glow(Color(1.0, 1.0, 1.0), 6.0)


func _build() -> void:
	_rng.seed = SEED
	_ceiling = 110.0
	# The trench floor is 32 m down: only below it do you count as fallen off.
	_fall = -TRENCH_D - 25.0
	_outline = rect_outline(Rect2(-HALF_X, -HALF_Z, HALF_X * 2.0, HALF_Z * 2.0))
	_surface()
	_trench()
	_towers()
	_stars()
	for i in 8:
		var z := lerpf(-300.0, 300.0, (i / 2) / 3.0)
		var x := (70.0 + _rng.randf_range(0.0, 60.0)) * (1.0 if i % 2 == 0 else -1.0)
		_spawns.append(Vector3(x, 1.0, z))
	for p in [Vector2(-60, -200), Vector2(60, 0), Vector2(-60, 200), Vector2(60, -350)]:
		_turrets.append(Vector3(p.x, 0.0, p.y))


## The plate either side of the trench (top at y 0), and blocks of machinery on it.
func _surface() -> void:
	var side_w := HALF_X - TRENCH_W / 2.0
	for s: float in [-1.0, 1.0]:
		var x := s * (TRENCH_W / 2.0 + side_w / 2.0)
		box(Vector3(x, -PLATE / 2.0, 0.0), Vector3(side_w, PLATE, HALF_Z * 2.0), _hull)
	# The trench walls, all the way down to its floor.
	for s: float in [-1.0, 1.0]:
		box(Vector3(s * (TRENCH_W / 2.0 + 1.0), -TRENCH_D / 2.0, 0.0), Vector3(2.0, TRENCH_D, HALF_Z * 2.0), _hull_dark)
	# The trench floor, and a lip at each end.
	box(Vector3(0.0, -TRENCH_D - PLATE / 2.0, 0.0), Vector3(TRENCH_W + 2.0, PLATE, HALF_Z * 2.0), _hull_dark)
	for s: float in [-1.0, 1.0]:
		box(Vector3(0.0, -TRENCH_D / 2.0, s * (HALF_Z - 2.0)), Vector3(TRENCH_W, TRENCH_D, 4.0), _hull_dark)
	# Machinery: low blocks, stacked blocks and long ribs.
	for i in 90:
		var s := 1.0 if _rng.randf() < 0.5 else -1.0
		var x := s * _rng.randf_range(TRENCH_W / 2.0 + 10.0, HALF_X - 10.0)
		var z := _rng.randf_range(-HALF_Z + 10.0, HALF_Z - 10.0)
		var w := _rng.randf_range(4.0, 18.0)
		var d := _rng.randf_range(4.0, 18.0)
		var h := _rng.randf_range(1.5, 8.0)
		box(Vector3(x, h / 2.0, z), Vector3(w, h, d), _greeble if _rng.randf() < 0.6 else _hull_dark)
		if _rng.randf() < 0.3:
			var h2 := _rng.randf_range(2.0, 10.0)
			box(Vector3(x, h + h2 / 2.0, z), Vector3(w * 0.5, h2, d * 0.5), _greeble)
		if _rng.randf() < 0.2:
			deco(Vector3(x, h + 0.1, z), Vector3(w * 0.7, 0.2, 0.6), _light_blue)
	# Long ribs running across the plate.
	for i in 12:
		var z := lerpf(-HALF_Z + 30.0, HALF_Z - 30.0, i / 11.0)
		for s: float in [-1.0, 1.0]:
			box(Vector3(s * (HALF_X * 0.55), 1.0, z), Vector3(HALF_X * 0.8, 2.0, 3.0), _hull_dark)


## The trench walls, lined with pipes, vents and lights, and catwalks across it.
func _trench() -> void:
	for s: float in [-1.0, 1.0]:
		var x := s * (TRENCH_W / 2.0)
		# Pipes: long horizontal runs at different heights, sticking out of the wall.
		for level in 4:
			var y := -TRENCH_D + 4.0 + level * 7.0
			box(Vector3(x - s * 1.0, y, 0.0), Vector3(2.0, 1.4, HALF_Z * 2.0 - 8.0), _greeble)
		# Blocks and vents on the walls, and lights between them.
		for i in 60:
			var z := _rng.randf_range(-HALF_Z + 8.0, HALF_Z - 8.0)
			var y := _rng.randf_range(-TRENCH_D + 2.0, -3.0)
			var depth := _rng.randf_range(1.5, 4.0)
			box(Vector3(x - s * depth / 2.0, y, z), Vector3(depth, _rng.randf_range(2.0, 6.0), _rng.randf_range(4.0, 14.0)), _hull_dark if i % 2 == 0 else _greeble)
		for i in 40:
			var z := lerpf(-HALF_Z + 12.0, HALF_Z - 12.0, i / 39.0)
			deco(Vector3(x - s * 0.3, -TRENCH_D + 1.0, z), Vector3(0.4, 0.4, 3.0), _light_blue)
	# Catwalks across the trench.
	for i in 6:
		var z := lerpf(-HALF_Z + 80.0, HALF_Z - 120.0, i / 5.0)
		var y := -_rng.randf_range(8.0, 20.0)
		box(Vector3(0.0, y, z), Vector3(TRENCH_W + 2.0, 1.2, 5.0), _hull)
	# The exhaust port: a square hole with a glowing ring, at the end of the trench.
	var z := HALF_Z - 30.0
	for s: float in [-1.0, 1.0]:
		box(Vector3(s * 4.0, -TRENCH_D + 0.8, z), Vector3(2.0, 1.6, 10.0), _hull)
		box(Vector3(0.0, -TRENCH_D + 0.8, z + s * 4.0), Vector3(10.0, 1.6, 2.0), _hull)
	deco(Vector3(0.0, -TRENCH_D + 0.05, z), Vector3(6.0, 0.1, 6.0), glow(Color(1.0, 0.5, 0.15), 5.0))
	var light := OmniLight3D.new()
	light.position = Vector3(0.0, -TRENCH_D + 4.0, z)
	light.light_color = Color(1.0, 0.55, 0.2)
	light.light_energy = 3.0
	light.omni_range = 40.0
	add_child(light)
	# A few lights down the trench so it isn't pitch black.
	for i in 8:
		var l := OmniLight3D.new()
		l.position = Vector3(0.0, -8.0, lerpf(-HALF_Z + 40.0, HALF_Z - 40.0, i / 7.0))
		l.light_color = Color(0.6, 0.75, 1.0)
		l.light_energy = 1.2
		l.omni_range = 70.0
		add_child(l)


## Gun towers on the surface: a stepped base, a tall shaft and a turret head.
func _towers() -> void:
	for i in 8:
		var s := 1.0 if i % 2 == 0 else -1.0
		var p := Vector2(s * _rng.randf_range(50.0, 150.0), lerpf(-HALF_Z + 60.0, HALF_Z - 60.0, i / 7.0))
		box(Vector3(p.x, 3.0, p.y), Vector3(18.0, 6.0, 18.0), _hull_dark)
		pillar(p, 6.0, 8.0, 24.0, _greeble)
		box(Vector3(p.x, 32.0, p.y), Vector3(12.0, 5.0, 12.0), _hull_dark)
		deco(Vector3(p.x, 34.6, p.y), Vector3(2.0, 0.4, 2.0), _light_red)
		# A ramp up to the base so it can be climbed.
		ramp(Vector3(p.x, 0.0, p.y + 24.0), Vector3(p.x, 6.0, p.y + 9.0), 6.0, _hull)


## Stars: tiny glowing specks far out in every direction (below the plate too).
func _stars() -> void:
	for i in 260:
		var dir := Vector3(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0)).normalized()
		var p := dir * _rng.randf_range(900.0, 1200.0)
		var size := _rng.randf_range(1.5, 4.0)
		deco(p, Vector3(size, size, size), _star)
