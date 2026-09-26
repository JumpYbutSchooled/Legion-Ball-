extends Control
## Killstreak counter, top-centre: a red skull with "x3" beside it. Every kill slams the
## skull in huge and flashes it white-hot red, with a ring bursting out behind it; dying
## resets the streak and the counter fades away. Drawn in code, no textures.

const UIStyle := preload("res://scripts/ui/ui_style.gd")
const RED := Color(1.0, 0.16, 0.2)
const SKULL := 26.0

var streak := 0

var _font: Font
## 1 right after a kill, easing to 0.
var _flash := 0.0
## 0..1 ring burst after a kill.
var _ring := 1.0
var _shown := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = UIStyle.font(true)
	custom_minimum_size = Vector2(160, 70)
	size = custom_minimum_size


func add_kill() -> void:
	streak += 1
	_flash = 1.0
	_ring = 0.0
	# Punch in from big.
	pivot_offset = size / 2.0
	scale = Vector2.ONE * 1.8
	create_tween().set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT) \
		.tween_property(self, "scale", Vector2.ONE, 0.45)


func reset() -> void:
	streak = 0


func _process(delta: float) -> void:
	_flash = move_toward(_flash, 0.0, delta / 1.2)
	_ring = move_toward(_ring, 1.0, delta / 0.6)
	_shown = move_toward(_shown, 1.0 if streak > 0 else 0.0, delta * (4.0 if streak > 0 else 1.5))
	queue_redraw()


func _draw() -> void:
	if _shown <= 0.0:
		return
	var c := Vector2(SKULL + 14.0, size.y / 2.0)
	var col := RED.lerp(Color(1.0, 0.85, 0.85), _flash * 0.7)
	col.a = _shown
	if _ring < 1.0:
		var ring_col := RED
		ring_col.a = (1.0 - _ring) * _shown
		draw_arc(c, SKULL * (0.9 + _ring * 1.6), 0.0, TAU, 40, ring_col, 3.0 * (1.0 - _ring) + 1.0, true)
	if _flash > 0.0:
		var glow := RED
		glow.a = _flash * 0.35 * _shown
		draw_circle(c, SKULL * (1.1 + _flash * 0.4), glow)
	_draw_skull(c, SKULL, col)
	var text := "x%d" % streak
	var text_col := Color.WHITE.lerp(RED, 0.35 + 0.65 * (1.0 - _flash))
	text_col.a = _shown
	draw_string_outline(_font, c + Vector2(SKULL + 10.0, 11.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, 6, Color(0, 0, 0, 0.6 * _shown))
	draw_string(_font, c + Vector2(SKULL + 10.0, 11.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, text_col)


## A simple skull: round cranium, jaw with teeth, two eye sockets and a nose.
func _draw_skull(c: Vector2, r: float, col: Color) -> void:
	var hole := Color(0.0, 0.0, 0.0, 0.85 * col.a)
	# Cranium and cheekbones.
	draw_circle(c + Vector2(0, -r * 0.12), r * 0.78, col)
	# Jaw.
	var jaw := Rect2(c + Vector2(-r * 0.45, r * 0.35), Vector2(r * 0.9, r * 0.5))
	draw_rect(jaw, col)
	# Teeth gaps.
	for i in 3:
		var x := jaw.position.x + jaw.size.x * (i + 1) / 4.0
		draw_line(Vector2(x, jaw.position.y + r * 0.12), Vector2(x, jaw.end.y), hole, 2.0)
	# Eyes, slanted in a little for menace.
	for side in [-1.0, 1.0]:
		var eye := c + Vector2(side * r * 0.32, -r * 0.05)
		draw_colored_polygon(PackedVector2Array([
			eye + Vector2(side * r * 0.2, -r * 0.14),  # Outer top, higher...
			eye + Vector2(-side * r * 0.2, -r * 0.02),  # ...than the inner top: a frown.
			eye + Vector2(-side * r * 0.16, r * 0.17),
			eye + Vector2(side * r * 0.16, r * 0.17),
		]), hole)
	# Nose.
	draw_colored_polygon(PackedVector2Array([
		c + Vector2(0, r * 0.18), c + Vector2(-r * 0.09, r * 0.34), c + Vector2(r * 0.09, r * 0.34),
	]), hole)
