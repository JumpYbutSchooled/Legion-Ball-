extends CanvasLayer
## The start screen, shown over the main menu once per launch (main_menu.gd).
## It opens with an intro (any key or click skips it):
##   1. black, a low hum and a point of light breathing in the middle
##   2. light streaks rushing in while a glowing crystal ball rockets across
##   3. the ball hits the middle and the whole screen shatters like black glass,
##      revealing the scene behind (flash, boom, shake)
##   4. the BALLISTIC letters slam down one by one, the subtitle types out and the
##      buttons spring up.
## Then it idles like a layered Scratch title screen: a map backdrop and crystal shards
## drift against the mouse at different depths, bob, sway and swell with the music, and
## every few seconds a colour flash swaps in a new map. PLAY (into the menu) and TUTORIAL
## spring and wobble; pressing one shatters it (scripts/ui/glass_shards.gd) and fades out.

signal done(choice: String)

const UIStyle := preload("res://scripts/ui/ui_style.gd")
const Sfx := preload("res://scripts/sfx.gd")
const GlassShards := preload("res://scripts/ui/glass_shards.gd")
## Seconds each backdrop stays before the flash swaps it.
const CYCLE := 6.5
## How far each depth step moves against the mouse (pixels per pixel off centre).
const PARALLAX := 0.022
## The intro's beats (seconds).
const T_STREAKS := 0.9
const T_BALL := 1.55
const T_HIT := 2.15
const T_GLASS := 1.5  # how long the full-screen pane takes to fall away
const T_LETTERS := 2.35
const LETTER_GAP := 0.07
const T_SUB := 3.15
const T_BUTTONS := 3.55
const T_END := 4.0

var _root: Control
var _back: Array[TextureRect] = []
var _layers: Array[Control] = []  # back to front; their depth is their index + 1
var _logo: LogoLayer
var _buttons: Array[Button] = []
var _intro: IntroLayer
var _flash: ColorRect
var _black: ColorRect
var _maps: Array[String] = []
var _map_i := 0
var _hue := 0.55
var _t := 0.0
var _next_swap := T_END + CYCLE
var _pulse := 0.0  # 0..1, the music's swell
var _beat_cool := 0.0
var _spectrum: AudioEffectSpectrumAnalyzerInstance
var _spectrum_bus := -1
var _leaving := false
var _springs := {}  # Button -> [size, velocity]
var _spring_acc := 0.0
var _shake := 0.0
var _rng := RandomNumberGenerator.new()
## Intro events already fired.
var _fired := {}
## The intro waits (on its first black frame) until its sounds exist: they're built in
## the background when the game starts (scripts/sfx.gd), and it isn't the same silent.
var _sounds_ready := false
var _held := 0.0


func _ready() -> void:
	layer = 40
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.theme = UIStyle.make_theme()
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.gui_input.connect(_on_root_input)
	add_child(_root)
	for f in DirAccess.get_files_at("res://textures/maps"):
		if f.ends_with(".png") and f != "training.png":
			_maps.append("res://textures/maps/" + f)
	_maps.shuffle()
	# The backdrop: a map picture, zoomed so it can drift.
	for i in 1:
		var tex := TextureRect.new()
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tex.modulate = Color(0.55, 0.6, 0.7)
		_root.add_child(tex)
		_back.append(tex)
	_back[0].texture = _load_map(0)
	# Shade over it: darker at the edges and the bottom, so the art and buttons stand out.
	var shade := TextureRect.new()
	var grad := GradientTexture2D.new()
	grad.fill = GradientTexture2D.FILL_RADIAL
	grad.fill_from = Vector2(0.5, 0.42)
	grad.fill_to = Vector2(1.1, 1.1)
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0.1))
	g.set_color(1, Color(0, 0.01, 0.03, 0.85))
	grad.gradient = g
	shade.texture = grad
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(shade)
	# Crystal shards (two depths), then the logo on top.
	for depth in 2:
		var art := ArtLayer.new()
		art.count = 7 if depth == 0 else 6
		art.scale_by = 0.75 if depth == 0 else 1.15
		_layers.append(art)
		_root.add_child(art)
	_logo = LogoLayer.new()
	_layers.append(_logo)
	_root.add_child(_logo)
	_recolour()
	# The buttons (hidden until the intro brings them up).
	for spec in [["PLAY", "play"], ["TUTORIAL", "tutorial"]]:
		var b := Button.new()
		b.text = "[ %s ]" % spec[0]
		b.set_meta("ui_motion", true)  # its own springy motion, below
		b.add_theme_font_size_override("font_size", 26)
		b.custom_minimum_size = Vector2(250, 64)
		b.focus_mode = Control.FOCUS_ALL
		b.pressed.connect(_choose.bind(b, spec[1]))
		b.modulate.a = 0.0
		_root.add_child(b)
		_buttons.append(b)
		_springs[b] = [0.0, 0.0]
	_buttons[0].focus_neighbor_right = _buttons[1].get_path()
	_buttons[1].focus_neighbor_left = _buttons[0].get_path()
	var hint := UIStyle.label("CLICK OR PRESS A TO START", 13, UIStyle.TEXT_DIM)
	hint.name = "Hint"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.modulate.a = 0.0
	_root.add_child(hint)
	_intro = IntroLayer.new()
	_root.add_child(_intro)
	_flash = ColorRect.new()
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.color = Color(1, 1, 1, 0)
	_root.add_child(_flash)
	_black = ColorRect.new()
	_black.set_anchors_preset(Control.PRESET_FULL_RECT)
	_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_black.color = Color(0, 0, 0, 0)
	_root.add_child(_black)
	_listen()


func _exit_tree() -> void:
	if _spectrum_bus >= 0 and AudioServer.get_bus_effect_count(_spectrum_bus) > 0:
		AudioServer.remove_bus_effect(_spectrum_bus, AudioServer.get_bus_effect_count(_spectrum_bus) - 1)


## Hear the music: a spectrum analyser on the Music bus (taken off again on exit).
func _listen() -> void:
	_spectrum_bus = AudioServer.get_bus_index("Music")
	if _spectrum_bus < 0:
		return
	var fx := AudioEffectSpectrumAnalyzer.new()
	fx.buffer_length = 0.1
	AudioServer.add_bus_effect(_spectrum_bus, fx)
	_spectrum = AudioServer.get_bus_effect_instance(_spectrum_bus, AudioServer.get_bus_effect_count(_spectrum_bus) - 1) as AudioEffectSpectrumAnalyzerInstance


func _load_map(i: int) -> Texture2D:
	if _maps.is_empty():
		return null
	return load(_maps[i % _maps.size()]) as Texture2D


## New colours for the shards and the logo's rim, and new shard shapes.
func _recolour() -> void:
	_hue = fposmod(_hue + _rng.randf_range(0.18, 0.42), 1.0)
	for i in 2:
		var art := _layers[i] as ArtLayer
		art.hue = fposmod(_hue + 0.5 + i * 0.06, 1.0)
		art.seed_shapes(_rng.randi())
	_logo.hue = _hue


# --- The intro ------------------------------------------------------------------------

## Once, when the intro's clock passes `at`.
func _once(id: String, at: float) -> bool:
	if _t >= at and not _fired.has(id):
		_fired[id] = true
		return true
	return false


func _run_intro() -> void:
	var view := _root.size
	_intro.t = _t
	if _once("hum", 0.05):
		Sfx.play_flat(get_tree(), "implode", -10.0, 0.6)
	if _once("streaks", T_STREAKS):
		Sfx.play_flat(get_tree(), "ui_page", -10.0, 0.5)
	if _once("ball", T_BALL):
		Sfx.play_flat(get_tree(), "rail", -6.0, 1.25)
	if _once("hit", T_HIT):
		# The screen breaks: the black pane cracks from the middle and falls away.
		var pane := PackedVector2Array([Vector2.ZERO, Vector2(view.x, 0), view, Vector2(0, view.y)])
		_intro.glass.build(pane, view * 0.5 + Vector2(0, -20), 2.4, 18, 6)
		_intro.broken_at = _t
		_flash.color = Color(1, 1, 1, 0.85)
		create_tween().tween_property(_flash, "color:a", 0.0, 0.5).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
		_shake = 1.0
		Sfx.play_flat(get_tree(), "impact_boom", 0.0, 0.85)
		Sfx.play_flat(get_tree(), "shatter", -2.0, 0.8)
	# The letters slam down one at a time.
	for i in LogoLayer.WORD.length():
		if _once("letter%d" % i, T_LETTERS + i * LETTER_GAP):
			_logo.slam(i, _t)
			_shake = maxf(_shake, 0.35)
			Sfx.play_flat(get_tree(), "ui_click", -6.0, 0.7 + i * 0.06)
	if _once("last_boom", T_LETTERS + LogoLayer.WORD.length() * LETTER_GAP):
		Sfx.play_flat(get_tree(), "boom", -8.0, 0.7)
	_logo.typed = clampf((_t - T_SUB) / 0.45, 0.0, 1.0)
	if _once("buttons", T_BUTTONS):
		for k in _buttons.size():
			var b := _buttons[k]
			b.create_tween().tween_property(b, "modulate:a", 1.0, 0.25).set_delay(k * 0.08)
			# Springs up from nothing (the spring overshoots, then settles).
			_springs[b] = [0.0, 0.25 + k * 0.05]
		_buttons[0].grab_focus.call_deferred()
		var hint := _root.get_node("Hint") as Label
		hint.create_tween().tween_property(hint, "modulate:a", 1.0, 0.4).set_delay(0.3)
		Sfx.play_flat(get_tree(), "ui_hover", -8.0, 0.9)


## Jump to the end of the intro (a key or click while it plays).
func _skip_intro() -> void:
	if _t >= T_END:
		return
	var fresh := not _fired.has("hit")
	if fresh:
		# Still break the glass: skipping is the hit.
		_t = T_HIT
		_fired["hum"] = true
		_fired["streaks"] = true
		_fired["ball"] = true
		_run_intro()
	_t = maxf(_t, T_BUTTONS)
	if fresh:
		_intro.broken_at = _t - 0.05  # the glass still falls away over the revealed screen
	for i in LogoLayer.WORD.length():
		if not _fired.has("letter%d" % i):
			_fired["letter%d" % i] = true
			_logo.slam(i, _t - 0.3)
	_fired["last_boom"] = true
	_run_intro()


# --- Every frame ----------------------------------------------------------------------

func _process(delta: float) -> void:
	_t += delta
	if not _sounds_ready:
		var sfx := get_tree().root.get_node_or_null("Sfx")
		_held += delta
		_sounds_ready = sfx == null or sfx.call("has_sound", "impact_boom") or _held > 6.0
		if not _sounds_ready:
			_t = 0.0
	var view := _root.size
	var centre := view * 0.5
	if _t < T_END + 1.0:
		_run_intro()
	_intro.size = view
	_intro.queue_redraw()
	_logo.now = _t
	_shake = move_toward(_shake, 0.0, delta * 2.2)
	var shake := Vector2(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) * 18.0 * _shake * _shake
	# The music's swell: low and mid energy, smoothed, with a "beat" when it jumps.
	var energy := 0.0
	if _spectrum:
		var low := _spectrum.get_magnitude_for_frequency_range(30.0, 250.0).length()
		var mid := _spectrum.get_magnitude_for_frequency_range(250.0, 2000.0).length()
		energy = clampf((low * 2.0 + mid) * 6.0, 0.0, 1.0)
	_beat_cool -= delta
	# No beat heard for a while (the menu track is slow): a gentle one anyway.
	if _t > T_END and ((energy > _pulse + 0.25 and _beat_cool <= 0.0) or _beat_cool < -1.6):
		_pulse = 1.0
		_beat_cool = 0.45
	_pulse = move_toward(_pulse, energy * 0.4, delta * 1.8)
	# Where the "mouse" is: the real one, or a slow drift on a controller.
	var pointer := _root.get_local_mouse_position()
	if Input.get_connected_joypads().size() > 0 and Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		pointer = centre + Vector2(sin(_t * 0.4), cos(_t * 0.3)) * view * 0.15
	var off := (pointer - centre).clamp(-centre, centre)
	var follow := 1.0 - exp(-delta * 6.0)
	# The backdrop drifts least.
	for tex in _back:
		tex.size = view * 1.12
		var goal := -view * 0.06 - off * PARALLAX * 0.6
		tex.position = tex.position.lerp(goal, follow) + shake * 0.3
	for i in _layers.size():
		var node := _layers[i]
		var depth := float(i + 1)
		node.size = view
		node.pivot_offset = view * 0.5
		var bob := Vector2(50.0 * sin(deg_to_rad(267.0) * _t), 40.0 * cos(deg_to_rad(200.0) * _t)) * (0.25 + depth * 0.12)
		var goal := -off * PARALLAX * depth + bob
		node.position = node.position.lerp(goal, follow) + shake
		var sway := (1.0 + depth * 0.2) * cos(deg_to_rad(120.0) * (depth + _t))
		node.rotation = deg_to_rad(sway * 0.8 - node.position.x * 0.004)
		var swell := 1.0 + _pulse * (0.012 + depth * 0.008)
		node.scale = node.scale.lerp(Vector2.ONE * swell, 1.0 - exp(-delta * 10.0))
		node.queue_redraw()
	# Buttons: a gentle wobble and breathe; bigger and brighter under the pointer; springy
	# (the spring steps 30 times a second, like the original).
	_spring_acc += delta
	var steps := 0
	while _spring_acc >= 1.0 / 30.0:
		_spring_acc -= 1.0 / 30.0
		steps += 1
	for k in _buttons.size():
		var b := _buttons[k]
		b.size = b.custom_minimum_size
		b.pivot_offset = b.size * 0.5
		b.position = Vector2(centre.x + (k * 2 - 1) * 170.0 - b.size.x * 0.5, view.y * 0.74)
		if _t < T_BUTTONS:
			b.scale = Vector2.ZERO
			continue
		var hot := (b.is_hovered() or b.has_focus()) and not _leaving
		var s: Array = _springs[b]
		var rest := 1.2 + 0.03 * sin(deg_to_rad(400.0) * _t) if hot else 1.0 + 0.03 * sin(deg_to_rad(400.0) * (k * 3 + _t))
		for step in steps:
			s[1] = 0.8 * (s[1] + 0.9 * (rest - s[0]) * 0.35)
			s[0] += s[1]
		b.scale = Vector2.ONE * maxf(s[0], 0.0)
		b.rotation = deg_to_rad((5.0 if hot else 2.0) * sin(deg_to_rad(360.0 if hot else 180.0) * (k * 0.5 + _t)) + s[1] * 40.0)
		var glow := 1.0 + (0.25 * (0.5 + 0.5 * sin(TAU * _t)) if hot else 0.0)
		b.self_modulate = Color(glow, glow, glow)
	var hint := _root.get_node("Hint") as Label
	hint.size = Vector2(view.x, 20)
	hint.position = Vector2(0, view.y * 0.74 + 92)
	if _t > T_BUTTONS + 0.8:
		hint.modulate.a = 0.45 + 0.4 * sin(_t * 3.0)
	# Every CYCLE seconds: a flash in the current colour, and a new map and colours.
	if not _leaving and _t >= _next_swap:
		_next_swap = _t + CYCLE
		_swap()


func _swap() -> void:
	_flash.color = Color.from_hsv(_hue, 0.5, 1.0, 0.0)
	var tw := create_tween().set_trans(Tween.TRANS_SINE)
	tw.tween_property(_flash, "color:a", 0.75, 0.12)
	tw.tween_callback(func() -> void:
		_map_i += 1
		_back[0].texture = _load_map(_map_i)
		_recolour()
		Sfx.play_flat(get_tree(), "ui_page", -14.0, 0.8))
	tw.tween_property(_flash, "color:a", 0.0, 0.45)


## A click on the background: skips the intro, or (after it) counts as PLAY.
func _on_root_input(event: InputEvent) -> void:
	if _leaving or not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	if _t < T_END:
		_skip_intro()
	else:
		_choose(_buttons[0], "play")


## Keys and the controller: any of them skips the intro; Start counts as PLAY after it
## (A presses whichever button is focused).
func _unhandled_input(event: InputEvent) -> void:
	if _leaving:
		return
	var pressed: bool = (event is InputEventKey or event is InputEventJoypadButton) and event.is_pressed() and not event.is_echo()
	if not pressed:
		return
	if _t < T_END:
		_skip_intro()
		get_viewport().set_input_as_handled()
	elif event is InputEventJoypadButton and event.button_index == JOY_BUTTON_START:
		_choose(_buttons[0], "play")
		get_viewport().set_input_as_handled()


## A button was pressed: it shatters, then the screen fades to black and goes.
func _choose(b: Button, choice: String) -> void:
	if _leaving or _t < T_BUTTONS:
		return
	_leaving = true
	Sfx.play_flat(get_tree(), "shatter", -4.0, 1.25)
	Sfx.play_flat(get_tree(), "ui_click", -4.0, 1.2)
	# The button breaks where it stands (in its current size and tilt).
	var corners := PackedVector2Array()
	var xf := b.get_transform()
	for c in [Vector2.ZERO, Vector2(b.size.x, 0), b.size, Vector2(0, b.size.y)]:
		corners.append(xf * c)
	var hit := xf * (b.size * 0.5 + Vector2(_rng.randf_range(-30, 30), 0))
	var burst := ShatterLayer.new()
	burst.tint = Color.from_hsv(_hue, 0.35, 1.0, 0.85)
	burst.glass.build(corners, hit, 1.3, 10, 3)
	_root.add_child(burst)
	_root.move_child(burst, _flash.get_index())
	b.visible = false
	_shake = 0.5
	var tw := create_tween()
	tw.tween_interval(0.45)
	tw.tween_property(_black, "color:a", 1.0, 0.35).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(func() -> void:
		done.emit(choice)
		# Everything but the black goes; the black fades to show the menu.
		for c in _root.get_children():
			if c != _black:
				c.visible = false)
	tw.tween_property(_black, "color:a", 0.0, 0.45).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(queue_free)


# --- Layers ---------------------------------------------------------------------------

## The intro's own layer: black with the breathing light, the streaks and the ball, and
## after the hit, the black pane shattering away.
class IntroLayer:
	extends Control
	var t := 0.0
	var broken_at := -1.0
	var glass := GlassShards.new()
	var _streaks: Array = []  # [angle, start delay, length, width]

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		for i in 90:
			_streaks.append([randf() * TAU, randf_range(0.0, 0.6), randf_range(0.15, 0.5), randf_range(1.0, 3.0)])

	func _draw() -> void:
		var view := size
		var c := view * 0.5
		if broken_at >= 0.0:
			# The pane falling away (dark glass with bright edges).
			var k := clampf((t - broken_at) / T_GLASS, 0.0, 1.0)
			if k < 1.0:
				glass.draw(self, Vector2.ZERO, GlassShards.CRACK + k * (1.0 - GlassShards.CRACK), Color(0.015, 0.02, 0.035, 1.0))
			return
		draw_rect(Rect2(Vector2.ZERO, view), Color(0.005, 0.008, 0.015))
		var diag := view.length() * 0.6
		# The point of light, breathing, growing as the hit nears.
		var grow := clampf(t / T_HIT, 0.0, 1.0)
		var breathe := 0.6 + 0.4 * sin(Time.get_ticks_msec() / 1000.0 * 9.0)
		for ring in 6:
			var r := (4.0 + ring * 7.0) * (0.6 + grow * 1.6) * (0.85 + breathe * 0.15)
			draw_circle(c, r, Color(0.6, 0.9, 1.0, (0.22 - ring * 0.033) * (0.4 + grow)))
		draw_circle(c, 3.0 + grow * 5.0, Color(1, 1, 1, 0.9))
		# Streaks rushing in toward the light.
		if t > T_STREAKS:
			for s in _streaks:
				var u := fposmod((t - T_STREAKS - float(s[1])) * 1.6, 1.0)
				if t - T_STREAKS < float(s[1]):
					continue
				var dir := Vector2.from_angle(float(s[0]))
				var far := diag * (1.0 - u)
				var near := maxf(far - diag * float(s[2]) * (0.4 + u), 12.0)
				var alpha := u * 0.8
				draw_line(c + dir * far, c + dir * near, Color(0.65, 0.92, 1.0, alpha), float(s[3]), true)
		# The ball: in from the left, fast, with a trail, straight into the light.
		if t > T_BALL:
			var u2 := clampf((t - T_BALL) / (T_HIT - T_BALL), 0.0, 1.0)
			u2 = u2 * u2
			var from := Vector2(-80.0, c.y + 140.0)
			var at := from.lerp(c, u2)
			var r2 := 26.0 + u2 * 10.0
			for k2 in 14:
				var back := at.lerp(from, k2 * 0.035)
				draw_circle(back, r2 * (1.0 - k2 * 0.06), Color(0.35, 0.85, 1.0, 0.16 * (1.0 - k2 / 14.0)))
			draw_circle(at, r2 * 1.5, Color(0.4, 0.85, 1.0, 0.25))
			draw_circle(at, r2, Color(0.06, 0.1, 0.16))
			# Crystal facets and a highlight.
			for f in 5:
				var a0 := t * 8.0 + TAU * f / 5.0
				draw_colored_polygon(PackedVector2Array([at, at + Vector2.from_angle(a0) * r2, at + Vector2.from_angle(a0 + 0.9) * r2]),
					Color(0.35, 0.85, 1.0, 0.25 + 0.15 * (f % 2)))
			draw_arc(at, r2, 0.0, TAU, 32, Color(0.75, 0.95, 1.0, 0.9), 2.0, true)
			draw_circle(at + Vector2(-r2 * 0.35, -r2 * 0.4), r2 * 0.18, Color(1, 1, 1, 0.8))


## Crystal shards drawn in code, one layer of them across the screen.
class ArtLayer:
	extends Control
	var hue := 0.5
	var count := 7
	var scale_by := 1.0
	var _shapes: Array = []  # [centre (0..1 of the screen), points round it (in screen heights), Color]

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func seed_shapes(seed_value: int) -> void:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		_shapes.clear()
		for i in count:
			var c := Vector2(rng.randf_range(0.0, 1.0), rng.randf_range(0.0, 1.0))
			# Keep the logo and the buttons clear.
			if absf(c.x - 0.5) < 0.3 and c.y > 0.12 and c.y < 0.9:
				c.x = 0.5 + signf(c.x - 0.5 + 0.001) * rng.randf_range(0.34, 0.5)
			var length := rng.randf_range(0.06, 0.15) * scale_by
			var width := length * rng.randf_range(0.18, 0.3)
			var dir := Vector2.from_angle(rng.randf() * TAU)
			var side := Vector2(-dir.y, dir.x)
			var tip := dir * length
			var tail := -dir * length * 0.6
			var col := Color.from_hsv(fposmod(hue + rng.randf_range(-0.05, 0.05), 1.0), 0.45, 1.0, 0.85)
			# Two facets, one lit and one shaded, like a cut crystal, and a bright edge.
			_shapes.append([c, PackedVector2Array([tail, side * width, tip]), col])
			_shapes.append([c, PackedVector2Array([tail, tip, -side * width]), col.darkened(0.35)])
			_shapes.append([c, PackedVector2Array([tail, tip, tip * 0.98 + side * width * 0.06]), Color(1, 1, 1, 0.55)])
		queue_redraw()

	func _draw() -> void:
		var s := size
		# Placed by the screen, sized by its height: right whatever the window's shape.
		for shape in _shapes:
			var c := Vector2(shape[0].x * s.x, shape[0].y * s.y)
			var pts := PackedVector2Array()
			for p in shape[1]:
				pts.append(c + p * s.y)
			draw_colored_polygon(pts, shape[2])


## BALLISTIC, letter by letter: each one slams down from big, with a colour ghost, a
## shadow and a rim in the current hue; the subtitle types out underneath.
class LogoLayer:
	extends Control
	const WORD := "BALLISTIC"
	const SUB := "COMBAT SIMULATION  //  CRYSTAL WEAPONS DIVISION"
	const SIZE := 132
	var hue := 0.55
	var now := 0.0
	var typed := 0.0
	var _slams := {}  # letter index -> when it slammed
	var _font: Font
	var _sub_font: Font

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_font = UIStyle.font(true)
		_sub_font = UIStyle.font(true)

	func slam(i: int, at: float) -> void:
		_slams[i] = at

	func _draw() -> void:
		var view := size
		var total := _font.get_string_size(WORD, HORIZONTAL_ALIGNMENT_LEFT, -1, SIZE).x
		var x := (view.x - total) * 0.5
		var base_y := view.y * 0.3 + SIZE * 0.35
		var rim := Color.from_hsv(hue, 0.7, 0.35, 0.95)
		for i in WORD.length():
			var ch := WORD[i]
			var w := _font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, SIZE).x
			if _slams.has(i):
				var u := clampf((now - float(_slams[i])) / 0.16, 0.0, 1.0)
				# From 2.6x and see-through down to its place, a tiny bounce at the end.
				var k := 1.0 + (1.0 - u) * (1.0 - u) * 1.6 - sin(u * PI) * 0.06 * u
				var centre := Vector2(x + w * 0.5, base_y - SIZE * 0.35)
				draw_set_transform(centre, 0.0, Vector2.ONE * k)
				var at := Vector2(-w * 0.5, SIZE * 0.35)
				var alpha := clampf(u * 1.5, 0.0, 1.0)
				# Colour ghosts that snap together as it lands.
				var split := (1.0 - u) * 14.0 + 1.5
				draw_string(_font, at + Vector2(-split, 0), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, SIZE, Color(1.0, 0.25, 0.45, 0.45 * alpha))
				draw_string(_font, at + Vector2(split, 0), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, SIZE, Color(0.3, 0.9, 1.0, 0.45 * alpha))
				draw_string(_font, at + Vector2(0, 10), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, SIZE, Color(0, 0, 0, 0.45 * alpha))
				draw_string_outline(_font, at, ch, HORIZONTAL_ALIGNMENT_LEFT, -1, SIZE, 22, Color(rim, rim.a * alpha))
				draw_string(_font, at, ch, HORIZONTAL_ALIGNMENT_LEFT, -1, SIZE, Color(1, 1, 1, alpha))
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			x += w
		if typed > 0.0:
			var shown := SUB.substr(0, int(SUB.length() * typed))
			var sw := _sub_font.get_string_size(SUB, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
			var col := Color.from_hsv(hue, 0.55, 1.0)
			draw_string(_sub_font, Vector2((view.x - sw) * 0.5, view.y * 0.3 + 95), shown + ("_" if typed < 1.0 else ""), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, col)


## A pressed button breaking.
class ShatterLayer:
	extends Control
	var glass := GlassShards.new()
	var tint := Color.WHITE
	var _t := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_preset(Control.PRESET_FULL_RECT)

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		glass.draw(self, Vector2.ZERO, _t / 0.9, tint)
