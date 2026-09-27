extends "res://scripts/maps/map_builder.gd"
## "The Parthenon": the Acropolis of Athens. A rocky plateau rising out of an olive grove,
## climbed by a zig-zag ramp to the Propylaea gateway. On top: the Parthenon as it stands
## today, a roofless ruin (8 x 17 marble columns on a stepped base, a few broken, drums
## lying in the grass, the gables still up), its inner hall with a giant Athena, plus the
## Erechtheion with its porch of maidens and the little Temple of Athena Nike.
## Written at real size (the Parthenon is 69.5 x 30.9 m, columns 10.4 m) and built twice
## as big.

const TOP := 20.0
const LONG := 69.5
const WIDE := 30.9
const COL_H := 10.4

var _marble := solid(Color(0.93, 0.9, 0.83), 0.55)
var _worn := solid(Color(0.86, 0.8, 0.7), 0.7)
var _rock := solid(Color(0.62, 0.54, 0.44), 0.95)
var _rock_dark := solid(Color(0.5, 0.43, 0.35), 0.95)
var _pave := solid(Color(0.7, 0.63, 0.52), 0.9)
var _grass := checker(Color(0.55, 0.55, 0.3), Color(0.5, 0.5, 0.27), 5.0)
var _olive := solid(Color(0.4, 0.47, 0.28), 0.9)
var _trunk := solid(Color(0.4, 0.33, 0.25), 0.9)
var _gold := solid(Color(0.95, 0.75, 0.3), 0.3, 0.8)
var _ivory := solid(Color(0.96, 0.93, 0.85), 0.3)


func map_size() -> float:
	return 2.0


func _build() -> void:
	_ceiling = 90.0
	_outline = rect_outline(Rect2(-150, -95, 300, 190))
	ground(Rect2(-150, -95, 300, 190), _grass)
	_acropolis()
	_parthenon(Vector3(8.0, TOP, 0.0))
	_erechtheion(Vector3(-22.0, TOP, 38.0))
	_nike(Vector3(-102.0, TOP, -30.0))
	_propylaea(Vector3(-92.0, TOP, 0.0))
	_olives()
	for i in 4:
		_spawns.append(Vector3(-40.0 + i * 25.0, TOP + 1.0, -42.0))
		_spawns.append(Vector3(-40.0 + i * 25.0, TOP + 1.0, 50.0))
	_turrets.append(Vector3(110, 1, 70))
	_turrets.append(Vector3(110, 1, -70))
	_turrets.append(Vector3(-130, 1, 70))


## The rock: a plateau of uneven slabs with cliffs, and a ramp zig-zagging up the west end.
func _acropolis() -> void:
	box(Vector3(0, TOP / 2.0, 0), Vector3(220.0, TOP, 130.0), _rock)
	# Rougher edges: blocks sticking out of the cliffs at random.
	for i in 40:
		var side := _rng.randi() % 4
		var along := _rng.randf_range(-0.95, 0.95)
		var h := _rng.randf_range(6.0, TOP - 1.0)
		var p := Vector3.ZERO
		match side:
			0: p = Vector3(along * 110.0, h / 2.0, 65.0)
			1: p = Vector3(along * 110.0, h / 2.0, -65.0)
			2: p = Vector3(110.0, h / 2.0, along * 65.0)
			_: p = Vector3(-110.0, h / 2.0, along * 65.0)
		box(p, Vector3(_rng.randf_range(8, 18), h, _rng.randf_range(8, 18)), _rock_dark, _rng.randf() * TAU)
	# Paving on top, a little uneven.
	for x in range(-100, 101, 25):
		for z in range(-55, 56, 22):
			box(Vector3(x, TOP + _rng.randf_range(-0.2, 0.15), z), Vector3(25.5, 0.5, 22.5), _pave)
	# The way up: three ramps zig-zagging up the west cliff.
	ramp(Vector3(-140.0, 0.0, 60.0), Vector3(-140.0, 7.0, -20.0), 12.0, _worn)
	ramp(Vector3(-128.0, 7.0, -20.0), Vector3(-128.0, 14.0, 50.0), 12.0, _worn)
	ramp(Vector3(-116.0, 14.0, 50.0), Vector3(-116.0, TOP, 0.0), 12.0, _worn)
	box(Vector3(-140.0, 3.5, -26.0), Vector3(12.0, 7.0, 12.0), _rock)
	box(Vector3(-128.0, 7.0, 56.0), Vector3(12.0, 14.0, 12.0), _rock)


## A marble column: a fluted shaft (two squares turned 45 degrees to each other), a
## capital slab on top. `broken` shortens it and leaves the top off.
func _column(p: Vector3, height: float, width: float, broken := false) -> void:
	var h := height * (_rng.randf_range(0.35, 0.7) if broken else 1.0)
	box(p + Vector3(0, h / 2.0, 0), Vector3(width, h, width), _marble)
	box(p + Vector3(0, h / 2.0, 0), Vector3(width, h, width), _marble, PI / 4.0)
	if not broken:
		box(p + Vector3(0, height - 0.3, 0), Vector3(width * 1.35, 0.6, width * 1.35), _marble)


func _parthenon(at: Vector3) -> void:
	# Three steps up.
	for i in 3:
		box(at + Vector3(0, 0.25 + i * 0.5, 0), Vector3(LONG + 6.0 - i * 2.0, 0.5, WIDE + 6.0 - i * 2.0), _marble)
	var base := at + Vector3(0, 1.5, 0)
	box(base + Vector3(0, -0.25, 0), Vector3(LONG, 0.5, WIDE), _marble)
	var broken := [3, 11, 20, 27, 34, 38]
	var n := 0
	# 17 along each long side, 8 across each end (corners shared).
	for i in 17:
		var x := lerpf(-LONG / 2.0 + 1.2, LONG / 2.0 - 1.2, i / 16.0)
		for s: float in [-1.0, 1.0]:
			_column(base + Vector3(x, 0, s * (WIDE / 2.0 - 1.2)), COL_H, 1.9, broken.has(n))
			n += 1
	for i in range(1, 7):
		var z := lerpf(-WIDE / 2.0 + 1.2, WIDE / 2.0 - 1.2, i / 7.0)
		for s: float in [-1.0, 1.0]:
			_column(base + Vector3(s * (LONG / 2.0 - 1.2), 0, z), COL_H, 1.9, broken.has(n))
			n += 1
	# The entablature still stands on the ends and part of each side.
	var top := base.y + COL_H
	for s: float in [-1.0, 1.0]:
		box(Vector3(base.x + s * (LONG / 2.0 - 1.2), top + 1.4, base.z), Vector3(3.0, 2.8, WIDE), _worn, 0.0, 0.0, false)
		box(Vector3(base.x - 12.0, top + 1.4, base.z + s * (WIDE / 2.0 - 1.2)), Vector3(40.0, 2.8, 3.0), _worn, 0.0, 0.0, false)
		# The gable over each end: a stepped triangle.
		for k in 6:
			var w := WIDE * (1.0 - k / 6.0)
			box(Vector3(base.x + s * (LONG / 2.0 - 1.2), top + 3.2 + k * 0.9, base.z), Vector3(2.0, 0.9, w), _marble, 0.0, 0.0, false)
	# The inner hall (cella): walls with a doorway at the east end.
	var cx := base.x
	for s: float in [-1.0, 1.0]:
		wall(Vector2(cx - 22.0, base.z + s * 9.0), Vector2(cx + 22.0, base.z + s * 9.0), base.y, COL_H - 1.0, 1.4, _worn)
	wall(Vector2(cx - 22.0, base.z - 9.0), Vector2(cx - 22.0, base.z + 9.0), base.y, COL_H - 1.0, 1.4, _worn)
	wall(Vector2(cx + 22.0, base.z - 9.0), Vector2(cx + 22.0, base.z - 3.0), base.y, COL_H - 1.0, 1.4, _worn)
	wall(Vector2(cx + 22.0, base.z + 3.0), Vector2(cx + 22.0, base.z + 9.0), base.y, COL_H - 1.0, 1.4, _worn)
	# Athena Parthenos: gold and ivory, 12 m tall, with her shield and spear.
	var a := Vector3(cx - 14.0, base.y, base.z)
	box(a + Vector3(0, 0.75, 0), Vector3(5.0, 1.5, 5.0), _marble)
	box(a + Vector3(0, 5.0, 0), Vector3(3.4, 7.0, 2.6), _gold)
	box(a + Vector3(0, 9.5, 0), Vector3(2.4, 2.0, 2.0), _ivory)
	box(a + Vector3(0, 11.0, 0), Vector3(2.8, 1.2, 2.6), _gold)
	box(a + Vector3(0.4, 3.5, 2.2), Vector3(0.4, 4.0, 4.0), _gold)
	box(a + Vector3(0.4, 6.0, -2.2), Vector3(0.3, 12.0, 0.3), _gold)
	# Column drums lying about in the grass round it.
	for i in 12:
		var p := Vector3(at.x + _rng.randf_range(-45.0, 45.0), TOP + 1.0, at.z + (1.0 if i % 2 == 0 else -1.0) * _rng.randf_range(22.0, 34.0))
		box(p, Vector3(1.9, 1.9, _rng.randf_range(1.5, 3.0)), _marble, _rng.randf() * TAU)


## The Erechtheion: a small temple with a porch held up by six stone maidens.
func _erechtheion(at: Vector3) -> void:
	box(at + Vector3(0, 0.5, 0), Vector3(24.0, 1.0, 12.0), _marble)
	for s: float in [-1.0, 1.0]:
		wall(Vector2(at.x - 11.0, at.z + s * 5.5), Vector2(at.x + 11.0, at.z + s * 5.5), at.y + 1.0, 8.0, 1.0, _marble)
	wall(Vector2(at.x - 11.0, at.z - 5.5), Vector2(at.x - 11.0, at.z + 5.5), at.y + 1.0, 8.0, 1.0, _marble)
	for i in 6:
		_column(at + Vector3(11.5 + 1.5, 1.0, -4.5 + i * 1.8), 8.0, 1.0)
	# The porch of the maidens (caryatids), on the south side.
	box(at + Vector3(4.0, 3.0, -9.0), Vector3(8.0, 2.0, 5.0), _marble)
	for i in 6:
		var p := at + Vector3(1.0 + (i % 3) * 3.0, 4.0, -7.5 - int(i / 3.0) * 2.8)
		box(p + Vector3(0, 1.7, 0), Vector3(0.9, 3.4, 0.9), _ivory)
		box(p + Vector3(0, 3.8, 0), Vector3(0.7, 0.8, 0.7), _ivory)
	box(at + Vector3(4.0, 8.4, -9.0), Vector3(9.0, 0.8, 6.0), _marble, 0.0, 0.0, false)


func _nike(at: Vector3) -> void:
	box(at + Vector3(0, 0.5, 0), Vector3(10.0, 1.0, 7.0), _marble)
	for i in 4:
		for s: float in [-1.0, 1.0]:
			_column(at + Vector3(-4.0 + i * 2.7, 1.0, s * 2.8), 5.0, 0.7)
	box(at + Vector3(0, 6.4, 0), Vector3(10.0, 1.0, 7.0), _marble, 0.0, 0.0, false)


## The gateway at the top of the ramp: a row of columns under a heavy lintel.
func _propylaea(at: Vector3) -> void:
	for i in 6:
		_column(at + Vector3(0, 0, -15.0 + i * 6.0), 9.0, 1.6)
		_column(at + Vector3(8.0, 0, -15.0 + i * 6.0), 9.0, 1.6)
	box(at + Vector3(4.0, 9.8, 0), Vector3(12.0, 1.6, 34.0), _worn, 0.0, 0.0, false)


func _olives() -> void:
	for i in 60:
		var p := Vector2(_rng.randf_range(-145.0, 145.0), _rng.randf_range(-90.0, 90.0))
		if absf(p.x) < 118.0 and absf(p.y) < 72.0:
			continue
		if p.x < -110.0 and p.y > -30.0:
			continue  # Keep the ramp clear.
		box(Vector3(p.x, 2.0, p.y), Vector3(1.0, 4.0, 1.0), _trunk, _rng.randf() * TAU)
		box(Vector3(p.x, 5.0, p.y), Vector3(6.0, 3.0, 6.0), _olive, _rng.randf() * TAU)
		box(Vector3(p.x, 6.2, p.y), Vector3(4.0, 2.0, 4.0), _olive, _rng.randf() * TAU)
