extends "res://scripts/maps/map_builder.gd"
## "Gotham": a dark gothic city at night, packed tight. Narrow streets between blocks of
## soot-black towers that step back as they rise, crowned with spires and gargoyle
## ledges; lower buildings in between have flat roofs with water towers, and zig-zag fire
## escapes up their sides. An elevated train line loops round the whole city on pillars
## (ramps up at the four corner stations), and Wayne Tower rises out of the middle. On
## the police headquarters' roof, the signal shines up into the fog.

const SEED := 1939
const GRID := 6
const BLOCK := 38.0
const STREET := 18.0
const PITCH := BLOCK + STREET
const TRAIN_Y := 30.0
const WALL_HEIGHT := 200.0

var _street := checker(Color(0.07, 0.07, 0.08), Color(0.09, 0.09, 0.1), 5.0)
var _soot := panel(Color(0.13, 0.12, 0.13), Color(0.18, 0.17, 0.18), 4.0)
var _soot_windows := panel(Color(0.11, 0.1, 0.11), Color(0.15, 0.14, 0.15), 3.0, 0.0, 0.35)
var _brick := panel(Color(0.28, 0.16, 0.13), Color(0.2, 0.12, 0.1), 2.5)
var _stone := panel(Color(0.32, 0.31, 0.3), Color(0.25, 0.24, 0.23), 3.0)
var _iron := solid(Color(0.18, 0.19, 0.2), 0.5, 0.7)
var _sodium := glow(Color(1.0, 0.6, 0.25), 5.0)
var _signal := glow(Color(1.0, 0.95, 0.7), 8.0)


func _build() -> void:
	_rng.seed = SEED
	_ceiling = 180.0
	var half := GRID * PITCH / 2.0 + STREET
	var bounds := Rect2(-half, -half, half * 2.0, half * 2.0)
	_outline = rect_outline(bounds)
	ground(bounds.grow(8.0), _street)
	for k in 4:
		var yaw := TAU * k / 4.0
		var out := Vector3(sin(yaw), 0.0, cos(yaw))
		box(out * (half + 2.0) + Vector3.UP * WALL_HEIGHT / 2.0, Vector3(half * 2.0 + 8.0, WALL_HEIGHT, 4.0), _soot, yaw)
	_soot_windows.set_shader_parameter("window_color", Color(1.0, 0.75, 0.4))
	var mid := (GRID - 1) / 2.0
	for row in GRID:
		for col in GRID:
			var c := Vector2(col - mid, row - mid) * PITCH
			if row == 2 and col == 2:
				_wayne_tower(c)
			elif row == 3 and col == 3:
				_police_hq(c)
			elif _rng.randf() < 0.45:
				_gothic_tower(c)
			else:
				_low_building(c)
	_train_loop(half)
	# Turrets up on the train line's corners.
	var r := half - STREET / 2.0 - 2.0
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_turrets.append(Vector3(sx * r, TRAIN_Y, sz * r))
	_street_lamps()
	# Spawns at street crossings.
	for i in 8:
		var a := TAU * (i + 0.5) / 8.0
		var p := Vector2.from_angle(a) * PITCH * 1.6
		p = (p / PITCH).round() * PITCH
		_spawns.append(Vector3(p.x, 1.0, p.y))


## A tall tower stepping back in tiers, with gargoyle ledges and a spire on top.
func _gothic_tower(c: Vector2) -> void:
	var w := _rng.randf_range(26.0, 34.0)
	var y := 0.0
	var tiers := _rng.randi_range(2, 4)
	for t in tiers:
		var h := _rng.randf_range(25.0, 45.0)
		box(Vector3(c.x, y + h / 2.0, c.y), Vector3(w, h, w), _soot_windows if t % 2 == 0 else _soot)
		# Gargoyle ledges: little blocks jutting out of each corner at the top of the tier.
		for sx: float in [-1.0, 1.0]:
			for sz: float in [-1.0, 1.0]:
				box(Vector3(c.x + sx * (w / 2.0 + 1.0), y + h - 1.0, c.y + sz * (w / 2.0 + 1.0)), Vector3(3.0, 2.0, 3.0), _stone)
		y += h
		w *= 0.72
	# The spire: two thin stacked pillars.
	pillar(c, y, w * 0.5, 14.0, _soot)
	pillar(c, y + 14.0, 1.2, 16.0, _iron)
	deco(Vector3(c.x, y + 30.5, c.y), Vector3(1.0, 1.0, 1.0), glow(Color(1.0, 0.15, 0.1), 5.0))


## Lower brick building with a flat roof, a water tower, and a zig-zag fire escape.
func _low_building(c: Vector2) -> void:
	var h := _rng.randf_range(16.0, 36.0)
	var w := BLOCK - 4.0
	box(Vector3(c.x, h / 2.0, c.y), Vector3(w, h, w), _brick)
	# Parapet.
	for s: float in [-1.0, 1.0]:
		box(Vector3(c.x, h + 0.75, c.y + s * (w / 2.0 - 0.4)), Vector3(w, 1.5, 0.8), _stone)
		if s < 0.0:  # The +x side stays open: the fire escape arrives there.
			box(Vector3(c.x + s * (w / 2.0 - 0.4), h + 0.75, c.y), Vector3(0.8, 1.5, w), _stone)
	# Water tower on legs.
	var t := c + Vector2(_rng.randf_range(-8.0, 8.0), _rng.randf_range(-8.0, 8.0))
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			pillar(t + Vector2(sx, sz) * 2.5, h, 0.6, 6.0, _iron)
	box(Vector3(t.x, h + 9.0, t.y), Vector3(7.0, 6.0, 7.0), solid(Color(0.3, 0.22, 0.16)))
	# Fire escape: ramps zig-zagging up the +x face, landing platforms at each turn.
	var x := c.x + w / 2.0 + 3.0
	var flights := ceili(h / 9.0)
	var y := 0.0
	for f in flights:
		var dir := 1.0 if f % 2 == 0 else -1.0
		var rise := minf(9.0, h - y)
		ramp(Vector3(x, y, c.y - dir * 13.0), Vector3(x, y + rise, c.y + dir * 11.0), 5.0, _iron)
		box(Vector3(x, y + rise - 0.3, c.y + dir * 14.5), Vector3(5.0, 0.6, 7.0), _iron)
		y += rise
	# The last landing reaches over the parapet onto the roof.
	box(Vector3(x - 3.5, y - 0.3, c.y), Vector3(7.0, 0.6, 6.0), _iron)


## The tallest tower, right of centre: glass-black with a lit crown and a mast.
func _wayne_tower(c: Vector2) -> void:
	var w := 34.0
	box(Vector3(c.x, 70.0, c.y), Vector3(w, 140.0, w), _soot_windows)
	box(Vector3(c.x, 150.0, c.y), Vector3(w * 0.7, 20.0, w * 0.7), _soot)
	deco(Vector3(c.x, 160.5, c.y), Vector3(w * 0.72, 1.0, w * 0.72), glow(Color(0.9, 0.85, 0.6), 4.0))
	pillar(c, 160.0, 1.5, 15.0, _iron)
	# A ledge ring halfway up.
	for s: float in [-1.0, 1.0]:
		box(Vector3(c.x, 70.0, c.y + s * (w / 2.0 + 1.5)), Vector3(w + 6.0, 1.0, 3.0), _stone)
		box(Vector3(c.x + s * (w / 2.0 + 1.5), 70.0, c.y), Vector3(3.0, 1.0, w + 6.0), _stone)


## Police headquarters: a squat stone block with the signal on its roof (a ramp up the
## back), pointing a beam up into the fog.
func _police_hq(c: Vector2) -> void:
	var w := BLOCK - 4.0
	var h := 24.0
	box(Vector3(c.x, h / 2.0, c.y), Vector3(w, h, w), _stone)
	ramp(Vector3(c.x - w / 2.0 - 3.0, 0.0, c.y + w / 2.0 + 3.0), Vector3(c.x - w / 2.0 - 3.0, h, c.y - w / 2.0 + 4.0), 5.0, _iron)
	box(Vector3(c.x - w / 2.0 - 0.5, h - 0.3, c.y - w / 2.0 + 2.0), Vector3(6.0, 0.6, 5.0), _iron)
	# The signal: a housing, its glowing lens, and a real spotlight tipped up.
	box(Vector3(c.x + 6.0, h + 2.0, c.y + 6.0), Vector3(5.0, 4.0, 5.0), _iron)
	deco(Vector3(c.x + 6.0, h + 4.2, c.y + 6.0), Vector3(4.2, 0.4, 4.2), _signal)
	var spot := SpotLight3D.new()
	spot.position = Vector3(c.x + 6.0, h + 5.0, c.y + 6.0)
	spot.rotation = Vector3(deg_to_rad(70.0), deg_to_rad(30.0), 0.0)
	spot.light_color = Color(1.0, 0.95, 0.75)
	spot.light_energy = 16.0
	spot.spot_range = 400.0
	spot.spot_angle = 6.0
	spot.light_volumetric_fog_energy = 4.0
	add_child(spot)


## The elevated train: a deck on pillars round the outer street, ramps up at the corners.
func _train_loop(half: float) -> void:
	var r := half - STREET / 2.0 - 2.0
	for k in 4:
		var yaw := TAU * k / 4.0
		var out := Vector3(sin(yaw), 0.0, cos(yaw))
		var side := Vector3(cos(yaw), 0.0, -sin(yaw))
		box(out * r + Vector3.UP * (TRAIN_Y - 0.5), Vector3(r * 2.0 + 10.0, 1.0, 10.0), _iron, yaw)
		for s: float in [-1.0, 1.0]:
			deco(out * (r + s * 4.8) + Vector3.UP * (TRAIN_Y + 0.6), Vector3(r * 2.0, 0.4, 0.3), _stone, yaw)
		for i in 12:
			var along := lerpf(-r, r, i / 11.0)
			var p := out * r + side * along
			pillar(Vector2(p.x, p.z), 0.0, 2.0, TRAIN_Y - 1.0, _iron)
		# Station ramp near each corner, running along the line.
		var foot := out * r + side * (r - 40.0 - 70.0)
		var head := out * r + side * (r - 40.0)
		ramp(Vector3(foot.x, 0.0, foot.z) - out * 9.0, Vector3(head.x, TRAIN_Y, head.z) - out * 9.0, 8.0, _stone)
		box(Vector3(head.x, TRAIN_Y - 0.5, head.z) - out * 5.5, Vector3(10.0, 1.0, 10.0), _stone, yaw)
	# A train stopped on the east side: three cars (cover up on the line).
	for i in 3:
		box(Vector3(r, TRAIN_Y + 3.0, -40.0 + i * 22.0), Vector3(6.0, 6.0, 20.0), panel(Color(0.3, 0.32, 0.3), Color(1.0, 0.8, 0.4), 2.0, 0.0, 0.5))


func _street_lamps() -> void:
	var mid := (GRID - 1) / 2.0
	for i in GRID + 1:
		var line := (i - mid - 0.5) * PITCH
		for j in GRID:
			if (i + j) % 2 != 0:
				continue
			var along := (j - mid) * PITCH
			for axis in 2:
				var p := Vector2(line, along) if axis == 0 else Vector2(along, line)
				pillar(p, 0.0, 0.5, 9.0, _iron)
				deco(Vector3(p.x, 9.3, p.y), Vector3(1.2, 0.5, 1.2), _sodium)
				if (i + j) % 4 == 0:
					var light := OmniLight3D.new()
					light.position = Vector3(p.x, 8.0, p.y)
					light.light_color = Color(1.0, 0.6, 0.3)
					light.light_energy = 1.8
					light.omni_range = 30.0
					add_child(light)
