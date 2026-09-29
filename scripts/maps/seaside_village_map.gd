extends "res://scripts/maps/map_builder.gd"
## "Seaside Village": a sleepy little village by the sea, laid out on a tile grid (T
## metres a tile) and built twice as big. Two cottages at the top, each with its sign and
## mailbox; the village hall at the bottom with a fountain out front and a model boat on the
## table inside; fences, flower beds and grass; the beach and the sea along the south edge;
## a wall of chunky trees round the rest, with a gap north to the road and its tall grass.

const T := 6.0
## The town is 20 x 18 tiles; tile (0, 0) is the north-west corner.
const W := 20
const H := 18

var _grass := checker(Color(0.45, 0.78, 0.35), Color(0.42, 0.74, 0.33), T)
var _path := solid(Color(0.86, 0.8, 0.6), 0.9)
var _tall_grass := solid(Color(0.2, 0.55, 0.22), 0.8)
var _trunk := solid(Color(0.45, 0.3, 0.18), 0.9)
var _tree := solid(Color(0.15, 0.5, 0.25), 0.8)
var _tree2 := solid(Color(0.22, 0.62, 0.3), 0.8)
var _wall := solid(Color(0.95, 0.92, 0.82), 0.7)
var _orange_roof := solid(Color(0.92, 0.52, 0.2), 0.6)
var _teal_roof := solid(Color(0.18, 0.58, 0.55), 0.6)
var _hall_roof := solid(Color(0.4, 0.3, 0.5), 0.6)
var _door := solid(Color(0.45, 0.28, 0.15), 0.7)
var _window := glow(Color(0.6, 0.85, 1.0), 0.8)
var _fence := solid(Color(0.98, 0.98, 0.95), 0.6)
var _sea := glow(Color(0.2, 0.5, 0.95), 0.5)
var _sand := solid(Color(0.95, 0.88, 0.62), 0.9)
var _sign := solid(Color(0.62, 0.45, 0.28), 0.8)
var _red := solid(Color(0.9, 0.12, 0.1), 0.3)
var _white := solid(Color(0.97, 0.97, 0.97), 0.3)
var _black := solid(Color(0.08, 0.08, 0.08), 0.5)
var _floor := checker(Color(0.85, 0.75, 0.55), Color(0.8, 0.7, 0.5), 2.0)
var _hall_floor := checker(Color(0.9, 0.9, 0.88), Color(0.8, 0.82, 0.82), 2.0)


## Already built at twice written size; the editing doc's "double the size" doubles it
## again, on top of that.
func map_size() -> float:
	return 4.0


## Centre of tile (tx, tz) in the map (x east, z south).
func _t(tx: float, tz: float) -> Vector2:
	return Vector2((tx - W / 2.0 + 0.5) * T, (tz - H / 2.0 + 0.5) * T)


func _build() -> void:
	_ceiling = 70.0
	var half := Vector2(W, H) * T / 2.0
	_outline = rect_outline(Rect2(-half.x, -half.y - 6.0 * T, half.x * 2.0, half.y * 2.0 + 6.0 * T))
	ground(Rect2(-half.x, -half.y, half.x * 2.0, half.y * 2.0 - 2.0 * T), _grass)
	# The beach and the sea along the bottom two rows.
	box(Vector3(0, -0.6, half.y - T * 1.5), Vector3(half.x * 2.0, 1.2, T), _sand)
	deco(Vector3(0, -1.2, half.y - T * 0.5), Vector3(half.x * 2.0, 0.2, T), _sea)
	box(Vector3(0, -3.0, half.y + T * 3.0), Vector3(half.x * 2.0, 1.0, T * 8.0), _sand)
	deco(Vector3(0, -1.4, half.y + T * 3.0), Vector3(half.x * 2.0, 0.2, T * 8.0), _sea)
	# The sandy paths.
	_strip(Rect2(9, 0, 2, 16), _path)
	_strip(Rect2(3, 7, 14, 2), _path)
	_trees()
	_house(Vector2(3, 3), _orange_roof, true)
	_house(Vector2(12, 3), _teal_roof, false)
	_hall(Vector2(11, 10))
	_fountain(_t(9.5, 12.0))
	# Fences and flower beds, like the map.
	_fence_row(Vector2(2, 9.5), Vector2(8, 9.5))
	_fence_row(Vector2(2, 14.5), Vector2(8, 14.5))
	for i in 6:
		_flower(_t(3 + i, 11))
		_flower(_t(3 + i, 12))
	_sign_post(_t(8, 6), false)
	_sign_post(_t(10.5, 9.5), true)
	# The road north: the gap in the trees, into tall grass.
	box(Vector3(_t(10, 0).x - T * 0.5, -0.5, -half.y - T * 3.0), Vector3(T * 4.0, 1.0, T * 6.0), _grass)
	for i in 12:
		var p := Vector2(_t(9, 0).x + (i % 4) * T * 0.9 - T * 0.4, -half.y - T * (1.0 + int(i / 4.0) * 1.6))
		deco(Vector3(p.x, 0.8, p.y), Vector3(T * 0.8, 1.6, T * 0.8), _tall_grass)
	for i in 8:
		_spawns.append(Vector3(_t(4 + i * 1.6, 7.5).x, 1.0, _t(4 + i * 1.6, 7.5).y + (T if i % 2 == 0 else -T)))
	_turrets.append(Vector3(_t(1, 16).x, 1.0, _t(1, 16).y - T))
	_turrets.append(Vector3(_t(18, 16).x, 1.0, _t(18, 16).y - T))


func _strip(tiles: Rect2, mat: Material) -> void:
	var a := _t(tiles.position.x, tiles.position.y) - Vector2(T, T) / 2.0
	var size := tiles.size * T
	box(Vector3(a.x + size.x / 2.0, 0.05, a.y + size.y / 2.0), Vector3(size.x, 0.1, size.y), mat)


## A wall of chunky trees round the village, leaving the road's gap at the top middle.
func _trees() -> void:
	for tx in W:
		for tz in [0, 1]:
			if tx >= 9 and tx <= 10:
				continue
			_tree_at(_t(tx, tz))
	for tz in range(2, H - 2):
		for tx in [0, W - 1]:
			_tree_at(_t(tx, tz))


func _tree_at(p: Vector2) -> void:
	box(Vector3(p.x, 1.5, p.y), Vector3(T * 0.3, 3.0, T * 0.3), _trunk)
	box(Vector3(p.x, 4.0, p.y), Vector3(T * 0.95, 3.0, T * 0.95), _tree)
	box(Vector3(p.x, 6.5, p.y), Vector3(T * 0.7, 2.4, T * 0.7), _tree2)


## A house: 4 x 3 tiles, hollow (door on the south side), windows, a pitched roof.
## The player's has a TV and table inside.
func _house(tile: Vector2, roof: Material, player: bool) -> void:
	var a := _t(tile.x, tile.y) - Vector2(T, T) / 2.0
	var size := Vector2(4, 3) * T
	var c := a + size / 2.0
	var h := 9.0
	box(Vector3(c.x, 0.1, c.y), Vector3(size.x, 0.2, size.y), _floor)
	wall(Vector2(a.x, a.y), Vector2(a.x + size.x, a.y), 0.0, h, 0.6, _wall)
	wall(Vector2(a.x, a.y), Vector2(a.x, a.y + size.y), 0.0, h, 0.6, _wall)
	wall(Vector2(a.x + size.x, a.y), Vector2(a.x + size.x, a.y + size.y), 0.0, h, 0.6, _wall)
	# South wall with the door (one tile wide) left of middle.
	var door := a.x + T * 1.5
	wall(Vector2(a.x, a.y + size.y), Vector2(door - T * 0.45, a.y + size.y), 0.0, h, 0.6, _wall)
	wall(Vector2(door + T * 0.45, a.y + size.y), Vector2(a.x + size.x, a.y + size.y), 0.0, h, 0.6, _wall)
	wall(Vector2(door - T * 0.45, a.y + size.y), Vector2(door + T * 0.45, a.y + size.y), 6.0, h - 6.0, 0.6, _wall)
	deco(Vector3(door, 3.0, a.y + size.y + 0.35), Vector3(T * 0.9, 0.2, 0.1), _door)
	for x: float in [a.x + T * 3.0]:
		deco(Vector3(x, 5.0, a.y + size.y + 0.35), Vector3(T * 0.8, 2.4, 0.1), _window)
	# Pitched roof: two slopes meeting over the middle.
	for s: float in [-1.0, 1.0]:
		box(Vector3(c.x, h + 2.2, c.y + s * size.y / 4.0), Vector3(size.x + 2.0, 0.6, size.y / 2.0 + 2.4), roof, 0.0, s * 0.55, false)
	if player:
		box(Vector3(a.x + T * 3.2, 1.6, a.y + T * 0.8), Vector3(3.2, 3.2, 2.0), _black)
		box(Vector3(c.x, 1.4, c.y + 1.0), Vector3(6.0, 0.4, 4.0), _door)
		for sx: float in [-1.0, 1.0]:
			for sz: float in [-1.0, 1.0]:
				box(Vector3(c.x + sx * 2.6, 0.6, c.y + 1.0 + sz * 1.6), Vector3(0.4, 1.2, 0.4), _door)
	# Mailbox by the door.
	box(Vector3(door - T, 1.4, a.y + size.y + T * 0.7), Vector3(0.5, 2.8, 0.5), _sign)
	box(Vector3(door - T, 3.0, a.y + size.y + T * 0.7), Vector3(1.6, 1.0, 1.2), _white if player else _red)


## The village hall: 6 x 4 tiles, a plum roof, a table with a model boat, bookshelves.
func _hall(tile: Vector2) -> void:
	var a := _t(tile.x, tile.y) - Vector2(T, T) / 2.0
	var size := Vector2(6, 4) * T
	var c := a + size / 2.0
	var h := 11.0
	box(Vector3(c.x, 0.1, c.y), Vector3(size.x, 0.2, size.y), _hall_floor)
	wall(Vector2(a.x, a.y), Vector2(a.x + size.x, a.y), 0.0, h, 0.7, _wall)
	wall(Vector2(a.x, a.y + size.y), Vector2(a.x + size.x, a.y + size.y), 0.0, h, 0.7, _wall)
	wall(Vector2(a.x + size.x, a.y), Vector2(a.x + size.x, a.y + size.y), 0.0, h, 0.7, _wall)
	# The door faces west onto the path.
	wall(Vector2(a.x, a.y), Vector2(a.x, c.y - T * 0.5), 0.0, h, 0.7, _wall)
	wall(Vector2(a.x, c.y + T * 0.5), Vector2(a.x, a.y + size.y), 0.0, h, 0.7, _wall)
	wall(Vector2(a.x, c.y - T * 0.5), Vector2(a.x, c.y + T * 0.5), 7.0, h - 7.0, 0.7, _wall)
	for i in 3:
		deco(Vector3(a.x + T * (1.5 + i * 1.5), 6.0, a.y - 0.4), Vector3(T * 0.8, 2.6, 0.1), _window)
	for s: float in [-1.0, 1.0]:
		box(Vector3(c.x, h + 2.5, c.y + s * size.y / 4.0), Vector3(size.x + 2.0, 0.6, size.y / 2.0 + 2.6), _hall_roof, 0.0, s * 0.5, false)
	# The table and the model boat on it (hull, cabin, mast and a sail).
	box(Vector3(c.x + T, 2.0, c.y), Vector3(8.0, 0.5, 4.0), _white)
	box(Vector3(c.x + T, 2.8, c.y), Vector3(4.6, 1.0, 1.4), _door)
	box(Vector3(c.x + T - 0.6, 3.6, c.y), Vector3(1.4, 0.8, 1.0), _white)
	box(Vector3(c.x + T + 0.6, 5.0, c.y), Vector3(0.15, 3.6, 0.15), _door)
	deco(Vector3(c.x + T + 1.3, 5.2, c.y), Vector3(1.4, 2.6, 0.05), _white)
	# Bookshelves along the back wall.
	for i in 4:
		box(Vector3(a.x + T * (1.0 + i * 1.3), 3.0, a.y + 1.4), Vector3(T, 6.0, 1.8), _sign)


func _fence_row(from: Vector2, to: Vector2) -> void:
	var a := _t(from.x, from.y)
	var b := _t(to.x, to.y)
	wall(a, b, 1.2, 0.5, 0.4, _fence)
	var n := int(a.distance_to(b) / 2.0)
	for i in n + 1:
		var p := a.lerp(b, float(i) / n)
		box(Vector3(p.x, 1.1, p.y), Vector3(0.5, 2.2, 0.5), _fence)


func _flower(p: Vector2) -> void:
	for k in 4:
		var q := p + Vector2(((k % 2) - 0.5) * T * 0.5, (int(k / 2.0) - 0.5) * T * 0.5)
		deco(Vector3(q.x, 0.6, q.y), Vector3(1.0, 1.0, 1.0), _red if k % 2 == 0 else _white)


func _sign_post(p: Vector2, big: bool) -> void:
	box(Vector3(p.x, 1.2, p.y), Vector3(0.5, 2.4, 0.5), _sign)
	box(Vector3(p.x, 2.8, p.y), Vector3(3.6 if big else 2.6, 2.0, 0.4), _sign)


## A round stone fountain with water in the bowl and a spout in the middle.
func _fountain(p: Vector2) -> void:
	var stone := solid(Color(0.72, 0.72, 0.7), 0.8)
	ring(p, 5.0, 12, 0.0, 1.4, 0.8, stone)
	disc(Vector3(p.x, 0.3, p.y), 4.6, 0.3, _sea, 2)
	pillar(p, 0.0, 1.0, 3.2, stone)
	box(Vector3(p.x, 3.4, p.y), Vector3(2.4, 0.4, 2.4), stone)
	deco(Vector3(p.x, 4.2, p.y), Vector3(0.5, 1.2, 0.5), _sea)
