extends Control
## Main menu: simulation-grid backdrop, a glitching title, and the shared menu panels.

const UIStyle := preload("res://scripts/ui/ui_style.gd")
const MenuUI := preload("res://scripts/ui/menu_ui.gd")
const GridShader := preload("res://shaders/sim_grid.gdshader")
const Services := preload("res://scripts/services.gd")
const Changelog := preload("res://scripts/ui/changelog.gd")
const GAME_SCENE := "res://scenes/arena.tscn"

var _title: Label
var _ghost_a: Label
var _ghost_b: Label
var _glitch_timer := 0.0
var _ui: Control
var _bg_mat: ShaderMaterial
## Backdrop tear strength (sim_grid.gdshader glitch), kicked by the title's bursts.
var _tear := 0.0


func _ready() -> void:
	# Normally the boot scene has already created these; this covers running the
	# menu straight from the editor. Deferred: the root is busy while this scene loads.
	_ensure_services.call_deferred()
	theme = UIStyle.make_theme()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = false
	Engine.time_scale = 1.0

	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	var mat := ShaderMaterial.new()
	mat.shader = GridShader
	bg.material = mat
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	_bg_mat = mat

	# Title, with red/cyan ghost copies that jitter now and then (chromatic glitch).
	_ghost_a = _title_label(Color(1.0, 0.2, 0.35, 0.55))
	_ghost_b = _title_label(Color(0.2, 0.9, 1.0, 0.55))
	_title = _title_label(Color.WHITE)
	var sub := UIStyle.label("COMBAT SIMULATION  //  CRYSTAL WEAPONS DIVISION", 15, UIStyle.ACCENT)
	sub.position = Vector2(68, 128)
	add_child(sub)
	var corner := UIStyle.label("SIM-LB  v%s\n60 HZ  //  JOLT" % _version(), 12, UIStyle.TEXT_DIM)
	corner.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	corner.position = Vector2(-190, 36)
	corner.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(corner)

	var ui := MenuUI.new()
	ui.pause_mode = false
	add_child(ui)
	ui.play_pressed.connect(func(scene: String) -> void: get_tree().change_scene_to_file(scene))
	ui.quit_pressed.connect(func() -> void: get_tree().quit())
	_ui = ui
	_whats_new.call_deferred()


## First time on a new version: a message with everything that's changed since the last
## version you saw (or just this one, on a first install).
func _whats_new() -> void:
	var settings := get_tree().root.get_node_or_null("Settings")
	var version := _version()
	if not settings or version == "?":
		return
	var seen: String = settings.call("get_value", "last_seen_version")
	if seen == version:
		return
	settings.call("set_value", "last_seen_version", version)
	var news: Array = Changelog.since(seen) if seen != "" else Changelog.since("").slice(0, 1)
	# Only what this build knows about (not anything newer than it).
	news = news.filter(func(e: Dictionary) -> bool: return not Changelog.newer(String(e["version"]), version))
	if news.is_empty():
		return
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.0, 0.02, 0.04, 0.7)
	add_child(dim)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(640, 0)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	dim.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	var title := "// UPDATED TO v%s" % version if seen != "" else "// WELCOME TO v%s" % version
	box.add_child(UIStyle.label(title, 24, UIStyle.ACCENT, true))
	if seen != "":
		box.add_child(UIStyle.label("WHAT'S NEW SINCE v%s" % seen, 13, UIStyle.TEXT_DIM))
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, mini(120 + news.size() * 70, 360))
	box.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 8)
	scroll.add_child(list)
	for e in news:
		list.add_child(UIStyle.label("v%s   %s" % [e["version"], e.get("date", "")], 15, Color.WHITE, true))
		var notes := UIStyle.label(String(e.get("notes", "")), 15, UIStyle.TEXT)
		notes.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		notes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		list.add_child(notes)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 14)
	box.add_child(buttons)
	var close := func() -> void: dim.queue_free()
	var all := Button.new()
	all.text = "[ SEE ALL UPDATES ]"
	all.pressed.connect(func() -> void:
		close.call()
		_ui.call("_show_page", "updates"))
	buttons.add_child(all)
	var ok := Button.new()
	ok.text = "[ CLOSE ]"
	ok.pressed.connect(close)
	buttons.add_child(ok)
	ok.grab_focus.call_deferred()
	# Pops in.
	panel.pivot_offset = panel.size / 2.0
	panel.scale = Vector2(0.9, 0.9)
	panel.modulate.a = 0.0
	var tw := panel.create_tween().set_parallel().set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_property(panel, "scale", Vector2.ONE, 0.35)
	tw.tween_property(panel, "modulate:a", 1.0, 0.25)
	MenuUI.ui_sound(self, "ui_page", -6.0)


func _ensure_services() -> void:
	Services.ensure(get_tree())


func _version() -> String:
	var f := FileAccess.open("res://version.txt", FileAccess.READ)
	return f.get_as_text().strip_edges() if f else "?"


func _title_label(color: Color) -> Label:
	var l := UIStyle.label("LEIGON BALL", 72, color, true)
	l.position = Vector2(62, 34)
	add_child(l)
	return l


func _process(delta: float) -> void:
	_tear = move_toward(_tear, 0.0, delta * 6.0)
	_bg_mat.set_shader_parameter("glitch", _tear)
	_glitch_timer -= delta
	if _glitch_timer <= 0.0:
		# Mostly calm, with short bursts of jitter.
		var burst := randf() < 0.25
		_glitch_timer = randf_range(0.03, 0.08) if burst else randf_range(0.4, 1.4)
		var amount := 7.0 if burst else 1.5
		# Now and then a burst tears the whole backdrop too.
		if burst and randf() < 0.3:
			_tear = randf_range(0.5, 1.0)
		_ghost_a.position = _title.position + Vector2(randf_range(-amount, amount), randf_range(-1, 1))
		_ghost_b.position = _title.position + Vector2(randf_range(-amount, amount), randf_range(-1, 1))
