extends "res://scripts/weapons/blade_weapon.gd"
## Shared base for the loadout weapons added in 1.1: fire input broken into pressed /
## just pressed / released, a cooldown, a charge, the "simple" crosshair, and helpers
## for what most of them do (hitscan with optional piercing, things near a point,
## statuses, spawning networked objects, set bonuses).
## A weapon overrides _build() (its blades) and _fire(pressed, just, released, hit, delta).

@export var cooldown := 1.0
@export var crosshair_shape := "ring"
@export var crosshair_radius := 10.0
## Lock-on (longer-range weapons): the target nearest the crosshair within
## lock_radius_px (and lock_range metres, in sight unless lock_through_walls) becomes the
## aim: target_point() and aim_dir() follow it, and shots can home on it (lock_path()).
## A small circle like the Gatling's (16 px), not the Railgun's big one: each weapon
## varies it a little.
@export var lock_on := false
@export var lock_radius_px := 16.0
@export var lock_range := INF
@export var lock_through_walls := false

var lock_target: Node3D = null
var lock_screen := Vector2.ZERO

var charge := 0.0
var _was_pressed := false


func handle_fire(pressed: bool, hit: Dictionary, delta: float) -> void:
	var just := pressed and not _was_pressed
	var released := _was_pressed and not pressed
	_was_pressed = pressed
	if not is_ready():
		charge = 0.0
		lock_target = null
		return
	if lock_on:
		_update_lock()
	_fire(pressed, just, released, hit, delta)


func _update_lock() -> void:
	lock_target = null
	if not manager.camera:
		return
	var found: Array = manager.targets_on_screen(lock_radius_px, lock_range, not lock_through_walls)
	if not found.is_empty():
		lock_target = found[0]["target"]
		lock_screen = found[0]["screen"]


## Where to shoot: the locked target, or wherever the crosshair lands.
func target_point() -> Vector3:
	if lock_target and is_instance_valid(lock_target) and lock_target.call("is_alive"):
		return lock_target.call("get_aim_point")
	return manager.aim_point


## The locked target's node path, for homing shots ("" = none).
func lock_path() -> String:
	return String(lock_target.get_path()) if lock_target and is_instance_valid(lock_target) else ""


## Overridden by each weapon.
func _fire(_pressed: bool, _just: bool, _released: bool, _hit: Dictionary, _delta: float) -> void:
	pass


func can_fire() -> bool:
	return _cooldown <= 0.0


func start_cooldown(seconds := -1.0) -> void:
	_cooldown = cooldown if seconds < 0.0 else seconds


func get_crosshair() -> Dictionary:
	var info := {
		"kind": "simple",
		"shape": crosshair_shape,
		"radius": crosshair_radius,
		"ready": can_fire(),
		"cooldown": 1.0 - _cooldown / cooldown if cooldown > 0.0 else 1.0,
		"charge": charge,
	}
	if lock_on:
		info["lock_ring"] = lock_radius_px
	if lock_target and is_instance_valid(lock_target):
		info["locked"] = true
		info["lock_pos"] = lock_screen
	_crosshair_extra(info)
	return info


## Add "meter", "count", "locked"/"lock_pos" to the crosshair.
func _crosshair_extra(_info: Dictionary) -> void:
	pass


func get_net_charge() -> float:
	return charge


func apply_net_charge(c: float) -> void:
	charge = c


func refill() -> void:
	_cooldown = 0.0
	charge = 0.0


# --- Helpers ---------------------------------------------------------------------------

func ball() -> RigidBody3D:
	return manager.ball


## Tip of blade `i`, in world space.
func tip(i := 0) -> Vector3:
	return _blades[i].to_global(_blades[i].call("get_tip"))


## From the ball toward the target (the lock, or the crosshair's aim point).
func aim_dir() -> Vector3:
	var d: Vector3 = target_point() - ball().global_position
	return d.normalized() if d.length() > 0.01 else -global_basis.z


## Where the camera looks.
func look_dir() -> Vector3:
	return -manager.camera.global_basis.z if manager.camera else aim_dir()


## Hitscan from `from` along `dir`. Hits the first thing (or, with `pierce`, every player
## and target along the line until a wall). Deals damage and a shove to each; returns
## the hits ({position, normal, collider}) and where the line stopped ("end").
func hitscan(from: Vector3, dir: Vector3, length: float, damage: float, impulse: float, pierce := false) -> Dictionary:
	var hits: Array = []
	var start := from
	var to := from + dir * length
	var skip: Array[RID] = [ball().get_rid()]
	var end := to
	for i in 8:
		var query := PhysicsRayQueryParameters3D.create(start, to)
		query.exclude = skip
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty():
			break
		var collider: Object = hit["collider"]
		hits.append(hit)
		manager.hit_object(collider, damage, hit["position"], dir, impulse)
		if not pierce or not collider.has_method("take_hit"):
			end = hit["position"]
			break
		skip.append(hit["rid"])
		start = hit["position"]
	return {"hits": hits, "end": end}


## Living lock targets (other players, practice targets, turrets) within `radius` of `pos`.
func targets_near(pos: Vector3, radius: float) -> Array:
	var out: Array = []
	for t in get_tree().get_nodes_in_group("lock_targets"):
		if t.call("is_alive") and (t.call("get_aim_point") as Vector3).distance_to(pos) <= radius:
			out.append(t)
	return out


func status(target: Object, kind: String, duration: float, data := Vector3.ZERO) -> void:
	manager.apply_status(target, kind, duration, data)


func spawn(script_path: String, props: Dictionary) -> Node3D:
	return manager.spawn_node(script_path, props)


## True if this weapon's owner has the set bonus of combo group `group`.
func perk(group: String) -> bool:
	var scene := get_tree().current_scene
	if scene and scene.has_method("perks_of"):
		return (scene.call("perks_of", manager.get_multiplayer_authority()) as Array).has(group)
	return false


## The owner's deployables last this much longer (FORTRESS set bonus).
func deploy_time(seconds: float) -> float:
	return seconds * (1.3 if perk("fortress") else 1.0)


## Muzzle flash at `pos` going `dir`: a spike, a light and a warp.
func flash_at(pos: Vector3, dir: Vector3, size := 1.0) -> void:
	manager.spawn_beam(pos, dir, 1.2 * size, 0.6 * size, 0.07, 16.0, color)
	manager.spawn_light(pos, 30.0 * size, 8.0, 0.08, color)
	manager.spawn_warp(pos, 0.08 * size, 1.2 * size)


## A tracer from `from` to `to`.
func tracer(from: Vector3, to: Vector3, width := 0.1, intensity := 5.0) -> void:
	var d := to - from
	if d.length() > 0.01:
		manager.spawn_beam(from, d.normalized(), d.length(), width, 0.1, intensity, color)
