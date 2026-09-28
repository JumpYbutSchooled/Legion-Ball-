extends "res://scripts/maps/map_builder.gd"
## "Starship": fight on the outside of an arrowhead-shaped starship in deep space. The
## round saucer at the front is the main arena: a huge deck stepping up in rings (low
## enough to jump) to the bridge on top. Behind it a flat spine runs back to the raised
## engine block, whose thrusters glow out of its back face, with two tail fins on top.
## Swept-back wings a jump below the spine reach out to either side. Fall off anywhere
## and it's a long way down.

const SEED := 2410
const SAUCER_R := 130.0
const SPINE_W := 36.0
const SPINE_Z0 := 110.0
const WING_ROOT_Z := 150.0
const WING_TIP_X := 140.0
const WING_TIP_Z := 400.0
const WING_W := 60.0
const WING_TOP := -3.0
const ENGINE_W := 180.0
const ENGINE_Z0 := 380.0
const ENGINE_Z1 := 430.0
var _hull := panel(Color(0.78, 0.8, 0.82), Color(0.62, 0.65, 0.68), 8.0)
var _hull_dark := panel(Color(0.55, 0.58, 0.62), Color(0.45, 0.48, 0.52), 5.0)
var _windows := panel(Color(0.6, 0.63, 0.66), Color(0.5, 0.52, 0.55), 3.0, 0.0, 0.5)
var _blue := glow(Color(0.3, 0.6, 1.0), 4.0)
var _red := glow(Color(1.0, 0.2, 0.1), 5.0)
var _thruster := glow(Color(0.7, 0.9, 1.0), 6.0)
var _green := glow(Color(0.2, 1.0, 0.35), 5.0)
var _star := glow(Color(1.0, 1.0, 1.0), 6.0)


## Built at twice its written size in every direction.
func map_size() -> float:
	return 2.0


func _build() -> void:
	_rng.seed = SEED
	_ceiling = 80.0
	_fall = -60.0
	_outline = rect_outline(Rect2(-WING_TIP_X - 32.0, -SAUCER_R - 10.0, (WING_TIP_X + 32.0) * 2.0, ENGINE_Z1 + SAUCER_R + 10.0))
	_saucer()
	_spine()
	_wings()
	_engines()
	_stars()
	for i in 6:
		var p := Vector2.from_angle(TAU * i / 6.0) * 105.0
		_spawns.append(Vector3(p.x, 1.0, p.y))
	_spawns.append(Vector3(0.0, 1.0, 225.0))
	_spawns.append(Vector3(0.0, 1.0, 325.0))
	_spawns.append(Vector3(-84.0, WING_TOP + 1.0, 300.0))
	_spawns.append(Vector3(84.0, WING_TOP + 1.0, 300.0))
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


## The spine: a flat deck running straight back from the saucer, level with its rim, with
## low bumps along it for cover.
func _spine() -> void:
	var length := ENGINE_Z0 - SPINE_Z0
	box(Vector3(0.0, -3.0, (SPINE_Z0 + ENGINE_Z0) / 2.0), Vector3(SPINE_W, 6.0, length), _hull)
	for side: float in [-1.0, 1.0]:
		deco(Vector3(side * (SPINE_W / 2.0 - 1.5), 0.05, (SPINE_Z0 + ENGINE_Z0) / 2.0), Vector3(0.8, 0.1, length - 10.0), _blue)
	for i in 5:
		var z := lerpf(SPINE_Z0 + 40.0, ENGINE_Z0 - 30.0, i / 4.0)
		box(Vector3(_rng.randf_range(-10.0, 10.0), 1.5, z), Vector3(8.0, 3.0, 10.0), _hull_dark)


## Two swept-back wings, one jump (3 m) below the spine, reaching out and back to the
## engine block so the whole ship is an arrowhead. Red and green lights on the tips.
func _wings() -> void:
	for s: float in [-1.0, 1.0]:
		var root := Vector2(s * (SPINE_W / 2.0 - 4.0), WING_ROOT_Z)
		var tip := Vector2(s * WING_TIP_X, WING_TIP_Z)
		var d := tip - root
		var yaw := atan2(d.x, d.y)
		var mid := (root + tip) / 2.0
		box(Vector3(mid.x, WING_TOP - 2.0, mid.y), Vector3(WING_W, 4.0, d.length()), _hull, yaw)
		# Glowing leading edge (the edge that faces forward and out).
		var edge := mid + Vector2(d.y, -d.x).normalized() * s * (WING_W / 2.0 - 0.6)
		deco(Vector3(edge.x, WING_TOP + 0.05, edge.y), Vector3(1.0, 0.1, d.length() - 8.0), _blue, yaw)
		# Panels along the wing to break it up, and a step back up to the spine.
		for i in 3:
			var p := root.lerp(tip, 0.3 + 0.25 * i)
			box(Vector3(p.x, WING_TOP + 1.0, p.y), Vector3(10.0, 2.0, 14.0), _hull_dark, yaw)
		for t: float in [0.15, 0.55]:
			var z := lerpf(WING_ROOT_Z, WING_TIP_Z, t)
			ramp(Vector3(s * (SPINE_W / 2.0 + 10.0), WING_TOP, z), Vector3(s * (SPINE_W / 2.0 - 1.0), 0.0, z), 10.0, _hull_dark)
		deco(Vector3(tip.x, WING_TOP + 0.6, tip.y), Vector3(2.0, 1.2, 2.0), _red if s < 0.0 else _green)
		var light := OmniLight3D.new()
		light.position = Vector3(mid.x, WING_TOP + 12.0, mid.y)
		light.light_color = Color(0.6, 0.75, 1.0)
		light.light_energy = 1.4
		light.omni_range = 70.0
		add_child(light)


## The engine block across the back: raised a jump above the spine (ramps up), two tail
## fins for cover, and a row of thrusters built into its back face.
func _engines() -> void:
	var depth := ENGINE_Z1 - ENGINE_Z0
	var zc := (ENGINE_Z0 + ENGINE_Z1) / 2.0
	box(Vector3(0.0, -3.0, zc), Vector3(ENGINE_W, 12.0, depth), _hull)
	box(Vector3(0.0, -10.0, zc + 4.0), Vector3(ENGINE_W - 30.0, 6.0, depth - 8.0), _hull_dark)
	for x: float in [-24.0, 24.0]:
		ramp(Vector3(x, 0.0, ENGINE_Z0 - 16.0), Vector3(x, 3.0, ENGINE_Z0 + 1.0), 12.0, _hull_dark)
	for s: float in [-1.0, 1.0]:
		box(Vector3(s * 46.0, 10.0, zc + 6.0), Vector3(3.0, 14.0, depth - 16.0), _hull_dark)
		deco(Vector3(s * 46.0, 17.2, zc + 6.0), Vector3(3.2, 0.4, depth - 18.0), _blue)
	for i in 5:
		var x := lerpf(-ENGINE_W / 2.0 + 22.0, ENGINE_W / 2.0 - 22.0, i / 4.0)
		deco(Vector3(x, -4.0, ENGINE_Z1 + 0.6), Vector3(18.0, 7.0, 1.0), _thruster)
		var light := OmniLight3D.new()
		light.position = Vector3(x, -4.0, ENGINE_Z1 + 10.0)
		light.light_color = Color(0.7, 0.9, 1.0)
		light.light_energy = 2.5
		light.omni_range = 45.0
		add_child(light)


func _stars() -> void:
	for i in 280:
		var dir := Vector3(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0)).normalized()
		var p := dir * _rng.randf_range(900.0, 1300.0) + Vector3(0, 0, 170.0)
		var size := _rng.randf_range(1.5, 4.5)
		deco(p, Vector3(size, size, size), _star)
