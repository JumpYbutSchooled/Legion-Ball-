extends CanvasLayer
## Mouse-wheel weapon browser. Scrolling slides a small panel in from the left, in the
## same style as the rest of the UI (dark glass, thin cyan border, "// ARMAMENT" header,
## bracketed names): a ring of weapon slots (the one you've scrolled to lit in its colour,
## a dot on the equipped one) round a spinning hologram of that weapon, with its name
## below. Right-click equips it; it hides after a few idle seconds. Ctrl + wheel is left
## alone (camera zoom). Controller: LB / RB step to the previous / next weapon and equip
## it straight away. Staff weapons only appear if unlocked (and not hidden with 0).

const UIStyle := preload("res://scripts/ui/ui_style.gd")
const WeaponInfo := preload("res://scripts/weapon_info.gd")
const HoloShader := preload("res://shaders/hologram.gdshader")
const InputSetup := preload("res://scripts/input_setup.gd")
const Sfx := preload("res://scripts/sfx.gd")

## The weapon manager (Ball/Weapon).
@export var weapon: Node
@export var idle_hide_time := 3.0
## Size of the whole wheel (and the text under it).
@export var panel_width := 200.0
## Distance from the left edge of the screen when shown.
@export var margin := 20.0
## Overall opacity when fully shown.
@export var opacity := 0.85

const OUTER := 86.0
const INNER := 56.0

var _open := false
var _candidate := 0
var _idle := 0.0
var _slide := 0.0  # 0 hidden .. 1 shown
var _confirm_flash := 0.0

var _panel: Control
var _ring: Control
var _name: Label
var _tag: Label
var _hint: Label
var _slot_label: Label
var _spin := 0.0
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
	_panel.modulate.a = 0.0
	if weapon and weapon.has_signal("staff_weapons_toggled"):
		weapon.connect("staff_weapons_toggled", _on_staff_weapons_toggled)


## Key 0: pop the wheel open so you can see the staff weapons appear or vanish.
func _on_staff_weapons_toggled(shown: bool) -> void:
	_open = true
	_candidate = weapon.get("current")
	_idle = 0.0
	_refresh()
	_hint.text = "STAFF WEAPONS SHOWN  (0)" if shown else "STAFF WEAPONS HIDDEN  (0)"


func _unhandled_input(event: InputEvent) -> void:
	if not weapon or get_tree().paused:
		return
	# Controller shoulders: step and equip in one press.
	for dir in [["weapon_prev", -1], ["weapon_next", 1]]:
		if event.is_action_pressed(dir[0]) and not _input_blocked():
			_browse(dir[1])
			_confirm()
			get_viewport().set_input_as_handled()
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
				_confirm()
				get_viewport().set_input_as_handled()


func _confirm() -> void:
	weapon.call("select", _candidate)
	_confirm_flash = 1.0
	_idle = idle_hide_time - 0.5  # Close shortly after confirming.
	_refresh()
	Sfx.play_flat(get_tree(), "ui_click", -12.0)


func _input_blocked() -> bool:
	var net := get_tree().root.get_node_or_null("Net")
	return net != null and net.get("input_blocked")


func _browse(step: int) -> void:
	var total := WeaponInfo.unlocked_count(get_tree())
	if not _open:
		_open = true
		_candidate = weapon.get("current")
	_candidate = (_candidate + step + total) % total
	_idle = 0.0
	_refresh()
	Sfx.play_flat(get_tree(), "ui_hover", -16.0)


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
	var x := lerpf(-_panel.size.x - 20.0, margin, eased)
	_panel.position = Vector2(x, (view.y - _panel.size.y) / 2.0)
	_panel.modulate.a = eased * opacity
	_panel.visible = _slide > 0.001
	_confirm_flash = move_toward(_confirm_flash, 0.0, delta * 3.0)
	_spin += delta * 0.4
	if _panel.visible:
		_ring.queue_redraw()
		if _holo_root:
			_holo_root.rotate_y(delta * 1.1)
			_holo_mat.set_shader_parameter("intensity", 1.4 + _confirm_flash * 4.0)


func _refresh() -> void:
	var info: Dictionary = weapon.call("slot_info", _candidate)
	var color: Color = info["color"]
	_name.text = "[ %s ]" % info["name"]
	_name.add_theme_color_override("font_color", color)
	_tag.text = info["tag"]
	_slot_label.text = "%02d/%02d" % [_candidate + 1, _count()]
	var equipped: int = weapon.get("current")
	if _candidate == equipped:
		_hint.text = "// EQUIPPED"
		_hint.add_theme_color_override("font_color", UIStyle.ACCENT)
	else:
		_hint.text = "LB/RB  //  EQUIP" if InputSetup.using_pad else "RMB  //  EQUIP"
		_hint.add_theme_color_override("font_color", UIStyle.TEXT_DIM)
	_holo_mat.set_shader_parameter("color", color)
	_pad_mat.set_shader_parameter("color", color)
	_build_hologram(_candidate)


func _count() -> int:
	return maxi(WeaponInfo.unlocked_count(get_tree()), 1)


## The wheel: a slowly turning tick ring, one thin segment per slot with its number (the
## scrolled-to one lit in its colour), a dot on the equipped one, and corner brackets.
func _draw_ring() -> void:
	var center := _ring.size / 2.0
	var n := _count()
	var step := TAU / n
	var gap := 0.06
	var equipped: int = weapon.get("current") if weapon else 0
	# Tick ring round the outside, turning slowly; every sixth tick longer.
	for k in 60:
		var a := TAU * k / 60.0 + _spin
		var long := k % 6 == 0
		var from := center + Vector2.from_angle(a) * (OUTER + 5.0)
		var to := center + Vector2.from_angle(a) * (OUTER + (10.0 if long else 7.0))
		_ring.draw_line(from, to, Color(UIStyle.ACCENT, 0.5 if long else 0.2), 1.0)
	_ring.draw_arc(center, INNER - 2.0, 0.0, TAU, 48, UIStyle.ACCENT_DIM, 1.0, true)
	# Corner brackets, as on the menu panels.
	var half := _ring.size.x / 2.0 - 2.0
	var arm := 12.0
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			var c := center + Vector2(sx, sy) * half
			_ring.draw_line(c, c - Vector2(sx * arm, 0), UIStyle.ACCENT, 1.5)
			_ring.draw_line(c, c - Vector2(0, sy * arm), UIStyle.ACCENT, 1.5)
	for i in n:
		var info: Dictionary = weapon.call("slot_info", i)
		var color: Color = info["color"]
		var mid := -PI / 2.0 + step * i
		var picked := i == _candidate
		var poly := PackedVector2Array()
		var segs := 10
		for k in segs + 1:
			poly.append(center + Vector2.from_angle(mid - step / 2.0 + gap + (step - gap * 2.0) * k / segs) * OUTER)
		for k in range(segs, -1, -1):
			poly.append(center + Vector2.from_angle(mid - step / 2.0 + gap + (step - gap * 2.0) * k / segs) * INNER)
		if picked:
			_ring.draw_colored_polygon(poly, Color(color, 0.28 + _confirm_flash * 0.3))
		poly.append(poly[0])
		_ring.draw_polyline(poly, Color(color, 0.9) if picked else Color(UIStyle.TEXT_DIM, 0.35), 1.5 if picked else 1.0, true)
		# Slot number in the segment.
		var text := str(i + 1)
		var pos := center + Vector2.from_angle(mid) * (INNER + OUTER) / 2.0
		var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		_ring.draw_string(_font, pos + Vector2(-w / 2.0, 4.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, color if picked else UIStyle.TEXT_DIM)
		if i == equipped:
			_ring.draw_circle(center + Vector2.from_angle(mid) * (OUTER - 7.0), 2.5, color)
		# Locked by the owner: a red slash across the segment.
		if weapon and not weapon.call("_slot_allowed", i):
			var a := center + Vector2.from_angle(mid - step * 0.3) * (INNER + 4.0)
			var b := center + Vector2.from_angle(mid + step * 0.3) * (OUTER - 4.0)
			_ring.draw_line(a, b, Color(1.0, 0.25, 0.25, 0.9), 2.0, true)


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

	# Dark glass panel with a thin cyan border, like the minimap and menus.
	_panel = PanelContainer.new()
	var box := UIStyle.panel_box(UIStyle.ACCENT_DIM, Color(0.02, 0.05, 0.08, 0.6))
	box.set_content_margin_all(10)
	_panel.add_theme_stylebox_override("panel", box)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_panel)
	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(panel_width, 0)
	column.add_theme_constant_override("separation", 3)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(column)

	var header := HBoxContainer.new()
	column.add_child(header)
	var title := UIStyle.label("// ARMAMENT", 10, UIStyle.ACCENT, true)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_slot_label = UIStyle.label("", 10, UIStyle.TEXT_DIM)
	header.add_child(_slot_label)

	# The wheel, with the hologram stage in its middle.
	_ring = Control.new()
	_ring.custom_minimum_size = Vector2(panel_width, panel_width)
	_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ring.draw.connect(_draw_ring)
	column.add_child(_ring)
	var holder := SubViewportContainer.new()
	holder.stretch = true
	holder.size = Vector2(INNER * 2.0 - 8.0, INNER * 2.0 - 8.0)
	holder.position = Vector2(panel_width / 2.0 - INNER + 4.0, panel_width / 2.0 - INNER + 4.0)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ring.add_child(holder)
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

	_name = UIStyle.label("", 16, Color.WHITE, true)
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_name)
	_tag = UIStyle.label("", 10, UIStyle.TEXT_DIM)
	_tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tag.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_tag)
	var line := ColorRect.new()
	line.color = UIStyle.ACCENT_DIM
	line.custom_minimum_size = Vector2(0, 1)
	column.add_child(line)
	_hint = UIStyle.label("", 10, UIStyle.TEXT_DIM)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_hint)
