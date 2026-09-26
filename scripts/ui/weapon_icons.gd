extends Node
## Pictures of the weapons for the Armory's picker (weapon_picker.gd): each weapon's real
## blades round a ball, rendered once into a small off-screen viewport, one weapon a
## frame, and kept for the rest of the game. The blades get a solid material in the
## weapon's colour (their in-game shader is see-through glass, which would vanish here).
## request(id) returns the picture, or null (and queues it) if it isn't ready yet;
## icon_ready fires when it is.

signal icon_ready(id: String)

const WeaponInfo := preload("res://scripts/weapon_info.gd")
const SIZE := 128

static var _cache := {}

var _queue: Array[String] = []
var _viewport: SubViewport
var _camera: Camera3D
var _stage: Node3D
var _current := ""
var _weapon: Node3D
var _wait := 0
## Frames to let the new viewport settle before the first picture (its first frames
## come out blank).
var _warm := 4


static func cached(id: String) -> Texture2D:
	return _cache.get(id)


func request(id: String) -> Texture2D:
	if _cache.has(id):
		return _cache[id]
	if DisplayServer.get_name() == "headless":
		return null  # Nothing to draw with.
	if id != _current and not _queue.has(id):
		_queue.append(id)
	return null


func _ready() -> void:
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(SIZE, SIZE)
	_viewport.transparent_bg = true
	_viewport.own_world_3d = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_viewport)
	_stage = Node3D.new()
	_viewport.add_child(_stage)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.55, 0.6, 0.7)
	env.environment.ambient_light_energy = 0.8
	_viewport.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	sun.light_energy = 1.4
	_viewport.add_child(sun)
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_viewport.add_child(_camera)
	# The ball the blades wrap round.
	var ball := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.14, 0.15, 0.18)
	mat.metallic = 0.6
	mat.roughness = 0.35
	ball.mesh = sphere
	ball.material_override = mat
	_stage.add_child(ball)


func _process(_delta: float) -> void:
	if _warm > 0:
		_warm -= 1
		_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		return
	if _current == "":
		if _queue.is_empty():
			return
		_current = _queue.pop_front()
		_pose(_current)
		_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		_wait = 6
		return
	_wait -= 1
	# Drawn twice: the first draw of a new material can come out empty while the GPU
	# prepares it.
	if _wait == 3:
		_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	if _wait > 0:
		return
	var image := _viewport.get_texture().get_image()
	if image:
		_cache[_current] = ImageTexture.create_from_image(image)
	if is_instance_valid(_weapon):
		_weapon.queue_free()
	var done := _current
	_current = ""
	icon_ready.emit(done)


## Builds weapon `id` on the stage with solid blades and frames the camera on it.
func _pose(id: String) -> void:
	var info := WeaponInfo.by_id(id)
	if not info.has("script"):
		return
	_weapon = load(info["script"]).new()
	_weapon.set("color", info["color"])
	_stage.add_child(_weapon)
	# Held still, fully out: no animation (it has no player to follow here).
	_weapon.set_process(false)
	_weapon.set_physics_process(false)
	_weapon.visible = true
	var color: Color = info["color"]
	var solid := StandardMaterial3D.new()
	solid.albedo_color = color.darkened(0.35)
	solid.emission_enabled = true
	solid.emission = color
	solid.emission_energy_multiplier = 0.9
	solid.roughness = 0.25
	solid.metallic = 0.3
	var box := AABB(Vector3(-0.5, -0.5, -0.5), Vector3.ONE)
	for blade in _weapon.get("_blades"):
		var mesh_node := blade as MeshInstance3D
		mesh_node.material_override = solid
		if mesh_node.mesh:
			box = box.merge(mesh_node.transform * mesh_node.mesh.get_aabb())
	# A three-quarter view from front-right and above, fitted to the blades.
	var center := box.get_center()
	var view := Vector3(1.0, 0.75, -0.9).normalized()
	_camera.size = maxf(box.size.length() * 0.78, 2.4)
	_camera.look_at_from_position(center + view * 30.0, center, Vector3.UP)
