extends CanvasLayer
## Mouse-wheel weapon browser. Scrolling slides a small, low-key panel in from the left:
## a spinning hologram of the weapon you've scrolled to, its name, and a compact slot
## list (a dot marks the equipped one). Right-click equips it; it hides after a few
## idle seconds. Ctrl + wheel is left alone (camera zoom).

const UIStyle := preload("res://scripts/ui/ui_style.gd")
const WeaponInfo := preload("res://scripts/weapon_info.gd")
const HoloShader := preload("res://shaders/hologram.gdshader")

## The weapon manager (Ball/Weapon).
@export var weapon: Node
@export var idle_hide_time := 3.0
@export var panel_width := 200.0
## Distance from the left edge of the screen when shown.
@export var margin := 20.0
## Overall opacity when fully shown.
@export var opacity := 0.85

var _open := false
var _candidate := 0
var _idle := 0.0
var _slide := 0.0  # 0 hidden .. 1 shown
var _confirm_flash := 0.0

var _panel: PanelContainer
var _name: Label
var _tag: Label
var _rows: Array[Label] = []
var _hint: Label
var _holo_root: Node3D
var _holo_model: Node3D
var _holo_mat: ShaderMaterial
var _pad_mat: ShaderMaterial


func _ready() -> void:
	layer = 8
	# Keeps running while paused, just so it can tuck itself away.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_panel.modulate.a = 0.0


func _unhandled_input(event: InputEvent) -> void:
	if not weapon or get_tree().paused:
		return
	var mb := event as InputEventMouseButton
	if not mb or not mb.pressed or mb.ctrl_pressed:
		return
	match mb.button_index:
		MOUSE_BUTTON_WHEEL_DOWN:
			_browse(1)
			get_viewport().set_input_as_handled()
		MOUSE_BUTTON_WHEEL_UP:
			_browse(-1)
			get_viewport().set_input_as_handled()
		MOUSE_BUTTON_RIGHT:
			if _open:
				weapon.call("select", _candidate)
				_confirm_flash = 1.0
				_idle = idle_hide_time - 0.5  # Close shortly after confirming.
				_refresh()
				get_viewport().set_input_as_handled()


func _browse(step: int) -> void:
	var total := WeaponInfo.count()
	if not _open:
		_open = true
		_candidate = weapon.get("current")
	_candidate = (_candidate + step + total) % total
	_idle = 0.0
	_refresh()


func _process(delta: float) -> void:
	if get_tree().paused:
		_open = false
	if _open:
		_idle += delta
		if _idle >= idle_hide_time:
			_open = false
	_slide = move_toward(_slide, 1.0 if _open else 0.0, delta * 6.0)
	var eased := ease(_slide, 0.4)
	var view := _panel.get_viewport_rect().size
	# Slides in from off the left edge, vertically centered.
	var x := lerpf(-panel_width - 20.0, margin, eased)
	_panel.position = Vector2(x, (view.y - _panel.size.y) / 2.0)
	_panel.modulate.a = eased * opacity
	_panel.visible = _slide > 0.001
	_confirm_flash = move_toward(_confirm_flash, 0.0, delta * 3.0)
	if _holo_root:
		_holo_root.rotate_y(delta * 1.1)
		_holo_mat.set_shader_parameter("intensity", 1.4 + _confirm_flash * 4.0)


func _refresh() -> void:
	var info := WeaponInfo.get_entry(_candidate)
	var color: Color = info["color"]
	_name.text = info["name"]
	_name.add_theme_color_override("font_color", color)
	_tag.text = info["tag"]
	var equipped: int = weapon.get("current")
	for i in _rows.size():
		var row_info := WeaponInfo.get_entry(i)
		var mark := ">" if i == _candidate else " "
		var dot := "  •" if i == equipped else ""
		_rows[i].text = "%s %d %s%s" % [mark, i + 1, row_info["name"], dot]
		_rows[i].add_theme_color_override("font_color", row_info["color"] if i == _candidate else UIStyle.TEXT_DIM)
	_hint.text = "RMB  equip" if _candidate != equipped else "equipped"
	_holo_mat.set_shader_parameter("color", color)
	_pad_mat.set_shader_parameter("color", color)
	_build_hologram(_candidate)


func _build_hologram(slot: int) -> void:
	for child in _holo_model.get_children():
		child.queue_free()
	var weapons: Array = weapon.get("weapons")
	if slot >= weapons.size():
		return
	var source = weapons[slot]
	# A copy of each blade's mesh, placed exactly as on the ball.
	var blades: Array = source.get("_blades")
	var bases: Array = source.get("_bases")
	# The ball's own bounds, then every blade's, so the whole weapon can be fitted.
	var bounds := AABB(Vector3(-0.5, -0.5, -0.5), Vector3.ONE)
	for i in blades.size():
		var mi := MeshInstance3D.new()
		mi.mesh = blades[i].mesh
		mi.material_override = _holo_mat
		mi.transform = Transform3D(bases[i], Vector3.ZERO)
		_holo_model.add_child(mi)
		if mi.mesh:
			bounds = bounds.merge(mi.transform * mi.mesh.get_aabb())
	# Scale to fit the stage and spin round the weapon's middle, whatever its size.
	var fit := 2.6 / maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))
	_holo_model.scale = Vector3.ONE * fit
	_holo_model.position = -bounds.get_center() * fit
	# The ball as a faint polygon shell.
	var ball := SphereMesh.new()
	ball.radius = 0.5
	ball.height = 1.0
	ball.radial_segments = 10
	ball.rings = 6
	var ball_mi := MeshInstance3D.new()
	ball_mi.mesh = ball
	ball_mi.material_override = _holo_mat
	_holo_model.add_child(ball_mi)


func _build_ui() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UIStyle.make_theme()
	add_child(root)

	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(panel_width, 0)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Faint glass: mostly see-through, barely-there border.
	var box_style := UIStyle.panel_box(Color(0.35, 0.9, 1.0, 0.16), Color(0.02, 0.05, 0.08, 0.45))
	box_style.set_content_margin_all(10)
	_panel.add_theme_stylebox_override("panel", box_style)
	root.add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	_panel.add_child(box)

	# Hologram stage: its own little 3D world rendered into the panel.
	var holder := SubViewportContainer.new()
	holder.stretch = true
	holder.custom_minimum_size = Vector2(panel_width - 20.0, 120)
	box.add_child(holder)
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_4X
	holder.add_child(vp)
	var cam := Camera3D.new()
	cam.fov = 40.0
	vp.add_child(cam)
	cam.look_at_from_position(Vector3(2.5, 1.8, 2.5), Vector3(0, -0.15, 0))
	_holo_mat = ShaderMaterial.new()
	_holo_mat.shader = HoloShader
	_pad_mat = ShaderMaterial.new()
	_pad_mat.shader = HoloShader
	_pad_mat.set_shader_parameter("intensity", 1.0)
	_holo_root = Node3D.new()
	vp.add_child(_holo_root)
	# Positioned and scaled per weapon in _build_hologram().
	_holo_model = Node3D.new()
	_holo_root.add_child(_holo_model)
	# A projector pad the hologram hovers over.
	var pad := TorusMesh.new()
	pad.inner_radius = 1.5
	pad.outer_radius = 1.6
	pad.rings = 32
	pad.ring_segments = 6
	var pad_mi := MeshInstance3D.new()
	pad_mi.mesh = pad
	pad_mi.material_override = _pad_mat
	pad_mi.position = Vector3(0, -0.9, 0)
	vp.add_child(pad_mi)

	_name = UIStyle.label("", 18, Color.WHITE, true)
	box.add_child(_name)
	_tag = UIStyle.label("", 10, UIStyle.TEXT_DIM)
	box.add_child(_tag)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 4)
	box.add_child(gap)
	for i in WeaponInfo.count():
		var row := UIStyle.label("", 12, UIStyle.TEXT_DIM)
		box.add_child(row)
		_rows.append(row)
	_hint = UIStyle.label("", 10, UIStyle.TEXT_DIM)
	box.add_child(_hint)
