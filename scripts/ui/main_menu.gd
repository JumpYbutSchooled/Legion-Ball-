extends Control
## Main menu: simulation-grid backdrop, a glitching title, and the shared menu panels.

const UIStyle := preload("res://scripts/ui/ui_style.gd")
const MenuUI := preload("res://scripts/ui/menu_ui.gd")
const GridShader := preload("res://shaders/sim_grid.gdshader")
const Services := preload("res://scripts/services.gd")
const GAME_SCENE := "res://scenes/arena.tscn"

var _title: Label
var _ghost_a: Label
var _ghost_b: Label
var _glitch_timer := 0.0


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
	ui.play_pressed.connect(func() -> void: get_tree().change_scene_to_file(GAME_SCENE))
	ui.quit_pressed.connect(func() -> void: get_tree().quit())


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
	_glitch_timer -= delta
	if _glitch_timer <= 0.0:
		# Mostly calm, with short bursts of jitter.
		var burst := randf() < 0.25
		_glitch_timer = randf_range(0.03, 0.08) if burst else randf_range(0.4, 1.4)
		var amount := 7.0 if burst else 1.5
		_ghost_a.position = _title.position + Vector2(randf_range(-amount, amount), randf_range(-1, 1))
		_ghost_b.position = _title.position + Vector2(randf_range(-amount, amount), randf_range(-1, 1))
