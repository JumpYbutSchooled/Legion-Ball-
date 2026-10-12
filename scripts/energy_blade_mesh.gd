@tool
extends MeshInstance3D
## Half of a Halo 2 style energy sword: one crescent blade that starts behind the ball,
## wraps round its side in a semicircle, then sweeps forward to a point.
## Built in local space with the ball at the origin and forward = -Z.
## Solid low-poly body: a polygonal cross-section swept along the curve. It's drawn as
## pentagons spread over that body (weapons/pentagon_skin.gd, shaders/pentagon_blade.gdshader)
## rather than the body itself.

const BladeShader := preload("res://shaders/blade_warp.gdshader")
const PentagonShader := preload("res://shaders/pentagon_blade.gdshader")
const PentagonSkin := preload("res://scripts/weapons/pentagon_skin.gd")
## Drawn as pentagons rather than its solid body. The body is then built clean (no jag)
## for the right-hand side only, and a left-hand blade wears the mirror image of its
## pentagons, so the two sides match exactly.
const PENTAGONS := true

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
## Random roughness on every vertex (fraction of the local size), for a chipped crystal look
## (not used when it's drawn as pentagons).
@export_range(0.0, 0.6) var jag := 0.3:
	set(value):
		jag = value
		_rebuild()
## Size of the whole blade (arc, tip, width, thickness). Every weapon's blades use the
## same scale (blade_weapon.gd BLADE_SCALE).
@export var scale_factor := 1.0:
	set(value):
		scale_factor = value
		_rebuild()
## The ball's radius plus a gap: no part of a blade comes closer to the ball's centre
## than this (plus half the blade's own width), so blades wrap AROUND the ball, never
## through it.
const BALL_CLEAR := 0.56
## The arc round the ball is pulled in this much tighter than its written radius, so
## blades hug the ball (the clearance still keeps them outside it).
const ARC_TIGHT := 0.8
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
	return _tip_for(side)


## The tip for a blade on side `s` (1 right, -1 left).
func _tip_for(s: float) -> Vector3:
	var p := Vector3(tip.x * s, tip.y, tip.z) * scale_factor
	var clear := _clearance()
	if p.length() < clear:
		p = (p.normalized() if p.length() > 0.001 else Vector3.FORWARD) * clear
	return p


## How far every point of the blade's centre line stays from the ball's centre.
func _clearance() -> float:
	# Half the blade's width, plus the chipping (jag) that can push a surface out further.
	return BALL_CLEAR + maxf(max_width, max_thickness) * scale_factor * 0.5 * (1.0 + jag)


func _rebuild() -> void:
	if not is_inside_tree():
		return
	var shape := _shape()
	var path: PackedVector3Array = shape[0]
	var rings: Array = shape[1]
	var half_ws: PackedFloat32Array = shape[2]
	var along: PackedFloat32Array = shape[3]
	var total := along[along.size() - 1]
	var mat := ShaderMaterial.new()
	if PENTAGONS and DisplayServer.get_name() != "headless":
		var key := _shape_key()
		var skin: ArrayMesh = PentagonSkin.skin(path, rings, key)
		mesh = skin if side >= 0.0 else PentagonSkin.mirrored(skin, key)
		mat.shader = PentagonShader
		material_override = mat
		cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		return

	# Every triangle gets its own flat normal so the blade reads as hard facets.
	# UV.x holds how far along the blade the segment is (0 = back point, 1 = tip); UV2.y how
	# far across (-1 / 1 at its two side edges); CUSTOM0 the facet's normal and the width.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_custom_format(0, SurfaceTool.CUSTOM_RGBA_FLOAT)
	for i in path.size() - 1:
		var mid := (path[i] + path[i + 1]) * 0.5
		var seg_u := (along[i] + along[i + 1]) * 0.5 / total
		var width := (half_ws[i] + half_ws[i + 1])
		for k in cross_sides:
			var k1 := (k + 1) % cross_sides
			var ca := cos(k * TAU / cross_sides)
			var cb := cos(k1 * TAU / cross_sides)
			var a: Vector3 = rings[i][k]
			var b: Vector3 = rings[i][k1]
			var c: Vector3 = rings[i + 1][k1]
			var d: Vector3 = rings[i + 1][k]
			_add_facet(st, [a, b, c], [ca, cb, cb], mid, seg_u, width)
			_add_facet(st, [a, c, d], [ca, cb, ca], mid, seg_u, width)
	mesh = st.commit()
	mat.shader = BladeShader
	material_override = mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## The blade's shape (no scene tree needed, so the pentagons can be worked out ahead of
## time on another thread, skin_warmup.gd): [path, cross-section rings, half widths, metres
## along]. Drawn as pentagons it's the right-hand shape (the left wears its mirror image).
func _shape() -> Array:
	var path := _build_path(1.0 if PENTAGONS else side)
	var along := PackedFloat32Array([0.0])
	for i in range(1, path.size()):
		along.append(along[i - 1] + path[i].distance_to(path[i - 1]))
	var total := along[along.size() - 1]
	# Polygon cross-section rings along the path.
	var rng := RandomNumberGenerator.new()
	rng.seed = jag_seed
	var rings: Array = []
	var half_ws := PackedFloat32Array()
	for i in path.size():
		var prev := path[maxi(i - 1, 0)]
		var next := path[mini(i + 1, path.size() - 1)]
		var tangent := (next - prev).normalized()
		var outward := tangent.cross(Vector3.UP).normalized()
		var u := along[i] / total
		# Pointed at both ends, widest through the curve, long taper to the tip.
		var profile := smoothstep(0.0, 0.3, u) * pow(1.0 - smoothstep(0.45, 1.0, u), 0.8)
		var half_w := max_width * scale_factor * 0.5 * profile
		var half_t := max_thickness * scale_factor * 0.5 * profile
		var ring := PackedVector3Array()
		for k in cross_sides:
			var ang := k * TAU / cross_sides
			var rough := 1.0 if PENTAGONS else 1.0 + rng.randf_range(-jag, jag)
			ring.append(path[i] + (outward * cos(ang) * half_w + Vector3.UP * sin(ang) * half_t) * rough)
		rings.append(ring)
		half_ws.append(half_w)
	return [path, rings, half_ws, along]


## For skin_warmup.gd: [key, path, rings], to work this blade's pentagons out ahead of time.
func pentagon_job() -> Array:
	var shape := _shape()
	return [_shape_key(), shape[0], shape[1]]

func _add_facet(st: SurfaceTool, pts: Array, across: Array, inside: Vector3, along_u: float, width: float) -> void:
	var a: Vector3 = pts[0]
	var b: Vector3 = pts[1]
	var c: Vector3 = pts[2]
	var n := (b - a).cross(c - a)
	if n.length_squared() < 1e-12:
		return  # Collapsed at the pointed ends.
	n = n.normalized()
	if n.dot((a + b + c) / 3.0 - inside) < 0.0:
		n = -n
	for v in 3:
		st.set_normal(n)
		st.set_custom(0, Color(n.x, n.y, n.z, width))
		st.set_uv(Vector2(along_u, 0.0))
		st.set_uv2(Vector2(0.0, across[v]))
		st.add_vertex(pts[v])


## Everything that makes this blade's shape what it is (but not its side: the left one is
## the right one's mirror image).
func _shape_key() -> String:
	return var_to_str([arc_radius, arc_start_deg, arc_end_deg, tip, max_width, max_thickness, cross_sides, segments, scale_factor, jag])


func _build_path(s: float) -> PackedVector3Array:
	var mirror := Vector3(s, 1.0, 1.0)
	var pts := PackedVector3Array()
	var arc_steps := segments / 2
	var radius := arc_radius * scale_factor * ARC_TIGHT
	# Semicircle round the ball's side.
	for i in arc_steps:
		var a := deg_to_rad(lerpf(arc_start_deg, arc_end_deg, float(i) / arc_steps))
		pts.append(Vector3(sin(a), 0.0, -cos(a)) * radius * mirror)

	# Then a smooth quadratic curve forward to the tip, leaving the arc tangentially
	# but bending toward straight ahead.
	var a_end := deg_to_rad(arc_end_deg)
	var p0 := Vector3(sin(a_end), 0.0, -cos(a_end)) * radius * mirror
	var arc_tangent := Vector3(-cos(a_end), 0.0, -sin(a_end)) * mirror
	var bend := (arc_tangent * 0.4 + Vector3.FORWARD * 0.6).normalized()
	var end := _tip_for(s)
	var p1 := p0 + bend * p0.distance_to(end) * 0.45
	var curve_steps := segments - arc_steps
	for i in curve_steps + 1:
		var t := float(i) / curve_steps
		pts.append(p0.lerp(p1, t).lerp(p1.lerp(end, t), t))
	# Around the ball, never through it: anything inside the clearance is pushed out onto
	# it, so a blade that would cut across the ball hugs its surface instead.
	var clear := _clearance()
	for i in pts.size():
		var p := pts[i]
		if p.length() < clear:
			var out := p.normalized() if p.length() > 0.001 else Vector3(s, 0.0, 0.0)
			pts[i] = out * clear
	return pts
