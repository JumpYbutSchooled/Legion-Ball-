extends "res://scripts/maps/map_builder.gd"
## "Garden of Eden": Dante's Earthly Paradise (Divine Comedy, Purgatorio 28-33), on the
## summit of Mount Purgatory. The mountain rises out of the sea in seven terraces, each a
## ring with stairs up to the next; on the flat top is the divine forest. From one fountain
## in the middle run two rivers in opposite directions: Lethe (forgetting) and Eunoe
## (remembering good). At the back stands the huge Tree of Knowledge, and before it the
## griffin's chariot of the pageant, led by the seven golden candlesticks whose flames
## trail bands of colour across the sky.

const SUMMIT := 70.0
const TOP_R := 62.0
## Terrace radii, lowest first, and how much each rises.
const TERRACES := [150.0, 134.0, 118.0, 104.0, 92.0, 82.0, 72.0]
const STEP := 10.0

var _stone := solid(Color(0.62, 0.58, 0.52), 0.95)
var _stone2 := solid(Color(0.55, 0.51, 0.46), 0.95)
var _meadow := checker(Color(0.36, 0.62, 0.24), Color(0.33, 0.58, 0.22), 3.0)
var _bark := solid(Color(0.36, 0.24, 0.14), 0.9)
var _leaf := solid(Color(0.22, 0.55, 0.2), 0.8)
var _leaf2 := solid(Color(0.3, 0.62, 0.18), 0.8)
var _blossom := glow(Color(1.0, 0.72, 0.85), 0.8)
var _lethe := glow(Color(0.55, 0.8, 1.0), 1.4)
var _eunoe := glow(Color(0.7, 1.0, 0.8), 1.4)
var _gold := solid(Color(1.0, 0.8, 0.3), 0.25, 0.9)
var _white := solid(Color(0.97, 0.96, 0.92), 0.4)
var _sea := solid(Color(0.08, 0.22, 0.42), 0.15, 0.2)


## Built at twice its written size in every direction.
func map_size() -> float:
	return 2.0


func _build() -> void:
	_ceiling = 180.0
	_fall = -15.0
	_outline = circle_outline(TERRACES[0] + 6.0, 48)
	# The sea round the mountain (just to look at: falling in is falling off).
	deco(Vector3(0, -12.0, 0), Vector3(5000.0, 0.5, 5000.0), _sea)
	for i in TERRACES.size():
		var top := i * STEP
		var r: float = TERRACES[i]
		# Only each terrace's outer band: the terrace above (and the summit) covers the
		# rest, so a full disc here was hundreds of blocks nobody could see or touch. The
		# bands overlap 2 m sideways and down, so the mountain stays sealed.
		var inner: float = (TERRACES[i + 1] if i + 1 < TERRACES.size() else TOP_R) - 2.0
		annulus(Vector3(0, top, 0), inner, r, STEP + 2.0, _stone if i % 2 == 0 else _stone2)
		# A low parapet round the outer edge, with a gap where the stairs from below arrive.
		var gaps := []
		if i > 0:
			var seg := int(floor(_stair_angle(i - 1) / TAU * 40.0))
			gaps = [posmod(seg - 1, 40), posmod(seg, 40), posmod(seg + 1, 40)]
		ring(Vector2.ZERO, r - 1.0, 40, top, 1.2, 1.0, _stone2, gaps)
		# Stairs cut into the cliff up to the next terrace.
		if i + 1 < TERRACES.size():
			var a := _stair_angle(i)
			var next: float = TERRACES[i + 1]
			var foot := Vector2.from_angle(a) * (next + 6.0)
			stairs(Vector3(foot.x, top, foot.y), -Vector2.from_angle(a), 10, STEP / 10.0, 1.2, 8.0, _stone2)
	# The summit: the meadow of the divine forest.
	var s := (TERRACES.size() - 1) * STEP
	stairs(Vector3(cos(0.4) * (TOP_R + 6.0), s, sin(0.4) * (TOP_R + 6.0)), -Vector2.from_angle(0.4), 10, (SUMMIT - s) / 10.0, 1.2, 10.0, _stone)
	disc(Vector3(0, SUMMIT, 0), TOP_R, SUMMIT - s + 2.0, _stone, 5)
	# The meadow is just the grass on the stone: decoration, a hair above it (no blocks).
	disc(Vector3(0, SUMMIT + 0.05, 0), TOP_R - 1.0, 0.3, _meadow, 5, false, false)
	_rivers()
	_forest()
	_tree_of_knowledge(Vector3(0, SUMMIT, -40.0))
	_chariot(Vector3(0, SUMMIT, -18.0))
	_candlesticks()
	for i in 8:
		var a := TAU * i / 8.0 + 0.2
		_spawns.append(Vector3(cos(a) * 40.0, SUMMIT + 1.5, sin(a) * 40.0 + 6.0))
	for i in 3:
		var a := TAU * i / 3.0
		_turrets.append(Vector3(cos(a) * 140.0, 1.0, sin(a) * 140.0))
	var light := OmniLight3D.new()
	light.position = Vector3(0, SUMMIT + 40.0, 0)
	light.light_color = Color(1.0, 0.9, 0.7)
	light.light_energy = 1.2
	light.omni_range = 140.0
	add_child(light)


## Where the stairs up from terrace `i` are (each flight a bit further round).
func _stair_angle(i: int) -> float:
	return fposmod(TAU * (i * 5 + 0.5) / 40.0 + 0.4, TAU)


## One spring in the middle; Lethe runs off east, Eunoe west, in shallow glowing beds.
func _rivers() -> void:
	var y := SUMMIT + 0.1
	box(Vector3(0, y + 1.0, 6.0), Vector3(7.0, 2.0, 7.0), _white)
	deco(Vector3(0, y + 2.2, 6.0), Vector3(5.0, 0.4, 5.0), _lethe)
	for s: float in [-1.0, 1.0]:
		var mat := _lethe if s > 0.0 else _eunoe
		for k in 7:
			var x0 := s * (4.0 + k * 8.0)
			var z := 6.0 + sin(k * 0.9) * 4.0
			deco(Vector3(x0 + s * 4.0, y + 0.35, z), Vector3(8.6, 0.1, 4.0), mat)
			# Banks: low stones either side.
			for side: float in [-1.0, 1.0]:
				box(Vector3(x0 + s * 4.0, y + 0.6, z + side * 2.6), Vector3(8.6, 0.6, 0.8), _stone2)


func _tree(p: Vector3, height: float, width: float) -> void:
	box(p + Vector3(0, height / 2.0, 0), Vector3(width, height, width), _bark, _rng.randf() * TAU)
	var crown := height * 0.45
	box(p + Vector3(0, height + crown * 0.2, 0), Vector3(crown * 1.4, crown * 0.8, crown * 1.4), _leaf, _rng.randf() * TAU)
	box(p + Vector3(0, height + crown * 0.6, 0), Vector3(crown, crown * 0.7, crown), _leaf2, _rng.randf() * TAU)


## The divine forest: trees all round the edge of the summit, thinning to open meadow in
## the middle; flowers everywhere.
func _forest() -> void:
	for i in 55:
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(24.0, TOP_R - 5.0)
		var p := Vector2.from_angle(a) * r
		if absf(p.y - 6.0) < 5.0:
			continue  # Leave the rivers open.
		_tree(Vector3(p.x, SUMMIT, p.y), _rng.randf_range(8.0, 15.0), _rng.randf_range(1.0, 1.8))
	var flowers := [glow(Color(1.0, 0.3, 0.4), 1.0), glow(Color(1.0, 0.9, 0.3), 1.0), glow(Color(0.8, 0.5, 1.0), 1.0), _white]
	for i in 160:
		var p := Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(3.0, TOP_R - 2.0)
		deco(Vector3(p.x, SUMMIT + 0.6, p.y), Vector3(0.5, 0.5, 0.5), flowers[i % flowers.size()], _rng.randf())


## The Tree of Knowledge: enormous, spreading wider the higher it goes, in blossom.
func _tree_of_knowledge(p: Vector3) -> void:
	box(p + Vector3(0, 20.0, 0), Vector3(5.0, 40.0, 5.0), _bark)
	for k in 5:
		var y := 24.0 + k * 5.0
		var w := 12.0 + k * 7.0
		box(p + Vector3(0, y, 0), Vector3(w, 1.2, 1.2), _bark, k * 0.7)
		box(p + Vector3(0, y + 2.0, 0), Vector3(w * 0.9, 3.0, w * 0.6), _leaf, k * 0.7 + 0.3)
		for b in 6:
			var q := Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(2.0, w * 0.45)
			deco(p + Vector3(q.x, y + 3.8, q.y), Vector3(1.6, 1.6, 1.6), _blossom, _rng.randf())


## The griffin's two-wheeled chariot of the pageant, the griffin (gold eagle in front,
## white lion behind) in the shafts.
func _chariot(p: Vector3) -> void:
	box(p + Vector3(0, 3.0, 0), Vector3(6.0, 3.0, 5.0), _gold)
	for s: float in [-1.0, 1.0]:
		box(p + Vector3(s * 3.4, 2.4, 0), Vector3(0.6, 4.8, 4.8), _gold, 0.0, PI / 4.0)
		box(p + Vector3(s * 3.4, 2.4, 0), Vector3(0.6, 4.8, 4.8), _gold)
	box(p + Vector3(0, 2.6, 7.0), Vector3(0.6, 0.6, 9.0), _gold)
	var g := p + Vector3(0, 0, 12.0)
	box(g + Vector3(0, 3.0, -1.5), Vector3(3.0, 3.0, 5.0), _white)
	box(g + Vector3(0, 4.5, 1.8), Vector3(2.4, 3.0, 2.6), _gold)
	box(g + Vector3(0, 6.2, 2.8), Vector3(1.2, 1.2, 2.0), _gold)
	for s: float in [-1.0, 1.0]:
		box(g + Vector3(s * 3.0, 6.5, 0.0), Vector3(5.0, 0.4, 3.0), _gold, 0.0, s * 0.4)


## Seven golden candlesticks in a row, each flame trailing a band of colour into the sky.
func _candlesticks() -> void:
	var colours := [Color(1, 0.2, 0.2), Color(1, 0.55, 0.1), Color(1, 0.95, 0.2), Color(0.3, 1, 0.3), Color(0.25, 0.6, 1), Color(0.35, 0.3, 1), Color(0.8, 0.3, 1)]
	for i in 7:
		var x := -18.0 + i * 6.0
		var p := Vector3(x, SUMMIT, 30.0)
		box(p + Vector3(0, 0.5, 0), Vector3(2.0, 1.0, 2.0), _gold)
		box(p + Vector3(0, 5.0, 0), Vector3(0.6, 9.0, 0.6), _gold)
		deco(p + Vector3(0, 10.0, 0), Vector3(0.8, 1.4, 0.8), glow(colours[i], 6.0))
		# The trail of colour: a long glowing band rising back over the summit.
		deco(p + Vector3(0, 30.0, -40.0), Vector3(2.5, 0.4, 90.0), glow(colours[i], 2.5)).rotation.x = 0.35
