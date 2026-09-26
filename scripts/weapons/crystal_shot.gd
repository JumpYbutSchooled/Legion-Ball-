extends Node3D
## A crystal projectile shared by many weapons (spawned with weapon.gd spawn_node, so
## everyone else sees a harmless copy). Configured entirely by properties:
##   velocity, gravity          how it flies (gravity in m/s^2: 0 = straight)
##   damage, impulse            on a direct hit (practice-scale; x4 on players)
##   status, status_time, status_data   put on whatever it hits (chill, cage, pin...)
##   pierce                     keeps going through players and targets
##   bounces, bounce_bonus      glance off walls this many times, damage x(1 + bonus) each
##   stick, fuse                stick to what it hits, then go off after `fuse` seconds
##   explosion                  explosion.gd props for when it goes off ({} = none)
##   split, split_props         burst into `split` more shots (props for each) when it goes off
##   spawn_script, spawn_props  leave an object behind where it lands (a Gravity Well...)
##   carry                      drag its owner's ball along behind it (Skylance)
##   lifetime, size, color
## Walls stop it (or bounce it); it goes off where it stops.

var manager: Node
var visual_only := false
var velocity := Vector3.FORWARD * 60.0
var gravity := 0.0
var damage := 3.0
var impulse := 6.0
var status := ""
var status_time := 0.0
var status_data := Vector3.ZERO
var pierce := false
var bounces := 0
var bounce_bonus := 0.0
var stick := false
var fuse := 0.0
var explosion: Dictionary = {}
var split := 0
var split_props: Dictionary = {}
var spawn_script := ""
var spawn_props: Dictionary = {}
var carry := false
## Arbalest: a target knocked into a wall within 3.5 m behind it is pinned this long.
var pin := 0.0
## Only leave spawn_script behind if it struck something (Prism Cage).
var spawn_on_hit := false
var lifetime := 4.0
var size := 0.3
var color := Color(1, 1, 1)
## Something to steer toward (homing), optional.
var target: Node3D = null
var turn_rate := 0.0

var _t := 0.0
var _bounced := 0
var _stuck_to: Node3D = null
var _stuck_offset := Vector3.ZERO
var _fuse_left := -1.0
var _hit: Array = []
var _done := false
var _struck_any := false


func _ready() -> void:
	top_level = true
	var gem := SphereMesh.new()
	gem.radius = size
	gem.height = size * 2.0
	gem.radial_segments = 6
	gem.rings = 3
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color.lerp(Color.WHITE, 0.3) * 3.0
	gem.material = mat
	var mesh := MeshInstance3D.new()
	mesh.mesh = gem
	mesh.scale = Vector3(1, 1, 1.8)
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh)
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 4.0
	light.omni_range = 4.0
	add_child(light)
	_face()


func _face() -> void:
	if velocity.length() > 0.01:
		var up := Vector3.UP if absf(velocity.normalized().y) < 0.98 else Vector3.RIGHT
		global_basis = Basis.looking_at(velocity.normalized(), up)


func _owner_ball() -> Node3D:
	return manager.ball if manager else null


func _physics_process(delta: float) -> void:
	if _done:
		return
	_t += delta
	if _stuck_to != null or _fuse_left >= 0.0:
		_tick_fuse(delta)
		return
	if _t >= lifetime:
		_go_off(global_position, Vector3.UP)
		return
	# Time Dilator fields slow other players' shots.
	var slow: float = TimeField.factor(get_tree(), global_position, manager.get_multiplayer_authority() if manager else 0)
	if target and is_instance_valid(target) and turn_rate > 0.0 and target.call("is_alive"):
		var want: Vector3 = (target.call("get_aim_point") - global_position).normalized()
		var dir := velocity.normalized()
		var angle := dir.angle_to(want)
		if angle > 0.001:
			var axis := dir.cross(want)
			if axis.length() > 0.0001:
				velocity = dir.rotated(axis.normalized(), minf(angle, turn_rate * delta)) * velocity.length()
	velocity += Vector3.DOWN * gravity * delta
	var step := velocity * delta * slow
	var from := global_position
	var query := PhysicsRayQueryParameters3D.create(from, from + step)
	var skip: Array[RID] = []
	var own := _owner_ball()
	if own:
		skip.append(own.get_rid())
	for c in _hit:
		if is_instance_valid(c):
			skip.append(c.get_rid())
	query.exclude = skip
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		global_position += step
		_face()
		_carry_owner()
		return
	var collider: Object = hit["collider"]
	var pos: Vector3 = hit["position"]
	var normal: Vector3 = hit["normal"]
	if collider.has_method("take_hit"):
		_strike(collider, pos)
		if pierce:
			_hit.append(collider)
			global_position = pos + velocity.normalized() * 0.2
			return
		if stick:
			_stick_to(collider as Node3D, pos)
			return
		_go_off(pos, normal)
		return
	# A wall.
	if _bounced < bounces:
		_bounced += 1
		velocity = velocity.bounce(normal)
		global_position = pos + normal * 0.15
		_face()
		if manager:
			manager.call("_light", pos, 20.0, 5.0, 0.08, color)
		return
	if stick:
		_stick_to(collider as Node3D, pos)
		return
	_go_off(pos, normal)


## Skylance: the owner's ball is hauled along behind.
func _carry_owner() -> void:
	if not carry or visual_only or not manager:
		return
	var b: RigidBody3D = manager.ball
	var behind := global_position - velocity.normalized() * 2.5
	b.linear_velocity = (behind - b.global_position) * 12.0


func _strike(collider: Object, pos: Vector3) -> void:
	if visual_only or not manager:
		return
	var dmg := damage * (1.0 + bounce_bonus * _bounced)
	_struck_any = true
	manager.hit_object(collider, dmg, pos, velocity.normalized(), impulse)
	if status != "":
		manager.apply_status(collider, status, status_time, status_data)
	if pin > 0.0 and collider is CollisionObject3D:
		var query := PhysicsRayQueryParameters3D.create(pos, pos + velocity.normalized() * 3.5)
		query.exclude = [(collider as CollisionObject3D).get_rid(), manager.ball.get_rid()]
		var wall := get_world_3d().direct_space_state.intersect_ray(query)
		if not wall.is_empty() and not (wall["collider"] as Object).has_method("take_hit"):
			manager.apply_status(collider, "pin", pin)
			manager.call("spawn_beam", wall["position"], wall["normal"], 1.5, 0.8, 0.3, 20.0, color)


func _stick_to(node: Node3D, pos: Vector3) -> void:
	_stuck_to = node
	_stuck_offset = node.to_local(pos) if node else pos
	global_position = pos
	_fuse_left = fuse


func _tick_fuse(delta: float) -> void:
	if _stuck_to != null and is_instance_valid(_stuck_to):
		global_position = _stuck_to.to_global(_stuck_offset)
	_fuse_left -= delta
	# Blinks faster as it's about to go.
	visible = fmod(_fuse_left, maxf(0.05, _fuse_left * 0.25)) > 0.03 or _fuse_left < 0.2
	if _fuse_left <= 0.0:
		visible = true
		_go_off(global_position, Vector3.UP)


func _go_off(pos: Vector3, normal: Vector3) -> void:
	if _done:
		return
	_done = true
	if manager:
		if not explosion.is_empty():
			var props := explosion.duplicate()
			props["position"] = pos + normal * 0.3
			if not props.has("color"):
				props["color"] = color
			manager.call("spawn_explosion", props, false, visual_only)
		if not visual_only:
			for i in split:
				var props := split_props.duplicate()
				var spread := Vector3(randf_range(-1, 1), randf_range(0.6, 1.4), randf_range(-1, 1)).normalized()
				props["position"] = pos + normal * 0.5
				props["velocity"] = spread * randf_range(12.0, 22.0)
				manager.call("spawn_node", "res://scripts/weapons/crystal_shot.gd", props)
			if spawn_script != "" and (_struck_any or not spawn_on_hit):
				var props := spawn_props.duplicate()
				props["position"] = pos + normal * 0.4
				manager.call("spawn_node", spawn_script, props)
	queue_free()


const TimeField := preload("res://scripts/weapons/time_field.gd")
