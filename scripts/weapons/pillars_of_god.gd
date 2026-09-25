extends "res://scripts/weapons/blade_weapon.gd"
## Slot 8 (owner only): Pillars of God, an orbital strike. Four huge blades.
## Locks like the railgun (any range) but through walls. Click to call the strike down
## on the locked target (or the crosshair point with no lock): a thin targeting beam
## drops from the sky and tracks them for strike_delay seconds, then a pillar of light
## slams down with a blast that kills anyone caught in it. Walls don't matter: it comes
## from above.
## Kills play the biggest impact frames in the game (impact_frames.gd).

## Seconds the targeting beam tracks before the strike lands.
@export var strike_delay := 0.9
@export var cooldown := 4.0
## Blast damage anywhere in the radius. x4 online is 200: a kill through any health.
@export var damage := 50.0
@export var blast_radius := 16.0
@export var blast_force := 90.0
@export var lock_radius_px := 70.0
## How high the pillar starts.
@export var sky_height := 350.0

var lock_target: Node3D = null
var lock_screen_pos := Vector2.ZERO

var _cooldown := 0.0
var _was_pressed := false
## Seconds left until the strike lands (-1 = no strike coming).
var _strike_timer := -1.0
var _strike_target: Node3D = null
var _strike_point := Vector3.ZERO
var _beam_timer := 0.0


func _build() -> void:
	var shape := {
		"arc_radius": 1.0,
		"tip": Vector3(0.4, 0.0, -4.6),
		"max_width": 0.4,
		"max_thickness": 0.3,
		"segments": 12,
	}
	for angle in [55.0, -35.0]:
		for side in [1.0, -1.0]:
			add_blade(side, angle, shape)


func handle_fire(pressed: bool, _hit: Dictionary, delta: float) -> void:
	var just_pressed := pressed and not _was_pressed
	_was_pressed = pressed
	_cooldown = maxf(_cooldown - delta, 0.0)
	_update_lock()
	if _strike_timer >= 0.0:
		_track_strike(delta)
	elif just_pressed and is_ready() and _cooldown == 0.0:
		_call_strike()


func _update_lock() -> void:
	lock_target = null
	if not is_ready() or not manager.camera:
		return
	# No sight check: the lock sees through walls.
	var found: Array = manager.targets_on_screen(lock_radius_px, INF, false)
	if not found.is_empty():
		lock_target = found[0]["target"]
		lock_screen_pos = found[0]["screen"]


func _update(_delta: float) -> void:
	if not is_ready():
		lock_target = null


## Peer id of the player locked onto, so they get the red warning (lock_warning.gd).
func locked_peer() -> int:
	var t := _strike_target if _strike_timer >= 0.0 else lock_target
	if t and is_instance_valid(t) and t.has_method("is_blocking"):
		return t.get_multiplayer_authority()
	return 0


func get_crosshair() -> Dictionary:
	var progress := 0.0
	if _strike_timer >= 0.0:
		progress = 1.0 - _strike_timer / strike_delay
	return {
		"kind": "rail",
		"radius": lock_radius_px,
		"circle": true,
		"reloading": _cooldown > 0.0 and _strike_timer < 0.0,
		"charge": progress,
		"locked": lock_target != null and is_instance_valid(lock_target),
		"lock_pos": lock_screen_pos,
	}


func _call_strike() -> void:
	_strike_target = lock_target
	_strike_point = lock_target.call("get_aim_point") if lock_target else manager.aim_point
	_strike_timer = strike_delay
	_beam_timer = 0.0
	for i in _blades.size():
		kick(i)
	manager.spawn_light(global_position, 60.0, 10.0, 0.3, color)
	manager.play_sound("rail", _strike_point, 6.0)
	manager.shake(0.4)


## Targeting beam follows the target until the strike lands.
func _track_strike(delta: float) -> void:
	if _strike_target and is_instance_valid(_strike_target) and _strike_target.call("is_alive"):
		_strike_point = _strike_target.call("get_aim_point")
	_strike_timer -= delta
	_beam_timer -= delta
	if _beam_timer <= 0.0:
		_beam_timer = 0.08
		var k := 1.0 - _strike_timer / strike_delay
		manager.spawn_beam(_strike_point + Vector3.UP * sky_height, Vector3.DOWN, sky_height, lerpf(0.15, 0.6, k), 0.1, lerpf(4.0, 14.0, k), color)
	if _strike_timer <= 0.0:
		_strike()


func _strike() -> void:
	_strike_timer = -1.0
	_cooldown = cooldown
	var ground := _strike_point
	var down: Dictionary = manager.raycast(_strike_point + Vector3.UP * 2.0, _strike_point + Vector3.DOWN * 50.0)
	if not down.is_empty():
		ground = down["position"]
	# The pillar: a huge beam from the sky, with a hot white core.
	manager.spawn_beam(ground + Vector3.UP * sky_height, Vector3.DOWN, sky_height, 7.0, 0.7, 30.0, color)
	manager.spawn_beam(ground + Vector3.UP * sky_height, Vector3.DOWN, sky_height, 2.5, 0.5, 60.0, Color.WHITE)
	manager.spawn_warp(ground, 0.6, blast_radius * 1.4)
	manager.spawn_explosion({
		"position": ground + Vector3.UP * 0.5,
		"color": color,
		"radius": blast_radius,
		"damage": damage,
		"full_damage": true,
		"force": blast_force,
		"spark_count": 600,
		"spark_speed": 45.0,
		"chunk_count": 60,
		"light_energy": 900.0,
		"warp_strength": 0.6,
		"flat_sparks": true,
		"sound": "impact_boom",
	})
	manager.shake(1.0)
	_strike_target = null
