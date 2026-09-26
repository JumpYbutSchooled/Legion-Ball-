extends Node3D
## AI turrets (scripts/turret.gd), added by the arena at the map's turret_points().
## The host runs them: each picks the nearest living player it can see within RANGE,
## turns to them and fires a bolt every FIRE_INTERVAL. Fast-moving targets are harder
## to hit (the host rolls each shot against the target's speed), so keep moving. Hits go
## through the arena's normal damage (shields block them; kills count as deaths for the
## victim and nobody's kill). Players shoot turrets down (their hits are sent here to the
## host); a destroyed turret rebuilds after REBUILD seconds.
## Every computer builds the same turrets under the same names, so the RPCs line up.
## Offline (practice) they track and shoot but can't hurt you, like everything else there.

const TurretScript := preload("res://scripts/turret.gd")
const Beam := preload("res://scripts/dash_laser.gd")
const FlashLight := preload("res://scripts/flash_light.gd")
const Sfx := preload("res://scripts/sfx.gd")

const HEALTH := 120.0
const RANGE := 95.0
const FIRE_INTERVAL := 1.1
## Damage per hit, in player health.
const DAMAGE := 7.0
const REBUILD := 25.0
## Chance a shot lands on a still target, and the least it gets at high speed.
const ACCURACY := 0.9
const MIN_ACCURACY := 0.3
const COLOR := Color(1.0, 0.25, 0.15)

## Set by the arena before adding.
var points: Array[Vector3] = []

var _turrets: Array = []
# Host state, per turret.
var _hp: Array = []
var _target: Array = []
var _cooldown: Array = []
var _stun: Array = []
var _rebuild: Array = []
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	for i in points.size():
		var t := TurretScript.new()
		t.name = "T%d" % i
		t.index = i
		t.manager = self
		t.position = points[i]
		add_child(t)
		_turrets.append(t)
		_hp.append(HEALTH)
		_target.append(0)
		_cooldown.append(_rng.randf_range(0.5, FIRE_INTERVAL))
		_stun.append(0.0)
		_rebuild.append(0.0)


func _arena() -> Node:
	return get_parent()


func _is_host() -> bool:
	return multiplayer.is_server()


func _process(_delta: float) -> void:
	# Every computer turns the heads toward their current targets.
	var arena := _arena()
	for i in _turrets.size():
		var id: int = _target[i]
		var ball: Node3D = arena.call("player_ball", id) if id != 0 else null
		if ball and is_instance_valid(ball):
			_turrets[i].aim_at = ball.get_global_transform_interpolated().origin


func _physics_process(delta: float) -> void:
	if not _is_host():
		return
	var arena := _arena()
	if arena.get("match_done"):
		return
	for i in _turrets.size():
		var t: Node3D = _turrets[i]
		if not t.alive:
			_rebuild[i] -= delta
			if _rebuild[i] <= 0.0:
				_revived.rpc(i)
			continue
		_stun[i] = maxf(_stun[i] - delta, 0.0)
		var target := _pick_target(t)
		if target != _target[i]:
			_aim.rpc(i, target)
		_cooldown[i] = maxf(_cooldown[i] - delta, 0.0)
		if target != 0 and _cooldown[i] == 0.0 and _stun[i] == 0.0:
			_cooldown[i] = FIRE_INTERVAL
			_shoot(i, target)


## The nearest living player within range with nothing in the way.
func _pick_target(t: Node3D) -> int:
	var arena := _arena()
	var best := 0
	var best_dist := RANGE
	var from: Vector3 = t.call("head_position")
	var space := get_world_3d().direct_space_state
	for id in arena.get("alive"):
		if not arena.get("alive")[id]:
			continue
		var ball: Node3D = arena.call("player_ball", id)
		if not ball or not ball.visible:
			continue
		var d := from.distance_to(ball.global_position)
		if d >= best_dist:
			continue
		var query := PhysicsRayQueryParameters3D.create(from, ball.global_position)
		query.exclude = [t.get_rid()]
		var hit := space.intersect_ray(query)
		if not hit.is_empty() and hit["collider"] != ball:
			continue
		best = id
		best_dist = d
	return best


func _shoot(i: int, target: int) -> void:
	var arena := _arena()
	var ball: Node3D = arena.call("player_ball", target)
	if not ball:
		return
	var speed := 0.0
	var sync := ball.get_node_or_null("Sync")
	if sync:
		speed = (sync.call("net_velocity") as Vector3).length()
	var chance := clampf(ACCURACY - speed / 140.0, MIN_ACCURACY, ACCURACY)
	var hit := _rng.randf() < chance
	var point := ball.global_position
	if not hit:
		# A near miss, off to the side and past them.
		point += Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-0.3, 1), _rng.randf_range(-1, 1)).normalized() * _rng.randf_range(2.0, 4.0)
	_fired.rpc(i, point)
	if hit and arena.call("is_online"):
		arena.call("turret_hit", target, DAMAGE)


# --- Hits on turrets (any peer; forwarded to the host) ----------------------------------

func request_hit(i: int, amount: float) -> void:
	if _is_host():
		_host_hit(i, amount)
	else:
		_host_hit.rpc_id(1, i, amount)


func request_stagger(i: int, duration: float) -> void:
	if _is_host():
		_host_stun(i, duration)
	else:
		_host_stun.rpc_id(1, i, duration)


@rpc("any_peer", "reliable")
func _host_hit(i: int, amount: float) -> void:
	if not _is_host() or i < 0 or i >= _turrets.size() or not _turrets[i].alive:
		return
	_hp[i] -= clampf(amount, 0.0, 200.0)
	if _hp[i] <= 0.0:
		_destroyed.rpc(i)


@rpc("any_peer", "reliable")
func _host_stun(i: int, duration: float) -> void:
	if _is_host() and i >= 0 and i < _turrets.size():
		_stun[i] = maxf(_stun[i], minf(duration, 5.0))


# --- Results (every peer) -------------------------------------------------------------

@rpc("authority", "call_local", "reliable")
func _aim(i: int, target: int) -> void:
	if i >= 0 and i < _turrets.size():
		_target[i] = target


@rpc("authority", "call_local", "unreliable")
func _fired(i: int, point: Vector3) -> void:
	if i < 0 or i >= _turrets.size() or DisplayServer.get_name() == "headless":
		return
	var t: Node3D = _turrets[i]
	var from: Vector3 = t.call("muzzle")
	var beam := Beam.new()
	beam.length = from.distance_to(point)
	beam.width = 0.35
	beam.lifetime = 0.14
	beam.extend_time = 0.03
	beam.shoot_speed = 0.0
	beam.widest_at = 0.1
	beam.intensity = 10.0
	beam.color = COLOR
	add_child(beam)
	beam.fire(from, (point - from).normalized())
	var flash := FlashLight.new()
	flash.light_color = COLOR
	flash.light_energy = 18.0
	flash.omni_range = 10.0
	flash.lifetime = 0.1
	flash.position = from
	add_child(flash)
	Sfx.play_at(get_tree(), "zap", from, -3.0, 0.6)


@rpc("authority", "call_local", "reliable")
func _destroyed(i: int) -> void:
	if i < 0 or i >= _turrets.size():
		return
	var t: Node3D = _turrets[i]
	t.call("set_alive", false)
	_target[i] = 0
	_rebuild[i] = REBUILD
	Sfx.play_at(get_tree(), "shatter", t.global_position + Vector3.UP * 3.0, 2.0)
	Sfx.play_at(get_tree(), "boom", t.global_position, -2.0)
	if DisplayServer.get_name() != "headless":
		var burst := preload("res://scripts/shard_burst.gd").new()
		burst.color = COLOR
		burst.count = 24
		burst.speed = 10.0
		add_child(burst)
		burst.global_position = t.global_position + Vector3.UP * 3.0


@rpc("authority", "call_local", "reliable")
func _revived(i: int) -> void:
	if i < 0 or i >= _turrets.size():
		return
	_hp[i] = HEALTH
	_turrets[i].call("set_alive", true)
	Sfx.play_at(get_tree(), "unshatter", _turrets[i].global_position + Vector3.UP * 3.0)
