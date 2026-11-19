extends RefCounted
## Speeds a map up without changing how it looks: every static box in it (thousands of
## separate objects, each its own draw call) is combined into a few big meshes, one per
## material per chunk of the map (so parts off-screen are still skipped). Collisions are
## untouched (they stay on the StaticBody3Ds); only the visible boxes are merged.
## Materials that are separate objects but identical (the builders make many) share a
## mesh. The map shaders work in world space, so merged pieces look exactly the same.
## Plain coloured materials are swapped for the surface shader (the same colour, finished
## like something built: shaders/surface.gdshader) as they're merged.
## Every box's face is baked into its vertices as it goes in (shaders/face.gdshaderinc reads
## it back): UV = the point on its face in metres from the face's middle, UV2 = half the
## face's size, CUSTOM0 = the face's tangent in world space, COLOR.r = a random number per
## box. That's what lets the map shaders bevel and wear each box's own edges and fit panels
## to each face.
## Anything that moves (rigid bodies, practice targets) is left alone.

## Chunk size in metres: small enough that looking one way skips most of the map, big
## enough to keep the number of meshes low.
const CHUNK := 120.0
const SurfaceShader := preload("res://shaders/surface.gdshader")


static func merge(map: Node3D) -> Dictionary:
	return commit(map, prepare(map))


## Turns a map's CSG boxes (the training arena is built from them in the editor) into the
## solid boxes the map builder makes: a body, a box mesh and a box collider (with its spark
## collider). Same shape, same place; they can then be merged and wear the map shaders like
## every other map's, and the ball's anti-tunnelling check works on them. The arena does
## this before anything else touches the map. Boxes that are part of a CSG operation (a
## child of another CSG shape) are left alone.
static func boxify(map: Node3D) -> void:
	var phys := PhysicsMaterial.new()
	phys.friction = 1.0
	for csg in _csg_boxes(map):
		var body := StaticBody3D.new()
		body.name = csg.name
		body.transform = csg.transform
		body.physics_material_override = phys
		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = csg.size
		mesh.mesh = box
		mesh.material_override = csg.material
		body.add_child(mesh)
		if csg.use_collision:
			var shape := CollisionShape3D.new()
			var solid := BoxShape3D.new()
			solid.size = csg.size
			shape.shape = solid
			var sparks := GPUParticlesCollisionBox3D.new()
			sparks.size = csg.size
			shape.add_child(sparks)
			body.add_child(shape)
		var parent := csg.get_parent()
		var at := csg.get_index()
		parent.remove_child(csg)
		csg.queue_free()
		parent.add_child(body)
		parent.move_child(body, at)


static func _csg_boxes(node: Node) -> Array[CSGBox3D]:
	var out: Array[CSGBox3D] = []
	for child in node.get_children():
		if child is CSGBox3D and not node is CSGShape3D:
			out.append(child)
		else:
			out.append_array(_csg_boxes(child))
	return out


## The heavy part, done ahead of time (the arena does it while the map loads, under the
## loading card): the merged meshes, made but not added yet, and the boxes they replace.
## commit() swaps them in. In between, shader_warmup.gd can draw copies so their shaders are
## built before they first appear.
static func prepare(map: Node3D) -> Dictionary:
	# key -> {"mat", "shadow", "pieces": [[shape_key, transform], ...]}, then the arrays.
	var groups := {}
	var merged: Array[MeshInstance3D] = []
	var to_local := map.global_transform.affine_inverse()
	var signatures := {}  # Material -> signature string (cached)
	var surfaces := {}  # signature -> its surface-shader version
	# A box's vertex arrays depend only on its size: made once per size, then transformed
	# for each box (in bulk, which is far quicker than appending mesh by mesh).
	var shapes := {}
	# On the main thread: which boxes go in which mesh (the scene tree isn't thread-safe).
	for inst in _meshes(map):
		var prim := inst.mesh as PrimitiveMesh
		if not prim or not inst.visible or not inst.is_visible_in_tree() or _moves(inst, map):
			continue
		var mat: Material = inst.material_override if inst.material_override else prim.material
		if not mat:
			continue
		if not signatures.has(mat):
			signatures[mat] = _signature(mat)
		var pos := inst.global_position
		var key := "%s|%d|%d|%d" % [signatures[mat], floori(pos.x / CHUNK), floori(pos.z / CHUNK), inst.cast_shadow]
		if not groups.has(key):
			groups[key] = {"mat": _surface(mat, signatures[mat], surfaces), "shadow": inst.cast_shadow, "pieces": []}
		var shape_key: Variant = "box%s" % (prim as BoxMesh).size if prim is BoxMesh else prim.get_instance_id()
		if not shapes.has(shape_key):
			shapes[shape_key] = _shape(prim)
		groups[key]["pieces"].append([shape_key, to_local * inst.global_transform])
		merged.append(inst)
	# The vertex maths, one mesh per task, spread over every CPU core.
	var list: Array = groups.values()
	var task := WorkerThreadPool.add_group_task(func(i: int) -> void: _build(list[i], shapes), list.size())
	WorkerThreadPool.wait_for_group_task_completion(task)
	var meshes: Array[MeshInstance3D] = []
	for g in list:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = g["verts"]
		arrays[Mesh.ARRAY_NORMAL] = g["normals"]
		arrays[Mesh.ARRAY_TEX_UV] = g["uvs"]
		arrays[Mesh.ARRAY_TEX_UV2] = g["uv2s"]
		arrays[Mesh.ARRAY_COLOR] = g["colors"]
		# (Three floats a vertex, straight from the vectors' own bytes: no loop.)
		arrays[Mesh.ARRAY_CUSTOM0] = (g["tangents"] as PackedVector3Array).to_byte_array().to_float32_array()
		arrays[Mesh.ARRAY_INDEX] = g["indices"]
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {},
			Mesh.ARRAY_CUSTOM_RGB_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
		var out := MeshInstance3D.new()
		out.name = "Merged"
		out.mesh = mesh
		out.material_override = g["mat"]
		out.cast_shadow = g["shadow"]
		meshes.append(out)
	return {"meshes": meshes, "originals": merged}


## Swaps prepare()'s meshes in for the boxes they replace (hidden at once, so they're never
## drawn again, even this frame).
static func commit(map: Node3D, prepared: Dictionary) -> Dictionary:
	for out in prepared["meshes"]:
		map.add_child(out)
	for inst in prepared["originals"]:
		if is_instance_valid(inst):
			inst.visible = false
			inst.queue_free()
	return {"pieces": (prepared["originals"] as Array).size(), "meshes": (prepared["meshes"] as Array).size()}


## A piece's own arrays, made once per shape: vertices, normals and indices, and (a box)
## its faces: where each vertex is on its face, half that face's size, and the face's
## tangent (see the top of this file).
static func _shape(prim: PrimitiveMesh) -> Dictionary:
	var arrays := prim.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var out := {"v": verts, "n": normals, "i": arrays[Mesh.ARRAY_INDEX], "box": prim is BoxMesh,
		"size": (prim as BoxMesh).size if prim is BoxMesh else Vector3.ZERO}
	out.merge(_faces(verts, normals, out["size"]))
	return out


## The face data for a box of `size` (zeros for anything else: the shaders then leave it be).
## A face's "up" is the box's own up on its four sides and its +Z on top and bottom; its
## tangent is the other axis, turned so tangent x up points out of the face.
static func _faces(verts: PackedVector3Array, normals: PackedVector3Array, size: Vector3) -> Dictionary:
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var tan := PackedVector3Array()
	uv.resize(verts.size())
	uv2.resize(verts.size())
	tan.resize(verts.size())
	if size != Vector3.ZERO:
		for k in verts.size():
			var n := normals[k]
			var up := Vector3.UP if absf(n.y) < 0.5 else Vector3.BACK
			var t := up.cross(n).normalized()
			uv[k] = Vector2(verts[k].dot(t), verts[k].dot(up))
			uv2[k] = Vector2(size.dot(t.abs()), size.dot(up.abs())) * 0.5
			tan[k] = t
	return {"uv": uv, "uv2": uv2, "t": tan}


## One merged mesh's arrays from its pieces (a worker thread: plain maths on this group's
## own dictionary, the shared shapes only read).
static func _build(g: Dictionary, shapes: Dictionary) -> void:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var tangents := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var colors := PackedColorArray()
	var out_idx := PackedInt32Array()
	var tint := PackedColorArray()
	for piece in g["pieces"]:
		var shape: Dictionary = shapes[piece[0]]
		var xf: Transform3D = piece[1]
		var src: PackedVector3Array = shape["v"]
		var base := verts.size()
		verts.append_array(xf * src)
		var turn := Transform3D(xf.basis.orthonormalized(), Vector3.ZERO)
		normals.append_array(turn * (shape["n"] as PackedVector3Array))
		tangents.append_array(turn * (shape["t"] as PackedVector3Array))
		var scale := xf.basis.get_scale()
		if shape["box"] and not scale.is_equal_approx(Vector3.ONE):
			# A stretched box: its faces measured at the size it's drawn.
			var stretched := _faces(Transform3D(Basis.from_scale(scale), Vector3.ZERO) * src, shape["n"], (shape["size"] as Vector3) * scale)
			uvs.append_array(stretched["uv"])
			uv2s.append_array(stretched["uv2"])
		else:
			uvs.append_array(shape["uv"])
			uv2s.append_array(shape["uv2"])
		# One random number for the whole box, from where it stands.
		var o := xf.origin
		tint.resize(src.size())
		tint.fill(Color(fposmod(sin(o.x * 12.9898 + o.y * 78.233 + o.z * 37.719) * 43758.5453, 1.0), 0.0, 0.0))
		colors.append_array(tint)
		var idx: PackedInt32Array = shape["i"]
		var start := out_idx.size()
		out_idx.resize(start + idx.size())
		for i in idx.size():
			out_idx[start + i] = idx[i] + base
	g["verts"] = verts
	g["normals"] = normals
	g["tangents"] = tangents
	g["uvs"] = uvs
	g["uv2s"] = uv2s
	g["colors"] = colors
	g["indices"] = out_idx
static func _meshes(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for child in node.get_children():
		if child is MeshInstance3D:
			out.append(child)
		out.append_array(_meshes(child))
	return out


## Under something that moves (between it and the map)?
static func _moves(node: Node, map: Node) -> bool:
	var n := node.get_parent()
	while n and n != map:
		if n is RigidBody3D or n is CharacterBody3D or n is AnimatableBody3D:
			return true
		n = n.get_parent()
	return false


## A plain, opaque, untextured StandardMaterial3D as the surface shader (one per look).
static func _surface(mat: Material, signature: String, cache: Dictionary) -> Material:
	var m := mat as StandardMaterial3D
	if not m or m.albedo_texture or m.emission_enabled or m.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED \
			or m.shading_mode != BaseMaterial3D.SHADING_MODE_PER_PIXEL or m.cull_mode != BaseMaterial3D.CULL_BACK \
			or m.vertex_color_use_as_albedo or m.albedo_color.a < 1.0:
		return mat
	if not cache.has(signature):
		var out := ShaderMaterial.new()
		out.shader = SurfaceShader
		out.set_shader_parameter("albedo", m.albedo_color)
		out.set_shader_parameter("roughness", m.roughness)
		out.set_shader_parameter("metallic", m.metallic)
		out.set_shader_parameter("kind", surface_kind(m))
		cache[signature] = out
	return cache[signature]


## What a plain material is made of, for the surface shader: 0 built (panels, worn edges),
## 1 organic (leafy greens: grass, hedges, treetops), 2 metal plate. A map can say itself
## with the material's "kind" meta.
static func surface_kind(m: StandardMaterial3D) -> int:
	if m.has_meta("kind"):
		return int(m.get_meta("kind"))
	if m.metallic >= 0.5:
		return 2
	var c := m.albedo_color
	if c.g > c.r * 1.12 and c.g > c.b * 1.12 and c.s > 0.25:
		return 1
	return 0


## Two materials with the same signature render identically, so they can share a mesh.
static func _signature(mat: Material) -> String:
	if mat is StandardMaterial3D:
		var m := mat as StandardMaterial3D
		return "S%s|%s|%s|%.3f|%.3f|%.3f|%d|%d|%d|%s|%s" % [m.albedo_color, m.emission_enabled, m.emission, m.emission_energy_multiplier,
			m.roughness, m.metallic, m.transparency, m.shading_mode, m.cull_mode, m.albedo_texture, m.get_meta("kind", -1)]
	if mat is ShaderMaterial:
		var sm := mat as ShaderMaterial
		var parts := [sm.shader.resource_path if sm.shader else "none"]
		if sm.shader:
			for p in sm.shader.get_shader_uniform_list():
				parts.append(str(sm.get_shader_parameter(p["name"])))
		return "H" + "|".join(PackedStringArray(parts))
	return "M%d" % mat.get_instance_id()
