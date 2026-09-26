extends "res://scripts/weapons/blade_weapon.gd"
## Slot 8 (owner only): Pillars of God, an orbital strike. Four huge blades.
## Locks like the railgun (any range) but through walls. Click to call the strike down
## on the locked target (or the crosshair point with no lock).
## Wind-up (strike_delay): a targeting beam drops from the sky and tracks them, thickening,
## while a ring of light closes in on them and the charge sound (heard across the map)
## screams up. Impact: a three-layer pillar of light, a blast that kills anyone caught in
## it, two shockwaves rolling out after it, a ring of lesser pillars, and the biggest
## sound and impact frames in the game, for everyone nearby, not just on a kill.
## Walls don't matter: it comes from above. Unparryable: the blast goes through shields.

## Seconds the targeting beam tracks before the strike lands.
@export var strike_delay := 1.6
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

var _was_pressed := false
## Seconds left until the strike lands (-1 = no strike coming).
var _strike_timer := -1.0
var _strike_target: Node3D = null
var _strike_point := Vector3.ZERO
var _beam_timer := 0.0
var _ring_timer := 0.0

## Beams in the closing ring round the target during the wind-up.
const RING_POINTS := 8


func _build() -> void:
	var shape := {
		"arc_radius": 1.0,
		"tip": Vector3(0.4, 0.0, -4.6),
		"max_width": 0.4,
		"max_thickness": 0.3,
		"segments": 12,
	}
	# A cross of light: one arm straight up, one straight down, one out each side.
	# (Placed one by one: a mirrored pair at 90 degrees would put both arms on top.)
	add_blade(1.0, 0.0, shape)
	add_blade(-1.0, 0.0, shape)
	add_blade(1.0, 90.0, shape)
	add_blade(1.0, -90.0, shape)


func handle_fire(pressed: bool, _hit: Dictionary, delta: float) -> void:
	var just_pressed := pressed and not _was_pressed
	_was_pressed = pressed
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
		return t.call("player_id") if t.has_method("player_id") else t.get_multiplayer_authority()
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
	_ring_timer = 0.0
	for i in _blades.size():
		kick(i)
	manager.spawn_light(global_position, 60.0, 10.0, 0.3, color)
	manager.spawn_warp(global_position, 0.25, 4.0)
	manager.play_sound_far("orbital_charge", _strike_point, 4.0)
	manager.shake(0.5)


## The wind-up: the beam follows the target, thickening, and a ring of light closes in.
func _track_strike(delta: float) -> void:
	if _strike_target and is_instance_valid(_strike_target) and _strike_target.call("is_alive"):
		_strike_point = _strike_target.call("get_aim_point")
	_strike_timer -= delta
	_beam_timer -= delta
	_ring_timer -= delta
	var k := clampf(1.0 - _strike_timer / strike_delay, 0.0, 1.0)
	var sky := _strike_point + Vector3.UP * sky_height
	if _beam_timer <= 0.0:
		_beam_timer = 0.08
		# White and flickering in the last moment.
		var final := _strike_timer < 0.25
		manager.spawn_beam(sky, Vector3.DOWN, sky_height, lerpf(0.15, 1.2, k * k), 0.1, lerpf(4.0, 24.0, k), Color.WHITE if final and randf() < 0.5 else color)
		manager.shake(0.04 + k * 0.2)
	if _ring_timer <= 0.0:
		_ring_timer = 0.12
		var radius := lerpf(22.0, 3.0, k)
		for i in RING_POINTS:
			var a := TAU * i / RING_POINTS + k * 2.0
			var p := _strike_point + Vector3(cos(a), 0.0, sin(a)) * radius
			manager.spawn_beam(p + Vector3.UP * 7.0, Vector3.DOWN, 7.5, 0.3, 0.14, 12.0, color)
		manager.spawn_light(_strike_point, lerpf(20.0, 140.0, k), radius + 6.0, 0.14, color)
	if _strike_timer <= 0.0:
		_strike()


func _strike() -> void:
	_strike_timer = -1.0
	_cooldown = cooldown
	var ground := _strike_point
	var down: Dictionary = manager.raycast(_strike_point + Vector3.UP * 2.0, _strike_point + Vector3.DOWN * 50.0)
	if not down.is_empty():
		ground = down["position"]
	var sky := ground + Vector3.UP * sky_height
	# The pillar, three layers: a wide flash, the thick coloured column, a white-hot core.
	manager.spawn_beam(sky, Vector3.DOWN, sky_height, 16.0, 0.45, 22.0, color)
	manager.spawn_beam(sky, Vector3.DOWN, sky_height, 8.0, 1.6, 35.0, color)
	manager.spawn_beam(sky, Vector3.DOWN, sky_height, 3.0, 1.3, 70.0, Color.WHITE)
	manager.spawn_warp(ground, 0.9, blast_radius * 2.2)
	manager.spawn_light(ground + Vector3.UP * 4.0, 3000.0, 140.0, 0.8, color)
	manager.play_sound_far("orbital_impact", ground, 8.0)
	manager.spawn_explosion({
		"position": ground + Vector3.UP * 0.5,
		"color": color,
		"radius": blast_radius,
		"damage": damage,
		"full_damage": true,
		"unblockable": true,
		"force": blast_force,
		"spark_count": 900,
		"spark_speed": 55.0,
		"chunk_count": 120,
		"light_energy": 1500.0,
		"warp_strength": 0.8,
		"flat_sparks": true,
		"sound": "",
		# Everyone near enough gets impact frames, kill or not.
		"impact_frame_range": 120.0,
		"impact_frame_id": "pillars_of_god",
	})
	manager.shake(1.6)
	_strike_target = null
	# Aftermath: a ring of lesser pillars, then two shockwaves rolling outward.
	var tree := get_tree()
	var m: Node = manager
	var c := color
	tree.create_timer(0.18).timeout.connect(func() -> void:
		for i in 8:
			var a := TAU * i / 8.0
			var p := ground + Vector3(cos(a), 0.0, sin(a)) * 12.0
			m.call("spawn_beam", p + Vector3.UP * 60.0, Vector3.DOWN, 60.0, 1.4, 0.6, 30.0, c))
	for wave in [[0.14, 26.0], [0.32, 40.0]]:
		tree.create_timer(wave[0]).timeout.connect(func() -> void:
			m.call("spawn_explosion", {
				"position": ground + Vector3.UP * 0.5,
				"color": c,
				"radius": wave[1],
				"damage": 0.0,
				"force": 0.0,
				"spark_count": 300,
				"spark_speed": 60.0,
				"chunk_count": 30,
				"light_energy": 500.0,
				"warp_strength": 0.5,
				"flat_sparks": true,
				"sound": "",
			}))


func refill() -> void:
	_cooldown = 0.0
