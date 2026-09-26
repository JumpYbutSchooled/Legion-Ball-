extends "res://scripts/maps/map_builder.gd"
## "El Dorado": the City of Gold, lost in the jungle. A great gold-capped step pyramid
## stands over a plaza of golden flagstones, with a stairway (a ramp) up each face to the
## shrine on top. Smaller temples, gold-roofed halls and statues line the causeways that
## run out to the four corners. The sacred lake sits to the east with a golden raft in
## the middle. Thick jungle fills the gaps and cliffs close it all in.

const SEED := 1541
const HALF := 200.0
const PYRAMID_TIERS := 6
const TIER_RISE := 5.0
const BASE := 90.0

var _gold := solid(Color(1.0, 0.78, 0.25), 0.25, 1.0)
var _gold_dark := solid(Color(0.8, 0.55, 0.15), 0.35, 1.0)
var _stone := panel(Color(0.62, 0.55, 0.42), Color(0.52, 0.46, 0.34), 3.0)
var _stone_dark := panel(Color(0.48, 0.42, 0.32), Color(0.4, 0.35, 0.26), 3.0)
var _plaza := checker(Color(0.85, 0.66, 0.25), Color(0.78, 0.6, 0.22), 6.0)
var _jungle := checker(Color(0.12, 0.32, 0.14), Color(0.14, 0.36, 0.16), 10.0)
var _leaves := [solid(Color(0.12, 0.4, 0.15)), solid(Color(0.18, 0.48, 0.18)), solid(Color(0.1, 0.33, 0.12))]
var _trunk := solid(Color(0.3, 0.2, 0.12))
var _water := glow(Color(0.15, 0.55, 0.45), 0.6)
var _cliff := solid(Color(0.4, 0.34, 0.26))


func _build() -> void:
	_rng.seed = SEED
	_ceiling = 100.0
	var bounds := Rect2(-HALF, -HALF, HALF * 2.0, HALF * 2.0)
	_outline = rect_outline(bounds)
	ground(bounds.grow(12.0), _jungle)
	# The golden plaza round the pyramid, and causeways to the corners.
	box(Vector3(0, 0.1, 0), Vector3(170, 0.4, 170), _plaza)
	for k in 4:
		var a := PI / 4.0 + TAU * k / 4.0
		var c := Vector2.from_angle(a) * 135.0
		box(Vector3(c.x, 0.1, c.y), Vector3(110.0, 0.4, 16.0), _plaza, -a)
	_pyramid()
	_temples()
	_lake()
	_jungle_trees()
	# Cliffs all round.
	for k in 4:
		var yaw := TAU * k / 4.0
		var out := Vector3(sin(yaw), 0.0, cos(yaw))
		box(out * (HALF + 6.0) + Vector3.UP * 45.0, Vector3(HALF * 2.0 + 24.0, 90.0, 12.0), _cliff, yaw)
	for i in 8:
		var a := TAU * (i + 0.5) / 8.0
		var p := Vector2.from_angle(a) * (70.0 if i % 2 == 0 else 150.0)
		_spawns.append(Vector3(p.x, 1.0, p.y))
	for k in 4:
		var a := PI / 4.0 + TAU * k / 4.0
		var p := Vector2.from_angle(a) * 170.0
		_turrets.append(Vector3(p.x, 0.0, p.y))


## The great pyramid: stepped gold-trimmed tiers, a ramp up the middle of each face, and a
## shrine with a gold roof on top.
func _pyramid() -> void:
	for t in PYRAMID_TIERS:
		var size := BASE - t * 13.0
		var y := t * TIER_RISE
		box(Vector3(0, y + TIER_RISE / 2.0, 0), Vector3(size, TIER_RISE, size), _stone if t % 2 == 0 else _stone_dark)
		# A gold band along each tier's lip.
		for k in 4:
			var yaw := TAU * k / 4.0
			var out := Vector3(sin(yaw), 0.0, cos(yaw))
			deco(out * (size / 2.0 + 0.05) + Vector3.UP * (y + TIER_RISE - 0.4), Vector3(size, 0.8, 0.3), _gold, yaw)
	var top := PYRAMID_TIERS * TIER_RISE
	var top_size := BASE - (PYRAMID_TIERS - 1) * 13.0
	# Stairways: one ramp per face from the plaza to the top tier.
	for k in 4:
		var yaw := TAU * k / 4.0
		var out := Vector3(sin(yaw), 0.0, cos(yaw))
		ramp(out * (BASE / 2.0 + 30.0), out * (top_size / 2.0) + Vector3.UP * top, 12.0, _gold_dark)
	# The shrine: a gold-roofed hall on four pillars.
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			pillar(Vector2(sx * 8.0, sz * 8.0), top, 2.5, 10.0, _stone)
	box(Vector3(0, top + 11.0, 0), Vector3(22.0, 2.0, 22.0), _gold)
	box(Vector3(0, top + 13.5, 0), Vector3(12.0, 3.0, 12.0), _gold)
	var light := OmniLight3D.new()
	light.position = Vector3(0, top + 6.0, 0)
	light.light_color = Color(1.0, 0.75, 0.35)
	light.light_energy = 2.5
	light.omni_range = 80.0
	add_child(light)


## Along each causeway: a small step temple and a pair of gold statues; gold-roofed halls
## between the causeways.
func _temples() -> void:
	for k in 4:
		var a := PI / 4.0 + TAU * k / 4.0
		var c := Vector2.from_angle(a) * 150.0
		for t in 3:
			var size := 26.0 - t * 7.0
			box(Vector3(c.x, t * 3.0 + 1.5, c.y), Vector3(size, 3.0, size), _stone_dark if t % 2 == 0 else _stone, -a)
		box(Vector3(c.x, 10.0, c.y), Vector3(8.0, 2.0, 8.0), _gold, -a)
		# Statues: a block body and head, all gold.
		for s: float in [-1.0, 1.0]:
			var p := Vector2.from_angle(a) * 105.0 + Vector2.from_angle(a + PI / 2.0) * 11.0 * s
			pillar(p, 0.0, 3.5, 7.0, _gold_dark, -a)
			box(Vector3(p.x, 8.5, p.y), Vector3(2.6, 3.0, 2.6), _gold, -a)
	for k in 4:
		var a := TAU * k / 4.0
		var c := Vector2.from_angle(a) * 118.0
		if k == 0:
			continue  # East is the lake.
		box(Vector3(c.x, 3.5, c.y), Vector3(30.0, 7.0, 18.0), _stone, -a + PI / 2.0)
		box(Vector3(c.x, 7.6, c.y), Vector3(34.0, 1.2, 22.0), _gold, -a + PI / 2.0)
		ramp(Vector3(c.x, 0.0, c.y) + Vector3(cos(a), 0, sin(a)) * -26.0, Vector3(c.x, 8.2, c.y) + Vector3(cos(a), 0, sin(a)) * -11.0, 8.0, _stone_dark)


## The sacred lake to the east: a pool inside a low stone rim, with a golden raft on it.
func _lake() -> void:
	var c := Vector2(128.0, 0.0)
	box(Vector3(c.x, 0.15, c.y), Vector3(60.0, 0.3, 70.0), _water)
	for s: float in [-1.0, 1.0]:
		box(Vector3(c.x + s * 30.5, 0.6, c.y), Vector3(1.0, 1.2, 72.0), _stone_dark)
		box(Vector3(c.x, 0.6, c.y + s * 35.5), Vector3(62.0, 1.2, 1.0), _stone_dark)
	box(Vector3(c.x, 0.8, c.y), Vector3(16.0, 1.0, 12.0), _gold)
	for s: float in [-1.0, 1.0]:
		pillar(Vector2(c.x + s * 5.0, c.y), 1.3, 0.6, 6.0, _gold_dark)

## Jungle: trees (trunk and a block of leaves) scattered outside the plaza.
func _jungle_trees() -> void:
	var placed := 0
	var tries := 0
	while placed < 70 and tries < 400:
		tries += 1
		var p := Vector2(_rng.randf_range(-HALF + 10.0, HALF - 10.0), _rng.randf_range(-HALF + 10.0, HALF - 10.0))
		if absf(p.x) < 92.0 and absf(p.y) < 92.0:
			continue
		# Keep the causeways and the lake clear.
		var on_road := false
		for k in 4:
			var a := PI / 4.0 + TAU * k / 4.0
			var d := Vector2.from_angle(a)
			var along := p.dot(d)
			if along > 70.0 and absf(p.dot(Vector2(-d.y, d.x))) < 16.0:
				on_road = true
		if on_road or (p.x > 90.0 and absf(p.y) < 45.0):
			continue
		var h := _rng.randf_range(10.0, 22.0)
		pillar(p, 0.0, 1.6, h, _trunk)
		var crown := _rng.randf_range(8.0, 14.0)
		box(Vector3(p.x, h + crown / 3.0, p.y), Vector3(crown, crown * 0.7, crown), _leaves[_rng.randi() % _leaves.size()], _rng.randf() * PI)
		placed += 1
