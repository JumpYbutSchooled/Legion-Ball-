extends "res://scripts/maps/map_builder.gd"
## "Coliseum": a Roman amphitheatre. A round sand floor with a low podium wall, five
## rising tiers of stone seating all the way round (eight aisle ramps run up them), a
## colonnade of marble columns along the top tier under a stone architrave, and a tall
## outer wall. In the arena: a raised central dais with four ramps, broken columns and
## gladiator barricades for cover.

const SEED := 4417
const ARENA_R := 96.0
const TIER_DEPTH := 11.0
const TIERS := 5
const TIER_RISE := 3.5
const SEGMENTS := 40
## Every fifth seating segment is an aisle with a ramp up it.
const AISLE_EVERY := 5
const OUTER_R := 162.0
const OUTER_HEIGHT := 72.0

var _sand := checker(Color(0.78, 0.67, 0.48), Color(0.74, 0.63, 0.45), 4.0)
var _stone := solid(Color(0.74, 0.68, 0.58))
var _stone_dark := solid(Color(0.62, 0.56, 0.48))
var _marble := solid(Color(0.9, 0.88, 0.84), 0.5)
var _bronze := solid(Color(0.72, 0.5, 0.26), 0.4, 0.6)


func _build() -> void:
	_rng.seed = SEED
	_ceiling = 64.0
	_outline = circle_outline(OUTER_R, 32)
	ground(Rect2(-OUTER_R - 12.0, -OUTER_R - 12.0, OUTER_R * 2.0 + 24.0, OUTER_R * 2.0 + 24.0), _sand)
	_build_tiers()
	_build_colonnade()
	ring(Vector2.ZERO, OUTER_R, 32, 0.0, OUTER_HEIGHT, 5.0, _stone_dark)
	_build_center()
	for i in 8:
		var a := TAU * (i + 0.5) / 8.0
		var p := Vector2.from_angle(a) * 74.0
		_spawns.append(Vector3(p.x, 1.0, p.y))
	# Turrets on the top tier, between aisles.
	var top_y := 4.0 + (TIERS - 1) * TIER_RISE
	for i in 4:
		var p := Vector2.from_angle(TAU * (i + 0.25) / 4.0) * (ARENA_R + TIER_DEPTH * (TIERS - 1) + 2.0)
		_turrets.append(Vector3(p.x, top_y, p.y))


## Seating: each tier a ring of solid blocks, higher the further out; aisles left open
## with a ramp from the sand to the top tier.
func _build_tiers() -> void:
	var step := TAU / SEGMENTS
	for i in SEGMENTS:
		var a0 := step * i
		var a1 := step * (i + 1)
		var mid := (a0 + a1) / 2.0
		var top := 4.0 + (TIERS - 1) * TIER_RISE
		var seats_end := ARENA_R + TIER_DEPTH * TIERS
		if i % AISLE_EVERY == 0:
			var low := Vector2.from_angle(mid) * (ARENA_R - 8.0)
			var high := Vector2.from_angle(mid) * seats_end
			ramp(Vector3(low.x, 0.0, low.y), Vector3(high.x, top, high.y), 11.0, _stone_dark)
			# The walkway behind the top of the aisle, out to the wall.
			var back := (OUTER_R - 2.5 - seats_end)
			var c := Vector2.from_angle(mid) * (seats_end + back / 2.0)
			box(Vector3(c.x, top / 2.0, c.y), Vector3(back, top, 2.0 * OUTER_R * sin(step / 2.0) + 0.4), _stone, -mid)
			continue
		for t in TIERS:
			var r0 := ARENA_R + TIER_DEPTH * t
			# The top tier runs all the way back to the outer wall (no gap to fall into).
			var r1 := r0 + TIER_DEPTH if t < TIERS - 1 else OUTER_R - 2.5
			var h := 4.0 + t * TIER_RISE
			# A block filling this wedge of the tier: as wide as the outer edge so there
			# are no gaps between neighbours.
			var rm := (r0 + r1) / 2.0
			var width := 2.0 * r1 * sin(step / 2.0) + 0.4
			var c := Vector2.from_angle(mid) * rm
			box(Vector3(c.x, h / 2.0, c.y), Vector3(r1 - r0, h, width), _stone if t % 2 == 0 else _stone_dark, -mid)
	# The podium's bronze trim along the front of the lowest tier.
	for i in SEGMENTS:
		if i % AISLE_EVERY == 0:
			continue
		var mid := step * (i + 0.5)
		var c := Vector2.from_angle(mid) * (ARENA_R - 0.2)
		deco(Vector3(c.x, 3.6, c.y), Vector3(0.6, 0.8, 2.0 * ARENA_R * sin(step / 2.0)), _bronze, -mid)


## Marble columns along the back of the top tier, joined by a stone beam.
func _build_colonnade() -> void:
	var base := 4.0 + (TIERS - 1) * TIER_RISE
	var r := ARENA_R + TIER_DEPTH * TIERS - 3.0
	var count := 32
	for i in count:
		var a := TAU * i / count
		var p := Vector2.from_angle(a) * r
		box(Vector3(p.x, base + 14.0, p.y), Vector3(3.0, 28.0, 3.0), _marble, -a)
	ring(Vector2.ZERO, r, count, base + 28.0, 3.0, 4.0, _stone)


func _build_center() -> void:
	# Raised dais with a ramp down each side.
	box(Vector3(0, 1.5, 0), Vector3(30, 3, 30), _marble)
	for k in 4:
		var yaw := TAU * k / 4.0
		var out := Vector3(sin(yaw), 0.0, cos(yaw))
		ramp(out * 33.0, out * 15.0 + Vector3.UP * 3.0, 10.0, _stone)
	# Broken columns: all different heights, some toppled.
	for i in 10:
		var a := TAU * (i + 0.3) / 10.0 + _rng.randf_range(-0.1, 0.1)
		var p := Vector2.from_angle(a) * _rng.randf_range(42.0, 56.0)
		if _rng.randf() < 0.3:
			# Toppled: lying on its side.
			box(Vector3(p.x, 1.6, p.y), Vector3(3.2, 3.2, _rng.randf_range(10.0, 16.0)), _marble, _rng.randf() * TAU)
		else:
			var h := _rng.randf_range(6.0, 22.0)
			box(Vector3(p.x, h / 2.0, p.y), Vector3(3.2, h, 3.2), _marble, a)
	# Gladiator barricades.
	for i in 6:
		var a := TAU * i / 6.0
		var p := Vector2.from_angle(a) * 72.0
		box(Vector3(p.x, 2.0, p.y), Vector3(14.0, 4.0, 2.0), _stone_dark, -a + PI / 2.0)
