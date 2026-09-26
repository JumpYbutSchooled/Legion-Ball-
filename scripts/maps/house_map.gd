extends "res://scripts/maps/map_builder.gd"
## "The House": an ordinary one-storey house at 10:1 scale, so you're the size of a
## marble in it. A hallway runs through the middle; the living room and the kitchen are
## on one side, the bedroom, bathroom and office on the other, with doorways (9 m wide,
## 21 m tall) off the hall. Everything is furniture-sized: couches, tables and chairs to
## roll under, counters and shelves to climb (up leaning ironing boards and cutting
## boards).
## VENTS: an air duct runs along the top of the hallway, with a branch into every room
## that opens above its tallest piece of furniture (fridge, wardrobe, shelves), and
## floor-level vents run through the walls between rooms that don't share a door.

const SEED := 1010
const HX := 80.0  # Half the house's width (x).
const HZ := 60.0  # Half its depth (z).
const HALL := 6.0  # Half the hallway's width.
const H := 25.0  # Ceiling height.
const WALL := 2.0
const DOOR_W := 9.0
const DOOR_H := 21.0
## The duct: inside size, and the height of its floor.
const DUCT_W := 6.0
const DUCT_H := 5.0
const DUCT_Y := 18.0

var _floor_wood := checker(Color(0.55, 0.38, 0.22), Color(0.5, 0.34, 0.2), 3.0)
var _tile := checker(Color(0.85, 0.86, 0.88), Color(0.72, 0.74, 0.78), 3.0)
var _carpet := checker(Color(0.35, 0.38, 0.5), Color(0.33, 0.36, 0.48), 2.0)
var _wallpaper := panel(Color(0.86, 0.82, 0.72), Color(0.8, 0.76, 0.66), 6.0)
var _ceiling_mat := solid(Color(0.92, 0.92, 0.9))
var _duct := panel(Color(0.62, 0.64, 0.66), Color(0.5, 0.52, 0.55), 2.0)
var _grille := solid(Color(0.8, 0.82, 0.84), 0.4, 0.6)
var _wood := solid(Color(0.45, 0.3, 0.18))
var _wood_light := solid(Color(0.7, 0.55, 0.36))
var _fabric := solid(Color(0.25, 0.4, 0.55))
var _white := solid(Color(0.92, 0.93, 0.95), 0.3)
var _steel := solid(Color(0.7, 0.72, 0.75), 0.3, 0.8)
var _black := solid(Color(0.08, 0.08, 0.09), 0.4)
var _duvet := solid(Color(0.75, 0.25, 0.3))


func _build() -> void:
	_rng.seed = SEED
	_ceiling = H - 2.5
	_outline = rect_outline(Rect2(-HX, -HZ, HX * 2.0, HZ * 2.0))
	_floors()
	_walls()
	# The roof: over everything, left off the minimap so the rooms show.
	box(Vector3(0, H + 1.0, 0), Vector3(HX * 2.0 + 8.0, 2.0, HZ * 2.0 + 8.0), _ceiling_mat, 0.0, 0.0, false)
	_ducts()
	_living_room()
	_kitchen()
	_bedroom()
	_bathroom()
	_office()
	_lights()
	for p in [Vector2(-60, -40), Vector2(-20, -25), Vector2(40, -25), Vector2(65, -45),
			Vector2(-60, 40), Vector2(0, 45), Vector2(50, 40), Vector2(-30, 0)]:
		_spawns.append(Vector3(p.x, 1.0, p.y))
	# Turrets on top of the tall furniture.
	_turrets.append(Vector3(-75.0, 18.0, -45.0))
	_turrets.append(Vector3(75.0, 9.0, -25.0))
	_turrets.append(Vector3(-25.0, 10.0, 56.0))
	_turrets.append(Vector3(70.0, 18.0, 52.0))


func _floors() -> void:
	box(Vector3(0, -1.0, 0), Vector3(HX * 2.0 + 8.0, 2.0, HZ * 2.0 + 8.0), _floor_wood)
	# Kitchen and bathroom tiles, living room rug, bedroom carpet (thin layers on top).
	deco(Vector3(45.0, 0.02, -33.0), Vector3(70.0, 0.04, 54.0), _tile)
	deco(Vector3(2.5, 0.02, 33.0), Vector3(35.0, 0.04, 54.0), _tile)
	deco(Vector3(-45.0, 0.02, 33.0), Vector3(66.0, 0.04, 50.0), _carpet)
	deco(Vector3(-35.0, 0.03, -33.0), Vector3(40.0, 0.04, 30.0), solid(Color(0.6, 0.2, 0.15)))


## Outer walls, the two hallway walls (with doorways and duct holes), and the walls
## between rooms (with floor vents).
func _walls() -> void:
	# Outer walls.
	for k in 4:
		var yaw := TAU * k / 4.0
		var out := Vector3(sin(yaw), 0.0, cos(yaw))
		var reach := HZ if k % 2 == 0 else HX
		var span := HX if k % 2 == 0 else HZ
		box(out * (reach + WALL / 2.0) + Vector3.UP * H / 2.0, Vector3(span * 2.0 + WALL * 2.0, H, WALL), _wallpaper, yaw)
	# Hallway walls: doors and the duct branches' holes.
	# North side (z = -HALL): living room door at x -40, kitchen door at 45; duct holes at
	# x -72 (over the bookshelf) and 72 (over the fridge).
	_wall_x(-HALL, [[-40.0, DOOR_W, 0.0, DOOR_H], [45.0, DOOR_W, 0.0, DOOR_H],
		[-72.0, DUCT_W, DUCT_Y, DUCT_Y + DUCT_H], [72.0, DUCT_W, DUCT_Y, DUCT_Y + DUCT_H]])
	# South side (z = HALL): bedroom door -45, bathroom door 0, office door 50; ducts over
	# the wardrobe (-50... its branch runs to -60), the bathroom cabinet (8) and the
	# office shelves (72).
	_wall_x(HALL, [[-40.0, DOOR_W, 0.0, DOOR_H], [0.0, DOOR_W, 0.0, DOOR_H], [50.0, DOOR_W, 0.0, DOOR_H],
		[-60.0, DUCT_W, DUCT_Y, DUCT_Y + DUCT_H], [12.0, DUCT_W, DUCT_Y, DUCT_Y + DUCT_H], [72.0, DUCT_W, DUCT_Y, DUCT_Y + DUCT_H]])
	# Between the living room and kitchen: a wide archway. Between bedroom/bathroom and
	# bathroom/office: walls with a floor vent each.
	_wall_z(10.0, -HZ, -HALL, [[-33.0, 22.0, 0.0, DOOR_H]])
	_wall_z(-15.0, HALL, HZ, [[33.0, 5.0, 0.0, 4.0]])
	_wall_z(20.0, HALL, HZ, [[40.0, 5.0, 0.0, 4.0]])
	# Grilles over the floor vents (bars you can see, with gaps to roll through... the
	# vent is 5 wide, the bars thin).
	for v in [Vector2(-15.0, 33.0), Vector2(20.0, 40.0)]:
		for side: float in [-1.0, 1.0]:
			for b in 3:
				deco(Vector3(v.x + side * (WALL / 2.0 + 0.1), 3.0 - b * 1.2, v.y), Vector3(0.1, 0.25, 5.0), _grille)
		# A short square duct through the wall, poking out both sides.
		_duct_run(Vector3(v.x - 4.0, 0.0, v.y), Vector3(v.x + 4.0, 0.0, v.y), 5.0, 4.0)


## A wall along x at `z` (full house width) with `holes`: [centre x, width, bottom, top].
func _wall_x(z: float, holes: Array) -> void:
	_wall_run(Vector2(-HX, z), Vector2(HX, z), holes)


## A wall along z at `x` from z0 to z1 with holes: [centre z, width, bottom, top].
func _wall_z(x: float, z0: float, z1: float, holes: Array) -> void:
	_wall_run(Vector2(x, z0), Vector2(x, z1), holes)


## A straight wall from a to b (x, z) with rectangular holes cut in it. Hole centres are
## given as the coordinate along the wall (x for walls along x, z for walls along z).
func _wall_run(a: Vector2, b: Vector2, holes: Array) -> void:
	var along_x := absf(b.x - a.x) > absf(b.y - a.y)
	var start := a.x if along_x else a.y
	var end := b.x if along_x else b.y
	var sorted := holes.duplicate()
	sorted.sort_custom(func(p: Array, q: Array) -> bool: return p[0] < q[0])
	var cursor := start
	for hole in sorted:
		var h0: float = hole[0] - hole[1] / 2.0
		var h1: float = hole[0] + hole[1] / 2.0
		_wall_piece(a, along_x, cursor, h0, 0.0, H)
		_wall_piece(a, along_x, h0, h1, 0.0, hole[2])
		_wall_piece(a, along_x, h0, h1, hole[3], H)
		cursor = h1
	_wall_piece(a, along_x, cursor, end, 0.0, H)


func _wall_piece(a: Vector2, along_x: bool, s0: float, s1: float, y0: float, y1: float) -> void:
	if s1 - s0 < 0.05 or y1 - y0 < 0.05:
		return
	var mid := (s0 + s1) / 2.0
	var center := Vector3(mid, (y0 + y1) / 2.0, a.y) if along_x else Vector3(a.x, (y0 + y1) / 2.0, mid)
	var size := Vector3(s1 - s0, y1 - y0, WALL) if along_x else Vector3(WALL, y1 - y0, s1 - s0)
	box(center, size, _wallpaper)


## A square duct (floor, roof, two sides) from a to b: a and b are points on the middle of
## its floor. It can slope.
func _duct_run(a: Vector3, b: Vector3, width := DUCT_W, height := DUCT_H, with_sides := true) -> void:
	var along := (b - a).normalized()
	var side := along.cross(Vector3.UP).normalized()
	var up := side.cross(along).normalized()
	var basis := Basis(side, up, along)
	var length := a.distance_to(b)
	var mid := (a + b) / 2.0
	var t := 0.6
	box_basis(basis, mid - up * t / 2.0, Vector3(width + t * 2.0, t, length), _duct, false)
	box_basis(basis, mid + up * (height + t / 2.0), Vector3(width + t * 2.0, t, length), _duct, false)
	if not with_sides:
		return
	for s: float in [-1.0, 1.0]:
		box_basis(basis, mid + up * height / 2.0 + side * s * (width / 2.0 + t / 2.0), Vector3(t, height, length), _duct, false)


## The trunk along the hallway ceiling, and a short branch through each hallway wall
## into a room, ending just past the wall right over the top of the room's tallest
## piece of furniture (which stands against the wall, its top level with the duct floor).
const BRANCHES := [[-72.0, -1.0], [72.0, -1.0], [-60.0, 1.0], [12.0, 1.0], [72.0, 1.0]]
const BRANCH_END := HALL + WALL / 2.0 + 1.0


func _ducts() -> void:
	# The trunk's floor and roof; its sides have gaps where the branches join.
	_duct_run(Vector3(-HX + 4.0, DUCT_Y, 0.0), Vector3(HX - 4.0, DUCT_Y, 0.0), DUCT_W, DUCT_H, false)
	for s: float in [-1.0, 1.0]:
		var cursor := -HX + 4.0
		for branch in BRANCHES:
			if branch[1] != s:
				continue
			_trunk_side(s, cursor, branch[0] - DUCT_W / 2.0)
			cursor = branch[0] + DUCT_W / 2.0
		_trunk_side(s, cursor, HX - 4.0)
	for branch in BRANCHES:
		var x: float = branch[0]
		var s: float = branch[1]
		_duct_run(Vector3(x, DUCT_Y, s * (DUCT_W / 2.0 + 0.6)), Vector3(x, DUCT_Y, s * BRANCH_END))
		# A grille frame round the opening.
		for e: float in [-1.0, 1.0]:
			deco(Vector3(x + e * (DUCT_W / 2.0 + 0.3), DUCT_Y + DUCT_H / 2.0, s * BRANCH_END), Vector3(0.6, DUCT_H + 1.2, 0.3), _grille)
		deco(Vector3(x, DUCT_Y + DUCT_H + 0.3, s * BRANCH_END), Vector3(DUCT_W + 1.2, 0.6, 0.3), _grille)

func _trunk_side(s: float, x0: float, x1: float) -> void:
	if x1 - x0 < 0.1:
		return
	box(Vector3((x0 + x1) / 2.0, DUCT_Y + DUCT_H / 2.0, s * (DUCT_W / 2.0 + 0.3)), Vector3(x1 - x0, DUCT_H, 0.6), _duct, 0.0, 0.0, false)


func _living_room() -> void:
	# Couch facing the TV: seat, back and arms.
	var c := Vector2(-35.0, -40.0)
	box(Vector3(c.x, 2.5, c.y), Vector3(22.0, 5.0, 9.0), _fabric)
	box(Vector3(c.x, 6.0, c.y - 4.0), Vector3(22.0, 7.0, 2.0), _fabric)
	for s: float in [-1.0, 1.0]:
		box(Vector3(c.x + s * 11.5, 3.5, c.y), Vector3(2.0, 7.0, 9.0), _fabric)
	# Coffee table (roll under it) and the TV on its stand.
	box(Vector3(-35.0, 4.2, -26.0), Vector3(12.0, 0.6, 6.0), _wood_light)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			pillar(Vector2(-35.0 + sx * 5.5, -26.0 + sz * 2.5), 0.0, 0.6, 3.9, _wood_light)
	box(Vector3(-35.0, 2.5, -10.0), Vector3(16.0, 5.0, 3.5), _wood)
	box(Vector3(-35.0, 9.0, -10.5), Vector3(14.0, 8.0, 0.6), _black)
	# Tall bookshelf under the duct (x -72), with a leaning plank up to it.
	box(Vector3(-72.0, 9.0, -BRANCH_END - 3.0), Vector3(12.0, 18.0, 6.0), _wood)
	for shelf in 3:
		deco(Vector3(-72.0, 4.5 + shelf * 4.5, -BRANCH_END - 6.1), Vector3(11.0, 0.3, 0.2), _wood_light)
	ramp(Vector3(-72.0, 0.0, -48.0), Vector3(-72.0, 18.0, -BRANCH_END - 6.0), 6.0, _wood_light)
	# Armchair and a floor lamp.
	box(Vector3(-62.0, 2.5, -30.0), Vector3(9.0, 5.0, 9.0), _fabric)
	box(Vector3(-66.0, 6.0, -30.0), Vector3(1.5, 7.0, 9.0), _fabric)
	pillar(Vector2(-10.0, -52.0), 0.0, 0.8, 15.0, _steel)
	box(Vector3(-10.0, 15.5, -52.0), Vector3(4.0, 3.0, 4.0), glow(Color(1.0, 0.9, 0.7), 2.0))


func _kitchen() -> void:
	# Counters along the far (north) and east walls, 9 high.
	box(Vector3(45.0, 4.5, -HZ + 3.5), Vector3(66.0, 9.0, 7.0), _white)
	box(Vector3(HX - 3.5, 4.5, -36.5), Vector3(7.0, 9.0, 33.0), _white)
	deco(Vector3(45.0, 9.05, -HZ + 3.5), Vector3(66.0, 0.1, 7.0), _black)
	# Stove top and sink on the counter.
	for i in 4:
		deco(Vector3(30.0 + (i % 2) * 4.0, 9.12, -HZ + 2.5 + (i / 2) * 3.0), Vector3(2.5, 0.05, 2.5), glow(Color(1.0, 0.3, 0.1), 0.8))
	box(Vector3(55.0, 8.4, -HZ + 3.5), Vector3(8.0, 1.2, 5.0), _steel)
	# Fridge by the hallway wall under the duct (x 72), 18 tall.
	box(Vector3(73.0, 9.0, -BRANCH_END - 4.0), Vector3(9.0, 18.0, 8.0), _steel)
	# Island in the middle.
	box(Vector3(45.0, 4.5, -32.0), Vector3(18.0, 9.0, 9.0), _wood_light)
	# Table and four chairs (seat, legs as one block below, back).
	box(Vector3(25.0, 7.2, -20.0), Vector3(14.0, 0.6, 9.0), _wood)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			pillar(Vector2(25.0 + sx * 6.0, -20.0 + sz * 3.8), 0.0, 0.7, 6.9, _wood)
	for sx: float in [-1.0, 1.0]:
		var p := Vector2(25.0 + sx * 10.0, -20.0)
		box(Vector3(p.x, 4.5, p.y), Vector3(4.5, 0.5, 4.5), _wood)
		box(Vector3(p.x + sx * 2.0, 7.0, p.y), Vector3(0.5, 5.0, 4.5), _wood)
		for lx: float in [-1.0, 1.0]:
			for lz: float in [-1.0, 1.0]:
				pillar(Vector2(p.x + lx * 1.9, p.y + lz * 1.9), 0.0, 0.4, 4.3, _wood)
	# Ironing board leaning up to the counter, and a cutting board from the counter up to
	# the fridge top.
	ramp(Vector3(62.0, 0.0, -24.0), Vector3(HX - 7.0, 9.0, -24.0), 4.0, _fabric)
	ramp(Vector3(75.5, 9.0, -46.0), Vector3(75.5, 18.0, -BRANCH_END - 8.0), 4.0, _wood_light)


func _bedroom() -> void:
	# Bed with a headboard against the west wall.
	box(Vector3(-62.0, 3.0, 35.0), Vector3(22.0, 6.0, 16.0), _duvet)
	box(Vector3(-62.0, 6.5, 35.0), Vector3(20.0, 1.0, 14.0), _white)
	box(Vector3(-HX + 1.5, 7.0, 35.0), Vector3(2.0, 14.0, 17.0), _wood)
	for s: float in [-1.0, 1.0]:
		box(Vector3(-HX + 4.0, 3.0, 35.0 + s * 12.0), Vector3(6.0, 6.0, 5.0), _wood_light)
	# Wardrobe under the duct (x -60), with a stack of boxes to climb.
	box(Vector3(-60.0, 9.0, BRANCH_END + 3.5), Vector3(14.0, 18.0, 7.0), _wood)
	# Moving boxes: a ramp onto the first, a jump onto the second, a plank to the wardrobe.
	ramp(Vector3(-40.0, 0.0, 55.0), Vector3(-40.0, 6.0, 44.0), 6.0, _wood_light)
	box(Vector3(-40.0, 3.0, 40.0), Vector3(8.0, 6.0, 8.0), solid(Color(0.7, 0.55, 0.35)))
	box(Vector3(-40.0, 7.5, 38.0), Vector3(6.0, 3.0, 6.0), solid(Color(0.75, 0.6, 0.4)))
	ramp(Vector3(-40.0, 9.0, 36.0), Vector3(-53.0, 18.0, BRANCH_END + 3.5), 4.0, _wood_light)
	# Dresser.
	box(Vector3(-25.0, 5.0, HZ - 4.0), Vector3(14.0, 10.0, 6.0), _wood)


func _bathroom() -> void:
	# Bathtub: floor and four sides (you can roll into it).
	var t := Vector2(5.0, 50.0)
	box(Vector3(t.x, 0.6, t.y), Vector3(18.0, 1.2, 8.0), _white)
	for s: float in [-1.0, 1.0]:
		box(Vector3(t.x, 3.2, t.y + s * 3.6), Vector3(18.0, 4.0, 0.8), _white)
		box(Vector3(t.x + s * 8.6, 3.2, t.y), Vector3(0.8, 4.0, 8.0), _white)
	# Toilet and sink.
	box(Vector3(-8.0, 2.0, 20.0), Vector3(4.0, 4.0, 6.0), _white)
	box(Vector3(-8.0, 5.5, 22.5), Vector3(4.0, 5.0, 1.8), _white)
	box(Vector3(14.0, 4.2, 20.0), Vector3(8.0, 8.4, 5.0), _wood_light)
	# Tall cabinet under the duct (x 12) and a towel draped as a ramp.
	box(Vector3(12.0, 9.0, BRANCH_END + 2.0), Vector3(6.0, 18.0, 4.0), _white)
	ramp(Vector3(12.0, 0.0, 44.0), Vector3(12.0, 18.0, BRANCH_END + 4.0), 3.0, solid(Color(0.3, 0.7, 0.75)))


func _office() -> void:
	# Desk with a monitor, and a chair.
	box(Vector3(50.0, 7.2, 50.0), Vector3(16.0, 0.6, 8.0), _wood)
	for sx: float in [-1.0, 1.0]:
		box(Vector3(50.0 + sx * 7.5, 3.45, 50.0), Vector3(0.8, 6.9, 7.5), _wood)
	box(Vector3(50.0, 10.0, 52.5), Vector3(8.0, 5.0, 0.5), _black)
	box(Vector3(50.0, 4.5, 42.0), Vector3(5.0, 0.6, 5.0), _black)
	pillar(Vector2(50.0, 42.0), 0.0, 0.8, 4.2, _steel)
	# Bookshelf under the duct (x 72) with stacked books to climb.
	box(Vector3(72.0, 9.0, BRANCH_END + 3.0), Vector3(12.0, 18.0, 6.0), _wood)
	for i in 4:
		box(Vector3(62.0 - i * 0.3, 1.0 + i * 2.0, 24.0 - i * 3.0), Vector3(7.0, 2.0, 9.0), solid(Color.from_hsv(0.1 * i, 0.6, 0.7)))
	ramp(Vector3(40.0, 0.0, 32.0), Vector3(66.0, 18.0, BRANCH_END + 3.0), 3.0, _wood_light)
	box(Vector3(28.0, 6.0, 32.0), Vector3(6.0, 12.0, 8.0), _steel)


func _lights() -> void:
	for p in [Vector2(-40, -33), Vector2(45, -33), Vector2(-45, 33), Vector2(2, 33), Vector2(50, 33), Vector2(-40, 0), Vector2(40, 0)]:
		deco(Vector3(p.x, H - 0.4, p.y), Vector3(5.0, 0.8, 5.0), glow(Color(1.0, 0.92, 0.75), 3.0))
		var light := OmniLight3D.new()
		light.position = Vector3(p.x, H - 3.0, p.y)
		light.light_color = Color(1.0, 0.9, 0.75)
		light.light_energy = 1.4
		light.omni_range = 60.0
		add_child(light)
