extends Node3D
## "Sprawl", the online map, built in code when it loads. It is big and deliberately not
## a box: an irregular outer boundary, a walled hub in the middle, a broken ring road and
## four spokes carving it into sectors, all joined by doorways, with every wall far too
## tall to see over. Cover is scattered with a fixed seed, so every computer (and the
## server) builds exactly the same map.
## Builds in _ready, which runs before the parent Map's, so Map's particle colliders
## (spark_colliders.gd) cover all of this too.

const CheckerShader := preload("res://shaders/checker.gdshader")

## Taller than the ball's 120 m soft ceiling (ball.gd max_height), so nobody gets out.
const OUTER_HEIGHT := 150.0
const HUB_HEIGHT := 70.0
const WALL_HEIGHT := 60.0
const HUB_RADIUS := 90.0
const RING_RADIUS := 260.0
const DOOR := 22.0
const SPOKES := 4
const SEED := 7331
const COVER_COUNT := 90

## Outer boundary (x, z), going round the map: about 1040 x 860 m, no two sides alike.
const OUTLINE := [
	Vector2(-480, -120), Vector2(-380, -330), Vector2(-160, -400), Vector2(-60, -300),
	Vector2(120, -420), Vector2(380, -360), Vector2(500, -160), Vector2(440, 40),
	Vector2(520, 240), Vector2(360, 400), Vector2(100, 340), Vector2(-40, 440),
	Vector2(-300, 380), Vector2(-420, 220), Vector2(-520, 80),
]

## Cover in each of the six sectors gets its own tint, so you can tell where you are.
const SECTOR_TINTS := [
	Color(0.62, 0.45, 0.42), Color(0.58, 0.55, 0.38), Color(0.4, 0.56, 0.44),
	Color(0.38, 0.5, 0.6), Color(0.48, 0.42, 0.62), Color(0.6, 0.42, 0.56),
]

var _outline := PackedVector2Array(OUTLINE)
## Footprint [a, b] of every wall, so cover stays out of corridors and doorways.
var _segments: Array = []
## [center, radius] of everything scattered so far.
var _cover: Array = []
var _spawns: Array[Vector3] = []
var _turrets: Array[Vector3] = []
var _phys := PhysicsMaterial.new()
var _outer_mat := _solid(Color(0.34, 0.3, 0.4))
var _wall_mat := _solid(Color(0.52, 0.48, 0.54))
var _hub_mat := _solid(Color(0.42, 0.48, 0.6))
var _sector_mats: Array = []


func _ready() -> void:
	_phys.friction = 1.0
	for tint in SECTOR_TINTS:
		_sector_mats.append(_solid(tint))
	_build_floor()
	_build_outer_wall()
	_build_hub()
	_build_ring()
	_build_spokes()
	_pick_spawns()
	_place_turrets()
	_scatter_cover()


## Where players (re)spawn: one per sector near the hub first, then the outer band.
func spawn_points() -> Array[Vector3]:
	return _spawns


## Where the AI turrets stand (scripts/turrets.gd).
func turret_points() -> Array[Vector3]:
	return _turrets


## One turret beside each spoke, just out from the hub; cover is kept off them.
func _place_turrets() -> void:
	for k in SPOKES:
		var p := Vector2.from_angle(_spoke_angle(k) + 0.14) * 135.0
		_turrets.append(Vector3(p.x, 0.0, p.y))
		_cover.append([p, 6.0])


## Height where upward speed starts bleeding off (ball.gd max_height): just under the
## top of the outer wall, so the bleed-off overshoot stops right about at its lip.
func ceiling() -> float:
	return OUTER_HEIGHT - 8.0


## The boundary, for the minimap.
func outline() -> PackedVector2Array:
	return _outline


# --- Layout ---------------------------------------------------------------------------

func _build_floor() -> void:
	var bounds := Rect2(_outline[0], Vector2.ZERO)
	for p in _outline:
		bounds = bounds.expand(p)
	bounds = bounds.grow(10.0)
	var mat := ShaderMaterial.new()
	mat.shader = CheckerShader
	mat.set_shader_parameter("color_a", Color(0.5, 0.47, 0.5))
	mat.set_shader_parameter("color_b", Color(0.455, 0.43, 0.465))
	mat.set_shader_parameter("cell_size", 4.0)
	var c := bounds.get_center()
	_box(Vector3(c.x, -0.5, c.y), Vector3(bounds.size.x, 1.0, bounds.size.y), mat)


func _build_outer_wall() -> void:
	for i in _outline.size():
		_wall(_outline[i], _outline[(i + 1) % _outline.size()], OUTER_HEIGHT, 4.0, _outer_mat)


func _build_hub() -> void:
	# Eight walls, a doorway in the middle of each.
	for i in 8:
		var a := Vector2.from_angle(TAU * (i + 0.5) / 8.0) * HUB_RADIUS
		var b := Vector2.from_angle(TAU * (i + 1.5) / 8.0) * HUB_RADIUS
		_wall_with_door(a, b, 0.5, 20.0, HUB_HEIGHT, 3.0, _hub_mat)
	# Raised block in the middle with a ramp down each side (as in the practice arena).
	_box(Vector3(0, 1.5, 0), Vector3(30, 3, 30), _wall_mat)
	for k in 4:
		var yaw := TAU * k / 4.0
		var out := Vector3(sin(yaw), 0.0, cos(yaw))
		_box(out * 23.96 + Vector3(0, 1.253, 0), Vector3(10, 0.5, 18.25), _wall_mat, yaw, deg_to_rad(9.46))
	# Four tall pillars so the doorways don't look straight across the hub.
	for k in 4:
		var p := Vector2.from_angle(TAU * (k + 0.5) / 4.0) * 55.0
		_box(Vector3(p.x, 17.5, p.y), Vector3(7, 35, 7), _hub_mat)
		_cover.append([p, 5.0])


func _build_ring() -> void:
	# A 12-sided ring road wall with every third side left open; any side that would
	# poke out of the boundary is left open too.
	for i in 12:
		var a := Vector2.from_angle(TAU * i / 12.0) * RING_RADIUS
		var b := Vector2.from_angle(TAU * (i + 1) / 12.0) * RING_RADIUS
		if i % 3 != 2 and _inside(a, 30.0) and _inside(b, 30.0):
			_wall_with_door(a, b, 0.3 if i % 2 == 0 else 0.7, DOOR, WALL_HEIGHT, 3.0, _wall_mat)


func _build_spokes() -> void:
	# Walls from just outside the hub to the boundary, each with doorways.
	for k in SPOKES:
		var dir := Vector2.from_angle(_spoke_angle(k))
		var end := _outline_distance(dir) + 2.0
		var from := HUB_RADIUS + 15.0
		for door in [150.0, 320.0]:
			if door + DOOR > end - 20.0:
				break
			_wall(dir * from, dir * door, WALL_HEIGHT, 3.0, _wall_mat)
			from = door + DOOR
		_wall(dir * from, dir * end, WALL_HEIGHT, 3.0, _wall_mat)


func _pick_spawns() -> void:
	var outer: Array[Vector3] = []
	for k in SPOKES:
		# Halfway between two spokes.
		var dir := Vector2.from_angle(_spoke_angle(k + 0.5))
		var inner := dir * 185.0
		_spawns.append(Vector3(inner.x, 1.0, inner.y))
		var room := _outline_distance(dir) - RING_RADIUS
		if room > 60.0:
			var p := dir * (RING_RADIUS + room * 0.5)
			outer.append(Vector3(p.x, 1.0, p.y))
	_spawns.append_array(outer)


func _scatter_cover() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var bounds := Rect2(_outline[0], Vector2.ZERO)
	for p in _outline:
		bounds = bounds.expand(p)
	var placed := 0
	for attempt in 6000:
		if placed >= COVER_COUNT:
			break
		var p := Vector2(rng.randf_range(bounds.position.x, bounds.end.x), rng.randf_range(bounds.position.y, bounds.end.y))
		var yaw := rng.randf() * TAU
		var kind := rng.randf()
		var sx := rng.randf_range(6.0, 18.0)
		var sy := rng.randf_range(3.0, 12.0)
		var sz := rng.randf_range(6.0, 18.0)
		var tall := rng.randf_range(28.0, 50.0)
		var mat: Material = _sector_mats[_sector(p)]
		var r: float
		if kind < 0.35:
			# Block.
			r = Vector2(sx, sz).length() / 2.0
			if not _fits(p, r):
				continue
			_box(Vector3(p.x, sy / 2.0, p.y), Vector3(sx, sy, sz), mat, yaw)
		elif kind < 0.5:
			# Tower.
			var side := 6.0 + sx * 0.4
			r = side * 0.71
			if not _fits(p, r):
				continue
			_box(Vector3(p.x, tall / 2.0, p.y), Vector3(side, tall, side), mat, yaw)
		elif kind < 0.75:
			# Low cover wall.
			var length := 12.0 + sx
			var height := 4.0 + sy * 0.25
			r = length / 2.0
			if not _fits(p, r):
				continue
			_box(Vector3(p.x, height / 2.0, p.y), Vector3(length, height, 2.0), mat, yaw)
		elif kind < 0.9:
			# Kicker ramp.
			r = 6.0
			if not _fits(p, r):
				continue
			_box(Vector3(p.x, 1.26, p.y), Vector3(8, 0.5, 10.44), mat, yaw, deg_to_rad(16.7))
		else:
			# Plateau with a ramp up one side.
			var half := 10.0 + sz * 0.3
			r = half + 24.0
			if not _fits(p, r):
				continue
			_box(Vector3(p.x, 2.0, p.y), Vector3(half * 2.0, 4.0, half * 2.0), mat, yaw)
			var out := Vector3(sin(yaw), 0.0, cos(yaw))
			_box(Vector3(p.x, 1.753, p.y) + out * (half + 11.96), Vector3(10, 0.5, 24.33), mat, yaw, deg_to_rad(9.46))
		_cover.append([p, r])
		placed += 1


## True if something of radius `r` at `p` stays clear of the hub, walls, spawns and
## other cover.
func _fits(p: Vector2, r: float) -> bool:
	if p.length() < HUB_RADIUS + r + 10.0 or not _inside(p, r + 10.0):
		return false
	for s in _segments:
		if p.distance_to(Geometry2D.get_closest_point_to_segment(p, s[0], s[1])) < r + 8.0:
			return false
	for s in _spawns:
		if p.distance_to(Vector2(s.x, s.z)) < r + 14.0:
			return false
	for c in _cover:
		if p.distance_to(c[0]) < r + c[1] + 6.0:
			return false
	return true


# --- Helpers --------------------------------------------------------------------------

## Inside the boundary and at least `margin` from it.
func _inside(p: Vector2, margin: float) -> bool:
	if not Geometry2D.is_point_in_polygon(p, _outline):
		return false
	for i in _outline.size():
		var q := Geometry2D.get_closest_point_to_segment(p, _outline[i], _outline[(i + 1) % _outline.size()])
		if p.distance_to(q) < margin:
			return false
	return true


## How far from the centre the boundary is in direction `dir`.
func _outline_distance(dir: Vector2) -> float:
	var best := INF
	for i in _outline.size():
		var hit = Geometry2D.segment_intersects_segment(Vector2.ZERO, dir * 2000.0, _outline[i], _outline[(i + 1) % _outline.size()])
		if hit != null:
			best = minf(best, (hit as Vector2).length())
	return best


func _spoke_angle(k: float) -> float:
	return TAU * k / SPOKES + TAU / 24.0


## Which of the six tint zones `p` is in.
func _sector(p: Vector2) -> int:
	return int(fposmod(p.angle() - TAU / 24.0, TAU) / (TAU / 6.0)) % 6


func _wall(a: Vector2, b: Vector2, height: float, thick: float, mat: Material) -> void:
	var d := b - a
	var mid := (a + b) / 2.0
	_box(Vector3(mid.x, height / 2.0, mid.y), Vector3(d.length() + thick, height, thick), mat, -d.angle())
	_segments.append([a, b])


## A wall from a to b with a doorway `width` wide, `at` of the way along.
func _wall_with_door(a: Vector2, b: Vector2, at: float, width: float, height: float, thick: float, mat: Material) -> void:
	var d := (b - a).normalized()
	var mid := a.lerp(b, at)
	_wall(a, mid - d * width / 2.0, height, thick, mat)
	_wall(mid + d * width / 2.0, b, height, thick, mat)


## A solid box: turned `yaw` about Y, then tipped `pitch` (its +z end goes down).
func _box(center: Vector3, size: Vector3, mat: Material, yaw := 0.0, pitch := 0.0) -> void:
	var body := StaticBody3D.new()
	body.transform = Transform3D(Basis.from_euler(Vector3(pitch, yaw, 0.0)), center)
	body.physics_material_override = _phys
	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	mesh.mesh = box_mesh
	mesh.material_override = mat
	body.add_child(mesh)
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	shape.shape = box_shape
	body.add_child(shape)
	add_child(body)


static func _solid(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.85
	return mat
