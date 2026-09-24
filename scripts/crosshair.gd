extends Control
## Crosshair for whichever weapon is equipped (asks the weapon manager what to draw).
## Gatling: six short white lines, one per blade at that blade's angle; a line kicks
##   outward when its blade fires.
## Railgun: a circle with four lines just outside it. A locked target pulls the lines in
##   to bracket it. The circle fills as it charges, disappears while reloading, and the
##   lines spin round the circle until it's reloaded.
## Everything fades with the weapon's enter/exit animation.

@export var weapon: Node
@export var color := Color(1, 1, 1, 1)
@export var line_width := 1.2

@export_group("Gatling")
## Gap between the screen center and the start of each line, and the line length, in pixels.
@export var line_gap := 8.0
@export var line_length := 6.0
## How far a line jumps out when its blade fires, and how fast it settles.
@export var kick_pixels := 6.0
@export var kick_recover := 16.0

@export_group("Railgun")
@export var rail_line_length := 8.0
## Gap between the circle (or the locked target) and the lines.
@export var rail_line_gap := 4.0
## Bracket size round a locked target, in pixels.
@export var lock_bracket := 14.0
@export var lock_speed := 14.0
## Spin while reloading, in radians per second.
@export var reload_spin := 4.0

var _dirs: Array[Vector2] = []  # Gatling line direction per blade, in firing order.
var _kicks := PackedFloat32Array()
var _rail_center := Vector2.ZERO
var _rail_radius := -1.0
var _spin := 0.0


func _ready() -> void:
	var angles := PackedFloat32Array([40.0, 0.0, -28.0])
	if weapon:
		if weapon.has_method("get_gatling_angles"):
			angles = weapon.call("get_gatling_angles")
		if weapon.has_signal("fired"):
			weapon.connect("fired", _on_fired)
	# Same order the gatling builds its blades: each row, right then left.
	# A blade rolled by `a` on side `s` points (s * cos a, sin a) on screen (y up).
	for a in angles:
		for side in [1.0, -1.0]:
			var r := deg_to_rad(a)
			_dirs.append(Vector2(side * cos(r), -sin(r)))
	_kicks.resize(_dirs.size())
	_kicks.fill(0.0)


func _on_fired(index: int) -> void:
	if index < _kicks.size():
		_kicks[index] = 1.0


func _process(delta: float) -> void:
	var settle := 1.0 - exp(-kick_recover * delta)
	for i in _kicks.size():
		_kicks[i] = lerpf(_kicks[i], 0.0, settle)

	var info := _info()
	if info.get("kind") == "rail":
		var c := size / 2.0
		var radius: float = info["radius"]
		var goal_center := c
		var goal_radius := radius
		if info["locked"]:
			goal_center = info["lock_pos"]
			goal_radius = lock_bracket
		if _rail_radius < 0.0:
			_rail_center = goal_center
			_rail_radius = goal_radius
		var t := 1.0 - exp(-lock_speed * delta)
		_rail_center = _rail_center.lerp(goal_center, t)
		_rail_radius = lerpf(_rail_radius, goal_radius, t)
		if info["reloading"]:
			_spin = wrapf(_spin + reload_spin * delta, 0.0, TAU)
		else:
			# Settle back onto the nearest quarter turn.
			var quarter := PI / 2.0
			_spin = lerpf(_spin, roundf(_spin / quarter) * quarter, t)
	queue_redraw()


func _info() -> Dictionary:
	if weapon and weapon.has_method("get_crosshair"):
		return weapon.call("get_crosshair")
	return {"kind": "gatling"}


func _draw() -> void:
	var arm := 1.0
	if weapon and weapon.has_method("get_arm_amount"):
		arm = weapon.call("get_arm_amount")
	if arm <= 0.01:
		return
	var col := color
	col.a *= arm

	var info := _info()
	match info.get("kind"):
		"gatling":
			_draw_gatling(col)
		"rail":
			_draw_rail(info, col)
		"scatter":
			_draw_scatter(info, col)
		"tether":
			_draw_tether(info, col)
		"nova":
			_draw_nova(info, col)
		"swarm":
			_draw_swarm(info, col)


func _draw_gatling(col: Color) -> void:
	var c := size / 2.0
	for i in _dirs.size():
		var d := _dirs[i]
		var start := c + d * (line_gap + _kicks[i] * kick_pixels)
		draw_line(start, start + d * line_length, col, line_width, true)


func _draw_rail(info: Dictionary, col: Color) -> void:
	var c := size / 2.0
	var radius: float = info["radius"]
	if info["circle"]:
		draw_arc(c, radius, 0.0, TAU, 72, col, line_width, true)
		var charge: float = info["charge"]
		if charge > 0.0:
			# Charge fills the circle clockwise from the top, thicker.
			draw_arc(c, radius, -PI / 2.0, -PI / 2.0 + TAU * charge, 72, col, line_width * 2.5, true)
	for k in 4:
		var d := Vector2.from_angle(-PI / 2.0 + k * PI / 2.0 + _spin)
		var inner := _rail_center + d * (_rail_radius + rail_line_gap)
		draw_line(inner, inner + d * rail_line_length, col, line_width, true)


## Scatter: two arcs marking the edge of the pellet cone; they bloom out on each shot
## and dim until it can fire again.
func _draw_scatter(info: Dictionary, col: Color) -> void:
	var c := size / 2.0
	var bloom: float = info["bloom"]
	var radius: float = maxf(info["radius"], 10.0) * (1.0 + 0.4 * bloom)
	if not info["ready"]:
		col.a *= 0.45
	var half := deg_to_rad(38.0)
	draw_arc(c, radius, -half, half, 24, col, line_width, true)
	draw_arc(c, radius, PI - half, PI + half, 24, col, line_width, true)
	# Small ticks top and bottom mark the vertical extent.
	for k in [-1.0, 1.0]:
		var p := c + Vector2(0, radius * k)
		draw_line(p, p - Vector2(0, 5.0 * k), col, line_width, true)

	# Heat gauge: thicker arcs just outside each side, filling from the bottom up.
	var heat: float = info.get("heat", 0.0)
	var overheated: bool = info.get("overheated", false)
	if heat > 0.0:
		var gauge := Color(1.0, 0.55, 0.2, col.a * 2.0 if not info["ready"] else col.a)
		if overheated:
			# Blink while venting.
			gauge.a *= 0.4 + 0.6 * float(int(Time.get_ticks_msec() / 120) % 2)
		var r := radius + 5.0
		var span := half * 2.0 * heat
		draw_arc(c, r, half, half - span, 16, gauge, line_width * 2.2, true)
		draw_arc(c, r, PI - half, PI - half + span, 16, gauge, line_width * 2.2, true)
	if overheated:
		var font := ThemeDB.fallback_font
		var text := "OVERHEAT"
		var fs := 11
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var warn := Color(1.0, 0.55, 0.2, col.a * 2.0)
		draw_string(font, c + Vector2(-w / 2.0, radius + 22.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, warn)


## Tether: a diamond. Solid in range, faint and wider out of range. While hooked, a
## second spinning diamond sits on the anchor.
func _draw_tether(info: Dictionary, col: Color) -> void:
	var c := size / 2.0
	var in_range: bool = info["in_range"]
	var r := 9.0 if in_range else 14.0
	var main := col
	if not in_range:
		main.a *= 0.35
	_diamond(c, r, 0.0, main)
	if info["attached"] and info.has("anchor_screen"):
		# The anchor diamond spins faster and pinches tighter as the rope pulls harder.
		var tension: float = info.get("tension", 0.0)
		var spin := Time.get_ticks_msec() / 1000.0 * (4.0 + tension * 10.0)
		_diamond(info["anchor_screen"], 7.0 - tension * 3.0, spin, col)


## Nova: eight short dashes round the center that spread out as it charges;
## a thin arc fills back in while it's on cooldown.
func _draw_nova(info: Dictionary, col: Color) -> void:
	var c := size / 2.0
	var charge: float = info["charge"]
	var r := 9.0 + charge * 24.0
	for k in 8:
		var d := Vector2.from_angle(k * TAU / 8.0 + PI / 8.0)
		draw_line(c + d * r, c + d * (r + 5.0 + charge * 3.0), col, line_width + charge, true)
	if not info["ready"]:
		var progress: float = info["cooldown"]
		var faint := col
		faint.a *= 0.5
		draw_arc(c, 16.0, -PI / 2.0, -PI / 2.0 + TAU * progress, 32, faint, line_width, true)


## Swarm: faint corner brackets show the paint zone, a small square marks the center,
## each painted target gets a spinning bracket, and pips count paints left.
func _draw_swarm(info: Dictionary, col: Color) -> void:
	var c := size / 2.0
	var zone: float = info["radius"] * 0.72
	var faint := col
	faint.a *= 0.3 if not info["painting"] else 0.6
	for k in 4:
		var corner := c + Vector2(zone if k % 2 == 0 else -zone, zone if k < 2 else -zone)
		var sx := -signf(corner.x - c.x) * 10.0
		var sy := -signf(corner.y - c.y) * 10.0
		draw_line(corner, corner + Vector2(sx, 0), faint, line_width, true)
		draw_line(corner, corner + Vector2(0, sy), faint, line_width, true)
	_brackets(c, 5.0, 0.0, col if info["ready"] else faint)
	var spin := Time.get_ticks_msec() / 1000.0 * 3.0
	for mark in info["marks"]:
		_brackets(mark, 11.0, spin, col)
	var total: int = info["max"]
	var used: int = info["marks"].size()
	for i in total:
		var p := c + Vector2((i - (total - 1) / 2.0) * 7.0, 16.0)
		if i < used:
			draw_rect(Rect2(p - Vector2(2, 2), Vector2(4, 4)), col)
		else:
			draw_rect(Rect2(p - Vector2(2, 2), Vector2(4, 4)), faint, false, 1.0)


func _diamond(center: Vector2, r: float, angle: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for k in 5:
		pts.append(center + Vector2.from_angle(angle + k * PI / 2.0) * r)
	draw_polyline(pts, col, line_width, true)


## Four corner brackets round `center`, rotated by `angle`.
func _brackets(center: Vector2, r: float, angle: float, col: Color) -> void:
	for k in 4:
		var a := angle + PI / 4.0 + k * PI / 2.0
		var corner := center + Vector2.from_angle(a) * r * 1.414
		var back_a := Vector2.from_angle(a + PI * 0.75) * r * 0.6
		var back_b := Vector2.from_angle(a - PI * 0.75) * r * 0.6
		draw_line(corner, corner + back_a, col, line_width, true)
		draw_line(corner, corner + back_b, col, line_width, true)
