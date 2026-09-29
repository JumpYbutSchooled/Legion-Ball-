extends Node3D
## MIASMA: a lingering cloud that heals everyone inside it, friend or foe - HEAL_RATE
## HP/s total, split evenly among however many are in it. Spawned by miasma.gd
## (manager.spawn_node); everyone sees a copy, only the caster's applies healing
## (visual_only guards that, the same as crystal_shot.gd).

const HEAL_RATE := 5.0
const TICK := 0.5

var manager: Node
var visual_only := false
var radius := 10.0
var lifetime := 6.0

var _t := 0.0
var _tick_timer := 0.0


func _ready() -> void:
	top_level = true
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = 16
	sphere.rings = 8
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.4, 1.0, 0.6, 0.16)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(0.4, 1.0, 0.6)
	mat.emission_energy_multiplier = 0.5
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mesh := MeshInstance3D.new()
	mesh.mesh = sphere
	mesh.material_override = mat
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh)
	var light := OmniLight3D.new()
	light.light_color = Color(0.4, 1.0, 0.6)
	light.light_energy = 3.0
	light.omni_range = radius * 1.5
	add_child(light)


func _physics_process(delta: float) -> void:
	_t += delta
	if _t >= lifetime:
		queue_free()
		return
	if visual_only or not manager:
		return
	_tick_timer -= delta
	if _tick_timer > 0.0:
		return
	_tick_timer = TICK
	var candidates := get_tree().get_nodes_in_group("lock_targets")
	var own: Node3D = manager.get("ball")
	if own and not candidates.has(own):
		candidates.append(own)
	var inside: Array = []
	for target in candidates:
		if target.call("is_alive") and target.global_position.distance_to(global_position) <= radius:
			inside.append(target)
	if inside.is_empty():
		return
	var each := HEAL_RATE * TICK / inside.size()
	for target in inside:
		manager.call("heal", target, each)
