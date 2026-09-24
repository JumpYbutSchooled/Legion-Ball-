extends Node3D
## Weapon manager, mounted on the ball. Follows the ball (not its spin), turns every
## weapon toward the crosshair, and routes input to the equipped one:
##   1 Gatling  2 Railgun  3 Scatter  4 Tether  5 Nova  6 Swarm
##   ` = holster/draw, left mouse = fire (mouse captured).
## Switching plays the old weapon's exit wave and the new weapon's enter wave together.
## Also provides the helpers the weapons share: beams, lights, warp bubbles, hits,
## recoil, knockback, camera shake, and finding targets on screen.

## Forwarded from the gatling: which blade just fired (the crosshair uses it).
signal fired(blade_index: int)

const BladeWeapon := preload("res://scripts/weapons/blade_weapon.gd")
const Gatling := preload("res://scripts/weapons/gatling.gd")
const Railgun := preload("res://scripts/weapons/railgun.gd")
const Scatter := preload("res://scripts/weapons/scatter.gd")
const Tether := preload("res://scripts/weapons/tether.gd")
const Nova := preload("res://scripts/weapons/nova.gd")
const Swarm := preload("res://scripts/weapons/swarm.gd")
const WeaponInfo := preload("res://scripts/weapon_info.gd")
const SLOT_ACTIONS := ["weapon_1", "weapon_2", "weapon_3", "weapon_4", "weapon_5", "weapon_6"]
const Beam := preload("res://scripts/dash_laser.gd")
const MuzzleWarp := preload("res://scripts/muzzle_warp.gd")
const FlashLight := preload("res://scripts/flash_light.gd")
const LightFlare := preload("res://scripts/light_flare.gd")
const Explosion := preload("res://scripts/explosion.gd")
const Missile := preload("res://scripts/weapons/swarm_missile.gd")

@export var ball: RigidBody3D
@export var camera: Camera3D
## Gets add_shake() calls.
@export var camera_rig: Node
@export var max_range := 400.0

## Where the crosshair ray lands (or max_range along it on a miss).
var aim_point := Vector3.ZERO
var weapons: Array = []
var current := 0

var _was_captured := false


func _ready() -> void:
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var scripts := [Gatling, Railgun, Scatter, Tether, Nova, Swarm]
	for slot in scripts.size():
		var w = scripts[slot].new()
		w.manager = self
		# Colours live in weapon_info.gd, shared with the menus and the selector.
		w.color = WeaponInfo.get_entry(slot)["color"]
		add_child(w)
		weapons.append(w)
	weapons[0].fired.connect(func(i: int) -> void: fired.emit(i))
	weapons[current].enter()


func current_weapon() -> Node3D:
	return weapons[current]


## Fade amount for the crosshair: 1 when the equipped weapon is fully out.
func get_arm_amount() -> float:
	return current_weapon().get_arm_amount()


func get_crosshair() -> Dictionary:
	return current_weapon().get_crosshair()


func get_gatling_angles() -> PackedFloat32Array:
	return weapons[0].row_angles


## Switches weapon: the old one's exit and the new one's enter play at the same time.
func select(slot: int) -> void:
	if slot < 0 or slot >= weapons.size():
		return
	if slot != current:
		current_weapon().exit()
		current = slot
	current_weapon().enter()


func toggle() -> void:
	var w = current_weapon()
	if w.state == BladeWeapon.State.READY or w.state == BladeWeapon.State.ENTERING:
		w.exit()
	else:
		w.enter()


func _physics_process(delta: float) -> void:
	# Other players' weapons follow the network (apply_net_state) instead of input.
	if not ball or not camera or not is_multiplayer_authority():
		return
	var controls := _controls_enabled()
	if controls:
		for slot in SLOT_ACTIONS.size():
			if Input.is_action_just_pressed(SLOT_ACTIONS[slot]):
				select(slot)
				break
		if Input.is_action_just_pressed("toggle_weapon"):
			toggle()

	var hit := _raycast_crosshair()
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	# Skip the click that captures the mouse, so capturing doesn't also fire.
	var pressed := controls and captured and _was_captured and Input.is_action_pressed("fire")
	current_weapon().handle_fire(pressed, hit, delta)
	_was_captured = captured


## What other players need to draw this weapon: [aim point, equipped slot, drawn?].
func get_net_state() -> Array:
	var w = current_weapon()
	var drawn: bool = w.state == BladeWeapon.State.READY or w.state == BladeWeapon.State.ENTERING
	return [aim_point, current, drawn]


## Applies another player's weapon state from the network.
func apply_net_state(aim: Vector3, slot: int, drawn: bool) -> void:
	aim_point = aim
	if slot != current:
		select(slot)
	var w = current_weapon()
	var is_drawn: bool = w.state == BladeWeapon.State.READY or w.state == BladeWeapon.State.ENTERING
	if drawn != is_drawn:
		toggle()


func _controls_enabled() -> bool:
	if ball.get("dead"):
		return false
	var net := get_tree().root.get_node_or_null("Net")
	return not (net and net.get("input_blocked"))


func _process(_delta: float) -> void:
	if not ball:
		return
	var center := ball.get_global_transform_interpolated().origin
	# Other players have no camera here: fall back to the way the weapon already faces.
	var look := -camera.global_basis.z if camera else -global_basis.z
	var dir := aim_point - center
	# Looking steeply down, the crosshair ray lands right next to the ball, where the
	# direction to it is meaningless; follow the camera's own look direction instead.
	if dir.length() < 2.0:
		dir = look
	dir = dir.normalized()
	# Keep the blades upright, but near vertical "up" is parallel to the aim, so use
	# the camera's horizontal heading as the reference instead (keeps them from spinning).
	var up := Vector3.UP
	if absf(dir.y) > 0.95:
		var heading := Vector3(look.x, 0.0, look.z)
		if heading.length() < 0.01:
			var ref := camera.global_basis.y if camera else global_basis.y
			heading = Vector3(ref.x, 0.0, ref.z)
		if heading.length() < 0.01:
			heading = Vector3.FORWARD
		up = heading.normalized() * -signf(dir.y)
	global_transform = Transform3D(Basis.looking_at(dir, up), center)


## Casts from the camera through the screen center (the crosshair).
## Updates aim_point and returns the hit dictionary (empty on a miss).
func _raycast_crosshair() -> Dictionary:
	var center := camera.get_viewport().get_visible_rect().size / 2.0
	var from := camera.project_ray_origin(center)
	var dir := camera.project_ray_normal(center)
	var hit := raycast(from, from + dir * max_range)
	aim_point = hit["position"] if not hit.is_empty() else from + dir * max_range
	return hit


# --- Helpers the weapons share -------------------------------------------------

## Living lock targets whose aim point is on screen within `radius_px` of the center,
## nearest to the ball first. Each entry: {"target", "point", "screen", "distance"}.
func targets_on_screen(radius_px: float) -> Array:
	var found := []
	var center := camera.get_viewport().get_visible_rect().size / 2.0
	var ball_pos := ball.global_position
	for target in get_tree().get_nodes_in_group("lock_targets"):
		if not target.call("is_alive"):
			continue
		var p: Vector3 = target.call("get_aim_point")
		if camera.is_position_behind(p):
			continue
		var screen := camera.unproject_position(p)
		if screen.distance_to(center) > radius_px:
			continue
		found.append({"target": target, "point": p, "screen": screen, "distance": p.distance_to(ball_pos)})
	found.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["distance"] < b["distance"])
	return found


## Converts an angle from the screen center (degrees) into pixels, using the camera's FOV.
func angle_to_pixels(degrees: float) -> float:
	var half_height := camera.get_viewport().get_visible_rect().size.y / 2.0
	return tan(deg_to_rad(degrees)) / tan(deg_to_rad(camera.fov / 2.0)) * half_height


func screen_pos(point: Vector3) -> Vector2:
	return camera.unproject_position(point)


## Physics ray that ignores the ball. Only call during physics.
func raycast(from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [ball.get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(query)


## Damages anything with take_hit() and shoves it: players through the network
## (receive_impulse), everything else directly.
func hit_object(collider: Object, damage: float, pos: Vector3, dir: Vector3, impulse: float) -> void:
	if collider.has_method("take_hit"):
		collider.call("take_hit", damage, pos, dir)
	if collider.has_method("receive_impulse"):
		collider.call("receive_impulse", dir * impulse)
		return
	var body := collider as RigidBody3D
	if body:
		# Resting bodies fall asleep and can ignore impulses until woken.
		body.sleeping = false
		body.apply_impulse(dir * impulse, pos - body.global_position)


## Pushes the ball back along the flattened shot direction.
func recoil(shot_dir: Vector3, impulse: float) -> void:
	var flat := Vector3(shot_dir.x, 0.0, shot_dir.z)
	if flat.length() > 0.01:
		ball.apply_central_impulse(-flat.normalized() * impulse)


## Dash-strength kick on the ball, opposite the shot.
func knockback(shot_dir: Vector3, speed: float) -> void:
	var flat := Vector3(shot_dir.x, 0.0, shot_dir.z)
	if flat.length() > 0.01 and ball.has_method("apply_knockback"):
		ball.call("apply_knockback", -flat.normalized() * speed)


## Instant change to the ball's velocity in any direction (Scatter jump, Nova launch),
## without the dash camera effects.
func push_ball(velocity_change: Vector3) -> void:
	if ball.has_method("apply_knockback"):
		ball.call("apply_knockback", velocity_change, false)


func shake(amount: float) -> void:
	if camera_rig and camera_rig.has_method("add_shake"):
		camera_rig.call("add_shake", amount)


# --- Effects -------------------------------------------------------------------------
# Every effect the local player makes is also sent to the other players (visual only),
# so everyone sees the same shots, flashes and explosions. See _broadcasting().

func spawn_beam(origin: Vector3, dir: Vector3, length: float, width: float, lifetime: float, intensity: float, color := Color(0.3, 0.8, 1.0)) -> void:
	_beam(origin, dir, length, width, lifetime, intensity, color)
	if _broadcasting():
		_net_beam.rpc(origin, dir, length, width, lifetime, intensity, color)


func spawn_light(pos: Vector3, energy: float, light_range: float, lifetime: float, color := Color(0.4, 0.85, 1.0)) -> void:
	_light(pos, energy, light_range, lifetime, color)
	if _broadcasting():
		_net_light.rpc(pos, energy, light_range, lifetime, color)


func spawn_warp(pos: Vector3, strength: float, end_radius: float) -> void:
	_warp(pos, strength, end_radius)
	if _broadcasting():
		_net_warp.rpc(pos, strength, end_radius)


## Explosion with the given settings (scripts/explosion.gd property names, plus
## "position"). Only the local player's copy deals damage; other players see a copy.
func spawn_explosion(props: Dictionary, broadcast := true, visual_only := false) -> void:
	var blast := Explosion.new()
	for key in props:
		if key != "position":
			blast.set(key, props[key])
	blast.manager = self
	blast.visual_only = visual_only
	blast.exclude = [ball.get_rid()]
	blast.position = props["position"]
	ball.get_parent().add_child(blast)
	if broadcast and _broadcasting():
		_net_explosion.rpc(props)


## Swarm missile (scripts/weapons/swarm_missile.gd property names, plus "position" and
## "target_path"). Other players get a harmless copy that flies the same way.
func spawn_missile(props: Dictionary, visual_only := false) -> void:
	var missile := Missile.new()
	for key in props:
		if key != "position" and key != "target_path":
			missile.set(key, props[key])
	var path: String = props.get("target_path", "")
	if path != "":
		missile.target = get_node_or_null(path)
	missile.manager = self
	missile.visual_only = visual_only
	missile.position = props["position"]
	ball.get_parent().add_child(missile)
	if not visual_only and _broadcasting():
		_net_missile.rpc(props)


## A blade jolted by a shot; other players see it too.
func broadcast_kick(weapon: Node, index: int) -> void:
	if _broadcasting():
		_net_kick.rpc(weapons.find(weapon), index)


## Only the player who owns this weapon sends effects, and only when online.
func _broadcasting() -> bool:
	if not is_multiplayer_authority():
		return false
	var net := get_tree().root.get_node_or_null("Net")
	return net != null and net.get("online")


@rpc("authority", "unreliable")
func _net_beam(origin: Vector3, dir: Vector3, length: float, width: float, lifetime: float, intensity: float, color: Color) -> void:
	_beam(origin, dir, length, width, lifetime, intensity, color)


@rpc("authority", "unreliable")
func _net_light(pos: Vector3, energy: float, light_range: float, lifetime: float, color: Color) -> void:
	_light(pos, energy, light_range, lifetime, color)


@rpc("authority", "unreliable")
func _net_warp(pos: Vector3, strength: float, end_radius: float) -> void:
	_warp(pos, strength, end_radius)


@rpc("authority", "reliable")
func _net_explosion(props: Dictionary) -> void:
	spawn_explosion(props, false, true)


@rpc("authority", "reliable")
func _net_missile(props: Dictionary) -> void:
	spawn_missile(props, true)


@rpc("authority", "unreliable")
func _net_kick(slot: int, index: int) -> void:
	if slot >= 0 and slot < weapons.size():
		weapons[slot].kick(index)


func _beam(origin: Vector3, dir: Vector3, length: float, width: float, lifetime: float, intensity: float, color: Color) -> void:
	var beam := Beam.new()
	beam.length = length
	beam.width = width
	beam.lifetime = lifetime
	beam.extend_time = minf(0.03, lifetime * 0.3)
	beam.shoot_speed = 0.0
	beam.widest_at = 0.1
	beam.intensity = intensity
	beam.color = color
	ball.get_parent().add_child(beam)
	beam.fire(origin, dir)


func _light(pos: Vector3, energy: float, light_range: float, lifetime: float, color: Color) -> void:
	var light := FlashLight.new()
	light.light_color = color
	light.light_energy = energy
	light.omni_range = light_range
	light.lifetime = lifetime
	_add_effect(light, pos)
	# Every flash of light also gets a lens-flare burst, sized by how bright it is.
	var flare := LightFlare.new()
	flare.color = color
	flare.size = clampf(0.4 + energy * 0.04, 0.5, 12.0)
	flare.lifetime = maxf(lifetime * 1.6, 0.1)
	_add_effect(flare, pos)


func _warp(pos: Vector3, strength: float, end_radius: float) -> void:
	var warp := MuzzleWarp.new()
	warp.strength = strength
	warp.end_radius = end_radius
	_add_effect(warp, pos)


func _add_effect(node: Node3D, pos: Vector3) -> void:
	# The effects parent (the scene root) sits at the origin, so local = global;
	# setting it before adding means _ready() already sees the right spot.
	node.position = pos
	ball.get_parent().add_child(node)
