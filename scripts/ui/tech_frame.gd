extends Control
## Animated sci-fi framing drawn over a menu panel: glowing corner brackets, crawling tick
## rulers along the edges, a scan line sweeping down, a hex readout ticking over in the
## corner, and a bright glitch sweep whenever the page changes (glitch()).
## Purely decorative: ignores the mouse and draws on top of the panel it's placed in.

const UIStyle := preload("res://scripts/ui/ui_style.gd")

var _font: Font
var _t := 0.0
## 1 at a page change, falling to 0: the sweep and the brackets flaring.
var _glitch := 0.0
var _hex := ""
var _hex_timer := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_font = UIStyle.font(false)


func glitch() -> void:
	_glitch = 1.0


func _process(delta: float) -> void:
	_t += delta
	_glitch = move_toward(_glitch, 0.0, delta / 0.45)
	_hex_timer -= delta
	if _hex_timer <= 0.0:
		_hex_timer = 0.09
		_hex = "0x%04X %04X  SYNC %02d%%" % [_rng.randi() % 0x10000, _rng.randi() % 0x10000, 90 + _rng.randi() % 10]
	queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	if r.size.x < 40.0 or r.size.y < 40.0:
		return
	var accent := UIStyle.ACCENT
	var dim := UIStyle.ACCENT_DIM
	var flare := 1.0 + _glitch * 1.5
	# Corner brackets, breathing a little, flaring on page changes.
	var arm := 22.0 + 4.0 * sin(_t * 2.2) + _glitch * 18.0
	var bc := accent
	bc.a = clampf(0.75 * flare, 0.0, 1.0)
	for corner in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
		var sx := 1.0 if corner.x == r.position.x else -1.0
		var sy := 1.0 if corner.y == r.position.y else -1.0
		var p: Vector2 = corner + Vector2(-sx * 4.0, -sy * 4.0)
		draw_line(p, p + Vector2(sx * arm, 0), bc, 2.0, true)
		draw_line(p, p + Vector2(0, sy * arm), bc, 2.0, true)
	# Tick ruler crawling along the top and bottom edges.
	var tick := dim
	tick.a = 0.5
	var spacing := 14.0
	var shift := fmod(_t * 20.0, spacing)
	var x := 40.0 + shift
	while x < r.size.x - 40.0:
		var long := int((x - shift) / spacing) % 5 == 0
		draw_line(Vector2(x, -2), Vector2(x, -2 - (6.0 if long else 3.0)), tick, 1.0)
		draw_line(Vector2(r.size.x - x, r.size.y + 2), Vector2(r.size.x - x, r.size.y + 2 + (6.0 if long else 3.0)), tick, 1.0)
		x += spacing
	# Slow scan line.
	var scan_y := fmod(_t * 60.0, r.size.y + 80.0) - 40.0
	var scan := accent
	scan.a = 0.05
	draw_rect(Rect2(0, scan_y, r.size.x, 2), scan)
	scan.a = 0.025
	draw_rect(Rect2(0, scan_y - 18, r.size.x, 18), scan)
	# Page-change glitch: a bright bar sweeping down, trailing offset slices.
	if _glitch > 0.0:
		var k := 1.0 - _glitch
		var y := k * r.size.y
		var hot := Color(0.7, 1.0, 1.0, _glitch * 0.55)
		draw_rect(Rect2(0, y - 3, r.size.x, 6), hot)
		for i in 5:
			var sy := y - 20.0 - i * 26.0 - _rng.randf() * 10.0
			if sy < 0.0:
				break
			var slice := accent
			slice.a = _glitch * 0.18 * (1.0 - i / 5.0)
			var off := _rng.randf_range(-30.0, 30.0) * _glitch
			draw_rect(Rect2(off, sy, r.size.x * _rng.randf_range(0.3, 1.0), _rng.randf_range(2.0, 7.0)), slice)
	# Readout in the bottom-right corner.
	var txt := dim
	txt.a = 0.8
	var w := _font.get_string_size(_hex, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
	draw_string(_font, Vector2(r.size.x - w - 14.0, r.size.y - 8.0), _hex, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, txt)
