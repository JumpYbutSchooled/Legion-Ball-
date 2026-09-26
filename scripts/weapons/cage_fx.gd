extends Node3D
## PRISM CAGE's crystal prison: glowing bars round where the orb caught someone, for
## `lifetime` seconds (the hold itself is the "cage" status). Shatters when it ends.

var manager: Node
var visual_only := false
var lifetime := 2.0
var color := Color(0.3, 1.0, 0.85)

var _t := 0.0


func _ready() -> void:
	top_level = true
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(color.r * 2.0, color.g * 2.0, color.b * 2.0, 0.8)
	# Eight bars in a ring, and a ring top and bottom.
	for i in 8:
		var a := TAU * i / 8.0
		var bar := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.12, 2.4, 0.12)
		bar.mesh = box
		bar.material_override = mat
		bar.position = Vector3(cos(a), 0.0, sin(a)) * 1.1
		add_child(bar)
	for y in [-1.2, 1.2]:
		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 1.05
		torus.outer_radius = 1.2
		ring.mesh = torus
		ring.material_override = mat
		ring.position = Vector3(0, y, 0)
		add_child(ring)


func _process(delta: float) -> void:
	_t += delta
	rotate_y(delta * 0.8)
	if _t >= lifetime:
		if manager:
			manager.call("_light", global_position, 30.0, 6.0, 0.15, color)
		var sfx := get_tree().root.get_node_or_null("Sfx")
		if sfx:
			sfx.call("play", "shatter", global_position, -4.0)
		queue_free()
