@tool
extends MeshInstance3D
## Builds a Goldberg polyhedron: hexagons plus the 12 pentagons needed to close a sphere.
## Made as the dual of a subdivided icosahedron, so `frequency` n gives
## 12 pentagons and 10 * (n^2 - 1) hexagons. Faces are flat-shaded; set `border` above 0
## to outline each one.

@export_range(1, 8) var frequency := 3:
	set(value):
		frequency = value
		_rebuild()
@export var radius := 0.5:
	set(value):
		radius = value
		_rebuild()
## Border width as a fraction of each face's size.
@export_range(0.0, 0.5) var border := 0.0:
	set(value):
		border = value
		_rebuild()
@export var hexagon_color := Color(0.2, 0.2, 0.22):
	set(value):
		hexagon_color = value
		_rebuild()
@export var pentagon_color := Color(0.2, 0.2, 0.22):
	set(value):
		pentagon_color = value
		_rebuild()
@export var border_color := Color(0.12, 0.12, 0.14):
	set(value):
		border_color = value
		_rebuild()


## [corners, normal] for every face, kept for build_shell_mesh().
var _faces: Array = []


func _ready() -> void:
	_rebuild()


## A copy of the faces for the block shield (scripts/shield.gd): every vertex carries its
## face's center in UV.xy + UV2.x, so the shader can move and grow whole faces.
func build_shell_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for face in _faces:
		var corners: Array[Vector3] = face[0]
		var normal: Vector3 = face[1]
		var center := Vector3.ZERO
		for c in corners:
			center += c
		center /= corners.size()
		for i in corners.size():
			var a := center
			var b := corners[i]
			var c := corners[(i + 1) % corners.size()]
			if (b - a).cross(c - a).dot(normal) > 0.0:
				var tmp := b
				b = c
				c = tmp
			for p in [a, b, c]:
				st.set_normal(normal)
				st.set_uv(Vector2(center.x, center.y))
				st.set_uv2(Vector2(center.z, 0.0))
				st.add_vertex(p)
	return st.commit()


func _rebuild() -> void:
	if not is_inside_tree():
		return

	var geo := _subdivided_icosahedron(frequency)
	var verts: PackedVector3Array = geo[0]
	var tris: Array[PackedInt32Array] = geo[1]

	# Triangles touching each vertex; their centroids become that vertex's face corners.
	var adjacent: Array[Array] = []
	for v in verts.size():
		adjacent.append([])
	for t in tris.size():
		for idx in tris[t]:
			adjacent[idx].append(t)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	_faces.clear()
	for v in verts.size():
		var n := verts[v]
		var corners: Array[Vector3] = []
		for t in adjacent[v]:
			var tri := tris[t]
			corners.append(((verts[tri[0]] + verts[tri[1]] + verts[tri[2]]) / 3.0).normalized() * radius)
		_sort_around(corners, n)
		var fill := pentagon_color if corners.size() == 5 else hexagon_color
		_add_face(st, corners, n, fill)
		_faces.append([corners, n])

	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = 0.4
	st.set_material(mat)
	mesh = st.commit()


func _add_face(st: SurfaceTool, corners: Array[Vector3], normal: Vector3, fill: Color) -> void:
	var center := Vector3.ZERO
	for c in corners:
		center += c
	center /= corners.size()

	var inner: Array[Vector3] = []
	for c in corners:
		inner.append(center + (c - center) * (1.0 - border))

	st.set_normal(normal)
	var count := corners.size()
	for i in count:
		var j := (i + 1) % count
		# Colored inner polygon as a fan.
		_add_tri(st, center, inner[i], inner[j], normal, fill)
		# Border strip between the outer and inner outlines.
		if border > 0.0:
			_add_tri(st, corners[i], corners[j], inner[j], normal, border_color)
			_add_tri(st, corners[i], inner[j], inner[i], normal, border_color)


func _add_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, normal: Vector3, color: Color) -> void:
	# Godot treats clockwise triangles as front-facing; flip if this one isn't.
	if (b - a).cross(c - a).dot(normal) > 0.0:
		var tmp := b
		b = c
		c = tmp
	st.set_color(color)
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)


func _sort_around(points: Array[Vector3], axis: Vector3) -> void:
	var tangent := axis.cross(Vector3.UP if absf(axis.y) < 0.9 else Vector3.RIGHT).normalized()
	var bitangent := axis.cross(tangent)
	points.sort_custom(func(p: Vector3, q: Vector3) -> bool:
		return atan2(p.dot(bitangent), p.dot(tangent)) < atan2(q.dot(bitangent), q.dot(tangent)))


## Returns [unit-sphere vertices, triangles] for an icosahedron with each face split n x n.
func _subdivided_icosahedron(n: int) -> Array:
	var t := (1.0 + sqrt(5.0)) / 2.0
	var base := [
		Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
		Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
		Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1),
	]
	var faces := [
		[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11],
		[1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8],
		[3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9],
		[4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1],
	]

	var verts := PackedVector3Array()
	var lookup := {}  # Snapped position -> index, so shared edges reuse vertices.
	var tris: Array[PackedInt32Array] = []

	for f in faces:
		var a: Vector3 = base[f[0]]
		var b: Vector3 = base[f[1]]
		var c: Vector3 = base[f[2]]
		# grid[i][j] = point i steps toward b and j steps toward c.
		var grid := []
		for i in n + 1:
			var row := PackedInt32Array()
			for j in n + 1 - i:
				var p := (a + (b - a) * i / n + (c - a) * j / n).normalized()
				var key := p.snapped(Vector3.ONE * 0.0001)
				if not lookup.has(key):
					lookup[key] = verts.size()
					verts.append(p)
				row.append(lookup[key])
			grid.append(row)
		for i in n:
			for j in n - i:
				tris.append(PackedInt32Array([grid[i][j], grid[i + 1][j], grid[i][j + 1]]))
				if j < n - i - 1:
					tris.append(PackedInt32Array([grid[i + 1][j], grid[i + 1][j + 1], grid[i][j + 1]]))

	return [verts, tris]
