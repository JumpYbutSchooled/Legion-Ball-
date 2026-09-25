extends CanvasLayer
## Speedometer, bottom right (local player). Speed is shown as m/s x 5, so the ball's
## top speed (100 m/s) reads 500.
## - The dial shakes harder the faster you go.
## - Every 100 it SHATTERS: the dial breaks into glass shards that fly apart, and a new
##   dial in the next colour takes its place.
## - At 500 it shatters away completely into a pulsing infinity sign.
## - Slowing back down REWINDS the shatter: the shards fly back together into the old dial.
## Also shows the shield (Q) cooldown underneath.

const UIStyle := preload("res://scripts/ui/ui_style.gd")
const Sfx := preload("res://scripts/sfx.gd")

const SCALE := 5.0
const MAX_DISPLAY := 500.0
const TIER_COLORS := [
	Color(0.35, 0.9, 1.0),   # 0-99
	Color(0.45, 1.0, 0.45),  # 100-199
	Color(1.0, 0.85, 0.25),  # 200-299
	Color(1.0, 0.45, 0.15),  # 300-399
	Color(1.0, 0.25, 0.7),   # 400-499
	Color(0.75, 0.55, 1.0),  # 500: infinity
]
const RADIUS := 50.0
const SEGMENTS := 30
## The glass panel round everything, relative to the dial's center.
const PANEL := Rect2(-110.0, -92.0, 220.0, 172.0)
## Dial sweep: 240 degrees, open at the bottom.
const ARC_START := PI * 0.75
const ARC_END := PI * 2.25
const SHATTER_TIME := 0.55

var ball: RigidBody3D

var _root: Control
var _font: Font
var _font_bold: Font
var _tier := 0
var _display := 0.0
var _shake_t := 0.0
var _noise := FastNoiseLite.new()
# Shatter animation: progress 0..1 and direction (+1 breaking, -1 rewinding).
var _anim := 1.0
var _anim_dir := 1
var _shard_color := Color.WHITE
var _shards: Array = []  # Each: [polygon (PackedVector2Array), velocity, spin]


func _ready() -> void:
	layer = 4
	_font = UIStyle.font()
	_font_bold = UIStyle.font(true)
	_noise.frequency = 1.0
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.draw.connect(_draw_all)
	add_child(_root)


func _process(delta: float) -> void:
	if not ball:
		return
	var speed := ball.linear_velocity.length() * SCALE
	# Needle eases toward the real value so it doesn't jitter from frame to frame.
	_display = lerpf(_display, minf(speed, MAX_DISPLAY), 1.0 - exp(-12.0 * delta))
	var goal := _tier_for(_display)
	if goal > _tier:
		_change_tier(_tier, goal, 1)
	elif goal < _tier:
		_change_tier(_tier, goal, -1)
	_anim = move_toward(_anim, 1.0, delta / SHATTER_TIME)
	_shake_t += delta * 38.0
	_root.queue_redraw()


## With a little hysteresis on the way down so it doesn't flicker at a boundary.
func _tier_for(v: float) -> int:
	if v >= MAX_DISPLAY - 2.0 or (_tier == 5 and v > MAX_DISPLAY - 20.0):
		return 5
	var t := int(v / 100.0)
	if t < _tier and v > _tier * 100.0 - 8.0:
		return _tier
	return t


func _change_tier(from: int, to: int, dir: int) -> void:
	_anim = 0.0
	_anim_dir = dir
	# Breaking: the old dial is what shatters. Rewinding: the lower dial reassembles.
	_shard_color = TIER_COLORS[from] if dir > 0 else TIER_COLORS[to]
	_make_shards()
	_tier = to
	if dir > 0:
		Sfx.play_flat(get_tree(), "infinity" if to == 5 else "shatter", -6.0, 1.0 + to * 0.08)
	else:
		Sfx.play_flat(get_tree(), "unshatter", -8.0, 1.0 + to * 0.08)


## Glass pieces covering the dial: rings of wedges, each flung outward with a spin.
func _make_shards() -> void:
	_shards.clear()
	var rings := [0.0, 0.45, 0.8, 1.12]
	for r in 3:
		var count := 6 + r * 5
		var offset := randf() * TAU
		for i in count:
			var a0 := offset + TAU * i / count
			var a1 := offset + TAU * (i + 1) / count
			var r0: float = rings[r] * RADIUS
			var r1: float = rings[r + 1] * RADIUS
			var poly := PackedVector2Array()
			# Jagged: jitter the outer corners a little.
			poly.append(Vector2.from_angle(a0) * r0)
			poly.append(Vector2.from_angle(a0) * r1 * randf_range(0.9, 1.08))
			poly.append(Vector2.from_angle((a0 + a1) * 0.5) * r1 * randf_range(0.95, 1.12))
			poly.append(Vector2.from_angle(a1) * r1 * randf_range(0.9, 1.08))
			if r0 > 0.0:
				poly.append(Vector2.from_angle(a1) * r0)
			var mid := Vector2.from_angle((a0 + a1) * 0.5)
			var vel := mid * randf_range(90.0, 260.0) * (0.6 + r * 0.3) + Vector2(randf_range(-40, 40), randf_range(-120, 0))
			_shards.append([poly, vel, randf_range(-9.0, 9.0)])


func _draw_all() -> void:
	if not ball:
		return
	var view := _root.size
	var base := Vector2(view.x - PANEL.size.x / 2.0 - 20.0, view.y - PANEL.end.y - 20.0)
	var speed_k := clampf(_display / MAX_DISPLAY, 0.0, 1.0)
	# Shake: grows with speed, sharper at the top end.
	var shake := pow(speed_k, 1.6) * 7.0
	var center := base + Vector2(_noise.get_noise_1d(_shake_t), _noise.get_noise_1d(_shake_t + 500.0)) * shake
	var jitter_rot := _noise.get_noise_1d(_shake_t + 900.0) * pow(speed_k, 2.0) * 0.06

	# How much of the new face is in: breaking fades it in; rewinding holds it back until
	# the shards have landed.
	var p := ease(_anim, 0.5)
	var face_alpha := 1.0
	if _anim < 1.0:
		face_alpha = p if _anim_dir > 0 else pow(_anim, 3.0)

	_root.draw_set_transform(center, jitter_rot, Vector2.ONE)
	_draw_panel()
	if _tier >= 5:
		_draw_infinity(face_alpha)
	else:
		_draw_dial(face_alpha)
	_draw_shield(Vector2(0.0, PANEL.end.y - 22.0))
	# Shards: flying apart (breaking) or flying back together (rewinding).
	if _anim < 1.0:
		var k := p if _anim_dir > 0 else 1.0 - p
		_draw_shards(k)
	_root.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Colour of the current tier (cycling hue once at infinity).
func _tier_color() -> Color:
	if _tier >= 5:
		return Color.from_hsv(fmod(Time.get_ticks_msec() / 4000.0, 1.0), 0.55, 1.0)
	return TIER_COLORS[_tier]


## Faint glass panel like the weapon selector: see-through fill, hairline border,
## bright corner brackets, a header line, scanlines and a slow scanning sweep.
func _draw_panel() -> void:
	var col := _tier_color()
	var r := PANEL
	_root.draw_rect(r, Color(0.02, 0.05, 0.08, 0.45))
	_root.draw_rect(r, Color(col, 0.16), false, 1.0)
	# Scanlines, and a brighter band sweeping down through them.
	var sweep := fmod(Time.get_ticks_msec() / 1800.0, 1.0) * r.size.y
	var y := 0.0
	while y < r.size.y:
		var near := 1.0 - clampf(absf(y - sweep) / 18.0, 0.0, 1.0)
		_root.draw_line(Vector2(r.position.x + 1.0, r.position.y + y), Vector2(r.end.x - 1.0, r.position.y + y), Color(col, 0.035 + near * 0.08), 1.0)
		y += 4.0
	# Corner brackets.
	var b := 12.0
	for corner in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
		var sx := 1.0 if corner.x == r.position.x else -1.0
		var sy := 1.0 if corner.y == r.position.y else -1.0
		_root.draw_line(corner, corner + Vector2(b * sx, 0.0), Color(col, 0.85), 1.5)
		_root.draw_line(corner, corner + Vector2(0.0, b * sy), Color(col, 0.85), 1.5)
	# Header: title left, tier right, hairline under both.
	var top := r.position.y + 16.0
	_root.draw_string(_font, Vector2(r.position.x + 10.0, top), "// VELOCITY", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UIStyle.TEXT_DIM)
	var tier_text := "TIER --" if _tier >= 5 else "TIER %02d" % (_tier + 1)
	var tw := _font.get_string_size(tier_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
	_root.draw_string(_font, Vector2(r.end.x - 10.0 - tw, top), tier_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, col)
	_root.draw_line(Vector2(r.position.x + 10.0, top + 5.0), Vector2(r.end.x - 10.0, top + 5.0), Color(col, 0.2), 1.0)


## Segmented dial: a ring of cells that light up through each hundred, the leading one
## white-hot, a ticked outer rail, a slowly turning scanner ring, and a digital readout.
func _draw_dial(alpha: float) -> void:
	var col: Color = TIER_COLORS[_tier]
	col.a = alpha
	var dim := Color(col, alpha * 0.14)
	var within := clampf((_display - _tier * 100.0) / 100.0, 0.0, 1.0)
	var lit := int(within * SEGMENTS)
	var span := (ARC_END - ARC_START) / SEGMENTS
	for i in SEGMENTS:
		var a0 := ARC_START + span * i + span * 0.12
		var a1 := ARC_START + span * (i + 1) - span * 0.12
		var c := dim
		if i < lit:
			c = col
		elif i == lit and within > 0.02:
			c = Color(1, 1, 1, alpha)
		_root.draw_arc(Vector2.ZERO, RADIUS, a0, a1, 4, c, 7.0)
	# Outer rail with a tick every five cells.
	_root.draw_arc(Vector2.ZERO, RADIUS + 8.0, ARC_START, ARC_END, 48, Color(col, alpha * 0.3), 1.0, true)
	for i in range(0, SEGMENTS + 1, 5):
		var d := Vector2.from_angle(ARC_START + span * i)
		_root.draw_line(d * (RADIUS + 8.0), d * (RADIUS + 12.0), Color(col, alpha * 0.6), 1.0)
	# Scanner ring: dashes turning inside the dial.
	var spin := Time.get_ticks_msec() / 1000.0 * (0.6 + within * 3.0)
	for k in 12:
		var a := spin + TAU * k / 12.0
		_root.draw_arc(Vector2.ZERO, RADIUS - 11.0, a, a + 0.22, 3, Color(col, alpha * 0.35), 1.0)
	# Digital readout: dim "888" ghost segments behind the lit digits.
	var fs := 30
	var ghost := "888"
	var text := "%03d" % int(_display)
	var w := _font_bold.get_string_size(ghost, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	_root.draw_string(_font_bold, Vector2(-w / 2.0, 10.0), ghost, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(col, alpha * 0.08))
	_root.draw_string(_font_bold, Vector2(-w / 2.0, 10.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, alpha))
	var unit := "U/S  //  x%d" % (_tier + 1)
	var uw := _font.get_string_size(unit, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
	_root.draw_string(_font, Vector2(-uw / 2.0, 26.0), unit, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, col)
	# Tier ladder: five pips, filled up to the current one.
	for i in 5:
		var pip := Rect2(Vector2(-22.0 + i * 10.0, 36.0), Vector2(6.0, 3.0))
		_root.draw_rect(pip, Color(TIER_COLORS[i], alpha * (0.9 if i <= _tier else 0.15)))


## Past the top: a glowing, breathing infinity sign in shifting colour.
func _draw_infinity(alpha: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var hue_col := Color.from_hsv(fmod(now * 0.25, 1.0), 0.55, 1.0)
	var pulse := 1.0 + 0.08 * sin(now * 7.0)
	var pts := PackedVector2Array()
	for i in 97:
		var t := TAU * i / 96.0
		# Lemniscate of Bernoulli.
		var d := 1.0 + sin(t) * sin(t)
		pts.append(Vector2(cos(t) / d, sin(t) * cos(t) / d) * RADIUS * 1.1 * pulse)
	for layer_i in 3:
		var c := hue_col
		c.a = alpha * [0.12, 0.3, 1.0][layer_i]
		_root.draw_polyline(pts, c, [14.0, 7.0, 2.5][layer_i], true)
	var text := "MAX"
	var w := _font_bold.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	_root.draw_string(_font_bold, Vector2(-w / 2.0, 40.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, alpha))


func _draw_shards(k: float) -> void:
	var col := _shard_color
	col.a = 1.0 - k * 0.85
	var edge := Color(1, 1, 1, col.a * 0.8)
	for s in _shards:
		var poly: PackedVector2Array = s[0]
		var vel: Vector2 = s[1]
		var spin: float = s[2]
		var offset := vel * k * 0.5 + Vector2(0, 260.0) * k * k * 0.5
		var rot := spin * k
		var moved := PackedVector2Array()
		var center := Vector2.ZERO
		for v in poly:
			center += v
		center /= poly.size()
		for v in poly:
			moved.append(center + offset + (v - center).rotated(rot) * (1.0 - k * 0.3))
		var fill := col
		fill.a *= 0.55
		_root.draw_colored_polygon(moved, fill)
		moved.append(moved[0])
		_root.draw_polyline(moved, edge, 1.0, true)

## Shield (Q) status: label plus a segmented charge bar.
func _draw_shield(pos: Vector2) -> void:
	if not ball.has_method("get_block_ready_ratio"):
		return
	var ready_k: float = ball.call("get_block_ready_ratio")
	var blocking: bool = ball.call("is_blocking")
	var col := Color(0.75, 0.55, 1.0) if ready_k >= 1.0 else UIStyle.TEXT_DIM
	if blocking:
		col = Color.WHITE
	var label := "SHIELD  [Q]" if ready_k >= 1.0 else "SHIELD  %.1fs" % ((1.0 - ready_k) * 10.0)
	if blocking:
		label = "SHIELD  ACTIVE"
	var left := PANEL.position.x + 10.0
	_root.draw_string(_font, Vector2(left, pos.y), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, col)
	var cells := 20
	var cw := (PANEL.size.x - 20.0) / cells
	for i in cells:
		var on := float(i) / cells < ready_k
		_root.draw_rect(Rect2(Vector2(left + i * cw, pos.y + 6.0), Vector2(cw - 2.0, 4.0)), Color(col, 0.9 if on else 0.15))
