extends "res://scripts/maps/map_builder.gd"
## "Jungle Gym": a kids' playground at toy scale. A big plastic play structure in the
## middle (four decks on posts joined by bridges, slides, stairs, a climbing wall and
## monkey bars), a swing set, a seesaw, a merry-go-round, a sandbox and a crawl tube, on
## rubber mulch inside a low wooden border, with grass and a fence round the outside.

const HALF := 90.0

var _mulch := checker(Color(0.42, 0.22, 0.14), Color(0.36, 0.18, 0.11), 1.6)
var _grass := checker(Color(0.3, 0.55, 0.22), Color(0.27, 0.5, 0.2), 6.0)
var _wood := solid(Color(0.55, 0.36, 0.2), 0.8)
var _metal := solid(Color(0.7, 0.72, 0.75), 0.35, 0.7)
var _red := solid(Color(0.85, 0.15, 0.12), 0.45)
var _blue := solid(Color(0.15, 0.4, 0.9), 0.45)
var _yellow := solid(Color(1.0, 0.8, 0.1), 0.45)
var _green := solid(Color(0.2, 0.75, 0.3), 0.45)
var _sand := solid(Color(0.93, 0.83, 0.58), 0.95)
var _fence := solid(Color(0.92, 0.92, 0.9), 0.6)

## Decks: [x, z, height, colour of their roof or rail].
var _decks := [
	[-24.0, -10.0, 8.0], [0.0, -10.0, 12.0], [24.0, -10.0, 8.0], [0.0, 14.0, 10.0],
]


## Built at twice its written size in every direction.
func map_size() -> float:
	return 2.0


func _build() -> void:
	_ceiling = 60.0
	_outline = rect_outline(Rect2(-HALF, -HALF, HALF * 2.0, HALF * 2.0))
	ground(Rect2(-HALF, -HALF, HALF * 2.0, HALF * 2.0), _grass)
	# Mulch pit inside a low timber border.
	box(Vector3(0, 0.15, 0), Vector3(120.0, 0.3, 110.0), _mulch)
	for s: float in [-1.0, 1.0]:
		box(Vector3(s * 60.0, 0.6, 0), Vector3(1.2, 1.2, 111.0), _wood)
		box(Vector3(0, 0.6, s * 55.0), Vector3(121.0, 1.2, 1.2), _wood)
	# Tall fence round the whole park.
	for k in 4:
		var yaw := TAU * k / 4.0
		var out := Vector3(sin(yaw), 0.0, cos(yaw))
		box(out * (HALF - 0.5) + Vector3.UP * 4.0, Vector3(HALF * 2.0, 8.0, 1.0), _fence, yaw)
	_structure()
	_swings(Vector3(-40.0, 0.0, 34.0))
	_seesaw(Vector3(38.0, 0.0, 34.0))
	_merry_go_round(Vector3(40.0, 0.0, -38.0))
	_sandbox(Vector3(-40.0, 0.0, -38.0))
	_crawl_tube(Vector3(0.0, 0.0, 40.0))
	for i in 8:
		var a := TAU * i / 8.0 + 0.3
		_spawns.append(Vector3(cos(a) * 48.0, 1.5, sin(a) * 42.0))
	for p in [Vector3(-75, 1, -75), Vector3(75, 1, -75), Vector3(-75, 1, 75), Vector3(75, 1, 75)]:
		_turrets.append(p)
	var sun_fill := OmniLight3D.new()
	sun_fill.position = Vector3(0, 40, 0)
	sun_fill.light_energy = 0.6
	sun_fill.omni_range = 120.0
	add_child(sun_fill)


## The big play structure: decks on posts with roofs, bridges, slides, stairs, a
## climbing wall and monkey bars.
func _structure() -> void:
	var colours := [_red, _blue, _yellow, _green]
	for i in _decks.size():
		var d: Array = _decks[i]
		var x: float = d[0]
		var z: float = d[1]
		var h: float = d[2]
		box(Vector3(x, h - 0.4, z), Vector3(12.0, 0.8, 12.0), _wood)
		for sx: float in [-1.0, 1.0]:
			for sz: float in [-1.0, 1.0]:
				pillar(Vector2(x + sx * 5.6, z + sz * 5.6), 0.0, 0.9, h + 7.0, colours[i])
		# Low rails on the sides nothing joins onto.
		box(Vector3(x, h + 0.6, z - 5.9), Vector3(12.0, 1.2, 0.4), colours[(i + 1) % 4])
		# A pointed roof: four panels leaning in.
		for k in 4:
			var yaw := TAU * k / 4.0 + PI / 4.0
			var out := Vector3(sin(yaw), 0.0, cos(yaw))
			box(Vector3(x, h + 8.2, z) + out * 3.2, Vector3(9.5, 0.5, 7.0), colours[i], yaw, -0.6, false)
	# Bridges between neighbouring decks.
	ramp(Vector3(-18.0, 7.6, -10.0), Vector3(-6.0, 11.6, -10.0), 4.0, _wood)
	ramp(Vector3(18.0, 7.6, -10.0), Vector3(6.0, 11.6, -10.0), 4.0, _wood)
	# A wavy chain bridge from the tall deck to the back one: planks going up and down.
	for i in 10:
		var t := (i + 0.5) / 10.0
		var y := lerpf(11.6, 9.6, t) + sin(t * TAU) * 0.6
		box(Vector3(0.0, y, lerpf(-4.0, 8.0, t)), Vector3(4.0, 0.4, 1.15), _wood)
	# Slides: long and wide from the tall deck, a steep one from each side deck.
	_slide(Vector3(0.0, 11.6, -16.0), Vector3(0.0, 0.6, -46.0), _yellow)
	_slide(Vector3(-30.0, 7.6, -10.0), Vector3(-52.0, 0.6, -10.0), _red)
	_slide(Vector3(30.0, 7.6, -10.0), Vector3(52.0, 0.6, -10.0), _blue)
	_slide(Vector3(0.0, 9.6, 20.0), Vector3(0.0, 0.6, 30.0), _green)
	# Stairs up to the side decks.
	stairs(Vector3(-24.0, 0.3, 6.0), Vector2(0, -1), 10, 0.75, 1.1, 4.0, _wood)
	stairs(Vector3(24.0, 0.3, 6.0), Vector2(0, -1), 10, 0.75, 1.1, 4.0, _wood)
	# Climbing wall up the back of the tall deck, with coloured holds.
	box(Vector3(-12.0, 5.0, 2.0), Vector3(8.0, 0.6, 14.0), _blue, PI / 2.0, 0.95)
	var colours2 := [_red, _yellow, _green]
	for i in 14:
		var hold := Vector3(-12.0 + _rng.randf_range(-3.0, 3.0), 1.0 + i * 0.7, 2.0 + 4.0 - i * 0.55)
		deco(hold, Vector3(0.6, 0.4, 0.5), colours2[i % 3])
	# Monkey bars from the right deck to the back deck: two rails and rungs you can roll over.
	for side: float in [-1.0, 1.0]:
		wall(Vector2(24.0 + side * 1.6, -4.0), Vector2(6.0 + side * 1.6, 14.0), 9.4, 0.4, 0.3, _metal)
	for i in 30:
		var t := (i + 0.5) / 30.0
		var p := Vector2(24.0, -4.0).lerp(Vector2(6.0, 14.0), t)
		box(Vector3(p.x, 9.8, p.y), Vector3(3.6, 0.25, 0.3), _metal, PI / 4.0)


func _slide(top: Vector3, bottom: Vector3, mat: Material) -> void:
	ramp(bottom, top, 4.0, mat)
	var flat := Vector2(top.x - bottom.x, top.z - bottom.z)
	var side := Vector2(-flat.y, flat.x).normalized() * 2.2
	for s: float in [-1.0, 1.0]:
		ramp(bottom + Vector3(side.x * s, 0.8, side.y * s), top + Vector3(side.x * s, 0.8, side.y * s), 0.4, mat)


func _swings(at: Vector3) -> void:
	for side: float in [-1.0, 1.0]:
		for lean: float in [-1.0, 1.0]:
			box(at + Vector3(side * 14.0, 6.0, lean * 2.2), Vector3(0.6, 12.4, 0.6), _metal, 0.0, lean * 0.35)
	box(at + Vector3(0, 11.8, 0), Vector3(29.0, 0.7, 0.7), _metal)
	for i in 3:
		var x := -9.0 + i * 9.0
		box(at + Vector3(x, 2.6, 0), Vector3(3.2, 0.4, 1.4), [_red, _blue, _yellow][i])
		for s: float in [-1.0, 1.0]:
			deco(at + Vector3(x + s * 1.4, 7.2, 0), Vector3(0.12, 9.0, 0.12), _metal)


func _seesaw(at: Vector3) -> void:
	box(at + Vector3(0, 1.0, 0), Vector3(1.6, 2.0, 1.6), _metal)
	box(at + Vector3(0, 2.2, 0), Vector3(2.4, 0.5, 20.0), _green, 0.0, 0.2)
	for s: float in [-1.0, 1.0]:
		box(at + Vector3(0, 2.2 - s * 1.9, s * 8.5), Vector3(0.3, 1.2, 0.3), _red)


func _merry_go_round(at: Vector3) -> void:
	disc(at + Vector3(0, 1.0, 0), 7.0, 0.8, _red, 3)
	pillar(Vector2(at.x, at.z), 1.0, 0.8, 4.0, _metal)
	for i in 6:
		var a := TAU * i / 6.0
		wall(Vector2(at.x, at.z), Vector2(at.x + cos(a) * 6.5, at.z + sin(a) * 6.5), 3.8, 0.3, 0.3, _yellow)


func _sandbox(at: Vector3) -> void:
	box(at + Vector3(0, 0.5, 0), Vector3(18.0, 0.6, 18.0), _sand)
	for s: float in [-1.0, 1.0]:
		box(at + Vector3(s * 9.0, 1.0, 0), Vector3(1.0, 1.6, 19.0), _wood)
		box(at + Vector3(0, 1.0, s * 9.0), Vector3(19.0, 1.6, 1.0), _wood)
	# A bucket and a spade someone left behind.
	box(at + Vector3(3.0, 1.9, 2.0), Vector3(2.0, 2.2, 2.0), _blue)
	box(at + Vector3(-3.0, 1.0, -2.0), Vector3(0.6, 0.3, 4.0), _red, 0.5)


func _crawl_tube(at: Vector3) -> void:
	for s: float in [-1.0, 1.0]:
		box(at + Vector3(s * 2.2, 2.2, 0), Vector3(0.4, 4.4, 16.0), _green)
	box(at + Vector3(0, 4.6, 0), Vector3(4.8, 0.4, 16.0), _green)
