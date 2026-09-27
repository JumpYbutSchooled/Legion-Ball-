extends "res://scripts/maps/map_builder.gd"
## "The RV": the old white-and-brown motorhome from Breaking Bad, parked out in the New
## Mexico desert, built eight times life size. Roll up the steps and in through the door:
## inside is the lab (steel tables, glassware, a cooker, drums and gas bottles), the cab
## up front, a bunk at the back. Outside: a dirt track, rocks, cacti and red mesas.

const S := 8.0
## The RV's box, in life-size metres (x along its length, front at -x).
const LENGTH := 10.0
const WIDTH := 2.5
const HEIGHT := 2.9
const FLOOR := 0.9

var _sand := checker(Color(0.82, 0.68, 0.48), Color(0.78, 0.64, 0.45), 8.0)
var _dirt := solid(Color(0.66, 0.52, 0.36), 0.95)
var _mesa := solid(Color(0.66, 0.36, 0.22), 0.95)
var _mesa2 := solid(Color(0.74, 0.44, 0.28), 0.95)
var _rock := solid(Color(0.55, 0.45, 0.36), 0.95)
var _cactus := solid(Color(0.3, 0.5, 0.28), 0.8)
var _body := solid(Color(0.93, 0.91, 0.84), 0.5)
var _stripe := solid(Color(0.48, 0.3, 0.16), 0.5)
var _stripe2 := solid(Color(0.75, 0.55, 0.3), 0.5)
var _glass := glow(Color(0.35, 0.45, 0.5), 0.3)
var _tyre := solid(Color(0.08, 0.08, 0.08), 0.9)
var _steel := solid(Color(0.7, 0.72, 0.74), 0.3, 0.8)
var _floor := checker(Color(0.55, 0.5, 0.42), Color(0.5, 0.45, 0.38), 2.0)
var _blue := glow(Color(0.25, 0.7, 1.0), 2.0)
var _yellow := solid(Color(0.95, 0.75, 0.1), 0.5)
var _drum := solid(Color(0.2, 0.3, 0.55), 0.5, 0.3)
var _seat := solid(Color(0.4, 0.3, 0.22), 0.8)


func _build() -> void:
	_ceiling = 120.0
	_outline = rect_outline(Rect2(-200, -200, 400, 400))
	ground(Rect2(-200, -200, 400, 400), _sand)
	box(Vector3(0, 0.1, 40.0), Vector3(400.0, 0.2, 14.0), _dirt)
	_rv(Vector3(0, 0, 0))
	_desert()
	for i in 6:
		var a := TAU * i / 6.0 + 0.4
		_spawns.append(Vector3(cos(a) * 90.0, 1.0, sin(a) * 90.0))
	# Two spawns inside the lab.
	_spawns.append(Vector3(-10.0, FLOOR * S + 1.0, 0.0))
	_spawns.append(Vector3(14.0, FLOOR * S + 1.0, 0.0))
	_turrets.append(Vector3(150, 1, 150))
	_turrets.append(Vector3(-150, 1, -150))
	var light := OmniLight3D.new()
	light.position = Vector3(0, FLOOR * S + 18.0, 0)
	light.light_color = Color(1.0, 0.95, 0.85)
	light.light_energy = 1.0
	light.omni_range = 40.0
	add_child(light)


## A point on the RV in life-size metres, turned into the map (x along, y up, z across).
func _p(x: float, y: float, z: float) -> Vector3:
	return Vector3(x, y, z) * S


func _rv(_at: Vector3) -> void:
	var l := LENGTH / 2.0
	var w := WIDTH / 2.0
	var t := 0.1
	# Floor, raised on the chassis, with the wheels under it.
	box(_p(0, FLOOR - t / 2.0, 0), Vector3(LENGTH, t, WIDTH) * S, _floor)
	box(_p(0.3, FLOOR / 2.0 + 0.1, 0), Vector3(LENGTH - 1.5, FLOOR - 0.5, WIDTH - 0.4) * S, _steel)
	for x: float in [-3.4, 2.6, 3.5]:
		for s: float in [-1.0, 1.0]:
			box(_p(x, 0.45, s * (w - 0.1)), Vector3(0.9, 0.9, 0.3) * S, _tyre)
			box(_p(x, 0.45, s * (w - 0.1)), Vector3(0.9, 0.9, 0.3) * S, _tyre, 0.0, 0.0).rotation.z = PI / 4.0
	# Side walls, with the door (right side, near the back) and window holes.
	var top := HEIGHT
	for s: float in [-1.0, 1.0]:
		var z := s * (w - t / 2.0)
		# Below the windows, all along.
		box(_p(0, (FLOOR + 1.9) / 2.0, z), Vector3(LENGTH, 1.9 - FLOOR, t) * S, _body)
		# Above the windows.
		box(_p(0, (2.5 + top) / 2.0, z), Vector3(LENGTH, top - 2.5, t) * S, _body)
		# Pillars between the windows.
		for x: float in [-5.0, -2.8, -0.6, 1.8, 4.9]:
			box(_p(x, 2.2, z), Vector3(0.4, 0.6, t) * S, _body)
		for x in [-4.0, -1.7, 0.6, 3.4]:
			deco(_p(x, 2.2, z), Vector3(1.5, 0.6, 0.02) * S, _glass)
		# The brown and tan stripes along the sides.
		deco(_p(0, 1.55, z + s * 0.06), Vector3(LENGTH, 0.14, 0.02) * S, _stripe)
		deco(_p(0, 1.35, z + s * 0.06), Vector3(LENGTH, 0.1, 0.02) * S, _stripe2)
	# The door: a gap in the lower wall on the right side, with steps up to it.
	var door_x := 2.0
	_door_gap(door_x, w)
	stairs(Vector3(door_x * S, 0.0, w * S + 9.0), Vector2(0, -1), 6, FLOOR * S / 6.0, 1.5, 7.0, _steel)
	# Back wall, front cab wall with the windscreen, roof.
	box(_p(l - t / 2.0, (FLOOR + top) / 2.0, 0), Vector3(t, top - FLOOR, WIDTH) * S, _body)
	box(_p(-l + t / 2.0, (FLOOR + 1.6) / 2.0, 0), Vector3(t, 1.6 - FLOOR, WIDTH) * S, _body)
	box(_p(-l + t / 2.0, (2.5 + top) / 2.0, 0), Vector3(t, top - 2.5, WIDTH) * S, _body)
	deco(_p(-l + 0.02, 2.05, 0), Vector3(0.02, 0.9, WIDTH - 0.3) * S, _glass)
	box(_p(-l - 0.5, 0.9, 0), Vector3(1.0, 1.0, WIDTH) * S, _body)
	box(_p(0, top + t / 2.0, 0), Vector3(LENGTH, t, WIDTH) * S, _body, 0.0, 0.0, false)
	box(_p(1.0, top + 0.35, 0), Vector3(1.0, 0.5, 0.9) * S, _steel, 0.0, 0.0, false)
	_lab(w)


## Opening in the right-hand wall where the door is: the wall below the windows is
## rebuilt either side of it.
func _door_gap(door_x: float, w: float) -> void:
	for child in get_children():
		var body := child as StaticBody3D
		if body and absf(body.position.z - (w - 0.05) * S) < 0.5 and absf(body.position.y - (FLOOR + 1.9) / 2.0 * S) < 0.5 and body.position.x == 0.0:
			body.queue_free()
			remove_child(body)
	var l := LENGTH / 2.0
	var z := w - 0.05
	var y := (FLOOR + 1.9) / 2.0
	var a := door_x - 0.5
	var b := door_x + 0.5
	box(_p((-l + a) / 2.0, y, z), Vector3(a + l, 1.9 - FLOOR, 0.1) * S, _body)
	box(_p((b + l) / 2.0, y, z), Vector3(l - b, 1.9 - FLOOR, 0.1) * S, _body)
	deco(_p((-l + a) / 2.0, 1.55, z + 0.06), Vector3(a + l, 0.14, 0.02) * S, _stripe)
	deco(_p((b + l) / 2.0, 1.55, z + 0.06), Vector3(l - b, 0.14, 0.02) * S, _stripe)


func _lab(w: float) -> void:
	var f := FLOOR
	# Cab: two seats and the dashboard.
	box(_p(-4.6, f + 0.5, 0), Vector3(0.5, 1.0, WIDTH - 0.3) * S, _steel)
	for s: float in [-1.0, 1.0]:
		box(_p(-3.8, f + 0.25, s * 0.6), Vector3(0.6, 0.5, 0.6) * S, _seat)
		box(_p(-3.5, f + 0.75, s * 0.6), Vector3(0.12, 0.8, 0.6) * S, _seat)
	# Steel benches down the left side with the glassware (glowing blue).
	for x: float in [-2.2, -0.6, 1.0]:
		box(_p(x, f + 0.45, -w + 0.35), Vector3(1.4, 0.9, 0.6) * S, _steel)
		for k in 3:
			deco(_p(x - 0.45 + k * 0.45, f + 1.05, -w + 0.35), Vector3(0.12, 0.3, 0.12) * S, _blue)
	# The cooker on the right, drums and gas bottles at the back, a bunk over the back.
	box(_p(-0.6, f + 0.5, w - 0.45), Vector3(1.2, 1.0, 0.7) * S, _steel)
	deco(_p(-0.6, f + 1.2, w - 0.45), Vector3(0.5, 0.4, 0.4) * S, _blue)
	for i in 3:
		box(_p(3.6, f + 0.45, -0.8 + i * 0.6), Vector3(0.5, 0.9, 0.5) * S, _drum)
	for i in 2:
		box(_p(4.4, f + 0.4, 0.6 - i * 0.5), Vector3(0.3, 0.8, 0.3) * S, _yellow)
	box(_p(4.3, f + 1.3, 0), Vector3(1.2, 0.15, WIDTH - 0.2) * S, _seat)


func _desert() -> void:
	# Mesas on the horizon: stacked slabs, each smaller.
	for i in 7:
		var a := TAU * i / 7.0 + 0.2
		var r := _rng.randf_range(150.0, 185.0)
		var p := Vector2.from_angle(a) * r
		var w := _rng.randf_range(30.0, 50.0)
		var h := _rng.randf_range(25.0, 50.0)
		box(Vector3(p.x, h / 2.0, p.y), Vector3(w, h, w * 0.8), _mesa, a)
		box(Vector3(p.x, h + 4.0, p.y), Vector3(w * 0.7, 8.0, w * 0.55), _mesa2, a)
	for i in 30:
		var p := Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(45.0, 140.0)
		if absf(p.y - 40.0) < 10.0:
			continue
		if i % 2 == 0:
			_saguaro(Vector3(p.x, 0, p.y), _rng.randf_range(8.0, 16.0))
		else:
			box(Vector3(p.x, 2.0, p.y), Vector3(_rng.randf_range(4, 10), 4.0 + _rng.randf() * 4.0, _rng.randf_range(4, 10)), _rock, _rng.randf() * TAU)


func _saguaro(p: Vector3, h: float) -> void:
	box(p + Vector3(0, h / 2.0, 0), Vector3(1.6, h, 1.6), _cactus)
	for s: float in [-1.0, 1.0]:
		var y := h * _rng.randf_range(0.4, 0.6)
		box(p + Vector3(s * 1.8, y, 0), Vector3(2.4, 1.2, 1.2), _cactus)
		box(p + Vector3(s * 2.6, y + 2.0, 0), Vector3(1.2, 4.0, 1.2), _cactus)
