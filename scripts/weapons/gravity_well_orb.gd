extends Node3D
## GRAVITY WELL's singularity: a dark orb that drags every other player within `radius`
## toward it for `lifetime` seconds (the owner's copy sends the pull), then pops.

var manager: Node
var visual_only := false
var radius := 15.0
var lifetime := 2.5
var color := Color(0.35, 0.2, 0.9)

var _t := 0.0
var _tick := 0.0
var _core: MeshInstance3D
var _ring: MeshInstance3D


func _ready() -> void:
	top_level = true
	var sphere := SphereMesh.new()
	sphere.radius = 0.9
	sphere.height = 1.8
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.02, 0.0, 0.05)
	dark.emission_enabled = true
	dark.emission = color
	dark.emission_energy_multiplier = 0.6
	_core = MeshInstance3D.new()
	_core.mesh = sphere
	_core.material_override = dark
	add_child(_core)
	var torus := TorusMesh.new()
	torus.inner_radius = 1.4
	torus.outer_radius = 1.6
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = color * 3.0
	_ring = MeshInstance3D.new()
	_ring.mesh = torus
	_ring.material_override = glow
	add_child(_ring)
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 6.0
	light.omni_range = radius
	add_child(light)


func _physics_process(delta: float) -> void:
	_t += delta
	var k := _t / lifetime
	# The ring swirls inward faster and faster.
	_ring.rotate_object_local(Vector3.RIGHT, delta * (3.0 + k * 10.0))
	_ring.scale = Vector3.ONE * lerpf(radius * 0.4, 1.0, k)
	if manager and fmod(_t, 0.25) < delta:
		manager.call("_warp", global_position, 0.12, radius * 0.5)
	if _t >= lifetime:
		if manager:
			manager.call("spawn_explosion", {
				"position": global_position, "color": color, "radius": 6.0, "damage": 5.0,
				"force": 30.0, "spark_count": 160, "light_energy": 160.0, "warp_strength": 0.35,
				"sound": "implode",
			}, false, visual_only)
		queue_free()
		return
	if visual_only or not manager:
		return
	_tick -= delta
	if _tick <= 0.0:
		_tick = 0.3
		for t in get_tree().get_nodes_in_group("lock_targets"):
			if t.call("is_alive") and (t.call("get_aim_point") as Vector3).distance_to(global_position) <= radius:
				manager.call("apply_status", t, "pull", 0.4, global_position)
