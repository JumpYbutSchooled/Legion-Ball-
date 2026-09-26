extends SceneTree
## Renders the game's icon: a player ball wrapped in cyan crystal blades, on a
## transparent background. Writes res://icon.png (the window and taskbar icon, set at
## runtime by main_menu.gd) and res://icon.ico (16-256 px, embedded in the .exe by the
## base build).
##   Godot --path . --script tools/make_icon.gd     (needs a window: not --headless)

const SIZE := 256
const BladeMesh := preload("res://scripts/energy_blade_mesh.gd")
const BallMesh := preload("res://scripts/goldberg_ball_mesh.gd")

var _viewport: SubViewport
var _frames := 0
var _blades: Array[MeshInstance3D] = []
var _blade_mat: StandardMaterial3D


func _initialize() -> void:
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(SIZE, SIZE)
	_viewport.transparent_bg = true
	_viewport.own_world_3d = true
	_viewport.msaa_3d = Viewport.MSAA_8X
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_viewport)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.5, 0.65, 0.8)
	env.environment.ambient_light_energy = 0.7
	_viewport.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 30, 0)
	sun.light_energy = 1.6
	_viewport.add_child(sun)
	var rim := OmniLight3D.new()
	rim.light_color = Color(0.35, 0.9, 1.0)
	rim.light_energy = 6.0
	rim.omni_range = 6.0
	rim.position = Vector3(-1.5, 0.8, 1.2)
	_viewport.add_child(rim)

	var stage := Node3D.new()
	_viewport.add_child(stage)
	var ball := MeshInstance3D.new()
	ball.set_script(BallMesh)
	stage.add_child(ball)
	var cyan := Color(0.35, 0.9, 1.0)
	var blade_mat := StandardMaterial3D.new()
	blade_mat.albedo_color = cyan.lightened(0.2)
	blade_mat.emission_enabled = true
	blade_mat.emission = cyan
	blade_mat.emission_energy_multiplier = 1.2
	blade_mat.roughness = 0.55
	blade_mat.metallic = 0.0
	# Two crescent blades a side, like the Gatling's rows.
	for roll in [28.0, -24.0]:
		for side in [1.0, -1.0]:
			var blade := BladeMesh.new()
			blade.side = side
			blade.jag_seed = int(roll) + int(side * 7.0)
			stage.add_child(blade)
			blade.transform = Transform3D(Basis(Vector3.BACK, deg_to_rad(roll * side)), Vector3.ZERO)
			_blades.append(blade)
	_blade_mat = blade_mat

	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 3.7
	_viewport.add_child(camera)
	camera.look_at_from_position(Vector3(-2.6, 1.5, -2.6).normalized() * 20.0 + Vector3(0.0, 0.1, -1.25), Vector3(0.0, 0.1, -1.25), Vector3.UP)


func _process(_delta: float) -> bool:
	_frames += 1
	# The blades set their own (glass) material when they're first ready: swap it after.
	for blade in _blades:
		blade.material_override = _blade_mat
	if _frames < 12:
		return false
	var image := _viewport.get_texture().get_image()
	image.convert(Image.FORMAT_RGBA8)
	image.save_png("res://icon.png")
	_write_ico(image, "res://icon.ico")
	print("icon written")
	quit()
	return false


## A Windows .ico holding PNG pictures at the usual sizes.
func _write_ico(source: Image, path: String) -> void:
	var sizes := [256, 128, 64, 48, 32, 16]
	var pngs: Array[PackedByteArray] = []
	for s in sizes:
		var img := source.duplicate() as Image
		img.resize(s, s, Image.INTERPOLATE_LANCZOS)
		pngs.append(img.save_png_to_buffer())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_16(0)  # Reserved.
	f.store_16(1)  # Icon.
	f.store_16(sizes.size())
	var offset := 6 + 16 * sizes.size()
	for i in sizes.size():
		var s: int = sizes[i]
		f.store_8(0 if s >= 256 else s)  # Width (0 = 256).
		f.store_8(0 if s >= 256 else s)  # Height.
		f.store_8(0)  # Palette.
		f.store_8(0)  # Reserved.
		f.store_16(1)  # Colour planes.
		f.store_16(32)  # Bits per pixel.
		f.store_32(pngs[i].size())
		f.store_32(offset)
		offset += pngs[i].size()
	for png in pngs:
		f.store_buffer(png)
	f.close()
