extends CanvasLayer
## Radial weapon menu. Scrolling the mouse wheel opens a ring of weapons round the middle
## of the screen and steps round it; while it's open, moving the mouse points at a weapon
## (the camera holds still meanwhile). The weapon you're on spins as a hologram in the
## middle, with its name below. Right-click equips it; Esc, or a few idle seconds, closes
## it. Ctrl + wheel is left alone (camera zoom). Staff weapons only appear if unlocked
## (and not hidden with 0).

const UIStyle := preload("res://scripts/ui/ui_style.gd")
const WeaponInfo := preload("res://scripts/weapon_info.gd")
const HoloShader := preload("res://shaders/hologram.gdshader")

## The weapon manager (Ball/Weapon).
@export var weapon: Node
@export var idle_hide_time := 3.0
## Ring size in pixels.
@export var outer_radius := 210.0
@export var inner_radius := 120.0
## Overall opacity when fully shown.
@export var opacity := 0.9
## How far (pixels of mouse movement) the pointer has to go before it picks a weapon.
@export var pick_deadzone := 40.0

var _open := false
var _candidate := 0
var _idle := 0.0
var _show := 0.0  # 0 hidden .. 1 shown
var _confirm_flash := 0.0
## Where the mouse is pointing, relative to the ring's middle.
var _pointer := Vector2.ZERO
var _message := ""

var _root: Control
var _ring: Control
var _holo_holder: SubViewportContainer
var _name: Label
var _tag: Label
var _hint: Label
var _font: Font
var _holo_root: Node3D
var _holo_model: Node3D
var _holo_mat: ShaderMaterial
var _pad_mat: ShaderMaterial


func _ready() -> void:
	layer = 8
	# Keeps running while paused, just so it can tuck itself away.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_font = UIStyle.font(true)
	_build_ui()
	_root.modulate.a = 0.0
	_root.visible = false
	if weapon and weapon.has_signal("staff_weapons_toggled"):
		weapon.connect("staff_weapons_toggled", _on_staff_weapons_toggled)


## Key 0: pop the ring open so you can see the staff weapons appear or vanish.
func _on_staff_weapons_toggled(shown: bool) -> void:
	_open_ring()
	_message = "STAFF WEAPONS SHOWN" if shown else "STAFF WEAPONS HIDDEN"
	_refresh()


func _input(event: InputEvent) -> void:
	# While open, the mouse points at weapons instead of turning the camera.
	if not _open or get_tree().paused:
		return
	var motion := event as InputEventMouseMotion
	if motion:
		_pointer = (_pointer + motion.relative).limit_length(outer_radius)
		if _pointer.length() > pick_deadzone:
			var pick := _slot_at(_pointer.angle())
			if pick != _candidate:
				_candidate = pick
				_refresh()
			_idle = 0.0
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		_open = false
		get_viewport().set_input_as_handled()


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
				_idle = idle_hide_time - 0.4  # Close shortly after confirming.
				_refresh()
				get_viewport().set_input_as_handled()


func _open_ring() -> void:
	if not _open:
		_open = true
		_candidate = weapon.get("current")
		_pointer = Vector2.ZERO
	_idle = 0.0


## Wheel: step round the ring (down = clockwise).
func _browse(step: int) -> void:
	var total := WeaponInfo.unlocked_count(get_tree())
	_open_ring()
	_message = ""
	_candidate = (_candidate + step + total) % total
	# Point the mouse "pointer" at it too, so moving the mouse carries on from here.
	_pointer = Vector2.from_angle(_slot_angle(_candidate)) * (pick_deadzone + 1.0)
	_refresh()


func _count() -> int:
	return maxi(WeaponInfo.unlocked_count(get_tree()), 1)


## Slot 0 at the top, going clockwise.
func _slot_angle(slot: int) -> float:
	return -PI / 2.0 + TAU * float(slot) / _count()


func _slot_at(angle: float) -> int:
	var step := TAU / _count()
	return int(round(fposmod(angle + PI / 2.0, TAU) / step)) % _count()


func _process(delta: float) -> void:
	if get_tree().paused:
		_open = false
	if _open:
		_idle += delta
		if _idle >= idle_hide_time:
			_open = false
	_show = move_toward(_show, 1.0 if _open else 0.0, delta * 7.0)
	var eased := ease(_show, 0.4)
	_root.visible = _show > 0.001
	_root.modulate.a = eased * opacity
	# Pops open from slightly smaller, round the middle of the screen.
	var s := lerpf(0.85, 1.0, eased)
	_root.pivot_offset = _root.size / 2.0
	_root.scale = Vector2(s, s)
	_confirm_flash = move_toward(_confirm_flash, 0.0, delta * 3.0)
	if _root.visible:
		_ring.queue_redraw()
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
	if _message != "":
		_hint.text = _message
	else:
		_hint.text = "RIGHT-CLICK  equip" if _candidate != equipped else "equipped"
	_holo_mat.set_shader_parameter("color", color)
	_pad_mat.set_shader_parameter("color", color)
	_build_hologram(_candidate)


## The ring: one wedge per weapon, the pointed-at one lit in its colour, the equipped one
## marked with a dot, and the mouse pointer as a small tick on the inner edge.
func _draw_ring() -> void:
	var center := _ring.size / 2.0
	var n := _count()
	var step := TAU / n
	var gap := 0.04
	var equipped: int = weapon.get("current") if weapon else 0
	# A dark disc behind the hologram, so your own ball doesn't clutter it.
	_ring.draw_circle(center, inner_radius - 6.0, Color(0.02, 0.05, 0.08, 0.78))
	_ring.draw_arc(center, inner_radius - 6.0, 0.0, TAU, 64, Color(UIStyle.ACCENT, 0.25), 1.0, true)
	for i in n:
		var info := WeaponInfo.get_entry(i)
		var color: Color = info["color"]
		var mid := _slot_angle(i)
		var picked := i == _candidate
		var poly := PackedVector2Array()
		var segs := 12
		for k in segs + 1:
			poly.append(center + Vector2.from_angle(mid - step / 2.0 + gap + (step - gap * 2.0) * k / segs) * (outer_radius + (8.0 if picked else 0.0)))
		for k in range(segs, -1, -1):
			poly.append(center + Vector2.from_angle(mid - step / 2.0 + gap + (step - gap * 2.0) * k / segs) * inner_radius)
		var fill := Color(color, 0.32 + _confirm_flash * 0.3) if picked else Color(0.02, 0.05, 0.08, 0.66)
		_ring.draw_colored_polygon(poly, fill)
		poly.append(poly[0])
		_ring.draw_polyline(poly, Color(color, 0.95 if picked else 0.35), 2.0 if picked else 1.0, true)
		# Slot number and name in the middle of the wedge.
		var text_pos := center + Vector2.from_angle(mid) * (inner_radius + outer_radius) / 2.0
		var label := "%d  %s" % [i + 1, _short_name(info["name"])]
		var size := 13
		var width := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		_ring.draw_string(_font, text_pos + Vector2(-width / 2.0, 5.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color if picked else Color(UIStyle.TEXT, 0.8))
		if i == equipped:
			_ring.draw_circle(center + Vector2.from_angle(mid) * (outer_radius - 12.0), 4.0, color)
	# Pointer tick on the inner edge, where the mouse is aiming.
	if _pointer.length() > pick_deadzone:
		var dir := _pointer.normalized()
		_ring.draw_line(center + dir * (inner_radius - 14.0), center + dir * (inner_radius - 2.0), UIStyle.ACCENT, 3.0, true)


## Long names shortened to fit a wedge ("PILLARS OF GOD" -> "PILLARS").
func _short_name(full: String) -> String:
	var words := full.split(" ")
	return words[0] if words.size() > 2 else full


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
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = UIStyle.make_theme()
	add_child(_root)

	_ring = Control.new()
	_ring.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ring.draw.connect(_draw_ring)
	_root.add_child(_ring)

	# Hologram stage in the middle of the ring: its own little 3D world.
	_holo_holder = SubViewportContainer.new()
	_holo_holder.stretch = true
	_holo_holder.custom_minimum_size = Vector2(180, 150)
	_holo_holder.size = Vector2(180, 150)
	_holo_holder.set_anchors_preset(Control.PRESET_CENTER)
	_holo_holder.position = Vector2(-90, -85)
	_holo_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_holo_holder)
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_4X
	_holo_holder.add_child(vp)
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

	# Name, tag and hint just below the ring.
	var info := VBoxContainer.new()
	info.set_anchors_preset(Control.PRESET_CENTER)
	info.custom_minimum_size = Vector2(420, 0)
	info.position = Vector2(-210, outer_radius + 18.0)
	info.alignment = BoxContainer.ALIGNMENT_BEGIN
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(info)
	_name = UIStyle.label("", 22, Color.WHITE, true)
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.add_child(_name)
	_tag = UIStyle.label("", 11, UIStyle.TEXT_DIM)
	_tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.add_child(_tag)
	_hint = UIStyle.label("", 11, UIStyle.ACCENT)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.add_child(_hint)
