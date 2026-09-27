extends "res://scripts/maps/map_builder.gd"
## "Big Toilet": a bathroom where you're the size of a mouse, and the star is a really
## big toilet. Roll up the step stool onto the lid-up seat, drop into the bowl (a steep
## skate bowl with water at the bottom), or climb onto the tank. Round the room: a
## bathtub (a half-pipe, with a rubber duck), the sink counter, a giant toilet roll, a
## bin and a bath mat, on a tiled floor.

const ROOM := Vector2(180.0, 130.0)
const WALL_H := 70.0

var _tile := checker(Color(0.93, 0.95, 0.97), Color(0.7, 0.82, 0.9), 6.0)
var _wall := panel(Color(0.85, 0.9, 0.88), Color(0.75, 0.8, 0.78), 8.0)
var _porcelain := solid(Color(0.97, 0.97, 0.96), 0.12)
var _seat := solid(Color(0.95, 0.95, 0.93), 0.3)
var _water := glow(Color(0.35, 0.65, 0.95), 0.6)
var _chrome := solid(Color(0.85, 0.87, 0.9), 0.1, 1.0)
var _wood := solid(Color(0.6, 0.42, 0.25), 0.7)
var _mat := checker(Color(0.3, 0.5, 0.75), Color(0.25, 0.42, 0.65), 1.2)
var _duck := solid(Color(1.0, 0.85, 0.1), 0.4)
var _orange := solid(Color(1.0, 0.45, 0.05), 0.4)
var _paper := solid(Color(0.98, 0.97, 0.94), 0.95)
var _cardboard := solid(Color(0.6, 0.45, 0.3), 0.9)
var _grey := solid(Color(0.45, 0.47, 0.5), 0.6)


func _build() -> void:
	_ceiling = WALL_H + 10.0
	var half := ROOM / 2.0
	_outline = rect_outline(Rect2(-half.x, -half.y, ROOM.x, ROOM.y))
	ground(Rect2(-half.x, -half.y, ROOM.x, ROOM.y), _tile)
	wall(Vector2(-half.x, -half.y), Vector2(half.x, -half.y), 0.0, WALL_H, 2.0, _wall)
	wall(Vector2(-half.x, half.y), Vector2(half.x, half.y), 0.0, WALL_H, 2.0, _wall)
	wall(Vector2(-half.x, -half.y), Vector2(-half.x, half.y), 0.0, WALL_H, 2.0, _wall)
	wall(Vector2(half.x, -half.y), Vector2(half.x, half.y), 0.0, WALL_H, 2.0, _wall)
	_toilet(Vector3(0, 0, -half.y + 26.0))
	_bathtub(Vector3(-half.x + 22.0, 0, 10.0))
	_sink(Vector3(half.x - 16.0, 0, -20.0))
	_roll(Vector3(28.0, 0, -half.y + 8.0))
	_bin(Vector3(half.x - 14.0, 0, 38.0))
	box(Vector3(0, 0.25, 22.0), Vector3(50.0, 0.5, 30.0), _mat)
	for i in 8:
		var a := TAU * i / 8.0
		_spawns.append(Vector3(cos(a) * 55.0, 1.0, 25.0 + sin(a) * 30.0))
	_turrets.append(Vector3(-half.x + 6.0, 1, half.y - 6.0))
	_turrets.append(Vector3(half.x - 6.0, 1, half.y - 6.0))
	for x: float in [-45.0, 45.0]:
		var light := OmniLight3D.new()
		light.position = Vector3(x, WALL_H - 10.0, 0)
		light.light_color = Color(1.0, 0.97, 0.9)
		light.light_energy = 1.4
		light.omni_range = 140.0
		add_child(light)


## The toilet: pedestal, a bowl you can skate round (a steep funnel down to the water),
## the seat on the rim with the lid up, the tank behind with its handle, and a stool.
func _toilet(at: Vector3) -> void:
	var rim_y := 22.0
	var rim_r := 14.0
	var water_r := 5.0
	var water_y := 11.0
	# Pedestal and the base of the bowl.
	box(at + Vector3(0, water_y / 2.0, 3.0), Vector3(16.0, water_y, 18.0), _porcelain)
	deco(at + Vector3(0, water_y + 0.05, 0), Vector3(water_r * 2.0, 0.1, water_r * 2.0), _water)
	# The funnel: 28 tilted slabs from the water up to the rim.
	var sides := 28
	for i in sides:
		var a := TAU * (i + 0.5) / sides
		var out := Vector2.from_angle(a)
		var mid_r := (water_r + rim_r) / 2.0
		var slope := atan2(rim_y - water_y, rim_r - water_r)
		var length := Vector2(rim_r - water_r, rim_y - water_y).length()
		var width := TAU * rim_r / sides + 0.6
		var u := Vector3(out.x, 0.0, out.y)
		var basis := Basis(u, Vector3.UP, u.cross(Vector3.UP).normalized()) * Basis(Vector3(0, 0, 1), slope)
		var centre := at + Vector3(out.x * mid_r, (water_y + rim_y) / 2.0, out.y * mid_r) - basis.y * 0.6
		box_basis(basis, centre, Vector3(length, 1.2, width), _porcelain)
	# The outside of the bowl down to the floor, and the rim with the seat on it.
	ring(Vector2(at.x, at.z), rim_r + 1.2, sides, 0.0, rim_y, 2.4, _porcelain)
	ring(Vector2(at.x, at.z), rim_r + 1.0, sides, rim_y, 1.4, 3.4, _seat)
	# The lid, up, leaning back against the tank.
	box(at + Vector3(0, rim_y + 13.0, -rim_r - 2.0), Vector3(rim_r * 2.0, 26.0, 1.2), _seat, 0.0, -0.12)
	# The tank, with its lid and flush handle.
	var tank := at + Vector3(0, 0, -rim_r - 9.0)
	box(tank + Vector3(0, 30.0, 0), Vector3(34.0, 24.0, 12.0), _porcelain)
	box(tank + Vector3(0, 42.6, 0), Vector3(36.0, 1.6, 13.5), _porcelain)
	box(tank + Vector3(-14.0, 38.0, 6.8), Vector3(6.0, 1.2, 1.4), _chrome)
	box(tank + Vector3(0, 11.0, -3.0), Vector3(4.0, 22.0, 4.0), _porcelain)
	# A step stool in front, and a ramp of books up onto it.
	box(at + Vector3(0, 7.0, rim_r + 9.0), Vector3(20.0, 1.6, 12.0), _wood)
	for s: float in [-1.0, 1.0]:
		box(at + Vector3(s * 9.0, 3.1, rim_r + 9.0), Vector3(1.6, 6.2, 11.0), _wood)
	ramp(at + Vector3(0, 0.0, rim_r + 36.0), at + Vector3(0, 7.8, rim_r + 15.0), 8.0, _orange)
	ramp(at + Vector3(0, 7.8, rim_r + 3.5), at + Vector3(0, rim_y + 0.6, rim_r - 1.5), 8.0, _wood)


## The bathtub: a long box open at the top, curved inside ends make it a half-pipe.
func _bathtub(at: Vector3) -> void:
	var length := 90.0
	var width := 38.0
	var h := 20.0
	box(at + Vector3(0, 1.0, 0), Vector3(width, 2.0, length), _porcelain)
	for s: float in [-1.0, 1.0]:
		box(at + Vector3(s * (width / 2.0 - 1.5), h / 2.0, 0), Vector3(3.0, h, length), _porcelain)
		box(at + Vector3(0, h / 2.0, s * (length / 2.0 - 1.5)), Vector3(width, h, 3.0), _porcelain)
		# Sloped ends and sides inside, for riding up the walls like a half-pipe.
		ramp(at + Vector3(0, 2.0, s * (length / 2.0 - 20.0)), at + Vector3(0, h - 2.0, s * (length / 2.0 - 3.0)), width - 7.0, _porcelain)
		ramp(at + Vector3(s * (width / 2.0 - 12.0), 2.0, 0), at + Vector3(s * (width / 2.0 - 3.0), h - 2.0, 0), length - 44.0, _porcelain)
	# The taps, and a rubber duck.
	box(at + Vector3(0, h + 3.0, -length / 2.0 + 1.5), Vector3(3.0, 2.0, 7.0), _chrome)
	var duck := at + Vector3(0.0, 2.0, 8.0)
	box(duck + Vector3(0, 3.0, 0), Vector3(9.0, 6.0, 12.0), _duck)
	box(duck + Vector3(0, 8.0, -3.0), Vector3(6.0, 5.0, 6.0), _duck)
	box(duck + Vector3(0, 7.5, -7.0), Vector3(3.0, 1.2, 3.0), _orange)
	# A step up over the side.
	ramp(at + Vector3(width / 2.0 + 18.0, 0.0, 0.0), at + Vector3(width / 2.0 + 0.5, h, 0.0), 10.0, _mat)


func _sink(at: Vector3) -> void:
	box(at + Vector3(0, 16.0, 0), Vector3(28.0, 32.0, 50.0), _wood)
	box(at + Vector3(0, 32.8, 0), Vector3(30.0, 1.6, 52.0), _porcelain)
	for s: float in [-1.0, 1.0]:
		box(at + Vector3(0, 35.0, s * 8.0), Vector3(14.0, 3.0, 1.2), _porcelain)
	box(at + Vector3(10.0, 38.0, 0), Vector3(2.0, 8.0, 2.0), _chrome)
	ramp(at + Vector3(-50.0, 0.0, -10.0), at + Vector3(-14.5, 33.4, -10.0), 8.0, _cardboard)


## A giant toilet roll lying on its side: a ring you can roll inside.
func _roll(at: Vector3) -> void:
	var r := 10.0
	for i in 20:
		var a := TAU * (i + 0.5) / 20.0
		var p := Vector2(cos(a), sin(a)) * r
		box(at + Vector3(p.x, r + p.y, 0), Vector3(3.6, 3.4, 22.0), _paper, 0.0, 0.0).rotation.z = a
	for i in 20:
		var a := TAU * (i + 0.5) / 20.0
		var p := Vector2(cos(a), sin(a)) * 4.0
		deco(at + Vector3(p.x, r + p.y, 0), Vector3(1.4, 1.3, 22.2), _cardboard).rotation.z = a


func _bin(at: Vector3) -> void:
	ring(Vector2(at.x, at.z), 8.0, 12, 0.0, 16.0, 1.2, _grey)
	box(at + Vector3(0, 0.6, 0), Vector3(15.0, 1.2, 15.0), _grey)
