extends "res://scripts/maps/map_builder.gd"
## "Castle": a medieval fortress on a hill of grass. A square curtain wall with a tower at
## each corner and crenellations along the top, wide enough to roll along (ramps inside
## lead up to it). A gatehouse on the south side opens onto a drawbridge over the moat.
## In the courtyard: the great keep (a tall stone block with its own ramp spiralling up
## the outside to the roof), stables, a well and training dummies. Outside: the moat all
## the way round, then open fields with haystacks up to a ring of rocky hills.

const SEED := 1066
const WALL_HALF := 90.0
const WALL_HEIGHT := 22.0
const WALL_THICK := 10.0
const TOWER := 22.0
const TOWER_HEIGHT := 34.0
const MOAT_IN := WALL_HALF + WALL_THICK / 2.0 + 6.0
const MOAT_WIDTH := 22.0
const FIELD_HALF := 230.0

var _stone := panel(Color(0.52, 0.5, 0.46), Color(0.42, 0.4, 0.37), 3.0)
var _stone_dark := panel(Color(0.4, 0.38, 0.35), Color(0.32, 0.3, 0.28), 3.0)
var _grass := checker(Color(0.25, 0.45, 0.2), Color(0.27, 0.48, 0.21), 10.0)
var _wood := solid(Color(0.42, 0.28, 0.16))
var _water := glow(Color(0.12, 0.32, 0.55), 0.5)
var _roof := solid(Color(0.45, 0.14, 0.12))
var _hay := solid(Color(0.85, 0.72, 0.35))
var _rock := solid(Color(0.45, 0.43, 0.4))


func _build() -> void:
	_rng.seed = SEED
	_ceiling = 80.0
	_outline = rect_outline(Rect2(-FIELD_HALF, -FIELD_HALF, FIELD_HALF * 2.0, FIELD_HALF * 2.0))
	_ground_and_moat()
	_curtain_walls()
	_keep()
	_courtyard()
	_fields()
	# Spawns: four in the courtyard, four out in the fields.
	for i in 4:
		var a := TAU * (i + 0.5) / 4.0
		var p := Vector2.from_angle(a) * 55.0
		_spawns.append(Vector3(p.x, 1.0, p.y))
		var q := Vector2.from_angle(a + PI / 4.0) * 175.0
		_spawns.append(Vector3(q.x, 1.0, q.y))
	# Turrets on the tower tops.
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_turrets.append(Vector3(sx * WALL_HALF, TOWER_HEIGHT, sz * WALL_HALF))


## Grass everywhere except a sunken moat ring round the walls (shallow water in it).
func _ground_and_moat() -> void:
	var moat_out := MOAT_IN + MOAT_WIDTH
	# Inside the moat: one slab.
	box(Vector3(0, -0.5, 0), Vector3(MOAT_IN * 2.0, 1.0, MOAT_IN * 2.0), _grass)
	# Outside the moat: four slabs round it.
	var outer := FIELD_HALF + 10.0
	var band := outer - moat_out
	for k in 4:
		var yaw := TAU * k / 4.0
		var out := Vector3(sin(yaw), 0.0, cos(yaw))
		box(out * (moat_out + band / 2.0) + Vector3.DOWN * 0.5, Vector3(outer * 2.0, 1.0, band), _grass, yaw)
	# The moat: a trench 5 m down with water in the bottom.
	for k in 4:
		var yaw := TAU * k / 4.0
		var out := Vector3(sin(yaw), 0.0, cos(yaw))
		box(out * (MOAT_IN + MOAT_WIDTH / 2.0) + Vector3.DOWN * 5.5, Vector3(moat_out * 2.0, 1.0, MOAT_WIDTH), _water, yaw)
	# Moat banks (earth walls down to the water).
	for k in 4:
		var yaw := TAU * k / 4.0
		var out := Vector3(sin(yaw), 0.0, cos(yaw))
		for r in [MOAT_IN, moat_out]:
			box(out * r + Vector3.DOWN * 2.75, Vector3(r * 2.0, 5.5, 1.0), _rock, yaw)


func _curtain_walls() -> void:
	# Four walls with a gate gap in the south one (+z), filled by the gatehouse.
	var gate := 16.0
	for k in 4:
		var yaw := TAU * k / 4.0
		var out := Vector3(sin(yaw), 0.0, cos(yaw))
		var side := Vector3(cos(yaw), 0.0, -sin(yaw))
		if k == 0:
			for s: float in [-1.0, 1.0]:
				var length := WALL_HALF - gate / 2.0
				box(out * WALL_HALF + side * s * (gate / 2.0 + length / 2.0) + Vector3.UP * WALL_HEIGHT / 2.0, Vector3(length, WALL_HEIGHT, WALL_THICK), _stone, yaw)
		else:
			box(out * WALL_HALF + Vector3.UP * WALL_HEIGHT / 2.0, Vector3(WALL_HALF * 2.0, WALL_HEIGHT, WALL_THICK), _stone, yaw)
		# Crenellations along the outer edge of the wall walk.
		var merlons := 20
		for m in merlons:
			var along := lerpf(-WALL_HALF + 6.0, WALL_HALF - 6.0, m / float(merlons - 1))
			if k == 0 and absf(along) < gate / 2.0 + 2.0:
				continue
			box(out * (WALL_HALF + WALL_THICK / 2.0 - 1.0) + side * along + Vector3.UP * (WALL_HEIGHT + 1.5), Vector3(3.5, 3.0, 2.0), _stone_dark, yaw)
		# A ramp up to the wall walk on the inside of each wall.
		var foot := out * (WALL_HALF - WALL_THICK / 2.0 - 6.0) + side * (WALL_HALF - 30.0)
		var head := out * (WALL_HALF - WALL_THICK / 2.0 - 6.0) + side * (WALL_HALF - 30.0 - 70.0)
		ramp(Vector3(head.x, 0.0, head.z), Vector3(foot.x, WALL_HEIGHT, foot.z), 12.0, _stone_dark)
		box(Vector3(foot.x, WALL_HEIGHT / 2.0, foot.z) + side * 3.0, Vector3(12.0, WALL_HEIGHT, 8.0), _stone_dark, yaw)
	# Corner towers, taller than the walls, with a pointed roof block on top.
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var p := Vector2(sx * WALL_HALF, sz * WALL_HALF)
			pillar(p, 0.0, TOWER, TOWER_HEIGHT, _stone_dark)
			for m in 4:
				var a := TAU * m / 4.0
				var e := p + Vector2.from_angle(a) * (TOWER / 2.0 - 1.5)
				box(Vector3(e.x, TOWER_HEIGHT + 1.5, e.y), Vector3(5.0, 3.0, 5.0), _stone, a)
	# Gatehouse: two squat towers either side of the gate, a lintel over it, and the
	# drawbridge across the moat.
	for s: float in [-1.0, 1.0]:
		pillar(Vector2(s * 14.0, WALL_HALF), 0.0, 12.0, WALL_HEIGHT + 8.0, _stone_dark)
	box(Vector3(0, WALL_HEIGHT + 2.0, WALL_HALF), Vector3(gate + 4.0, 8.0, WALL_THICK + 2.0), _stone_dark)
	var bridge_len := MOAT_IN + MOAT_WIDTH - WALL_HALF + 4.0
	box(Vector3(0, 0.3, WALL_HALF + bridge_len / 2.0), Vector3(14.0, 1.0, bridge_len), _wood)
	for s: float in [-1.0, 1.0]:
		box(Vector3(s * 7.5, 1.5, WALL_HALF + bridge_len / 2.0), Vector3(1.0, 2.0, bridge_len), _wood)


## The keep: a big tower in the courtyard's north half. A ramp climbs round its outside
## (three sides) to the roof.
func _keep() -> void:
	var c := Vector2(0.0, -28.0)
	var w := 44.0
	var h := 40.0
	box(Vector3(c.x, h / 2.0, c.y), Vector3(w, h, w), _stone)
	# Roof edge merlons.
	for m in 12:
		var t := m / 12.0 * 4.0
		var side := int(t)
		var f := t - side
		var corners := [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
		var a: Vector2 = corners[side] * (w / 2.0 - 1.0)
		var b: Vector2 = corners[(side + 1) % 4] * (w / 2.0 - 1.0)
		if side == 1:
			continue  # The east edge stays open: the ramp arrives there.
		var p := c + a.lerp(b, f)
		box(Vector3(p.x, h + 1.5, p.y), Vector3(3.0, 3.0, 3.0), _stone_dark)
	# A spiral ramp: west side up to 14, north side up to 27, east side up to the roof,
	# with a landing at each corner. The lane hugs the keep's walls.
	var r := w / 2.0 + 4.5
	ramp(Vector3(c.x - r, 0.0, c.y + w / 2.0), Vector3(c.x - r, 14.0, c.y - r + 5.0), 9.0, _stone_dark)
	box(Vector3(c.x - r, 13.5, c.y - r), Vector3(10.0, 1.0, 10.0), _stone_dark)
	ramp(Vector3(c.x - r + 5.0, 14.0, c.y - r), Vector3(c.x + r - 5.0, 27.0, c.y - r), 9.0, _stone_dark)
	box(Vector3(c.x + r, 26.5, c.y - r), Vector3(10.0, 1.0, 10.0), _stone_dark)
	ramp(Vector3(c.x + r, 27.0, c.y - r + 5.0), Vector3(c.x + r, h, c.y + w / 2.0 - 4.0), 9.0, _stone_dark)
	# Supports under the landings so they read as solid.
	pillar(Vector2(c.x - r, c.y - r), 0.0, 3.0, 13.0, _stone)
	pillar(Vector2(c.x + r, c.y - r), 0.0, 3.0, 26.0, _stone)	# A flag on top.
	pillar(Vector2(c.x, c.y), h, 0.8, 14.0, _wood)
	deco(Vector3(c.x + 3.5, h + 11.0, c.y), Vector3(6.0, 4.0, 0.3), glow(Color(0.8, 0.12, 0.1), 1.2))


func _courtyard() -> void:
	# Stables along the east wall: a low roofed shed.
	box(Vector3(WALL_HALF - 22.0, 4.0, 30.0), Vector3(20.0, 8.0, 50.0), _wood)
	box(Vector3(WALL_HALF - 22.0, 8.5, 30.0), Vector3(24.0, 1.0, 54.0), _roof)
	# The well.
	pillar(Vector2(-30.0, 40.0), 0.0, 7.0, 2.5, _stone_dark)
	for s: float in [-1.0, 1.0]:
		pillar(Vector2(-30.0 + s * 3.0, 40.0), 2.5, 0.8, 5.0, _wood)
	box(Vector3(-30.0, 8.0, 40.0), Vector3(9.0, 1.0, 5.0), _roof)
	# Training dummies and crates for cover.
	for i in 6:
		var p := Vector2(_rng.randf_range(-70.0, 60.0), _rng.randf_range(10.0, 70.0))
		if p.distance_to(Vector2(-30.0, 40.0)) < 12.0:
			continue
		if _rng.randf() < 0.5:
			pillar(p, 0.0, 1.2, 5.0, _wood)
			box(Vector3(p.x, 4.2, p.y), Vector3(4.0, 1.0, 1.0), _wood, _rng.randf() * PI)
		else:
			box(Vector3(p.x, 2.0, p.y), Vector3(4, 4, 4), _wood, _rng.randf() * PI)


## Fields outside the moat: haystacks, a windmill and a ring of hills at the edge.
func _fields() -> void:
	for i in 26:
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(MOAT_IN + MOAT_WIDTH + 18.0, FIELD_HALF - 30.0)
		var p := Vector2.from_angle(a) * r
		if absf(p.x) < 14.0 and p.y > 0.0:
			continue  # Keep the road to the gate clear.
		box(Vector3(p.x, 2.0, p.y), Vector3(6, 4, 6), _hay, _rng.randf() * PI)
	# A windmill in the west field: tower and four sails (solid, so you can ride them).
	var m := Vector2(-170.0, 60.0)
	pillar(m, 0.0, 12.0, 30.0, _stone)
	box(Vector3(m.x, 32.0, m.y), Vector3(14.0, 5.0, 14.0), _roof)
	for k in 4:
		box_basis(Basis(Vector3(1, 0, 0), TAU * k / 4.0 + 0.3), Vector3(m.x + 8.0, 30.0, m.y), Vector3(1.0, 22.0, 3.0), _wood)
	# Hills round the edge: grassy slopes rising to a ridge (a wall behind the ridge, out
	# of sight, keeps anyone from flying off the world).
	var sides := 28
	var hill := checker(Color(0.3, 0.42, 0.22), Color(0.32, 0.45, 0.24), 12.0)
	for i in sides:
		var a := TAU * (i + 0.5) / sides
		var d := Vector2.from_angle(a)
		var chord := 2.0 * (FIELD_HALF + 20.0) * sin(PI / sides) + 8.0
		ramp(Vector3(d.x * (FIELD_HALF - 30.0), 0.0, d.y * (FIELD_HALF - 30.0)), Vector3(d.x * (FIELD_HALF + 18.0), 42.0, d.y * (FIELD_HALF + 18.0)), chord, hill)
	ring(Vector2.ZERO, FIELD_HALF + 22.0, sides, 0.0, 95.0, 4.0, _rock)