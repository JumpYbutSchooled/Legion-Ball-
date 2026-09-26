extends SceneTree
## Renders a thumbnail of every combat map for the map select (scripts/ui/map_grid.gd):
## loads each one with the wireframe build-in off, hides the HUD, frames it from a good
## angle and saves res://textures/maps/<name>.png (480 x 270).
##   Godot --path . --resolution 960x540 --script tools/make_map_thumbs.gd   (not --headless)
## Pass a map name after -- to redo just that one: ... --script tools/make_map_thumbs.gd -- castle

const OUT := "res://textures/maps/"
const SIZE := Vector2i(480, 270)
## Camera position and what it looks at, per map (scene file name without "arena_").
const VIEWS := {
	"training": [Vector3(40, 30, 110), Vector3(0, 2, 30)],
	"sprawl": [Vector3(0, 200, 300), Vector3(0, 0, 0)],
	"coliseum": [Vector3(0, 95, 175), Vector3(0, 0, 0)],
	"box": [Vector3(-95, 70, -95), Vector3(40, 10, 40)],
	"thunderdome": [Vector3(55, 22, 55), Vector3(0, 4, 0)],
	"tunnels": [Vector3(-3, 8, 12), Vector3(0, 2, -10)],
	"city": [Vector3(190, 150, 190), Vector3(0, 0, 0)],
	"castle": [Vector3(60, 110, 250), Vector3(0, 10, 0)],
	"daytona": [Vector3(0, 230, 430), Vector3(0, 0, 0)],
	"talladega": [Vector3(0, 280, 540), Vector3(0, 0, 0)],
	"atlantis": [Vector3(0, 160, 240), Vector3(0, 0, 0)],
	"el_dorado": [Vector3(130, 110, 190), Vector3(0, 15, 0)],
	"military_base": [Vector3(0, 190, 310), Vector3(0, 0, 0)],
	"house": [Vector3(-20, 13, -52), Vector3(-62, 10, -8)],
	"trench_run": [Vector3(0, 22, -420), Vector3(0, -22, -120)],
	"enterprise": [Vector3(-210, 130, -230), Vector3(0, -20, 150)],
	"gotham": [Vector3(-20, 95, 175), Vector3(0, 40, 0)],
	"chess": [Vector3(0, 125, 230), Vector3(0, 0, 0)],
}

var _queue: Array = []
var _t := 0.0
var _current := ""
var _intro_was := true


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	load("res://scripts/services.gd").ensure(self)
	var settings := root.get_node("Settings")
	_intro_was = settings.call("get_value", "map_intro")
	settings.call("set_value", "map_intro", false)
	var only := OS.get_cmdline_user_args()
	_queue = VIEWS.keys() if only.is_empty() else only
	_next()


func _next() -> void:
	_t = 0.0
	if _queue.is_empty():
		root.get_node("Settings").call("set_value", "map_intro", _intro_was)
		print("THUMBS DONE")
		quit()
		return
	_current = _queue.pop_front()
	change_scene_to_file("res://scenes/arena.tscn" if _current == "training" else "res://scenes/arena_%s.tscn" % _current)


func _process(delta: float) -> bool:
	_t += delta
	if _current == "" or not current_scene:
		return false
	if _t > 1.5 and not current_scene.has_meta("framed"):
		current_scene.set_meta("framed", true)
		_hide_hud(current_scene)
		var cam := Camera3D.new()
		cam.far = 4000.0
		cam.fov = 60.0
		current_scene.add_child(cam)
		var view: Array = VIEWS[_current]
		cam.look_at_from_position(view[0], view[1])
		cam.make_current()
	if _t > 3.0:
		var image := root.get_viewport().get_texture().get_image()
		image.resize(SIZE.x, SIZE.y, Image.INTERPOLATE_LANCZOS)
		image.save_png(OUT + _current + ".png")
		print("saved ", _current)
		_current = ""
		_next()
	return false


## Every overlay (HUD, crosshair, minimap, speedometer) off, and the local ball hidden.
func _hide_hud(node: Node) -> void:
	for child in node.get_children():
		if child is CanvasLayer:
			(child as CanvasLayer).visible = false
		_hide_hud(child)
	var players := current_scene.get_node_or_null("Players")
	if players:
		for ball in players.get_children():
			(ball as Node3D).visible = false
