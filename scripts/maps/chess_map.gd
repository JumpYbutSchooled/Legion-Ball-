extends "res://scripts/maps/map_builder.gd"
## "Chess Board": a really big chess board floating in the void. 8 x 8 squares, 30 m
## each, with a low wooden rim round the edge (jumpable: past it is a long fall). All 32
## pieces stand in their starting positions, built big (a king is over 40 m tall), so
## the back ranks are a forest of cover and the middle of the board is open ground.

const SQUARE := 30.0
const HALF := SQUARE * 4.0
const RIM := 12.0

var _white_sq := solid(Color(0.9, 0.86, 0.76), 0.5)
var _black_sq := solid(Color(0.22, 0.16, 0.12), 0.5)
var _rim := solid(Color(0.4, 0.24, 0.12), 0.4)
var _ivory := solid(Color(0.95, 0.92, 0.85), 0.25)
var _ebony := solid(Color(0.16, 0.14, 0.16), 0.12, 0.55)


func _build() -> void:
	_ceiling = 90.0
	_outline = rect_outline(Rect2(-HALF - RIM, -HALF - RIM, (HALF + RIM) * 2.0, (HALF + RIM) * 2.0))
	# The squares: one box each, so the colours line up exactly with the pieces.
	for file in 8:
		for rank in 8:
			var p := _square(file, rank)
			box(Vector3(p.x, -4.0, p.y), Vector3(SQUARE, 8.0, SQUARE), _white_sq if (file + rank) % 2 == 1 else _black_sq)
	# The rim: a raised wooden frame round the board.
	for k in 4:
		var yaw := TAU * k / 4.0
		var out := Vector3(sin(yaw), 0.0, cos(yaw))
		box(out * (HALF + RIM / 2.0) + Vector3.DOWN * 3.0, Vector3((HALF + RIM) * 2.0, 10.0, RIM), _rim, yaw)
	var back := ["rook", "knight", "bishop", "queen", "king", "bishop", "knight", "rook"]
	for side in 2:
		var mat := _ivory if side == 0 else _ebony
		var home := 0 if side == 0 else 7
		var pawns := 1 if side == 0 else 6
		var facing := 0.0 if side == 0 else PI
		for file in 8:
			_piece(back[file], _square(file, home), mat, facing)
			_piece("pawn", _square(file, pawns), mat, facing)
	# Spawns on the empty middle four ranks.
	for i in 8:
		var p := _square(i, 3 if i % 2 == 0 else 4)
		_spawns.append(Vector3(p.x, 1.0, p.y))
	for file in [0, 7]:
		for rank in [0, 7]:
			var p := _square(file, rank)
			_turrets.append(Vector3(p.x, 25.5, p.y))
	# Soft light over the board, like a lamp over a table.
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var light := OmniLight3D.new()
			light.position = Vector3(sx * 60.0, 90.0, sz * 60.0)
			light.light_color = Color(1.0, 0.92, 0.8)
			light.light_energy = 1.2
			light.omni_range = 200.0
			add_child(light)


## Centre of a square: files along x (a..h), ranks along z (1 at +z, white's side).
func _square(file: int, rank: int) -> Vector2:
	return Vector2((file - 3.5) * SQUARE, (3.5 - rank) * SQUARE)


## A piece made of stacked blocks: a wide base, a body, a collar and a head that tells
## you which piece it is.
func _piece(kind: String, p: Vector2, mat: Material, facing: float) -> void:
	var sizes := {"pawn": [15.0, 9.0, 10.0], "rook": [18.0, 13.0, 17.0], "knight": [17.0, 11.0, 12.0],
		"bishop": [16.0, 10.0, 20.0], "queen": [19.0, 12.0, 24.0], "king": [20.0, 13.0, 26.0]}
	var s: Array = sizes[kind]
	var base: float = s[0]
	var body: float = s[1]
	var height: float = s[2]
	box(Vector3(p.x, 1.5, p.y), Vector3(base, 3.0, base), mat, facing)
	box(Vector3(p.x, 3.0 + height / 2.0, p.y), Vector3(body, height, body), mat, facing)
	var top := 3.0 + height
	box(Vector3(p.x, top + 0.75, p.y), Vector3(body + 3.0, 1.5, body + 3.0), mat, facing)
	top += 1.5
	match kind:
		"pawn":
			box(Vector3(p.x, top + 4.0, p.y), Vector3(8.0, 8.0, 8.0), mat, facing + PI / 4.0)
		"rook":
			box(Vector3(p.x, top + 2.0, p.y), Vector3(16.0, 4.0, 16.0), mat, facing)
			for sx: float in [-1.0, 1.0]:
				for sz: float in [-1.0, 1.0]:
					box(Vector3(p.x + sx * 6.0, top + 5.5, p.y + sz * 6.0), Vector3(4.0, 3.0, 4.0), mat, facing)
		"knight":
			# The horse's head: a block leaning forward, and a snout.
			var fwd := Vector3(sin(facing), 0.0, -cos(facing))
			box(Vector3(p.x, top + 7.0, p.y) + fwd * 1.5, Vector3(9.0, 14.0, 9.0), mat, facing, -0.25)
			box(Vector3(p.x, top + 10.0, p.y) + fwd * 7.0, Vector3(7.0, 6.0, 9.0), mat, facing)
			box(Vector3(p.x, top + 15.0, p.y) - fwd * 1.0, Vector3(3.0, 3.0, 5.0), mat, facing)
		"bishop":
			box(Vector3(p.x, top + 5.0, p.y), Vector3(8.0, 10.0, 8.0), mat, facing + PI / 4.0)
			box(Vector3(p.x, top + 11.5, p.y), Vector3(3.0, 3.0, 3.0), mat, facing)
		"queen":
			box(Vector3(p.x, top + 3.0, p.y), Vector3(14.0, 6.0, 14.0), mat, facing + PI / 4.0)
			for i in 8:
				var q := p + Vector2.from_angle(TAU * i / 8.0) * 6.5
				box(Vector3(q.x, top + 7.5, q.y), Vector3(2.0, 3.0, 2.0), mat)
			box(Vector3(p.x, top + 8.5, p.y), Vector3(4.0, 4.0, 4.0), mat, facing + PI / 4.0)
		"king":
			box(Vector3(p.x, top + 3.5, p.y), Vector3(15.0, 7.0, 15.0), mat, facing)
			box(Vector3(p.x, top + 12.0, p.y), Vector3(2.5, 10.0, 2.5), mat, facing)
			box(Vector3(p.x, top + 13.5, p.y), Vector3(8.0, 2.5, 2.5), mat, facing)
