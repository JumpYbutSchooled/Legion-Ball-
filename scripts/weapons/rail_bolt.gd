extends Node3D
## The railgun's shot: a bolt of light that streaks out from the blade and only does
## anything when it gets there. Flies `speed` m/s, leaving a fading trail, homing onto
## the locked target if there is one. Each physics step it raycasts the stretch it just
## covered, so it hits whatever is actually in the way (players moving across it too).
## On impact: damage, a shove, a star of spikes and the explosion.
## Other players get a harmless copy (visual_only) that flies the same way; the real
## bolt's impact effects reach them over the network.
## Set properties and position before adding it to the tree; frees itself.

const TimeField := preload("res://scripts/weapons/time_field.gd")

var manager: Node
var visual_only := false
var dir := Vector3.FORWARD
var speed := 200.0
var max_range := 400.0
var color := Color(1.0, 0.5, 0.1)
## Homes onto this (a lock target) if set.
var target: Node3D = null
var damage := 10.0
var hit_impulse := 40.0
var explosion_radius := 5.0
var explosion_damage := 8.0
var explosion_force := 30.0

var _traveled := 0.0
var _head: MeshInstance3D
var _light: OmniLight3D


func _ready() -> void:
	top_level = true
	# The glowing head: a long thin spindle pointing where it's going.
	var spindle := SphereMesh.new()
	spindle.radius = 0.5
	spindle.height = 1.0
	spindle.radial_segments = 8
	spindle.rings = 4
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color.lerp(Color.WHITE, 0.5) * 4.0
	spindle.material = mat
	_head = MeshInstance3D.new()
	_head.mesh = spindle
	_head.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_head.scale = Vector3(0.45, 0.45, 5.0)
	add_child(_head)
	_light = OmniLight3D.new()
	_light.light_color = color
	_light.light_energy = 14.0
	_light.omni_range = 9.0
	add_child(_light)
	_face()


func _face() -> void:
	var up := Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT
	global_basis = Basis.looking_at(dir, up)


func _physics_process(delta: float) -> void:
	if target and is_instance_valid(target) and target.call("is_alive"):
		var to: Vector3 = target.call("get_aim_point") - global_position
		if to.length() > 0.01:
			dir = to.normalized()
	# Half speed inside someone else's Time Dilator field.
	var step := speed * delta * TimeField.factor(get_tree(), global_position, manager.get_multiplayer_authority() if manager else 0)
	var from := global_position
	var to_pos := from + dir * step
	var hit: Dictionary = manager.raycast(from, to_pos) if manager else {}
	var end: Vector3 = hit["position"] if not hit.is_empty() else to_pos
	# Trail: a fading streak over the stretch just covered (each computer draws its own).
	if manager:
		manager.call("_beam", from, dir, from.distance_to(end) + 1.0, 0.75, 0.5, 30.0, color)
	global_position = end
	_face()
	_traveled += step
	if not hit.is_empty():
		if not visual_only:
			_impact(hit)
		queue_free()
	elif _traveled >= max_range:
		queue_free()


func _impact(hit: Dictionary) -> void:
	var pos: Vector3 = hit["position"]
	var normal: Vector3 = hit["normal"]
	# A star of long spikes bursting off the surface.
	manager.call("spawn_beam", pos, normal, 3.0, 2.0, 0.25, 30.0, color)
	for i in 8:
		var jitter := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1))
		manager.call("spawn_beam", pos, (normal + jitter * 1.2).normalized(), randf_range(1.5, 3.0), 1.0, 0.2, 30.0, color)
	manager.call("hit_object", hit["collider"], damage, pos, dir, hit_impulse)
	manager.call("spawn_explosion", {
		"position": pos + normal * 0.3,
		"color": color,
		"radius": explosion_radius,
		"damage": explosion_damage,
		"force": explosion_force,
	})
