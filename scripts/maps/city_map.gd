extends "res://scripts/maps/map_builder.gd"
## "City": a night-time downtown with many floors to fight on. A 5 x 5 grid of blocks
## with streets between:
##   - Garages: open-sided parking structures, FLOORS levels high, with ramps spiralling
##     up (alternating sides) to a roof with a parapet. Skybridges join neighbouring
##     garages on the third floor.
##   - Towers: tall solid buildings with lit windows (cover and sightline blockers).
##   - Low blocks: two-storey buildings with a ramp up to the roof.
##   - The middle block is an open plaza.
## Street lamps along the roads; a high boundary wall round it all.

const SEED := 6061
const GRID := 5
const BLOCK := 56.0
const STREET := 26.0
const PITCH := BLOCK + STREET
const FLOORS := 5
const FLOOR_HEIGHT := 8.0
const SLAB := 0.8
const BOUNDARY_HEIGHT := 170.0
## Which block is what (G garage, T tower, L low block, P plaza), row by row.
const PLAN := [
	"GGTLT",
	"TLGTL",
	"LTPGG",
	"GTLGT",
	"GLTGL",
]

var _road := checker(Color(0.12, 0.12, 0.14), Color(0.14, 0.14, 0.16), 6.0)
var _concrete := panel(Color(0.42, 0.42, 0.44), Color(0.36, 0.36, 0.38), 8.0)
var _concrete_dark := solid(Color(0.3, 0.3, 0.32))
var _rail := solid(Color(0.55, 0.57, 0.6), 0.4, 0.7)
var _stripe := glow(Color(1.0, 0.75, 0.25), 1.6)
var _lamp := glow(Color(1.0, 0.85, 0.55), 5.0)
var _tower_mats: Array = []


func _build() -> void:
	_rng.seed = SEED
	_ceiling = BOUNDARY_HEIGHT - 20.0
	var half := GRID * PITCH / 2.0 + 4.0
	var bounds := Rect2(-half, -half, half * 2.0, half * 2.0)
	_outline = rect_outline(bounds)
	ground(bounds.grow(8.0), _road)
	for k in 4:
		var yaw := TAU * k / 4.0
		var out := Vector3(sin(yaw), 0.0, cos(yaw))
		box(out * (half + 2.0) + Vector3.UP * BOUNDARY_HEIGHT / 2.0, Vector3(half * 2.0 + 8.0, BOUNDARY_HEIGHT, 4.0), _concrete_dark, yaw)
	for tint in [Color(1.0, 0.82, 0.5), Color(0.6, 0.85, 1.0), Color(0.9, 0.6, 1.0)]:
		var m := panel(Color(0.16, 0.17, 0.2), Color(0.22, 0.23, 0.27), 3.5, 0.0, 0.45)
		m.set_shader_parameter("window_color", tint)
		_tower_mats.append(m)
	for row in GRID:
		for col in GRID:
			var c := _center(col, row)
			match PLAN[row][col]:
				"G":
					_garage(c)
					# On the roof, on the solid side (the top ramp's slot is on +x).
					if _rng.randf() < 0.5:
						_turrets.append(Vector3(c.x - 14.0, FLOORS * FLOOR_HEIGHT, c.y - 14.0))
				"T":
					_tower(c)
				"L":
					_low_block(c)
				"P":
					_plaza(c)
	_skybridges()
	_street_lamps()
	# Spawns in the streets, spread round the city.
	for i in 8:
		var a := TAU * (i + 0.5) / 8.0
		var p := Vector2.from_angle(a) * PITCH * 1.5
		# Snap onto the nearest street line (between blocks).
		p.x = (roundf(p.x / PITCH - 0.5) + 0.5) * PITCH
		_spawns.append(Vector3(p.x, 1.0, p.y))
	# Turrets: at least four, on garage roofs (topped up from the plaza corners).
	var extra := 0
	while _turrets.size() < 4:
		var p := Vector2(1.0 if extra % 2 == 0 else -1.0, 1.0 if extra < 2 else -1.0) * 20.0
		_turrets.append(Vector3(p.x, 0.0, p.y))
		extra += 1


func _center(col: int, row: int) -> Vector2:
	var offset := (GRID - 1) / 2.0
	return Vector2(col - offset, row - offset) * PITCH


## Open-sided parking structure. Floor k's ramp runs up along one side (+x on odd
## floors, -x on even), so they spiral; each slab has a slot cut where the ramp from
## below comes up through it.
func _garage(c: Vector2) -> void:
	var h := BLOCK / 2.0 - 3.0  # Half footprint.
	var strip := 12.0  # Width of the ramp slot.
	var ramp_z := h - 6.0
	for k in range(1, FLOORS + 1):
		var y := k * FLOOR_HEIGHT
		var s := 1.0 if k % 2 == 1 else -1.0
		# Slab, minus the slot on side s from the back edge to where the ramp lands.
		var main_w := h * 2.0 - strip
		box(Vector3(c.x - s * strip / 2.0, y - SLAB / 2.0, c.y), Vector3(main_w, SLAB, h * 2.0), _concrete)
		var land := h - ramp_z
		box(Vector3(c.x + s * (h - strip / 2.0), y - SLAB / 2.0, c.y + ramp_z + land / 2.0), Vector3(strip, SLAB, land), _concrete)
		# The ramp up to it, from the floor below.
		var x := c.x + s * (h - strip / 2.0)
		ramp(Vector3(x, y - FLOOR_HEIGHT, c.y - ramp_z), Vector3(x, y, c.y + ramp_z), strip - 2.0, _concrete_dark)
		# Yellow edge stripe so floors read from a distance.
		for side: float in [-1.0, 1.0]:
			deco(Vector3(c.x, y - SLAB - 0.2, c.y + side * h), Vector3(h * 2.0, 0.35, 0.3), _stripe)
	# Columns at the corners and mid-sides.
	var top := FLOORS * FLOOR_HEIGHT
	for px: float in [-1.0, 0.0, 1.0]:
		for pz: float in [-1.0, 1.0]:
			box(Vector3(c.x + px * (h - 1.0), top / 2.0, c.y + pz * (h - 1.0)), Vector3(2, top, 2), _concrete_dark)
	# Roof parapet (low, so you can jump off).
	for side: float in [-1.0, 1.0]:
		box(Vector3(c.x, top + 0.6, c.y + side * (h - 0.3)), Vector3(h * 2.0, 1.2, 0.6), _rail)
		box(Vector3(c.x + side * (h - 0.3), top + 0.6, c.y), Vector3(0.6, 1.2, h * 2.0), _rail)


func _tower(c: Vector2) -> void:
	var w := _rng.randf_range(34.0, 48.0)
	var d := _rng.randf_range(34.0, 48.0)
	var h := _rng.randf_range(45.0, 125.0)
	var mat: Material = _tower_mats[_rng.randi() % _tower_mats.size()]
	box(Vector3(c.x, h / 2.0, c.y), Vector3(w, h, d), mat)
	# Some towers step back near the top.
	if _rng.randf() < 0.5:
		var h2 := _rng.randf_range(12.0, 30.0)
		box(Vector3(c.x, h + h2 / 2.0, c.y), Vector3(w * 0.6, h2, d * 0.6), mat)
	# A red aircraft light on the roof.
	deco(Vector3(c.x, h + 0.6, c.y), Vector3(1.2, 1.2, 1.2), glow(Color(1.0, 0.15, 0.1), 6.0))


## Two storeys with a ramp up to the roof along one side.
func _low_block(c: Vector2) -> void:
	var h := BLOCK / 2.0 - 3.0
	var height := 7.0
	var lane := 12.0
	var flip := 1.0 if _rng.randf() < 0.5 else -1.0
	box(Vector3(c.x, height / 2.0, c.y - flip * lane / 2.0), Vector3(h * 2.0, height, h * 2.0 - lane), _concrete)
	var z := c.y + flip * (h - lane / 2.0)
	ramp(Vector3(c.x - h, 0.0, z), Vector3(c.x + h - 4.0, height, z), lane - 1.0, _concrete_dark)
	box(Vector3(c.x + h - 2.0, height / 2.0, z), Vector3(4.0, height, lane), _concrete)
	# Rooftop clutter for cover.
	for i in 2:
		var p := c + Vector2(_rng.randf_range(-h + 6.0, h - 6.0), -flip * _rng.randf_range(0.0, h - lane - 4.0))
		box(Vector3(p.x, height + 1.5, p.y), Vector3(5, 3, 5), _rail)


func _plaza(c: Vector2) -> void:
	# A low fountain in the middle and planters round it.
	box(Vector3(c.x, 1.0, c.y), Vector3(16, 2, 16), _concrete)
	deco(Vector3(c.x, 2.05, c.y), Vector3(12, 0.1, 12), glow(Color(0.3, 0.7, 1.0), 1.5))
	for k in 4:
		var a := TAU * (k + 0.5) / 4.0
		var p := c + Vector2.from_angle(a) * 20.0
		box(Vector3(p.x, 0.75, p.y), Vector3(6, 1.5, 6), _concrete_dark)


## Bridges across the street between garages that sit side by side, on the third floor.
func _skybridges() -> void:
	var y := 3.0 * FLOOR_HEIGHT
	for row in GRID:
		for col in GRID:
			if PLAN[row][col] != "G":
				continue
			for d: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
				var c2 := Vector2i(col, row) + d
				if c2.x >= GRID or c2.y >= GRID or PLAN[c2.y][c2.x] != "G":
					continue
				var a := _center(col, row)
				var b := _center(c2.x, c2.y)
				var dir := Vector2(d).normalized()
				var side := Vector2(-dir.y, dir.x)
				# North-south bridges run down the middle. East-west ones keep to the +z
				# edge: the third floor's ramp slot runs along the east side, all but its
				# last few metres (the landing).
				var width := 10.0 if d.x == 0 else 6.0
				var shift := Vector2.ZERO if d.x == 0 else Vector2(0.0, BLOCK / 2.0 - 3.0 - width / 2.0)
				var from := a + dir * (BLOCK / 2.0 - 3.0) + shift
				var to := b - dir * (BLOCK / 2.0 - 3.0) + shift
				var mid := (from + to) / 2.0
				var yaw := -dir.angle()
				box(Vector3(mid.x, y - SLAB / 2.0, mid.y), Vector3(from.distance_to(to) + 2.0, SLAB, width), _concrete, yaw)
				for s: float in [-1.0, 1.0]:
					var p := mid + side * width / 2.0 * s
					box(Vector3(p.x, y + 0.6, p.y), Vector3(from.distance_to(to), 1.2, 0.4), _rail, yaw)


## Lamps down the middle of the streets between blocks, beside each block, with a light
## on every other one.
func _street_lamps() -> void:
	for i in GRID - 1:
		var line := (i - (GRID - 2) / 2.0) * PITCH
		for j in GRID:
			var along := _center(j, 0).x
			for axis in 2:
				var p := Vector2(line, along) if axis == 0 else Vector2(along, line)
				box(Vector3(p.x, 4.0, p.y), Vector3(0.5, 8.0, 0.5), _rail)
				deco(Vector3(p.x, 8.3, p.y), Vector3(1.4, 0.5, 1.4), _lamp)
				if (i + j) % 2 == 0:
					var light := OmniLight3D.new()
					light.position = Vector3(p.x, 7.0, p.y)
					light.light_color = Color(1.0, 0.8, 0.55)
					light.light_energy = 1.6
					light.omni_range = 28.0
					add_child(light)
