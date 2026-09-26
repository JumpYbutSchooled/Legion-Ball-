extends Node3D
## Weapon manager, mounted on the ball. Follows the ball (not its spin), turns every
## weapon toward the crosshair, and routes input to the equipped one:
##   1-6 the player's own loadout (weapon_info.gd; Gatling, Railgun... by default)
##   7 Rain of God, 8 Tears of an Angel (mods, owner)  9 Pillars of God (owner)
##   0 hide/show the staff weapons
##   (WeaponInfo.unlocked_count)
##   ` = holster/draw, left mouse = fire (mouse captured).
## Switching plays the old weapon's exit wave and the new weapon's enter wave together.
## Also provides the helpers the weapons share: beams, lights, warp bubbles, hits,
## recoil, knockback, camera shake, and finding targets on screen.

## Forwarded from the gatling: which blade just fired (the crosshair uses it).
signal fired(blade_index: int)
## Key 0 hid or showed the staff weapons (the weapon selector shows the result).
signal staff_weapons_toggled(shown: bool)

const BladeWeapon := preload("res://scripts/weapons/blade_weapon.gd")
const WeaponInfo := preload("res://scripts/weapon_info.gd")
const SLOT_ACTIONS := ["weapon_1", "weapon_2", "weapon_3", "weapon_4", "weapon_5", "weapon_6", "weapon_7", "weapon_8", "weapon_9"]
const Beam := preload("res://scripts/dash_laser.gd")
const MuzzleWarp := preload("res://scripts/muzzle_warp.gd")
const FlashLight := preload("res://scripts/flash_light.gd")
const LightFlare := preload("res://scripts/light_flare.gd")
const Explosion := preload("res://scripts/explosion.gd")
const Missile := preload("res://scripts/weapons/swarm_missile.gd")
const RailBolt := preload("res://scripts/weapons/rail_bolt.gd")
const Sfx := preload("res://scripts/sfx.gd")
const DamageNumber := preload("res://scripts/damage_number.gd")
const BallScript := preload("res://scripts/ball.gd")
const InputSetup := preload("res://scripts/input_setup.gd")
const WallRipple := preload("res://scripts/wall_ripple.gd")
## How fast the weapon turns to follow the aim (higher = snappier).
const TURN_RATE := 30.0

@export var ball: RigidBody3D
@export var camera: Camera3D
## Gets add_shake() calls.
@export var camera_rig: Node
## Long enough to reach across the whole online map.
@export var max_range := 2000.0

## Where the crosshair ray lands (or max_range along it on a miss).
var aim_point := Vector3.ZERO
var weapons: Array = []
var current := 0
## This ball's loadout (weapon ids for keys 1-6, weapon_info.gd). Set by the arena
## before the ball is added (from the roster online, Settings offline).
var loadout: Array = WeaponInfo.DEFAULT_LOADOUT.duplicate()
## The weapon id in each slot: the loadout, then the staff weapons (keys 7-9).
var slot_ids: Array = []

var _was_captured := false
## Id of the weapon that last dealt damage: picks the kill's impact frames.
var last_hit_id := "railgun"
## Damage numbers still collecting hits, by target.
var _numbers := {}
## Objects this weapon manager has spawned (their network names).
var _spawn_count := 0
var _aim_basis := Basis.IDENTITY
var _has_aim_basis := false


func _ready() -> void:
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	# The player's own loadout, then the staff weapons: every ball has those too, so a
	# moderator's or the owner's shows up on their ball for everyone.
	slot_ids = WeaponInfo.slot_ids(loadout)
	loadout = slot_ids.slice(0, WeaponInfo.LOADOUT_SIZE)
	for id in slot_ids:
		weapons.append(_make(id))
	weapons[current].enter()


func _make(id: String) -> Node3D:
	var info := WeaponInfo.by_id(id)
	var w = load(info["script"]).new()
	w.manager = self
	# Colours live in weapon_info.gd, shared with the menus and the selector.
	w.color = info["color"]
	add_child(w)
	if w.has_signal("fired"):
		w.fired.connect(func(i: int) -> void: fired.emit(i))
	return w


## Swaps in a new loadout (keys 1-6); the staff weapons stay. Every computer does this
## for a player at the same moment (their respawn), so slot numbers stay in step.
func set_loadout(ids: Array) -> void:
	var fresh := WeaponInfo.valid_loadout(ids)
	if fresh == loadout:
		return
	var was_drawn := is_drawn()
	for i in WeaponInfo.LOADOUT_SIZE:
		weapons[i].queue_free()
	loadout = fresh
	slot_ids = WeaponInfo.slot_ids(loadout)
	for i in WeaponInfo.LOADOUT_SIZE:
		weapons[i] = _make(slot_ids[i])
	if was_drawn:
		current_weapon().enter()


func slot_id(slot: int) -> String:
	return slot_ids[slot] if slot >= 0 and slot < slot_ids.size() else ""


func slot_info(slot: int) -> Dictionary:
	return WeaponInfo.by_id(slot_id(slot))


func current_weapon() -> Node3D:
	return weapons[current]


## Fade amount for the crosshair: 1 when the equipped weapon is fully out.
func get_arm_amount() -> float:
	return current_weapon().get_arm_amount()


func get_crosshair() -> Dictionary:
	return current_weapon().get_crosshair()


func get_gatling_angles() -> PackedFloat32Array:
	for w in weapons:
		if "row_angles" in w:
			return w.row_angles
	return PackedFloat32Array([40.0, 0.0, -28.0])


## Switches weapon: the old one's exit and the new one's enter play at the same time.
func select(slot: int) -> void:
	if slot < 0 or slot >= weapons.size() or not _slot_allowed(slot):
		return
	if slot != current:
		current_weapon().exit()
		current = slot
	current_weapon().enter()


## False while holstered (or putting it away).
func is_drawn() -> bool:
	var w = current_weapon()
	return w.state == BladeWeapon.State.READY or w.state == BladeWeapon.State.ENTERING


## After a respawn: every weapon loaded and ready (not just the equipped one).
func refill_all() -> void:
	for w in weapons:
		w.refill()


func toggle() -> void:
	var w = current_weapon()
	if w.state == BladeWeapon.State.READY or w.state == BladeWeapon.State.ENTERING:
		w.exit()
	elif _slot_allowed(current):
		w.enter()


## Whether our own player may use `slot` (the owner can lock weapons, moderation.gd).
## Other players' weapons just follow the network.
func _slot_allowed(slot: int) -> bool:
	if not is_multiplayer_authority() or not is_inside_tree():
		return true
	var mod := get_tree().root.get_node_or_null("Mod")
	return mod == null or mod.call("weapon_allowed", slot_id(slot))


## First allowed slot among the unlocked ones (-1 if every one is locked).
func _first_allowed(unlocked: int) -> int:
	for slot in unlocked:
		if _slot_allowed(slot):
			return slot
	return -1


func _physics_process(delta: float) -> void:
	# Other players' weapons follow the network (apply_net_state) instead of input.
	if not ball or not camera or not is_multiplayer_authority():
		return
	var controls := _controls_enabled()
	if not _slot_allowed(current):
		# The owner locked this weapon: switch to one that's allowed, or put it away.
		var other := _first_allowed(WeaponInfo.unlocked_count(get_tree()))
		if other >= 0:
			select(other)
		else:
			if is_drawn():
				current_weapon().exit()
			controls = false
	if controls and Input.is_action_just_pressed("toggle_staff_weapons") and WeaponInfo.has_staff_weapons(get_tree()):
		var settings := get_tree().root.get_node_or_null("Settings")
		if settings:
			var shown: bool = not settings.call("get_value", "show_staff_weapons")
			settings.call("set_value", "show_staff_weapons", shown)
			staff_weapons_toggled.emit(shown)
	var unlocked := WeaponInfo.unlocked_count(get_tree())
	if current >= unlocked:
		# Staff weapon no longer available (hidden with 0, or left the server).
		var fallback := _first_allowed(unlocked)
		if fallback >= 0:
			select(fallback)
	if controls:
		for slot in mini(SLOT_ACTIONS.size(), unlocked):
			if Input.is_action_just_pressed(SLOT_ACTIONS[slot]):
				select(slot)
				break
		if Input.is_action_just_pressed("toggle_weapon"):
			toggle()
		if Input.is_action_just_pressed("reload"):
			current_weapon().manual_reload()

	var hit := _raycast_crosshair()
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	# Skip the click that captures the mouse, so capturing doesn't also fire. A controller
	# doesn't need the mouse at all.
	var aiming := (captured and _was_captured) or InputSetup.using_pad
	var pressed := controls and aiming and Input.is_action_pressed("fire")
	current_weapon().handle_fire(pressed, hit, delta)
	_was_captured = captured


## What other players need to draw this weapon:
## [aim point, equipped slot, drawn?, charge (railgun/nova, so others see it building),
## peer id the railgun is locked onto (0 = none, so that player can be warned),
## reload state (so others see reloads and Scatter's heat; -1 = none)].
func get_net_state() -> Array:
	var w = current_weapon()
	var locked: int = w.call("locked_peer") if w.has_method("locked_peer") else 0
	return [aim_point, current, is_drawn(), w.get_net_charge(), locked, w.get_net_reload()]


## Applies another player's weapon state from the network.
func apply_net_state(aim: Vector3, slot: int, drawn: bool, charge := 0.0, reload := -1.0) -> void:
	aim_point = aim
	if slot != current:
		select(slot)
	var w = current_weapon()
	if drawn != is_drawn():
		toggle()
	w.apply_net_charge(charge)
	w.apply_net_reload(reload)


## No shooting while dead, stunned or behind the shield.
func _controls_enabled() -> bool:
	if ball.get("dead") or ball.call("is_blocking") or ball.call("is_staggered"):
		return false
	var net := get_tree().root.get_node_or_null("Net")
	return not (net and net.get("input_blocked"))


func _process(delta: float) -> void:
	if not ball:
		return
	var center := ball.get_global_transform_interpolated().origin
	# Other players have no camera here: fall back to the way the weapon already faces.
	var look := -camera.global_basis.z if camera else -global_basis.z
	var to_aim := aim_point - center
	var dist := to_aim.length()
	var dir := to_aim / dist if dist > 0.001 else look
	# Looking down at the floor, the crosshair ray lands right next to the ball, where
	# the direction to it swings wildly. Blend smoothly toward the camera's own look
	# direction as the aim point closes in (a hard switch here made the gun snap).
	var blended := look.lerp(dir, smoothstep(1.5, 6.0, dist))
	dir = blended.normalized() if blended.length() > 0.01 else look
	# Keep the blades upright. The camera's own up is never parallel to where it looks,
	# so it's a smooth reference at any pitch (straight "up" flips when aiming at the floor).
	var up := camera.global_basis.y if camera else _remote_up(dir, look)
	if absf(up.dot(dir)) > 0.99:
		up = Vector3.UP if absf(dir.y) < 0.9 else Vector3.FORWARD
	var goal := Basis.looking_at(dir, up)
	if not _has_aim_basis:
		_aim_basis = goal
		_has_aim_basis = true
	else:
		_aim_basis = _aim_basis.slerp(goal, 1.0 - exp(-TURN_RATE * delta)).orthonormalized()
	global_transform = Transform3D(_aim_basis, center)


## Up reference for other players' weapons (no camera): world up, or the heading when
## they aim nearly straight up or down.
func _remote_up(dir: Vector3, look: Vector3) -> Vector3:
	if absf(dir.y) < 0.95:
		return Vector3.UP
	var heading := Vector3(look.x, 0.0, look.z)
	if heading.length() < 0.01:
		heading = Vector3(global_basis.y.x, 0.0, global_basis.y.z)
	if heading.length() < 0.01:
		heading = Vector3.FORWARD
	return heading.normalized() * -signf(dir.y)


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

## Living lock targets whose aim point is on screen within `radius_px` of the center and
## no further than `max_distance` metres, closest to the center of the circle first.
## With `need_sight`, targets with the map in the way are skipped (so long-range locks
## can't find people hiding behind walls).
## Each entry: {"target", "point", "screen", "distance", "off_center"}.
func targets_on_screen(radius_px: float, max_distance := INF, need_sight := false) -> Array:
	var found := []
	if not camera:
		return found
	var center := camera.get_viewport().get_visible_rect().size / 2.0
	var ball_pos := ball.global_position
	for target in get_tree().get_nodes_in_group("lock_targets"):
		if not target.call("is_alive"):
			continue
		var p: Vector3 = target.call("get_aim_point")
		if camera.is_position_behind(p) or p.distance_to(ball_pos) > max_distance:
			continue
		var screen := camera.unproject_position(p)
		var off := screen.distance_to(center)
		if off > radius_px:
			continue
		if need_sight:
			var block := raycast(ball_pos, p)
			if not block.is_empty() and block["collider"] != target:
				continue
		found.append({"target": target, "point": p, "screen": screen, "distance": p.distance_to(ball_pos), "off_center": off})
	found.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["off_center"] < b["off_center"])
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
## (receive_impulse), everything else directly. `unblockable` hits go through players'
## shields and can't be parried (staff weapons).
func hit_object(collider: Object, damage: float, pos: Vector3, dir: Vector3, impulse: float, unblockable := false) -> void:
	if unblockable and collider.has_method("take_unblockable_hit"):
		collider.call("take_unblockable_hit", damage, pos, dir)
		report_damage(collider, damage, pos)
	elif collider.has_method("take_hit"):
		collider.call("take_hit", damage, pos, dir)
		report_damage(collider, damage, pos)
	if collider.has_method("receive_impulse"):
		collider.call("receive_impulse", dir * impulse)
		return
	var body := collider as RigidBody3D
	if body:
		# Resting bodies fall asleep and can ignore impulses until woken.
		body.sleeping = false
		body.apply_impulse(dir * impulse, pos - body.global_position)


## Local player only: show a floating number for damage we just dealt to `target`, with
## the distance. Shown as player damage, so practice tells you what a hit is worth online.
## Repeated hits on the same target add into one number.
func report_damage(target: Object, damage: float, pos: Vector3) -> void:
	if not is_multiplayer_authority() or damage <= 0.0 or not ball:
		return
	last_hit_id = slot_id(current)
	var amount := damage * BallScript.PVP_DAMAGE_SCALE
	var dist := ball.global_position.distance_to(pos)
	var existing = _numbers.get(target)
	if existing and is_instance_valid(existing) and existing.can_merge():
		existing.add(amount, dist)
		return
	var n := DamageNumber.new()
	n.total = amount
	n.distance = dist
	var anchor := pos
	if target is Node3D and target.has_method("get_aim_point"):
		anchor = target.call("get_aim_point")
	n.position = anchor
	ball.get_parent().add_child(n)
	_numbers[target] = n
	for key in _numbers.keys():
		if not is_instance_valid(_numbers[key]):
			_numbers.erase(key)


## Pushes the ball back, horizontally, away from `shot_dir` (measure it from the ball,
## not a blade tip: a tip can be past a point on the floor right in front of you, which
## pushed you forward). Shots aimed steeply down push less.
func recoil(shot_dir: Vector3, impulse: float) -> void:
	var d := shot_dir.normalized()
	var flat := Vector3(d.x, 0.0, d.z)
	if flat.length() > 0.01:
		ball.apply_central_impulse(-flat * impulse)


## Dash-strength kick on the ball, straight back along the shot (up and down included).
func knockback(shot_dir: Vector3, speed: float) -> void:
	if shot_dir.length() > 0.01 and ball.has_method("apply_knockback"):
		ball.call("apply_knockback", -shot_dir.normalized() * speed)


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


## A sound at `pos`; other players hear it too.
func play_sound(sound: String, pos: Vector3, volume_db := 0.0) -> void:
	Sfx.play_at(get_tree(), sound, pos, volume_db)
	if _broadcasting():
		_net_sound.rpc(sound, pos, volume_db)


@rpc("authority", "unreliable")
func _net_sound(sound: String, pos: Vector3, volume_db: float) -> void:
	Sfx.play_at(get_tree(), sound, pos, volume_db)


## A sound heard across the whole map (the orbital strike): flat rather than 3D, full
## volume near `pos` and fading to a distant rumble far away. Everyone hears it.
func play_sound_far(sound: String, pos: Vector3, volume_db := 0.0) -> void:
	_sound_far(sound, pos, volume_db)
	if _broadcasting():
		_net_sound_far.rpc(sound, pos, volume_db)


@rpc("authority", "reliable")
func _net_sound_far(sound: String, pos: Vector3, volume_db: float) -> void:
	_sound_far(sound, pos, volume_db)


func _sound_far(sound: String, pos: Vector3, volume_db: float) -> void:
	var cam := get_viewport().get_camera_3d()
	var dist := cam.global_position.distance_to(pos) if cam else 0.0
	Sfx.play_flat(get_tree(), sound, volume_db - clampf((dist - 40.0) / 30.0, 0.0, 22.0))


## Railgun bolt (scripts/weapons/rail_bolt.gd property names, plus "position" and
## "target_path"). Other players get a harmless copy that flies the same way.
func spawn_rail_bolt(props: Dictionary, visual_only := false) -> void:
	var bolt := RailBolt.new()
	for key in props:
		if key != "position" and key != "target_path":
			bolt.set(key, props[key])
	var path: String = props.get("target_path", "")
	if path != "":
		bolt.target = get_node_or_null(path)
	bolt.manager = self
	bolt.visual_only = visual_only
	bolt.position = props["position"]
	ball.get_parent().add_child(bolt)
	if not visual_only and _broadcasting():
		_net_rail_bolt.rpc(props)


@rpc("authority", "reliable")
func _net_rail_bolt(props: Dictionary) -> void:
	spawn_rail_bolt(props, true)


## Any weapon object (projectile, mine, pylon, wall, drone, decoy...): a script under
## scripts/weapons/ with `props` set on it ("position" places it, "target_path" becomes
## its `target`). Everyone else gets a copy with visual_only set, which looks and moves
## the same but hurts nothing: the owner's copy decides every hit, as with missiles.
func spawn_node(script_path: String, props: Dictionary, visual_only := false) -> Node3D:
	if not script_path.begins_with("res://scripts/weapons/") or not ResourceLoader.exists(script_path):
		return null
	var node: Node3D = load(script_path).new()
	for key in props:
		if key == "position" or key == "target_path":
			continue
		node.set(key, props[key])
	var path: String = props.get("target_path", "")
	if path != "" and "target" in node:
		node.set("target", get_node_or_null(path))
	node.set("manager", self)
	node.set("visual_only", visual_only)
	node.position = props.get("position", global_position)
	# Named the same on every computer, so despawn_node() can remove everyone's copy.
	if not props.has("node_name"):
		_spawn_count += 1
		props["node_name"] = "W%d_%d" % [get_multiplayer_authority(), _spawn_count]
	node.name = String(props["node_name"])
	ball.get_parent().add_child(node)
	if not visual_only and _broadcasting():
		_net_znode.rpc(script_path, props)
	return node


## Removes an object made with spawn_node (a mine going off, a replaced pylon), here
## and on everyone else's screen.
func despawn_node(node: Node) -> void:
	if not is_instance_valid(node):
		return
	var node_name := String(node.name)
	node.queue_free()
	if _broadcasting():
		_net_zdespawn.rpc(node_name)


## (Named to sort after the other RPCs.)
@rpc("authority", "reliable")
func _net_zdespawn(node_name: String) -> void:
	var node := ball.get_parent().get_node_or_null(node_name)
	if node:
		node.queue_free()


## (Named to sort after the other RPCs.)
@rpc("authority", "reliable")
func _net_znode(script_path: String, props: Dictionary) -> void:
	spawn_node(script_path, props, true)


## Puts a status on something we hit: "chill" (slowed; data.x = speed left, 0..1),
## "freeze" / "pin" / "cage" (held in place), "pull" (dragged toward data). Players
## go through the host (arena.gd); practice targets just react.
func apply_status(target: Object, kind: String, duration: float, data := Vector3.ZERO) -> void:
	if target and target.has_method("take_status"):
		target.call("take_status", kind, duration, data)


## A shot from `from` to `to` passed through walls: white ripples on every face it went
## in and out of (wall_ripple.gd). Everyone works out the crossings on their own map.
func spawn_ripples(from: Vector3, to: Vector3) -> void:
	WallRipple.pierce(ball.get_parent(), get_world_3d().direct_space_state, from, to, [ball.get_rid()])
	if _broadcasting():
		_net_zripples.rpc(from, to)


## (Named to sort after the other RPCs.)
@rpc("authority", "unreliable")
func _net_zripples(from: Vector3, to: Vector3) -> void:
	WallRipple.pierce(ball.get_parent(), get_world_3d().direct_space_state, from, to, [ball.get_rid()])


## The Tether hooked something (or let go): other players draw the same rope. `path` is
## the hooked body ("" for the static map) and `anchor` the hook point in its local space
## (world space on the map).
func broadcast_tether(weapon: Node, attached: bool, path: String, anchor: Vector3) -> void:
	if _broadcasting():
		_net_ztether.rpc(weapons.find(weapon), attached, path, anchor)


## (Named to sort after the other RPCs.)
@rpc("authority", "reliable")
func _net_ztether(slot: int, attached: bool, path: String, anchor: Vector3) -> void:
	if slot >= 0 and slot < weapons.size() and weapons[slot].has_method("apply_net_tether"):
		weapons[slot].call("apply_net_tether", attached, path, anchor)


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
