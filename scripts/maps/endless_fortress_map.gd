extends "res://scripts/maps/map_builder.gd"
## "Endless Fortress": an impossible fortress of wooden floors, tatami rooms, paper screens
## and stairs hanging at every height in the dark. It goes on forever in every direction,
## up and down too... or seems to. It's one block of castle WIDTH across that repeats:
## leave through any side (or fall out of the bottom) and you come back in through the
## opposite one at the same speed, and copies of the block all round (lost in the gloom)
## hide the seams. Pillars and beams run the whole way across, so they look endless.

const WIDTH := 220.0
const HALF := WIDTH / 2.0

var _floor := checker(Color(0.62, 0.55, 0.32), Color(0.56, 0.5, 0.29), 2.0)
var _dark_wood := solid(Color(0.22, 0.11, 0.05), 0.7)
var _wood := solid(Color(0.42, 0.24, 0.12), 0.75)
var _lacquer := solid(Color(0.55, 0.07, 0.05), 0.35)
var _paper := glow(Color(1.0, 0.86, 0.62), 0.7)
var _lantern := glow(Color(1.0, 0.55, 0.2), 4.0)
var _roof := solid(Color(0.18, 0.2, 0.24), 0.6)

var _platforms: Array[Vector3] = []


## Roofed over / lit by lamps: no sun shadows here (graphics.gd).
func is_indoor() -> bool:
	return true


func _build() -> void:
	_wrap = Vector3(WIDTH, WIDTH, WIDTH)
	# No ceiling and no falling off: you just go round.
	_ceiling = 1.0e6
	_fall = -1.0e6
	_outline = rect_outline(Rect2(-HALF, -HALF, WIDTH, WIDTH))
	_rng.seed = 1917
	# The hall in the middle where everyone starts.
	_room(Vector3(0, 0, 0), Vector2(46.0, 40.0), true)
	# Rooms and landings at every height.
	var tries := 0
	while _platforms.size() < 46 and tries < 400:
		tries += 1
		var p := Vector3(_rng.randf_range(-HALF + 12.0, HALF - 12.0), _rng.randf_range(-HALF + 8.0, HALF - 8.0), _rng.randf_range(-HALF + 12.0, HALF - 12.0))
		var size := Vector2(_rng.randf_range(12.0, 28.0), _rng.randf_range(10.0, 22.0))
		var clear := true
		for q in _platforms:
			if absf(q.y - p.y) < 14.0 and Vector2(q.x - p.x, q.z - p.z).length() < 30.0:
				clear = false
				break
		if clear:
			_room(p, size, _rng.randf() < 0.35)
	# Stairs climbing off landings in all directions.
	for i in 22:
		var from: Vector3 = _platforms[_rng.randi() % _platforms.size()]
		var dir := Vector2.from_angle(_rng.randi_range(0, 3) * PI / 2.0)
		var up := _rng.randf() < 0.5
		var low := from + Vector3(dir.x, 0, dir.y) * 8.0 + (Vector3.ZERO if up else Vector3.DOWN * 14.0)
		stairs(low, dir if up else -dir, 14, 1.0, 1.4, 5.0, _wood)
	# Endless pillars (top to bottom of the block) and beams (side to side).
	for i in 16:
		var x := _rng.randf_range(-HALF, HALF)
		var z := _rng.randf_range(-HALF, HALF)
		box(Vector3(x, 0, z), Vector3(2.4, WIDTH, 2.4), _lacquer if i % 3 == 0 else _dark_wood)
	for i in 10:
		var y := _rng.randf_range(-HALF + 5.0, HALF - 5.0)
		var c := _rng.randf_range(-HALF, HALF)
		if i % 2 == 0:
			box(Vector3(0, y, c), Vector3(WIDTH, 1.6, 2.0), _dark_wood)
		else:
			box(Vector3(c, y, 0), Vector3(2.0, 1.6, WIDTH), _dark_wood)
	for i in 8:
		var p: Vector3 = _platforms[i % _platforms.size()]
		_spawns.append(p + Vector3(_rng.randf_range(-4.0, 4.0), 1.5, _rng.randf_range(-4.0, 4.0)))
	# No lamps: a light would only be in this block and not its copies, and the change in
	# light across the seam would give the loop away. Glowing lanterns and warm ambient.


## A room: a tatami floor in a dark wooden frame, paper screens on some sides (some rooms
## upside down, their screens hanging below), lanterns at the corners.
func _room(p: Vector3, size: Vector2, screens: bool) -> void:
	_platforms.append(p)
	box(p + Vector3(0, -0.6, 0), Vector3(size.x + 1.0, 1.2, size.y + 1.0), _dark_wood)
	deco(p + Vector3(0, 0.02, 0), Vector3(size.x, 0.05, size.y), _floor)
	var upside := _rng.randf() < 0.3
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			deco(p + Vector3(sx * size.x / 2.0, 1.0 if not upside else -2.0, sz * size.y / 2.0), Vector3(0.9, 1.4, 0.9), _lantern)
	if not screens:
		return
	var side := _rng.randi() % 4
	var h := 7.0
	var y := p.y + (0.0 if not upside else -h - 1.2)
	var corners := [Vector2(-size.x, -size.y) / 2.0, Vector2(size.x, -size.y) / 2.0, Vector2(size.x, size.y) / 2.0, Vector2(-size.x, size.y) / 2.0]
	for k in 4:
		if k == side:
			continue
		var a: Vector2 = corners[k] + Vector2(p.x, p.z)
		var b: Vector2 = corners[(k + 1) % 4] + Vector2(p.x, p.z)
		# The screen: paper panels in a wooden frame. You can roll through the paper, so
		# the rails along its bottom and top are decoration too (a solid rail the ball's
		# height stopped dashes dead); only the posts are solid.
		var mid := (a + b) / 2.0
		var d := b - a
		deco(Vector3(mid.x, y + h - 0.3, mid.y), Vector3(d.length() + 0.5, 0.6, 0.5), _dark_wood, -d.angle())
		deco(Vector3(mid.x, y + 0.25, mid.y), Vector3(d.length() + 0.5, 0.5, 0.5), _dark_wood, -d.angle())
		deco(Vector3(mid.x, y + h / 2.0, mid.y), Vector3(d.length(), h - 1.2, 0.2), _paper, -d.angle())
		for t in 5:
			var q := a.lerp(b, t / 4.0)
			box(Vector3(q.x, y + h / 2.0, q.y), Vector3(0.5, h, 0.5), _dark_wood)
	# A roof over the right-way-up rooms: two slopes of dark tiles.
	if not upside:
		for s: float in [-1.0, 1.0]:
			box(p + Vector3(0, h + 2.0, s * size.y / 4.0), Vector3(size.x + 3.0, 0.5, size.y / 2.0 + 2.0), _roof, 0.0, s * 0.35, false)
