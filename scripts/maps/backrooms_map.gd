extends "res://scripts/maps/map_builder.gd"
## "The Backrooms" (Level 0): endless empty office rooms. Mono-yellow wallpaper, damp
## brown carpet, a low ceiling of tiles and humming fluorescent panels, and a maze of
## walls with no plan to it at all. It never ends, in any direction... because it loops:
## walk out of one side of the block and you're back in the other, and copies of it all
## round (fading into the yellow haze) hide where.

const WIDTH := 216.0
const HALF := WIDTH / 2.0
const CELL := 12.0
const CEILING := 9.0

var _carpet := checker(Color(0.5, 0.43, 0.27), Color(0.47, 0.4, 0.25), 1.2)
var _paper := panel(Color(0.8, 0.74, 0.44), Color(0.72, 0.66, 0.38), 1.5)
var _paper2 := solid(Color(0.76, 0.7, 0.42), 0.95)
var _ceiling_tile := checker(Color(0.86, 0.84, 0.74), Color(0.8, 0.78, 0.68), 3.0)
var _light := glow(Color(1.0, 0.98, 0.85), 3.5)
var _trim := solid(Color(0.6, 0.52, 0.34), 0.8)


## Roofed over / lit by lamps: no sun shadows here (graphics.gd).
func is_indoor() -> bool:
	return true


func _build() -> void:
	_wrap = Vector3(WIDTH, 0.0, WIDTH)
	_ceiling = CEILING - 1.0
	_outline = rect_outline(Rect2(-HALF, -HALF, WIDTH, WIDTH))
	_rng.seed = 8008
	# One floor and one ceiling for the whole block (each copy of the block has its own).
	box(Vector3(0, -0.5, 0), Vector3(WIDTH, 1.0, WIDTH), _carpet)
	box(Vector3(0, CEILING + 0.4, 0), Vector3(WIDTH, 0.8, WIDTH), _ceiling_tile, 0.0, 0.0, false)
	var cells := int(WIDTH / CELL)
	# The maze: every cell edge might be a wall, some with doorways; pillars here and there.
	for i in cells:
		for j in cells:
			var x := -HALF + i * CELL
			var z := -HALF + j * CELL
			if _rng.randf() < 0.42:
				_wall_piece(Vector2(x, z), Vector2(x + CELL, z))
			if _rng.randf() < 0.42:
				_wall_piece(Vector2(x, z), Vector2(x, z + CELL))
			if _rng.randf() < 0.08:
				pillar(Vector2(x + CELL / 2.0, z + CELL / 2.0), 0.0, 2.2, CEILING, _paper)
			# A fluorescent panel over most cells (some dead ones).
			if _rng.randf() < 0.82:
				deco(Vector3(x + CELL / 2.0, CEILING - 0.05, z + CELL / 2.0), Vector3(2.4, 0.1, 1.2), _light)
	for i in 8:
		var a := TAU * i / 8.0
		var p := Vector2.from_angle(a) * 60.0
		_spawns.append(Vector3(snappedf(p.x, CELL) + CELL / 2.0, 1.0, snappedf(p.y, CELL) + CELL / 2.0))
	# A few real lights to go with the panels (the rest is the glow and the haze).
	for x in range(-2, 3):
		for z in range(-2, 3):
			var light := OmniLight3D.new()
			light.position = Vector3(x * 44.0, CEILING - 1.5, z * 44.0)
			light.light_color = Color(1.0, 0.95, 0.75)
			light.light_energy = 0.9
			light.omni_range = 36.0
			add_child(light)


## A wall along a cell edge: solid, or with a doorway in the middle, with a skirting board.
func _wall_piece(a: Vector2, b: Vector2) -> void:
	var mat: Material = _paper if _rng.randf() < 0.7 else _paper2
	if _rng.randf() < 0.35:
		var d := (b - a) / 3.0
		wall(a, a + d, 0.0, CEILING, 0.5, mat)
		wall(b - d, b, 0.0, CEILING, 0.5, mat)
		wall(a + d, b - d, 6.5, CEILING - 6.5, 0.5, mat)
	else:
		wall(a, b, 0.0, CEILING, 0.5, mat)
	var mid := (a + b) / 2.0
	deco(Vector3(mid.x, 0.3, mid.y), Vector3((b - a).length(), 0.6, 0.7), _trim, -(b - a).angle())
