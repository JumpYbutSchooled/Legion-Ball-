extends "res://scripts/maps/map_builder.gd"
## "Military Base": a high-tech installation behind a perimeter wall. A runway with
## glowing edge lights runs along the north side past three open-fronted hangars (roll
## through them, or up the ramps onto their roofs). In the middle: the command centre,
## a glass-and-steel block with a helipad on the roof, flanked by radar towers with
## spinning-looking dishes. The south yard is a maze of stacked shipping containers,
## sandbag bunkers and watchtowers at the corners.

const SEED := 7331
const HALF_X := 260.0
const HALF_Z := 190.0

var _tarmac := checker(Color(0.16, 0.17, 0.18), Color(0.18, 0.19, 0.2), 10.0)
var _concrete := panel(Color(0.46, 0.47, 0.48), Color(0.38, 0.39, 0.4), 6.0)
var _steel := panel(Color(0.3, 0.33, 0.36), Color(0.2, 0.9, 0.6), 4.0, 0.8)
var _hangar := panel(Color(0.38, 0.42, 0.38), Color(0.3, 0.33, 0.3), 5.0)
var _glass := panel(Color(0.08, 0.14, 0.18), Color(0.2, 0.9, 0.7), 3.0, 1.0, 0.6)
var _sandbag := solid(Color(0.55, 0.5, 0.38))
var _runway_light := glow(Color(0.3, 1.0, 0.6), 4.0)
var _warning := glow(Color(1.0, 0.25, 0.15), 4.0)
var _helipad := glow(Color(0.2, 0.9, 0.7), 1.5)
var _container_colors := [Color(0.7, 0.2, 0.15), Color(0.15, 0.35, 0.6), Color(0.2, 0.45, 0.25), Color(0.75, 0.55, 0.15), Color(0.4, 0.42, 0.45)]


func _build() -> void:
	_rng.seed = SEED
	_ceiling = 120.0
	var bounds := Rect2(-HALF_X, -HALF_Z, HALF_X * 2.0, HALF_Z * 2.0)
	_outline = rect_outline(bounds)
	ground(bounds.grow(10.0), _tarmac)
	_perimeter()
	_runway()
	_hangars()
	_command_center()
	_container_yard()
	for i in 8:
		var p := Vector2(lerpf(-200.0, 200.0, (i % 4) / 3.0), -40.0 if i < 4 else 70.0)
		_spawns.append(Vector3(p.x, 1.0, p.y))
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_turrets.append(Vector3(sx * (HALF_X - 14.0), 18.0, sz * (HALF_Z - 14.0)))


## A tall wall round everything with a gate on the east side, and a watchtower at each
## corner (turrets stand on their platforms).
func _perimeter() -> void:
	for k in 4:
		var yaw := TAU * k / 4.0
		var out := Vector3(sin(yaw), 0.0, cos(yaw))
		var reach := HALF_Z if k % 2 == 0 else HALF_X
		var span := HALF_X if k % 2 == 0 else HALF_Z
		box(out * (reach + 2.0) + Vector3.UP * 30.0, Vector3(span * 2.0 + 8.0, 60.0, 4.0), _concrete, yaw)
		# Glowing strip along the top.
		deco(out * (reach + 0.0) + Vector3.UP * 59.0, Vector3(span * 2.0, 0.4, 0.4), _warning, yaw)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var p := Vector2(sx * (HALF_X - 14.0), sz * (HALF_Z - 14.0))
			for cx: float in [-1.0, 1.0]:
				for cz: float in [-1.0, 1.0]:
					pillar(p + Vector2(cx, cz) * 5.0, 0.0, 1.2, 17.0, _steel)
			box(Vector3(p.x, 17.5, p.y), Vector3(14.0, 1.0, 14.0), _steel)
			ramp(Vector3(p.x - sx * 32.0, 0.0, p.y), Vector3(p.x - sx * 7.0, 17.0, p.y), 6.0, _concrete)


func _runway() -> void:
	var z := -HALF_Z + 45.0
	box(Vector3(0, 0.05, z), Vector3(HALF_X * 2.0 - 30.0, 0.3, 40.0), checker(Color(0.1, 0.1, 0.11), Color(0.12, 0.12, 0.13), 20.0))
	# Centre-line dashes and edge lights.
	for i in 24:
		var x := lerpf(-HALF_X + 30.0, HALF_X - 30.0, i / 23.0)
		deco(Vector3(x, 0.25, z), Vector3(8.0, 0.05, 0.8), glow(Color(0.95, 0.95, 0.9), 1.5))
		for s: float in [-1.0, 1.0]:
			deco(Vector3(x, 0.4, z + s * 19.0), Vector3(0.8, 0.5, 0.8), _runway_light)
	# A parked jet: fuselage, wings and tail (solid: good cover and a ramp).
	var j := Vector2(-120.0, z)
	box(Vector3(j.x, 2.5, j.y), Vector3(36.0, 4.0, 5.0), _steel)
	box(Vector3(j.x + 2.0, 2.0, j.y), Vector3(12.0, 0.8, 34.0), _steel)
	box(Vector3(j.x + 15.0, 6.0, j.y), Vector3(6.0, 7.0, 0.8), _steel)
	box(Vector3(j.x - 16.0, 3.6, j.y), Vector3(5.0, 1.6, 3.6), _glass)


## Three open hangars facing the runway, with a ramp up to each curved-looking roof.
func _hangars() -> void:
	for i in 3:
		var x := -130.0 + i * 130.0
		var z := -HALF_Z + 105.0
		var w := 70.0
		var d := 50.0
		var h := 24.0
		# Back wall and two side walls (open at the front, toward the runway).
		box(Vector3(x, h / 2.0, z + d / 2.0), Vector3(w, h, 2.0), _hangar)
		for s: float in [-1.0, 1.0]:
			box(Vector3(x + s * w / 2.0, h / 2.0, z), Vector3(2.0, h, d), _hangar)
		# Stepped roof: a flat top and two sloped halves.
		box(Vector3(x, h + 0.5, z), Vector3(w * 0.5, 1.0, d + 2.0), _hangar)
		for s: float in [-1.0, 1.0]:
			box_basis(Basis(Vector3(0, 0, 1), s * -0.28), Vector3(x + s * w * 0.37, h - 1.8, z), Vector3(w * 0.28, 1.0, d + 2.0), _hangar)
		ramp(Vector3(x + w / 2.0 + 30.0, 0.0, z + d / 2.0 + 8.0), Vector3(x + w / 4.0, h + 1.0, z + d / 2.0 + 8.0), 8.0, _concrete)
		box(Vector3(x + w / 4.0 - 4.0, h + 0.5, z + d / 2.0 + 4.0), Vector3(12.0, 1.0, 10.0), _concrete)
		# Crates inside.
		for c in 3:
			box(Vector3(x + _rng.randf_range(-25.0, 25.0), 2.0, z + _rng.randf_range(-15.0, 15.0)), Vector3(4, 4, 4), _sandbag, _rng.randf() * PI)


## Command centre in the middle, radar towers either side.
func _command_center() -> void:
	var c := Vector2(0.0, 30.0)
	box(Vector3(c.x, 12.0, c.y), Vector3(60.0, 24.0, 40.0), _glass)
	# Helipad on the roof: a glowing ring and an H, reached by a ramp up the east side.
	deco(Vector3(c.x, 24.1, c.y), Vector3(26.0, 0.1, 26.0), _helipad)
	deco(Vector3(c.x, 24.15, c.y), Vector3(22.0, 0.1, 22.0), solid(Color(0.1, 0.12, 0.14)))
	for s: float in [-1.0, 1.0]:
		deco(Vector3(c.x + s * 5.0, 24.2, c.y), Vector3(1.5, 0.1, 12.0), _helipad)
	deco(Vector3(c.x, 24.2, c.y), Vector3(10.0, 0.1, 1.5), _helipad)
	ramp(Vector3(c.x + 30.0 + 60.0, 0.0, c.y + 14.0), Vector3(c.x + 30.0, 24.0, c.y + 14.0), 10.0, _concrete)
	for s: float in [-1.0, 1.0]:
		var p := c + Vector2(s * 90.0, -10.0)
		pillar(p, 0.0, 4.0, 38.0, _steel)
		# The dish: a tilted wide slab on top, and a glowing emitter.
		box_basis(Basis.from_euler(Vector3(-0.6, s * 0.5, 0.0)), Vector3(p.x, 40.0, p.y), Vector3(18.0, 1.0, 14.0), _steel)
		deco(Vector3(p.x, 43.0, p.y), Vector3(1.2, 1.2, 1.2), _warning)
		var light := OmniLight3D.new()
		light.position = Vector3(p.x, 42.0, p.y)
		light.light_color = Color(1.0, 0.3, 0.2)
		light.light_energy = 2.0
		light.omni_range = 40.0
		add_child(light)
	# Floodlights round the base.
	for i in 6:
		var p := Vector2(lerpf(-200.0, 200.0, i / 5.0), 5.0)
		var light := OmniLight3D.new()
		light.position = Vector3(p.x, 30.0, p.y)
		light.light_color = Color(0.75, 0.95, 0.9)
		light.light_energy = 1.3
		light.omni_range = 110.0
		add_child(light)


## The south yard: containers in rows and stacks, and sandbag bunkers.
func _container_yard() -> void:
	for row in 5:
		for col in 9:
			if _rng.randf() < 0.3:
				continue
			var x := -200.0 + col * 50.0 + _rng.randf_range(-6.0, 6.0)
			var z := 95.0 + row * 17.0
			var yaw := 0.0 if _rng.randf() < 0.7 else PI / 2.0
			var stack := 1 if _rng.randf() < 0.6 else (2 if _rng.randf() < 0.8 else 3)
			for s in stack:
				var tint: Color = _container_colors[_rng.randi() % _container_colors.size()]
				box(Vector3(x, 1.6 + s * 3.2, z), Vector3(18.0, 3.2, 3.2), panel(tint, tint.darkened(0.3), 1.0), yaw + _rng.randf_range(-0.05, 0.05))
	for i in 8:
		var p := Vector2(_rng.randf_range(-220.0, 220.0), _rng.randf_range(-20.0, 80.0))
		if absf(p.x) < 50.0 and p.y > 5.0:
			continue
		var a := _rng.randf() * TAU
		for k in 3:
			var q := p + Vector2.from_angle(a + k * 0.9) * 5.0
			box(Vector3(q.x, 1.1, q.y), Vector3(6.0, 2.2, 1.8), _sandbag, -(a + k * 0.9) + PI / 2.0)
