extends "res://scripts/maps/map_builder.gd"
## "Tunnels": an underground maze. A 5 x 5 grid of lit chambers joined by roofed
## corridors: a random (fixed-seed) maze so every chamber is reachable, plus some extra
## links so there are loops to flank round. Corridors glow with strip lights in each
## row's colour; some chambers have raised mezzanines with a ramp, some a pillar.
## Everything is roofed, so it's close-quarters: the ceiling is low.

const SEED := 3301
const GRID := 5
const SPACING := 84.0
## Chamber half-size and height; corridor half-width and height.
const ROOM := 21.0
const ROOM_HEIGHT := 26.0
const HALL := 9.0
const HALL_HEIGHT := 14.0
const THICK := 2.0
## Chance of an extra corridor on top of the maze.
const EXTRA_LINKS := 0.3

const ROW_COLORS := [
	Color(0.35, 0.9, 1.0), Color(1.0, 0.55, 0.2), Color(0.6, 0.4, 1.0),
	Color(0.3, 1.0, 0.55), Color(1.0, 0.3, 0.45),
]

var _floor := checker(Color(0.26, 0.26, 0.28), Color(0.31, 0.31, 0.33), 4.0)
var _rock := panel(Color(0.24, 0.23, 0.22), Color(0.3, 0.29, 0.28), 5.0)
var _roof := solid(Color(0.14, 0.14, 0.15))
var _metal := solid(Color(0.3, 0.32, 0.35), 0.5, 0.6)
## Corridors, as pairs of grid cells [Vector2i, Vector2i].
var _links: Array = []


func _build() -> void:
	_rng.seed = SEED
	_ceiling = HALL_HEIGHT - 2.0
	var half := (GRID - 1) * SPACING / 2.0 + ROOM + 10.0
	var bounds := Rect2(-half, -half, half * 2.0, half * 2.0)
	_outline = rect_outline(bounds)
	ground(bounds.grow(10.0), _floor)
	_make_maze()
	for x in GRID:
		for y in GRID:
			_build_room(Vector2i(x, y))
	for link in _links:
		_build_hall(link[0], link[1])
	# Spawns in the corner and edge-middle chambers; turrets in four inner ones.
	for cell: Vector2i in [Vector2i(0, 0), Vector2i(4, 0), Vector2i(0, 4), Vector2i(4, 4),
			Vector2i(2, 0), Vector2i(0, 2), Vector2i(4, 2), Vector2i(2, 4)]:
		# In a corner, clear of whatever stands in the middle of the room.
		var c := _center(cell) - Vector2(ROOM - 4.0, ROOM - 4.0)
		_spawns.append(Vector3(c.x, 1.0, c.y))
	for cell: Vector2i in [Vector2i(1, 1), Vector2i(3, 1), Vector2i(1, 3), Vector2i(3, 3)]:
		var c := _center(cell) + Vector2(ROOM - 6.0, ROOM - 6.0)
		_turrets.append(Vector3(c.x, 0.0, c.y))


func _center(cell: Vector2i) -> Vector2:
	var offset := (GRID - 1) / 2.0
	return Vector2(cell.x - offset, cell.y - offset) * SPACING


func _linked(a: Vector2i, b: Vector2i) -> bool:
	for link in _links:
		if (link[0] == a and link[1] == b) or (link[0] == b and link[1] == a):
			return true
	return false


## Depth-first maze over the grid, then a few extra links for loops.
func _make_maze() -> void:
	var seen := {Vector2i(2, 2): true}
	var stack: Array[Vector2i] = [Vector2i(2, 2)]
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	while not stack.is_empty():
		var cell: Vector2i = stack.back()
		var options: Array[Vector2i] = []
		for d in dirs:
			var n: Vector2i = cell + d
			if n.x >= 0 and n.y >= 0 and n.x < GRID and n.y < GRID and not seen.has(n):
				options.append(n)
		if options.is_empty():
			stack.pop_back()
			continue
		var next: Vector2i = options[_rng.randi() % options.size()]
		seen[next] = true
		_links.append([cell, next])
		stack.append(next)
	for x in GRID:
		for y in GRID:
			for d: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
				var a := Vector2i(x, y)
				var b: Vector2i = a + d
				if b.x < GRID and b.y < GRID and not _linked(a, b) and _rng.randf() < EXTRA_LINKS:
					_links.append([a, b])


func _build_room(cell: Vector2i) -> void:
	var c := _center(cell)
	var color: Color = ROW_COLORS[cell.y % ROW_COLORS.size()]
	# Four walls, each with a doorway (and a lintel over it) if a corridor leaves that way.
	var sides := [[Vector2i(1, 0), Vector2(1, 0)], [Vector2i(-1, 0), Vector2(-1, 0)],
		[Vector2i(0, 1), Vector2(0, 1)], [Vector2i(0, -1), Vector2(0, -1)]]
	for side in sides:
		var normal: Vector2 = side[1]
		var along := Vector2(-normal.y, normal.x)
		var mid := c + normal * ROOM
		var a := mid - along * ROOM
		var b := mid + along * ROOM
		if _linked(cell, cell + side[0]):
			wall(a, mid - along * HALL, 0.0, ROOM_HEIGHT, THICK, _rock)
			wall(mid + along * HALL, b, 0.0, ROOM_HEIGHT, THICK, _rock)
			wall(mid - along * HALL, mid + along * HALL, HALL_HEIGHT, ROOM_HEIGHT - HALL_HEIGHT, THICK, _rock)
		else:
			wall(a, b, 0.0, ROOM_HEIGHT, THICK, _rock)
	box(Vector3(c.x, ROOM_HEIGHT + 1.0, c.y), Vector3(ROOM * 2.0 + THICK, 2.0, ROOM * 2.0 + THICK), _roof, 0.0, 0.0, false)
	# A lamp in the ceiling, in the row's colour.
	deco(Vector3(c.x, ROOM_HEIGHT - 0.3, c.y), Vector3(8, 0.4, 8), glow(color, 2.5))
	var light := OmniLight3D.new()
	light.position = Vector3(c.x, ROOM_HEIGHT - 4.0, c.y)
	light.light_color = color.lerp(Color.WHITE, 0.6)
	light.light_energy = 12.0
	light.omni_range = 52.0
	add_child(light)
	# Something in the room: a mezzanine with a ramp, a pillar, or crates.
	var roll := _rng.randf()
	if roll < 0.3:
		var yaw := TAU * (_rng.randi() % 4) / 4.0
		var out := Vector3(sin(yaw), 0.0, cos(yaw))
		var deck := Vector3(c.x, 0.0, c.y) - out * (ROOM - 7.0)
		box(deck + Vector3.UP * 3.5, Vector3(14, 1, 14), _metal, yaw)
		ramp(deck + out * 26.0, deck + out * 7.0 + Vector3.UP * 4.0, 8.0, _metal)
	elif roll < 0.6:
		box(Vector3(c.x, ROOM_HEIGHT / 2.0, c.y), Vector3(6, ROOM_HEIGHT, 6), _rock)
	else:
		for i in 3:
			var p := c + Vector2(_rng.randf_range(-12, 12), _rng.randf_range(-12, 12))
			var s := _rng.randf_range(3.0, 5.0)
			box(Vector3(p.x, s / 2.0, p.y), Vector3(s, s, s), _metal, _rng.randf() * TAU)


func _build_hall(a: Vector2i, b: Vector2i) -> void:
	var ca := _center(a)
	var cb := _center(b)
	var dir := (cb - ca).normalized()
	var side := Vector2(-dir.y, dir.x)
	var from := ca + dir * ROOM
	var to := cb - dir * ROOM
	var mid := (from + to) / 2.0
	var length := from.distance_to(to)
	for s: float in [-1.0, 1.0]:
		wall(from + side * HALL * s, to + side * HALL * s, 0.0, HALL_HEIGHT, THICK, _rock)
	var yaw := -dir.angle()
	box(Vector3(mid.x, HALL_HEIGHT + 1.0, mid.y), Vector3(length + THICK, 2.0, HALL * 2.0 + THICK * 2.0), _roof, yaw, 0.0, false)
	# Strip lights along both walls, in the colour of the row it leaves from.
	var color: Color = ROW_COLORS[mini(a.y, b.y) % ROW_COLORS.size()]
	var strip := glow(color, 3.0)
	for s: float in [-1.0, 1.0]:
		var p := mid + side * (HALL - 1.2) * s
		deco(Vector3(p.x, HALL_HEIGHT - 1.5, p.y), Vector3(length, 0.3, 0.3), strip, yaw)
	var light := OmniLight3D.new()
	light.position = Vector3(mid.x, HALL_HEIGHT - 3.0, mid.y)
	light.light_color = color.lerp(Color.WHITE, 0.5)
	light.light_energy = 4.0
	light.omni_range = 40.0
	add_child(light)
