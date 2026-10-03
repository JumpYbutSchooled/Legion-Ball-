extends StaticBody3D
## CRYSTAL WALL: a slab of crystal that rises out of the ground, solid for everyone
## (every computer builds the same one), blocking shots and players for `lifetime`
## seconds, then crumbles. `facing` is the direction it faces (flat). Looks like an
## orange PLASMA NET: glowing, flickering hexagon outlines over a faint orange pane.

const PlasmaNet := preload("res://scripts/weapons/plasma_net_node.gd")
const ORANGE := Color(1.0, 0.48, 0.1)
const HEX := 1.1

var manager: Node
var visual_only := false
var lifetime := 5.0
var facing := Vector3.FORWARD
var color := Color(0.6, 0.45, 0.35)
var width := 30.0
var height := 14.0
## Panel thickness (was 0.8; the editing doc asked for it thin).
var thickness := 0.22

var _t := 0.0
var _visual: Node3D
var _lines_mat: StandardMaterial3D


func _ready() -> void:
	top_level = true
	var flat := Vector3(facing.x, 0.0, facing.z)
	if flat.length() < 0.01:
		flat = Vector3.FORWARD
	global_basis = Basis.looking_at(flat.normalized(), Vector3.UP)
	_visual = Node3D.new()
	add_child(_visual)
	# The hexagons, like the Plasma Net's (additive, so they glow), in orange.
	_lines_mat = _glow_material(Color(ORANGE * 1.2, 0.9))
	var half := Vector2(width, height) * 0.5
	var lines := MeshInstance3D.new()
	lines.mesh = PlasmaNet.hex_mesh(half, HEX, func(c: Vector2) -> bool:
		return absf(c.x) <= half.x - HEX * 0.9 and absf(c.y) <= half.y - HEX)
	lines.material_override = _lines_mat
	lines.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_visual.add_child(lines)
	# A faint pane behind them, so you can see it's solid.
	var pane := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(width, height, thickness)
	pane.mesh = box
	pane.material_override = _glow_material(Color(ORANGE * 0.5, 0.35))
	pane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_visual.add_child(pane)
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = box.size
	shape.shape = box_shape
	add_child(shape)
	var sfx := get_tree().root.get_node_or_null("Sfx")
	if sfx:
		sfx.call("play", "shield", global_position, 0.0, 0.6)


func _glow_material(c: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = c
	return mat


func _process(delta: float) -> void:
	_t += delta
	# Rises out of the ground, sinks back at the end; flickers like the net.
	var up := minf(_t / 0.25, 1.0) * clampf((lifetime - _t) / 0.3, 0.0, 1.0)
	_visual.scale = Vector3(1.0, maxf(up, 0.02), 1.0)
	_visual.position = Vector3(0.0, -height * 0.5 * (1.0 - up), 0.0)
	_lines_mat.albedo_color = Color(ORANGE * (1.05 + 0.3 * sin(_t * 9.0)), 0.85)
	if _t >= lifetime:
		queue_free()
