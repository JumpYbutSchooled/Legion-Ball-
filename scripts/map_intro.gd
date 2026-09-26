extends Node
## The map loading in as a simulation: when an arena starts, every piece of the level is
## swapped for a blue wireframe (shaders/build_wire.gdshader). The base traces in across
## the floor, then the buildings and ramps grow up out of it with a ticking,
## rising whine, it charges, and the whole thing detonates into the real, solid map with
## a white flash and a boom, and the players drop in.
## Added by the arena for the local player (never on the dedicated server). Purely visual
## and local: the host just keeps everyone spawn-protected for its length (arena.gd).
## Jump or fire skips to the end. Settings "map_intro" turns it off.

const WireShader := preload("res://shaders/build_wire.gdshader")
const Sfx := preload("res://scripts/sfx.gd")

## Seconds for each stage.
const TRACE := 0.6
const GROW := 2.4
const CHARGE := 0.45
## Total, for the arena's spawn protection.
const LENGTH := TRACE + GROW + CHARGE

var map: Node3D
## Hidden until the map detonates in (the players, the turrets).
var hidden: Array[Node3D] = []

var _mat: ShaderMaterial
## [instance, its own material_override], to put back.
var _pieces: Array = []
var _top := 10.0
var _t := 0.0
var _tick := 0.0
var _done := false
var _flash: ColorRect


func _ready() -> void:
	_mat = ShaderMaterial.new()
	_mat.shader = WireShader
	_mat.set_shader_parameter("reveal", -1.0)
	_collect(map)
	for piece in _pieces:
		var inst: GeometryInstance3D = piece[0]
		inst.material_override = _mat
		inst.set_instance_shader_parameter("box_size", piece[2])
	for node in hidden:
		node.visible = false
	_set_blocked(true)
	# The white flash when it all goes solid.
	var layer := CanvasLayer.new()
	layer.layer = 30
	add_child(layer)
	_flash = ColorRect.new()
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.color = Color(0.8, 0.95, 1.0, 0.0)
	layer.add_child(_flash)
	Sfx.play_flat(get_tree(), "ui_page", -4.0, 0.6)


func _collect(node: Node) -> void:
	for child in node.get_children():
		_collect(child)
	var size := Vector3.ZERO
	if node is CSGBox3D:
		size = (node as CSGBox3D).size
	elif node is MeshInstance3D and (node as MeshInstance3D).mesh is BoxMesh:
		size = ((node as MeshInstance3D).mesh as BoxMesh).size
	if size == Vector3.ZERO:
		return
	var inst := node as GeometryInstance3D
	_pieces.append([inst, inst.material_override, size])
	var top := (inst.global_transform * AABB(-size / 2.0, size)).end.y
	# Skip the sky-high boundary walls when judging how tall the level is.
	if top < 400.0:
		_top = maxf(_top, top)


func _process(delta: float) -> void:
	if _done:
		# Fade the flash, then go.
		_flash.color.a = move_toward(_flash.color.a, 0.0, delta * 2.0)
		if _flash.color.a <= 0.0:
			queue_free()
		return
	_t += delta
	if _t > 0.5 and (Input.is_action_just_pressed("jump") or Input.is_action_just_pressed("fire")):
		_t = LENGTH
	var reveal: float
	if _t < TRACE:
		# The base: a sliver above the floor.
		reveal = lerpf(-1.0, 0.6, _t / TRACE)
	elif _t < TRACE + GROW:
		var k := (_t - TRACE) / GROW
		reveal = lerpf(0.6, _top + 2.0, ease(k, 1.8))
		_tick -= delta
		if _tick <= 0.0:
			# Faster, higher ticks as it builds.
			_tick = lerpf(0.14, 0.05, k)
			Sfx.play_flat(get_tree(), "ui_hover", -12.0, lerpf(0.7, 1.8, k))
	else:
		reveal = _top + 2.0
		var k := clampf((_t - TRACE - GROW) / CHARGE, 0.0, 1.0)
		_mat.set_shader_parameter("intensity", lerpf(2.0, 7.0, k))
		if _tick > -1.0:
			_tick = -2.0
			Sfx.play_flat(get_tree(), "implode", -6.0)
	_mat.set_shader_parameter("reveal", reveal)
	if _t >= LENGTH:
		_detonate()


func _detonate() -> void:
	_done = true
	for piece in _pieces:
		if is_instance_valid(piece[0]):
			piece[0].material_override = piece[1]
	for node in hidden:
		if is_instance_valid(node):
			node.visible = true
	_set_blocked(false)
	_flash.color.a = 0.85
	Sfx.play_flat(get_tree(), "impact_boom", 0.0)
	var cam := get_viewport().get_camera_3d()
	if cam:
		var rig := cam.get_parent()
		while rig and not rig.has_method("add_shake"):
			rig = rig.get_parent()
		if rig:
			rig.call("add_shake", 0.9)


func _set_blocked(on: bool) -> void:
	var net := get_tree().root.get_node_or_null("Net")
	if net:
		net.set("input_blocked", on)


func _exit_tree() -> void:
	# Leaving mid-intro (quit to menu): never leave input blocked.
	if not _done:
		_set_blocked(false)
		for node in hidden:
			if is_instance_valid(node):
				node.visible = true
