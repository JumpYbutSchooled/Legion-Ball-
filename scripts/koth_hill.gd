extends Node3D
## King of the Hill's hill (arena.gd _zzzhill): a glowing gold ring on the ground with a
## see-through column of light, so it can be spotted from across the map. Brighter while
## the local player is standing in it.

const GOLD := Color(1.0, 0.78, 0.25)

var radius := 10.0

var _ring_mat: StandardMaterial3D
var _column_mat: StandardMaterial3D
var _t := 0.0


func _ready() -> void:
	var torus := TorusMesh.new()
	torus.inner_radius = radius - 0.35
	torus.outer_radius = radius
	torus.rings = 64
	torus.ring_segments = 8
	_ring_mat = StandardMaterial3D.new()
	_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_mat.albedo_color = GOLD * 3.0
	var ring := MeshInstance3D.new()
	ring.mesh = torus
	ring.material_override = _ring_mat
	ring.position.y = 0.15
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)

	var column := CylinderMesh.new()
	column.top_radius = radius
	column.bottom_radius = radius
	column.height = 40.0
	column.radial_segments = 48
	column.cap_top = false
	column.cap_bottom = false
	_column_mat = StandardMaterial3D.new()
	_column_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_column_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_column_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_column_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_column_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_column_mat.albedo_texture = _fade_texture()
	_column_mat.albedo_color = Color(GOLD, 0.12)
	var col := MeshInstance3D.new()
	col.mesh = column
	col.material_override = _column_mat
	col.position.y = 20.0
	col.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(col)

	var light := OmniLight3D.new()
	light.light_color = GOLD
	light.light_energy = 1.0
	light.omni_range = radius * 1.5
	light.position.y = 2.0
	add_child(light)


## Bright at the bottom, gone at the top (the cylinder's V runs top to bottom).
func _fade_texture() -> GradientTexture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.7, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0.25), Color(1, 1, 1, 1)])
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill_from = Vector2(0, 0)
	tex.fill_to = Vector2(0, 1)
	tex.width = 4
	tex.height = 64
	return tex


func _process(delta: float) -> void:
	_t += delta
	var arena := get_parent()
	var inside: bool = arena.call("on_hill", multiplayer.get_unique_id()) if arena and arena.has_method("on_hill") else false
	var pulse := 0.5 + 0.5 * sin(_t * (6.0 if inside else 2.5))
	_ring_mat.albedo_color = GOLD * (3.0 + pulse * (3.0 if inside else 1.0))
	# Faint from inside, or it would wash the whole view out.
	_column_mat.albedo_color = Color(GOLD, (0.05 if inside else 0.14) + pulse * 0.04)
