extends "res://scripts/maps/map_builder.gd"
## "THE THUNDER DOME": a round steel arena under a great panelled dome. Four tesla pylons
## crackle with lightning that arcs to the dome, the floor and each other (just for show,
## each computer its own); a raised cage platform in the middle with four ramps; a ring
## of low barriers; glowing rings on the floor.

const Beam := preload("res://scripts/dash_laser.gd")
const FlashLight := preload("res://scripts/flash_light.gd")
const Sfx := preload("res://scripts/sfx.gd")

const SEED := 9120
const RADIUS := 88.0
const WALL_HEIGHT := 28.0
const BANDS := 6
const BOLT := Color(0.55, 0.75, 1.0)

var _floor := checker(Color(0.13, 0.14, 0.18), Color(0.16, 0.17, 0.22), 6.0)
var _steel := panel(Color(0.22, 0.24, 0.3), Color(0.4, 0.55, 0.9), 6.0, 0.35)
var _dark := solid(Color(0.1, 0.11, 0.14), 0.5, 0.7)
var _hot := glow(BOLT, 4.0)
## Pylon tips, where the lightning comes from.
var _tips: Array[Vector3] = []
var _bolt_timer := 1.0
var _fx_rng := RandomNumberGenerator.new()


func _build() -> void:
	_rng.seed = SEED
	_fx_rng.randomize()
	_ceiling = WALL_HEIGHT + RADIUS * 0.8
	_outline = circle_outline(RADIUS, 32)
	ground(Rect2(-RADIUS - 10.0, -RADIUS - 10.0, RADIUS * 2.0 + 20.0, RADIUS * 2.0 + 20.0), _floor)
	ring(Vector2.ZERO, RADIUS, 32, 0.0, WALL_HEIGHT, 3.0, _steel)
	_build_dome()
	_build_center()
	for i in 8:
		var p := Vector2.from_angle(TAU * (i + 0.5) / 8.0) * 66.0
		_spawns.append(Vector3(p.x, 1.0, p.y))
	for i in 4:
		var p := Vector2.from_angle(TAU * (i + 0.5) / 4.0) * 44.0
		_turrets.append(Vector3(p.x, 0.0, p.y))


## The dome: bands of flat steel panels, each tangent to a sphere sitting on the wall.
func _build_dome() -> void:
	var center := Vector3(0, WALL_HEIGHT, 0)
	var band := (PI / 2.0) / BANDS
	for b in BANDS:
		var phi0 := band * b
		var phi1 := band * (b + 1)
		var phi := (phi0 + phi1) / 2.0
		var count := maxi(6, int(32 * cos(phi)))
		var ring_r := RADIUS * cos(phi)
		var slant := RADIUS * band * 1.12
		for i in count:
			var theta := TAU * (i + 0.5 * (b % 2)) / count
			var n := Vector3(cos(phi) * cos(theta), sin(phi), cos(phi) * sin(theta))
			var u := Vector3(-sin(theta), 0.0, cos(theta))
			var basis := Basis(u, n, u.cross(n))
			var width := 2.0 * ring_r * sin(PI / count) * 1.12 + 1.0
			box_basis(basis, center + n * RADIUS, Vector3(width, 2.0, slant), _steel, false)
	# A cap over the top.
	box(center + Vector3.UP * (RADIUS - 0.5), Vector3(24, 2, 24), _dark, 0.0, 0.0, false)
	# Glowing ribs running up the dome.
	for i in 8:
		var theta := TAU * i / 8.0
		for b in BANDS:
			var phi := (PI / 2.0) / BANDS * (b + 0.5)
			var n := Vector3(cos(phi) * cos(theta), sin(phi), cos(phi) * sin(theta))
			var m := MeshInstance3D.new()
			var mesh := BoxMesh.new()
			mesh.size = Vector3(0.6, 0.6, RADIUS * (PI / 2.0) / BANDS)
			m.mesh = mesh
			m.material_override = _hot
			var u := Vector3(-sin(theta), 0.0, cos(theta))
			m.transform = Transform3D(Basis(u, n, u.cross(n)), center + n * (RADIUS - 1.3))
			m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(m)


func _build_center() -> void:
	# The cage: a raised platform with a ramp on each side and corner posts.
	box(Vector3(0, 3, 0), Vector3(26, 6, 26), _dark)
	for k in 4:
		var yaw := TAU * k / 4.0
		var out := Vector3(sin(yaw), 0.0, cos(yaw))
		ramp(out * 42.0, out * 13.0 + Vector3.UP * 6.0, 10.0, _steel)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			box(Vector3(sx * 12.0, 12.0, sz * 12.0), Vector3(1.5, 12.0, 1.5), _dark)
	# Tesla pylons.
	for i in 4:
		var p := Vector2.from_angle(TAU * i / 4.0) * 58.0
		box(Vector3(p.x, 3.0, p.y), Vector3(8, 6, 8), _dark)
		box(Vector3(p.x, 20.0, p.y), Vector3(2.5, 28.0, 2.5), _steel)
		for k in 4:
			deco(Vector3(p.x, 10.0 + k * 6.0, p.y), Vector3(4.5, 0.6, 4.5), _hot)
		deco(Vector3(p.x, 35.0, p.y), Vector3(3.5, 3.5, 3.5), _hot)
		_tips.append(Vector3(p.x, 35.0, p.y))
	# Low barriers in a broken ring.
	for i in 12:
		if i % 3 == 1:
			continue
		var a := TAU * (i + 0.5) / 12.0
		var p := Vector2.from_angle(a) * 76.0
		box(Vector3(p.x, 2.0, p.y), Vector3(16.0, 4.0, 2.0), _dark, -a + PI / 2.0)
	# Glowing floor rings (flush, no collision).
	for r: float in [20.0, 50.0, 84.0]:
		var sides := 48
		for i in sides:
			var a := TAU * (i + 0.5) / sides
			var c := Vector2.from_angle(a) * r
			deco(Vector3(c.x, 0.03, c.y), Vector3(0.5, 0.06, 2.0 * r * sin(PI / sides) + 0.2), _hot, -a)


## Lightning: every second or so a bolt jumps from a pylon to the dome, the floor or the
## next pylon, with a flash and a crack of thunder.
func _process(delta: float) -> void:
	if _tips.is_empty() or DisplayServer.get_name() == "headless":
		return
	_bolt_timer -= delta
	if _bolt_timer > 0.0:
		return
	_bolt_timer = _fx_rng.randf_range(0.4, 1.8)
	var from: Vector3 = _tips[_fx_rng.randi() % _tips.size()]
	var to: Vector3
	match _fx_rng.randi() % 3:
		0:
			to = _tips[_fx_rng.randi() % _tips.size()]
			if to == from:
				to = Vector3(0, 12, 0)
		1:
			var a := _fx_rng.randf() * TAU
			var phi := _fx_rng.randf_range(0.3, 1.2)
			to = Vector3(0, WALL_HEIGHT, 0) + Vector3(cos(phi) * cos(a), sin(phi), cos(phi) * sin(a)) * (RADIUS - 2.0)
		_:
			var p := Vector2.from_angle(_fx_rng.randf() * TAU) * _fx_rng.randf_range(10.0, 80.0)
			to = Vector3(p.x, 0.1, p.y)
	_bolt(from, to)


## A jagged bolt: a few straight beams through jittered points.
func _bolt(from: Vector3, to: Vector3) -> void:
	var points: Array[Vector3] = [from]
	var steps := 6
	var side := (to - from).cross(Vector3.UP).normalized()
	if side.length() < 0.1:
		side = Vector3.RIGHT
	for i in range(1, steps):
		var p := from.lerp(to, float(i) / steps)
		var up := side.cross(to - from).normalized()
		p += side * _fx_rng.randf_range(-4.0, 4.0) + up * _fx_rng.randf_range(-4.0, 4.0)
		points.append(p)
	points.append(to)
	for i in points.size() - 1:
		var a := points[i]
		var b := points[i + 1]
		var beam := Beam.new()
		beam.length = a.distance_to(b)
		beam.width = 0.5
		beam.lifetime = 0.18
		beam.extend_time = 0.02
		beam.shoot_speed = 0.0
		beam.widest_at = 0.1
		beam.intensity = 14.0
		beam.color = BOLT
		add_child(beam)
		beam.fire(a, (b - a).normalized())
	var light := FlashLight.new()
	light.light_color = BOLT
	light.light_energy = 20.0
	light.omni_range = 60.0
	light.lifetime = 0.2
	light.position = to
	add_child(light)
	Sfx.play_at(get_tree(), "zap", from, -2.0, 0.5)
	Sfx.play_at(get_tree(), "boom", to, -14.0, 1.4)
