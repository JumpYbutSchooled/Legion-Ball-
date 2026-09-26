extends "res://scripts/maps/map_builder.gd"
## "Enterprise": fight on the outside of a starship in deep space. The saucer section is
## the main arena: a huge round deck stepping up in rings (low enough to jump) to the
## bridge dome on top. The neck slopes down and back from the saucer to the engineering
## hull, a long deck with the glowing deflector dish at its front. From there two pylons
## climb out to the warp nacelles: long, narrow runways with red bussard collectors at
## the front and blue warp-field strips down the sides. Fall off anywhere and it's a
## long way down.

const SEED := 1701
const SAUCER_R := 130.0
const HULL_Y := -40.0
const HULL_Z0 := 190.0
const HULL_Z1 := 380.0
const NACELLE_X := 62.0
const NACELLE_Y := -8.0
const NACELLE_Z0 := 240.0
const NACELLE_Z1 := 470.0

var _hull := panel(Color(0.78, 0.8, 0.82), Color(0.62, 0.65, 0.68), 8.0)
var _hull_dark := panel(Color(0.55, 0.58, 0.62), Color(0.45, 0.48, 0.52), 5.0)
var _windows := panel(Color(0.6, 0.63, 0.66), Color(0.5, 0.52, 0.55), 3.0, 0.0, 0.5)
var _blue := glow(Color(0.3, 0.6, 1.0), 4.0)
var _red := glow(Color(1.0, 0.2, 0.1), 5.0)
var _deflector := glow(Color(1.0, 0.6, 0.25), 4.0)
var _star := glow(Color(1.0, 1.0, 1.0), 6.0)


func _build() -> void:
	_rng.seed = SEED
	_ceiling = 80.0
	_fall = HULL_Y - 60.0
	_outline = rect_outline(Rect2(-SAUCER_R - 10.0, -SAUCER_R - 10.0, (SAUCER_R + 10.0) * 2.0, NACELLE_Z1 + SAUCER_R + 20.0))
	_saucer()
	_neck_and_hull()
	_nacelles()
	_stars()
	for i in 6:
		var p := Vector2.from_angle(TAU * i / 6.0) * 105.0
		_spawns.append(Vector3(p.x, 1.0, p.y))
	_spawns.append(Vector3(0.0, HULL_Y + 1.0, 250.0))
	_spawns.append(Vector3(0.0, HULL_Y + 1.0, 340.0))
	for i in 4:
		var p := Vector2.from_angle(TAU * i / 4.0 + PI / 4.0) * 118.0
		_turrets.append(Vector3(p.x, 0.0, p.y))


## The saucer: rings stepping up 3 m at a time to the bridge, with a ramp up each step.
func _saucer() -> void:
	disc(Vector3(0, 0, 0), SAUCER_R, 6.0, _hull, 6)
	disc(Vector3(0, 3, 0), 88.0, 3.0, _windows, 4)
	disc(Vector3(0, 6, 0), 46.0, 3.0, _hull_dark, 3)
	# The bridge: a small raised deck and a dome block.
	disc(Vector3(0, 9, 0), 16.0, 3.0, _hull, 2)
	box(Vector3(0, 11.5, 0), Vector3(12.0, 5.0, 12.0), _windows)
	deco(Vector3(0, 14.2, 0), Vector3(4.0, 0.6, 4.0), _blue)
	for k in 4:
		var a := TAU * k / 4.0 + PI / 4.0
		var d := Vector2.from_angle(a)
		ramp(Vector3(d.x * 100.0, 0.0, d.y * 100.0), Vector3(d.x * 86.0, 3.0, d.y * 86.0), 10.0, _hull_dark)
		ramp(Vector3(d.x * 58.0, 3.0, d.y * 58.0), Vector3(d.x * 44.0, 6.0, d.y * 44.0), 8.0, _hull_dark)
	# Running lights round the rim, and blue lights in the grooves between the rings.
	for i in 24:
		var a := TAU * i / 24.0
		var p := Vector2.from_angle(a) * (SAUCER_R - 1.0)
		deco(Vector3(p.x, 0.3, p.y), Vector3(1.0, 0.6, 1.0), _red if i % 6 == 0 else _blue)
	var light := OmniLight3D.new()
	light.position = Vector3(0, 40.0, 0)
	light.light_color = Color(0.75, 0.85, 1.0)
	light.light_energy = 1.2
	light.omni_range = 220.0
	add_child(light)


## The neck slopes from the back of the saucer down to the engineering hull.
func _neck_and_hull() -> void:
	ramp(Vector3(0.0, HULL_Y, HULL_Z0 + 6.0), Vector3(0.0, 0.0, SAUCER_R - 12.0), 18.0, _hull_dark)
	var length := HULL_Z1 - HULL_Z0
	box(Vector3(0.0, HULL_Y - 12.0, (HULL_Z0 + HULL_Z1) / 2.0), Vector3(32.0, 24.0, length), _hull)
	# Shuttle bay doors at the back, the deflector dish at the front.
	box(Vector3(0.0, HULL_Y - 10.0, HULL_Z1 + 1.0), Vector3(20.0, 14.0, 2.0), _hull_dark)
	deco(Vector3(0.0, HULL_Y - 14.0, HULL_Z0 - 0.6), Vector3(18.0, 14.0, 1.0), _deflector)
	var glow_light := OmniLight3D.new()
	glow_light.position = Vector3(0.0, HULL_Y - 14.0, HULL_Z0 - 8.0)
	glow_light.light_color = Color(1.0, 0.6, 0.3)
	glow_light.light_energy = 3.0
	glow_light.omni_range = 60.0
	add_child(glow_light)
	# Low bumps along the hull's top for cover.
	for i in 5:
		var z := lerpf(HULL_Z0 + 25.0, HULL_Z1 - 25.0, i / 4.0)
		box(Vector3(_rng.randf_range(-8.0, 8.0), HULL_Y + 1.5, z), Vector3(8.0, 3.0, 10.0), _hull_dark)


## Two pylons from the hull up to the nacelles, which run far back past it.
func _nacelles() -> void:
	for s: float in [-1.0, 1.0]:
		var x := s * NACELLE_X
		# Pylon: a ramp from the hull's top edge up and out to the nacelle's side.
		ramp(Vector3(s * 14.0, HULL_Y, 330.0), Vector3(x - s * 7.0, NACELLE_Y, 330.0), 12.0, _hull_dark)
		var length := NACELLE_Z1 - NACELLE_Z0
		box(Vector3(x, NACELLE_Y - 7.0, (NACELLE_Z0 + NACELLE_Z1) / 2.0), Vector3(14.0, 14.0, length), _hull)
		# Bussard collector and warp-field strips.
		box(Vector3(x, NACELLE_Y - 7.0, NACELLE_Z0 - 5.0), Vector3(14.0, 14.0, 10.0), _red)
		for side: float in [-1.0, 1.0]:
			deco(Vector3(x + side * 7.05, NACELLE_Y - 7.0, (NACELLE_Z0 + NACELLE_Z1) / 2.0), Vector3(0.2, 6.0, length - 20.0), _blue)
		var light := OmniLight3D.new()
		light.position = Vector3(x, NACELLE_Y + 6.0, NACELLE_Z0 + 20.0)
		light.light_color = Color(1.0, 0.3, 0.2)
		light.light_energy = 2.0
		light.omni_range = 50.0
		add_child(light)
		for i in 3:
			var blue := OmniLight3D.new()
			blue.position = Vector3(x, NACELLE_Y + 4.0, lerpf(NACELLE_Z0 + 60.0, NACELLE_Z1 - 20.0, i / 2.0))
			blue.light_color = Color(0.4, 0.6, 1.0)
			blue.light_energy = 1.5
			blue.omni_range = 50.0
			add_child(blue)


func _stars() -> void:
	for i in 280:
		var dir := Vector3(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0)).normalized()
		var p := dir * _rng.randf_range(900.0, 1300.0) + Vector3(0, 0, 170.0)
		var size := _rng.randf_range(1.5, 4.5)
		deco(p, Vector3(size, size, size), _star)
