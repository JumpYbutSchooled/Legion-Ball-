extends Node3D
## HUNTER'S SIGIL tag: a spinning red sigil and a beam of light over a tagged target,
## drawn through walls, for `lifetime` seconds. Only the tagger sees it (it's added on
## their computer only, as a child of the target).

var lifetime := 6.0
var color := Color(1.0, 0.12, 0.18)

var _t := 0.0
var _ring: MeshInstance3D


func _ready() -> void:
	# The minimap (ui/minimap.gd) draws every tag, walls or not.
	add_to_group("sigil_marks")
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(color.r * 2.0, color.g * 2.0, color.b * 2.0, 0.9)
	mat.render_priority = 10
	_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 1.0
	torus.outer_radius = 1.2
	torus.ring_segments = 4
	_ring.mesh = torus
	_ring.material_override = mat
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)
	var beam := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.05
	cyl.bottom_radius = 0.15
	cyl.height = 30.0
	beam.mesh = cyl
	var beam_mat := mat.duplicate() as StandardMaterial3D
	beam_mat.albedo_color = Color(color, 0.35)
	beam.material_override = beam_mat
	beam.position = Vector3(0, 15.0, 0)
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(beam)


func _process(delta: float) -> void:
	_t += delta
	if _t >= lifetime:
		queue_free()
		return
	top_level = true
	var parent := get_parent() as Node3D
	if parent:
		global_position = parent.global_position
	_ring.rotation = Vector3(PI / 2.0 * 0.3, _t * 4.0, 0.0)
	visible = parent == null or parent.visible
