@tool
extends MeshInstance3D
## Half of a Halo 2 style energy sword: one crescent blade that starts behind the ball,
## wraps round its side in a semicircle, then sweeps forward to a point.
## Built in local space with the ball at the origin and forward = -Z.
## Solid low-poly body: a polygonal cross-section swept along the curve, flat-shaded
## so every face reads as its own polygon.

const BladeShader := preload("res://shaders/blade_warp.gdshader")

## 1 = right side of the ball, -1 = mirrored onto the left.
@export var side := 1.0:
	set(value):
		side = value
		_rebuild()
@export var arc_radius := 0.85:
	set(value):
		arc_radius = value
		_rebuild()
## Angles measured from straight ahead, clockwise seen from above (90 = right side, 180 = behind).
@export var arc_start_deg := 180.0:
	set(value):
		arc_start_deg = value
		_rebuild()
@export var arc_end_deg := 60.0:
	set(value):
		arc_end_deg = value
		_rebuild()
## Tip position for the right-side blade; mirrored automatically for the left.
@export var tip := Vector3(0.25, 0.0, -3.2):
	set(value):
		tip = value
		_rebuild()
@export var max_width := 0.26:
	set(value):
		max_width = value
		_rebuild()
@export var max_thickness := 0.2:
	set(value):
		max_thickness = value
		_rebuild()
## Sides of the cross-section polygon.
@export_range(3, 12) var cross_sides := 4:
	set(value):
		cross_sides = value
		_rebuild()
## Low counts give a faceted, geometric blade.
@export_range(4, 256) var segments := 9:
	set(value):
		segments = value
		_rebuild()
## Random roughness on every vertex (fraction of the local size), for a chipped crystal look.
@export_range(0.0, 0.6) var jag := 0.3:
	set(value):
		jag = value
		_rebuild()
## Seed for the jag, so each blade is chipped differently but consistently.
@export var jag_seed := 1:
	set(value):
		jag_seed = value
		_rebuild()


func _ready() -> void:
	_rebuild()
	# So impact frames can include it in their shading (impact_frames.gd).
	add_to_group("impact_blades")


## Tip position in this blade's local space, with mirroring applied.
func get_tip() -> Vector3:
	return Vector3(tip.x * side, tip.y, tip.z)


func _rebuild() -> void:
	if not is_inside_tree():
		return
	var path := _build_path()

	# Normalized length along the path, for the width/thickness profile.
	var along := PackedFloat32Array([0.0])
	for i in range(1, path.size()):
		along.append(along[i - 1] + path[i].distance_to(path[i - 1]))
	var total := along[along.size() - 1]

	# Polygon cross-section rings along the path.
	var rng := RandomNumberGenerator.new()
	rng.seed = jag_seed
	var rings: Array[PackedVector3Array] = []
	for i in path.size():
		var prev := path[maxi(i - 1, 0)]
		var next := path[mini(i + 1, path.size() - 1)]
		var tangent := (next - prev).normalized()
		var outward := tangent.cross(Vector3.UP).normalized()
		var u := along[i] / total
		# Pointed at both ends, widest through the curve, long taper to the tip.
		var profile := smoothstep(0.0, 0.3, u) * pow(1.0 - smoothstep(0.45, 1.0, u), 0.8)
		var half_w := max_width * 0.5 * profile
		var half_t := max_thickness * 0.5 * profile
		var ring := PackedVector3Array()
		for k in cross_sides:
			var ang := k * TAU / cross_sides
			var rough := 1.0 + rng.randf_range(-jag, jag)
			ring.append(path[i] + (outward * cos(ang) * half_w + Vector3.UP * sin(ang) * half_t) * rough)
		rings.append(ring)

	# Every triangle gets its own flat normal so the blade reads as hard facets.
	# UV.x holds how far along the blade the segment is (0 = back point, 1 = tip);
	# the shader uses it for the holster/draw wave.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in path.size() - 1:
		var mid := (path[i] + path[i + 1]) * 0.5
		var seg_u := (along[i] + along[i + 1]) * 0.5 / total
		for k in cross_sides:
			var a := rings[i][k]
			var b := rings[i][(k + 1) % cross_sides]
			var c := rings[i + 1][(k + 1) % cross_sides]
			var d := rings[i + 1][k]
			_add_facet(st, a, b, c, mid, seg_u)
			_add_facet(st, a, c, d, mid, seg_u)

	mesh = st.commit()
	var mat := ShaderMaterial.new()
	mat.shader = BladeShader
	material_override = mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _add_facet(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, inside: Vector3, along_u: float) -> void:
	var n := (b - a).cross(c - a)
	if n.length_squared() < 1e-12:
		return  # Collapsed at the pointed ends.
	n = n.normalized()
	if n.dot((a + b + c) / 3.0 - inside) < 0.0:
		n = -n
	st.set_normal(n)
	st.set_uv(Vector2(along_u, 0.0))
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)


func _build_path() -> PackedVector3Array:
	var mirror := Vector3(side, 1.0, 1.0)
	var pts := PackedVector3Array()
	var arc_steps := segments / 2
	# Semicircle round the ball's side.
	for i in arc_steps:
		var a := deg_to_rad(lerpf(arc_start_deg, arc_end_deg, float(i) / arc_steps))
		pts.append(Vector3(sin(a), 0.0, -cos(a)) * arc_radius * mirror)

	# Then a smooth quadratic curve forward to the tip, leaving the arc tangentially
	# but bending toward straight ahead.
	var a_end := deg_to_rad(arc_end_deg)
	var p0 := Vector3(sin(a_end), 0.0, -cos(a_end)) * arc_radius * mirror
	var arc_tangent := Vector3(-cos(a_end), 0.0, -sin(a_end)) * mirror
	var bend := (arc_tangent * 0.4 + Vector3.FORWARD * 0.6).normalized()
	var end := get_tip()
	var p1 := p0 + bend * p0.distance_to(end) * 0.45
	var curve_steps := segments - arc_steps
	for i in curve_steps + 1:
		var t := float(i) / curve_steps
		pts.append(p0.lerp(p1, t).lerp(p1.lerp(end, t), t))
	return pts
