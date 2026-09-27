extends Node3D
## PLASMA NET: a big disc of glowing hexagons hanging in mid-air, facing whoever fired it.
## Any other player (or target) that touches it is stunned for STUN seconds, once per net
## (the owner's copy watches and applies it). Gone after `lifetime` seconds.

const STUN := 4.0
## How far out the net reaches, and how close to its plane counts as touching.
const RADIUS := 9.0
const THICKNESS := 1.6
const HEX := 1.1

var manager: Node
var visual_only := false
var lifetime := 20.0
var facing := Vector3.FORWARD
var color := Color(0.3, 1.0, 0.9)

var _t := 0.0
var _caught := {}
var _mat: StandardMaterial3D


func _ready() -> void:
	top_level = true
	if facing.length() > 0.01:
		look_at(global_position + facing, Vector3.UP if absf(facing.normalized().y) < 0.95 else Vector3.RIGHT)
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat.albedo_color = Color(color * 2.0, 0.9)
	var mesh := MeshInstance3D.new()
	mesh.mesh = _hex_mesh()
	mesh.material_override = _mat
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh)
	scale = Vector3.ONE * 0.05


## Every hexagon's outline in the disc, as thin quads (one mesh).
func _hex_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var w := HEX * sqrt(3.0)
	var rows := int(RADIUS / (HEX * 1.5)) + 1
	var cols := int(RADIUS / w) + 1
	for r in range(-rows, rows + 1):
		for c in range(-cols, cols + 1):
			var center := Vector2(c * w + (w * 0.5 if r % 2 != 0 else 0.0), r * HEX * 1.5)
			if center.length() > RADIUS - HEX * 0.5:
				continue
			for k in 6:
				var a0 := TAU * k / 6.0 + PI / 6.0
				var a1 := TAU * (k + 1) / 6.0 + PI / 6.0
				_edge(st, center + Vector2(cos(a0), sin(a0)) * HEX, center + Vector2(cos(a1), sin(a1)) * HEX)
	return st.commit()


func _edge(st: SurfaceTool, a: Vector2, b: Vector2) -> void:
	var along := (b - a).normalized()
	var side := Vector2(-along.y, along.x) * 0.06
	var p := [a + side, b + side, b - side, a - side]
	for i in [0, 1, 2, 0, 2, 3]:
		st.add_vertex(Vector3(p[i].x, p[i].y, 0.0))


func _physics_process(delta: float) -> void:
	_t += delta
	# Unfolds fast, flickers, fades out over its last second.
	scale = Vector3.ONE * minf(0.05 + _t * 5.0, 1.0)
	var fade := clampf(lifetime - _t, 0.0, 1.0)
	_mat.albedo_color = Color(color * (1.6 + 0.5 * sin(_t * 9.0)), 0.85 * fade)
	if _t >= lifetime:
		queue_free()
		return
	if visual_only or not manager:
		return
	var normal := global_basis.z
	for t in get_tree().get_nodes_in_group("lock_targets"):
		if _caught.has(t) or not t.call("is_alive"):
			continue
		var d: Vector3 = (t.call("get_aim_point") as Vector3) - global_position
		var off_plane := absf(d.dot(normal))
		if off_plane > THICKNESS or (d - normal * d.dot(normal)).length() > RADIUS:
			continue
		_caught[t] = true
		if t.has_method("stagger"):
			t.call("stagger", STUN)
		manager.call("spawn_light", t.call("get_aim_point"), 40.0, 8.0, 0.3, color)
		manager.call("play_sound", "zap", global_position, 0.0)
