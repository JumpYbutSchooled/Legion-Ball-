extends RefCounted
## Speeds a map up without changing how it looks: every static box in it (thousands of
## separate objects, each its own draw call) is combined into a few big meshes, one per
## material per chunk of the map (so parts off-screen are still skipped). Collisions are
## untouched (they stay on the StaticBody3Ds); only the visible boxes are merged.
## Materials that are separate objects but identical (the builders make many) share a
## mesh. The map shaders work in world space, so merged pieces look exactly the same.
## Plain coloured materials are swapped for the surface shader (the same colour with soft
## world-space detail on top, see shaders/detail.gdshaderinc) as they're merged.
## Anything that moves (rigid bodies, practice targets) is left alone.

## Chunk size in metres: small enough that looking one way skips most of the map, big
## enough to keep the number of meshes low.
const CHUNK := 120.0
const SurfaceShader := preload("res://shaders/surface.gdshader")


static func merge(map: Node3D) -> Dictionary:
	# key -> {"mat", "shadow", "verts", "normals", "uvs", "indices"}
	var groups := {}
	var merged: Array[MeshInstance3D] = []
	var to_local := map.global_transform.affine_inverse()
	var signatures := {}  # Material -> signature string (cached)
	var surfaces := {}  # signature -> its surface-shader version
	# A box's vertex arrays depend only on its size: made once per size, then transformed
	# for each box (in bulk, which is far quicker than appending mesh by mesh).
	var shapes := {}
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
			groups[key] = {"mat": _surface(mat, signatures[mat], surfaces), "shadow": inst.cast_shadow, "verts": PackedVector3Array(),
				"normals": PackedVector3Array(), "uvs": PackedVector2Array(), "indices": PackedInt32Array()}
		var shape_key: Variant = "box%s" % (prim as BoxMesh).size if prim is BoxMesh else prim.get_instance_id()
		if not shapes.has(shape_key):
			shapes[shape_key] = prim.get_mesh_arrays()
		var arrays: Array = shapes[shape_key]
		var xf := to_local * inst.global_transform
		var g: Dictionary = groups[key]
		# Packed arrays are values: take each out, add to it, put it back.
		var verts: PackedVector3Array = g["verts"]
		var normals: PackedVector3Array = g["normals"]
		var uvs: PackedVector2Array = g["uvs"]
		var out_idx: PackedInt32Array = g["indices"]
		var src: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var base := verts.size()
		verts.append_array(xf * src)
		normals.append_array(Transform3D(xf.basis.orthonormalized(), Vector3.ZERO) * (arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array))
		var uv = arrays[Mesh.ARRAY_TEX_UV]
		if uv is PackedVector2Array and (uv as PackedVector2Array).size() == src.size():
			uvs.append_array(uv)
		else:
			uvs.resize(uvs.size() + src.size())
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var start := out_idx.size()
		out_idx.resize(start + idx.size())
		for i in idx.size():
			out_idx[start + i] = idx[i] + base
		g["verts"] = verts
		g["normals"] = normals
		g["uvs"] = uvs
		g["indices"] = out_idx
		merged.append(inst)
	for key in groups:
		var g: Dictionary = groups[key]
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = g["verts"]
		arrays[Mesh.ARRAY_NORMAL] = g["normals"]
		arrays[Mesh.ARRAY_TEX_UV] = g["uvs"]
		arrays[Mesh.ARRAY_INDEX] = g["indices"]
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var out := MeshInstance3D.new()
		out.name = "Merged"
		out.mesh = mesh
		out.material_override = g["mat"]
		out.cast_shadow = g["shadow"]
		map.add_child(out)
	for inst in merged:
		inst.queue_free()
	return {"pieces": merged.size(), "meshes": groups.size()}


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
		cache[signature] = out
	return cache[signature]


## Two materials with the same signature render identically, so they can share a mesh.
static func _signature(mat: Material) -> String:
	if mat is StandardMaterial3D:
		var m := mat as StandardMaterial3D
		return "S%s|%s|%s|%.3f|%.3f|%.3f|%d|%d|%d|%s" % [m.albedo_color, m.emission_enabled, m.emission, m.emission_energy_multiplier,
			m.roughness, m.metallic, m.transparency, m.shading_mode, m.cull_mode, m.albedo_texture]
	if mat is ShaderMaterial:
		var sm := mat as ShaderMaterial
		var parts := [sm.shader.resource_path if sm.shader else "none"]
		if sm.shader:
			for p in sm.shader.get_shader_uniform_list():
				parts.append(str(sm.get_shader_parameter(p["name"])))
		return "H" + "|".join(PackedStringArray(parts))
	return "M%d" % mat.get_instance_id()
