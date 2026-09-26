extends "res://scripts/maps/map_builder.gd"
## "Atlantis": the lost city on the sea floor, laid out as Plato described it: rings of
## land and water round a central island. The island holds the Temple of Poseidon, a
## stepped platform crowned with a ring of pillars and a glowing orichalcum spire. Two
## water rings (sunken canals you can roll through) separate it from two land rings of
## broken colonnades, arches and coral; four bridges cross each canal. A sea wall rings
## the whole city. Everything glows faintly blue-green under the water.

const SEED := 9000
## Ring edges, from the middle out: island, canal, land, canal, land, sea wall.
const ISLAND := 45.0
const CANAL_1 := 70.0
const LAND_1 := 125.0
const CANAL_2 := 150.0
const LAND_2 := 215.0
const CANAL_DEPTH := 7.0

var _marble := panel(Color(0.72, 0.8, 0.82), Color(0.35, 0.85, 0.9), 4.0, 0.6)
var _marble_dark := panel(Color(0.45, 0.55, 0.6), Color(0.3, 0.75, 0.85), 4.0, 0.4)
var _sand := checker(Color(0.55, 0.6, 0.55), Color(0.5, 0.56, 0.52), 8.0)
var _canal_bed := glow(Color(0.05, 0.35, 0.45), 0.5)
var _orichalcum := glow(Color(1.0, 0.55, 0.2), 4.0)
var _coral := [glow(Color(1.0, 0.35, 0.5), 1.2), glow(Color(0.9, 0.5, 1.0), 1.2), glow(Color(1.0, 0.7, 0.3), 1.2)]
var _seaweed := solid(Color(0.1, 0.4, 0.28))


func _build() -> void:
	_rng.seed = SEED
	_ceiling = 95.0
	_outline = circle_outline(LAND_2 + 8.0, 36)
	# Land at y 0; canals are trenches down to -CANAL_DEPTH.
	disc(Vector3.ZERO, ISLAND, 2.0, _sand, 3)
	_ring_slab(CANAL_1, LAND_1, 0.0, _sand)
	_ring_slab(CANAL_2, LAND_2 + 10.0, 0.0, _sand)
	_ring_slab(ISLAND - 1.0, CANAL_1 + 1.0, -CANAL_DEPTH, _canal_bed)
	_ring_slab(LAND_1 - 1.0, CANAL_2 + 1.0, -CANAL_DEPTH, _canal_bed)
	# Canal walls (quay sides), so the trenches have edges.
	for r in [ISLAND, CANAL_1, LAND_1, CANAL_2]:
		ring(Vector2.ZERO, r, 40, -CANAL_DEPTH, CANAL_DEPTH, 1.2, _marble_dark)
	_bridges()
	_temple()
	_ruins()
	# The sea wall.
	ring(Vector2.ZERO, LAND_2 + 8.0, 36, 0.0, 70.0, 6.0, _marble_dark)
	for i in 8:
		var a := TAU * (i + 0.5) / 8.0
		var p := Vector2.from_angle(a) * (95.0 if i % 2 == 0 else 185.0)
		_spawns.append(Vector3(p.x, 1.0, p.y))
	for i in 4:
		var p := Vector2.from_angle(TAU * i / 4.0 + PI / 4.0) * 110.0
		_turrets.append(Vector3(p.x, 0.0, p.y))
	# Light shafts from the surface: a few big soft blue-green lights high up.
	for i in 6:
		var p := Vector2.from_angle(TAU * i / 6.0) * 120.0
		var light := OmniLight3D.new()
		light.position = Vector3(p.x, 70.0, p.y)
		light.omni_range = 180.0
		light.light_energy = 1.1
		light.light_color = Color(0.4, 0.9, 0.95)
		add_child(light)


## A flat ring of blocks between radii r0 and r1, top at `top`.
func _ring_slab(r0: float, r1: float, top: float, mat: Material) -> void:
	var sides := maxi(16, int(TAU * r1 / 16.0))
	var step := TAU / sides
	for s in sides:
		var mid := step * (s + 0.5)
		var c := Vector2.from_angle(mid) * (r0 + r1) / 2.0
		box(Vector3(c.x, top - 1.0, c.y), Vector3(r1 - r0, 2.0, 2.0 * r1 * sin(step / 2.0) + 0.5), mat, -mid)


func _bridges() -> void:
	for k in 4:
		var a := TAU * k / 4.0
		for span in [[ISLAND - 2.0, CANAL_1 + 2.0], [LAND_1 - 2.0, CANAL_2 + 2.0]]:
			var r: float = (span[0] + span[1]) / 2.0
			var length: float = span[1] - span[0]
			var c := Vector2.from_angle(a) * r
			# A low arch: flat deck on two piers down in the canal.
			box(Vector3(c.x, -0.5, c.y), Vector3(length, 1.0, 12.0), _marble, -a)
			for s: float in [-0.3, 0.3]:
				var pier := Vector2.from_angle(a) * (r + s * length)
				pillar(pier, -CANAL_DEPTH, 4.0, CANAL_DEPTH - 1.0, _marble_dark, -a)
			for side: float in [-1.0, 1.0]:
				var rail := c + Vector2.from_angle(a + PI / 2.0) * 6.5 * side
				box(Vector3(rail.x, 0.8, rail.y), Vector3(length, 1.6, 0.8), _marble_dark, -a)


## The Temple of Poseidon on the island: three stepped tiers (low enough to jump up), a
## ring of pillars, and an orichalcum spire in the middle.
func _temple() -> void:
	for tier in 3:
		var size := 58.0 - tier * 14.0
		var h := 2.5
		box(Vector3(0.0, tier * h + h / 2.0, 0.0), Vector3(size, h, size), _marble if tier % 2 == 0 else _marble_dark, PI / 4.0 * tier)
	# Ramps up each face of the lowest tier.
	for k in 4:
		var yaw := TAU * k / 4.0
		var out := Vector3(sin(yaw), 0.0, cos(yaw))
		ramp(out * 40.0, out * 29.0 + Vector3.UP * 2.5, 10.0, _marble)
	var top := 7.5
	for i in 12:
		var p := Vector2.from_angle(TAU * i / 12.0) * 13.0
		pillar(p, top, 2.2, 14.0, _marble)
	disc(Vector3(0.0, top + 15.0, 0.0), 15.0, 1.5, _marble_dark, 2, false)
	pillar(Vector2.ZERO, top, 3.0, 30.0, _orichalcum)
	var glow_light := OmniLight3D.new()
	glow_light.position = Vector3(0.0, top + 20.0, 0.0)
	glow_light.light_color = Color(1.0, 0.6, 0.3)
	glow_light.light_energy = 3.0
	glow_light.omni_range = 70.0
	add_child(glow_light)


## Broken colonnades, fallen arches and coral on the two land rings.
func _ruins() -> void:
	for band in [[CANAL_1 + 8.0, LAND_1 - 8.0], [CANAL_2 + 8.0, LAND_2 - 8.0]]:
		# Colonnade arcs: rows of columns along the ring, some broken short.
		for arc in 5:
			var a0 := _rng.randf() * TAU
			var r: float = _rng.randf_range(band[0], band[1])
			for i in 7:
				var a := a0 + i * 0.07
				var p := Vector2.from_angle(a) * r
				if _rng.randf() < 0.25:
					continue
				var h := 18.0 if _rng.randf() < 0.6 else _rng.randf_range(4.0, 12.0)
				pillar(p, 0.0, 2.6, h, _marble, -a)
			# A beam across the tops of the first few.
			var mid := Vector2.from_angle(a0 + 0.1) * r
			box(Vector3(mid.x, 19.0, mid.y), Vector3(2.4, 2.0, r * 0.2), _marble_dark, -(a0 + 0.1))
		# Fallen arches: a slab lying tilted against the ground, a ramp to jump from.
		for i in 4:
			var a := _rng.randf() * TAU
			var r: float = _rng.randf_range(band[0], band[1])
			var p := Vector2.from_angle(a) * r
			box(Vector3(p.x, 3.0, p.y), Vector3(10.0, 1.5, 18.0), _marble, _rng.randf() * TAU, 0.35)
		# Coral and seaweed.
		for i in 14:
			var a := _rng.randf() * TAU
			var p: Vector2 = Vector2.from_angle(a) * _rng.randf_range(band[0], band[1])
			if _rng.randf() < 0.5:
				var h := _rng.randf_range(3.0, 9.0)
				pillar(p, 0.0, _rng.randf_range(1.0, 2.2), h, _coral[_rng.randi() % _coral.size()], _rng.randf() * PI)
			else:
				deco(Vector3(p.x, 3.0, p.y), Vector3(0.6, 6.0, 0.6), _seaweed, _rng.randf() * PI)
