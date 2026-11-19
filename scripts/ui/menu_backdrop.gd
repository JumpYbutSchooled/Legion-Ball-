extends SubViewportContainer
## The main menu's backdrop: one of the real maps, live, with a camera circling slowly over
## it, dimmed so the menu reads on top. The map is loaded without its arena (no players, no
## rules: just the level, its sun and its sky), in a world of its own, merged and graded
## like it is in play. A different map every time the menu opens. On LOW graphics (or with
## no screen) the menu keeps its flat grid instead (main_menu.gd).

const MapMerge := preload("res://scripts/map_merge.gd")
const Graphics := preload("res://scripts/graphics.gd")
## Maps that look good from the air: [scene, the point the camera circles, how far out, how high].
const VIEWS := [
	["res://scenes/arena_coliseum.tscn", Vector3(0, 10, 0), 250.0, 120.0],
	["res://scenes/arena_castle.tscn", Vector3(0, 10, 0), 240.0, 90.0],
	["res://scenes/arena_el_dorado.tscn", Vector3(0, 15, 0), 220.0, 100.0],
	["res://scenes/arena_eden.tscn", Vector3(0, 110, 0), 420.0, 260.0],
	["res://scenes/arena_city.tscn", Vector3(0, 40, 0), 300.0, 170.0],
	["res://scenes/arena_seaside_village.tscn", Vector3(-10, 0, 0), 190.0, 80.0],
	["res://scenes/arena_chess.tscn", Vector3(0, 0, 0), 300.0, 150.0],
	["res://scenes/arena_starship.tscn", Vector3(0, -5, 190), 520.0, 260.0],
	["res://scenes/arena.tscn", Vector3(0, 2, 0), 150.0, 45.0],
]

var _view: SubViewport
var _cam: Camera3D
var _at := Vector3.ZERO
var _out := 200.0
var _up := 80.0
var _angle := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view = SubViewport.new()
	_view.own_world_3d = true
	_view.msaa_3d = Viewport.MSAA_2X
	_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_view)
	var pick: Array = VIEWS[randi() % VIEWS.size()]
	var packed := load(pick[0]) as PackedScene
	if not packed:
		return
	var level := packed.instantiate()
	# Just the level: without the arena's script nothing spawns and no match starts.
	level.set_script(null)
	for extra in ["Targets", "LockTargets", "Players"]:
		var node := level.get_node_or_null(extra)
		if node:
			level.remove_child(node)
			node.free()
	_view.add_child(level)
	var map := level.get_node_or_null("Map") as Node3D
	if map:
		MapMerge.boxify(map)
		MapMerge.merge(map)
	var env_node := level.get_node_or_null("WorldEnvironment") as WorldEnvironment
	var sun := level.get_node_or_null("Sun") as DirectionalLight3D
	var layout := level.get_node_or_null("Map/Layout")
	var indoor: bool = layout != null and layout.has_method("is_indoor") and layout.call("is_indoor")
	var scale: float = layout.get("map_scale") if layout and "map_scale" in layout else 1.0
	if env_node and env_node.environment:
		Graphics._grade(env_node.environment, sun, indoor or not sun or sun.light_energy < 0.05)
		Graphics._sky(env_node.environment, sun, indoor, String(pick[0]).get_file().get_basename())
		env_node.environment.volumetric_fog_enabled = false
	if sun:
		sun.shadow_enabled = true
		sun.directional_shadow_max_distance = 900.0
	_at = (pick[1] as Vector3) * scale
	_out = float(pick[2]) * scale
	_up = float(pick[3]) * scale
	_angle = randf() * TAU
	_cam = Camera3D.new()
	_cam.fov = 55.0
	_cam.far = 6000.0
	_view.add_child(_cam)
	_cam.make_current()
	# Dimmed and cooled, so the menu's text stays the brightest thing on screen.
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.0, 0.02, 0.05, 0.5)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	_place()


func _process(delta: float) -> void:
	_angle += delta * 0.035
	_place()


func _place() -> void:
	if _cam:
		_cam.look_at_from_position(_at + Vector3(sin(_angle) * _out, _up, cos(_angle) * _out), _at)
